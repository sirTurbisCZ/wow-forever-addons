# Playtest brief — BetterBackpack 0.2.5

**Bug:** bag-bar click did not open/close BB (HookScript OnClick crashed hooks install; ToggleBag only parked).

**Fix:** safe OnClick hooks; ToggleBag/bag-bar XOR like B; OpenBag open+focus; CloseBag closes ours; one-shot chat log `hooks ok` / first `bag path`.

**Done when:** `/reload` → `loaded v0.2.5` + `hooks ok` · click bag N opens BB (slots for that bag highlighted) · second bag click closes · B still toggles · no HookScript errors in `/bb errors` or FElog.
