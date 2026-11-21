--[[
  BetterBackpack.LayoutModes — lanes (default) vs denser grid columns (v1).
  profile.layoutMode = "lanes" | "dense"
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local LayoutModes = {}
BetterBackpack.Modules.LayoutModes = LayoutModes

local Config = BetterBackpack.Config

local function Profile()
  return Config.GetProfile()
end

function LayoutModes.Get()
  local m = Profile().layoutMode
  if m == "dense" then
    return "dense"
  end
  return "lanes"
end

function LayoutModes.Set(mode)
  if mode ~= "dense" then
    mode = "lanes"
  end
  Profile().layoutMode = mode
  local Layout = BetterBackpack.Modules.Layout
  if Layout and Layout.Relayout then
    Layout.Relayout()
  end
end

function LayoutModes.Toggle()
  if LayoutModes.Get() == "dense" then
    LayoutModes.Set("lanes")
  else
    LayoutModes.Set("dense")
  end
  return LayoutModes.Get()
end

--- Override columns for dense mode (still respects profile.columns floor).
function LayoutModes.Columns(base)
  base = tonumber(base) or 10 -- CombinedBags/BagShelves default
  if LayoutModes.Get() == "dense" then
    return math.min(16, math.max(base + 2, 12))
  end
  return base
end
