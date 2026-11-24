# To do

Open work for Clausage, newest decisions first. Bugs live in [BUGS.md](BUGS.md); marketing's 3-week plan lives in `~/Dev/clausage-mkt/strategy/phase-2-relaunch.md`. Tick items off here as they land.

## Now

- [x] **0% label on the weekly chart** ([BUGS.md](BUGS.md)): fixed in `ab23346`, merged into `0.0.13`.

## Ship 0.0.13 (Mac + iPhone)

- [x] Release notes for 0.0.13 approved (`release-notes/0.0.13.md`).
- [ ] `./release.sh 0.0.13`, fast-forward `main`, start `0.0.14`. **Travis's OK first** (public host).
- [ ] Get `mcp/` onto public `main` (comes with the release push; public repo, Travis's call). The MCP launch posts link to `github.com/traviskirton/clausage/tree/main/mcp`, which is 404 until then. The installer is already live at `https://clausage.ai/mcp/install.sh`.
- [ ] Upload the iPhone archive from Xcode Organizer (Travis). App Store Connect has had the name reserved since Oct 7 with no build; Apple can release unused names.

## Testing (Travis, on real hardware)

- [ ] macOS 13 Ventura path (one account, `App/Compat.swift`): never run on a Ventura machine.
- [ ] Sparkle update from an old "Claude Usage" 0.0.3 install to the current release (old bundle ID, legacy feed).
- [ ] iPhone on device: App Group, Keychain group, widgets, background refresh.
- [ ] Live checks left from 0.0.11: the Disconnect confirmation, account radio switching, the shortcut migration, permission states after a round trip to System Settings.

## MCP (`mcp/`)

- [ ] Mid-December: calibrate job sizes from `~/.clausage-mcp/jobs.jsonl` (match checks to transcripts, per-size ranges). **Ask Travis first.**
- [ ] Custom `CLAUDE_CONFIG_DIR`: read the matching `Claude Code-credentials-<suffix>` Keychain item. Only matters for public users with several accounts.
- [ ] Idea: a warn-only PreToolUse hook on Agent/Workflow.

## Backlog

- [ ] A way to see archived weeks: step through weeks on the Settings › Usage chart, and/or CSV export.
- [ ] A separate "Clausage Dev" bundle ID, so `./build.sh install` stops replacing the notarized copy.
- [ ] GitHub repo: upload `media/social-preview.png` under Settings → Social preview (manual).
- [ ] Deferred from the 0.0.11 design review: the food-metaphor caption (9), the Claude Code numbers (16).

## Done recently

- [x] 2026-11-24: MCP `get_history`, App ↔ MCP contract tests, MCP installer hosted at clausage.ai/mcp, `site-mkt` merged and deployed (`/support` live).
