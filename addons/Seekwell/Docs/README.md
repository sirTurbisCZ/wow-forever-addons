# Seekwell

An addon for **World of Warcraft Forever** that answers "what drops from this mob, and where do I find this item?". Press a key with a mob in target and you get its drop table. Item tooltips show the best sources. Seekwell also learns from your own loot as you play.

## Install

1. Extract the addon so that you get `Interface/AddOns/Seekwell/`.
2. Enable it at character select and log in. A **new addon needs a full game restart** the first time; `/reload` is not enough.
3. Look for `[Seekwell] loaded v0.5.5 · /sw · Tinny data: yes` in chat (one line) and a small spyglass button at the minimap.
4. Optional but recommended: **Tnny's Mob Loot** (TnnysMobLoot). Seekwell reads its drop data while you play. Without it, Seekwell shows only what you have learned yourself.

## Set up the hotkey

**Game Menu > Options > Key Bindings > AddOns > Seekwell > "Show my target's drops"**. Pick any key. The key opens and closes the target panel. The settings window (Target section) shows the key you chose.

## Overview (version 0.5.5)

- **Browser** (left-click the minimap button or `/sw`): search items, mobs and dungeons on the left, details and a zone map with pins on the right. Tabs Search, Wishlist and Zone. Right-click the button for settings, Shift+click for the target panel.
- **Map pins** on the world map, minimap and the browser preview: silver dots for mob spots, a cyan rim for spots you learned yourself, violet pins for dungeon entrances.
- **Wishlist** with quantities and automatic tick when you own enough, **alerts** for wanted mobs and drops, **zone view**, **learning** from your own loot, positions, vendors and quests.
- **Forever content**: dungeons from ForeverDungeonJournal, optional forever-db data, Forever-only items marked with an F.
- `/sw selftest` checks every part, `/sw perf` shows memory and CPU per addon.

## What the target panel does

### My target's drops (the hotkey)

The key, `/sw target` or Shift+click on the minimap button opens a small panel for the mob in your **target**. With no target it uses the mob **under the mouse**. The panel shows:

