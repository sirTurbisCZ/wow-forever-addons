--[[ Plateband — English (default) strings ]]

Plateband = Plateband or {}
Plateband.L = Plateband.L or {}

local L = Plateband.L

L.PREFIX = "|cff7ec8e3[Plateband]|r"
L.LOADED = "loaded v%s · merge on by default · /pb merge off for native-only · /pb help"
L.UNKNOWN_CMD = "unknown command — /pb help"
L.HELP_LINES = {
  "/pb help — this help",
  "/pb on|off — enable/disable the above-plate aura band",
  "/pb diagnose — compact status card (also auto-saved)",
  "/pb dump — status + recent errors + last diagnose",
  "/pb watch on|off — print one-line card every ~2s while on",
  "/pb safe — disable band and clear overlays",
  "/pb reset — restore defaults",
  "/pb size <n> — icon size hint (12–32)",
  "/pb merge on|off — paint omitted foreign harmful beside native (experimental)",
}
L.STATUS_LINE = "enabled=%s · safe=%s · watch=%s · schema=%s · ver=%s · log=%s"
L.ENABLED = "band on"
L.DISABLED = "band off"
L.SAFE_ON = "safe mode — band cleared; /pb on to resume"
L.CONFIG_RESET = "config reset to defaults"
L.SIZE_SET = "icon size hint: %d"
L.SIZE_BAD = "usage: /pb size <12-32>"
L.NO_ERRORS = "no errors in ring"
L.DUMP_HEADER = "dump — errors=%d · sessionLog lines=%d · file=%s"
L.WATCH_ON = "watch on — card every %ss (also SV sessionLog)"
L.WATCH_OFF = "watch off"
L.MERGE_ON = "merge on — foreign DoTs beside native DebuffList (enemy plates)"
L.MERGE_OFF = "merge off — native DebuffList only"
L.MERGE_USAGE = "usage: /pb merge on|off  (currently %s)"
L.LOG_HINT = "send WTF/.../SavedVariables/Plateband.lua after /reload (or Logs/session.log if file=yes)"
