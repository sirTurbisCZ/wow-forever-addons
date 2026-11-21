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

local function Changed()
  local Layout = BetterBackpack.Modules.Layout
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
  local p = EnsureTables()
  name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
  if name == "" then
    return nil
  end
  local base = "custom_" .. tostring((GetTime and math.floor(GetTime() * 1000)) or (#p.customCategories + 1))
  local id, n = base, 1
  while CustomCategories.Label(id) do
    n = n + 1
    id = base .. "_" .. n
  end
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
  Changed()
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
    p.itemRules[tostring(itemID)] = nil
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
  Changed()
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

--- Extended order: defaults (minus hidden) + custom + trash + other last.
function CustomCategories.ExtendOrder(baseOrder)
  local p = EnsureTables()
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
  for i = 1, #p.customCategories do
    local id = p.customCategories[i].id
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
  local p = EnsureTables()
  for i = 1, #p.customCategories do
    if p.customCategories[i].id == id then
      p.customCategories[i].name = name
    end
  end
  Changed()
end

--- Drag-teach: send itemID to laneKey from now on. Dropping on the lane the item would
--- land in anyway (its natural lane) clears the rule instead of storing a redundant one.
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

function CustomCategories.CountRules()
  local n = 0
  for _, rule in pairs(EnsureTables().itemRules) do
    if type(rule) == "string" and rule ~= "" then
      n = n + 1
    end
  end
  return n
end

function CustomCategories.CountLaneRules(laneKey)
  local n = 0
  for _, rule in pairs(EnsureTables().itemRules) do
    if rule == laneKey then
      n = n + 1
    end
  end
  return n
end

function CustomCategories.ForgetAll()
  local p = EnsureTables()
  p.itemRules = {}
  for i = 1, #p.customCategories do
    p.customCategories[i].itemIDs = {}
  end
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

-- StaticPopup edit box key differs across clients (editBox → EditBox / GetEditBox).
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
