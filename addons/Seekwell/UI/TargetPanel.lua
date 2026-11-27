--[[
  Seekwell.TargetPanel — what drops from the unit in target (fallback mouseover), on a key or /sw target.
  Own non-secure frame: movable (position saved), closes with Escape, works in combat.
  Rows are pooled (12 visible, mouse wheel / bar scrolls), no OnUpdate. Click = wishlist star, Shift+click = link in chat.
  Events (target change, item info) are registered only while the panel is shown.
]]

Seekwell = Seekwell or {}
local P = {}
Seekwell.TargetPanel = P

local ROWS, ROW_H, W = 12, 20, 400
local HEADER_H, FOOTER_H = 58, 24
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local OWN_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
local STAR_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"

local frame
local rowFrames = {}
local state = nil -- last resolved unit state
local drops = nil -- Registry.NpcDrops result
local offset = 0
local pending = {} -- [itemID] = true while waiting for GET_ITEM_INFO_RECEIVED
local renderQueued = false

local function L()
  return Seekwell.L or {}
end

local function Sec()
  return Seekwell.Secret
end

--- Item name, link, quality, icon (name nil while the client has not loaded it; a load is requested).
local function ItemInfo(id)
  local name, link, quality, icon
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if getInfo then
    local res = { pcall(getInfo, id) }
    if res[1] then
      name, link, quality, icon = res[2], res[3], res[4], res[11]
    end
  end
  local S = Sec()
  name, link, quality, icon = S.Str(name), S.Str(link), tonumber(S.Plain(quality)), S.Plain(icon)
  if not name then
    pending[id] = true
    if C_Item and C_Item.RequestLoadItemDataByID then
      pcall(C_Item.RequestLoadItemDataByID, id)
    end
  end
  if not icon then
    if C_Item and C_Item.GetItemIconByID then
      icon = S.Get(C_Item.GetItemIconByID, id)
    end
    if not icon then
      local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
      if inst then
        local res = { pcall(inst, id) }
        if res[1] then
          icon = S.Plain(res[6])
        end
      end
    end
  end
  return name, link, quality, icon
end
P.ItemInfo = ItemInfo

local function OwnedCount(id)
  local S = Sec()
  local n
  if C_Item and C_Item.GetItemCount then
    n = S.Get(C_Item.GetItemCount, id, true)
  end
  if n == nil and GetItemCount then
    n = S.Get(GetItemCount, id, true)
  end
  return tonumber(n) or 0
end
P.OwnedCount = OwnedCount

local function QualityColor(q)
  local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if type(c) == "table" and c.r then
    return c.r, c.g, c.b
  end
  return 1, 1, 1
end

--- What the panel should show: { kind = "npc"|"hint"|"player"|"pet"|"secret"|"notnpc", unit, npcID, name, level }
function P.Resolve()
  local S = Sec()
  local unit
  if S.Get(UnitExists, "target") then
    unit = "target"
  elseif S.Get(UnitExists, "mouseover") then
    unit = "mouseover"
  end
  if not unit then
    return { kind = "hint" }
  end
  local okG, guid = pcall(UnitGUID, unit)
  local kind = okG and S.GUIDKind(guid) or "secret"
  local name = S.Str(S.Get(UnitName, unit))
  if kind == "secret" then
    return { kind = "secret", unit = unit, name = name }
  end
  if kind == "player" or S.Get(UnitIsPlayer, unit) then
    return { kind = "player", unit = unit, name = name }
  end
  if kind == "pet" or (kind == "creature" and S.Get(UnitPlayerControlled, unit)) then
    return { kind = "pet", unit = unit, name = name }
  end
  local npcID = (kind == "creature") and S.NpcIDFromGUID(guid) or nil
  if not npcID then
    return { kind = "notnpc", unit = unit, name = name }
  end
  if Seekwell.Loot then
    Seekwell.Loot.RememberUnit(unit)
  end
  return { kind = "npc", unit = unit, npcID = npcID, name = name, level = tonumber(S.Get(UnitLevel, unit)) }
end

