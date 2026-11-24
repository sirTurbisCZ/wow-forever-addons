# Forever Error Log

Captures Lua errors from **all** addons into SavedVariables so you can share them without fighting the Blizzard error popup queue.

## Install

1. Download the latest `ForeverErrorLog-*.zip` from [Releases](https://github.com/sirTurbisCZ/wow-forever-addons/releases).
2. Extract so the folder `ForeverErrorLog` sits in `World of Warcraft/_forever_/Interface/AddOns/`.
3. Enable the addon at character select (if needed) and `/reload` in game.

## Commands

| Command | What it does |
|---------|----------------|
| `/felog help` | Show help and status |
| `/felog list` | Summarize stored errors |
| `/felog dump` | Print recent errors with stacks to chat |
| `/felog clear` | Clear the error log |
| `/felog reset` | Reset settings to defaults and clear the log |
| `/felog on` / `/felog off` | Enable or disable capture |
| `/felog ui on` / `/felog ui off` | Show or hide the Blizzard scriptErrors popup |

Aliases: `/ferrors`, `/forevererrors`.

## Default behavior

- Errors are **collected** into `ForeverErrorLogDB`.
- **Chat:** only real **errors** (short `[FElog]` line) + intentional `/felog` commands — no boot spam (`silentBoot`, 0.1.2+).
- The Blizzard error popup is **off** by default (it queues old errors and is painful to dismiss).
- After `/reload`, capture stays active and settings persist via SavedVariables.
- **Agent watch:** `./scripts/watch-forever-traces.sh` (BB + Plateband + FElog SV paths).

## Sharing a bug

1. Reproduce the error (or wait until it appears — chat shows a short `[FElog]` line).
2. `/reload` once (or log out) so SavedVariables flush to disk.
3. Send this file to friends / Discord / GitHub:

`World of Warcraft/_forever_/WTF/Account/<Account>/SavedVariables/ForeverErrorLog.lua`

Inside: `errors` (ring across sessions) and `sessionLog` (wiped each login, append-only during play).  
Optional rare path if addon file IO works: `Interface/AddOns/ForeverErrorLog/Logs/session.log`.

You can still `/felog list` / `/felog dump` for a quick chat view.

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| Addon does not load | Check Interface folder name is exactly `ForeverErrorLog` and the `.toc` is inside it |
| No errors captured | `/felog on`, then `/reload`; confirm another addon actually errors |
| Want the Blizzard popup | `/felog ui on` |
| Want a clean slate | `/felog clear` (log only) or `/felog reset` (settings + log) |
