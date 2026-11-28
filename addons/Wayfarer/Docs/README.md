# Wayfarer

One addon for **World of Warcraft Forever** with one button at the minimap and one settings window. It collects small tools that make the field easier to read and play.

## Install

1. Download `Wayfarer-*.zip` from [Releases](https://github.com/sirTurbisCZ/wow-forever-addons/releases) and extract it so you get `World of Warcraft/_forever_/Interface/AddOns/Wayfarer`.
2. Enable it at character select and log in. A **newly installed addon needs a full game restart**; `/reload` is not enough the first time.
3. Expect `[Wayfarer] v… · /wf` in chat and a small round button at the minimap.

Problems or ideas: [Issues](https://github.com/sirTurbisCZ/wow-forever-addons/issues).

## What it does

### Party and raid marks on nameplates

Party and raid members are easy to tell apart from everyone else, in a city or in the field:

- a **coloured outline** around the health bar,
- a small **tag** left of the bar: **P** for party, **R** for raid.

The colour is the **class colour**, or **one custom colour** for party and one for raid (your choice in the settings). Blizzard's own health bar is never recoloured; the marks are extra frames next to it, so they work in combat too. Marks are created out of combat; a nameplate seen for the very first time in combat gets its mark afterwards.

Friendly **player nameplates must be enabled** in the game options (Options > Nameplates) for players to show nameplates at all; the settings window shows a hint while they are off. Marks are refreshed shortly (0.2 s) after a roster change, not once per event.

### One-key fishing

Pick a key in **Settings → Fishing** (click the button, press the key; **Clear** removes it) or with `/wf fish key F`. Each press does **one** thing:

1. a fishing loot window is open (Auto Loot off): take the loot,
2. your bobber is the soft-interact target: reel in (the game's Interact Key),
3. otherwise: cast Fishing (not in combat, swimming, mounted or in a vehicle).

Wayfarer never hooks the fish for you: press the key when you see or hear the splash. The key is a temporary override binding; your own key bindings are not changed, and the override is released when you turn the module off or clear the key. Binding changes wait until combat ends. By default the key is taken only while a fishing pole is equipped. While a cast runs, Wayfarer can raise the interact reach to the bobber and (optional **Louder splash**) play sound effects at full volume; both are put back when the cast ends. If another addon with its own one-key fishing is active, the settings and `/wf fish status` warn that the two may conflict; turn the other one off. EasyFish overlaps with SKTools Easy Fishing and with dedicated fishing addons: use only one of them on the same key.

### Procs and timers (mage, shaman, druid, priest, warlock)

A small HUD of its own (it never attaches to Blizzard frames):

- **Arcane Blast meter:** 4 pips and a timer. In combat the game may hide your own stack count from addons, so the count is predicted from your Arcane Blast casts and corrected from the real aura whenever it is readable (always out of combat).
- **At 4/4:** the meter pulses gold and shows a **dump** hint with the Arcane Wrath and Arcane Missiles icons. Optionally an extra glow frame is drawn over the matching action bar buttons (off by default; the buttons themselves are not touched).
- **Proc icons:** Clearcasting, Missile Barrage and Presence of Mind, with the remaining time when readable. Spells this client does not know are skipped.
- **Other classes (proc icons only, no meter):** a proc icon is shown while its buff is up, with stacks and remaining time when readable.
  - Shaman: Clearcasting (Elemental Focus), Flurry, Nature's Swiftness.
  - Druid: Clearcasting (Omen of Clarity), Nature's Grace, Nature's Swiftness.
  - Priest: Inner Focus, Spirit Tap, Power Infusion.
  - Warlock: Shadow Trance (Nightfall).
  - The buff is found by spell id or by name (English and Czech client text). The ids are not verified on Forever yet; if an icon does not appear, run `/wf proc auras` while the buff is up and report the id and name.
- Only your own class is tracked. For other classes (warrior, rogue, hunter, paladin) the module does nothing (`/wf proc status` says why).
- Place it: **Unlock** (or `/wf proc unlock`), **Test mode** shows fake 0–4 stacks (mage) and lights up the proc icons one by one, out of combat, drag, then **Lock**. Scale 50–200 %.
- **Not verified in the Forever client yet:** the Arcane Blast window (assumed 18 s, carried over from an earlier addon) and whether a new cast refreshes it (assumed no). Both are learned from the real aura the first time it is readable and saved as `procHUD.abWindow` / `procHUD.abRefresh`; `/wf proc status` shows `default` or `learned`.

### Minimap button and settings

- **Left-click** the button: settings. **Right-click**: party marks on/off. **Drag**: move it around the minimap (the position is saved).
- The settings window has the options for every module.

## Commands

| Command | What it does |
|---------|----------------|
| `/wf`, `/wf settings` | Open or close the settings window |
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

## Procs in combat

In combat the game hides your auras from addons, so Wayfarer cannot read a proc buff then. Proc icons therefore come from a Blizzard-managed aura container (an `AuraContainer` frame bound to your character): the game itself draws icon, duration swipe and stack count, and the addon never reads the aura. The container follows a list of aura ids: the ids of your class's procs, plus every proc aura id Wayfarer sees while it is readable out of combat (saved, at most 40, so the next fight already knows it). `/wf proc add <spellId>` adds one by hand, `/wf proc ids` lists them. The container is built out of combat only (login, entering the world, end of combat). If the client has no such container, or refuses it, the old Wayfarer icons are used instead (out of combat they always work); `/wf proc container off` forces that.

Not yet verified in the game: that this client lets the container show your own auras in combat (it is known to work for party frames and nameplates, not yet for the player). Run `/wf proc diag` in combat with a proc up: `container=active ids=N unit=player` and `buttons made/shown` tell what happens; if proc icons are missing altogether, `/wf proc container off` brings the old icons back; if the container shows nothing in combat, the proc glow still marks Missile Barrage (glow on Arcane Missiles) and Shadow Trance (glow on Shadow Bolt). `/wf proc status` shows the container state and how many glow events arrived; `/wf proc auras` lists your auras with their ids.
