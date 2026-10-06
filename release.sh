#!/bin/zsh
# Build, notarize, zip, sign and publish a Clausage update to https://clausage.ai/updates/
#
#   ./release.sh 1.2.0               bump to 1.2.0 (build number +1), build, sign, upload
#   ./release.sh                     rebuild/publish the current version as-is
#   ./release.sh 1.2.0 --no-upload   do everything except upload (output in release/)
#
# Needs: SPARKLE_KEY_FILE (path to the Sparkle private key, set in ~/.zshrc), .claude/release.env, and both FTP
# passwords in the Keychain. Uploads over explicit FTPS with full certificate checking.
set -euo pipefail
cd "$(dirname "$0")"

FEED_BASE="https://clausage.ai/updates"
# Copies released as "Claude Usage" (0.0.1–0.0.3) only ever check this feed, so it gets the same appcast.
LEGACY_FEED_BASE="https://updates.postfl.com/claude-usage"
# Upload host, FTP accounts and Keychain services live outside git, in .claude/release.env:
#   FTP_HOST=...               (the name on the FTP server's TLS certificate)
#   SITE_FTP_USER=...          (rooted at the clausage.ai document root; shared with deploy-site.sh)
#   SITE_KEYCHAIN_SERVICE=...
#   FTP_USER=...               (the legacy feed's account, rooted at updates.postfl.com/claude-usage)
#   KEYCHAIN_SERVICE=...
[[ -f .claude/release.env ]] || { echo "error: .claude/release.env is missing (see .claude/release.md)" >&2; exit 1; }
source .claude/release.env
GEN_APPCAST="build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"

die() { echo "error: $*" >&2; exit 1; }

