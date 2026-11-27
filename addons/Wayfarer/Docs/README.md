# Wayfarer

One addon for **World of Warcraft Forever** with one button at the minimap and one settings window. It collects small tools that make the field easier to read and play.

## Install

1. Download `Wayfarer-*.zip` from [Releases](https://github.com/sirTurbisCZ/wow-forever-addons/releases) and extract so you get `Interface/AddOns/Wayfarer/`.
2. Enable it at character select and log in. A **new addon needs a full game restart**, `/reload` is not enough the first time.
3. Expect `[Wayfarer] loaded v…` in chat and a small round button at the minimap.

## What it does (version 0.1)

### Party and raid marks on nameplates

Party and raid members are easy to tell apart from everyone else, in a city or in the field:

- a **coloured outline** around the health bar,
- a small **tag** left of the bar: **P** for party, **R** for raid.

The colour is the **class colour**, or **one custom colour** for party and one for raid (your choice in the settings). Blizzard's own health bar is never recoloured; the marks are extra frames next to it, so they work in combat too. Marks are created out of combat; a nameplate seen for the very first time in combat gets its mark afterwards.

Friendly **player nameplates must be enabled** in the game options for players to show nameplates at all.

### One-key fishing

Pick a key in **Settings → Fishing** (click the button, press the key; **Clear** removes it) or with `/wf fish key F`. Each press does **one** thing:

1. a fishing loot window is open (Auto Loot off): take the loot,
2. your bobber is the soft-interact target: reel in (the game's Interact Key),
3. otherwise: cast Fishing (not in combat, swimming, mounted or in a vehicle).

Wayfarer never hooks the fish for you: press the key when you see or hear the splash. The key is a temporary override binding; your own key bindings are not changed, and the override is released when you turn the module off or clear the key. Binding changes wait until combat ends. By default the key is taken only while a fishing pole is equipped. While a cast runs, Wayfarer can raise the interact reach to the bobber and (optional **Louder splash**) play sound effects at full volume; both are put back when the cast ends. If another addon with its own one-key fishing is active, the settings and `/wf fish status` warn that the two may conflict; turn the other one off.

### Procs and timers (mage)

A small HUD of its own (it never attaches to Blizzard frames):

- **Arcane Blast meter:** 4 pips and a timer. In combat the game may hide your own stack count from addons, so the count is predicted from your Arcane Blast casts and corrected from the real aura whenever it is readable (always out of combat).
- **At 4/4:** the meter pulses gold and shows a **dump** hint with the Arcane Wrath and Arcane Missiles icons. Optionally an extra glow frame is drawn over the matching action bar buttons (off by default; the buttons themselves are not touched).
- **Proc icons:** Clearcasting, Missile Barrage and Presence of Mind, with the remaining time when readable. Spells this client does not know are skipped.
- Only your own class is tracked; mage now, priest, shaman and druid later. For other classes the module does nothing (`/wf proc status` says why).
- Place it: **Unlock** (or `/wf proc unlock`), **Test mode** shows fake 0–4 stacks out of combat, drag, then **Lock**. Scale 50–200 %.
- **Not verified in the Forever client yet:** the Arcane Blast window (assumed 18 s, as in the old Retinue) and whether a new cast refreshes it (assumed no). Both are learned from the real aura the first time it is readable and saved as `procHUD.abWindow` / `procHUD.abRefresh`; `/wf proc status` shows `default` or `learned`.

### Minimap button and settings

- **Left-click** the button: settings. **Right-click**: party marks on/off. **Drag**: move it around the minimap (the position is saved).
- The settings window has the options for every module.

## Commands

| Command | What it does |
|---------|----------------|
| `/wf` | Open or close the settings window |
| `/wf marks on` / `off` | Party and raid marks |
| `/wf minimap on` / `off` / `reset` | The minimap button |
| `/wf fish on` / `off` | One-key fishing |
| `/wf fish key` / `key <KEY>` / `clear` | Show, set (e.g. `F`, `ALT-F`, `BUTTON4`) or remove the fishing key |
| `/wf fish status` | Fishing key, current binding, conflict note |
| `/wf proc on` / `off` | Procs and timers |
| `/wf proc test` / `unlock` / `lock` / `reset` | Place the HUD (fake stacks, drag, fix, default position) |
| `/wf proc status` | Why the procs HUD runs or not, stacks, learned timer |
| `/wf status` | What is enabled |
| `/wf reset` | Restore the default settings |
| `/wf help` | Command list |

Also `/wayfarer`.

## Settings

Stored in `WayfarerDB.profile`:

| Key | Default | Meaning |
|-----|---------|---------|
| `minimap.show` / `minimap.angle` | true / 215 | Button visibility and position |
| `partyMarks.enabled` | true | Marks on or off |
| `partyMarks.outline` / `badge` | true / true | Outline around the bar / P and R tag |
| `partyMarks.colorMode` | `class` | `class` or `custom` |
| `partyMarks.partyColor` / `raidColor` | green / orange | Colours used in `custom` mode |
| `partyMarks.thickness` | 2 | Outline thickness (1–4) |
| `procHUD.enabled` | true | Procs and timers on or off |
| `procHUD.meter` / `procs` / `dumpHint` | true / true / true | Arcane Blast meter / proc icons / dump hint at 4/4 |
| `procHUD.actionGlow` | false | Glow frame over matching action bar buttons |
| `procHUD.scale` / `locked` / `x` / `y` | 100 / true / 0 / -160 | HUD scale (%), lock, offset from the screen centre |
| `procHUD.abWindow` / `abRefresh` | — | Learned from the real aura (Arcane Blast duration, refresh on cast) |
| `easyFish.enabled` / `easyFish.key` | true / not set | One-key fishing; nothing is bound until a key is set |
| `easyFish.poleOnly` | true | Take the key only while a fishing pole is equipped |
| `easyFish.reach` / `easyFish.loud` | true / false | Raise the interact reach / sound effects at full volume while a cast runs |

## Coming next

- Procs and timers for priest, shaman and druid.
## Notes

- Optional: **ForeverErrorLog** collects Lua errors.
- Nothing is sent anywhere and no files are written; the Forever client has no file access for addons.

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| No button at the minimap | `/wf minimap reset` |
| No marks on players in a city | Enable friendly player nameplates in the game options; be grouped |
| Marks missing on a new nameplate in combat | They appear after combat |
| Errors | `/felog list` if Forever Error Log is installed |
