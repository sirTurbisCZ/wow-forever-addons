# Seekwell changelog

## Release 0.5.6 — fewer allocations, fixes from the audit

- `Config.Get()` / `Learned` / `Char` return the checked saved-variable table after the first pass instead of building the default tables on every call (it is called on every ForeverDB lookup, tooltip, minimap tick and mouseover).
- A saved hunt no longer loads ForeverDB during login (it loads about 20 s later, out of combat); the hunt's mob list is re-resolved when the wishlist or ForeverDB changed (learned data at most every 60 s), so starring an item or a finished ForeverDB load now adds pins.
- Learned drop rate counts the kills that dropped an item, not the stack size (no more 100 % and "learned 5/3" for 2-3 cloth per kill; data saved earlier stays as it was).
- Item source cache: 500 entries and a plain reset when full (the old oldest-entry scan walked all entries on every insert); ForeverDB spawn cache 600.
- The settings / wishlist window skips rendering while it is hidden.
- The "Got X" alert fires only from your own loot chat line, no longer for items merely shown in the loot window (a lost roll or a left item) that, with "remove on loot", also removed the wishlist star.
- ForeverDB: the target panel and the search refresh when an index finishes building (they showed nothing until the next action); a failed index build is retried (twice) instead of staying "building"; spawn point cap applies per map for both sources.
- Pruning old learned mobs also removes their learned spawn points, so SavedVariables stop growing.
- Item search caches its id pool and requests at most 50 uncached item names per search (each id once); the mob search caches lowercased learned names; the item tooltip does its early exits before building lines.

## Release 0.5.5

- **Loot lag with ForeverDB on: root cause fixed.** During a hunt the minimap ticker (10x per second) rebuilt the points of every source mob each tick (spawns merged from learned / ForeverDB / Classic with de-duplication, then clustered). With ForeverDB an item has up to 200 source mobs, so the main thread was busy all the time and loot / bag events were processed late. `Map.PointsForMap` is now cached per hunt and map and rebuilt only when spawns, ForeverDB, wishlist, learned data, hidden mobs or the filters changed; the minimap skips the redraw while position, zoom and data are unchanged.
- ForeverDB data is on by default again (the 0.5.4 opt-in is reverted: the owner wants the data, the lag came from the minimap ticker). The setting key stays `forever.fdbData` (true by default; `/sw fdb off` to turn it off).

## Release 0.5.4

- (superseded by 0.5.5) **ForeverDB data opt-in.** ForeverDBData needs ~97 MB of memory in the game and Seekwell's own indexes over it another ~35 MB, which made looting lag. The setting is now `forever.fdbData` (default false; `/sw fdb on`, or Settings > Forever). Off = nothing is loaded and Seekwell is back to ~16 MB. Tinny, learned data, Seekwell_Locations and the Dungeon Journal bridge work as before.

## Release 0.5.3

- `/sw perf`: top addons by memory and CPU (CPU needs `/console scriptProfile 1` and a reload), FPS and latency, to find what slows looting down.

## Release 0.5.2

- **Loot lag fixed.** The wanted-mob index of the alerts was rebuilt on the next target / mouseover after every loot (its cache key contained the learned-data counter, which changes with each loot) and the rebuild looks up the sources of every wished item. The key now follows only the wishlist; newly learned data refreshes the index at most every 120 s and never in combat.

## Release 0.5.1

- **Pins no longer black.** The disc and ring used `TempPortraitAlphaMask`, a black mask picture, so every pin (world map, minimap, preview) was a black disc whatever its colour band. They are now white colour textures cut round with a mask texture, tinted by the band colour.
- **Silver pins:** mob pins are plain silver dots without a glyph (distinct from the gold gathering nodes); the drop-% band is shown in the tooltip only.
- **Map preview:** pins are smaller and spots closer than 2.2 % of the map merge into one pin with a count, so a mob with many spawns is no longer one blob.

## Release 0.5.0

