# ForeverErrorLog changelog

## Release 0.3.2 — repeat counters after clear/reset (#52)

- Help and usage lines use a slash instead of a pipe between words (#54): the client reads `|r`, `|t`, `|n`, `|k` and similar as escape codes and swallowed part of the text.
- **#52:** the "same error again within 1 s" counters are forgotten after `/felog clear` and `/felog reset` (a repeat right after was counted on the discarded entry and lost); the addon name taken from the error path is capped at 100 characters. Known limitation: when a second addon wraps the error handler after ours was re-installed on top, an even earlier wrapper is not called any more (the base handler still is).

## Release 0.3.1 — audit fixes (#42), polish (#46)

- **Counts (#42):** a taint entry no longer receives the repeat count of a plain error that follows it (error, taint, same error within 1 s used to increment the taint entry).
- **Handler chain (#42):** the first-captured Blizzard handler stays reachable when another addon wraps FElog, so `/felog ui on` popups keep working. A handler installed by another addon is always forwarded to, also with the popup off. A failing forwarded handler is recorded once and no longer re-thrown (which re-entered the handler).
- **Load line (#42):** `[ForeverErrorLog] vX.Y.Z · /felog`, or `· capture OFF (/felog on)` when capture is disabled. The chat prefix is now `[ForeverErrorLog]`.
- **Minimap button (#42):** repositioned on `PLAYER_ENTERING_WORLD` and when the minimap is resized; tooltip lists the click actions; right-click prints the `/felog help` hint.
- **Window (#42):** the text is cut on a character boundary, `|` is shown as `||`, and a too-long page ends with `... (page truncated, use Next)`. Clear on the Previous view needs a second click (`Really clear?`, 3 s). `/felog reset` re-places the minimap button and window. Key repeat no longer re-sets the whole text.
- **SavedVariables (#42):** the stored addon name is capped at 100 characters; all other diagnostic tables were already bounded.
- **Polish (#46):** TOC `X-Website`, `X-License`, `IconTexture`; `/felog settings` opens the window; the copied report starts with the issues link; README install and issues sections.

## Release 0.3.0 — error window, minimap button, taint capture (#32)

- **Minimap button position (#37):** the radius follows the real minimap width (the Forever minimap is larger, the button used to float outside the ring) and the default angles differ per addon so the buttons do not overlap.
- **Window:** `/felog` (no argument) or the minimap button opens a draggable window with a copyable report (header with FElog version, client build, locale and loaded Forever addon versions, then the errors with stacks). Buttons: This session / Previous, page back/forward (20 entries per page), Clear, Close; Esc closes. Built on first open; nothing is created at login except the minimap button. Position is saved.
- **Minimap button:** left-click toggles the window, hover shows the error count and the last 5 errors, drag to move; `/felog minimap` hides or shows it (`minimapHide`).
- **Taint capture:** `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` are recorded as `[blocked] <addon> tried <function>` (repeats counted). `/felog taint on|off` (`captureTaint`, default on).
- Existing subcommands are unchanged; `/felog help` still lists them.

## Release 0.2.1 — survive handler replacement, less work per error

- **Handler re-check:** if another addon calls `seterrorhandler` later, FElog (on `PLAYER_LOGIN` and `PLAYER_ENTERING_WORLD`) forwards to that handler as its original and installs itself again; a re-entrancy guard prevents forwarding loops.
- **Chat:** at most one `[FElog]` line per 2 s, with a "(+N more)" counter for the errors held back.
- **Repeats:** the same message within 1 s is only counted, before `debugstack` is taken. Messages are capped at 1500 characters (was 4000) and stacks at 1500; the archive of a previous session keeps its top 20 entries by count. The visible error list is unchanged.

## Release 0.2.0 — rewrite: working capture, persistent popup setting, dev telemetry opt-in

- **Fix (critical):** every session-log write threw (`AppendLiveStream` was called before it was declared), so the error handler was installed late, the `[FElog]` chat line never appeared and nothing was recorded after the first error. `Core.lua` is rewritten without the dead export/pulse/version code (about 40 % of the old file); the handler is installed on `ADDON_LOADED`.
- **`/felog ui on` persists** across `/reload` and relog (the saved preference is applied; the `scriptErrors` CVar is only written when it differs).
- **`/felog off` hands errors to the default handler** instead of swallowing them; the same happens if capture itself fails.
- **Error list:** reset once per load (previous list archived, last 8 kept, each message/stack trimmed to 1000 characters). FElog no longer wipes other addons' error lists. Repeated errors write to the session log sparsely.
- **Developer telemetry** (`AgentFeed`, `NotifyRuntime`, `ApplyLiveHeadSnapshot`, live head, export strings) runs only after **`/felog dev on`** (default off). All file-writing code is gone: the Forever client has no `io`.
- **SavedVariables schema 5:** `errorWipeTok` removed; session `export` strings are emptied unless dev telemetry is on.
- TOC: `OptionalDeps: !BugGrabber` (stable load order). README rewritten.

Earlier 0.1.x versions: internal development builds.
