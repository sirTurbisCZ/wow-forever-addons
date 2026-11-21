--[[
  Plateband.Modules.Plates — above-plate AuraContainer band.
  No CLEU. No SetStatusBarColor on plate HP. Click-through holder.
]]

Plateband = Plateband or {}
Plateband.Modules = Plateband.Modules or {}

local ns = Plateband
local Mod = {}
ns.Modules.Plates = Mod

local AC_GROUP = "platebandHarmful"
local OVERLAY_PAD = 2
local OVERLAY_GAP_ABOVE = 2
local TICKER_SEC = 0.25

local overlays = {} -- [nameplateUnit] = container
local acCreateFailed = false
local ticker
local started = false
local eventFrame
local lastBlocked = "none"

local function Profile()
  return ns.Config.GetProfile()
end

local function IsSecret(v)
  if issecretvalue then
    local ok, secret = pcall(issecretvalue, v)
    return ok and secret and true or false
  end
  return false
end

local function SafeShown(frame)
  if not frame then
    return false
  end
  local ok, shown = pcall(frame.IsShown, frame)
  if not ok or IsSecret(shown) then
    return false
  end
  return shown and true or false
end

local function PlateFor(unit)
  if not unit or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
    return nil
  end
  local plate
  pcall(function()
    plate = C_NamePlate.GetNamePlateForUnit(unit)
  end)
  return plate
end

local function IsForbiddenPlate(plate)
  if not plate then
    return true
  end
  local forbidden = false
  pcall(function()
    if plate.IsForbidden and plate:IsForbidden() then
      forbidden = true
    end
  end)
  return forbidden
end

local function SameUnit(a, b)
  if not a or not b then
    return false
  end
  local ok, same = pcall(UnitIsUnit, a, b)
  if not ok or IsSecret(same) then
    return false
  end
  return same and true or false
end

local function HealthBar(plate)
  local uf = plate and plate.UnitFrame
  if not uf then
    return nil
  end
  local bar
  pcall(function()
    if uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar then
      bar = uf.HealthBarsContainer.healthBar
    else
      bar = uf.healthBar or uf.HealthBarsContainer
    end
  end)
  return bar
end

local function NativeDebuffList(plate)
  local list
  pcall(function()
    local uf = plate and plate.UnitFrame
    local af = uf and uf.AurasFrame
    if af then
      list = af.DebuffListFrame
    end
    if not list and uf then
      list = uf.DebuffListFrame or uf.DebuffFrame
    end
  end)
  return list
end

local function CountShownAuraKids(frame)
  if not frame then
    return 0
  end
  local n = 0
  local ok, kids = pcall(function()
    return { frame:GetChildren() }
  end)
  if not ok or type(kids) ~= "table" then
    return 0
  end
  for i = 1, #kids do
    local child = kids[i]
    if child and (child.icon or child.Icon) and SafeShown(child) then
      n = n + 1
    end
  end
  return n
end

local function GetTargetAuraContainer()
  local c
  pcall(function()
    if TargetFrame and TargetFrame.GetAuraContainer then
      c = TargetFrame:GetAuraContainer()
    end
  end)
  if c then
    return c
  end
  pcall(function()
    local content = TargetFrame and TargetFrame.TargetFrameContent
    local ctx = content and content.TargetFrameContentContextual
    c = ctx and ctx.Auras
  end)
  return c
end

local function CountTargetFrameAuras()
  local container = GetTargetAuraContainer()
  if not container then
    return 0
  end
  local n = CountShownAuraKids(container)
  if n > 0 then
    return n
  end
  pcall(function()
    if container.auraPools and container.auraPools.EnumerateActiveAuraButtons then
      local count = 0
      for btn in container.auraPools:EnumerateActiveAuraButtons() do
        if btn and SafeShown(btn) then
          count = count + 1
        end
      end
      n = count
    end
  end)
  return n
end

local function IconSize()
  local p = Profile()
  local sz = tonumber(p.iconSize) or 18
  if sz < 12 then
    sz = 12
  elseif sz > 32 then
    sz = 32
  end
  -- Prefer live native measure when available.
  for i = 1, 40 do
    local u = "nameplate" .. i
    if UnitExists(u) then
      local list = NativeDebuffList(PlateFor(u))
      if list then
        local ok, kids = pcall(function()
          return { list:GetChildren() }
        end)
        if ok and type(kids) == "table" then
          for j = 1, #kids do
            local child = kids[j]
            if child and (child.icon or child.Icon) and SafeShown(child) then
              local w
              pcall(function()
                w = child:GetWidth()
              end)
              if type(w) == "number" and not IsSecret(w) and w >= 12 and w <= 48 then
                return w
              end
            end
          end
        end
      end
    end
  end
  return sz
