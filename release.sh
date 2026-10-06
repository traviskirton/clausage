#!/bin/zsh
# Build, notarize, zip, sign and publish a Claude Usage update to https://updates.postfl.com/claude-usage/
#
#   ./release.sh 1.2.0               bump to 1.2.0 (build number +1), build, sign, upload
#   ./release.sh                     rebuild/publish the current version as-is
#   ./release.sh 1.2.0 --no-upload   do everything except upload (output in release/)
#
# Needs: SPARKLE_KEY_FILE (path to the Sparkle private key, set in ~/.zshrc), .claude/release.env, and the FTP
# password in the Keychain. Uploads over explicit FTPS with full certificate checking.
set -euo pipefail
cd "$(dirname "$0")"

FEED_BASE="https://updates.postfl.com/claude-usage"
# Upload host, FTP account and Keychain service live outside git, in .claude/release.env:
#   FTP_HOST=...   (the name on the FTP server's TLS certificate)
#   FTP_USER=...
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
xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -configuration Release -derivedDataPath build \
  -archivePath build/archive/ClaudeUsage.xcarchive -allowProvisioningUpdates -quiet archive
xcodebuild -exportArchive -archivePath build/archive/ClaudeUsage.xcarchive -exportPath build/archive/upload \
  -exportOptionsPlist tools/ExportOptionsUpload.plist -allowProvisioningUpdates >/dev/null 2>&1 \
  || die "uploading to Apple's notary service failed"
echo "Submitted for notarization; waiting for Apple…"
APP="build/archive/notarized/Claude Usage.app"
for i in {1..45}; do
  out=$(xcodebuild -exportNotarizedApp -archivePath build/archive/ClaudeUsage.xcarchive \
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
ZIP="ClaudeUsage-$VER-$BUILD.zip"
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

# 4. Upload: zip first, appcast last, so the feed never points at a missing file.
ftp_put() {
  printf 'user = "%s:%s"\n' "$FTP_USER" "$FTP_PASS" |
    curl -sS --fail -m 300 --ssl-reqd -K - -T "$1" "ftp://$FTP_HOST/$(basename "$1")"
}
ftp_put "release/$ZIP"
ftp_put "release/appcast.xml"
unset FTP_PASS

# 5. Verify what the public sees
for f in "$ZIP" appcast.xml; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$FEED_BASE/$f")
  [[ "$code" == 200 ]] || die "$FEED_BASE/$f returned HTTP $code"
done
echo "Published: $FEED_BASE/appcast.xml"

# 6. Record the release in git: commit the version bump and tag it.
git add project.yml
git diff --cached --quiet || git commit -qm "Release $VER (build $BUILD)"
git tag -a "release-$VER" -m "Release $VER (build $BUILD)"
echo "Tagged release-$VER on $(git branch --show-current)."
echo "Next: fast-forward main to this branch, then branch for the next version."