local function HeaderText()
  local Lx = L()
  if not state or state.kind ~= "npc" then
    return state and state.name or (Lx.PANEL_TITLE or "Seekwell"), ""
  end
  local name = state.name or (drops and drops.name) or ("npc " .. state.npcID)
  local lvl = state.level
  if lvl and lvl < 0 then
    name = name .. "  (level ??)"
  elseif lvl and lvl > 0 then
    name = name .. "  (level " .. math.floor(lvl) .. ")"
  end
  local parts = {}
  if drops then
    if drops.hasForever then
      parts[#parts + 1] = "Forever" .. (drops.foreverKills and (" n=" .. drops.foreverKills) or "")
    end
    if drops.learnedKills and drops.learnedKills > 0 then
      parts[#parts + 1] = "learned " .. drops.learnedKills .. " kill" .. (drops.learnedKills == 1 and "" or "s")
    end
    if drops.hasFdb then
      parts[#parts + 1] = "ForeverDB"
    end
    if drops.hasClassic then
      parts[#parts + 1] = Lx.ORIGIN_CLASSIC or "Classic estimate"
    end
  end
  local fdbOn = Seekwell.FDB and Seekwell.FDB.Data and Seekwell.FDB.Data() ~= nil
  if not Seekwell.Tinny.Available() and not fdbOn then
    parts[#parts + 1] = Lx.TINNY_MISSING or "Tinny data not available"
  end
  return name, table.concat(parts, " \194\183 ")
end

local function MessageText()
  local Lx = L()
  if not state or state.kind == "hint" then
    return Lx.PANEL_HINT
  elseif state.kind == "player" then
    return Lx.PANEL_PLAYER
  elseif state.kind == "pet" then
    return Lx.PANEL_PET
  elseif state.kind == "secret" then
    return Lx.PANEL_SECRET
  elseif state.kind == "notnpc" then
    return Lx.PANEL_NOTNPC
  elseif not drops or #drops.rows == 0 then
    if not Seekwell.Tinny.Available() and not (Seekwell.FDB and Seekwell.FDB.Data and Seekwell.FDB.Data()) then
      return Lx.PANEL_NOTINNY or Lx.PANEL_NODATA
    end
    return Lx.PANEL_NODATA
  end
  return nil
end

local function RowCount()
  return (drops and state and state.kind == "npc") and #drops.rows or 0
end

local function Render()
  if not frame then
    return
  end
  local title, sub = HeaderText()
  frame.title:SetText(title)
  frame.sub:SetText(sub)
  local msg = MessageText()
  frame.msg:SetText(msg or "")
  frame.msg:SetShown(msg ~= nil)
  local n = RowCount()
  local maxOff = math.max(0, n - ROWS)
  if offset > maxOff then
    offset = maxOff
  end
  local R = Seekwell.Registry
  for i = 1, ROWS do
    local rf = rowFrames[i]
    local r = (n > 0) and drops.rows[offset + i] or nil
    rf.data = r
    if r then
      local name, _, quality, icon = ItemInfo(r.id)
      rf.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      rf.name:SetText(name or ("item " .. r.id))
      rf.name:SetTextColor(QualityColor(quality))
      rf.pct:SetText(R.FormatPct(r.p))
      rf.origin:SetText(R.OriginLabel(r))
      rf.quest:SetShown(r.quest == true)
      rf.own:SetShown(OwnedCount(r.id) > 0)
      rf.star:SetShown(Seekwell.Wish.Has(r.id))
      rf:Show()
    else
      rf:Hide()
    end
  end
  if frame.bar then
    frame.bar:SetShown(n > ROWS)
    if n > ROWS then
      frame.bar:SetMinMaxValues(0, maxOff)
      frame.bar.lock = true
      frame.bar:SetValue(offset)
      frame.bar.lock = false
    end
  end
end
P.Render = Render

local function QueueRender()
  if renderQueued then
    return
  end
  renderQueued = true
  local run = Seekwell.Safe("panel.render", function()
    renderQueued = false
    Render()
  end)
  if C_Timer and C_Timer.After then
    C_Timer.After(0.2, run)
  else
    run()
  end
end

--- Re-read the target and redraw (no-op while hidden). keep = keep the last mob when nothing is targeted.
function P.Refresh(keep)
  if not frame or not frame:IsShown() then
    return
  end
  local st = P.Resolve()
  if keep and st.kind == "hint" and state and state.kind == "npc" then
    st = state -- target cleared (e.g. after looting): keep showing the last mob
  end
  if not state or st.npcID ~= state.npcID or st.kind ~= state.kind then
    offset = 0
  end
  state = st
  drops = (st.kind == "npc") and Seekwell.Registry.NpcDrops(st.npcID) or nil
  Render()
end

local function InsertLink(id)
  local _, link = ItemInfo(id)
  link = link or ("item:" .. id)
  local active = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
  if active and ChatEdit_InsertLink then
    ChatEdit_InsertLink(link)
    return true
  end
  return false
end

local function RowTooltip(self)
  local r = self.data
  if not r or not GameTooltip then
    return
  end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  local ok = pcall(GameTooltip.SetItemByID, GameTooltip, r.id)
  if not ok then
    ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. r.id)
  end
  if not ok then
    GameTooltip:SetText("item " .. r.id)
  end
  local R = Seekwell.Registry
  GameTooltip:AddLine(R.FormatPct(r.p) .. " \194\183 " .. R.OriginLabel(r), 0.6, 0.8, 1)
  if r.mine and r.origin ~= "learned" then
    GameTooltip:AddLine("yours: " .. r.mine.d .. " drop(s) in " .. r.mine.k .. " kill(s)", 0.6, 0.8, 1)
  end
  if r.quest then
    GameTooltip:AddLine("quest item", 1, 0.82, 0)
  end
  GameTooltip:Show()
end

local function RowClick(self, button)
  local r = self.data
  if not r then
    return
  end
  if button == "RightButton" then
    if Seekwell.ItemView and Seekwell.ItemView.Show then
      Seekwell.ItemView.Show(r.id)
    end
    return
  end
  if IsShiftKeyDown and IsShiftKeyDown() then
    InsertLink(r.id)
    return
  end
  local on = Seekwell.Wish.Toggle(r.id)
  local name = ItemInfo(r.id) or ("item " .. r.id)
  Seekwell.Print(string.format(on and (L().WISH_ADDED or "added: %s") or (L().WISH_REMOVED or "removed: %s"), name))
  Render()
  if Seekwell.Window and Seekwell.Window.Refresh then
    Seekwell.Window.Refresh()
  end
end

local function MakeRow(parent, i)
  local rf = CreateFrame("Button", nil, parent)
  rf:SetSize(W - 34, ROW_H)
  rf:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -(HEADER_H + (i - 1) * ROW_H))
  rf:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local hl = rf:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  rf.icon = rf:CreateTexture(nil, "ARTWORK")
  rf.icon:SetSize(ROW_H - 2, ROW_H - 2)
  rf.icon:SetPoint("LEFT", 0, 0)
  rf.star = rf:CreateTexture(nil, "OVERLAY")
  rf.star:SetSize(12, 12)
  rf.star:SetPoint("TOPLEFT", rf.icon, "TOPLEFT", -3, 3)
  rf.star:SetTexture(STAR_ICON)
  rf.name = rf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rf.name:SetPoint("LEFT", rf.icon, "RIGHT", 6, 0)
  rf.name:SetWidth(176)
  rf.name:SetJustifyH("LEFT")
  if rf.name.SetWordWrap then
    rf.name:SetWordWrap(false)
  end
  rf.quest = rf:CreateTexture(nil, "OVERLAY")
  rf.quest:SetSize(14, 14)
  rf.quest:SetPoint("LEFT", rf.name, "RIGHT", 0, 0)
  rf.quest:SetTexture(QUEST_ICON)
  rf.own = rf:CreateTexture(nil, "OVERLAY")
  rf.own:SetSize(14, 14)
  rf.own:SetPoint("LEFT", rf.quest, "RIGHT", 0, 0)
  rf.own:SetTexture(OWN_ICON)
  rf.pct = rf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  rf.pct:SetPoint("RIGHT", rf, "RIGHT", -96, 0)
  rf.pct:SetWidth(54)
  rf.pct:SetJustifyH("RIGHT")
  rf.origin = rf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  rf.origin:SetPoint("RIGHT", rf, "RIGHT", 0, 0)
  rf.origin:SetWidth(92)
  rf.origin:SetJustifyH("LEFT")
  rf:SetScript("OnEnter", Seekwell.Safe("panel.row.enter", RowTooltip))
  rf:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  rf:SetScript("OnClick", Seekwell.Safe("panel.row.click", RowClick))
  rf:Hide()
  return rf
end

local function Scroll(delta)
  local maxOff = math.max(0, RowCount() - ROWS)
  offset = math.max(0, math.min(maxOff, offset - delta * 3))
  Render()
end

local function SavePosition(f)
  local point, _, _, x, y = f:GetPoint(1)
  if type(point) == "string" then
    local p = Seekwell.Config.Get().panel
    p.point, p.x, p.y = point, tonumber(x) or 0, tonumber(y) or 0
  end
end

local function OnEvent(_, event, arg1)
  if event == "PLAYER_TARGET_CHANGED" then
    P.Refresh(true)
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    local id = tonumber(arg1)
    if id and pending[id] then
      pending[id] = nil
      QueueRender()
    end
  elseif event == "BAG_UPDATE_DELAYED" then
    QueueRender()
  end
end

local function Build()
  local okF, f = pcall(CreateFrame, "Frame", "SeekwellTargetPanel", UIParent, "BackdropTemplate")
  if not okF or not f then
    f = CreateFrame("Frame", "SeekwellTargetPanel", UIParent)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)
  end
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    if f.SetBackdropColor then
      f:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
    end
  end
  f:SetSize(W, HEADER_H + ROWS * ROW_H + FOOTER_H)
  local pos = Seekwell.Config.Get().panel
  f:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", tonumber(pos.x) or 0, tonumber(pos.y) or 0)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", Seekwell.Safe("panel.drag", function(self)
    self:StopMovingOrSizing()
    SavePosition(self)
  end))
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", Seekwell.Safe("panel.wheel", function(_, delta)
    Scroll(delta)
  end))

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function()
    f:Hide()
  end)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.title:SetWidth(W - 50)
  f.title:SetJustifyH("LEFT")
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
  f.sub:SetWidth(W - 30)
  f.sub:SetJustifyH("LEFT")
  f.sub:SetTextColor(0.65, 0.65, 0.65)
  f.msg = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.msg:SetPoint("TOPLEFT", 14, -HEADER_H - 6)
  f.msg:SetWidth(W - 28)
  f.msg:SetJustifyH("LEFT")
  f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.foot:SetPoint("BOTTOMLEFT", 12, 8)
  f.foot:SetText(L().PANEL_FOOTER or "")

  for i = 1, ROWS do
    rowFrames[i] = MakeRow(f, i)
  end

  local bar = CreateFrame("Slider", nil, f)
  bar:SetOrientation("VERTICAL")
  bar:SetSize(10, ROWS * ROW_H)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -HEADER_H)
  bar:SetMinMaxValues(0, 1)
  bar:SetValueStep(1)
  if bar.SetObeyStepOnDrag then
    bar:SetObeyStepOnDrag(true)
  end
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(1, 1, 1, 0.06)
  local thumb = bar:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(1, 0.82, 0, 0.55)
  thumb:SetSize(10, 24)
  bar:SetThumbTexture(thumb)
  bar:SetScript("OnValueChanged", Seekwell.Safe("panel.bar", function(self, v)
    if self.lock then
      return
    end
    offset = math.floor((tonumber(v) or 0) + 0.5)
    Render()
  end))
  bar:Hide()
  f.bar = bar

  f:SetScript("OnEvent", Seekwell.Safe("panel.event", OnEvent))
  f:SetScript("OnShow", function(self)
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    self:RegisterEvent("BAG_UPDATE_DELAYED")
  end)
  f:SetScript("OnHide", function(self)
    self:UnregisterAllEvents()
    pending = {}
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  if UISpecialFrames then
    table.insert(UISpecialFrames, "SeekwellTargetPanel")
  end
  f:Hide()
  return f
end

if Seekwell.RegisterStart then
  Seekwell.RegisterStart("panel.fdbready", function()
    if Seekwell.FDB and Seekwell.FDB.OnReady then
      Seekwell.FDB.OnReady(function()
        if frame and frame:IsShown() then
          P.Refresh(true)
        end
      end)
    end
  end)
end

function P.Ensure()
  if not frame then
    frame = Build()
  end
  return frame
end

function P.Show()
  if Seekwell.FDB and Seekwell.FDB.Touch then
    pcall(Seekwell.FDB.Touch)
  end
  P.Ensure()
  frame:Show()
  P.Refresh(false)
end

function P.Hide()
  if frame then
    frame:Hide()
  end
end

function P.Toggle()
  P.Ensure()
  if frame:IsShown() then
    frame:Hide()
  else
    P.Show()
  end
end

function P.IsShown()
  return frame ~= nil and frame:IsShown() and true or false
end

--- For the tests and the window: current state and rows.
function P.Current()
  return state, drops
end

-- Key binding (Bindings.xml) entry point.
function Seekwell_ShowTarget()
  local fn = Seekwell.Safe("binding.target", P.Toggle)
  fn()
end
