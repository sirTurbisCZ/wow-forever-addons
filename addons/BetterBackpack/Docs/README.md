# BetterBackpack

Category-lane bags for **World of Warcraft Forever** (Interface 16001) with combat-safe item use.

## Install

1. Download `BetterBackpack-*.zip` from [Releases](https://github.com/sirTurbisCZ/wow-forever-addons/releases) and extract so you get `Interface/AddOns/BetterBackpack/`.
2. Enable it at character select, then `/reload`. Expect `[BetterBackpack] loaded v…` in chat.

**B** (and the backpack key) opens BetterBackpack instead of Blizzard's combined bags. Clicking a single bag in the bag bar still opens Blizzard's own bag window (keyring and reagent bag included).

## Lanes

Items are grouped into lanes: Junk, Consumables, Recipes, Materials, Gems, Gear, Quest, Keys, Containers, Other, Trash (off by default) and your own custom lanes. Click a lane header to collapse it. The window size is based on the full bag with every lane expanded; search, filter and collapse do not resize it.

**Drag to teach:** pick up an item and drop it on another lane header (or on an item in that lane). The item stays in its slot and the choice is remembered. Drop it on its natural lane again to forget. **Everything you teach is saved per character.**

### Junk lane and selling

- Junk holds grey items plus anything you drag into it. The lane is always visible, even when empty, so you can drop items on it.
- **Plain right-click** on an item at a vendor sells it; at a mailbox it attaches the item. (Auction house selling is not supported by this client's API.)
- **Shift+right-click** on a stacked icon at a vendor or mailbox moves **all** physical stacks of that item.
- **Ctrl+Shift+right-click** on a lane header at a vendor, mailbox or bank moves the whole lane. The **Junk** lane sells everything in it, whatever its quality. Other lanes keep a safety filter (quest items, green or better, unknown quality are skipped). The **Trash** lane is never sold.
- Optional **auto-sell** at the vendor (Settings → Features): grey items per character, optionally the whole Junk lane and items you marked.

### Trash lane (destroy)

Off by default (Settings → Lanes). Drop an item on the Trash header: it is destroyed, and future loot of the same item is destroyed on your next click in the bag.

- **Per character.** The list of auto-destroyed items belongs to the character.
- A confirmation is asked before destroying (turn it off with "Don't ask again" in Settings → Trash).
- **Settings → Trash** lists everything this character destroys; **Keep** removes an item from the list. Never destroys quest items, green or better quality, or the Hearthstone.
- Works out of combat only.

## Item level and BoE

Weapons and armor show their item level as a small number in the top-left corner of the slot. Green or better gear that is not yet bound and binds when equipped shows a gold **BoE** in the top-right corner. Both labels can be switched off separately in Settings → Features. During combat only values already seen are shown; new items get their label after combat.

## Settings (`/bb settings`)

| Section | What |
|---------|------|
| Lanes | Turn built-in lanes on or off (incl. Recipes and Trash) |
| Custom lanes | Create, rename, delete your own lanes |
| Trash | Destroy confirmation and the list of auto-destroyed items |
| Learned | Every item you taught: icon, name, the lane it is in and its default lane, with **Forget** |
| Features | Item level and BoE labels, stack merge display, auto-sell and other toggles |

Long lists scroll with the mouse wheel; the scroll bar appears only when needed.

## Combat

- **B** works in combat: the bag is kept ready (invisible while closed) and shown with alpha only; no protected frames are created or moved. While closed it shows no tooltips.
- **Esc** closes open bags first; the next Esc opens the game menu.
- Bags opened by a vendor, mailbox, auction house or bank close with that window if they were closed before.
- Sorting, tidy and Trash work out of combat only.

## Slash commands

| Command | Action |
|---------|--------|
| `/bb` | Toggle bags |
| `/bb on` / `/bb off` | Enable, or restore Blizzard's bags |
| `/bb sort` / `/bb tidy` | Out-of-combat tidy (`SortBags` plus stack merge) |
| `/bb settings` | Settings panel |
| `/bb search <text>` | Filter by name or item id (empty clears) |
| `/bb filter <lane\|all>` | Show only one lane |
| `/bb pin <itemID>` | Toggle a ghost pin for an item you do not own |
| `/bb custom add <name>` / `del <id>` | Create / remove a custom lane |
| `/bb assign <itemID> <lane\|clear>` | Set or clear a lane rule for an item |
| `/bb layout [lanes\|dense]` | Layout mode |
| `/bb merge [on\|off]` | Visual stack merge |
| `/bb trashtest` | Check that destroying still works on this client |
| `/bb reset` | Reset settings and **this character** (other characters are kept) |
| `/bb reset all` | Reset everything, every character |
| `/bb safe` | Release to Blizzard's bags |
| `/bb dump` | Status, errors and the action trace tail |
| `/bb selftest` | Wiring self-check (does not sell or move items) |
| `/bb help` | Full list |

Also `/betterbackpack`.

## Notes

- Optional: **ForeverErrorLog** collects Lua errors.
- Do not run next to another addon that replaces the bags (for example **BagShelves** or **CombinedBags**); disable the other one. `/bb bagkey` shows whether the **B** key is ours (`ToggleBackpack ours=true`).
- The frame position is fixed by the client.
- Bulk and vendor diagnostics (the `ACTION` trace) go to SavedVariables, not chat: `WTF/Account/<Account>/SavedVariables/BetterBackpack.lua`.

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| **B** opens Blizzard's bags | `/bb bagkey`; another bag addon is probably active |
| Item not sold with Ctrl+Shift lane click | Items outside the Junk lane are protected (quest / green+); drag the item into Junk first |
| An item disappears | `/bb assign <itemID> clear`; check Settings → Learned |
| Errors or odd layout | `/bb safe`, then `/felog list` if Forever Error Log is installed |
