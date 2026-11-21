--[[ Plateband — English (default) strings ]]

Plateband = Plateband or {}
Plateband.L = Plateband.L or {}

local L = Plateband.L

L.PREFIX = "|cff7ec8e3[Plateband]|r"
L.LOADED = "loaded v%s · /pb"
L.UNKNOWN_CMD = "unknown command — /pb help"
L.HELP_LINES = {
  "/pb help — this help",
  "/pb on|off — enable/disable the above-plate aura band",
  "/pb diagnose — compact status card (target a mob first)",
  "/pb dump — status + recent errors + last diagnose",
  "/pb safe — disable band and clear overlays",
  "/pb reset — restore defaults",
  "/pb size <n> — icon size hint (12–32)",
}
L.STATUS_LINE = "enabled=%s · safe=%s · schema=%s · ver=%s"
L.ENABLED = "band on"
L.DISABLED = "band off"
L.SAFE_ON = "safe mode — band cleared; /pb on to resume"
L.CONFIG_RESET = "config reset to defaults"
L.SIZE_SET = "icon size hint: %d"
L.SIZE_BAD = "usage: /pb size <12-32>"
L.NO_ERRORS = "no errors in ring"
L.DUMP_HEADER = "dump — errors=%d"
L.DIAG_NEED_TARGET = "diagnose: target an enemy with a nameplate"
