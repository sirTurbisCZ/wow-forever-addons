# Forever Error Log

Captures Lua errors from **all** addons into SavedVariables so you can share them without fighting the Blizzard error popup queue.

## Install

1. Download the latest `ForeverErrorLog-*.zip` from [Releases](https://github.com/sirTurbisCZ/wow-forever-addons/releases).
2. Extract so the folder `ForeverErrorLog` sits in `World of Warcraft/_forever_/Interface/AddOns/`.
3. Enable the addon at character select (if needed) and `/reload` in game.

Expect `[FElog] loaded v… — N errors this session · popup off` in chat.

## Commands

| Command | What it does |
|---------|----------------|
| `/felog help` | Help and status |
| `/felog list` | Summary of this session's errors (last 15) |
| `/felog dump` | Recent errors with stacks, printed to chat |
| `/felog session` | Tail of this load's session log |
| `/felog archive [dump]` | Error lists of earlier loads (last 8 are kept) |
| `/felog clear` | Clear the error list (it is archived first) |
| `/felog reset` | Reset settings to defaults and clear the log |
| `/felog on` / `/felog off` | Enable or disable capture. **Off** hands errors to the default handler. |
| `/felog ui on` / `/felog ui off` | Show or hide the Blizzard error popup. Saved; survives `/reload` and relog. |
| `/felog dev on` / `/felog dev off` | Developer telemetry (off by default) |

Aliases: `/ferrors`, `/forevererrors`. `/felog history` and `/felog ls` are aliases of `archive` and `list`.

## Default behavior

- Errors are **collected** into `ForeverErrorLogDB`; a short `[FElog]` line appears in chat for each **new** error.
- The Blizzard error popup is **off** by default (it queues old errors and is painful to dismiss). `/felog ui on` turns it back on and stays on.
- Identical errors are counted, not repeated.
- Every `/reload` or login starts a fresh error list; the previous one is moved to the archive (`/felog archive`).
- Capture off (`/felog off`) or a failure inside FElog never swallows an error: it goes to the normal handler.
- If **BugGrabber** is installed, FElog listens to it instead of replacing the error handler.

## Sharing a bug

1. Reproduce the error (or wait until it appears — chat shows the `[FElog]` line).
2. `/reload` once (or log out) so SavedVariables are written to disk.
3. Send this file:

`World of Warcraft/_forever_/WTF/Account/<Account>/SavedVariables/ForeverErrorLog.lua`

Inside: `errors` (this load), `errorArchive` (earlier loads, trimmed to 1000 characters per message/stack) and `sessionLog` (this load).

You can also use `/felog list` and `/felog dump` for a quick view in chat.

## Notes

- The Forever client has no `io` library, so addons cannot write files; everything goes to SavedVariables.
- Developer telemetry (`/felog dev on`) lets other addons (for example Plateband) append diagnostic lines and live-head data to the session log. Nothing is sent anywhere.

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| Addon does not load | Folder name must be exactly `ForeverErrorLog` and the `.toc` must be inside it |
| No errors captured | `/felog on`, then `/reload`; confirm another addon actually errors |
| Want the Blizzard popup | `/felog ui on` |
| Want a clean slate | `/felog clear` (list) or `/felog reset` (settings + list) |
