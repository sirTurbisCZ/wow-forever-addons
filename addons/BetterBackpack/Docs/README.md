# BetterBackpack

Category-lane bags for **World of Warcraft Forever** (Interface 16001) with combat-safe RMB.

## Install

1. Put this folder in `Interface/AddOns/BetterBackpack/` (or symlink via `./scripts/link-addon.sh BetterBackpack`).
2. Enable at character select if needed.
3. `/reload` in game — chat should show `loaded v0.3.2` (visible gear left of broom, used/total N/M, bag-bar XOR).

## Slash

| Command | Action |
|---------|--------|
| `/bb` | Toggle bags |
| `/bb on\|off` | Enable or restore Blizzard bags |
| `/bb sort` | OOC tidy (`SortBags`) |
| `/bb dump` | Status + error ring |
| `/bb safe` | Safe mode → Blizzard |
| `/bb reset` | Defaults |
| `/bb selftest` | Wiring check (still need 1× manual combat RMB) |
| `/bb bags` | Reagent / free-space probe |

Also `/betterbackpack`.

## Playtest (T0–T3)

1. `/reload` → version print; B opens lanes; CombinedBags not visible.
2. Enter combat with bags open → RMB potion/Q-item works.
3. Open B mid-combat → lanes usable; no CombinedBags ghost.
4. Spam B 5× in combat → leave combat OK without `/reload`.

## Notes

- Never hides CombinedBags (parks alpha / off-screen).
- Optional: ForeverErrorLog for error capture.
- Disable BagShelves if both are present.
