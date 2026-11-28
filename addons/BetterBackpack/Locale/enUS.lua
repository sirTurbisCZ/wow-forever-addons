--[[ BetterBackpack — English (default) strings ]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.L = BetterBackpack.L or {}

local L = BetterBackpack.L

L.PREFIX = "|cffc9a227[BetterBackpack]|r"
L.LOADED = "v%s · /bb"
L.UNKNOWN_CMD = "unknown command — /bb help"
L.HELP_LINES = {
  "/bb — toggle bags",
  "/bb help — this help",
  "/bb on/off — enable / restore Blizzard bags",
  "/bb sort/tidy — OOC tidy (SortBags + stack merge)",
  "/bb settings — categories + feature toggles",
  "/bb search <text> — filter by name/itemID (empty clears)",
  "/bb filter <cat/all> — show one category lane",
  "/bb pin <itemID> — toggle red ghost pin (not owned)",
  "/bb custom add <name> — new custom category",
  "/bb custom del <id> — remove custom category",
  "/bb assign <itemID> <cat/clear> — item → category rule",
  "/bb trashtest [go/<itemID>] — check click destroy still works (destroys 1 grey stack)",
  "/bb layout [lanes/dense] — layout mode toggle",
  "/bb merge [on/off] — visual stack merge",
  "/bb dump — status + errors + actionTrace tail",
  "/bb bagkey — B-key hook + onBagKey trace (diagnose)",
  "/bb safe — safe mode (release to Blizzard)",
  "/bb reset — reset settings + this character (other characters kept); /bb reset all — everything",
  "/bb selftest — CS-RMB wiring card (still need 1× manual combat RMB)",
  "/bb bags — reagent/free-space probe (no secret print)",
  "/bb slots — slot button counters (placed / shown / mouse / usable, secure driver) for combat diagnosis",
  "/bb frame [open] — print frame shown/size/strata (debug)",
}
L.STATUS_LINE = "enabled=%s · safe=%s · replace=%s · schema=%s · ver=%s · open=%s"
L.ENABLED = "on — /bb opens BetterBackpack (B = Blizzard bags)"
L.DISABLED = "off — Blizzard bags restored"
L.SAFE_ON = "safe mode — Blizzard bags; /bb on to resume"
L.CONFIG_RESET = "settings + this character reset (other characters kept) — /bb reset all wipes everything"
L.CONFIG_RESET_ALL = "all BetterBackpack data reset (every character)"
L.NO_ERRORS = "no errors in ring"
L.DUMP_HEADER = "dump — errors=%d · ver=%s"
L.SORT_COMBAT = "sort: not in combat"
L.COMBAT_NO_FRAME = "combat: open bags once out of combat first (no UI build in lockdown)"
L.SORT_BUSY = "sort already running…"
L.SORT_START = "tidying…"
L.SORT_DONE = "tidy done"
L.SELFTEST_HINT = "selftest PASS — still need 1× manual combat RMB potion = CS-RMB evidence"