- a header with the mob's name and level, and how much data exists for it: `Forever n=55` (kills measured by the Forever community), `learned 3 kills` (yours) and `Classic estimate`;
- one row per item: icon, name in its quality colour, drop chance, and where the value comes from:
  - **Forever n=…**: measured on Forever (from Tinny's data);
  - **Classic estimate**: an estimate from the original Classic database (from Tinny's data). It can be wrong for content that Forever changed;
  - **learned a/b**: your own loot, a drops in b kills;
  - **—**: unknown. Seekwell never makes up a percentage;
- a **tick** when you already own the item (bags and bank), a **star** when it is on your wishlist, and a **quest marker** for quest items;
- rows sorted by drop chance. Scroll with the mouse wheel when the list is long.

Hover a row to see the item tooltip. **Click** a row to star or unstar it for your wishlist. **Shift+click** links the item in the chat box while the chat box is open.

The panel follows your target while it is open. When you lose your target (for example after looting) it keeps showing the last mob. You can drag it, and it remembers where you put it. **Escape** closes it, and it works in combat. Players, pets and units whose identity the game hides (secret values, for example in some instances) get a short message instead of a list.

### Item tooltips

Item tooltips get up to 3 lines (you can set 1 to 5) such as `Seekwell: Kobold Vermin 12.5 %`. Forever and learned sources come first, in blue. Classic estimates come after them, in grey. These lines are shown even when Tinny's own tooltip is on. You can turn them off in the settings.

### Learning from your loot

Each time you open a loot window, Seekwell notes which creature dropped which item. It counts each corpse once, so re-opening the same corpse or skinning it is not a new kill. A corpse with only money still counts as a kill. Seekwell stores only item ids, kill counts and the zone (map id): no positions and no item links. It keeps at most about 20 000 mobs and drops the ones you saw longest ago. Loot whose source the game hides (secret values) is skipped.

### Wishlist (per character)

Star items in the target panel. The **Wishlist** section of the window lists them with their best known sources, up to 5 mobs with drop chances. Each character has its own wishlist.

### Window and minimap button

- **Left-click** the minimap button opens the browser. **Right-click** opens the settings. **Shift+left-click** opens the target panel. **Drag** moves the button around the minimap (the position is saved).
- Window sections: **Target** (open the panel, the key you chose), **Wishlist**, **Learned** (how much is stored, *Clear learned data* with a confirmation), **Settings**.

## Commands

| Command | What it does |
|---------|--------------|
| `/sw` | Open or close the window |
| `/sw target` | Show what drops from your target (same as the key) |
| `/sw status` | Version, Tinny data (counts, date), learned data, wishlist size |
| `/sw selftest` | Checks every piece in the running game: one PASS / WARN / FAIL / SKIP line each and a summary (changes nothing you would notice) |
| `/sw probe` | Which client APIs exist, Tinny tables and counts, whether your target's GUID is secret |
| `/sw minimap on` / `off` / `reset` | The minimap button |
| `/sw reset` | Restore default settings (learned data and wishlist stay) |
| `/sw reset learned` | Forget all learned loot data |
| `/sw dev on` / `off` | Debug output (off by default) |
| `/sw help` | Command list |

`/seekwell` works the same as `/sw`.

## Settings

Stored in `SeekwellDB.settings`. The wishlist is in `SeekwellCharDB.wish`, one per character.

| Key | Default | Meaning |
|-----|---------|---------|
| `minimap.show` / `minimap.angle` | true / 200 | Button visibility and position |
| `tooltip.enabled` / `tooltip.max` | true / 3 | "Drops from" lines on item tooltips, and how many (1–5) |
| `classic` | true | Include Tinny's Classic estimates |
| `hideQuest` | false | Hide quest items in drop lists |
| `learn` | true | Learn from your loot windows |
| `share` | false | Share learned data with group / guild (see Sharing; `shareChannels` party / guild, `shareStats` counters in status) |
| `dev` | false | Debug output |
| `panel` | centre right | Target panel position |

## Release 0.2.0

- **Wishlist alerts ("hunt mode")**: a toast "Wanted: <Mob> drops <Item> (12.5 %)" when a mob that drops a wished item is your target or under the mouse (nameplates optional), once per mob per 60 s; "Got <Item>" when a wished item drops, optionally removing it from the wishlist. Add mobs you want on their own with `/sw alert mob add <npcID|target>`. Settings in the window's Alerts section (`settings.alerts`: `enabled` on, `wantedMob` on, `wantedDrop` on, `nameplates` off, `sound` off, `removeOnLoot` off, `throttleSec` 60). Commands: `/sw alert on|off|test|status|nameplates on|off|sound on|off|remove on|off|mob add|del <npcID|target>|mob list`.
- **Vendors and quests**: Seekwell learns the vendors whose window you open (name, zone, your position on a 0.5 % grid, the item ids they sell; about 2000 vendors) and the quests you are offered or turn in (title, giver, item rewards; about 3000 quests). Switches in the Zone section (`settings.zone.vendors`, `settings.zone.quests`, both on; the main "learn" switch turns them off too). Secret values are skipped. `/sw reset learned` clears them.
- **`/sw item <item link|id>`**: every known source of an item in chat: the best 5 drops with % and origin, learned vendors (zone and coordinates) and learned quest rewards.
- **Zone view** (window section Zone, `/sw zone`): the mobs known in your current zone (from your loot, and from learned spawns when available) with level range, your kills and the wished items they drop (star; these mobs come first), a summary of the wished items obtainable here, and the vendors learned in this zone. It refreshes on zone change while the section is open.
- **Map pins for a hunt** (`/sw hunt <item link|item id|mob name|npc id>`, `/sw hunt wish`, `/sw hunt off`; window section Map): world map pins through Blizzard's map data provider, one silver dot per 40-yard cluster with a count (the drop % is in the tooltip). Tooltip: mob, level range, drop % with origin, and where the position comes from: "position learned from your loot (approximate)", "Classic spawn data (approximate)" or "learned + Classic spawn data". Left-click sets a waypoint (Blizzard, TomTom when installed, else coordinates in chat); right-click hides that mob for this character (`/sw map unhide`). `/sw map [on|off]` toggles pins. Up to 12 dots on the minimap while a hunt is active. The hunt is kept per character.
- **Mob positions are learned from your own loot**: each loot window stores where you stood (0.5 % grid, up to 64 spots per mob and zone, `SeekwellDB.learned.spawn`); secret or unknown positions are skipped. A mob with no known position gets no pin, just a chat note. Settings `settings.map`: `enabled` on, `minimap` on, `minPct` 0, `cellYards` 40, `bundled` on.
- **Classic spawn points (optional addon Seekwell_Locations)**: a separate, load-on-demand data addon with original Classic spawn points (about 3 770 mobs, pfQuest / CMaNGOS classic-db, GPL-3.0). Seekwell loads it the first time it needs a position (never at login, never in combat) and adds its points to the pins of mobs you have not looted there (points within 1.5 % of a learned spot are skipped). Original Classic spawns only: mobs new or moved on Forever are missing. `/sw locations on|off|status` (setting `map.bundled`); `/sw status` shows a line for it. Delete the Seekwell_Locations folder to drop it; Seekwell works without it. `/sw reset learned` clears positions too.
- **Sharing (opt-in, off by default)**: turn it on in the window's Sharing section or with `/sw share on`. After each loot window your learned totals for that mob (npc id, your kill count, item ids and how often they dropped; nothing about you) go to your party / raid and / or guild (`settings.shareChannels.party` / `.guild`, both on), at most one message every 3 s, never in combat or inside instances. Data from other Seekwell users who also enabled sharing is kept separately, shown as "shared (N players)" below every other source and only from 5 kills; `/sw share clear` or "Clear shared data" removes it. `/sw share status` shows sent / received / rejected counters (this session) and the shared npc count. Shared numbers come from other players and can be wrong: treat them as hints.

## Where does an item drop?

Right-click a row in the target panel (or click an item in your wishlist, or type `/sw find linen cloth`) to open the **Item** section: all known mobs that drop it with chance and origin, the zones you have met them in and a button to show a mob (or all of them) on the map. Locations are the places where you looted those mobs yourself, plus original Classic spawn zones when Seekwell_Locations is installed.

## Search browser (0.3.1)

`/sw` (or a left click on the minimap button) opens the big window in **browser mode**: Search, Wishlist and Zone. The **Search** page has two panes. On the left, type part of an item or mob name (it searches after a short pause, Enter searches at once); the tabs **All / Items / Mobs** show how many of each match, and if your tab has nothing but the other one has, the status line tells you. **[+] Filters** opens "only with known location", "only wishlist", "min drop %" and "pin the selection on the map". The list scrolls with the mouse wheel; a pin icon marks results with a known location. An empty search lists your wishlist and the last 15 things you viewed.

Click a row and the right pane shows it: for an item every mob that drops it (%, origin, zones, **On map**, **Waypoint**), vendors and quest rewards, the wishlist toggle with the wanted amount and **Link**; for a mob its full drop table (click an item to open it, star to wish it). Above the list a **map of the zone** shows the known spots (green = learned, gold = bundled Classic data; hover for the name, click for a waypoint); pick another zone in the row above the map. **Show on map** puts the hunt on the world map and minimap, **Open world map** opens it on that zone (not in combat), **Clear map** removes the pins, **Waypoint to nearest** points you to the closest spot. With "pin the selection" on (default), the map pins simply follow what you select. **< Back** returns along the links you clicked. `/sw browse [text]` opens it prefilled; `/sw find <name>` selects an item or mob directly. The **Settings >** button at the bottom of the nav switches to the small **settings mode**; **< Browser** goes back.

## Forever content (0.4.0)

Content new in WoW Forever (items, mobs, dungeons that do not exist in Classic) comes from three places, all optional and read at runtime: **Tinny's Forever data** (measured drop rates, Forever-only npcs), **ForeverDungeonJournal** (dungeons, bosses and their loot, dungeon quests and their reward items, entrance positions) and **your own play** (loot, vendors, quest rewards, dungeon entrances you walk into).

- Search has a **Dungeons** tab (`/sw dungeon [name]`): pick a dungeon to see its bosses (click one for its loot), its quests with reward items, its entrance on the zone map and an **Open in DungeonJournal** button.
- Items from a journal boss or dungeon quest show "Seekwell: Hall of Thanes — Boss" in the tooltip, a "Dungeon:" row in the item detail, a `dungeon:` / `quest:` line in `/sw item` and a "Dungeon Journal" line in the wishlist. The drop chance is unknown ("—").
- Dungeon entrances are violet pins on the world map, minimap and map preview when you hunt an item from that dungeon or the dungeon itself; click for a waypoint. Dungeons the journal cannot place get the entrance you used last time (your last outdoor position before the loading screen).
- Forever-only content has a gold **F** in the lists and "Forever" in the detail header. **[+] Filters > Forever content only** or `/sw forever on|off` shows only that; `/sw forever` lists the active bridges (also in Settings > Forever). Turn the journal bridge off with Settings > Forever (`settings.forever.dj`).
- Open-world spawn spots of Forever-new mobs are still known only from your own loot.

## Map pins (0.4.1)

| Part | Meaning |
|------|---------|
| Disc colour | drop chance: grey < 1 %, white 1-10 %, green 10-30 %, gold > 30 %, light blue = unknown |
| Glyph | skull = mob, coin = vendor, yellow ! = quest, portal = dungeon entrance |
| Ring | cyan = a spot you learned yourself, thin dark = Classic spawn data, violet = dungeon entrance |
| Number | several spots clustered into one (bigger pin) |

About 20 px on the world map (scaled with the zoom), 16 px on the minimap, 15 px in the browser preview. Hover: bigger with a glow and the usual tooltip. Left click: waypoint; right click (world map): hide that mob.

## What has a location, and what has not

Positions come from two places: your own loot (and what group members share) and the optional **Seekwell_Locations** addon with the original Classic spawn points of about 3770 NPCs. Not covered by that data: mobs new in Forever, Alterac Valley, mobs inside dungeons and raids, and skinning / world drops. Such a mob shows "location not known yet" and a disabled **On map** button until you loot it once. The item page says how many of its mobs are located ("Locations known for 12 of 150 mobs ..."), and **Located first** (on by default) lists the located ones first within each origin group.

## What it does not do yet

- No recipe or gathering sources (GatherLite nodes are not read), and no continent-level summary pins.
- Mob positions are those you learned yourself by looting, plus (with the optional Seekwell_Locations addon) original Classic spawn points, which can be wrong for Forever.

## ForeverDB data (0.5.0, optional)

[forever-db](https://github.com/foreverfraddons/forever-db) is a merged WoW Forever database (about 15 800 npcs, 32 000 items with names, 11 000 drop tables, 3 900 vendors, 6 300 quests, spawn positions for 15 900 npcs including Forever-new zones, 232 dungeon entrances). When its data addon is installed, Seekwell uses it as the **primary source for Forever content**: drops of Forever-new mobs, Forever-only item and mob names in search, spawn pins in new zones, vendors and quest rewards.

- **Install:** download the data files `ForeverDB.lua`, `ForeverDB_2.lua`, `ForeverDB_3.lua` and `ForeverDB_4.lua` from the `ForeverDB` folder of the forever-db repository and put them into `Interface/AddOns/ForeverDBData/`, together with a `ForeverDBData.toc` that has `## Interface: 16001`, `## Title: ForeverDB data`, `## LoadOnDemand: 1` and the four file names. The folder must be named **ForeverDBData** (or `ForeverDB_Data`): the game folder `ForeverDB` is usually a different addon (ForeverDB.net helper) and is used only if it is LoadOnDemand and really contains the data layout. The files are GPL-3.0 data; keep the repository's `LICENSE-DATA.txt` beside them.
- **Runtime only:** Seekwell reads the global `ForeverDB` after loading it on demand (first search, hunt, target panel or `/sw fdb`, never at login or in combat). Nothing is copied into Seekwell or its saved data. The files are about 12 MB, but the loaded Lua tables take roughly 60 to 100 MB of memory, so turn it off with `/sw fdb off` on a small machine. Indexes are built in small time slices.
- **Optional:** without it everything works as before (Tinny, your loot, Seekwell_Locations). With it, Seekwell_Locations is no longer needed.
- `/sw fdb status|on|off|reload`, setting `settings.forever.fdbData` (Settings > Forever, on by default, only used when the data addon is installed).
- **Licence:** the merged data is **GPL-3.0**. Its sources (LICENSE-DATA.txt): QuestieDB (WoW Forever, GPL-3.0), VMaNGOS world database (GPL-2.0-or-later), cMaNGOS classic-db (GPL-3.0), pfQuest database (MIT), AllTheThings (MIT), WoW Forever client tables (Blizzard game data), LegacyForever (GPL-3.0-or-later), Shortest Path Forever (GPL-3.0-or-later), Drop Tables (CC BY-SA 4.0, incl. Blackthornes Farmer MIT, EG Link CC BY 4.0, Everloot CC BY-SA 4.0), plus in-game recordings.

## Data and credits

- Seekwell **bundles no drop data**. Its numbers come from:
  - **Tnny's Mob Loot** (by Tony Perez), read while you play from its loaded data tables. Tinny's Forever rates come from Everloot contributors (everloot.app, CC BY-SA 4.0). Its Classic estimates come from the CMaNGOS classic-db project (GPL-3.0). Nothing is copied into Seekwell's saved data, and Tinny's own saved settings are never read;
  - your own loot windows;
  - optionally the **forever-db** data addon (ForeverDBData, by Fatedfr / foreverfraddons, GPL-3.0; sources listed above), read at runtime only.
- Nothing is sent anywhere unless you turn on sharing (off by default), and no files are written: addons in the Forever client cannot access files.
- Optional: **ForeverErrorLog** collects Lua errors (`Seekwell:` prefix).

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| No button at the minimap | `/sw minimap reset` |
| "Tinny data not available" | Install or enable Tnny's Mob Loot. Learned data works without it |
| The key does nothing | Set it under Key Bindings > AddOns > Seekwell |
| "The game hides this unit's identity" | Expected in some places (secret values). Nothing can be looked up there |
| Errors | `/felog list` if Forever Error Log is installed |
