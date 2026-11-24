#!/usr/bin/env python3
"""clausage MCP: Claude plan usage for Claude Code. Stdio JSON-RPC, stdlib only.

Sources, first fresh one wins:
  oauth      GET api.anthropic.com/api/oauth/usage with Claude Code's own login (read locally, never logged)
  app        the Clausage Mac app's snapshot (App Group plist)
  statusline ~/.clausage-mcp/usage-latest.json, written by the optional statusline shim
`python3 server.py --check` prints the source used and the percentages.
"""
import json, os, plistlib, subprocess, sys, time, urllib.error, urllib.request
from datetime import datetime

VERSION = "0.2.0"
HOME = os.path.expanduser(os.environ.get("CLAUSAGE_HOME", "~/.clausage-mcp"))
STATUSLINE_CACHE = os.path.expanduser(os.environ.get("CLAUSAGE_CACHE", os.path.join(HOME, "usage-latest.json")))
OAUTH_CACHE = os.path.join(HOME, "oauth-cache.json")
JOBS_LOG = os.path.join(HOME, "jobs.jsonl")  # one line per check_job, to calibrate job sizes later
API_BASE = os.environ.get("CLAUSAGE_API_BASE", "https://api.anthropic.com")
APP_PLIST = os.path.expanduser(os.environ.get("CLAUSAGE_APP_PLIST",
    "~/Library/Group Containers/G3GED29J33.com.postfl.clausage/Library/Preferences/G3GED29J33.com.postfl.clausage.plist"))
TTL, BACKOFF_429, FRESH, STALE = 60, 300, 15 * 60, 10 * 60

# window key -> (display name, length in seconds)
WINDOWS = {"five_hour": ("session", 5 * 3600), "seven_day": ("week", 7 * 86400),
           "seven_day_opus": ("week_opus", 7 * 86400), "seven_day_sonnet": ("week_sonnet", 7 * 86400)}
SIZES = {"small": 2, "medium": 10, "large": 30, "overnight": 60}  # % of a 5h session
WEEK_PER_SESSION = float(os.environ.get("CLAUSAGE_WEEK_PER_SESSION", "0.2"))  # 1% session ~ 0.2% week
WARN, STOP = 85, 95


class SourceError(Exception):
    """Message must never contain a token."""


# ---------- helpers ----------

