--[[ Seekwell — English strings ]]

Seekwell = Seekwell or {}
Seekwell.L = Seekwell.L or {}

local L = Seekwell.L

-- Key Bindings > AddOns > Seekwell
BINDING_HEADER_SEEKWELL = "Seekwell"
BINDING_NAME_SEEKWELL_TARGET = "Show my target's drops"

L.PREFIX = "|cff6fc3e8[Seekwell]|r"
L.LOADED = "loaded v%s · /sw · %s"
L.TINNY_YES = "Tinny data: yes"
L.TINNY_NO = "Tinny data not available (learned data only)"
L.UNKNOWN_CMD = "unknown command — /sw help"
L.HELP_LINES = {
  "/sw — open or close the search browser (items, mobs, where they drop, wishlist)",
  "/sw settings [section] — the settings window",
  "/sw target — show what drops from your target (also a key: Key Bindings > AddOns > Seekwell)",
  "/sw status — version, data sources, learned data, wishlist",
  "/sw probe — which client APIs are available",
  "/sw minimap on|off|reset — the minimap button",
  "/sw reset — restore default settings (learned data and wishlist stay)",
  "/sw reset learned — forget all learned loot data",
  "/sw dev on|off — debug output",
}
L.CONFIG_RESET = "settings reset to defaults (learned data and wishlist kept)"
L.LEARNED_RESET = "learned data cleared"
L.DEV_ON = "debug output on"
L.DEV_OFF = "debug output off"
L.MINIMAP_SHOWN = "minimap button shown"
L.MINIMAP_HIDDEN = "minimap button hidden (/sw minimap on to bring it back)"
L.MINIMAP_RESET = "minimap button reset"

L.TIP_TITLE = "Seekwell"
L.TIP_LEFT = "Left-click: search items and mobs"
L.TIP_RIGHT = "Right-click: settings   Shift+click: my target's drops"
L.TIP_DRAG = "Drag: move around the minimap"

L.ORIGIN_FOREVER = "Forever"
L.ORIGIN_CLASSIC = "Classic estimate"
L.ORIGIN_LEARNED = "learned (yours)"
L.UNKNOWN = "\226\128\148" -- em dash

L.PANEL_TITLE = "Seekwell"
L.PANEL_HINT = "Target a creature (or hover one) and press the key again."
L.PANEL_PLAYER = "That is a player. Players have no drop table."
L.PANEL_PET = "That is a pet or a companion. No drop table."
L.PANEL_SECRET = "The game hides this unit's identity here (secret value), so its drops cannot be looked up."
L.PANEL_NOTNPC = "This kind of unit has no drop table."
L.PANEL_NODATA = "No drop data known for this mob yet. Loot it to learn."
L.PANEL_FOOTER = "Click: wishlist star · Right-click: where it drops · Shift+click: link"
L.TINNY_MISSING = "Tinny data not loaded"
L.PANEL_NOTINNY = "The drop database comes from TnnysMobLoot, which is not loaded on this character. Enable \"Tnny's Mob Loot\" in the AddOns list at character select, then log in again. Until then only mobs you looted yourself are known."

L.WISH_ADDED = "added to the wishlist: %s"
L.WISH_REMOVED = "removed from the wishlist: %s"