- **ForeverDB data as the primary Forever source.** New optional bridge `Data/FDBBridge.lua` (`Seekwell.FDB`) reads the forever-db data addon (game folder **ForeverDBData**, also `ForeverDB_Data`; global `ForeverDB`; GPL-3.0) at runtime. Nothing is copied into Seekwell. It is loaded on first need (search, hunt / On map, target panel, `/sw fdb`), never at login and never in combat (queued to `PLAYER_REGEN_ENABLED`), with a one-line chat note "loading Forever database..." and the load time in its status. Passive lookups (tooltips) never trigger the load.
- **Drops:** ForeverDB drop tables are merged as origin `forever_db`, label "ForeverDB (kills)" (kills from its Drop Tables `gold` table when known). Ranking: learned / Tinny Forever (measured) > ForeverDB > Classic estimates > extra providers; a lower source never overwrites a row, missing npcs are added. Chance per 10000 becomes percent (5000 = 50 %); `0` = drops, rate unknown ("—"). Mob drops use an npc -> items index inverted once from `drop`, built in ~4 ms `C_Timer` slices. Npc names and levels come from ForeverDB when Tinny lacks them, so the target panel and tooltip lines also work **without Tinny**.
- **Spawns:** ForeverDB positions (`spm` map spots / 1000 and `spw` world coordinates converted with `C_Map.GetMapPosFromWorldPos`, cached per npc, at most 60 points per continent group) join learned points (src `fdb`, de-dup within 1.5 %). When ForeverDB knows an npc, the old Classic bundle (Seekwell_Locations) is skipped for it. Pins, map preview, zone view and coverage now work for Forever-new mobs and zones; pin tooltip "ForeverDB spawn data (approximate)".
- **Search:** item and mob names from ForeverDB's name indexes (all 32k items, no client cache needed), Forever 'F' tag from ForeverDB (`IsForeverOnly`: id >= 211000, or not in Tinny's Classic Starter table), dungeon entrances from `dng` as a fallback for journal dungeons without one. Without the data addon the browser says once: "For full Forever coverage install the ForeverDB data addon (see README)".
- **Vendors and quest rewards** from ForeverDB (`vend`, `rew` + `quest` + `qg`) after the learned ones in item pages and `/sw item`.
- `/sw fdb [status|on|off|reload]`, a `/sw status` line, `settings.forever.fdb` (default on) with a checkbox and build / counts in Settings > Forever, and `/sw selftest` checks (addon found, loads, npc 3 and item 2589 resolve, spawn conversion, status).
- `Seekwell_Locations` stays as a fallback; it is no longer needed when ForeverDBData is installed.

## Release 0.4.1

- **New map pins** (world map, minimap, map preview; shared `Map/PinArt.lua`). Round pin ~20 px on the world map (16 px minimap, 15 px preview): the **disc colour is the drop chance** (grey < 1 %, white 1-10 %, green 10-30 %, gold > 30 %, light blue = unknown), the **glyph is the kind** (skull = mob, coin = vendor, yellow ! = quest, portal = dungeon entrance), the **ring is the source** (cyan = learned by you, thin dark = Classic data, violet = entrance). Clustered spots are 4 px bigger with an outlined count. Hover = 1.2x + glow; tooltips unchanged. World-map pins use `UseFrameLevelType` + `SetScalingLimits(1, 1.0, 1.35)`. Colours are applied with `SetVertexColor` on textures created in Lua (the old XML template had a fixed `<Color>` square and white dots for 1-10 % and unknown chances).
- **Honest coverage.** The item page says "Locations known for X of Y mobs (Classic data + your loot) — the rest: loot them to learn where they live"; the mob page says whether its location is known. New toggle **Located first** (default on, `settings.browser.locatedFirst`): located mobs float above unlocated ones within the same origin class (Forever/learned, then Classic), percent order kept otherwise. The map preview now uses **all** sources of an item (it used only the first 12), zone tabs exist only for zones with spots, and the tab row shows the total "N spot(s) in M zone(s)".
- **Dungeon hunt saved by name** (`hunt = { kind = "dungeon", id = "<name>" }`); a 0.4.0 numeric hunt (a list position) is dropped at login instead of pointing at a wrong dungeon. Dungeons are no longer written to the recently-viewed list.
- **Forever badge** only when Tinny's Starter (Classic) tables are loaded; without them nothing tells Classic from Forever, so no badge.
- **Entrance learning switch** `settings.forever.learnEntrances` (default on; Settings > Forever): off cancels the 5 s outdoor position ticker entirely.
- **Learned entrances** are looked up case-insensitively and fuzzily against journal names (e.g. a wing name vs. the instance name); instance names from the game are matched to the journal the same way. `DJ.Get(name)` is case-insensitive.
- **`/sw selftest`**: one PASS / WARN / FAIL / SKIP line per piece (Tinny tables, name index, Registry, Classic spawn data, map provider, pin template, minimap, map art, waypoints, Dungeon Journal, tooltip hook, binding, SavedVariables, learning, wishlist round trip, alerts, sharing default, `Seekwell:` entries in ForeverErrorLog) and a summary. Restores what it toggles; SKIPs loading / frame creation in combat.
- Browser buttons size to their label (no overflow at the 1060 px layout); the wishlist quantity and Link button follow the wishlist button.

