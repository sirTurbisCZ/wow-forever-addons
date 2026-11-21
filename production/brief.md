# Playtest brief — BetterBackpack 0.5.1

**Bug:** OpenOurs false ×16 + `lastBlocked SetFrameStrata` — bags won’t open (feels like crash).

**Fix:** `pcall` all EnsureMain `SetFrameStrata`; recover half-built named frame; stricter OnClick HasScript; throttle OpenOurs false spam.

**Keep:** chrome+/70 · NTH modules.

**Done when:** `/reload` → `loaded v0.5.1` → B opens bags.
