--[[
  BetterBackpack.Search — search box + name/itemID match (v1 nice-to-have).
  Layout calls Search.Passes during CollectBuckets. Chrome attaches to main frame.
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local Search = {}
BetterBackpack.Modules.Search = Search

local Config = BetterBackpack.Config
local Slots = BetterBackpack.Modules.Slots

local box, edit

local function Profile()
  return Config.GetProfile()
end

local function SafeStr(v)
  if type(v) ~= "string" then
    return nil
  end
  if Slots and Slots.IsSecret and Slots.IsSecret(v) then
    return nil
  end
  return v
end

local function SafeNum(v)
  if Slots and Slots.SafeNum then
    return Slots.SafeNum(v)
  end
  if type(v) == "number" then
    return v
  end
  return nil
end

function Search.GetQuery()
  local p = Profile()
  local q = p.searchQuery
  if type(q) ~= "string" then
    return ""
  end
  return q
end

function Search.SetQuery(q)
  local p = Profile()
  p.searchQuery = type(q) == "string" and q or ""
  local Layout = BetterBackpack.Modules.Layout
  if Layout and Layout.Relayout then
    Layout.Relayout()
  end
end

local function ItemName(bag, slot, info)
  local link = SafeStr(info and info.hyperlink)
  if not link and C_Container and C_Container.GetContainerItemLink then
    local ok, res = pcall(C_Container.GetContainerItemLink, bag, slot)
    if ok then
      link = SafeStr(res)
    end
  end
  if link then
    local name = link:match("%[(.-)%]")
    if name then
      return name
    end
  end
  local id = SafeNum(info and info.itemID)
  if id and C_Item and C_Item.GetItemNameByID then
    local ok, n = pcall(C_Item.GetItemNameByID, id)
    if ok then
      return SafeStr(n)
    end
  end
  if id and GetItemInfo then
    local ok, n = pcall(GetItemInfo, id)
    if ok then
      return SafeStr(n)
    end
  end
  return nil
end

--- Return false to hide the slot from layout.
function Search.Passes(bag, slot, info)
  local q = Search.GetQuery()
  if q == "" then
    return true
  end
  local needle = q:lower()
  local name = ItemName(bag, slot, info)
  if name and name:lower():find(needle, 1, true) then
    return true
  end
  local id = SafeNum(info and info.itemID)
  if id and tostring(id):find(needle, 1, true) then
    return true
  end
  return false
end

function Search.EnsureChrome(main)
  if not main then
    return
  end
  if box and box:GetParent() == main then
    if edit then
      local cur = Search.GetQuery()
      if edit:GetText() ~= cur then
        edit:SetText(cur)
      end
    end
    box:Show()
    return box
  end

  box = CreateFrame("Frame", "BetterBackpackSearchBox", main)
  box:SetSize(160, 20)
  -- CombinedBags / BagShelves: search under title on the LEFT, not fighting Close twins.
  box:SetPoint("TOPLEFT", main, "TOPLEFT", 12, -30)
  box:SetFrameLevel((main:GetFrameLevel() or 1) + 80)

  local bg = box:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.08, 0.08, 0.1, 0.92)

  edit = CreateFrame("EditBox", nil, box)
  edit:SetAllPoints()
  edit:SetAutoFocus(false)
  edit:SetFontObject(GameFontHighlightSmall)
  edit:SetTextInsets(6, 6, 0, 0)
  edit:SetMaxLetters(48)
  edit:SetText(Search.GetQuery())
  edit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    if self:GetText() ~= "" then
      self:SetText("")
      Search.SetQuery("")
    end
  end)
  edit:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
  end)
  edit:SetScript("OnTextChanged", function(self, user)
    if not user then
      return
    end
    Search.SetQuery(self:GetText() or "")
  end)

  local ph = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ph:SetPoint("LEFT", 6, 0)
  ph:SetText("Search…")
  box.placeholder = ph
  local function SyncPh()
    if (edit:GetText() or "") == "" and not edit:HasFocus() then
      ph:Show()
    else
      ph:Hide()
    end
  end
  edit:HookScript("OnEditFocusGained", SyncPh)
  edit:HookScript("OnEditFocusLost", SyncPh)
  edit:HookScript("OnTextChanged", SyncPh)
  SyncPh()

  return box
end

function Search.HideChrome()
  if box then
    box:Hide()
  end
end
