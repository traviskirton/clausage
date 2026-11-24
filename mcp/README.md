# clausage MCP

Lets Claude Code see your Claude plan limits (5-hour session, weekly, per-model weekly) and warn you before it starts a job that won't fit. Works in the terminal and in the VS Code extension.

## Install

```sh
git clone https://github.com/traviskirton/clausage && sh clausage/mcp/install.sh
```

Restart Claude Code (or reload the VS Code window). Needs `python3` and Claude Code signed in with a Pro/Max plan. Nothing else to install.

- `sh install.sh --statusline` also adds a statusline shim as an extra source (it keeps your current statusline running).
- `sh install.sh uninstall` removes everything and puts your old statusline back.
- `python3 ~/.clausage-mcp/server.py --check` shows which source works and your percentages.

## What Claude gets

| Tool | What it does |
|---|---|
| `get_usage` | % used and left, reset time, even-pace mark, projected runout, per limit |
| `get_history` | past weeks from the Clausage app's saved readings: final % (or so far), peak, % used each day, newest first |
| `check_job` | `go` / `caution` / `wait` / `stop` for a job of a given size (`small`, `medium`, `large`, `overnight`, or a % of a session) |

The server tells Claude to call `check_job` before big work (subagents, workflows, `/loop`, overnight runs), so you don't need to ask.

## Where the numbers come from

First source that works wins:

1. **Claude's usage endpoint**, using the login Claude Code already has (macOS Keychain, or `~/.claude/.credentials.json`). Results are cached for 60 seconds.
2. **The Clausage Mac app**, if installed and signed in.
3. **The statusline shim**, if you installed it with `--statusline`.

`get_history` needs the Clausage Mac app: it reads the hourly weekly readings the app saves (the last two weeks, more if Settings → Keep history is longer).

## Privacy

Your login token is read on your machine and sent only to `api.anthropic.com`. It is never written to disk, logged or shown to Claude; the cache holds percentages only (file mode 600). The server never refreshes your login, so it can't sign Claude Code out. The usage endpoint is undocumented and may change; if it does, the other sources take over.

## Job log

Every `check_job` call appends one line to `~/.clausage-mcp/jobs.jsonl` (mode 600): time, Claude Code session ID and project, size or estimate, description, verdict and the usage percentages at that moment. No tokens. It's there to calibrate job sizes against what jobs really cost.

## Settings

- `CLAUSAGE_WEEK_PER_SESSION` (default `0.2`): how much of the week 1% of a session costs.

## Tests

```sh
python3 -m unittest discover -s tests -v
```

24 tests, no network beyond localhost, no real credentials: parsing for each source (both API response shapes), HTTP failures (401/429/500/timeout/garbage) falling through, credential edge cases, a token-leak check on every failure path, the stdio protocol, the verdict table, and the installer in a fake HOME.

Not supported yet: a custom `CLAUDE_CONFIG_DIR` on macOS (Claude Code uses a different Keychain item name for it).
