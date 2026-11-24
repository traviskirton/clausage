#!/bin/sh
# Install the clausage MCP for Claude Code. Needs: python3, the `claude` CLI, a Claude subscription plan.
#   curl -fsSL https://clausage.ai/mcp/install.sh | sh             install, or update (safe to re-run)
#   curl -fsSL https://clausage.ai/mcp/install.sh | sh -s uninstall
#   sh install.sh               install from a checkout (safe to re-run)
#   sh install.sh --statusline  also add the statusline shim (fallback source; edits settings.json)
#   sh install.sh uninstall  remove and restore your previous statusline
set -e
DIR="$HOME/.clausage-mcp"
SRC=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
BASE="${CLAUSAGE_MCP_BASE:-https://clausage.ai/mcp}"  # where `curl | sh` fetches the other files (deploy-site.sh puts them there)
SETTINGS="$HOME/.claude/settings.json"

command -v python3 >/dev/null || { echo "clausage: python3 is required"; exit 1; }
command -v claude >/dev/null || { echo "clausage: the claude CLI is required"; exit 1; }

statusline() {  # $1 = install | uninstall; edits only the statusLine key of settings.json
python3 - "$1" "$SETTINGS" "$DIR" <<'EOF'
import json, os, sys
mode, path, d = sys.argv[1:]
shim = os.path.join(d, "statusline.sh")
s = json.load(open(path)) if os.path.exists(path) else {}
cur = (s.get("statusLine") or {}).get("command", "")
prev = os.path.join(d, "previous-statusline")
if mode == "install":
    if cur and cur != shim:
        open(prev, "w").write(cur)  # keep the user's statusline running behind the shim
    s["statusLine"] = {"type": "command", "command": shim}
else:
    if cur == shim:
        old = open(prev).read().strip() if os.path.exists(prev) else ""
        if old: s["statusLine"] = {"type": "command", "command": old}
        else: s.pop("statusLine", None)
os.makedirs(os.path.dirname(path), exist_ok=True)
if os.path.exists(path):
    open(path + ".clausage-backup", "w").write(open(path).read())
json.dump(s, open(path, "w"), indent=2)
EOF
}

if [ "$1" = "uninstall" ]; then
  claude mcp remove -s user clausage >/dev/null 2>&1 || true
  statusline uninstall
  rm -rf "$DIR"
  echo "clausage: removed. Restart Claude Code."
  exit 0
fi

mkdir -p "$DIR"
if [ -f "$SRC/server.py" ] && [ -f "$SRC/statusline.sh" ]; then
  cp -f "$SRC/server.py" "$SRC/statusline.sh" "$DIR/"
else  # piped from curl: no files beside the script, so fetch them
  for f in server.py statusline.sh; do
    curl -fsSL "$BASE/$f" -o "$DIR/$f.tmp" || { rm -f "$DIR/$f.tmp"; echo "clausage: download of $f failed"; exit 1; }
    mv -f "$DIR/$f.tmp" "$DIR/$f"
  done
fi
chmod +x "$DIR/server.py" "$DIR/statusline.sh"
[ "$1" = "--statusline" ] && statusline install
claude mcp remove -s user clausage >/dev/null 2>&1 || true
claude mcp add -s user clausage -- python3 "$DIR/server.py" >/dev/null
echo "clausage: installed. Restart Claude Code (or reload the VS Code window)."
python3 "$DIR/server.py" --check || echo "clausage: no source yet; it starts working once you're signed in to Claude Code with a subscription."
[ -s "$DIR/previous-statusline" ] && echo "clausage: your statusline still runs: $(cat "$DIR/previous-statusline")"
exit 0
