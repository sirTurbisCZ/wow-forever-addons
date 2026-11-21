# Playtest brief — BetterBackpack 0.2.3

**Goal:** Fix layout nil (EnsureTitleChrome); compact Úklid|Nastavení left of X; white stack counts >1.

**Evidence:** FElog `Layout.lua: attempt to call a nil value` — forward decl never assigned (`local function` shadowed).

**Done when:** `/reload` → `loaded v0.2.3` · bags open without layout error · chrome tight L of X · stacks>1 white · Settings Other tip.
