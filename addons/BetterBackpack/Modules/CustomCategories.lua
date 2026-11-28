--[[
  BetterBackpack.CustomCategories — user lanes + hide defaults (v1).
  Hidden defaults still route items to Other (existing CategoryEnabled path).
  Custom cats + rules targeting custom_* live per character (Config.GetCharProfile).
  Since schema 12 ALL item rules (built-in lanes, custom, Trash) live per character.
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local CustomCategories = {}
BetterBackpack.Modules.CustomCategories = CustomCategories

local Config = BetterBackpack.Config

local function Profile()
  return Config.GetProfile()
end

local function Char()
  return Config.GetCharProfile()
end

local function IsCustomLaneId(id)
  return type(id) == "string" and id:find("^custom_", 1) ~= nil
end


local function EnsureCharTables()
  local c = Char()
  if type(c.customCategories) ~= "table" then
    c.customCategories = {}
  end
  if type(c.itemRules) ~= "table" then
    c.itemRules = {}
  end
  return c
end

local function EnsureProfileTables()
  local p = Profile()
  if type(p.hiddenDefaults) ~= "table" then
    p.hiddenDefaults = {}
  end
  if type(p.itemRules) ~= "table" then
    p.itemRules = {}
  end
  return p
end

local function Changed()
  local Layout = BetterBackpack.Modules.Layout
  if Layout and Layout.WipeClassCache then
    Layout.WipeClassCache() -- lane rules changed: classification starts fresh (#56)
  end
  if Layout and Layout.Relayout then
    Layout.Relayout()
  end
  local Settings = BetterBackpack.Modules.Settings
  if Settings and Settings.Refresh then
    Settings.Refresh()
  end
  local Trash = BetterBackpack.Modules.Trash
  if Trash and Trash.RulesChanged then
    Trash.RulesChanged()
  end
end

function CustomCategories.List()
  return EnsureCharTables().customCategories
end

function CustomCategories.IsDefaultHidden(key)
  if key == "other" then
    return false
  end
  local h = EnsureProfileTables().hiddenDefaults
  return h[key] == true
end

function CustomCategories.SetDefaultHidden(key, hidden)
  if key == "other" or type(key) ~= "string" then
    return
  end
  local p = EnsureProfileTables()
  p.hiddenDefaults[key] = hidden and true or nil
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
  Changed()
end

local function NormalizeId(id)
  local n = tonumber(id)
  if n then
    return n
  end
  return nil
end

function CustomCategories.Add(name)
  local c = EnsureCharTables()
  name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
  if name == "" then
    return nil
  end
  local base = "custom_" .. tostring((GetTime and math.floor(GetTime() * 1000)) or (#c.customCategories + 1))
  local id, n = base, 1
  while CustomCategories.Label(id) do
    n = n + 1
    id = base .. "_" .. n
  end
  local entry = { id = id, name = name, itemIDs = {} }
  c.customCategories[#c.customCategories + 1] = entry
  return entry
end

function CustomCategories.Remove(id)
  local c = EnsureCharTables()
  for i = #c.customCategories, 1, -1 do
    if c.customCategories[i].id == id then
      for itemID, rule in pairs(c.itemRules) do
        if rule == id then
          c.itemRules[itemID] = nil
        end
      end
      table.remove(c.customCategories, i)
      break
    end
  end
  Changed()
end

function CustomCategories.AssignItem(itemID, categoryId)
  itemID = NormalizeId(itemID)
  if not itemID then
    return
  end
  local c = EnsureCharTables()
  local p = EnsureProfileTables()
  if not categoryId then
    c.itemRules[itemID] = nil
    c.itemRules[tostring(itemID)] = nil
    p.itemRules[itemID] = nil
    p.itemRules[tostring(itemID)] = nil
    for i = 1, #c.customCategories do
      local cat = c.customCategories[i]
      if type(cat.itemIDs) == "table" then
        cat.itemIDs[itemID] = nil
        cat.itemIDs[tostring(itemID)] = nil
      end
    end
  else
    -- Every lane (built-in, custom, Trash) stores its rule on the character.
    p.itemRules[itemID] = nil
    p.itemRules[tostring(itemID)] = nil
    c.itemRules[tostring(itemID)] = nil
    c.itemRules[itemID] = categoryId
    for i = 1, #c.customCategories do
      local cat = c.customCategories[i]
      if type(cat.itemIDs) ~= "table" then
        cat.itemIDs = {}
      end
      if cat.id == categoryId then
        cat.itemIDs[itemID] = true
      else
        cat.itemIDs[itemID] = nil
        cat.itemIDs[tostring(itemID)] = nil
      end
    end
  end
  Changed()
end

--- Before default classify: return custom category id/key or nil.
function CustomCategories.Resolve(itemID)
  itemID = NormalizeId(itemID)
  if not itemID then
    return nil
  end
  local c = EnsureCharTables()
  local rule = c.itemRules[itemID] or c.itemRules[tostring(itemID)]
  if type(rule) == "string" and rule ~= "" then
    return rule
  end
  for i = 1, #c.customCategories do
    local cat = c.customCategories[i]
    if type(cat.itemIDs) == "table" and (cat.itemIDs[itemID] or cat.itemIDs[tostring(itemID)]) then
      return cat.id
    end
  end
  return nil
end

function CustomCategories.Label(key)
  local c = EnsureCharTables()
  for i = 1, #c.customCategories do
    local cat = c.customCategories[i]
    if cat.id == key then
      return cat.name or key
    end
  end
  return nil
end

--- Extended order: defaults (minus hidden) + custom + trash + other last.
function CustomCategories.ExtendOrder(baseOrder)
  local c = EnsureCharTables()
  local out = {}
  local seen = {}
  local hasTrash = false
  for i = 1, #baseOrder do
    local key = baseOrder[i]
    if key == "other" then
      -- defer
    elseif key == "trash" then
      hasTrash = not CustomCategories.IsDefaultHidden(key)
    elseif not CustomCategories.IsDefaultHidden(key) then
      out[#out + 1] = key
      seen[key] = true
    end
  end
  for i = 1, #c.customCategories do
    local id = c.customCategories[i].id
    if id and not seen[id] then
      out[#out + 1] = id
      seen[id] = true
    end
  end
  if hasTrash then
    out[#out + 1] = "trash"
  end
  out[#out + 1] = "other"
  return out
end

function CustomCategories.Rename(id, name)
  name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
  if name == "" then
    return
  end
  local c = EnsureCharTables()
  for i = 1, #c.customCategories do
    if c.customCategories[i].id == id then
      c.customCategories[i].name = name
    end
  end
  Changed()
end

function CustomCategories.Teach(itemID, laneKey, naturalKey)
  if not NormalizeId(itemID) or type(laneKey) ~= "string" then
    return
  end
  if laneKey == naturalKey then
    CustomCategories.AssignItem(itemID, nil)
  else
    CustomCategories.AssignItem(itemID, laneKey)
  end
end

local function CountRulesIn(tableRules)
  local n = 0
  if type(tableRules) ~= "table" then
    return 0
  end
  for _, rule in pairs(tableRules) do
    if type(rule) == "string" and rule ~= "" then
      n = n + 1
    end
  end
  return n
end

--- Every taught item with its lane: { { itemID = n, lane = "key" }, ... } sorted by itemID.
--- Built-in lane teachings come from the account profile, custom lanes + Trash from this character.
function CustomCategories.ListRules()
  local out, seen = {}, {}
  local function add(rules)
    if type(rules) ~= "table" then
      return
    end
    for itemID, rule in pairs(rules) do
      local n = tonumber(itemID)
      if n and type(rule) == "string" and rule ~= "" and not seen[n] then
        seen[n] = true
        out[#out + 1] = { itemID = n, lane = rule }
      end
    end
  end
  add(EnsureCharTables().itemRules)
  add(EnsureProfileTables().itemRules)
  table.sort(out, function(a, b)
    return a.itemID < b.itemID
  end)
  return out
end

function CustomCategories.CountRules()
  local c = EnsureCharTables()
  local p = EnsureProfileTables()
  return CountRulesIn(c.itemRules) + CountRulesIn(p.itemRules)
end

function CustomCategories.CountLaneRules(laneKey)
  local n = 0
  for _, rule in pairs(EnsureCharTables().itemRules) do
    if rule == laneKey then
      n = n + 1
    end
  end
  return n
end

function CustomCategories.ForgetAll()
  local c = EnsureCharTables()
  local p = EnsureProfileTables()
  c.itemRules = {}
  for i = 1, #c.customCategories do
    c.customCategories[i].itemIDs = {}
  end
  p.itemRules = {}
  Changed()
end

function CustomCategories.CreateLane(name, itemID)
  local entry = CustomCategories.Add(name)
  if not entry then
    return nil
  end
  if NormalizeId(itemID) then
    CustomCategories.AssignItem(itemID, entry.id)
  else
    Changed()
  end
  return entry
end

local function PopupEdit(dialog)
  if not dialog then
    return nil
  end
  return dialog.editBox or dialog.EditBox or (dialog.GetEditBox and dialog:GetEditBox())
end

local function PopupData(self)
  if self and self.data ~= nil then
    return self.data
  end
  local parent = self and self.GetParent and self:GetParent()
  return parent and parent.data
end

local popupsReady = false
local function EnsurePopups()
  if popupsReady or not StaticPopupDialogs then
    return popupsReady
  end
  popupsReady = true
  StaticPopupDialogs.BETTERBACKPACK_NEW_LANE = {
    text = "New lane name:",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 32,
    OnAccept = function(self, data)
      local eb = PopupEdit(self)
      CustomCategories.CreateLane(eb and eb:GetText(), data or PopupData(self))
    end,
    EditBoxOnEnterPressed = function(self, data)
      local dialog = self:GetParent()
      CustomCategories.CreateLane(self:GetText(), data or PopupData(dialog))
      dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
      self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
  StaticPopupDialogs.BETTERBACKPACK_RENAME_LANE = {
    text = "Rename lane:",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 32,
    OnAccept = function(self, data)
      local eb = PopupEdit(self)
      CustomCategories.Rename(data or PopupData(self), eb and eb:GetText())
    end,
    EditBoxOnEnterPressed = function(self, data)
      local dialog = self:GetParent()
      CustomCategories.Rename(data or PopupData(dialog), self:GetText())
      dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
      self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
  StaticPopupDialogs.BETTERBACKPACK_DELETE_LANE = {
    text = "Delete lane \"%s\"? Its items go back to their default lanes.",
    button1 = DELETE or "Delete",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, data)
      CustomCategories.Remove(data or PopupData(self))
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,
  }
  StaticPopupDialogs.BETTERBACKPACK_FORGET_RULES = {
    text = "Forget every item you taught by dragging? Items return to their default lanes.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
      CustomCategories.ForgetAll()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
  return true
end

local function ShowPopup(which, textArg, data, prefill)
  if not EnsurePopups() or not StaticPopup_Show then
    return
  end
  local dialog = StaticPopup_Show(which, textArg, nil, data)
  if dialog then
    dialog.data = data
    local eb = PopupEdit(dialog)
    if eb then
      eb:SetText(prefill or "")
      eb:HighlightText()
      eb:SetFocus()
    end
  end
end

function CustomCategories.PromptNew(itemID)
  ShowPopup("BETTERBACKPACK_NEW_LANE", nil, NormalizeId(itemID), "")
end

function CustomCategories.PromptRename(id)
  ShowPopup("BETTERBACKPACK_RENAME_LANE", nil, id, CustomCategories.Label(id) or "")
end

function CustomCategories.PromptDelete(id)
  ShowPopup("BETTERBACKPACK_DELETE_LANE", CustomCategories.Label(id) or id, id)
end

function CustomCategories.PromptForgetAll()
  ShowPopup("BETTERBACKPACK_FORGET_RULES", nil, nil)
end

--- Called on PLAYER_LOGIN / character switch so layout matches new char tables.
function CustomCategories.OnCharacterActive()
  Changed()
end

return CustomCategories