# Seekwell Locations (Classic spawns)

Optional, load-on-demand data addon for **Seekwell**. It ships original Classic mob spawn points
(about 3 770 npcs in 44 zones, ~400 KB) so Seekwell's map and minimap pins can show where a mob
lives even if you never looted it.

- Seekwell loads it the first time it needs a position (never at login, never in combat).
- Pins from this data say "Classic spawn data (approximate)" in their tooltip; positions learned
  from your own loot keep "position learned from your loot".
- `/sw locations on|off|status` toggles its use (setting `map.bundled`, default on).
- It covers original Classic spawns only; Forever-only mobs and moved spawns are missing.
  Alterac Valley npcs are left out (no zone map id).
- Delete the folder to remove it; Seekwell works without it.

Data: pfQuest (shagu) / CMaNGOS classic-db, GPL-3.0. See `DATA-CREDITS.txt` and `LICENSE.txt`.
Rebuild: `dev-tools/build_seekwell_locations.py` (outside the repo).
