--[[
  Plateband.Modules.Plates — native DebuffList stays fully visible.
  Safe default (0.1.12+): merge OFF — Blizzard plates only.
  Hard rule (three-addon refactor): NEVER ClearAllPoints / SetPoint UnitFrame.name.
  Opt-in mergeMissing: paint textures beside native DebuffList only (Docs/merge-design.md).
  No CLEU / no HP recolor / no DebuffList SetPoint.
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

local overlays = {} -- [nameplateUnit] = AuraContainer (or nil)
local fallbacks = {} -- [nameplateUnit] = scrape Frame
local nameShifts = {} -- [nameplateUnit] = { saved points / shifted }
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

local function NativeBuffList(plate)
  local list
  pcall(function()
    local uf = plate and plate.UnitFrame
    local af = uf and uf.AurasFrame
    if af then
      list = af.BuffListFrame
    end
    if not list and uf then
      list = uf.BuffListFrame or uf.BuffFrame
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
    if child and SafeShown(child) then
      -- Require real aura chrome — bare Frame/Button kids false-trigger friend name shifts.
      if child.icon or child.Icon or child.GetAuraInstance then
        n = n + 1
      end
    end
  end
  return n
end

local function RawChildCount(frame)
  if not frame then
    return 0
  end
  local ok, kids = pcall(function()
    return { frame:GetChildren() }
  end)
  if not ok or type(kids) ~= "table" then
    return 0
  end
  return #kids
end

local function CountNativeAuraRow(plate)
  return CountShownAuraKids(NativeDebuffList(plate))
    + CountShownAuraKids(NativeBuffList(plate))
end

--- Friend / player plates: name must sit above auras (preference).
local function IsPlayerOrFriendPlate(unit, plate)
  if not unit then
    return false
  end
  if SameUnit(unit, "player") then
    return true
  end
  local hit = false
  pcall(function()
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if okP and not IsSecret(isPlayer) and isPlayer then
      hit = true
      return
    end
    local okF, isFriend = pcall(UnitIsFriend, "player", unit)
    if okF and not IsSecret(isFriend) and isFriend then
      hit = true
    end
  end)
  if hit then
    return true
  end
  for i = 1, 4 do
    if SameUnit(unit, "party" .. i) then
      return true
    end
  end
  for i = 1, 40 do
    if SameUnit(unit, "raid" .. i) then
      return true
    end
  end
  return false
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

-- Forward decls: TF harvest must see these locals (Lua scope — nil global = dead merge).
local IconSize
local MaxIcons

--- Forever TF auras live in auraPools — GetChildren() alone often yields tf=0.
local function HarvestAuraPoolButtons(pools, out, maxN)
  if type(pools) ~= "table" or not out then
    return
  end
  maxN = maxN or MaxIcons()
  local function take(btn)
    if not btn or #out >= maxN then
      return
    end
    if SafeShown(btn) or btn.Icon or btn.icon or btn.GetAuraInstance then
      out[#out + 1] = btn
    end
  end
  pcall(function()
    if pools.EnumerateActiveAuraButtons then
      for btn in pools:EnumerateActiveAuraButtons() do
        take(btn)
        if #out >= maxN then
          return
        end
      end
    end
  end)
  pcall(function()
    if pools.EnumerateActive then
      for frame in pools:EnumerateActive() do
        take(frame)
        if #out >= maxN then
          return
        end
      end
    end
  end)
  for _, pool in pairs(pools) do
    if type(pool) == "table" and #out < maxN then
      pcall(function()
        if pool.EnumerateActiveAuraButtons then
          for btn in pool:EnumerateActiveAuraButtons() do
            take(btn)
            if #out >= maxN then
              return
            end
          end
        elseif pool.EnumerateActive then
          for frame in pool:EnumerateActive() do
            take(frame)
            if #out >= maxN then
              return
            end
          end
        end
      end)
    end
  end
end

local function CollectTargetFrameButtons(out, maxN)
  maxN = maxN or MaxIcons()
  local container = GetTargetAuraContainer()
  if container then
    pcall(HarvestAuraPoolButtons, container.auraPools, out, maxN)
    if #out == 0 then
      -- Fallback: direct children (retail-style).
      local ok, kids = pcall(function()
        return { container:GetChildren() }
      end)
      if ok and type(kids) == "table" then
        for i = 1, #kids do
          if #out >= maxN then
            break
          end
          local child = kids[i]
          if child and (child.Icon or child.icon or child.GetAuraInstance) then
            out[#out + 1] = child
          end
        end
      end
    end
    if container.debuffAuraGroup and container.debuffAuraGroup.GetFramesByIndex then
      pcall(function()
        local frames = container.debuffAuraGroup:GetFramesByIndex()
        if type(frames) == "table" then
          for i = 1, #frames do
            if #out >= maxN then
              return
            end
            local f = frames[i]
            if f then
              out[#out + 1] = f
            end
          end
        end
      end)
    end
  end
  if TargetFrame then
    pcall(HarvestAuraPoolButtons, TargetFrame.auraPools, out, maxN)
  end
  for i = 1, 16 do
    if #out >= maxN then
      break
    end
    local frame = _G["TargetFrameDebuff" .. i]
    if frame and SafeShown(frame) then
      out[#out + 1] = frame
    end
  end
end

local function CountTargetFrameAuras()
  local buttons = {}
  CollectTargetFrameButtons(buttons, MaxIcons())
  local n = 0
  local seen = {}
  for i = 1, #buttons do
    local btn = buttons[i]
    local id = tostring(btn)
    if not seen[id] then
      seen[id] = true
      if SafeShown(btn) or btn.Icon or btn.icon or btn.GetAuraInstance then
        n = n + 1
      end
    end
  end
  return n
end

IconSize = function()
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

MaxIcons = function()
  local n = tonumber(Profile().maxIcons) or 12
  if n < 1 then
    n = 1
  elseif n > 16 then
    n = 16
  end
  return n
end

local function InitAuraButton(button, size)
  -- Forever aura icons are often masked: SetTexCoord → FE flood
  -- "Texture:SetTextCoord(): Cannot set tex coords when texture has mask"
  -- and broken initializeFrame leaves AuraContainer empty (ac=0).
  pcall(function()
    button:SetSize(size, size)
  end)
  pcall(function()
    button:EnableMouse(true)
    if button.SetMouseMotionEnabled then
      button:SetMouseMotionEnabled(true)
    end
    if button.SetMouseClickEnabled then
      button:SetMouseClickEnabled(false)
    end
  end)

  local icon = button.icon or button.Icon
  if not icon then
    icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    button.icon = icon
  end
  -- Do NOT SetTexCoord on Forever (masked FileDataIDs).
  if button.SetIcon then
    pcall(button.SetIcon, button, icon)
  end

  if not button.cooldown then
    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button)
    cd:EnableMouse(false)
    pcall(cd.SetDrawBling, cd, false)
    pcall(cd.SetReverse, cd, true)
    pcall(cd.SetDrawSwipe, cd, true)
    -- Neutral dark swipe only — no orange/sepia tint.
    pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0.5)
    pcall(cd.SetHideCountdownNumbers, cd, false)
    button.cooldown = cd
    if button.SetDurationCooldown then
      pcall(button.SetDurationCooldown, button, cd)
    end
  end

  if not button.count then
    local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    button.count = count
    if button.SetApplicationCount then
      pcall(button.SetApplicationCount, button, count)
    end
  end

  if button.SetDurationText and not button._pbDur then
    local dur = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    dur:SetPoint("CENTER", button, "CENTER", 0, 1)
    pcall(button.SetDurationText, button, dur)
    button._pbDur = dur
  end
end

local function CreateBandContainer(parent, size)
  if acCreateFailed then
    return nil
  end
  local container
  for _, tpl in ipairs({ "CustomAuraContainerTemplate", "ManagedAuraContainerTemplate" }) do
    -- Try AuraContainer type first, then Frame+template (Forever variance).
    for _, ftype in ipairs({ "AuraContainer", "Frame" }) do
      local ok, c = pcall(CreateFrame, ftype, nil, parent, tpl)
      if ok and c and c.AddAuraGroup then
        container = c
        break
      end
    end
    if container then
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

  -- Solo personal DoTs first (party-share path later).
  local function makeOpts(withPlayerFilter)
    return {
      maxFrameCount = maxN,
      candidateFilters = withPlayerFilter and { isFromPlayerOrPlayerPet = true } or nil,
      sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Expiration or nil,
      sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal or nil,
      initializeFrame = function(button)
        pcall(InitAuraButton, button, size)
      end,
      layout = {
        elementWidth = size,
        elementHeight = size,
        elementSpacing = OVERLAY_PAD,
      },
    }
  end

  local okAdd = false
  local tries = {
    { "HARMFUL|PLAYER", true },
    { "HARMFUL|PLAYER", false },
    { "HARMFUL", true },
    { "HARMFUL", false },
  }
  for i = 1, #tries do
    local filter, withPf = tries[i][1], tries[i][2]
    okAdd = pcall(container.AddAuraGroup, container, AC_GROUP, filter, makeOpts(withPf))
    if okAdd then
      container._pbFilter = filter
      break
    end
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

--- Always keep native DebuffList fully visible (solo native-first).
--- Never ClearAllPoints on DebuffList — 0.1.8 orphaned icons when SetPoint FORBIDDEN.
local function EnsureNativeVisible(plate)
  local function restore(list)
    if not list then
      return
    end
    pcall(function()
      if list.SetAlpha then
        list:SetAlpha(1)
      end
    end)
    pcall(function()
      if list.Show and not SafeShown(list) then
        list:Show()
      end
    end)
  end
  restore(NativeDebuffList(plate))
  restore(NativeBuffList(plate))
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
    container:ClearAllPoints()
    -- One above-plate group (same slot as native DebuffList — not beside it).
    if bar then
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
  -- Solo personal DoTs: Forever often only surfaces them on AuraContainer via "target".
  local bind = unit
  if HasTarget() then
    local tp = NameplateUnitFor("target")
    if (tp and tp == unit)
      or SameUnit(unit, "target")
      or unit == lastTargetPlateUnit
      or PlateFor(unit) == PlateFor("target") then
      bind = "target"
      if type(unit) == "string" then
        lastTargetPlateUnit = unit
      end
    end
  end
  local cur
  pcall(function()
    cur = container.GetUnit and container:GetUnit()
  end)
  if cur ~= bind then
    pcall(container.SetUnit, container, bind)
  end
  pcall(container.UpdateAllAuras, container)
end

local function ModuleActive()
  local p = Profile()
  return p.enabled and not p.safeMode and p.showBand and not acCreateFailed
end

local function ClearFallback(unit)
  local fb = fallbacks[unit]
  if not fb then
    return
  end
  if fb.icons then
    for i = 1, #fb.icons do
      fb.icons[i]:Hide()
    end
  end
  fb:Hide()
  fb:ClearAllPoints()
end

local function PlateNameFS(plate)
  local name
  pcall(function()
    local uf = plate and plate.UnitFrame
    name = uf and uf.name
  end)
  return name
end

--- Intentionally no-ops: three-addon refactor forbids any name ClearAllPoints/SetPoint.
--- Prior versions saved/restored name anchors and broke Forever plates; /reload resets Blizzard layout.
local function SaveNamePoints(unit, nameFS)
  return
end

local function RestoreNameShift(unit, plate)
  if unit then
    nameShifts[unit] = nil
  end
end

-- Forward decl: Layout anchors merge beside native (defined below).
local NativeBandRightAnchor

--- Opt-in merge layout: only move Plateband fallback frame — never name / DebuffList.
local function LayoutMergeBesideNative(unit, plate, mergeFb, painted)
  painted = tonumber(painted) or 0
  if IsPlayerOrFriendPlate(unit, plate) then
    return
  end
  if not mergeFb or painted <= 0 then
    return
  end

  local bar = HealthBar(plate)
  local native = NativeDebuffList(plate)
  mergeFb:ClearAllPoints()
  local right = NativeBandRightAnchor(plate)
  if right then
    -- Same band as native: continue LEFT→RIGHT of rightmost native icon.
    mergeFb:SetPoint("LEFT", right, "RIGHT", OVERLAY_PAD, 0)
  elseif native and SafeShown(native) then
    mergeFb:SetPoint("LEFT", native, "RIGHT", OVERLAY_PAD, 0)
  elseif bar then
    mergeFb:SetPoint("BOTTOM", bar, "TOP", 0, OVERLAY_GAP_ABOVE)
  else
    mergeFb:SetPoint("BOTTOM", plate, "TOP", 0, OVERLAY_GAP_ABOVE)
  end
end

local function ClearOverlay(unit)
  local plate = unit and PlateFor(unit)
  if plate then
    EnsureNativeVisible(plate)
  end
  RestoreNameShift(unit, plate)
  local holder = overlays[unit]
  if holder then
    pcall(holder.SetEnabled, holder, false)
    holder:Hide()
    holder:ClearAllPoints()
  end
  ClearFallback(unit)
end

local function EnsureOverlay(unit)
  if not unit then
    return nil
  end
  local holder = overlays[unit]
  if holder then
    return holder
  end
  if acCreateFailed then
    return nil
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

local function EnsureFallback(unit, parent)
  local fb = fallbacks[unit]
  if fb then
    if parent and fb:GetParent() ~= parent then
      pcall(fb.SetParent, fb, parent)
    end
    return fb
  end
  fb = CreateFrame("Frame", nil, parent or UIParent)
  fb:EnableMouse(false)
  fb:Hide()
  fb.icons = {}
  local maxN = MaxIcons()
  local sz = IconSize()
  for i = 1, maxN do
    local tex = fb:CreateTexture(nil, "ARTWORK")
    tex:SetSize(sz, sz)
    tex:Hide()
    -- No SetTexCoord — Forever masks.
    fb.icons[i] = tex
  end
  fb._pbFallback = true
  fallbacks[unit] = fb
  return fb
end

--- Collect aura icon textures from a frame tree (native DebuffList / TF).
--- Pass textures straight into SetTexture — never compare secret FileIDs.
--- Direct aura buttons only — no deep recurse (nested Icon frames caused dup stacks).
local function CollectAuraTextures(root, out, maxN)
  if not root or #out >= maxN then
    return
  end
  local ok, kids = pcall(function()
    return { root:GetChildren() }
  end)
  if not ok or type(kids) ~= "table" then
    return
  end
  for i = 1, #kids do
    if #out >= maxN then
      return
    end
    local child = kids[i]
    if child and SafeShown(child) then
      local iconTex = child.Icon or child.icon
      if iconTex then
        local file
        pcall(function()
          if iconTex.GetTexture then
            file = iconTex:GetTexture()
          end
        end)
        -- Secret FileIDs are SetTexture-safe.
        if file ~= nil then
          out[#out + 1] = file
        else
          out[#out + 1] = iconTex
        end
      end
    end
  end
end

--- Public texture key for dedupe — nil when secret / unkeyable (skip paint to avoid dups).
local function PublicTexKey(t)
  local key
  pcall(function()
    if type(t) == "number" or type(t) == "string" then
      if not IsSecret(t) then
        key = tostring(t)
      end
    elseif type(t) == "table" or type(t) == "userdata" then
      if t.GetTexture then
        local file = t:GetTexture()
        if (type(file) == "number" or type(file) == "string") and not IsSecret(file) then
          key = tostring(file)
        end
      end
    end
  end)
  return key
end

local function NativeKeySet(plate)
  local keys = {}
  local texes = {}
  CollectAuraTextures(NativeDebuffList(plate), texes, MaxIcons())
  for i = 1, #texes do
    local k = PublicTexKey(texes[i])
    if k then
      keys[k] = true
    end
  end
  return keys
end

--- Rightmost shown native aura button (or DebuffListFrame) — merge anchors beside it.
NativeBandRightAnchor = function(plate)
  local list = NativeDebuffList(plate)
  if not list then
    return nil
  end
  local rightmost, bestRight
  local ok, kids = pcall(function()
    return { list:GetChildren() }
  end)
  if ok and type(kids) == "table" then
    for i = 1, #kids do
      local child = kids[i]
      if child and SafeShown(child) and (child.Icon or child.icon or child.GetAuraInstance) then
        local r
        pcall(function()
          r = child:GetRight()
        end)
        if type(r) == "number" and not IsSecret(r) then
          if not bestRight or r > bestRight then
            bestRight = r
            rightmost = child
          end
        elseif not rightmost then
          rightmost = child
        end
      end
    end
  end
  if rightmost then
    return rightmost
  end
  if SafeShown(list) then
    return list
  end
  return list
end

local function IsTargetPlate(unit, plate)
  if not HasTarget() then
    return false
  end
  if SameUnit(unit, "target") then
    return true
  end
  local tu = NameplateUnitFor("target")
  if tu and tu == unit then
    return true
  end
  if plate and PlateFor("target") == plate then
    return true
  end
  return false
end

--- True when aura data is publicly player/pet-owned (nil = unknown/secret).
local function AuraIsPlayerOwned(data)
  if not data then
    return nil
  end
  local owned
  pcall(function()
    local v = data.isFromPlayerOrPlayerPet
    if not IsSecret(v) then
      owned = v and true or false
    end
  end)
  if owned ~= nil then
    return owned
  end
  local src
  pcall(function()
    src = data.sourceUnit
  end)
  if type(src) == "string" and not IsSecret(src) then
    if SameUnit(src, "player") or SameUnit(src, "pet") then
      return true
    end
  end
  return nil
end

--- Public texture keys known to be player-owned (skip even if native keys are secret).
local function CollectPlayerOwnedKeys(unitToken, into)
  if not unitToken or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
    return
  end
  for i = 1, 40 do
    local data
    local ok = pcall(function()
      data = C_UnitAuras.GetAuraDataByIndex(unitToken, i, "HARMFUL")
    end)
    if not ok or not data then
      break
    end
    if AuraIsPlayerOwned(data) == true then
      local key = PublicTexKey(data.icon)
      if key then
        into[key] = true
      end
    end
  end
end

--- Dedupe key: public texture, else public spellId, else nil (caller may still paint).
local function AuraDedupeKey(data, icon)
  local key = PublicTexKey(icon)
  if key then
    return key
  end
  if data then
    local spellKey
    pcall(function()
      local id = data.spellId
      if type(id) == "number" and not IsSecret(id) then
        spellKey = "spell:" .. tostring(id)
      end
    end)
    if spellKey then
      return spellKey
    end
  end
  return nil
end

--- Source looks like another unit (not local player/pet) — include foreign like "Ours".
local function AuraLooksForeign(data)
  if not data then
    return false
  end
  local src
  pcall(function()
    src = data.sourceUnit
  end)
  if type(src) ~= "string" or IsSecret(src) or src == "" then
    return false
  end
  if SameUnit(src, "player") or SameUnit(src, "pet") then
    return false
  end
  -- Any other public unit token (partyN, nameplateN, raidN, or player name token).
  return true
end

--- All harmful Blizzard may omit: other players (party or not). Not party-only.
--- allowSecretUnknown: target/enemy path — take secret icons when ownership isn't clearly ours.
local function CollectUnitAuraMissing(unitToken, skipKeys, out, maxN, allowSecretUnknown)
  if not unitToken or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
    return
  end
  for i = 1, 40 do
    if #out >= maxN then
      return
    end
    local data
    local ok = pcall(function()
      data = C_UnitAuras.GetAuraDataByIndex(unitToken, i, "HARMFUL")
    end)
    if not ok or not data then
      break
    end

    local owned = AuraIsPlayerOwned(data)
    -- Skip only clearly *our* auras — native DebuffList owns those.
    if owned == true then
      -- skip
    else
      local icon = data.icon
      local key = AuraDedupeKey(data, icon)
      local take = false
      if key and not skipKeys[key] then
        take = true
      elseif not key then
        -- Secret FileID: take when not ours, foreign source, or target allow-secret path.
        if owned == false or AuraLooksForeign(data) or allowSecretUnknown then
          take = true
          key = "sec:" .. tostring(i) .. ":" .. tostring(unitToken)
        end
      end
      if take and key and not skipKeys[key] then
        out[#out + 1] = icon
        skipKeys[key] = true
      end
    end
  end
end

--- Pull icon texture from a TF aura button (secret FileIDs OK for SetTexture).
--- Returns icon, skippedPersonal, gotIcon — never compare icon to nil (secret throws).
local function ButtonAuraIcon(btn)
  if not btn then
    return nil, false, false
  end
  local icon
  local skippedPersonal = false
  local got = false
  pcall(function()
    if btn.GetAuraInstance then
      local _, data = btn:GetAuraInstance()
      if type(data) == "table" then
        if AuraIsPlayerOwned(data) == true then
          skippedPersonal = true
          return
        end
        icon = data.icon
        got = true
      end
    end
  end)
  if skippedPersonal then
    return nil, true, false
  end
  if got then
    return icon, false, true
  end
  local tex = btn.Icon or btn.icon
  if tex then
    local file
    local gotFile = false
    pcall(function()
      if tex.GetTexture then
        file = tex:GetTexture()
        gotFile = true
      end
    end)
    if gotFile then
      return file, false, true
    end
    return tex, false, true
  end
  return nil, false, false
end

--- Brute TF walk — Forever often paints icons while auraPools/GetFramesByIndex are empty.
local function ScrapeTargetFrameIconsBrute(skipKeys, out, maxN)
  if not TargetFrame or #out >= maxN then
    return
  end
  local function isCastBar(frame)
    local hit = false
    pcall(function()
      local n = frame.GetName and frame:GetName()
      if type(n) == "string" and (n:find("Casting", 1, true) or n:find("SpellBar", 1, true)
        or n:find("CastBar", 1, true)) then
        hit = true
      end
    end)
    return hit
  end
  local function scan(frame, depth)
    if not frame or depth > 12 or #out >= maxN then
      return
    end
    if isCastBar(frame) then
      return
    end
    pcall(function()
      if not SafeShown(frame) then
        return
      end
      local iconTex = frame.Icon or frame.icon
      if not iconTex then
        return
      end
      local w
      pcall(function()
        w = frame:GetWidth()
      end)
      if type(w) == "number" and not IsSecret(w) and (w < 12 or w > 48) then
        return
      end
      local icon, skippedPersonal, gotIcon = ButtonAuraIcon(frame)
      if skippedPersonal or not gotIcon then
        return
      end
      local key = PublicTexKey(icon)
      if not key then
        key = "tfbrute:" .. tostring(frame)
      end
      if key and not skipKeys[key] then
        out[#out + 1] = icon
        skipKeys[key] = true
      end
    end)
    local ok, kids = pcall(function()
      return { frame:GetChildren() }
    end)
    if ok and type(kids) == "table" then
      for i = 1, #kids do
        scan(kids[i], depth + 1)
        if #out >= maxN then
          return
        end
      end
    end
  end
  local container = GetTargetAuraContainer()
  if container then
    scan(container, 0)
  end
  -- Contextual Auras only — never whole TargetFrame (scoops cast bar).
end

--- TargetFrame scrape via Forever auraPools (+ brute + public/secret textures).
local function CollectTargetFrameMissing(skipKeys, out, maxN)
  local buttons = {}
  CollectTargetFrameButtons(buttons, maxN)
  local seenBtn = {}
  for i = 1, #buttons do
    if #out >= maxN then
      return
    end
    local btn = buttons[i]
    local bid = tostring(btn)
    if not seenBtn[bid] then
      seenBtn[bid] = true
      local icon, skippedPersonal, gotIcon = ButtonAuraIcon(btn)
      if not skippedPersonal and gotIcon then
        local key = PublicTexKey(icon)
        if not key then
          key = "tf:" .. bid
        end
        if key and not skipKeys[key] then
          out[#out + 1] = icon
          skipKeys[key] = true
        end
      end
    end
  end
  if #out < maxN then
    ScrapeTargetFrameIconsBrute(skipKeys, out, maxN)
  end
  -- activeDebuffs table (Forever)
  if TargetFrame and type(TargetFrame.activeDebuffs) == "table" and #out < maxN then
    pcall(function()
      for _, aura in pairs(TargetFrame.activeDebuffs) do
        if #out >= maxN then
          return
        end
        if type(aura) == "table" and (aura.icon or aura.Icon or aura.GetAuraInstance) then
          if aura.Icon or aura.icon or aura.GetAuraInstance then
            local asBtn = aura
            if asBtn.GetAuraInstance or asBtn.Icon or asBtn.icon then
              local icon, skippedPersonal, gotIcon = ButtonAuraIcon(asBtn)
              if not skippedPersonal and gotIcon then
                local key = PublicTexKey(icon) or ("tfadbtn:" .. tostring(aura))
                if not skipKeys[key] then
                  out[#out + 1] = icon
                  skipKeys[key] = true
                end
              end
            end
          end
          if AuraIsPlayerOwned(aura) ~= true then
            local icon = aura.icon
            local key = AuraDedupeKey(aura, icon)
            if not key then
              key = "tfad:" .. tostring(aura)
            end
            if key and not skipKeys[key] then
              out[#out + 1] = icon
              skipKeys[key] = true
            end
          end
        end
      end
    end)
  end
end

local function SetIconTexture(icon, t)
  local okSet = false
  pcall(function()
    if type(t) == "table" or type(t) == "userdata" then
      if t.GetTexture then
        icon:SetTexture(t:GetTexture())
        okSet = true
      end
    else
      icon:SetTexture(t)
      okSet = true
    end
  end)
  return okSet
end

--- Paint only missing (others') icons beside native DebuffList — never replace native.
local function PaintMergeMissing(unit, plate)
  local uf = plate and plate.UnitFrame
  local parent = uf or plate
  if not parent then
    return 0
  end

  EnsureNativeVisible(plate)
  RestoreNameShift(unit, plate)

  -- Friend/party plates: never merge.
  if IsPlayerOrFriendPlate(unit, plate) then
    ClearFallback(unit)
    return 0
  end

  -- skipKeys = native DebuffList + known player-owned (never re-paint personal).
  local skipKeys = NativeKeySet(plate)
  local maxN = MaxIcons()
  local missing = {}
  local isTarget = IsTargetPlate(unit, plate)

  -- Target plate: merge TF + unit auras Blizzard omitted from DebuffList.
  if isTarget then
    CollectPlayerOwnedKeys("target", skipKeys)
    if type(unit) == "string" and unit ~= "target" then
      CollectPlayerOwnedKeys(unit, skipKeys)
    end
    CollectUnitAuraMissing("target", skipKeys, missing, maxN, true)
    if type(unit) == "string" and unit ~= "target" then
      CollectUnitAuraMissing(unit, skipKeys, missing, maxN, true)
    end
    CollectTargetFrameMissing(skipKeys, missing, maxN)
  else
    CollectPlayerOwnedKeys(unit, skipKeys)
    CollectUnitAuraMissing(unit, skipKeys, missing, maxN, true)
  end

  if #missing == 0 then
    ClearFallback(unit)
    return 0
  end

  local fb = EnsureFallback(unit, parent)
  local sz = IconSize()
  local painted = 0
  for i = 1, #missing do
    if painted >= maxN then
      break
    end
    painted = painted + 1
    local icon = fb.icons[painted]
    icon:ClearAllPoints()
    icon:SetSize(sz, sz)
    icon:SetPoint("LEFT", fb, "LEFT", (painted - 1) * (sz + OVERLAY_PAD), 0)
    if SetIconTexture(icon, missing[i]) then
      icon:Show()
    else
      icon:Hide()
      painted = painted - 1
    end
  end
  for i = painted + 1, #fb.icons do
    fb.icons[i]:Hide()
  end

  if painted == 0 then
    fb:Hide()
    fb._painted = 0
    return 0
  end

  fb:SetSize(math.max(1, painted * (sz + OVERLAY_PAD)), sz)
  fb:SetFrameStrata("MEDIUM")
  local lvl = 50
  pcall(function()
    lvl = (parent:GetFrameLevel() or 1) + 15
  end)
  fb:SetFrameLevel(lvl)
  fb:Show()
  fb._painted = painted

  LayoutMergeBesideNative(unit, plate, fb, painted)
  return painted
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

  overlayUpdates = overlayUpdates + 1
  EnsureNativeVisible(plate)

  -- Never use full AC overlay paint (duplicates personal / covers name).
  local holder = overlays[unit]
  if holder then
    pcall(holder.SetEnabled, holder, false)
    holder:Hide()
    holder:ClearAllPoints()
  end

  local p = Profile()
  -- 0.1.12 safe default: mergeMissing=false → native DebuffList only, no chrome.
  ClearFallback(unit)
  RestoreNameShift(unit, plate)
  if p.mergeMissing ~= true then
    return
  end

  PaintMergeMissing(unit, plate)
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
  for unit in pairs(fallbacks) do
    if not live[unit] then
      ClearFallback(unit)
      fallbacks[unit] = nil
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

  local fb = 0
  local kids = 0
  if plateUnit and overlays[plateUnit] then
    kids = RawChildCount(overlays[plateUnit])
  end
  if plateUnit and fallbacks[plateUnit] then
    fb = tonumber(fallbacks[plateUnit]._painted) or 0
  end
  if fb == 0 then
    for _, f in pairs(fallbacks) do
      local n = tonumber(f._painted) or 0
      if n > fb then
        fb = n
      end
    end
  end

  local card = string.format(
    "PLATEBAND_CARD ver=%s reason=%s target=%s plate=%s plates=%s overlays=%s ac=%s fb=%s kids=%s tf=%s native=%s acFail=%s enabled=%s safe=%s watch=%s seen=%s upd=%s blocked=%s",
    tostring(ns.Config.VERSION),
    tostring(reason or "manual"),
    targetYes and "yes" or "no",
    plateUnit or (plate and "yes" or "no"),
    tostring(plateCount),
    tostring(overlayN),
    tostring(ac),
    tostring(fb),
    tostring(kids),
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
    fb = fb,
    kids = kids,
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
    nameShifts[arg1] = nil
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
    -- Only record Plateband blocks — BetterBackpack spam was drowning cards.
    if type(arg1) == "string" and arg1:find("Plateband", 1, true) then
      lastBlocked = arg1
      MaybeAutoDiagnose("blocked", true)
    end
  end
end

function Mod.Start()
  acCreateFailed = false
  -- Always wipe any leftover overlay chrome + undo name mutation from ≤0.1.11.
  for unit in pairs(overlays) do
    ClearOverlay(unit)
    overlays[unit] = nil
  end
  for unit in pairs(fallbacks) do
    ClearFallback(unit)
    fallbacks[unit] = nil
  end
  for u in pairs(nameShifts) do
    nameShifts[u] = nil
  end
  local live = EnumerateLivePlates()
  for i = 1, #live do
    if live[i].plate then
      EnsureNativeVisible(live[i].plate)
    end
  end
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
  for unit in pairs(fallbacks) do
    ClearFallback(unit)
    fallbacks[unit] = nil
  end
  for unit in pairs(nameShifts) do
    RestoreNameShift(unit, PlateFor(unit))
    nameShifts[unit] = nil
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