### Coverage: what is and is not located

The bundled Classic spawn data (Seekwell_Locations) covers about 3770 NPCs of **original Classic** open-world spawns. It has nothing for Forever-new mobs, Alterac Valley, mobs inside instances, and it cannot place skinning or world drops. Those mobs get a location only after you loot them once (or a group member shares it). For Mageweave Cloth, for example, most of its ~150 sources are not in the Classic data: the page now says so instead of looking incomplete.

## Release 0.4.0

- **Forever content.** New optional bridge `Data/DJBridge.lua` (`Seekwell.DJ`) reads the **ForeverDungeonJournal** addon at runtime (global `ForeverDungeonJournal_NS`; nothing copied, never required). It indexes its dungeons, bosses with loot (including its shared loot), dungeon quests with reward items and entrance positions once, lazily (about 2 ms for 35 dungeons / 1687 loot items / 393 quest reward items).
- **Dungeon sources everywhere.** Items dropped by a journal boss or given by a dungeon quest show the source "Hall of Thanes — Boss" (chance unknown, "—") in the browser detail, in `/sw item`, as one compact tooltip line and in the wishlist (labelled "Dungeon Journal"). Bosses with an npc id are also a Registry drop row (rank 3, below Forever / learned / Classic).
- **Dungeons tab.** Search has tabs **All / Items / Mobs / Dungeons**. A dungeon row shows its level range, boss and quest count and entrance zone; its page lists the bosses (click one for its loot), the quests with reward items (click an item to open it), the entrance on the zone map and **Open in DungeonJournal** (its `OpenBossPage`, when available). `/sw dungeon [name]`.
- **Entrance pins.** Dungeon entrances are violet pins (kind `entrance`) on the world map, minimap and map preview for the hunt of an item or a dungeon, with the tooltip "Dungeon entrance: X (levels, boss count)"; left click sets a waypoint.
- **Learned entrances.** Entering a party/raid instance remembers your last outdoor position as `learned.entrance[instance name]` for dungeons the journal cannot place (secret values skipped).
- **Forever badge and filter.** Forever-only items, mobs and dungeons get a gold **F** in result rows and "Forever" in the detail header; filter **Forever content only** (`settings.browser.foreverOnly`, `/sw forever on|off`) and a Forever count in the status line. Forever-only items found by their journal name; names fall back to the journal when the client cache has none.
- Settings section **Forever** lists the active bridges; new `settings.forever = { dj = true, nodes = true }`; `/sw status` lines.
- GatherLite nodes are not used: its node data is private to that addon (not a global) and keyed by game object id without an item mapping.

## Release 0.3.1

