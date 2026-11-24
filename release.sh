#!/bin/zsh
# Build, notarize, zip, sign and publish a Clausage update to https://clausage.ai/updates/, and archive the iPhone app
# (same build) for Xcode's Organizer, to upload to App Store Connect from there.
#
#   ./release.sh 1.2.0               bump to 1.2.0 (build number +1), build, sign, upload
#   ./release.sh                     rebuild/publish the current version as-is
#   ./release.sh 1.2.0 --no-upload   do everything except upload (output in release/)
#   ./release.sh 1.2.0 --keep-installed   leave /Applications/Clausage.app alone
#
# Release notes come first: tools/release-notes.sh <version> drafts release-notes/<version>.md, you approve it, and it's
# committed. This script refuses a version without approved notes. Each update's headline sentence goes in the appcast
# (Sparkle's description); the details go on clausage.ai/releases/, which the appcast links to.
#
# Each release doubles as an update test: before building, the previous release from release/ is installed in
# /Applications and opened, so once this one is live, quitting and relaunching Clausage updates it through Sparkle.
#
# Needs: SPARKLE_KEY_FILE (path to the Sparkle private key, set in ~/.zshrc), .claude/release.env, and both FTP
# passwords in the Keychain. Uploads over explicit FTPS with full certificate checking.
set -euo pipefail
cd "$(dirname "$0")"

FEED_BASE="https://clausage.ai/updates"
# Copies released as "Claude Usage" (0.0.1–0.0.3) only ever check this feed, so it gets the same appcast.
LEGACY_FEED_BASE="https://updates.postfl.com/claude-usage"
NOTES_PAGE="https://clausage.ai/releases/"
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

UPLOAD=1; VERSION=""; INSTALL_PREVIOUS=1
for a in "$@"; do
  case "$a" in
    --no-upload) UPLOAD=0 ;;
    --keep-installed) INSTALL_PREVIOUS=0 ;;
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

# The build is the working tree and only project.yml gets committed, so anything else uncommitted would ship unrecorded.
git diff --quiet HEAD -- . ':!project.yml' || die "uncommitted changes; commit them first"

# Approved, committed release notes for this version.
NOTES_VER="${VERSION:-$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)}"
NOTES="release-notes/$NOTES_VER.md"
[[ -f "$NOTES" ]] || die "no release notes for $NOTES_VER: run tools/release-notes.sh $NOTES_VER, approve them, commit"
grep -q -- "<!-- draft -->" "$NOTES" && die "$NOTES is a draft: approve it (tools/release-notes.sh $NOTES_VER --approve) and commit"
git ls-files --error-unmatch "$NOTES" >/dev/null 2>&1 || die "$NOTES isn't committed"

# The MCP reads this app's snapshot, so its tests gate the release too.
MCP_LOG=$(cd mcp && python3 -W ignore -m unittest discover -s tests 2>&1) || { echo "$MCP_LOG" >&2; die "mcp tests failed"; }
echo "mcp tests: OK"

# 0. Install and open the previous release, so this one arrives as a real Sparkle update.
if (( UPLOAD && INSTALL_PREVIOUS )); then
  PREV=$(ls release/Clausage-*.zip 2>/dev/null | sort -V | tail -1)
  [[ -n "$PREV" ]] || die "no earlier release in release/ to install (use --keep-installed)"
  pkill -x Clausage 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Clausage.app
  ditto -x -k "$PREV" /Applications/
  open /Applications/Clausage.app
  echo "Installed and opened $(basename "$PREV" .zip) for the update test."
fi

# 1. Version bump (Sparkle compares the build number, so it must always increase). The branch's first commit already
# sets the build to the last release's + 1; this only raises it if that was skipped.
if [[ -n "$VERSION" ]]; then
  LAST_TAG=$(git tag -l 'release-*' --sort=-v:refname | head -1)
  LAST_BUILD=$(git show "$LAST_TAG:project.yml" 2>/dev/null | sed -n 's/^ *CURRENT_PROJECT_VERSION: "\([0-9]*\)"/\1/p' | head -1)
  python3 - "$VERSION" "${LAST_BUILD:-0}" <<'PY'
