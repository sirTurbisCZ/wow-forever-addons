--[[
  Wayfarer.PartyMarks — tells party / raid members apart on nameplates.
  The Blizzard health bar is never recoloured (that taints). Instead one frame of OURS per plate holds a
  coloured outline around the bar and a small P / R tag left of it. Group membership comes from
  UnitInParty / UnitInRaid (readable in combat); the colour is the class colour or one custom colour per group.
  Frames are created and anchored out of combat only (anchoring to plate frames in lockdown is blocked); in combat
  existing frames are just shown, hidden and recoloured.
]]

Wayfarer = Wayfarer or {}
Wayfarer.Modules = Wayfarer.Modules or {}

local Mod = {}
Wayfarer.Modules.PartyMarks = Mod

local marks = {} -- [plateFrame] = mark frame
local plateOf = {} -- [unitToken] = plateFrame
local eventFrame
local started = false

local function Cfg()
  return Wayfarer.Config.GetProfile().partyMarks
end

local function IsSecret(v)
  return issecretvalue and issecretvalue(v) or false
end

local function InCombat()
  return InCombatLockdown and InCombatLockdown() or false
end

local function HealthBar(plate)
  local bar
  pcall(function()
    local uf = plate.UnitFrame
    if uf then
      if uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar then
        bar = uf.HealthBarsContainer.healthBar
      else
        bar = uf.healthBar or uf.HealthBarsContainer
      end
    end
  end)
  return bar
end

--- "party" | "raid" | nil for a nameplate unit token.
local function GroupOf(unit)
  if type(unit) ~= "string" then
    return nil
  end
  local ok, isPlayer = pcall(UnitIsPlayer, unit)
  if not ok or IsSecret(isPlayer) or not isPlayer then
    return nil
  end
  local okS, isSelf = pcall(UnitIsUnit, unit, "player")
  if okS and not IsSecret(isSelf) and isSelf then
    return nil
  end
  local inRaidGroup = IsInRaid and IsInRaid() or false
  if inRaidGroup then
    local okR, idx = pcall(UnitInRaid, unit)
    if okR and not IsSecret(idx) and idx then
      return "raid"
    end
    return nil
  end
  local okP, inParty = pcall(UnitInParty, unit)
  if okP and not IsSecret(inParty) and inParty then
    return "party"
  end
  return nil
end

local function ClassColor(unit)
  local classFile
  pcall(function()
    local _, f = UnitClass(unit)
    if f and not IsSecret(f) then
      classFile = f
    end
  end)
  if not classFile then
    return nil
  end
  local c
  if C_ClassColor and C_ClassColor.GetClassColor then
    local ok, col = pcall(C_ClassColor.GetClassColor, classFile)
    if ok then
      c = col
    end
  end
  c = c or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
  if c and c.r then
    return c.r, c.g, c.b
  end
  return nil
end

local function ColorFor(unit, group)
  local cfg = Cfg()
  if cfg.colorMode == "class" then
    local r, g, b = ClassColor(unit)
    if r then
      return r, g, b
    end
  end
  local c = group == "raid" and cfg.raidColor or cfg.partyColor
  return c.r or 1, c.g or 1, c.b or 1
end

local function AnchorEdges(mark, bar)
  local th = math.max(1, tonumber(Cfg().thickness) or 2)
  local e = mark.edges
  for i = 1, 4 do
    e[i]:ClearAllPoints()
  end
  e[1]:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -th, 0)
  e[1]:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", th, 0)
  e[1]:SetHeight(th)
  e[2]:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -th, 0)
  e[2]:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", th, 0)
  e[2]:SetHeight(th)
  e[3]:SetPoint("TOPRIGHT", bar, "TOPLEFT", 0, 0)
  e[3]:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", 0, 0)
  e[3]:SetWidth(th)
  e[4]:SetPoint("TOPLEFT", bar, "TOPRIGHT", 0, 0)
  e[4]:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", 0, 0)
  e[4]:SetWidth(th)
  mark.badge:ClearAllPoints()
  mark.badge:SetPoint("RIGHT", bar, "LEFT", -(th + 3), 0)
  mark.th = th
end