def _ts(v):
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return v / 1000 if v > 1e12 else float(v)
    try:
        return datetime.fromisoformat(str(v).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def _clock(t):
    return datetime.fromtimestamp(t).strftime("%a %-I:%M %p")


def _dur(s):
    s = max(0, int(s)); h, m = divmod(s // 60, 60)
    return f"{h}h{m:02d}m" if h < 48 else f"{h // 24}d{h % 24}h"


def _write_private(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, path)


def _load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


# ---------- source: oauth ----------

def read_credentials():
    """Claude Code's OAuth login -> access token, or raise SourceError (no secrets in messages)."""
    raw = None
    path = os.environ.get("CLAUSAGE_CREDENTIALS_FILE")
    if not path and sys.platform == "darwin":
        try:
            r = subprocess.run(["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
                               capture_output=True, text=True, timeout=3)
            raw = r.stdout if r.returncode == 0 else None
        except (OSError, subprocess.TimeoutExpired):
            raw = None
    if raw is None:
        base = os.environ.get("CLAUDE_CONFIG_DIR", os.path.expanduser("~/.claude"))
        try:
            with open(path or os.path.join(base, ".credentials.json")) as f:
                raw = f.read()
        except OSError:
            raise SourceError("no Claude Code login found (sign in to Claude Code with a subscription)")
    try:
        o = json.loads(raw).get("claudeAiOauth") or {}
    except (ValueError, AttributeError):
        raise SourceError("Claude Code login is unreadable")
    tok = o.get("accessToken")
    if not tok:
        raise SourceError("Claude Code login has no OAuth token (API-key users have no plan limits)")
    if "user:profile" not in (o.get("scopes") or []):
        raise SourceError("Claude Code login lacks the user:profile scope; run /login again")
    exp = _ts(o.get("expiresAt"))
    if exp and exp - time.time() < 60:
        raise SourceError("Claude Code login token expired; it refreshes when Claude Code is next used")
    return tok


def fetch_oauth():
    tok = read_credentials()
    req = urllib.request.Request(API_BASE + "/api/oauth/usage", headers={
        "Authorization": "Bearer " + tok, "anthropic-beta": "oauth-2025-04-20",
        "Content-Type": "application/json", "User-Agent": f"clausage-mcp/{VERSION}"})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            body = json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise SourceError(f"usage endpoint returned HTTP {e.code}") from None
    except (urllib.error.URLError, OSError, TimeoutError):
        raise SourceError("usage endpoint unreachable") from None
    except ValueError:
        raise SourceError("usage endpoint returned an unreadable body") from None
    if not isinstance(body, dict):
        raise SourceError("usage endpoint returned an unexpected body")
    return parse_usage(body)


def _scoped_key(model):
    return "seven_day_" + ("".join(c if c.isalnum() else "_" for c in (model or "scoped").lower()).strip("_") or "scoped")


def parse_usage(body):
    """Both response shapes: the newer `limits` array (kind/percent/scope.model) and the `five_hour`/`seven_day*` keys."""
    limits = {}
    for l in body.get("limits") or []:
        if not isinstance(l, dict) or l.get("percent") is None:
            continue
        kind = l.get("kind")
        model = ((l.get("scope") or {}).get("model") or {}).get("display_name") if isinstance(l.get("scope"), dict) else None
        key = {"session": "five_hour", "weekly_all": "seven_day"}.get(kind) or (_scoped_key(model) if kind == "weekly_scoped" else None)
        if key and key not in limits:
            limits[key] = {"used_percentage": float(l["percent"]), "resets_at": l.get("resets_at")}
    for key, w in body.items():
        if (key == "five_hour" or key.startswith("seven_day")) and key not in limits and isinstance(w, dict) \
                and w.get("utilization") is not None and "breakdown" not in key:
            limits[key] = {"used_percentage": float(w["utilization"]), "resets_at": w.get("resets_at")}
    return limits


def src_oauth():
    c = _load(OAUTH_CACHE) or {}
    now = time.time()
    if c.get("backoff_until", 0) > now:
        if c.get("rate_limits") and now - c.get("at", 0) < FRESH:
            return c
        raise SourceError("usage endpoint rate-limited; backing off")
    if c.get("rate_limits") and now - c.get("at", 0) < TTL:
        return c
    try:
        limits = fetch_oauth()
    except SourceError as e:
        if "HTTP 429" in str(e):
            _write_private(OAUTH_CACHE, {**c, "backoff_until": now + BACKOFF_429})
        raise
    if not limits:
        raise SourceError("no plan limits on this account")
    c = {"at": now, "source": "oauth", "rate_limits": limits}
    _write_private(OAUTH_CACHE, c)
    return c


# ---------- source: Clausage app ----------

APP_KINDS = {"session": "five_hour", "weekly_all": "seven_day"}


def src_app():
    try:
        with open(APP_PLIST, "rb") as f:
            raw = plistlib.load(f).get("snapshot")
        s = json.loads(raw)
    except FileNotFoundError:
        raise SourceError("Clausage app not installed")
    except Exception:
        raise SourceError("Clausage app snapshot unreadable")
    if s.get("sample") or s.get("cleared") or not s.get("connected"):
        raise SourceError("Clausage app is not signed in")
    at = _ts(s.get("updated")) or 0
    if time.time() - at > FRESH:
        raise SourceError("Clausage app snapshot is older than 15 minutes")
    limits = {}
    for l in s.get("limits") or []:
        k = APP_KINDS.get(l.get("kind"))
        if l.get("kind") == "weekly_scoped":
            title = (l.get("shortTitle") or l.get("title") or "").split("·")[-1].strip().lower()
            k = "seven_day_" + (title or "scoped")
        if k and l.get("percent") is not None and k not in limits:
            limits[k] = {"used_percentage": float(l["percent"]), "resets_at": l.get("resetsAt")}
    if not limits:
        raise SourceError("Clausage app snapshot has no limits")
    return {"at": at, "source": "app", "rate_limits": limits}


# ---------- source: statusline ----------

def src_statusline():
    c = _load(STATUSLINE_CACHE)
    if not c:
        raise SourceError("no statusline cache (statusline shim not installed, or not run yet)")
    rl = c.get("rate_limits") or {}
    if not rl:
        raise SourceError("statusline cache has no rate limits")
    if time.time() - c.get("at", 0) > FRESH:
        raise SourceError("statusline cache is older than 15 minutes")
    return {"at": c.get("at", 0), "source": "statusline", "rate_limits": rl}


SOURCES = [("oauth", src_oauth), ("app", src_app), ("statusline", src_statusline)]


# ---------- tools ----------

def snapshot():
    errors = {}
    for name, fn in SOURCES:
        try:
            data = fn()
            break
        except SourceError as e:
            errors[name] = str(e)
        except Exception as e:  # never let a source crash the server; type name only, no message
            errors[name] = f"failed ({type(e).__name__})"
    else:
        return {"error": "No usage source worked.", "sources": errors}
    now = time.time(); at = data.get("at", now)
    out = {"source": data["source"], "as_of": _clock(at), "age_seconds": int(now - at), "limits": {}}
    if now - at > STALE:
        out["stale"] = True
    for key, w in data["rate_limits"].items():
        if not isinstance(w, dict) or w.get("used_percentage") is None:
            continue
        name, length = WINDOWS.get(key, (key.replace("seven_day_", "week_"), 7 * 86400))
        used = float(w["used_percentage"]); reset = _ts(w.get("resets_at"))
        lim = {"used_percent": round(used, 1), "left_percent": round(max(0, 100 - used), 1)}
        if reset and reset > now:
            elapsed = max(60, length - (reset - now))
            pace = used / elapsed
            lim.update(resets_at=_clock(reset), resets_in=_dur(reset - now),
                       even_pace_percent=round(min(100, 100 * elapsed / length), 1))
            if 0 < pace and used < 100:
                runout = now + (100 - used) / pace
                if runout < reset:
                    lim["runs_out_at"] = f"~{_clock(runout)} (before reset)"
        lim["status"] = "stop" if used >= STOP else "warn" if used >= WARN else "ok"
        out["limits"][name] = lim
    if not out["limits"]:
        return {"error": "Usage source had no limits.", "sources": errors}
    if errors:
        out["skipped_sources"] = errors
    return out


RANK = ["go", "caution", "wait", "stop"]
ADVICE = {"go": "Fits in every limit.",
          "caution": "Fits, but leaves little headroom. Consider a smaller model or splitting the job.",
          "wait": "Won't fit this session. Start after the session reset, or split it.",
          "stop": "Won't fit this week. Shrink it, use a cheaper model, or wait for the weekly reset."}


def check_job(args):
    snap = snapshot()
    if "error" in snap:
        return snap
    est = args.get("estimate_session_percent")
    if est is None:
        est = SIZES.get(args.get("size") or "medium", 10)
    est = float(est)
    verdict, notes, costs = "go", [], {}
    for name, lim in snap["limits"].items():
        cost = est if name == "session" else est * WEEK_PER_SESSION
        costs[name] = round(cost, 1)
        after = lim["used_percent"] + cost
        lim["after_job_percent"] = round(after, 1)
        if after >= 100:
            v = "wait" if name == "session" else "stop"
            notes.append(f"{name}: job (~{cost:.0f}%) won't fit in {lim['left_percent']:.0f}% left"
                         + (f"; resets {lim['resets_at']} (in {lim['resets_in']})" if lim.get("resets_at") else ""))
        elif after >= WARN:
            v = "caution"
            notes.append(f"{name}: would end at ~{after:.0f}%")
        else:
            continue
        verdict = max(verdict, v, key=RANK.index)
    log_job(args, est, verdict, snap)
    return {"verdict": verdict, "advice": ADVICE[verdict], "notes": notes, "assumed_cost": costs, **snap}


def log_job(args, est, verdict, snap):
    """Append the check to jobs.jsonl (mode 600). Percentages and ids only; never fails the call."""
    try:
        rec = {"at": round(time.time()), "session_id": os.environ.get("CLAUDE_CODE_SESSION_ID"),
               "project": os.environ.get("CLAUDE_PROJECT_DIR"), "size": args.get("size"),
               "estimate_session_percent": est, "description": str(args.get("description") or "")[:300],
               "verdict": verdict, "source": snap["source"], "age_seconds": snap["age_seconds"],
               "used": {k: v["used_percent"] for k, v in snap["limits"].items()},
               "resets_in": {k: v.get("resets_in") for k, v in snap["limits"].items()}}
        os.makedirs(HOME, exist_ok=True)
        fd = os.open(JOBS_LOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(fd, "a") as f:
            f.write(json.dumps(rec) + "\n")
    except Exception:
        pass


TOOLS = [
    {"name": "get_usage",
     "description": "Current Claude plan usage: 5-hour session, weekly, and per-model weekly limits: percent used/left, reset time, even-pace mark, projected runout. Call before planning long work.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "check_job",
     "description": "Before starting a big job, check it fits in the remaining session and weekly limits. Returns verdict go/caution/wait/stop with reasons. Give estimate_session_percent (share of a 5h session the job will use) or size small(2%)/medium(10%)/large(30%)/overnight(60%).",
     "inputSchema": {"type": "object", "properties": {
         "estimate_session_percent": {"type": "number"},
         "size": {"type": "string", "enum": list(SIZES)},
         "description": {"type": "string", "description": "What the job is (for the record)."}}}},
]

INSTRUCTIONS = ("clausage reports the user's Claude plan limits (5-hour session and weekly). "
                "Before starting big work (subagents, workflows, /loop, long renders or builds, overnight runs, "
                "multi-file refactors) call check_job with a size or estimate and tell the user the verdict if it is "
                "not 'go'. Call get_usage when the user asks how much is left or what fits before a reset.")


def handle(msg):
    m, p = msg.get("method"), msg.get("params") or {}
    if m == "initialize":
        return {"protocolVersion": p.get("protocolVersion", "2025-06-18"), "capabilities": {"tools": {}},
                "serverInfo": {"name": "clausage", "version": VERSION}, "instructions": INSTRUCTIONS}
    if m == "tools/list":
        return {"tools": TOOLS}
    if m == "tools/call":
        name, args = p.get("name"), p.get("arguments") or {}
        res = snapshot() if name == "get_usage" else check_job(args) if name == "check_job" else {"error": f"unknown tool {name}"}
        return {"content": [{"type": "text", "text": json.dumps(res, indent=1)}], "isError": "error" in res}
    if m == "ping":
        return {}
    raise KeyError(m)


def main():
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}}) + "\n")
            sys.stdout.flush(); continue
        if "id" not in msg:
            continue  # notification
        try:
            reply = {"jsonrpc": "2.0", "id": msg["id"], "result": handle(msg)}
        except KeyError as e:
            reply = {"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32601, "message": f"Method not found: {e}"}}
        sys.stdout.write(json.dumps(reply) + "\n"); sys.stdout.flush()


if __name__ == "__main__":
    if "--check" in sys.argv:
        s = snapshot()
        if "error" in s:
            print("clausage: " + s["error"]); [print(f"  {k}: {v}") for k, v in s["sources"].items()]; sys.exit(1)
        print(f"clausage: OK via {s['source']}: " + ", ".join(f"{k} {v['used_percent']:.0f}%" for k, v in s["limits"].items()))
    else:
        main()
