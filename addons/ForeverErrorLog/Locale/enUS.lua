--[[ ForeverErrorLog — English (default) strings ]]

ForeverErrorLog = ForeverErrorLog or {}
ForeverErrorLog.L = ForeverErrorLog.L or {}

local L = ForeverErrorLog.L

L.PREFIX = "|cffd94a4a[FElog]|r"
L.LOADED_COUNT = "loaded v%s — %d errors this session · popup %s · /felog list"
L.LOADED_EMPTY = "loaded v%s — 0 errors this session · popup %s · /felog help"
L.SESSION_HEADER = "session lines=%d (this load)"
L.SESSION_HINT = "prior rings: /felog archive · live list: /felog list · /felog session"
L.NO_SESSION = "no session lines yet"
L.NO_ERRORS = "no errors stored"
L.LOG_CLEARED = "log cleared (archived %d)"
L.ARCHIVE_HEADER = "%d archived session(s) — /felog archive dump"
L.NO_ARCHIVE = "no archived error rings yet"
L.CONFIG_RESET = "config reset to defaults (log cleared)"
L.UNKNOWN_CMD = "unknown command — /felog help"
L.HELP_LINES = {
  "/felog help — this help",
  "/felog list — errors this session",
  "/felog archive [dump] — prior session rings (kept in SV)",
  "/felog session — session log tail (this load)",
  "/felog dump — recent errors with stacks (chat)",
  "/felog clear — clear the error log",
  "/felog reset — reset config + clear log",
  "/felog on|off — enable/disable capture (off = errors go to the default handler)",
  "/felog ui on|off — Blizzard scriptErrors popup (saved)",
  "/felog dev on|off — dev telemetry (default off)",
}
L.LIST_HEADER = "%d error(s) — last 15:"
L.DUMP_HINT = "send WTF/.../SavedVariables/ForeverErrorLog.lua after /reload (sessionLog + errors)"
L.CAPTURE_ON = "capture on"
L.CAPTURE_OFF = "capture off — errors go to the default handler"
L.UI_ON = "scriptErrors popup on"
L.UI_OFF = "scriptErrors popup off (capture still runs)"
L.UI_STATUS = "scriptErrors preference: %s — /felog ui on|off"
L.STATUS_LINE = "stored: %d · enabled=%s · schema=%s"
L.DEV_ON = "dev telemetry on"
L.DEV_OFF = "dev telemetry off"
L.DEV_STATUS = "dev telemetry: %s — /felog dev on|off"
L.BUGGRABBER = "hooked into BugGrabber"
L.NO_SETHANDLER = "seterrorhandler missing — use /console scriptErrors 1 at least"