end

local function MaxIcons()
  local n = tonumber(Profile().maxIcons) or 12
  if n < 1 then
    n = 1
  elseif n > 16 then
    n = 16
  end
  return n
end

local function InitAuraButton(button, size)
  button:SetSize(size, size)
  button:EnableMouse(true)
  if button.SetMouseMotionEnabled then
    button:SetMouseMotionEnabled(true)
  end
  if button.SetMouseClickEnabled then
    button:SetMouseClickEnabled(false)
  end

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(button)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button.icon = icon
  if button.SetIcon then
    pcall(button.SetIcon, button, icon)
  end

  local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
  cd:SetAllPoints(button)
  cd:EnableMouse(false)
  cd:SetDrawBling(false)
  cd:SetReverse(true)
  cd:SetDrawSwipe(true)
  cd:SetSwipeColor(0, 0, 0, 0.5)
  cd:SetHideCountdownNumbers(false)
  button.cooldown = cd
  if button.SetDurationCooldown then
    pcall(button.SetDurationCooldown, button, cd)
  end

  local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
  button.count = count
  if button.SetApplicationCount then
    pcall(button.SetApplicationCount, button, count)
  end

  local dur = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  dur:SetPoint("CENTER", button, "CENTER", 0, 1)
  if button.SetDurationText then
    pcall(button.SetDurationText, button, dur)
  end
end

local function CreateBandContainer(parent, size)
  if acCreateFailed then
    return nil
  end
  local container
  for _, tpl in ipairs({ "CustomAuraContainerTemplate", "ManagedAuraContainerTemplate" }) do
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, tpl)
    if ok and c then
      container = c
      break
    end
  end
  if not container then
    acCreateFailed = true
    return nil
  end

  local maxN = MaxIcons()
  container:Hide()
  container:EnableMouse(false)
  container:SetSize(math.max(1, maxN * (size + OVERLAY_PAD)), size)

  if container.SetFlowLayoutAxis and AnchorUtil and AnchorUtil.FlowLayoutAxis then
    pcall(container.SetFlowLayoutAxis, container, AnchorUtil.FlowLayoutAxis.Horizontal)
    pcall(container.SetFlowLayoutAnchorPoint, container, "BOTTOMLEFT")
    if AnchorUtil.FlowDirection then
      pcall(container.SetFlowLayoutGrowthDirection, container,
        AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)
    end
  end
  pcall(container.SetFlowLayoutPadding, container, 0, 0, 0, 0)

  local groupOpts = {
    maxFrameCount = maxN,
    candidateFilters = {
      isFromPlayerOrPlayerPet = true,
    },
    sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Expiration or nil,
    sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal or nil,
    initializeFrame = function(button)
      InitAuraButton(button, size)
    end,
    layout = {
      elementWidth = size,
      elementHeight = size,
      elementSpacing = OVERLAY_PAD,
    },
  }

  local okAdd = pcall(container.AddAuraGroup, container, AC_GROUP, "HARMFUL", groupOpts)
  if not okAdd then
    groupOpts.candidateFilters = nil
    okAdd = pcall(container.AddAuraGroup, container, AC_GROUP, "HARMFUL", groupOpts)
  end
  if not okAdd then
    acCreateFailed = true
    pcall(container.Hide, container)
    return nil
  end

  pcall(container.SetAuraGroupMaxFrameCount, container, AC_GROUP, maxN)
  container._plateband = true
  container._iconSize = size
  return container
end

local function SetNativeParked(plate, park)
  local list = NativeDebuffList(plate)
  if not list then
    return
  end
  pcall(function()
    if park then
      if list.SetAlpha then
        list:SetAlpha(0)
      end
    else
      if list.SetAlpha then
        list:SetAlpha(1)
      end
    end
  end)
end