--- Out of combat only: create and anchor the mark frame of a plate.
local function CreateMark(plate)
  if InCombat() or marks[plate] then
    return marks[plate]
  end
  local forbidden = false
  pcall(function()
    forbidden = plate:IsForbidden()
  end)
  local bar = HealthBar(plate)
  if forbidden or not bar then
    return nil
  end
  local f = CreateFrame("Frame", nil, plate)
  f:EnableMouse(false)
  f:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 1) + 5)
  f.edges = {}
  for i = 1, 4 do
    f.edges[i] = f:CreateTexture(nil, "OVERLAY")
  end
  local badge = CreateFrame("Frame", nil, f)
  badge:SetSize(14, 14)
  badge.bg = badge:CreateTexture(nil, "BACKGROUND")
  badge.bg:SetAllPoints()
  badge.bg:SetColorTexture(1, 1, 1, 1)
  badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  badge.text:SetPoint("CENTER", 0, 0)
  badge.text:SetTextColor(0, 0, 0, 1)
  f.badge = badge
  AnchorEdges(f, bar)
  f:Hide()
  marks[plate] = f
  return f
end

local function Update(plate, unit)
  local cfg = Cfg()
  local mark = marks[plate]
  if not cfg.enabled then
    if mark then
      mark:Hide()
    end
    return
  end
  local group = GroupOf(unit)
  if not group then
    if mark then
      mark:Hide()
    end
    return
  end
  mark = mark or CreateMark(plate)
  if not mark then
    return
  end
  if not InCombat() and mark.th ~= math.max(1, tonumber(cfg.thickness) or 2) then
    local bar = HealthBar(plate)
    if bar then
      AnchorEdges(mark, bar)
    end
  end
  local r, g, b = ColorFor(unit, group)
  for i = 1, 4 do
    mark.edges[i]:SetColorTexture(r, g, b, 1)
    mark.edges[i]:SetShown(cfg.outline and true or false)
  end
  mark.badge.bg:SetColorTexture(r, g, b, 1)
  mark.badge.text:SetText(group == "raid" and "R" or "P")
  mark.badge:SetShown(cfg.badge and true or false)
  mark:Show()
end

local function UnitOfPlate(plate)
  local unit
  pcall(function()
    unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
  end)
  return unit
end

local function RefreshAll()
  if not (C_NamePlate and C_NamePlate.GetNamePlates) then
    return
  end
  local ok, plates = pcall(C_NamePlate.GetNamePlates)
  if not ok or type(plates) ~= "table" then
    return
  end
  for i = 1, #plates do
    local plate = plates[i]
    local unit = UnitOfPlate(plate)
    if unit then
      plateOf[unit] = plate
      Update(plate, unit)
    end
  end
end

local refreshPending = false
--- GROUP_ROSTER_UPDATE comes in bursts: one refresh shortly after the last of them.
local function ScheduleRefresh()
  if not (C_Timer and C_Timer.After) then
    RefreshAll()
    return
  end
  if refreshPending then
    return
  end
  refreshPending = true
  C_Timer.After(0.2, function()
    refreshPending = false
    RefreshAll() -- safe in combat: marks are only shown or hidden, new frames wait for combat to end
  end)
end

local function OnEvent(_, event, unit)
  if event == "NAME_PLATE_UNIT_ADDED" then
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if plate then
      plateOf[unit] = plate
      Update(plate, unit)
    end
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    local plate = plateOf[unit]
    plateOf[unit] = nil
    if plate and marks[plate] then
      marks[plate]:Hide()
    end
  elseif event == "GROUP_ROSTER_UPDATE" then
    ScheduleRefresh()
  else
    -- world / combat end: re-evaluate everything (creates what could not be made in combat)
    RefreshAll()
  end
end

--- Apply the current settings (enable/disable, colours, styles).
function Mod.Apply()
  if not started then
    return
  end
  if Cfg().enabled then
    RefreshAll()
  else
    for _, mark in pairs(marks) do
      mark:Hide()
    end
  end
end

function Mod.Start()
  if started then
    return
  end
  started = true
  eventFrame = CreateFrame("Frame")
  for _, e in ipairs({
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED",
  }) do
    pcall(eventFrame.RegisterEvent, eventFrame, e)
  end
  eventFrame:SetScript("OnEvent", function(self, event, unit)
    local ok, err = pcall(OnEvent, self, event, unit)
    if not ok and Wayfarer.RecordError then
      Wayfarer.RecordError("partymarks:" .. tostring(event), err)
    end
  end)
  Mod.Apply()
end

function Mod.Status()
  local n = 0
  for _ in pairs(marks) do
    n = n + 1
  end
  return string.format("enabled=%s class=%s frames=%d", tostring(Cfg().enabled), tostring(Cfg().colorMode == "class"), n)
end