- **Big two-pane browser.** In browser mode the window is large (1060x680, at most 92 % of the screen, centred; its position is remembered per mode). Settings mode keeps 580x460. The nav is a narrow strip (Search, Wishlist, Zone); Wishlist and Zone reflow to the wide content (`Window.ContentWidth()`, `Window.Size()`, `RegisterSection{fixed, layout}`).
- **Search page = master / detail.** Left: search box, mode tabs **All / Items / Mobs** with live counts and a clear selected state (gold text + underline), collapsible filters (known location, only wishlist, min drop %, pin the selection), and a virtual list (20 pooled rows, mouse wheel + slider, up to 300 matches per kind; selected row highlighted; star, owned tick and a pin icon when a location is known). Right: the selected item or mob - header with wishlist toggle, wanted amount and Link, **Show on map**, **Clear map**, **Open world map** (out of combat only), **Waypoint to nearest**, a **zone map preview** (C_Map art tiles, grid fallback) with the known spots (hover = name + source, click = waypoint), a zone selector when there are several zones, and the sources list (mobs with %, zones, On map / Waypoint; vendors; quests) or the mob's drop table in its own scroll. Clicking a link selects it; **< Back** walks the history.
- **No more empty "Mobs" searches.** The default mode is **All**; a mode left on Mobs/Items by an older version is reset once. When the chosen mode has no results but the other has, the status line says so ("No items - 3 mobs match (click Mobs)").
- **Auto pin.** Selecting an item or mob sets the map hunt quietly, so the world map and minimap pins follow the selection (`settings.browser.autoPin`, default on).
- The separate Item and Mob pages are gone; `ItemView.Show`, `MobView.Show`, `Window.Show("item"/"mob")`, `/sw find` and `/sw browse` select on the Search page. New file `UI/MapPreview.lua`.

## Release 0.3.0

