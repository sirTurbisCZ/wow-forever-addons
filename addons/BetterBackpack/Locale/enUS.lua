--[[ BetterBackpack — English (default) strings ]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.L = BetterBackpack.L or {}

local L = BetterBackpack.L

L.PREFIX = "|cffc9a227[BetterBackpack]|r"
L.LOADED = "loaded v%s · B = category bags · /bb"
L.UNKNOWN_CMD = "unknown command — /bb help"
L.HELP_LINES = {
  "/bb — toggle bags",
  "/bb help — this help",
  "/bb on|off — enable / restore Blizzard bags",
  "/bb sort — OOC Úklid (SortBags)",
  "/bb dump — status + recent errors",
  "/bb safe — safe mode (release to Blizzard)",
  "/bb reset — restore defaults",
  "/bb selftest — CS-RMB wiring card (still need 1× manual combat RMB)",
  "/bb bags — reagent/free-space probe (no secret print)",
  "/bb frame [open] — print frame shown/size/strata (debug)",
}
L.STATUS_LINE = "enabled=%s · safe=%s · replace=%s · schema=%s · ver=%s · open=%s"
L.ENABLED = "on — B opens BetterBackpack"
L.DISABLED = "off — Blizzard bags restored"
L.SAFE_ON = "safe mode — Blizzard bags; /bb on to resume"
L.CONFIG_RESET = "config reset to defaults"
L.NO_ERRORS = "no errors in ring"
L.DUMP_HEADER = "dump — errors=%d · ver=%s"
L.SORT_COMBAT = "sort: not in combat"
L.SORT_BUSY = "sort already running…"
L.SORT_START = "tidying…"
L.SORT_DONE = "tidy done"
L.SELFTEST_HINT = "selftest PASS — still need 1× manual combat RMB potion = CS-RMB evidence"
