--[[ Plateband — English (default) strings ]]

Plateband = Plateband or {}
Plateband.L = Plateband.L or {}

local L = Plateband.L

L.PREFIX = "|cff7ec8e3[Plateband]|r"
L.LOADED = "v%s · /pb"
L.UNKNOWN_CMD = "unknown command — /pb help"
L.HELP_LINES = {
  "/pb, /pb settings — open the settings window (also the minimap button)",
  "/pb help — this help",
  "/pb minimap — show/hide the minimap button",
  "/pb on|off — enable/disable the above-plate aura band",
  "/pb diagnose — compact status card (chat); SV always logs silently",
  "/pb dump — status + errors + last diagnose card",
  "/pb watch on|off — chat card every ~2s (off by default)",
  "/pb dev on|off — dev telemetry (PAINT trace, cards in SavedVariables; default off)",
  "/pb selftest — quick self check",
  "/pb tree — aura frames of the target plate (which frame draws which icon)",
  "/pb safe — disable band and clear overlays",
  "/pb reset — restore defaults",
  "/pb size <n> — icon size hint (12–32)",
  "/pb merge on|off — add party debuffs / short buffs / dispellable enemy buffs to the aura row",
  "/pb ac on|off|status — EXPERIMENTAL: draw the row with Blizzard's AuraContainer (works in combat?)",
}
L.STATUS_LINE = "enabled=%s · safe=%s · watch=%s · schema=%s · ver=%s · log=%s"
L.ENABLED = "band on"
L.DISABLED = "band off"
L.SAFE_ON = "safe mode — band cleared; /pb on to resume"
L.CONFIG_RESET = "settings reset"
L.SIZE_SET = "icon size hint: %d"
L.SIZE_BAD = "usage: /pb size <12-32>"
L.NO_ERRORS = "no errors in ring"
L.DUMP_HEADER = "dump — errors=%d · sessionLog lines=%d"
L.WATCH_ON = "watch on — card every %ss (also SV sessionLog)"
L.WATCH_OFF = "watch off"
L.MERGE_ON = "merge on — foreign DoTs beside native DebuffList (enemy plates)"
L.MERGE_OFF = "merge off — native DebuffList only"
L.MERGE_USAGE = "usage: /pb merge on|off  (currently %s)"
L.LOG_HINT = "diagnostics are in WTF/.../SavedVariables/Plateband.lua after /reload"
L.DEV_ON = "dev telemetry on — PAINT trace + cards go to SavedVariables"
L.DEV_OFF = "dev telemetry off"
L.DEV_USAGE = "usage: /pb dev on|off  (currently %s)"
L.AC_ON = "AuraContainer row ON (experimental) — containers are built out of combat; /pb tree shows them"
L.AC_OFF = "AuraContainer row off — legacy row"
L.RELOAD_NEEDED = "/reload needed: this setting applies to plates created after /reload"
L.RELOAD_NOTE = "/reload needed: enemy buffs and icon count apply to plates created after /reload."
L.AC_USAGE = "usage: /pb ac on|off|status"
