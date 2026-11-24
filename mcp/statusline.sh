#!/bin/sh
# clausage statusline shim: saves Claude Code's rate limits for the clausage MCP,
# then hands the same input to your previous statusline (if any) so it keeps working.
DIR="$HOME/.clausage-mcp"
input=$(cat)
printf '%s' "$input" | python3 -c '
import json, sys, time
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit()
out = {"at": time.time(), "rate_limits": d.get("rate_limits"), "model": (d.get("model") or {}).get("id")}
p = sys.argv[1]
open(p + ".tmp", "w").write(json.dumps(out))
import os; os.replace(p + ".tmp", p)
' "$DIR/usage-latest.json" 2>/dev/null
if [ -s "$DIR/previous-statusline" ]; then
  printf '%s' "$input" | sh -c "$(cat "$DIR/previous-statusline")"
else
  printf '%s' "$input" | python3 -c '
import json, sys
r = (json.load(sys.stdin).get("rate_limits") or {})
f = [f"{k}:{round(r[w][\"used_percentage\"])}%" for k, w in (("5h", "five_hour"), ("7d", "seven_day")) if (r.get(w) or {}).get("used_percentage") is not None]
print(" ".join(f) or "clausage")' 2>/dev/null || echo clausage
fi
