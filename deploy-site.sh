#!/bin/zsh
# Upload site/ to https://clausage.ai over explicit FTPS, then check the pages load.
#
#   ./deploy-site.sh
#
# Uses the FTP account rooted at the clausage.ai document root (shared with release.sh, which uploads to updates/).
# It lives outside git, in .claude/release.env:
#   FTP_HOST=...               (shared with release.sh: the name on the FTP server's TLS certificate)
#   SITE_FTP_USER=...
#   SITE_KEYCHAIN_SERVICE=...  (login Keychain item holding that account's password)
set -euo pipefail
cd "$(dirname "$0")"

SITE_BASE="https://clausage.ai"
[[ -f .claude/release.env ]] || { echo "error: .claude/release.env is missing (see .claude/release.md)" >&2; exit 1; }
source .claude/release.env

die() { echo "error: $*" >&2; exit 1; }

[[ -n "${SITE_FTP_USER:-}" && -n "${SITE_KEYCHAIN_SERVICE:-}" ]] || die "SITE_FTP_USER / SITE_KEYCHAIN_SERVICE not set in .claude/release.env"
FTP_PASS=$(security find-generic-password -s "$SITE_KEYCHAIN_SERVICE" -a "$SITE_FTP_USER" -w 2>/dev/null) \
  || die "FTP password not in Keychain (service $SITE_KEYCHAIN_SERVICE, account $SITE_FTP_USER)"

# Stage a copy so the HTML can carry cache-busting versions: the host caches assets for a week, so every page asks
# for site.css?v=<content hash> and a changed stylesheet is fetched right away.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R site/. "$STAGE/"
CSS_V=$(shasum -a 256 site/assets/site.css | cut -c1-10)
find "$STAGE" -name '*.html' -exec perl -pi -e "s{/assets/site\.css(\?v=[0-9a-f]+)?\"}{/assets/site.css?v=$CSS_V\"}g" {} +

ftp_put() {
  printf 'user = "%s:%s"\n' "$SITE_FTP_USER" "$FTP_PASS" |
    curl -sS --fail -m 120 --ssl-reqd --ftp-create-dirs -K - -T "$STAGE/$1" "ftp://$FTP_HOST/$1"
}
for f in $(cd "$STAGE" && find . -type f ! -name .DS_Store | sed 's|^\./||' | sort); do
  ftp_put "$f"
  echo "uploaded $f"
done
unset FTP_PASS

for p in / /privacy/ /acknowledgements/; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$SITE_BASE$p")
  [[ "$code" == 200 ]] || die "$SITE_BASE$p returned HTTP $code"
done
echo "Published: $SITE_BASE"