local function AnchorBand(container, unit)
  local plate = PlateFor(unit)
  if not plate or not container then
    return false
  end
  if IsForbiddenPlate(plate) then
    container:Hide()
    return false
  end

  local ok = pcall(function()
    local uf = plate.UnitFrame
    local parent = uf or plate
    if container:GetParent() ~= parent then
      container:SetParent(parent)
      local strata = "MEDIUM"
      pcall(function()
        strata = parent:GetFrameStrata() or "MEDIUM"
      end)
      if strata == "HIGH" or strata == "DIALOG" or strata == "FULLSCREEN"
        or strata == "FULLSCREEN_DIALOG" or strata == "TOOLTIP" then
        strata = "MEDIUM"
      end
      container:SetFrameStrata(strata)
      local lvl = 50
      pcall(function()
        lvl = (parent:GetFrameLevel() or 1) + 20
      end)
      container:SetFrameLevel(lvl)
    end

    local bar = HealthBar(plate)
    local native = NativeDebuffList(plate)
    container:ClearAllPoints()
    -- Group with native debuffs ABOVE the plate (not under-bar).
    if native and SafeShown(native) then
      container:SetPoint("BOTTOMLEFT", native, "BOTTOMLEFT", 0, 0)
    elseif bar then
      container:SetPoint("BOTTOM", bar, "TOP", 0, OVERLAY_GAP_ABOVE)
    else
      container:SetPoint("BOTTOM", plate, "TOP", 0, OVERLAY_GAP_ABOVE)
    end

    local sz = IconSize()
    if container._iconSize ~= sz then
      container._iconSize = sz
      container:SetHeight(sz)
      container:SetWidth(math.max(1, MaxIcons() * (sz + OVERLAY_PAD)))
    end
  end)
  return ok and true or false
end

local function BindUnit(container, unit)
  if not container or not container.SetUnit then
    return
  end
  local bind = unit
  if SameUnit(unit, "target") then
    bind = "target"
  end
  local cur
  pcall(function()
    cur = container.GetUnit and container:GetUnit()
  end)
  if cur ~= bind then
    pcall(container.SetUnit, container, bind)
  else
    pcall(container.UpdateAllAuras, container)
  end
end

local function ModuleActive()
  local p = Profile()
  return p.enabled and not p.safeMode and p.showBand and not acCreateFailed
end

local function ClearOverlay(unit)
  local holder = overlays[unit]
  local plate = PlateFor(unit)
  if plate then
    SetNativeParked(plate, false)
  end
  if not holder then
    return
  end
  pcall(holder.SetEnabled, holder, false)
  holder:Hide()
  holder:ClearAllPoints()
end

local function EnsureOverlay(unit)
  local holder = overlays[unit]
  if holder then
    return holder
  end
  local sz = IconSize()
  holder = CreateBandContainer(UIParent, sz)
  if not holder then
    return nil
  end
  holder:EnableMouse(false)
  holder:Hide()
  holder.plateUnit = unit
  overlays[unit] = holder
  return holder
end

local function UpdateOverlay(unit)
  if not ModuleActive() or not unit then
    return
  end
  if not UnitExists(unit) then
    ClearOverlay(unit)
    return
  end
  local plate = PlateFor(unit)
  if not plate or IsForbiddenPlate(plate) then
    ClearOverlay(unit)
    return
  end

  local holder = EnsureOverlay(unit)
  if not holder then
    return
  end
  holder.plateUnit = unit

  if not AnchorBand(holder, unit) then
    holder:Hide()
    return
  end

  -- Still on UIParent = parent failed; never Show (map punch-through).
  local parentOk = false
  pcall(function()
    parentOk = holder:GetParent() ~= UIParent
  end)
  if not parentOk then
    holder:Hide()
    return
  end

  BindUnit(holder, unit)
  pcall(holder.SetEnabled, holder, true)
  holder:Show()

  local painted = CountShownAuraKids(holder)
  SetNativeParked(plate, painted > 0)
end

local function RefreshAll()
  local live = {}
  for i = 1, 40 do
    local unit = "nameplate" .. i
    if UnitExists(unit) then
      live[unit] = true
      if ModuleActive() then
        UpdateOverlay(unit)
      else
        ClearOverlay(unit)
      end
    end
  end
  for unit in pairs(overlays) do
    if not live[unit] then
      ClearOverlay(unit)
      overlays[unit] = nil
    end
  end
end

local function EnsureTicker()
  if ticker or not C_Timer or not C_Timer.NewTicker then
    return
  end
  ticker = C_Timer.NewTicker(TICKER_SEC, function()
    if not ModuleActive() then
      return
    end
    RefreshAll()
  end)
