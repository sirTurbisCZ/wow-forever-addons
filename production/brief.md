# Playtest brief — BetterBackpack 0.1.3

**Goal:** B reliably opens/closes BetterBackpack only (session = source of truth).

**Evidence fixed:** `SetToplevel` ADDON_ACTION_BLOCKED; OnShow→Open + Toggle→Close empty UI.

**Avoid:** SetToplevel; OpenOurs from CombinedBags OnShow; OpenAllBags as open owner.

**Done when:** `/reload` → v0.1.3; B opens solid CENTER panel; one B closes; `/bb frame` shows shown=true.
