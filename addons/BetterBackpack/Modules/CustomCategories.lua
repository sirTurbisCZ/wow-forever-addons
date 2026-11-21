--[[
  BetterBackpack.CustomCategories — user lanes + hide defaults (v1).
  Hidden defaults still route items to Other (existing CategoryEnabled path).
  Custom cats: profile.customCategories = { { id, name, itemIDs = { [id]=true } } }
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local CustomCategories = {}
BetterBackpack.Modules.CustomCategories = CustomCategories

local Config = BetterBackpack.Config

local function Profile()
  return Config.GetProfile()
end

local function EnsureTables()
  local p = Profile()
  if type(p.customCategories) ~= "table" then
    p.customCategories = {}
  end
  if type(p.hiddenDefaults) ~= "table" then
    p.hiddenDefaults = {}
  end
  if type(p.itemRules) ~= "table" then
    p.itemRules = {}
  end
  return p
end

function CustomCategories.List()
  return EnsureTables().customCategories
end

function CustomCategories.IsDefaultHidden(key)
  if key == "other" then
    return false
  end
  local h = EnsureTables().hiddenDefaults
  return h[key] == true
end

function CustomCategories.SetDefaultHidden(key, hidden)
  if key == "other" or type(key) ~= "string" then
    return
  end
  local p = EnsureTables()
  p.hiddenDefaults[key] = hidden and true or nil
  -- Mirror into categories enable so Layout.CategoryEnabled stays consistent.
  if type(p.categories) ~= "table" then
    p.categories = {}
  end
  if hidden then
    p.categories[key] = false
  else
    if p.categories[key] == false then
      p.categories[key] = true
    end
  end
  local Layout = BetterBackpack.Modules.Layout
  if Layout and Layout.Relayout then
    Layout.Relayout()
  end
end

local function NormalizeId(id)
  local n = tonumber(id)
  if n then
    return n
  end
  return nil
end

function CustomCategories.Add(name)
  local p = EnsureTables()
  name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
  if name == "" then
    return nil
  end
  local id = "custom_" .. tostring((GetTime and math.floor(GetTime() * 1000)) or (#p.customCategories + 1))
  local entry = { id = id, name = name, itemIDs = {} }
  p.customCategories[#p.customCategories + 1] = entry
  return entry
end

function CustomCategories.Remove(id)
  local p = EnsureTables()
  for i = #p.customCategories, 1, -1 do
    if p.customCategories[i].id == id then
      -- Clear itemRules pointing at this cat.
      for itemID, rule in pairs(p.itemRules) do
        if rule == id then
          p.itemRules[itemID] = nil
        end
      end
      table.remove(p.customCategories, i)
      break
    end
  end
  local Layout = BetterBackpack.Modules.Layout
  if Layout and Layout.Relayout then
    Layout.Relayout()
  end
end

function CustomCategories.AssignItem(itemID, categoryId)
  itemID = NormalizeId(itemID)
  if not itemID then
    return
  end
  local p = EnsureTables()
  if not categoryId then
    p.itemRules[itemID] = nil
    p.itemRules[tostring(itemID)] = nil
  else
    p.itemRules[itemID] = categoryId
  end
  -- Also stash on the custom cat table for Settings UI.
  for i = 1, #p.customCategories do
    local c = p.customCategories[i]
    if type(c.itemIDs) ~= "table" then
      c.itemIDs = {}
    end
    if c.id == categoryId then
      c.itemIDs[itemID] = true
    else
      c.itemIDs[itemID] = nil
    end
  end
  local Layout = BetterBackpack.Modules.Layout
  if Layout and Layout.Relayout then
    Layout.Relayout()
  end
end

--- Before default classify: return custom category id/key or nil.
function CustomCategories.Resolve(itemID)
  itemID = NormalizeId(itemID)
  if not itemID then
    return nil
  end
  local p = EnsureTables()
  local rule = p.itemRules[itemID] or p.itemRules[tostring(itemID)]
  if type(rule) == "string" and rule ~= "" then
    return rule
  end
  for i = 1, #p.customCategories do
    local c = p.customCategories[i]
    if type(c.itemIDs) == "table" and (c.itemIDs[itemID] or c.itemIDs[tostring(itemID)]) then
      return c.id
    end
  end
  return nil
end

function CustomCategories.Label(key)
  local p = EnsureTables()
  for i = 1, #p.customCategories do
    local c = p.customCategories[i]
    if c.id == key then
      return c.name or key
    end
  end
  return nil
end

--- Extended order: defaults (minus hidden) + custom + other last.
function CustomCategories.ExtendOrder(baseOrder)
  local p = EnsureTables()
  local out = {}
  local seen = {}
  for i = 1, #baseOrder do
    local key = baseOrder[i]
    if key == "other" then
      -- defer
    elseif not CustomCategories.IsDefaultHidden(key) then
      out[#out + 1] = key
      seen[key] = true
    end
  end
  for i = 1, #p.customCategories do
    local id = p.customCategories[i].id
    if id and not seen[id] then
      out[#out + 1] = id
      seen[id] = true
    end
  end
  out[#out + 1] = "other"
  return out
end
