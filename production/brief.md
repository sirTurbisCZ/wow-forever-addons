# Playtest brief — BetterBackpack 0.1.9

**Goal:** Fix broken layout after 0.1.8 (content stretch + half-init); money/Úklid/stack.

**Evidence:** FElog older parse crash; SV lastBlocked SetToplevel (historical). Live break: content TOPLEFT+BOTTOMRIGHT+SetSize + fragile EnsureMain. Baganator disabled (conflict).

**Done when:** `/reload` → `loaded v0.1.9` · panel shows lanes · coins · N/M · Úklid sorts+stacks · stack counts visible.