- **Search browser.** New window section **Search**: one box searches all items (Tinny's Classic item names, Forever / learned / wishlist items the client has cached; uncached names are requested and the search repeats once) and all mobs (Tinny and learned names). Modes All / Items / Mobs, filters "only with known location", "only wishlist", "min drop %" (`settings.browser`). Up to 40 rows are shown ("N more — refine your search"), at most 200 matches are scanned. Item rows: icon, quality colour, best source ("Blackrock Grunt 50 % · +12 more"), wishlist star, owned tick. Mob rows: level, kills, number of drops, "seen in …" or "location unknown". Empty search = wishlist + the last 15 viewed pages (per character, `SeekwellCharDB.recent`). `/sw browse [text]`.
- **Item page** (was the Item section): "< Back to search", wishlist toggle with the wanted quantity, per mob **On map** and **Waypoint** (nearest known spot), a click on a mob opens its page; Vendors and Quest rewards blocks; honest "location not known — loot this mob once to learn it"; the source label of spawn points is shown when the data carries one.
- **Mob page** (new): level, learned / Forever kills, zones and spot count, On map / Waypoint to nearest / Clear map, the full drop table (icon, %, origin, wishlist star; click = item page). `/sw find` falls back to mob names (one match opens the mob page, several open the search).
- **Window modes.** The window has a **browser mode** (nav: Search, Wishlist, Zone; Item and Mob are hidden detail pages that keep "Search" highlighted) and a **settings mode** (Target, Map, Alerts, Sharing, Learned, Settings), switched with the button at the bottom of the nav; the title says "Seekwell" or "Seekwell - Settings". New API: `Window.ShowBrowser`, `Window.ShowSettings`, `Window.CurrentMode`; `Window.Show(section)` picks the mode of the section; `Window.Toggle` toggles in browser mode. `RegisterSection` accepts `mode`, `hidden`, `navAs`, `before`. The Target section has a "Browse items and mobs" button.
- **Classic spawn points for mobs you never looted.** New optional, load-on-demand data addon **Seekwell_Locations** (about 3 770 mobs in 44 zones, original Classic spawns from pfQuest / CMaNGOS classic-db, GPL-3.0, own LICENSE and DATA-CREDITS). Seekwell loads it the first time a position is needed, never at login and never in combat (it waits for combat to end).
- Map and minimap pins, the hunt and the Item section's zones now use learned positions plus these Classic points; Classic points within 1.5 % of a learned spot are skipped. Pin tooltips say "Classic spawn data (approximate)", "position learned from your loot (approximate)" or "learned + Classic spawn data".
- `/sw locations on|off|status` and a `/sw status` line; setting `map.bundled` (on by default). Alterac Valley npcs are not included. Deleting the Seekwell_Locations folder leaves Seekwell working as before.

## Release 0.2.4

- **Where does this item drop?** New window section **Item**: every known source of one item (all mobs with drop chance and origin, up to 40 shown, vendors and quest rewards you have learned), with the zones you have met each mob in and the number of known spots, a button **On map** per mob (hunt: pins on the world map and minimap), **Show all on map** for the whole item, **Clear map**, and a wishlist toggle. Open it with **right-click** on a row in the target panel, a click on a wishlist item, or `/sw find <name|link|id>`.
- The source list is no longer limited to 10 mobs per item (up to 200 are looked up).

## Release 0.2.3

- Wishlist section layout: rows no longer overlap the hint text, and the have/wanted count and the amount box are spaced apart.

## Release 0.2.2

- **Wishlist: item icon and a wanted quantity.** Each wishlist row shows the item icon, a "have/wanted" count and a box for the wanted amount. The tick and the "left out of alerts and hunts" rule apply once you carry at least that many. Add a quantity with the name: `linen cloth x20` (also in the input box), or `/sw wish qty <name|id> <n>`; `/sw wish list` shows have/wanted.
- The owned tick is now a texture (the check-mark character was missing in the game font).

## Release 0.2.1

- **Wishlist: owned items are ticked automatically.** An item you already have (bags, bank when the client counts it) gets a green tick in the Wishlist section, is listed last and is left out of the wanted-mob alerts, the `/sw hunt wish` pins and the zone summary. It updates when your bags change. Setting "Wishlist: leave items I already own out of alerts and hunts" (on by default).
- **Add to the wishlist by name.** An input box with an Add button in the Wishlist section, and `/sw wish add <name|item link|id>`, `/sw wish del <name>`, `/sw wish list` (`/sw wish` opens the section). Names are searched in Tinny's Classic item table, the items you have looted and the Forever data (names the client has cached); an exact name or a single match is added, several matches are listed so you can type more. Links and ids always work.

## Release 0.2.0

- **Wishlist alerts (hunt mode).** When a mob that drops an item of this character's wishlist becomes your target or is under the mouse (nameplates optional, off by default), a toast at the top of the screen says "Wanted: <Mob> drops <Item> (12.5 %)". It fades after about 4 s, lets clicks through, and shows once per mob per 60 s (setting). Mobs can also be wanted on their own: `/sw alert mob add <npcID|target>`, `mob del`, `mob list`, or the "Add target" button. Units with a hidden (secret) identity, players and pets are skipped.
- **Wanted drop.** When a wished item is in your loot window or in your own "You receive loot" message, the toast says "Got <Item>". Optional "Remove from wishlist when looted" (off by default). Optional sound (off by default).
- New window section **Alerts** with the settings, a "Test alert" button and the wanted-mob list. Commands `/sw alert on|off|test|status|nameplates on|off|sound on|off|remove on|off|mob ...`, plus an alerts line in `/sw status`. No events are registered while alerts are off.
- **Vendor learning.** Opening a merchant window records the vendor (name, zone, your position on a 0.5 % grid, the item ids sold) in the learned data; about 2000 vendors, the oldest are dropped. Secret GUIDs, item links and positions are skipped.
- **Quest learning.** The quest offer and turn-in frames record the quest title, giver, turn-in npc and item rewards (choices and fixed rewards); about 3000 quests.
- **`/sw item <item link|id>`** prints all known sources of an item: drops (top 5, % and origin), vendors and quest rewards. `Seekwell.Sources.ForItem(itemID)` gives the same vendor and quest sources to other modules.
- **Zone view.** New window section Zone and `/sw zone`: mobs known in the current zone with levels, kills and wished drops (starred, listed first; at most 30 rows), the wished items obtainable in the zone, the vendors learned there, and honest empty states. Zone and vendor lines in `/sw status`.
- **Opt-in sharing of learned drops** (off by default; Net/Share.lua). When on, after a loot window Seekwell sends your learned totals for that mob to party / raid and / or guild as an addon message (prefix `SWKL`, `v1|npcID|kills|itemID:drops,...`, at most 240 bytes, split by items, at most 40 items): only npc ids, kill counts and item ids with counts, nothing about you. At most 1 message per 3 s and 20 per minute, nothing in combat (resumes afterwards) or inside instances. Received data is validated strictly (version, id and count ranges, drops <= kills, length, item count, secret values, own echo, 30 messages per sender per minute), stored apart from your own data (`SeekwellDB.shared`, about 5000 npcs, 20 senders per npc, oldest dropped), and each sender's contribution is replaced, never added twice (one new snapshot per sender and npc per day). Shared rows appear as "shared (N players)" below Forever, your learned data and Classic estimates, and only from 5 kills. New window section Sharing (explanation, switch, party / guild channels, counters, "Clear shared data"), `/sw share on|off|status|clear`, a share line in `/sw status`. The Settings checkbox now switches the same thing. `Seekwell.Registry.RegisterExtra` lets a module add rows below the built-in sources.
- **Map pins for a hunt** (`/sw hunt <item link|item id|mob name|npc id>`, `/sw hunt wish`, `/sw hunt off`; window section Map): world map pins through Blizzard's map data provider, one dot per 40-yard cluster with a count, coloured by drop % (grey < 1, white 1–10 or unknown, green 10–30, gold > 30). Tooltip: mob, level range, drop % with origin, "position learned from your loot (approximate)". Left-click sets a waypoint (Blizzard, TomTom when installed, else coordinates in chat); right-click hides that mob for this character (`/sw map unhide`). `/sw map [on|off]` toggles pins. Up to 12 dots on the minimap while a hunt is active. The hunt is kept per character.
- **Mob positions are learned only from your own loot**: each loot window stores where you stood (0.5 % grid, up to 64 spots per mob and zone, `SeekwellDB.learned.spawn`); secret or unknown positions are skipped and no coordinates are bundled. A mob with no learned position gets no pin, just a chat note. Settings `settings.map`: `enabled` on, `minimap` on, `minPct` 0, `cellYards` 40. `/sw reset learned` clears positions too.

## Release 0.1.2

- Item tooltips: when another addon (Tinny) already added a "Drops from" list, Seekwell skips its own lines so the sources are not listed twice. Setting "Skip ours when the tooltip already has a Drops from list" (on by default; turn it off to always show ours).

## Release 0.1.1

- When TnnysMobLoot is not loaded (for example disabled on the character) the target panel now says so and how to enable it, instead of "no drop data known".

## Release 0.1.0: first version (milestones M0 + M1)

- **Target drops on a key** (Key Bindings > AddOns > Seekwell > "Show my target's drops", also `/sw target` and right-click on the minimap button). This opens a small movable panel with the drop table of the mob in target, or the one under the mouse when nothing is targeted. Each row has the icon, the name in its quality colour, the drop chance and where the value comes from (Forever n=…, Classic estimate, learned). It also shows a tick when you own the item, a star for the wishlist and a marker for quest items. Rows are sorted by drop chance and the list scrolls. The panel follows the target, closes with Escape and works in combat. Players, pets and units with a hidden (secret) identity get a clear message.
- **Tinny data bridge.** Reads the runtime tables `TnnysMobLoot_Forever` and `TnnysMobLoot_Starter` only when a mob or an item is looked up. A small cache holds the parsed data. Nothing is copied or saved. Forever data beats Classic estimates. Percentages are never invented. Without Tinny, Seekwell says "Tinny data not available" and learned data still works.
- **Learning from loot.** Every loot window records which creature dropped which item, counting each corpse once. Seekwell stores item ids, kill counts and the zone (no positions), up to about 20 000 mobs with the oldest pruned. Secret values are skipped.
- **Item tooltips.** Up to 3 "Seekwell: Mob 12.5 %" lines (setting 1–5), Forever and learned sources before Classic estimates. They are shown even when Tinny is installed and can be turned off.
- **Wishlist per character.** Click a row in the target panel to star an item. The Wishlist section of the window lists the best sources (up to 5 mobs).
- **Window** in the Wayfarer / BetterBackpack layout with four sections: Target, Wishlist, Learned (counts, size, *Clear learned data* with a confirmation) and Settings (minimap button, tooltip lines and count, Classic estimates, hide quest items, learning on or off, and a "share learned data" checkbox that is off by default and does nothing yet).
- **Minimap button.** Left-click opens the window, right-click opens the target panel, drag moves it.
- **Commands:** `/sw` or `/seekwell` with `help`, `target`, `status`, `probe` (which client APIs exist, Tinny tables and counts, whether the target's GUID is secret), `minimap`, `reset`, `reset learned` and `dev on|off`.
- Every handler is error-guarded and reports to ForeverErrorLog (`Seekwell:` prefix). Nothing heavy runs at login, and there is one chat line at login.
