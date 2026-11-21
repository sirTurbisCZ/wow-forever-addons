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

local function SyncEdit()
  if edit then
    local cur = Search.GetQuery()
    if edit:GetText() ~= cur then
      edit:SetText(cur)
    end
  end
end

local function WireEdit(e)
  e:SetAutoFocus(false)
  e:SetMaxLetters(48)
  e:HookScript("OnTextChanged", function(self)
    local t = self:GetText() or ""
    if t ~= Search.GetQuery() then
      Search.SetQuery(t)
    end
  end)
  e:HookScript("OnEscapePressed", function(self)
    self:ClearFocus()
    if (self:GetText() or "") ~= "" then
      self:SetText("")
    end
  end)
  e:HookScript("OnEnterPressed", function(self)
    self:ClearFocus()
  end)
end

-- Same look as CombinedBags' BagItemSearchBox: it is SearchBoxTemplate (rounded
-- common-search-border, magnifier, clear X, "Search" instructions). Never
-- BagSearchBoxTemplate — it drives C_Container.SetItemSearch and opens a second CombinedBags.
local function CreateNativeLook(main)
  local ok, e = pcall(CreateFrame, "EditBox", "BetterBackpackSearchBox", main, "SearchBoxTemplate")
  if not ok or not e then
    return nil
  end
  e:SetSize(160, 20)
  e:SetPoint("TOPLEFT", main, "TOPLEFT", 16, -29)
  return e
end

local function CreateFlat(main)
  local e = CreateFrame("EditBox", "BetterBackpackSearchBoxFlat", main)
  e:SetSize(168, 22)
  e:SetPoint("TOPLEFT", main, "TOPLEFT", 11, -28)
  local bg = e:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.06, 0.06, 0.07, 0.94)
  e:SetFontObject(GameFontHighlightSmall)
  e:SetTextInsets(6, 6, 0, 0)
  local ph = e:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ph:SetPoint("LEFT", 6, 0)
  ph:SetText(SEARCH or "Search")
  local function SyncPh()
    ph:SetShown((e:GetText() or "") == "" and not e:HasFocus())
  end
  e:HookScript("OnEditFocusGained", SyncPh)
  e:HookScript("OnEditFocusLost", SyncPh)
  e:HookScript("OnTextChanged", SyncPh)
  SyncPh()
  return e
end

function Search.EnsureChrome(main)
  if not main then
    return
  end
  if box and box:GetParent() == main then
    SyncEdit()
    box:Show()
    return box
  end
  edit = CreateNativeLook(main) or CreateFlat(main)
  box = edit
  edit:SetFrameLevel((main:GetFrameLevel() or 1) + 80)
  WireEdit(edit)
  SyncEdit()
  edit:Show()
  return box
end

function Search.HideChrome()
  if box then
    box:Hide()
  end
end
