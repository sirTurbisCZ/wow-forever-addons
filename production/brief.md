# Playtest brief — BetterBackpack 0.3.5

**Bug:** gear/broom still wrong size vs Close.

**Fix:** create once as `UIPanelCloseButtonNoScripts`; after layout `SetSize(close:GetWidth(), close:GetHeight())` on both; chat logs `chrome sizes close=… broom=… gear=…` once; no recreate loops.

**Done when:** `/reload` → `loaded v0.3.5` · chat shows equal sizes · gear=broom=X visually.
