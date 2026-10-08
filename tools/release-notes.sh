#!/bin/zsh
# Draft and approve the release notes for a Mac version: release-notes/<version>.md.
#
#   tools/release-notes.sh 0.0.9                 draft from the commits since the last release tag (Claude writes it)
#   tools/release-notes.sh 0.0.6 --from A --to B draft from a specific range (backfilling older versions)
#   tools/release-notes.sh 0.0.9 --approve       mark the draft approved (release.sh refuses unapproved notes)
#
# A draft starts with a `<!-- draft -->` line. In a terminal the script shows the draft and asks to approve, edit
# or cancel; otherwise it prints the draft and leaves it unapproved. Commit the approved file before releasing.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { echo "error: $*" >&2; exit 1; }
MARK="<!-- draft -->"

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die "usage: tools/release-notes.sh <version> [--from <ref>] [--to <ref>] [--approve]"
shift
FROM=""; TO=""; APPROVE=0
while (( $# )); do
  case "$1" in
    --from) FROM="$2"; shift 2 ;;
    --to) TO="$2"; shift 2 ;;
    --approve) APPROVE=1; shift ;;
    *) die "unknown argument '$1'" ;;
  esac
done
FILE="release-notes/$VERSION.md"

approve() {
  [[ -f "$FILE" ]] || die "$FILE doesn't exist; draft it first"
  python3 - "$FILE" "$MARK" <<'PY'
import sys
p, mark = sys.argv[1], sys.argv[2]
lines = [l for l in open(p).read().split("\n") if l.strip() != mark]
open(p, "w").write("\n".join(lines).strip("\n") + "\n")
PY
  echo "Approved $FILE. Commit it before running release.sh."
}

if (( APPROVE )); then approve; exit 0; fi

# Range: the last release tag before this version, up to this version's tag (or HEAD while it's unreleased).
[[ -n "$TO" ]] || { git rev-parse -q --verify "refs/tags/release-$VERSION" >/dev/null && TO="release-$VERSION" || TO=HEAD; }
if [[ -z "$FROM" ]]; then
  FROM=$(git describe --tags --abbrev=0 --match 'release-*' --exclude "release-$VERSION" "$TO" 2>/dev/null) \
    || die "no earlier release tag; pass --from"
fi

# Commits that can change the Mac app, minus housekeeping, with the files each touched (so iPhone-only and
# website-only work can be told apart).
COMMITS=$(git log --no-merges --reverse --format='@@%s%n%b' --name-only "$FROM..$TO" | python3 -c '
import re, sys
mac = ("App/", "Shared/", "SharedUI/", "Widget/", "Resources/", "project.yml", "design/clausage-icon.icon")
skip = re.compile(r"^(Start \d|Snapshot notes|Release \d|Add development report|Co-Authored-By)")
out = []
for block in sys.stdin.read().split("@@")[1:]:
    lines = [l for l in block.split("\n")]
    subject = lines[0].strip()
    files = [l for l in lines[1:] if re.match(r"^[\w./-]+$", l) and ("/" in l or "." in l)]
    body = [l for l in lines[1:] if l not in files and l.strip() and not l.startswith("Co-Authored-By")]
    if skip.match(subject) or not any(f.startswith(mac) for f in files):
        continue
    out.append("- " + subject + ("\n  " + " ".join(body) if body else "") + "\n  files: " + ", ".join(files[:12]))
print("\n".join(out))
')
[[ -n "$COMMITS" ]] || die "no Mac app changes between $FROM and $TO"

PROMPT=$(cat <<EOF
Write the release notes for Clausage $VERSION for Mac. Clausage is a macOS menu bar app (plus a desktop widget) that
shows Claude plan usage limits. Below are the commits since the previous release, with the files each touched.

Rules:
- Only what a Mac user notices: the menu bar icon, the popover, Settings, the widget, notifications, updates, sign-in.
  Skip iPhone-only changes (files only under iOS/), the website, tests, build tooling and internal refactors.
- Output plain Markdown only, nothing else: one short headline sentence on its own line, a blank line, then 2 to 7
  bullets ("- "). Each bullet is one or two short sentences, at most 30 words. Say "you". No version numbers, commit
  hashes, file names or code identifiers. Name settings the way the app labels them.
- House voice throughout: Clausage counts usage like tally marks, and its copy plays on food and plates ("Plate's
  clean", "Leftovers likely", "seconds aren't served until Tuesday", "Nothing on the plate yet", "One tally down").
  Put a light pun or turn of phrase in the headline and in most bullets, but never at the cost of saying clearly
  what changed.
- If nothing user-facing changed, write one headline and a single bullet about fixes and polish.

Commits:
$COMMITS
EOF
)

mkdir -p release-notes
echo "Drafting $FILE from $FROM..$TO with Claude…" >&2
DRAFT=$(print -r -- "$PROMPT" | claude -p "Follow the instructions in the input exactly and reply with only the release notes." 2>/dev/null) \
  || die "claude -p failed"
[[ -n "$DRAFT" ]] || die "Claude returned nothing"
printf '%s\n%s\n' "$MARK" "$DRAFT" > "$FILE"

echo "---- $FILE"
grep -v -- "$MARK" "$FILE"
echo "----"

if [[ -t 0 && -t 1 ]]; then
  while true; do
    read "choice?Approve, edit or cancel? [a/e/c] "
    case "$choice" in
      a|A) approve; break ;;
      e|E) ${EDITOR:-nano} "$FILE"; echo "---- $FILE"; grep -v -- "$MARK" "$FILE"; echo "----" ;;
      c|C|"") echo "Left as a draft: $FILE"; break ;;
    esac
  done
else
  echo "Draft only (not approved). Approve with: tools/release-notes.sh $VERSION --approve"
fi
