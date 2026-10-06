#!/bin/zsh
# Upload site/ to https://clausage.ai over explicit FTPS, then check the pages load.
#
#   ./deploy-site.sh
#
# Uses its own FTP account, restricted to the clausage.ai document root. It lives outside git, in .claude/release.env:
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

ftp_put() {
  printf 'user = "%s:%s"\n' "$SITE_FTP_USER" "$FTP_PASS" |
    curl -sS --fail -m 120 --ssl-reqd --ftp-create-dirs -K - -T "site/$1" "ftp://$FTP_HOST/$1"
}
for f in $(cd site && find . -type f ! -name .DS_Store | sed 's|^\./||' | sort); do
  ftp_put "$f"
  echo "uploaded $f"
done
unset FTP_PASS

for p in / /privacy/ /acknowledgements/; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$SITE_BASE$p")
  [[ "$code" == 200 ]] || die "$SITE_BASE$p returned HTTP $code"
done
echo "Published: $SITE_BASE"
