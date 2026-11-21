--[[
  Plateband.Modules.Plates — above-plate AuraContainer band.
  Secret-safe plate discovery via GetNamePlates + token fallbacks.
  Auto lastDiagnose → SavedVariables (disk flush only on /reload|logout).
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
local AUTO_DIAG_MIN = 0.5
local WATCH_DEFAULT_SEC = 2

local overlays = {} -- [nameplateUnit] = container
local acCreateFailed = false
local ticker
local watchTicker
local started = false
local eventFrame
local lastBlocked = "none"
local lastTargetPlateUnit
local lastDiagAt = 0
local lastChatSig = nil
local platesSeen = 0
local overlayUpdates = 0

local function Profile()
  return ns.Config.GetProfile()
end

local function IsSecret(v)
  if type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, v)
    return ok and secret and true or false
  end
  return false
end

--- Forever: UnitExists / UnitIsUnit results may be secret — never raw truthy-test secrets.
local function SafeUnitExists(unit)
  if type(unit) ~= "string" or unit == "" then
    return false
  end
  local ok, exists = pcall(UnitExists, unit)
  if not ok then
    return false
  end
  if IsSecret(exists) then
    -- Secret boolean: probe plate / known tokens instead of truthy-test.
    if unit == "target" or unit == "focus" or unit:match("^nameplate%d+") then
      if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local okP, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if okP and plate then
          return true
        end
      end
      -- Optimistic for nameplateN tokens delivered by NAME_PLATE_UNIT_ADDED.
      if unit:match("^nameplate%d+") then
        return true
      end
      -- TargetFrame shown ⇒ treat as having a target.
      if unit == "target" then
        local shown = false
        pcall(function()
          if TargetFrame and TargetFrame.IsShown then
            local s = TargetFrame:IsShown()
            if not IsSecret(s) and s then
              shown = true
            end
          end
        end)
        return shown
      end
    end
    return false
  end
  return exists and true or false
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
  local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
  if ok then
    return plate
  end
  return nil
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

local function PublicString(v)
  if type(v) ~= "string" then
    return nil
  end
  if IsSecret(v) then
    return nil
  end
  if v == "" then
    return nil
  end
  return v
end

local function UnitTokenFromPlate(plate)
  if not plate then
    return nil
  end
  local unit
  pcall(function()
    unit = plate.namePlateUnitToken or plate.nameplateUnitToken
  end)
  unit = PublicString(unit)
  if unit then
    return unit
  end
  pcall(function()
    local uf = plate.UnitFrame
    if uf then
      unit = uf.unit or uf.displayedUnit
    end
  end)
  unit = PublicString(unit)
  if unit then
    return unit
  end
  for i = 1, 40 do
    local u = "nameplate" .. i
    local p = PlateFor(u)
    if p and p == plate then
      return u
    end
  end
  return nil
end

--- Prefer C_NamePlate.GetNamePlates(); fall back to nameplate1..40.
local function EnumerateLivePlates()
  local out = {}
  local seen = {}
  if C_NamePlate and C_NamePlate.GetNamePlates then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and type(plates) == "table" then
      for _, plate in pairs(plates) do
        if plate and not IsForbiddenPlate(plate) then
          local unit = UnitTokenFromPlate(plate)
          if unit and not seen[unit] then
            seen[unit] = true
            out[#out + 1] = { plate = plate, unit = unit }
          elseif not unit then
            -- Plate without public token — still try to attach via synthetic key.
            local key = tostring(plate)
            if not seen[key] then
              seen[key] = true
              out[#out + 1] = { plate = plate, unit = nil }
            end
          end
        end
      end
    end
  end
  for i = 1, 40 do
    local u = "nameplate" .. i
    if not seen[u] then
      local plate = PlateFor(u)
      if plate and not IsForbiddenPlate(plate) then
        seen[u] = true
        out[#out + 1] = { plate = plate, unit = u }
      elseif SafeUnitExists(u) then
        -- Exists but GetNamePlateForUnit failed — still track token for later.
        seen[u] = true
        out[#out + 1] = { plate = PlateFor(u), unit = u }
      end
    end
  end
  return out
end

--- Forever: GetNamePlateForUnit("target") / UnitIsUnit often secret after DoT.
local function NameplateUnitFor(token)
  if not token then
    return nil
  end
  if type(token) == "string" and token:match("^nameplate%d+") then
    return token
  end

  local plate = PlateFor(token)
  if plate then
    local u = UnitTokenFromPlate(plate)
    if u then
      if token == "target" then
        lastTargetPlateUnit = u
      end
      return u
    end
    for i = 1, 40 do
      local np = "nameplate" .. i
      if PlateFor(np) == plate then
        if token == "target" then
          lastTargetPlateUnit = np
        end
        return np
      end
    end
  end

  for i = 1, 40 do
    local u = "nameplate" .. i
    if SafeUnitExists(u) and SameUnit(u, token) then
      if token == "target" then
        lastTargetPlateUnit = u
      end
      return u
    end
  end

  local guid
  pcall(function()
    guid = UnitGUID(token)
  end)
  if guid and not IsSecret(guid) then
    for i = 1, 40 do
      local u = "nameplate" .. i
      if SafeUnitExists(u) then
        local g
        pcall(function()
          g = UnitGUID(u)
        end)
        if g and not IsSecret(g) and g == guid then
          if token == "target" then
            lastTargetPlateUnit = u
          end
          return u
        end
      end
    end
  end

  local tName
  local tNamePublic = false
  pcall(function()
    tName = UnitName(token)
    if type(tName) == "string" and not IsSecret(tName) and tName ~= "" then
      tNamePublic = true
    end
  end)
  if tNamePublic then
    for i = 1, 40 do
      local u = "nameplate" .. i
      if SafeUnitExists(u) then
        local matched = false
        pcall(function()
          local n = UnitName(u)
          if type(n) == "string" and not IsSecret(n) and n == tName then
            matched = true
          end
        end)
        if matched then
          if token == "target" then
            lastTargetPlateUnit = u
          end
          return u
        end
      end
    end
  end

  if token == "target" and lastTargetPlateUnit and SafeUnitExists(lastTargetPlateUnit) then
    return lastTargetPlateUnit
  end

  -- Sole non-player live plate while we believe we have a target.
  if token == "target" then
    local live = EnumerateLivePlates()
    local only, n = nil, 0
    for i = 1, #live do
      local u = live[i].unit
      if u and not SameUnit(u, "player") then
        local skipPlayer = false
        pcall(function()
          local okP, isPlayer = pcall(UnitIsPlayer, u)
          if okP and not IsSecret(isPlayer) and isPlayer then
            skipPlayer = true
          end
        end)
        if not skipPlayer then
          n = n + 1
          only = u
          if n > 1 then
            only = nil
            break
          end
        end
      end
    end
    if only then
      lastTargetPlateUnit = only
      return only
    end
  end

  return nil
end

local function HasTarget()
  if PlateFor("target") then
    return true
  end
  if SafeUnitExists("target") then
    return true
  end
  if NameplateUnitFor("target") then
    return true
  end
  return false
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
  local live = EnumerateLivePlates()
  for i = 1, #live do
    local list = NativeDebuffList(live[i].plate)
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
    if list.SetAlpha then
      list:SetAlpha(park and 0 or 1)
    end
  end)
end

local function AnchorBand(container, unit, plate)
  plate = plate or PlateFor(unit)
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
  if unit and (SameUnit(unit, "target") or unit == lastTargetPlateUnit) and HasTarget() then
    bind = "target"
  elseif HasTarget() then
    local tp = NameplateUnitFor("target")
    if tp and tp == unit then
      bind = "target"
    end
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
  local plate = unit and PlateFor(unit)
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
  if not unit then
    return nil
  end
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

local function UpdateOverlay(unit, plate)
  if not ModuleActive() or not unit then
    return
  end
  plate = plate or PlateFor(unit)
  if not plate or IsForbiddenPlate(plate) then
    ClearOverlay(unit)
    return
  end

  local holder = EnsureOverlay(unit)
  if not holder then
    return
  end
  holder.plateUnit = unit
  overlayUpdates = overlayUpdates + 1

  if not AnchorBand(holder, unit, plate) then
    holder:Hide()
    return
  end

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

-- Forward decl for auto-diag after RefreshAll
local SnapshotDiagnose
local MaybeAutoDiagnose

local function RefreshAll()
  local live = {}
  local list = EnumerateLivePlates()
  for i = 1, #list do
    local entry = list[i]
    local unit = entry.unit
    local plate = entry.plate
    if unit then
      live[unit] = true
      if ModuleActive() then
        UpdateOverlay(unit, plate)
      else
        ClearOverlay(unit)
      end
    end
  end
  -- Always try target plate explicitly (secret UnitIsUnit fallbacks).
  if ModuleActive() and HasTarget() then
    local tu = NameplateUnitFor("target")
    if tu then
      live[tu] = true
      UpdateOverlay(tu, PlateFor(tu) or PlateFor("target"))
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

local function WatchInterval()
  local n = tonumber(Profile().watchInterval) or WATCH_DEFAULT_SEC
  if n < 1 then
    n = 1
  elseif n > 10 then
    n = 10
  end
  return n
end

local function StopWatchTicker()
  if watchTicker then
    pcall(function()
      watchTicker:Cancel()
    end)
    watchTicker = nil
  end
end

local function EnsureWatchTicker()
  StopWatchTicker()
  if not Profile().watchOn then
    return
  end
  if not C_Timer or not C_Timer.NewTicker then
    return
  end
  watchTicker = C_Timer.NewTicker(WatchInterval(), function()
    if not Profile().watchOn then
      return
    end
    local card = SnapshotDiagnose("watch", { forceChat = true })
    if card and ns.Print then
      ns.Print(card)
    elseif card then
      print("|cff7ec8e3" .. card .. "|r")
    end
  end)
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

SnapshotDiagnose = function(reason, opts)
  opts = opts or {}
  local targetYes = HasTarget()
  local plateUnit = nil
  local plate = nil
  local live = EnumerateLivePlates()
  local plateCount = #live

  if targetYes then
    plateUnit = NameplateUnitFor("target")
    if plateUnit then
      plate = PlateFor(plateUnit) or PlateFor("target")
    else
      plate = PlateFor("target")
    end
  end
  if not plate and plateCount == 1 and live[1] then
    plate = live[1].plate
    plateUnit = plateUnit or live[1].unit
  end

  local ac = 0
  local native = 0
  if plateUnit and overlays[plateUnit] then
    ac = CountShownAuraKids(overlays[plateUnit])
  end
  -- Sum AC across overlays if target-specific is 0
  if ac == 0 then
    for _, holder in pairs(overlays) do
      local n = CountShownAuraKids(holder)
      if n > ac then
        ac = n
      end
    end
  end
  if plate then
    native = CountShownAuraKids(NativeDebuffList(plate))
  elseif plateCount > 0 then
    for i = 1, #live do
      local n = CountShownAuraKids(NativeDebuffList(live[i].plate))
      if n > native then
        native = n
      end
    end
  end

  local tf = 0
  if targetYes then
    tf = CountTargetFrameAuras()
  end

  local overlayN = 0
  for _ in pairs(overlays) do
    overlayN = overlayN + 1
  end

  local card = string.format(
    "PLATEBAND_CARD ver=%s reason=%s target=%s plate=%s plates=%s overlays=%s ac=%s tf=%s native=%s acFail=%s enabled=%s safe=%s watch=%s seen=%s upd=%s blocked=%s",
    tostring(ns.Config.VERSION),
    tostring(reason or "manual"),
    targetYes and "yes" or "no",
    plateUnit or (plate and "yes" or "no"),
    tostring(plateCount),
    tostring(overlayN),
    tostring(ac),
    tostring(tf),
    tostring(native),
    acCreateFailed and "1" or "0",
    tostring(Profile().enabled),
    tostring(Profile().safeMode),
    tostring(Profile().watchOn),
    tostring(platesSeen),
    tostring(overlayUpdates),
    tostring(lastBlocked)
  )

  local snap = {
    at = time and time() or 0,
    reason = tostring(reason or "manual"),
    card = card,
    target = targetYes and "yes" or "no",
    plate = plateUnit or (plate and "yes" or "no"),
    plates = plateCount,
    overlays = overlayN,
    ac = ac,
    tf = tf,
    native = native,
    acFail = acCreateFailed and 1 or 0,
    seen = platesSeen,
    upd = overlayUpdates,
    blocked = lastBlocked,
  }

  local db = ns.Config.EnsureDB()
  db.lastDiagnose = snap
  db.lastDiag = snap -- alias for older readers

  if ns.SessionLog and ns.SessionLog.Append then
    pcall(ns.SessionLog.Append, card)
  end

  local sig = string.format("%s|%s|%s|%s|%s|%s",
    snap.target, tostring(snap.plate), tostring(ac), tostring(tf), tostring(native), tostring(plateCount))

  local chatOnChange = Profile().chatOnChange
  if opts.forceChat then
    -- watch ticker always prints via caller
  elseif chatOnChange and sig ~= lastChatSig then
    lastChatSig = sig
    -- Only announce meaningful transitions (have plates or target), skip idle spam.
    if targetYes or plateCount > 0 or ac > 0 or native > 0 then
      if ns.Print then
        ns.Print(card)
      else
        print("|cff7ec8e3" .. card .. "|r")
      end
    end
  else
    lastChatSig = lastChatSig or sig
  end

  return card, snap
end

MaybeAutoDiagnose = function(reason, force)
  local p = Profile()
  if p.autoDiag == false then
    return
  end
  local now = GetTime and GetTime() or 0
  if not force and (now - lastDiagAt) < AUTO_DIAG_MIN then
    return
  end
  lastDiagAt = now
  pcall(SnapshotDiagnose, reason or "auto", {})
end

local function OnEvent(_, event, arg1)
  if event == "NAME_PLATE_UNIT_ADDED" then
    local unit = arg1
    platesSeen = platesSeen + 1
    if type(unit) == "string" and unit:match("^nameplate%d+") then
      lastTargetPlateUnit = lastTargetPlateUnit -- keep
    end
    Defer(function()
      UpdateOverlay(unit, PlateFor(unit))
      -- Also refresh target binding — added plate may be the target.
      if HasTarget() then
        local tu = NameplateUnitFor("target")
        if tu then
          UpdateOverlay(tu, PlateFor(tu) or PlateFor("target"))
        end
      end
      MaybeAutoDiagnose("plate_added", true)
    end)
    if C_Timer and C_Timer.After then
      C_Timer.After(0.05, function()
        pcall(UpdateOverlay, unit, PlateFor(unit))
      end)
      C_Timer.After(0.25, function()
        pcall(function()
          RefreshAll()
          MaybeAutoDiagnose("plate_added_late", false)
        end)
      end)
    end
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    ClearOverlay(arg1)
    overlays[arg1] = nil
    if lastTargetPlateUnit == arg1 then
      lastTargetPlateUnit = nil
    end
    MaybeAutoDiagnose("plate_removed", false)
  elseif event == "PLAYER_TARGET_CHANGED" then
    lastTargetPlateUnit = nil
    Defer(function()
      RefreshAll()
      MaybeAutoDiagnose("target", true)
    end)
  elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
    Defer(function()
      RefreshAll()
      MaybeAutoDiagnose(event == "PLAYER_ENTERING_WORLD" and "pew" or "roster", true)
    end)
  elseif event == "UNIT_AURA" then
    local unit = arg1
    if not unit then
      return
    end
    if type(unit) == "string" and unit:match("^nameplate%d+") then
      Defer(function()
        UpdateOverlay(unit, PlateFor(unit))
        MaybeAutoDiagnose("aura_np", false)
      end)
      return
    end
    if unit == "target" or unit == "focus" then
      Defer(function()
        RefreshAll()
        MaybeAutoDiagnose("aura_target", false)
      end)
    end
  elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    if type(arg1) == "string" then
      lastBlocked = arg1
      MaybeAutoDiagnose("blocked", true)
    end
  end
end

function Mod.Start()
  if started then
    RefreshAll()
    EnsureTicker()
    EnsureWatchTicker()
    MaybeAutoDiagnose("start", true)
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
  if eventFrame.RegisterUnitEvent then
    pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_AURA", "target", "focus")
  else
    pcall(eventFrame.RegisterEvent, eventFrame, "UNIT_AURA")
  end
  -- Never register COMBAT_LOG_EVENT_UNFILTERED on Forever.
  EnsureTicker()
  EnsureWatchTicker()
  RefreshAll()
  MaybeAutoDiagnose("start", true)
end

function Mod.Stop()
  StopTicker()
  StopWatchTicker()
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
  local card = SnapshotDiagnose("manual", {})
  return card
end

function Mod.SetWatch(on)
  local p = Profile()
  p.watchOn = on and true or false
  EnsureWatchTicker()
  if p.watchOn then
    local card = SnapshotDiagnose("watch_on", { forceChat = true })
    return card
  end
  return nil
end

function Mod.ClearAll()
  Mod.Stop()
end