end

local function StopTicker()
  if ticker then
    pcall(function()
      ticker:Cancel()
    end)
    ticker = nil
  end
end

local function Defer(fn)
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      pcall(fn)
    end)
  else
    pcall(fn)
  end
end

local function OnEvent(_, event, arg1)
  if event == "NAME_PLATE_UNIT_ADDED" then
    local unit = arg1
    Defer(function()
      UpdateOverlay(unit)
    end)
    if C_Timer and C_Timer.After then
      C_Timer.After(0.05, function()
        pcall(UpdateOverlay, unit)
      end)
      C_Timer.After(0.25, function()
        pcall(UpdateOverlay, unit)
      end)
    end
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    ClearOverlay(arg1)
    overlays[arg1] = nil
  elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD"
    or event == "GROUP_ROSTER_UPDATE" then
    Defer(RefreshAll)
  elseif event == "UNIT_AURA" then
    local unit = arg1
    if not unit then
      return
    end
    if type(unit) == "string" and unit:match("^nameplate%d+") then
      Defer(function()
        UpdateOverlay(unit)
      end)
      return
    end
    if unit == "target" or unit == "focus" then
      Defer(RefreshAll)
    end
  elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    if type(arg1) == "string" then
      lastBlocked = arg1
    end
  end
end

function Mod.Start()
  if started then
    RefreshAll()
    EnsureTicker()
    return
  end
  started = true
  eventFrame = eventFrame or CreateFrame("Frame")
  eventFrame:SetScript("OnEvent", function(self, event, ...)
    local ok, err = pcall(OnEvent, self, event, ...)
    if not ok and ns.RecordError then
      ns.RecordError("plates:" .. tostring(event), err)
    end
  end)
  local events = {
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_ENTERING_WORLD",
    "GROUP_ROSTER_UPDATE",
    "ADDON_ACTION_BLOCKED",
    "ADDON_ACTION_FORBIDDEN",
  }
  for i = 1, #events do
    pcall(eventFrame.RegisterEvent, eventFrame, events[i])
  end
  -- UNIT_AURA: unit-scoped only (Mainline-style). Nameplate aura refresh via ticker.
  if eventFrame.RegisterUnitEvent then
    pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_AURA", "target", "focus")
  else
    pcall(eventFrame.RegisterEvent, eventFrame, "UNIT_AURA")
  end
  -- Never register COMBAT_LOG_EVENT_UNFILTERED on Forever.
  EnsureTicker()
  RefreshAll()
end

function Mod.Stop()
  StopTicker()
  for unit in pairs(overlays) do
    ClearOverlay(unit)
  end
  for unit in pairs(overlays) do
    overlays[unit] = nil
  end
end

function Mod.Refresh()
  RefreshAll()
end

function Mod.IsAcFailed()
  return acCreateFailed
end

function Mod.Diagnose()
  local target = UnitExists("target") and "yes" or "no"
  local plateUnit = nil
  local plate = nil
  if UnitExists("target") then
    for i = 1, 40 do
      local u = "nameplate" .. i
      if UnitExists(u) and SameUnit(u, "target") then
        plateUnit = u
        plate = PlateFor(u)
        break
      end
    end
    if not plate then
      plate = PlateFor("target")
    end
  end

  local ac = 0
  local native = 0
  local holder = plateUnit and overlays[plateUnit]
  if holder then
    ac = CountShownAuraKids(holder)
  end
  if plate then
    native = CountShownAuraKids(NativeDebuffList(plate))
  end
  local tf = 0
  if UnitExists("target") then
    tf = CountTargetFrameAuras()
  end

  local card = string.format(
    "PLATEBAND_CARD ver=%s target=%s plate=%s ac=%s tf=%s native=%s acFail=%s enabled=%s safe=%s blocked=%s",
    tostring(ns.Config.VERSION),
    target,
    plateUnit or (plate and "yes" or "no"),
    tostring(ac),
    tostring(tf),
    tostring(native),
    acCreateFailed and "1" or "0",
    tostring(Profile().enabled),
    tostring(Profile().safeMode),
    tostring(lastBlocked)
  )

  local db = ns.Config.EnsureDB()
  db.lastDiag = {
    at = time and time() or 0,
    card = card,
    ac = ac,
    tf = tf,
    native = native,
  }
  return card
end

function Mod.ClearAll()
  Mod.Stop()
end
