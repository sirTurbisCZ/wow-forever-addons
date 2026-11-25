--[[ ForeverErrorLog — English (default) strings ]]

ForeverErrorLog = ForeverErrorLog or {}
ForeverErrorLog.L = ForeverErrorLog.L or {}

local L = ForeverErrorLog.L

L.PREFIX = "|cffd94a4a[FElog]|r"
L.LOADED_COUNT = "loaded v%s — %d errors stored (historical) · session %s · /felog session"
L.LOADED_EMPTY = "loaded v%s — session %s · /felog session · popup off"
L.RELOAD_LINE = "reloaded v%s · live feed %s"
L.SESSION_HEADER = "session lines=%d file=%s (LIVE this login)"
L.SESSION_HINT = "historical errors: /felog list · agent LIVE: Logs/session.log or /felog session"
L.NO_SESSION = "no session lines yet"
L.NO_ERRORS = "no errors stored"
L.LOG_CLEARED = "log cleared"
L.CONFIG_RESET = "config reset to defaults (log cleared)"
L.UNKNOWN_CMD = "unknown command — /felog help"
L.HELP_LINES = {
  "/felog help — this help",
  "/felog list — stored errors (historical ring)",
  "/felog session — live session tail (AGENT/ERROR this login)",
  "/felog dump — recent errors with stacks (chat)",
  "/felog clear — clear the error log",
  "/felog reset — reset config + clear log",
  "/felog on|off — enable/disable capture",
  "/felog ui on|off — Blizzard scriptErrors popup",
}
L.LIST_HEADER = "%d error(s) — last 15:"
L.DUMP_HINT = "send WTF/.../SavedVariables/ForeverErrorLog.lua after /reload (sessionLog + errors)"
L.CAPTURE_ON = "capture on"
L.CAPTURE_OFF = "capture off"
L.UI_ON = "scriptErrors popup on"
L.UI_OFF = "scriptErrors popup off (capture still runs)"
L.UI_STATUS = "scriptErrors preference: %s — /felog ui on|off"
L.STATUS_LINE = "stored: %d · enabled=%s · schema=%s"
L.BUGGRABBER = "hooked into BugGrabber"
L.NO_SETHANDLER = "seterrorhandler missing — use /console scriptErrors 1 at least"