import re, sys
p = "project.yml"; s = open(p).read()
last = int(sys.argv[2])
s = re.sub(r'(MARKETING_VERSION: )"[^"]*"', r'\1"%s"' % sys.argv[1], s)
s = re.sub(r'(CURRENT_PROJECT_VERSION: )"(\d+)"', lambda m: '%s"%d"' % (m.group(1), max(int(m.group(2)), last + 1)), s)
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

# 2b. The iPhone app, same build, archived into Xcode's Archives folder so it shows in Window → Organizer, ready to
# upload to App Store Connect from there. Before anything is published, so a failure here stops the release.
IOS_ARCHIVE="$HOME/Library/Developer/Xcode/Archives/$(date +%F)/ClausageiOS-$BUILD.xcarchive"
rm -rf "$IOS_ARCHIVE"
xcodebuild -project Clausage.xcodeproj -scheme ClausageiOS -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build -archivePath "$IOS_ARCHIVE" -allowProvisioningUpdates -quiet archive \
  || die "archiving the iPhone app failed"
IOS_VER=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$IOS_ARCHIVE/Info.plist")
echo "Archived Clausage for iPhone $IOS_VER ($BUILD): upload it from Xcode → Window → Organizer."

# 3. Zip + appcast (release/ keeps earlier zips so the appcast lists history)
mkdir -p release
[[ -e "release/$ZIP" ]] && die "release/$ZIP already exists. Bump the version."
ditto -c -k --sequesterRsrc --keepParent "$APP" "release/$ZIP"
# site/releases/index.html, and release/Clausage-<version>-<build>.html (the headline) beside each zip for the appcast.
python3 tools/releases-page.py --sparkle release >/dev/null
"$GEN_APPCAST" --ed-key-file "$SPARKLE_KEY_FILE" --maximum-deltas 0 --download-url-prefix "$FEED_BASE/" \
  --full-release-notes-url "$NOTES_PAGE" release/ >/dev/null
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
# The releases page (with the site's cache-busting stylesheet version, as deploy-site.sh does).
NOTES_STAGE=$(mktemp -d)
perl -pe "s{/assets/site\.css(\?v=[0-9a-f]+)?\"}{/assets/site.css?v=$(shasum -a 256 site/assets/site.css | cut -c1-10)\"}g" \
  site/releases/index.html > "$NOTES_STAGE/index.html"
ftp_put "$SITE_FTP_USER" "$SITE_FTP_PASS" "$NOTES_STAGE/index.html" "releases/index.html"
rm -rf "$NOTES_STAGE"
ftp_put "$SITE_FTP_USER" "$SITE_FTP_PASS" "release/appcast.xml" "updates/appcast.xml"
ftp_put "$FTP_USER" "$FTP_PASS" "release/appcast.xml" "appcast.xml"
unset SITE_FTP_PASS FTP_PASS

# 5. Verify what the public sees
for url in "$FEED_BASE/$ZIP" "$FEED_BASE/Clausage.zip" "$NOTES_PAGE" "$FEED_BASE/appcast.xml" "$LEGACY_FEED_BASE/appcast.xml"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  [[ "$code" == 200 ]] || die "$url returned HTTP $code"
done
echo "Published: $FEED_BASE/appcast.xml (and the legacy feed)"

# 6. Record the release in git: commit the version bump and tag it.
git add project.yml site/releases/index.html
git diff --cached --quiet || git commit -qm "Release $VER (build $BUILD)"
git tag -a "release-$VER" -m "Release $VER (build $BUILD)"
echo "Tagged release-$VER on $(git branch --show-current)."
echo "Next: fast-forward main to this branch, then branch for the next version."
if (( INSTALL_PREVIOUS )); then
  echo "Update test: quit and relaunch Clausage; about 8 seconds later it finds $VER (build $BUILD)."
fi