UPLOAD=1; VERSION=""
for a in "$@"; do
  case "$a" in
    --no-upload) UPLOAD=0 ;;
    [0-9]*.[0-9]*) [[ "$a" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die "bad version '$a'"; VERSION="$a" ;;
    *) die "unknown argument '$a'" ;;
  esac
done

[[ -s "${SPARKLE_KEY_FILE:-}" ]] || die "SPARKLE_KEY_FILE is not set or the file is missing (open a new shell?)"
[[ -x "$GEN_APPCAST" ]] || die "Sparkle tools not found. Run ./build.sh once to fetch packages."

if [[ -n "$VERSION" ]] && git rev-parse -q --verify "refs/tags/release-$VERSION" >/dev/null; then
  die "tag release-$VERSION already exists"
fi

if (( UPLOAD )); then
  [[ -n "${SITE_FTP_USER:-}" && -n "${SITE_KEYCHAIN_SERVICE:-}" ]] || die "SITE_FTP_USER / SITE_KEYCHAIN_SERVICE not set in .claude/release.env"
  SITE_FTP_PASS=$(security find-generic-password -s "$SITE_KEYCHAIN_SERVICE" -a "$SITE_FTP_USER" -w 2>/dev/null) \
    || die "FTP password not in Keychain (service $SITE_KEYCHAIN_SERVICE, account $SITE_FTP_USER)"
  FTP_PASS=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$FTP_USER" -w 2>/dev/null) \
    || die "FTP password not in Keychain (service $KEYCHAIN_SERVICE, account $FTP_USER)"
fi

# 1. Version bump (Sparkle compares the build number, so it must always increase).
if [[ -n "$VERSION" ]]; then
  python3 - "$VERSION" <<'PY'
import re, sys
p = "project.yml"; s = open(p).read()
s = re.sub(r'(MARKETING_VERSION: )"[^"]*"', r'\1"%s"' % sys.argv[1], s)
s = re.sub(r'(CURRENT_PROJECT_VERSION: )"(\d+)"', lambda m: '%s"%d"' % (m.group(1), int(m.group(2)) + 1), s)
open(p, "w").write(s)
PY
fi

# 2. Archive, sign with Developer ID, notarize (via Xcode's Apple login), staple
rm -rf build/archive
xcodegen generate --quiet
xcodebuild -project Clausage.xcodeproj -scheme Clausage -configuration Release -derivedDataPath build \
  -archivePath build/archive/Clausage.xcarchive -allowProvisioningUpdates -quiet archive
xcodebuild -exportArchive -archivePath build/archive/Clausage.xcarchive -exportPath build/archive/upload \
  -exportOptionsPlist tools/ExportOptionsUpload.plist -allowProvisioningUpdates >/dev/null 2>&1 \
  || die "uploading to Apple's notary service failed"
echo "Submitted for notarization; waiting for Apple…"
APP="build/archive/notarized/Clausage.app"
for i in {1..45}; do
  out=$(xcodebuild -exportNotarizedApp -archivePath build/archive/Clausage.xcarchive \
        -exportPath build/archive/notarized 2>&1 || true)
  [[ -d "$APP" ]] && break
  [[ "$out" == *"processing"* ]] || die "notarization failed: $(echo "$out" | grep -E 'error' | head -3)"
  sleep 20
done
[[ -d "$APP" ]] || die "notarization did not finish in time; re-run later"
xcrun stapler validate "$APP" >/dev/null || die "notarization ticket missing"
spctl -a -t exec "$APP" || die "Gatekeeper rejects the app"
PLIST="$APP/Contents/Info.plist"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
ZIP="Clausage-$VER-$BUILD.zip"
echo "Releasing $VER (build $BUILD), notarized"

# 3. Zip + appcast (release/ keeps earlier zips so the appcast lists history)
mkdir -p release
[[ -e "release/$ZIP" ]] && die "release/$ZIP already exists. Bump the version."
ditto -c -k --sequesterRsrc --keepParent "$APP" "release/$ZIP"
"$GEN_APPCAST" --ed-key-file "$SPARKLE_KEY_FILE" --maximum-deltas 0 --download-url-prefix "$FEED_BASE/" release/ >/dev/null
[[ -s release/appcast.xml ]] || die "appcast.xml was not generated"
grep -q "sparkle:edSignature" release/appcast.xml || die "appcast has no signature"
echo "Signed. release/$ZIP + release/appcast.xml ready."

(( UPLOAD )) || { echo "--no-upload: skipping upload."; exit 0; }

# 4. Upload: zip first, appcasts last, so neither feed ever points at a missing file.
#    ftp_put <user> <password> <local file> <remote path>
ftp_put() {
  printf 'user = "%s:%s"\n' "$1" "$2" |
    curl -sS --fail -m 300 --ssl-reqd --ftp-create-dirs -K - -T "$3" "ftp://$FTP_HOST/$4"
}
ftp_put "$SITE_FTP_USER" "$SITE_FTP_PASS" "release/$ZIP" "updates/$ZIP"
ftp_put "$SITE_FTP_USER" "$SITE_FTP_PASS" "release/$ZIP" "updates/Clausage.zip"   # stable "latest" link (README, site)
ftp_put "$SITE_FTP_USER" "$SITE_FTP_PASS" "release/appcast.xml" "updates/appcast.xml"
ftp_put "$FTP_USER" "$FTP_PASS" "release/appcast.xml" "appcast.xml"
unset SITE_FTP_PASS FTP_PASS

# 5. Verify what the public sees
for url in "$FEED_BASE/$ZIP" "$FEED_BASE/Clausage.zip" "$FEED_BASE/appcast.xml" "$LEGACY_FEED_BASE/appcast.xml"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  [[ "$code" == 200 ]] || die "$url returned HTTP $code"
done
echo "Published: $FEED_BASE/appcast.xml (and the legacy feed)"

# 6. Record the release in git: commit the version bump and tag it.
git add project.yml
git diff --cached --quiet || git commit -qm "Release $VER (build $BUILD)"
git tag -a "release-$VER" -m "Release $VER (build $BUILD)"
echo "Tagged release-$VER on $(git branch --show-current)."
echo "Next: fast-forward main to this branch, then branch for the next version."
