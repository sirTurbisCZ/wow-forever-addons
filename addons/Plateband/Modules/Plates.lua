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
local lastAuraRefreshAt = 0
local AURA_DEBOUNCE_SEC = 0.12
local GAP_STICKY_SEC = 3.0 -- hold when UNIT_AURA/API flickers empty on target paint (melee refresh)
local SILENT_SWEEP_SEC = 0.5
local gapSticky = {} -- [unit] = { icons = {}, at = number }
local lastPaintDebug = {} -- diagnose: last PaintMergeMissing / Refresh snapshot
local lastSilentSweepAt = 0
-- Forward decl — module fns use assignment form (Lua 5.1: locals invisible above `local function`).
local AnchorBand
local AppendGapRow
local ApplyGapSticky
local AuraCountsAsForeignGaps
local AuraDedupeKey
local AuraIconPresent
local AuraIsOurPersonalOnly
local AuraIsPlayerOwned
local AuraLooksForeign
local BindUnit
local BuildPaintTraceLine
local ButtonAuraIcon
local ButtonAuraIconAny
local ClearFallback
local ClearOverlay
local CollectAuraSlotsGaps
local CollectAuraTextures
local CollectForeignAuraGaps
local CollectPersonalAuraGaps
local CollectPlateDebuffButtons
local CollectPlayerOwnedKeys
local CollectTargetFrameButtons
local CollectTargetFrameMissing
local CollectTargetFramePersonalGaps
local CollectTargetHarmfulFromApi
local CollectTargetHarmfulRows
local CollectUnitHarmfulMirror
local DeduplicateHarmfulRows
local CollectTfActiveDebuffs
local CollectTfAuraSlots
local CopyKeySet
local CountNativeAuraRow
local CountPlateHarmfulShown
local CountShownAuraKids
local CountTargetFrameAuras
local ApplyGapAuraVisual
local EnrichGapAuraEntry
local GapAuraLive
local PruneInactiveGapRows
local CreateBandContainer
local CreateGapAuraButton
local CanonicalGapKey
local EnsureTargetHarmfulParity
local EnsureUnitHarmfulParity
local MergeFriendPlatesEnabled
local GapAuraKey
local MergeRowIconSize
local DedupeGapIcons
local Defer
local EnsureFallback
local EnsureNativeVisible
local EnsureOverlay
local EnsureTicker
local EnsureWatchTicker
local EnumerateLivePlates
local FallbackPaintParent
local FallbackParent
local FrameIsGlobalChrome
local FrameIsShownSafe
local GetTargetAuraContainer
local HarvestAuraPoolButtons
local HarvestTfAuraPool
local HasTarget
local HealthBar
local IconSize
local InitAuraButton
local IsCastOrSpellBarFrame
local IsForbiddenPlate
local IsLikelyBuffFrame
local IsPlayerOrFriendPlate
local IsSecret
local IsTargetPlate
local IsUsableSpellIcon
local LayoutMergeBesideNative
local MaxIcons
local MaybeAutoDiagnose
local ModuleActive
local NameplateUnitFor
local NativeAuraMetrics
local NativeBandRightAnchor
local NativeBuffList
local NativeDebuffAnchorList
local NativeDebuffList
local NativeKeySet
local OnEvent
local OverlayUnitKey
local PaintMergeMissing
local PickRightmostAuraFrame
local PlateAuraPools
local PlateFor
local PlateNameFS
local Profile
local PublicString
local PublicTexKey
local PushTfAuraFrame
local RawChildCount
local RefreshAll
local SamplePlateNativeDebuffSize
local SampleTfDebuffIconSize
local RememberGapSticky
local RefreshHeldGapFallback
local RestoreNameShift
local SafeFallbackParent
local SafeShown
local SafeUnitExists
local SameUnit
local SaveNamePoints
local ScrapeTargetFrameBrute
local SetIconTexture
local ShouldUseTargetAuraSource
local SilentTraceEnabled
local SilentTracePaint
local SilentTraceSweep
local SnapshotDiagnose
local StopTicker
local StopWatchTicker
local TextureHasArt
local TfRowKey
local TfSupplementSkipKeys
local UnitTokenFromPlate
local UpdateOverlay
local WatchInterval

OverlayUnitKey = function(unit, plate)
  if type(unit) == "string" and unit ~= "" and not unit:match("^pb:") then
    return unit
  end
  if plate then
    return "pb:" .. tostring(plate)
  end
  return nil
end

local GLOBAL_UI = {
  UIParent = true,
  PlayerFrame = true,
  TargetFrame = true,
  MainMenuBar = true,
  MultiBarBottomLeft = true,
  MultiBarBottomRight = true,
  MultiBarLeft = true,
  MultiBarRight = true,
  StanceBar = true,
  PetActionBar = true,
  ChatFrame1 = true,
}

Profile = function()
  return ns.Config.GetProfile()
end

IsSecret = function(v)
  if type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, v)
    return ok and secret and true or false
  end
  return false
end

--- Forever: UnitExists / UnitIsUnit results may be secret — never raw truthy-test secrets.
SafeUnitExists = function(unit)
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

SafeShown = function(frame)
  if not frame then
    return false
  end
  local ok, shown = pcall(frame.IsShown, frame)
  if not ok or IsSecret(shown) then
    return false
  end
  return shown and true or false
end

PlateFor = function(unit)
  if not unit or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
    return nil
  end
  local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
  if ok then
    return plate
  end
  return nil
end

IsForbiddenPlate = function(plate)
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

FrameIsGlobalChrome = function(frame)
  if not frame or frame == UIParent then
    return true
  end
  local chrome = false
  pcall(function()
    local n = frame.GetName and frame:GetName()
    if type(n) == "string" and GLOBAL_UI[n] then
      chrome = true
    end
  end)
  return chrome
end

SafeFallbackParent = function(plate)
  if not plate or IsForbiddenPlate(plate) then
    return nil
  end
  local uf = plate.UnitFrame
  if not uf or FrameIsGlobalChrome(uf) then
    return nil
  end
  return uf
end

SameUnit = function(a, b)
  if not a or not b then
    return false
  end
  local ok, same = pcall(UnitIsUnit, a, b)
  if not ok or IsSecret(same) then
    return false
  end
  return same and true or false
end

PublicString = function(v)
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

UnitTokenFromPlate = function(plate)
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
EnumerateLivePlates = function()
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
            local key = OverlayUnitKey(nil, plate)
            if key and not seen[key] then
              seen[key] = true
              out[#out + 1] = { plate = plate, unit = key }
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
NameplateUnitFor = function(token)
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

HasTarget = function()
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

HealthBar = function(plate)
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

NativeDebuffList = function(plate)
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

--- Layout anchor when DebuffListFrame missing but AurasFrame exists (Forever variants).
NativeDebuffAnchorList = function(plate)
  local list = NativeDebuffList(plate)
  if list then
    return list
  end
  pcall(function()
    local uf = plate and plate.UnitFrame
    if uf and uf.AurasFrame then
      list = uf.AurasFrame
    end
  end)
  return list
end

NativeBuffList = function(plate)
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

CountShownAuraKids = function(frame)
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

RawChildCount = function(frame)
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

CountNativeAuraRow = function(plate)
  return CountShownAuraKids(NativeDebuffList(plate))
    + CountShownAuraKids(NativeBuffList(plate))
end

--- Shown harmful on plate — pools enumerate what GetChildren misses on Forever.
CountPlateHarmfulShown = function(plate)
  if not plate then
    return 0
  end
  local buttons = {}
  CollectPlateDebuffButtons(plate, buttons, MaxIcons())
  local n = 0
  for i = 1, #buttons do
    if SafeShown(buttons[i]) then
      n = n + 1
    end
  end
  if n > 0 then
    return n
  end
  return CountShownAuraKids(NativeDebuffList(plate))
end

CopyKeySet = function(src)
  local t = {}
  if type(src) == "table" then
    for k, v in pairs(src) do
      t[k] = v
    end
  end
  return t
end

MergeFriendPlatesEnabled = function()
  local p = Profile()
  if p.mergeMissing ~= true then
    return false
  end
  return p.mergeFriendPlates ~= false
end

--- Friend / player plates: name must sit above auras (preference).
IsPlayerOrFriendPlate = function(unit, plate)
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

GetTargetAuraContainer = function()
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


--- Forever TF auras live in auraPools — GetChildren() alone often yields tf=0.
HarvestAuraPoolButtons = function(pools, out, maxN)
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

--- Nameplate harmful pools (Forever — DebuffList GetChildren often empty while pools paint).
PlateAuraPools = function(plate)
  local pools
  pcall(function()
    local uf = plate and plate.UnitFrame
    local af = uf and uf.AurasFrame
    if af and af.auraPools then
      pools = af.auraPools
    end
    local list = NativeDebuffList(plate)
    if not pools and list and list.auraPools then
      pools = list.auraPools
    end
  end)
  return pools
end

CollectPlateDebuffButtons = function(plate, out, maxN)
  if not plate or not out then
    return
  end
  maxN = maxN or MaxIcons()
  local pools = PlateAuraPools(plate)
  if pools then
    HarvestAuraPoolButtons(pools, out, maxN)
  end
  if #out >= maxN then
    return
  end
  local list = NativeDebuffList(plate)
  if not list then
    return
  end
  local ok, kids = pcall(function()
    return { list:GetChildren() }
  end)
  if not ok or type(kids) ~= "table" then
    return
  end
  for i = 1, #kids do
    if #out >= maxN then
      return
    end
    local child = kids[i]
    if child and (child.Icon or child.icon or child.GetAuraInstance) and SafeShown(child) then
      out[#out + 1] = child
    end
  end
end

FallbackParent = function(plate)
  return NativeDebuffList(plate) or NativeDebuffAnchorList(plate) or SafeFallbackParent(plate)
end

--- When native harmful row is empty, parent on health bar (hidden DebuffList parents clip icons).
FallbackPaintParent = function(plate)
  local nativeN = CountPlateHarmfulShown(plate)
  if nativeN > 0 then
    return FallbackParent(plate)
  end
  local bar = HealthBar(plate)
  if bar and not FrameIsGlobalChrome(bar) then
    return bar
  end
  local uf = plate and plate.UnitFrame
  if uf and not FrameIsGlobalChrome(uf) then
    return uf
  end
  return FallbackParent(plate)
end

CollectTargetFrameButtons = function(out, maxN)
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

CountTargetFrameAuras = function()
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

local GAP_AURA_TEMPLATES = {
  "DebuffButtonTemplate",
  "BuffButtonTemplate",
  "TargetDebuffFrameTemplate",
  "TargetBuffFrameTemplate",
}

CreateGapAuraButton = function(parent, size)
  size = size or IconSize()
  for i = 1, #GAP_AURA_TEMPLATES do
    local tpl = GAP_AURA_TEMPLATES[i]
    local ok, btn = pcall(CreateFrame, "Button", nil, parent, tpl)
    if ok and btn then
      btn:Hide()
      pcall(InitAuraButton, btn, size)
      return btn
    end
  end
  local frame = CreateFrame("Frame", nil, parent)
  frame:Hide()
  pcall(InitAuraButton, frame, size)
  return frame
end

InitAuraButton = function(button, size)
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

CreateBandContainer = function(parent, size)
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
EnsureNativeVisible = function(plate)
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

AnchorBand = function(container, unit, plate)
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

BindUnit = function(container, unit)
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

ModuleActive = function()
  local p = Profile()
  return p.enabled and not p.safeMode and p.showBand and not acCreateFailed
end

ClearFallback = function(unit, keepSticky)
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
  fb._painted = 0
  if not keepSticky then
    gapSticky[unit] = nil
  end
end

PlateNameFS = function(plate)
  local name
  pcall(function()
    local uf = plate and plate.UnitFrame
    name = uf and uf.name
  end)
  return name
end

--- Intentionally no-ops: three-addon refactor forbids any name ClearAllPoints/SetPoint.
--- Prior versions saved/restored name anchors and broke Forever plates; /reload resets Blizzard layout.
SaveNamePoints = function(unit, nameFS)
  return
end

RestoreNameShift = function(unit, plate)
  if unit then
    nameShifts[unit] = nil
  end
end


--- Opt-in merge layout: only move Plateband fallback frame — never name / DebuffList.
LayoutMergeBesideNative = function(unit, plate, mergeFb, painted)
  painted = tonumber(painted) or 0
  if IsPlayerOrFriendPlate(unit, plate) and not MergeFriendPlatesEnabled() then
    return
  end
  if not mergeFb or painted <= 0 then
    return
  end

  local native = NativeDebuffList(plate)
  local _, pad = MergeRowIconSize(plate)
  mergeFb:ClearAllPoints()
  local right = NativeBandRightAnchor(plate)
  local anchor = right or native
  if anchor then
    -- Same horizontal band as native (left-of-health row): continue after rightmost icon.
    pcall(function()
      mergeFb:SetPoint("LEFT", anchor, "RIGHT", pad, 0)
      mergeFb:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)
    end)
  else
    local bar = HealthBar(plate)
    if bar then
      pcall(function()
        mergeFb:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, OVERLAY_GAP_ABOVE)
      end)
    end
  end
end

ClearOverlay = function(unit)
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

EnsureOverlay = function(unit)
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

EnsureFallback = function(unit, plate)
  local parent = FallbackPaintParent(plate)
  if not parent then
    return nil
  end
  local fb = fallbacks[unit]
  if fb then
    if fb._pbGapVer ~= 2 or not fb.icons or not fb.icons[1] then
      fb._pbGapVer = nil
    elseif fb.icons[1] and fb.icons[1].SetTexture and not (fb.icons[1].icon or fb.icons[1].Icon) then
      fb._pbGapVer = nil
    end
    if not fb._pbGapVer then
      if fb.icons then
        for i = 1, #fb.icons do
          pcall(fb.icons[i].Hide, fb.icons[i])
        end
      end
      fb.icons = nil
    else
      if fb:GetParent() ~= parent then
        pcall(fb.SetParent, fb, parent)
      end
      fb._pbPlate = plate
      return fb
    end
  end
  fb = CreateFrame("Frame", nil, parent)
  fb:EnableMouse(false)
  fb:Hide()
  fb.icons = {}
  local maxN = MaxIcons()
  local sz = MergeRowIconSize(plate)
  fb._pbPlate = plate
  for i = 1, maxN do
    local btn = CreateGapAuraButton(fb, sz)
    btn._pbPlate = plate
    fb.icons[i] = btn
  end
  fb._pbFallback = true
  fb._pbGapVer = 2
  fb._pbPlate = plate
  fallbacks[unit] = fb
  return fb
end

--- Collect aura icon textures from a frame tree (native DebuffList / TF).
--- Pass textures straight into SetTexture — never compare secret FileIDs.
--- Direct aura buttons only — no deep recurse (nested Icon frames caused dup stacks).
CollectAuraTextures = function(root, out, maxN)
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
PublicTexKey = function(t)
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

NativeKeySet = function(plate)
  local keys = {}
  local texes = {}
  CollectAuraTextures(NativeDebuffList(plate), texes, MaxIcons())
  for i = 1, #texes do
    local k = PublicTexKey(texes[i])
    if k then
      keys["tex:" .. tostring(k)] = true
    end
  end
  local buttons = {}
  CollectPlateDebuffButtons(plate, buttons, MaxIcons())
  for i = 1, #buttons do
    local icon, _, gotIcon = ButtonAuraIcon(buttons[i])
    if gotIcon and icon then
      local k
      pcall(function()
        if buttons[i].GetAuraInstance then
          local _, data = buttons[i]:GetAuraInstance()
          if data then
            k = GapAuraKey(data, icon)
          end
        end
      end)
      if not k then
        k = GapAuraKey(nil, icon)
      end
      if k then
        keys[k] = true
      end
    end
  end
  return keys
end

local function AuraChromeWidth(frame)
  if not frame then
    return nil
  end
  local w
  pcall(function()
    w = frame:GetWidth()
  end)
  if type(w) ~= "number" or IsSecret(w) then
    return nil
  end
  if w < 12 or w > 48 then
    return nil
  end
  -- Plate/container chrome can report wider than the icon; prefer art child.
  if w > 28 then
    local art = frame.icon or frame.Icon
    if art then
      local iw
      pcall(function()
        iw = art:GetWidth()
      end)
      if type(iw) == "number" and not IsSecret(iw) and iw >= 12 and iw <= 32 then
        return iw
      end
    end
  end
  return w
end

SamplePlateNativeDebuffSize = function(plate)
  if not plate then
    return nil
  end
  local buttons = {}
  CollectPlateDebuffButtons(plate, buttons, MaxIcons())
  local best
  for i = 1, #buttons do
    local btn = buttons[i]
    if btn and SafeShown(btn) then
      local w = AuraChromeWidth(btn)
      if w and (not best or w < best) then
        best = w
      end
    end
  end
  return best
end

SampleTfDebuffIconSize = function()
  local best
  for i = 1, 16 do
    local f = _G["TargetFrameDebuff" .. i]
    if f and SafeShown(f) then
      local w = AuraChromeWidth(f)
      if w and (not best or w < best) then
        best = w
      end
    end
  end
  local container = GetTargetAuraContainer()
  if container and container.debuffAuraGroup and container.debuffAuraGroup.GetFramesByIndex then
    local frames
    pcall(function()
      frames = container.debuffAuraGroup:GetFramesByIndex()
    end)
    if type(frames) == "table" then
      for j = 1, #frames do
        local w = AuraChromeWidth(frames[j])
        if w and (not best or w < best) then
          best = w
        end
      end
    end
  end
  return best
end

--- Match native debuff chrome — reject oversized chrome (stack parent, not aura kid).
NativeAuraMetrics = function(plate)
  local pad = OVERLAY_PAD
  local sz = IconSize()
  local widths = {}
  local buttons = {}
  CollectPlateDebuffButtons(plate, buttons, MaxIcons())
  for i = 1, #buttons do
    local w = AuraChromeWidth(buttons[i])
    if w and w <= 36 then
      widths[#widths + 1] = w
    end
  end
  if #widths > 0 then
    table.sort(widths)
    sz = widths[1]
    if widths[#widths] - widths[1] > 4 then
      local mid = widths[math.ceil(#widths / 2)]
      if mid and mid >= 12 and mid <= 32 then
        sz = mid
      end
    end
  else
    local tf = SampleTfDebuffIconSize()
    if tf then
      sz = tf
    end
  end
  local bar = HealthBar(plate)
  if bar then
    pcall(function()
      local bh = bar:GetHeight()
      if type(bh) == "number" and not IsSecret(bh) and bh > 0 then
        local cap = math.floor(bh * 0.92)
        if cap >= 12 and sz > cap then
          sz = cap
        end
      end
    end)
  end
  if sz < 12 then
    sz = 12
  elseif sz > 32 then
    sz = 32
  end
  return sz, pad
end

--- Gap icons match native plate personal kids when native row visible; else TF personal chrome.
MergeRowIconSize = function(plate, fb)
  local pad = OVERLAY_PAD
  local nativeN = plate and CountPlateHarmfulShown(plate) or 0
  local sz
  if nativeN > 0 then
    sz = SamplePlateNativeDebuffSize(plate) or select(1, NativeAuraMetrics(plate))
  elseif HasTarget() then
    sz = SampleTfDebuffIconSize() or select(1, NativeAuraMetrics(plate))
  else
    sz = select(1, NativeAuraMetrics(plate))
  end
  if fb then
    if nativeN > 0 then
      -- Own DoT on native row sets band size — gap foreign must match (grow lock).
      fb._pbLockedSz = sz
    elseif type(fb._pbLockedSz) == "number" then
      if sz > fb._pbLockedSz then
        sz = fb._pbLockedSz
      else
        fb._pbLockedSz = sz
      end
    else
      fb._pbLockedSz = sz
    end
    sz = fb._pbLockedSz
  end
  local cap = nativeN > 0 and 40 or 32
  if sz < 12 then
    sz = 12
  elseif sz > cap then
    sz = cap
  end
  return sz, pad
end

PickRightmostAuraFrame = function(frames)
  local rightmost, bestRight
  for i = 1, #frames do
    local child = frames[i]
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
  return rightmost
end

--- Rightmost shown native aura button (or DebuffListFrame) — merge anchors beside it.
NativeBandRightAnchor = function(plate)
  local list = NativeDebuffList(plate)
  if not list then
    return nil
  end
  local buttons = {}
  CollectPlateDebuffButtons(plate, buttons, MaxIcons())
  local rightmost = PickRightmostAuraFrame(buttons)
  if rightmost then
    return rightmost
  end
  local ok, kids = pcall(function()
    return { list:GetChildren() }
  end)
  if ok and type(kids) == "table" then
    rightmost = PickRightmostAuraFrame(kids)
  end
  if rightmost then
    return rightmost
  end
  if SafeShown(list) then
    return list
  end
  return list
end

IsTargetPlate = function(unit, plate)
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
  if plate and unit and HasTarget() then
    local tp = PlateFor("target")
    if tp and tp == plate then
      return true
    end
    local live = EnumerateLivePlates()
    local onlyU, onlyP, n = nil, nil, 0
    for i = 1, #live do
      local u = live[i].unit
      local pl = live[i].plate
      if u and pl and not SameUnit(u, "player") and not IsPlayerOrFriendPlate(u, pl) then
        n = n + 1
        onlyU = u
        onlyP = pl
        if n > 1 then
          onlyU = nil
          onlyP = nil
          break
        end
      end
    end
    if n == 1 and onlyU == unit and onlyP == plate then
      return true
    end
  end
  return false
end

ShouldUseTargetAuraSource = function(unit, plate)
  if not HasTarget() then
    return false
  end
  if IsTargetPlate(unit, plate) then
    return true
  end
  local tp = PlateFor("target")
  if tp and plate and tp == plate then
    return true
  end
  if unit == "target" then
    return true
  end
  if type(unit) == "string" and lastTargetPlateUnit and unit == lastTargetPlateUnit then
    return true
  end
  return false
end

--- True when aura data is publicly player/pet-owned (nil = unknown/secret).
AuraIsPlayerOwned = function(data)
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

--- Local player/pet harmful only — party DoTs must not land here (0.2.16 coexist).
AuraIsOurPersonalOnly = function(data)
  if AuraIsPlayerOwned(data) ~= true then
    return false
  end
  if AuraLooksForeign(data) then
    return false
  end
  return true
end

--- Public texture keys known to be player-owned (skip even if native keys are secret).
CollectPlayerOwnedKeys = function(unitToken, into)
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
    if AuraIsOurPersonalOnly(data) then
      local key = AuraDedupeKey(data, data.icon)
      if key then
        into[key] = true
      end
      if type(CanonicalGapKey) == "function" then
        local ck = CanonicalGapKey({ icon = data.icon, spellId = data.spellId, auraInstanceID = data.auraInstanceID })
        if ck then
          into[ck] = true
        end
      end
    end
  end
end

--- Instance → spellId → texture (never collapse unlike spells by icon file).
GapAuraKey = function(data, icon)
  if type(data) == "table" then
    local aid = data.auraInstanceID
    if aid ~= nil and not IsSecret(aid) then
      return "inst:" .. tostring(aid)
    end
    local sid = data.spellId
    if sid ~= nil and not IsSecret(sid) then
      return "spell:" .. tostring(sid)
    end
    if data.icon ~= nil and icon == nil then
      icon = data.icon
    end
  end
  local tk = PublicTexKey(icon)
  if tk then
    return "tex:" .. tostring(tk)
  end
  return nil
end

AuraDedupeKey = function(data, icon)
  return GapAuraKey(data, icon)
end

--- Source looks like another unit (not local player/pet) — include foreign like "Ours".
AuraLooksForeign = function(data)
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

--- Gap paint candidate for foreign/API pass — anything except our personal-only row.
AuraCountsAsForeignGaps = function(data)
  if not data then
    return true
  end
  return not AuraIsOurPersonalOnly(data)
end

--- v0.2.4 P0 — 0.1.15 foreign API pass: skip owned==true (personal stays native-only).
CollectForeignAuraGaps = function(unitToken, skipKeys, out, maxN, allowSecretUnknown, stats)
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

    if not AuraCountsAsForeignGaps(data) then
      -- personal-only — native or personal gap pass owns it
    else
      local icon = data.icon
      local owned = AuraIsPlayerOwned(data)
      local key = AuraDedupeKey(data, icon)
      local take = false
      if key and not skipKeys[key] then
        take = true
      elseif not key then
        if owned == false or AuraLooksForeign(data) or allowSecretUnknown then
          key = "sec:" .. tostring(i) .. ":" .. tostring(unitToken)
          if not skipKeys[key] then
            take = true
          end
        end
      end
      local ck = CanonicalGapKey({ icon = icon, spellId = data.spellId, auraInstanceID = data.auraInstanceID })
      if ck and skipKeys[ck] then
        -- dup
      elseif take and key and not skipKeys[key] then
        out[#out + 1] = {
          icon = icon,
          spellId = data.spellId,
          auraInstanceID = data.auraInstanceID,
          applications = data.applications,
          expirationTime = data.expirationTime,
          duration = data.duration,
        }
        skipKeys[key] = true
        if ck then
          skipKeys[ck] = true
        end
        if stats then
          stats.foreign = (stats.foreign or 0) + 1
        end
      end
    end
  end
end

--- Phase B — personal gaps when native DebuffList omits player DoTs (§5.2).
CollectPersonalAuraGaps = function(unitToken, paintKeys, out, maxN, stats)
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
    if not AuraIsOurPersonalOnly(data) then
      -- party / foreign / unknown — foreign+TF passes
    else
      local icon = data.icon
      local key = AuraDedupeKey(data, icon)
      if not key then
        key = "per:" .. tostring(i) .. ":" .. tostring(unitToken)
      end
      local ck = CanonicalGapKey({ icon = icon, spellId = data.spellId, auraInstanceID = data.auraInstanceID })
      if ck and paintKeys[ck] then
        -- already queued (TF harvest / texture dedupe)
      elseif key and not paintKeys[key] then
        out[#out + 1] = {
          icon = icon,
          spellId = data.spellId,
          auraInstanceID = data.auraInstanceID,
          applications = data.applications,
          expirationTime = data.expirationTime,
          duration = data.duration,
        }
        paintKeys[key] = true
        if ck then
          paintKeys[ck] = true
        end
        if stats then
          stats.personal = (stats.personal or 0) + 1
        end
      end
    end
  end
end

CollectTargetFramePersonalGaps = function(paintKeys, out, maxN, stats)
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
      local icon, skipped, gotIcon = ButtonAuraIcon(btn, "personal")
      if not skipped and gotIcon then
        local key = PublicTexKey(icon)
        if not key then
          key = "tfper:" .. bid
        end
        local ck = CanonicalGapKey({ icon = icon })
        if ck and paintKeys[ck] then
          -- dup
        elseif key and not paintKeys[key] then
          out[#out + 1] = icon
          paintKeys[key] = true
          if ck then
            paintKeys[ck] = true
          end
          if stats then
            stats.personal = (stats.personal or 0) + 1
          end
        end
      end
    end
  end
end

ApplyGapSticky = function(unit, missing, isTarget, unitToken)
  if not isTarget or not unit or #missing > 0 then
    return
  end
  local c = gapSticky[unit]
  if not c or type(c.icons) ~= "table" or #c.icons == 0 then
    return
  end
  local now = GetTime and GetTime() or 0
  if type(c.at) == "number" and (now - c.at) <= GAP_STICKY_SEC then
    unitToken = unitToken or "target"
    local live = {}
    for i = 1, #c.icons do
      if GapAuraLive(c.icons[i], unitToken) then
        live[#live + 1] = c.icons[i]
        missing[#missing + 1] = c.icons[i]
      end
    end
    if #live == 0 then
      gapSticky[unit] = nil
      return
    end
    c.icons = live
    DedupeGapIcons(missing, MaxIcons())
  end
end

local function CopyGapRow(row)
  if type(row) ~= "table" then
    return row
  end
  return {
    icon = row.icon,
    iconTex = row.iconTex,
    spellId = row.spellId,
    auraInstanceID = row.auraInstanceID,
    applications = row.applications,
    expirationTime = row.expirationTime,
    duration = row.duration,
    _key = row._key,
    fromTargetFrame = row.fromTargetFrame,
    fromUnitApi = row.fromUnitApi,
  }
end

EnrichGapAuraEntry = function(entry, unitToken)
  if type(entry) ~= "table" or not unitToken or not C_UnitAuras then
    return entry
  end
  if entry.auraInstanceID and C_UnitAuras.GetAuraDataByAuraInstanceID then
    local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unitToken, entry.auraInstanceID)
    if ok and type(data) == "table" then
      if data.expirationTime ~= nil then
        entry.expirationTime = data.expirationTime
      end
      if data.duration ~= nil then
        entry.duration = data.duration
      end
      if data.applications ~= nil then
        entry.applications = data.applications
      end
      if data.icon ~= nil then
        entry.icon = data.icon
      end
      return entry
    end
  end
  if entry.spellId and C_UnitAuras.GetAuraDataBySpellID then
    local ok, data = pcall(C_UnitAuras.GetAuraDataBySpellID, unitToken, entry.spellId)
    if ok and type(data) == "table" and data.expirationTime then
      entry.expirationTime = data.expirationTime
      entry.duration = data.duration or entry.duration
      entry.applications = data.applications or entry.applications
      return entry
    end
  end
  if C_UnitAuras.GetAuraDataByIndex then
    for idx = 1, 40 do
      local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unitToken, idx, "HARMFUL")
      if not ok or not data then
        break
      end
      local match = false
      if entry.auraInstanceID and data.auraInstanceID == entry.auraInstanceID then
        match = true
      elseif entry.spellId and data.spellId == entry.spellId then
        match = true
      end
      if match then
        entry.expirationTime = data.expirationTime
        entry.duration = data.duration
        entry.applications = data.applications
        entry.auraInstanceID = entry.auraInstanceID or data.auraInstanceID
        break
      end
    end
  end
  return entry
end

--- Drop expired or unit-absent rows (sticky must not ghost party DoTs).
GapAuraLive = function(entry, unitToken)
  if type(entry) ~= "table" then
    return false
  end
  EnrichGapAuraEntry(entry, unitToken)
  local now = GetTime and GetTime() or 0
  local exp = entry.expirationTime
  if type(exp) == "number" and not IsSecret(exp) and exp > 0 then
    if now >= exp then
      return false
    end
    return true
  end
  if entry.auraInstanceID and unitToken and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
    local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unitToken, entry.auraInstanceID)
    if ok and type(data) == "table" then
      local e2 = data.expirationTime
      if type(e2) == "number" and not IsSecret(e2) and e2 > 0 and now >= e2 then
        return false
      end
      return true
    end
    return false
  end
  if entry.spellId and unitToken and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
    local ok, data = pcall(C_UnitAuras.GetAuraDataBySpellID, unitToken, entry.spellId)
    if ok and type(data) == "table" then
      return true
    end
    return false
  end
  return true
end

PruneInactiveGapRows = function(rows, unitToken, maxN)
  if type(rows) ~= "table" or not unitToken then
    return 0
  end
  maxN = maxN or MaxIcons()
  local out = {}
  for i = 1, #rows do
    if #out >= maxN then
      break
    end
    if GapAuraLive(rows[i], unitToken) then
      out[#out + 1] = rows[i]
    end
  end
  for i = #out + 1, #rows do
    rows[i] = nil
  end
  for i = 1, #out do
    rows[i] = out[i]
  end
  return #out
end

RememberGapSticky = function(unit, icons, unitToken)
  if not unit or type(icons) ~= "table" or #icons == 0 then
    return
  end
  unitToken = unitToken or (unit == "target" and "target" or unit)
  local copy = {}
  for i = 1, #icons do
    local row = CopyGapRow(icons[i])
    if GapAuraLive(row, unitToken) then
      copy[#copy + 1] = row
    end
  end
  if #copy == 0 then
    gapSticky[unit] = nil
    return
  end
  DedupeGapIcons(copy, MaxIcons())
  gapSticky[unit] = { icons = copy, at = GetTime and GetTime() or 0 }
end

RefreshHeldGapFallback = function(unit, plate, fb, icons, auraUnit)
  if not fb or type(icons) ~= "table" or #icons == 0 then
    return 0, 0
  end
  auraUnit = auraUnit or "target"
  local live = {}
  for i = 1, #icons do
    if GapAuraLive(icons[i], auraUnit) then
      live[#live + 1] = icons[i]
    end
  end
  if #live == 0 then
    return 0, 0
  end
  icons = live
  local maxN = MaxIcons()
  local sz, pad = MergeRowIconSize(plate, fb)
  fb._pbPlate = plate
  local painted = math.min(#live, maxN, tonumber(fb._painted) or #live)
  local cdN = 0
  for i = 1, painted do
    local row = live[i]
    EnrichGapAuraEntry(row, auraUnit)
    local slot = fb.icons[i]
    if slot and slot.SetSize then
      if slot._pbSz ~= sz then
        pcall(InitAuraButton, slot, sz)
        slot._pbSz = sz
      end
      pcall(function()
        slot:SetSize(sz, sz)
        slot:SetPoint("LEFT", fb, "LEFT", (i - 1) * (sz + pad), 0)
      end)
      local _, cdSet = ApplyGapAuraVisual(slot, row, auraUnit)
      if cdSet then
        cdN = cdN + 1
      end
      pcall(slot.Show, slot)
    end
  end
  for i = painted + 1, #(fb.icons or {}) do
    local slot = fb.icons[i]
    if slot then
      pcall(slot.Hide, slot)
    end
  end
  pcall(function()
    fb:SetSize(math.max(1, painted * (sz + pad)), sz)
    fb:Show()
  end)
  fb._painted = painted
  pcall(LayoutMergeBesideNative, unit, plate, fb, painted)
  lastPaintDebug.gapSz = sz
  lastPaintDebug.lockSz = fb._pbLockedSz
  lastPaintDebug.cdN = cdN
  lastPaintDebug.painted = painted
  return painted, cdN
end

CollectTargetHarmfulFromApi = function(rows, maxN)
  if type(rows) ~= "table" or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
    return
  end
  maxN = maxN or MaxIcons()
  for idx = 1, 40 do
    if #rows >= maxN then
      return
    end
    local data
    local ok = pcall(function()
      data = C_UnitAuras.GetAuraDataByIndex("target", idx, "HARMFUL")
    end)
    if not ok or not data then
      break
    end
    if not AuraIconPresent(data.icon) then
      -- still queue secret/live rows
    end
    local row = {
      icon = data.icon,
      spellId = data.spellId,
      auraInstanceID = data.auraInstanceID,
      applications = data.applications,
      expirationTime = data.expirationTime,
      duration = data.duration,
      fromUnitApi = true,
    }
    row._key = CanonicalGapKey(row) or TfRowKey(row) or ("api:" .. tostring(idx))
    local rowKey = CanonicalGapKey(row)
    local dup = false
    for r = 1, #rows do
      if rowKey and CanonicalGapKey(rows[r]) == rowKey then
        dup = true
        break
      end
    end
    if not dup then
      rows[#rows + 1] = row
    end
  end
end

--- Pull icon texture from a TF aura button (secret FileIDs OK for SetTexture).
--- mode: nil/"foreign" skips personal; "personal" skips non-personal.
--- Returns icon, skippedPersonal, gotIcon — never compare icon to nil (secret throws).
ButtonAuraIcon = function(btn, mode)
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
        local owned = AuraIsPlayerOwned(data)
        if mode == "personal" then
          if owned ~= true then
            skippedPersonal = true
            return
          end
        elseif owned == true then
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

--- TF supplement: ownership-agnostic icon read; skipKeys dedupes personal already painted.
ButtonAuraIconAny = function(btn)
  if not btn then
    return nil, false
  end
  local icon
  local got = false
  pcall(function()
    if btn.GetAuraInstance then
      local _, data = btn:GetAuraInstance()
      if type(data) == "table" and data.icon then
        icon = data.icon
        got = true
      end
    end
  end)
  if got then
    return icon, true
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
      return file, true
    end
    return tex, true
  end
  return nil, false
end

--- Retinue-style TF harvest (read-only). Forever 16001 paths 0.2.6 missed.
AuraIconPresent = function(icon)
  local present = false
  pcall(function()
    if IsSecret(icon) then
      present = true
      return
    end
    if icon ~= nil then
      present = true
    end
  end)
  return present
end

FrameIsShownSafe = function(frame)
  if not frame or not frame.IsShown then
    return true
  end
  local ok, shown = pcall(frame.IsShown, frame)
  if not ok or IsSecret(shown) then
    return true
  end
  return shown and true or false
end

IsCastOrSpellBarFrame = function(frame)
  if not frame then
    return false
  end
  local p = frame
  for _ = 1, 8 do
    if not p then
      return false
    end
    local n
    pcall(function()
      n = p.GetName and p:GetName()
    end)
    if type(n) == "string" then
      local l = n:lower()
      if l:find("castingbar", 1, true) or l:find("spellbar", 1, true) or l:find("castbar", 1, true) then
        return true
      end
    end
    if p == TargetFrameSpellBar or p == CastingBarFrame then
      return true
    end
    pcall(function()
      p = p.GetParent and p:GetParent()
    end)
    if not p or p == UIParent then
      return false
    end
  end
  return false
end

IsLikelyBuffFrame = function(frame)
  if not frame or IsCastOrSpellBarFrame(frame) then
    return true
  end
  local buffish = false
  pcall(function()
    local flag = frame.isBuff
    if flag ~= nil and not IsSecret(flag) and flag then
      buffish = true
    end
  end)
  if buffish then
    return true
  end
  pcall(function()
    local flag = frame.isHelpful
    if flag ~= nil and not IsSecret(flag) and flag then
      buffish = true
    end
  end)
  return buffish
end

TextureHasArt = function(iconTex)
  if not iconTex then
    return false
  end
  local ok = false
  pcall(function()
    if iconTex.GetTexture then
      local path = iconTex:GetTexture()
      if IsSecret(path) or (type(path) == "number" and path > 0) or (type(path) == "string" and path ~= "") then
        ok = true
      end
    end
  end)
  return ok
end

IsUsableSpellIcon = function(path, allowSecret)
  local ok = false
  pcall(function()
    if IsSecret(path) then
      ok = allowSecret and true or false
      return
    end
    if type(path) == "number" then
      ok = path > 0
    elseif type(path) == "string" and path ~= "" then
      ok = true
    end
  end)
  return ok
end

TfRowKey = function(row)
  if type(row) ~= "table" then
    return nil
  end
  if type(row._key) == "string" then
    return row._key
  end
  local sid = row.spellId
  if sid ~= nil and not IsSecret(sid) then
    return "s:" .. tostring(sid)
  end
  local aid = row.auraInstanceID
  if aid ~= nil and not IsSecret(aid) then
    return "a:" .. tostring(aid)
  end
  local k = PublicTexKey(row.icon)
  if k then
    return k
  end
  return nil
end

--- One harmful aura = one plate icon — instance/spell before texture.
CanonicalGapKey = function(row)
  if type(row) == "table" then
    local k = GapAuraKey(row, row.icon)
    if k then
      return k
    end
  end
  return GapAuraKey(nil, row)
end

--- TF harmful minus native plate + gap queue — recovers drops when own DoT joins native.
EnsureTargetHarmfulParity = function(plate, missing, skipKeys, maxN, stats)
  if not plate or not missing or not skipKeys then
    return
  end
  local nativeKeys = NativeKeySet(plate)
  local tfRows = CollectTargetHarmfulRows(maxN)
  for i = 1, #tfRows do
    if #missing >= maxN then
      return
    end
    local row = tfRows[i]
    local ck = CanonicalGapKey(row)
    if not ck then
      ck = TfRowKey(row)
    end
    if ck and nativeKeys[ck] then
      -- Blizzard already shows on plate DebuffList
    elseif ck and skipKeys[ck] then
      -- already queued
    else
      local inMissing = false
      for j = 1, #missing do
        if CanonicalGapKey(missing[j]) == ck then
          inMissing = true
          break
        end
      end
      if not inMissing then
        local isPersonal = false
        if row.spellId and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
          pcall(function()
            local data = C_UnitAuras.GetAuraDataBySpellID("target", row.spellId)
            if data and AuraIsOurPersonalOnly(data) then
              isPersonal = true
            end
          end)
        end
        AppendGapRow(skipKeys, missing, maxN, stats, row, not isPersonal)
      end
    end
  end
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for idx = 1, 40 do
      if #missing >= maxN then
        return
      end
      local data
      local ok = pcall(function()
        data = C_UnitAuras.GetAuraDataByIndex("target", idx, "HARMFUL")
      end)
      if not ok or not data then
        break
      end
      local ck = GapAuraKey(data, data.icon)
      if ck and nativeKeys[ck] then
        -- native
      elseif ck and skipKeys[ck] then
        -- queued
      else
        local inMissing = false
        for j = 1, #missing do
          if CanonicalGapKey(missing[j]) == ck then
            inMissing = true
            break
          end
        end
        if not inMissing then
          local row = {
            icon = data.icon,
            spellId = data.spellId,
            auraInstanceID = data.auraInstanceID,
            applications = data.applications,
            expirationTime = data.expirationTime,
            duration = data.duration,
          }
          local personal = AuraIsOurPersonalOnly(data)
          if personal then
            AppendGapRow(skipKeys, missing, maxN, stats, row, false)
          elseif AuraCountsAsForeignGaps(data) then
            AppendGapRow(skipKeys, missing, maxN, stats, row, true)
          end
        end
      end
    end
  end
end

--- Nameplate unit token (party/friend/player) — full harmful row from C_UnitAuras.
EnsureUnitHarmfulParity = function(unitToken, plate, missing, skipKeys, maxN, stats)
  if not unitToken or not plate or not missing or not skipKeys then
    return
  end
  if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
    return
  end
  local nativeKeys = NativeKeySet(plate)
  for idx = 1, 40 do
    if #missing >= maxN then
      return
    end
    local data
    local ok = pcall(function()
      data = C_UnitAuras.GetAuraDataByIndex(unitToken, idx, "HARMFUL")
    end)
    if not ok or not data then
      break
    end
    local ck = GapAuraKey(data, data.icon)
    if ck and nativeKeys[ck] then
      -- native DebuffList
    elseif ck and skipKeys[ck] then
      -- queued
    else
      local inMissing = false
      for j = 1, #missing do
        if CanonicalGapKey(missing[j]) == ck then
          inMissing = true
          break
        end
      end
      if not inMissing then
        local row = {
          icon = data.icon,
          spellId = data.spellId,
          auraInstanceID = data.auraInstanceID,
          applications = data.applications,
          expirationTime = data.expirationTime,
          duration = data.duration,
          fromUnitApi = true,
        }
        if AuraIsOurPersonalOnly(data) then
          AppendGapRow(skipKeys, missing, maxN, stats, row, false)
        else
          AppendGapRow(skipKeys, missing, maxN, stats, row, true)
        end
      end
    end
  end
end

DedupeGapIcons = function(missing, maxN)
  if type(missing) ~= "table" then
    return missing
  end
  maxN = maxN or MaxIcons()
  local seen = {}
  local out = {}
  for i = 1, #missing do
    if #out >= maxN then
      break
    end
    local entry = missing[i]
    local key = CanonicalGapKey(entry)
    if not key then
      key = "tex:" .. tostring(i)
    end
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = entry
    end
  end
  for i = #out + 1, #missing do
    missing[i] = nil
  end
  for i = 1, #out do
    missing[i] = out[i]
  end
  return missing
end

DeduplicateHarmfulRows = function(rows, maxN)
  if type(rows) ~= "table" then
    return rows
  end
  maxN = maxN or MaxIcons()
  local seen = {}
  local out = {}
  for i = 1, #rows do
    if #out >= maxN then
      break
    end
    local row = rows[i]
    local key = CanonicalGapKey(row)
    if not key then
      key = "row:" .. tostring(i)
    end
    if not seen[key] then
      seen[key] = true
      row._key = key
      out[#out + 1] = row
    end
  end
  return out
end

PushTfAuraFrame = function(frame, rows, maxN)
  if not frame or #rows >= maxN or IsLikelyBuffFrame(frame) then
    return
  end
  pcall(function()
    local icon, sid, aid
    local tex = frame.Icon or frame.icon
    local expTime
    local dur
    local apps
    pcall(function()
      if frame.GetAuraInstance then
        local _, data = frame:GetAuraInstance()
        if type(data) == "table" then
          icon = data.icon
          sid = data.spellId
          aid = data.auraInstanceID
          expTime = data.expirationTime
          dur = data.duration
          apps = data.applications
        end
      end
    end)
    if not IsUsableSpellIcon(icon, true) and tex and tex.GetTexture then
      pcall(function()
        icon = tex:GetTexture()
      end)
    end
    local liveBtn = false
    pcall(function()
      if IsSecret(aid) or IsSecret(sid) or aid ~= nil or sid ~= nil then
        liveBtn = true
      end
    end)
    if not IsUsableSpellIcon(icon, true) and not liveBtn and not TextureHasArt(tex) then
      return
    end
    local rowTmp = { spellId = sid, auraInstanceID = aid, icon = icon, iconTex = tex }
    local key = CanonicalGapKey(rowTmp)
    if not key then
      key = "tf:" .. tostring(frame)
    end
    for i = 1, #rows do
      if rows[i]._key == key or CanonicalGapKey(rows[i]) == key then
        return
      end
    end
    rows[#rows + 1] = {
      icon = icon,
      iconTex = tex,
      spellId = sid,
      auraInstanceID = aid,
      applications = apps,
      expirationTime = expTime,
      duration = dur,
      _key = key,
      fromTargetFrame = true,
    }
  end)
end

HarvestTfAuraPool = function(pools, rows, maxN)
  if type(pools) ~= "table" then
    return
  end
  local function take(frame)
    if frame and not IsLikelyBuffFrame(frame) then
      PushTfAuraFrame(frame, rows, maxN)
    end
  end
  pcall(function()
    if pools.EnumerateActiveAuraButtons then
      for btn in pools:EnumerateActiveAuraButtons() do
        take(btn)
      end
    end
  end)
  pcall(function()
    if pools.EnumerateActive then
      for f in pools:EnumerateActive() do
        take(f)
      end
    end
  end)
  for _, pool in pairs(pools) do
    if type(pool) == "table" and #rows < maxN then
      pcall(function()
        if pool.EnumerateActiveAuraButtons then
          for btn in pool.EnumerateActiveAuraButtons() do
            take(btn)
          end
        elseif pool.EnumerateActive then
          for f in pool:EnumerateActive() do
            take(f)
          end
        end
      end)
    end
  end
end

CollectTfActiveDebuffs = function(rows, maxN)
  if not TargetFrame or type(TargetFrame.activeDebuffs) ~= "table" then
    return
  end
  pcall(function()
    for key, aura in pairs(TargetFrame.activeDebuffs) do
      if #rows >= maxN then
        return
      end
      if type(aura) == "table" and (aura.Icon or aura.icon or aura.GetAuraInstance) then
        PushTfAuraFrame(aura, rows, maxN)
      elseif type(aura) == "number" and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "target", aura)
        if ok and type(data) == "table" and AuraIconPresent(data.icon) then
          local row = {
            icon = data.icon,
            spellId = data.spellId,
            auraInstanceID = data.auraInstanceID or key,
            fromTargetFrame = true,
          }
          row._key = TfRowKey(row) or ("tfaid:" .. tostring(aura))
          rows[#rows + 1] = row
        end
      end
    end
  end)
end

CollectTfAuraSlots = function(rows, maxN)
  if not C_UnitAuras or not C_UnitAuras.GetAuraSlots then
    return
  end
  local pack = { pcall(C_UnitAuras.GetAuraSlots, "target", "HARMFUL") }
  if not pack[1] then
    return
  end
  for i = 3, #pack do
    if #rows >= maxN then
      break
    end
    local slot = pack[i]
    local data
    if C_UnitAuras.GetAuraDataBySlot then
      local ok, d = pcall(C_UnitAuras.GetAuraDataBySlot, "target", slot)
      if ok then
        data = d
      end
    end
    if type(data) == "table" and AuraIconPresent(data.icon) then
      local row = {
        icon = data.icon,
        spellId = data.spellId,
        auraInstanceID = data.auraInstanceID,
        fromUnitApi = true,
      }
      row._key = TfRowKey(row) or ("slot:" .. tostring(i))
      local dup = false
      for r = 1, #rows do
        if rows[r]._key == row._key then
          dup = true
          break
        end
      end
      if not dup then
        rows[#rows + 1] = row
      end
    end
  end
end

ScrapeTargetFrameBrute = function(rows, maxN)
  if not TargetFrame then
    return
  end
  local function scan(frame, depth)
    if not frame or depth > 14 or #rows >= maxN or IsCastOrSpellBarFrame(frame) then
      return
    end
    pcall(function()
      if not FrameIsShownSafe(frame) then
        return
      end
      local iconTex = frame.Icon or frame.icon
      if iconTex then
        local w
        pcall(function()
          w = frame:GetWidth()
        end)
        if type(w) == "number" and not IsSecret(w) and (w < 12 or w > 48) then
          return
        end
        PushTfAuraFrame(frame, rows, maxN)
      end
    end)
    local ok, kids = pcall(function()
      return { frame:GetChildren() }
    end)
    if ok and type(kids) == "table" then
      for i = 1, #kids do
        scan(kids[i], depth + 1)
      end
    end
  end
  local container = GetTargetAuraContainer()
  if container then
    scan(container, 0)
  end
  scan(TargetFrame, 0)
  pcall(function()
    local content = TargetFrame.TargetFrameContent
    if content then
      scan(content, 0)
    end
  end)
end

--- API mirror when TF scrape returns empty but target has HARMFUL (native plate empty).
CollectUnitHarmfulMirror = function(unitToken, skipKeys, out, maxN, stats)
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
    local row = {
      icon = data.icon,
      spellId = data.spellId,
      auraInstanceID = data.auraInstanceID,
      applications = data.applications,
      expirationTime = data.expirationTime,
      duration = data.duration,
      fromUnitApi = true,
    }
    AppendGapRow(skipKeys, out, maxN, stats, row, true)
  end
end

CollectTargetHarmfulRows = function(maxN)
  maxN = maxN or MaxIcons()
  local rows = {}
  local container = GetTargetAuraContainer()
  if container then
    pcall(function()
      local group = container.debuffAuraGroup
      local frames = group and group.GetFramesByIndex and group:GetFramesByIndex()
      if type(frames) == "table" then
        for i = 1, #frames do
          PushTfAuraFrame(frames[i], rows, maxN)
        end
      end
    end)
    pcall(function()
      local group = container.debuffAuraGroup
      local auras = group and group.GetAuras and group:GetAuras()
      if auras and auras.Iterate then
        auras:Iterate(function(_id, data)
          if #rows >= maxN then
            return true
          end
          if type(data) == "table" and AuraIconPresent(data.icon) then
            local row = {
              icon = data.icon,
              spellId = data.spellId,
              auraInstanceID = data.auraInstanceID,
              applications = data.applications,
              expirationTime = data.expirationTime,
              duration = data.duration,
              fromTargetFrame = true,
            }
            row._key = TfRowKey(row) or ("tfit:" .. tostring(#rows + 1))
            rows[#rows + 1] = row
          end
          return false
        end)
      end
    end)
    pcall(HarvestTfAuraPool, container.auraPools, rows, maxN)
  end
  for i = 1, 16 do
    local f = _G["TargetFrameDebuff" .. i]
    if f then
      PushTfAuraFrame(f, rows, maxN)
    end
  end
  if TargetFrame and TargetFrame.auraPools then
    pcall(HarvestTfAuraPool, TargetFrame.auraPools, rows, maxN)
  end
  CollectTfActiveDebuffs(rows, maxN)
  CollectTfAuraSlots(rows, maxN)
  if #rows == 0 then
    ScrapeTargetFrameBrute(rows, maxN)
  elseif #rows < maxN then
    ScrapeTargetFrameBrute(rows, maxN)
  end
  if #rows < maxN then
    CollectTargetHarmfulFromApi(rows, maxN)
  end
  return DeduplicateHarmfulRows(rows, maxN)
end

AppendGapRow = function(skipKeys, out, maxN, stats, row, countForeign)
  if #out >= maxN or type(row) ~= "table" then
    return
  end
  local key = CanonicalGapKey(row)
  if not key then
    key = TfRowKey(row) or ("gap:" .. tostring(#out + 1))
  end
  if skipKeys[key] then
    return
  end
  local icon = row.icon
  if not AuraIconPresent(icon) and row.iconTex then
    pcall(function()
      icon = row.iconTex:GetTexture()
    end)
  end
  if AuraIconPresent(icon) then
    row.icon = icon
    out[#out + 1] = row
  elseif row.iconTex then
    out[#out + 1] = { iconTex = row.iconTex, icon = icon, spellId = row.spellId, auraInstanceID = row.auraInstanceID }
  else
    return
  end
  skipKeys[key] = true
  if stats and countForeign then
    stats.foreign = (stats.foreign or 0) + 1
  end
end

--- TF mirror minus plate skipKeys — party DoTs (Retinue CollectFromTargetFrame parity).
CollectTargetFrameMissing = function(skipKeys, out, maxN, stats)
  local rows = CollectTargetHarmfulRows(maxN)
  for i = 1, #rows do
    if #out >= maxN then
      return
    end
    AppendGapRow(skipKeys, out, maxN, stats, rows[i], true)
  end
end

CollectAuraSlotsGaps = function(unitToken, skipKeys, out, maxN, stats)
  if unitToken ~= "target" or not C_UnitAuras or not C_UnitAuras.GetAuraSlots then
    return
  end
  local pack = { pcall(C_UnitAuras.GetAuraSlots, unitToken, "HARMFUL") }
  if not pack[1] then
    return
  end
  for i = 3, #pack do
    if #out >= maxN then
      break
    end
    local slot = pack[i]
    local data
    if C_UnitAuras.GetAuraDataBySlot then
      local ok, d = pcall(C_UnitAuras.GetAuraDataBySlot, unitToken, slot)
      if ok then
        data = d
      end
    end
    if type(data) == "table" and AuraCountsAsForeignGaps(data) then
      local row = {
        icon = data.icon,
        spellId = data.spellId,
        auraInstanceID = data.auraInstanceID,
        applications = data.applications,
        expirationTime = data.expirationTime,
        duration = data.duration,
      }
      AppendGapRow(skipKeys, out, maxN, stats, row, true)
    end
  end
end

SetIconTexture = function(icon, t)
  local okSet = false
  pcall(function()
    if type(t) == "table" and t.iconTex and t.iconTex.GetTexture then
      icon:SetTexture(t.iconTex:GetTexture())
      okSet = true
      return
    end
    if type(t) == "table" and t.icon ~= nil then
      t = t.icon
    end
    if type(t) == "table" or type(t) == "userdata" then
      if t.GetTexture then
        icon:SetTexture(t:GetTexture())
        okSet = true
      end
    elseif t ~= nil then
      icon:SetTexture(t)
      okSet = true
    end
  end)
  return okSet
end

ApplyGapAuraVisual = function(button, entry, unitToken)
  if not button then
    return false, false
  end
  local tex = button.icon or button.Icon
  if not tex then
    pcall(function()
      local psz = select(1, MergeRowIconSize(button._pbPlate))
      InitAuraButton(button, button:GetWidth() or psz or IconSize())
    end)
    tex = button.icon or button.Icon
  end
  if not tex then
    return false, false
  end
  local ok = SetIconTexture(tex, entry)
  if type(entry) == "table" then
    EnrichGapAuraEntry(entry, unitToken)
    local exp = entry.expirationTime
    local dur = entry.duration
    local apps = entry.applications or entry.stacks
    pcall(function()
      if button.count and apps ~= nil and not IsSecret(apps) and type(apps) == "number" then
        if apps > 1 then
          button.count:SetText(tostring(apps))
          button.count:Show()
        else
          button.count:SetText("")
        end
      end
    end)
    pcall(function()
      if button.SetAuraInstance and entry.auraInstanceID then
        if button.SetUnit and unitToken then
          button:SetUnit(unitToken)
        end
        button:SetAuraInstance(entry.auraInstanceID)
      end
    end)
    local cdSet = false
    pcall(function()
      local cd = button.cooldown
      if cd and type(exp) == "number" and type(dur) == "number" and dur > 0 and not IsSecret(exp) and not IsSecret(dur) then
        local start = exp - dur
        if start and start >= 0 then
          cd:SetCooldown(start, dur)
          cd:Show()
          cdSet = true
        end
      end
    end)
    entry._pbCd = cdSet
  end
  local cdSet = type(entry) == "table" and entry._pbCd == true
  return ok, cdSet
end

TfSupplementSkipKeys = function(paintKeys, missing)
  local skip = CopyKeySet(paintKeys)
  if type(missing) == "table" then
    for i = 1, #missing do
      local k = CanonicalGapKey(missing[i]) or TfRowKey(missing[i])
      if k then
        skip[k] = true
      end
    end
  end
  return skip
end

SilentTraceEnabled = function()
  local p = Profile()
  return p.silentTrace ~= false and p.paintTraceOn ~= false
end

BuildPaintTraceLine = function(why, unit, plate)
  if not SilentTraceEnabled() then
    return nil
  end
  unit = OverlayUnitKey(unit, plate) or tostring(unit or "?")
  local p = Profile()
  local nativeN = plate and CountPlateHarmfulShown(plate) or 0
  local nativeList = plate and NativeDebuffList(plate)
  local nativeKids = nativeList and RawChildCount(nativeList) or 0
  local poolKids = 0
  if plate then
    local buttons = {}
    CollectPlateDebuffButtons(plate, buttons, MaxIcons())
    poolKids = #buttons
  end
  local tf = HasTarget() and #CollectTargetHarmfulRows(MaxIcons()) or 0
  if tf == 0 and HasTarget() then
    tf = CountTargetFrameAuras()
  end
  local fb = 0
  if unit and fallbacks[unit] then
    fb = tonumber(fallbacks[unit]._painted) or 0
  end
  local lpd = lastPaintDebug or {}
  local tgtSrc = ShouldUseTargetAuraSource(unit, plate) and 1 or 0
  local parentKind = lpd.parent or (nativeN > 0 and "nativeRow" or "healthBar")
  local nativeVis = nativeList and (SafeShown(nativeList) and 1 or 0) or 0
  local bar = plate and HealthBar(plate)
  local barVis = bar and (SafeShown(bar) and 1 or 0) or 0
  return string.format(
    "PAINT ver=%s why=%s unit=%s tgt=%s merge=%s native=%s pool=%s kids=%s tf=%s harv=%s miss=%s painted=%s fb=%s pers=%s for=%s tgtSrc=%s parent=%s natVis=%s barVis=%s active=%s safe=%s acFail=%s gapSz=%s lockSz=%s cdN=%s",
    tostring(ns.Config.VERSION),
    tostring(why or "?"),
    tostring(unit),
    HasTarget() and "1" or "0",
    p.mergeMissing == true and "1" or "0",
    tostring(nativeN),
    tostring(poolKids),
    tostring(nativeKids),
    tostring(tf),
    tostring(lpd.harv or "?"),
    tostring(lpd.miss or "?"),
    tostring(lpd.painted or fb),
    tostring(fb),
    tostring(lpd.personal or (fallbacks[unit] and fallbacks[unit]._gapPersonal) or "?"),
    tostring(lpd.foreign or (fallbacks[unit] and fallbacks[unit]._gapForeign) or "?"),
    tostring(tgtSrc),
    tostring(parentKind),
    tostring(nativeVis),
    tostring(barVis),
    ModuleActive() and "1" or "0",
    p.safeMode and "1" or "0",
    acCreateFailed and "1" or "0",
    tostring(lpd.gapSz or "?"),
    tostring(lpd.lockSz or "?"),
    tostring(lpd.cdN or "?")
  )
end

SilentTracePaint = function(why, unit, plate)
  if not SilentTraceEnabled() then
    return
  end
  local line = BuildPaintTraceLine(why, unit, plate)
  if line and ns.SessionLog and ns.SessionLog.RecordPaint then
    pcall(ns.SessionLog.RecordPaint, line)
  end
end

SilentTraceSweep = function(why)
  if not SilentTraceEnabled() then
    return
  end
  local now = GetTime and GetTime() or 0
  if (now - lastSilentSweepAt) < SILENT_SWEEP_SEC then
    return
  end
  lastSilentSweepAt = now
  local list = EnumerateLivePlates()
  local swept = {}
  if HasTarget() then
    local tp = PlateFor("target")
    local tu = NameplateUnitFor("target") or (tp and UnitTokenFromPlate(tp))
    tu = OverlayUnitKey(tu, tp)
    if tp then
      SilentTracePaint(why or "sweep_tgt", tu, tp)
      swept[tu or tostring(tp)] = true
    end
  end
  for i = 1, #list do
    if i > 8 then
      break
    end
    local entry = list[i]
    local u = OverlayUnitKey(entry.unit, entry.plate)
    if u and not swept[u] and entry.plate then
      SilentTracePaint((why or "sweep") .. "_np", u, entry.plate)
      swept[u] = true
    end
  end
end

--- Paint personal + foreign gaps beside native — 0.1.15 sources + 0.2 layout (§5 P0/P1).
PaintMergeMissing = function(unit, plate)
  if not plate then
    ClearFallback(unit)
    return 0
  end
  local parent = FallbackParent(plate)
  if not parent then
    ClearFallback(unit)
    return 0
  end
  local nativeList = NativeDebuffAnchorList(plate) or parent

  EnsureNativeVisible(plate)
  RestoreNameShift(unit, plate)

  local friendPlate = IsPlayerOrFriendPlate(unit, plate)
  if friendPlate and not MergeFriendPlatesEnabled() then
    ClearFallback(unit)
    return 0
  end

  local paintKeys = NativeKeySet(plate)
  local maxN = MaxIcons()
  local missing = {}
  local stats = { personal = 0, foreign = 0 }
  local isTarget = IsTargetPlate(unit, plate)
  local useTargetSrc = ShouldUseTargetAuraSource(unit, plate)
  local nativeN = CountPlateHarmfulShown(plate)
  local allowSecret = useTargetSrc or nativeN == 0

  local queueSkip = CopyKeySet(paintKeys)

  -- TF-first: mirror harmful row when target plate (party DoTs + personal when native=0).
  local harvN = 0
  if useTargetSrc then
    local harv = CollectTargetHarmfulRows(maxN)
    harvN = #harv
    lastPaintDebug.harv = harvN
    lastPaintDebug.tgtSrc = 1
    for i = 1, #harv do
      AppendGapRow(queueSkip, missing, maxN, stats, harv[i], false)
    end
  else
    lastPaintDebug.tgtSrc = 0
    lastPaintDebug.harv = 0
  end

  if useTargetSrc then
    CollectPersonalAuraGaps("target", queueSkip, missing, maxN, stats)
    if type(unit) == "string" and unit ~= "target" then
      CollectPersonalAuraGaps(unit, queueSkip, missing, maxN, stats)
    end
    CollectTargetFramePersonalGaps(queueSkip, missing, maxN, stats)

    local foreignSkip = CopyKeySet(queueSkip)
    CollectForeignAuraGaps("target", foreignSkip, missing, maxN, allowSecret, stats)
    CollectAuraSlotsGaps("target", foreignSkip, missing, maxN, stats)
    if type(unit) == "string" and unit ~= "target" then
      CollectForeignAuraGaps(unit, foreignSkip, missing, maxN, allowSecret, stats)
    end
    -- TF supplement: queueSkip + CanonicalGapKey dedupe; catches party harm TF/API missed in harv.
    CollectTargetFrameMissing(queueSkip, missing, maxN, stats)
    CollectUnitHarmfulMirror("target", queueSkip, missing, maxN, stats)
    if type(unit) == "string" and unit ~= "target" then
      CollectUnitHarmfulMirror(unit, queueSkip, missing, maxN, stats)
    end
    EnsureTargetHarmfulParity(plate, missing, queueSkip, maxN, stats)
    DedupeGapIcons(missing, maxN)
    local auraTok = "target"
    PruneInactiveGapRows(missing, auraTok, maxN)
  else
    if type(unit) == "string" then
      CollectPersonalAuraGaps(unit, paintKeys, missing, maxN, stats)
      local foreignSkip = CopyKeySet(paintKeys)
      CollectPlayerOwnedKeys(unit, foreignSkip)
      CollectForeignAuraGaps(unit, foreignSkip, missing, maxN, allowSecret, stats)
      CollectUnitHarmfulMirror(unit, foreignSkip, missing, maxN, stats)
      EnsureUnitHarmfulParity(unit, plate, missing, foreignSkip, maxN, stats)
      DedupeGapIcons(missing, maxN)
      PruneInactiveGapRows(missing, unit, maxN)
    end
  end

  ApplyGapSticky(unit, missing, useTargetSrc, useTargetSrc and "target" or unit)
  if useTargetSrc then
    PruneInactiveGapRows(missing, "target", maxN)
  elseif type(unit) == "string" then
    PruneInactiveGapRows(missing, unit, maxN)
  end

  lastPaintDebug.miss = #missing
  lastPaintDebug.unit = tostring(unit)
  lastPaintDebug.nativeN = nativeN
  lastPaintDebug.friendPlate = friendPlate and 1 or 0

  if #missing == 0 then
    local held = fallbacks[unit]
    local sticky = gapSticky[unit]
    local now = GetTime and GetTime() or 0
    local heldN = held and tonumber(held._painted) or 0
    if heldN > 0 and sticky and type(sticky.icons) == "table" and #sticky.icons > 0 then
      if type(sticky.at) == "number" and (now - sticky.at) <= GAP_STICKY_SEC then
        local auraUnit = useTargetSrc and "target" or unit
        local heldCd = 0
        pcall(function()
          local n, cdn = RefreshHeldGapFallback(unit, plate, held, sticky.icons, auraUnit)
          heldN = n or 0
          heldCd = cdn or 0
        end)
        if heldN <= 0 then
          gapSticky[unit] = nil
          lastPaintDebug.painted = 0
          ClearFallback(unit, false)
          SilentTracePaint("paint_hold_expired", unit, plate)
          return 0
        end
        lastPaintDebug.painted = heldN
        lastPaintDebug.miss = 0
        lastPaintDebug.cdN = heldCd
        SilentTracePaint("paint_hold", unit, plate)
        return heldN
      end
    end
    lastPaintDebug.painted = 0
    ClearFallback(unit, false)
    return 0
  end

  local fb = EnsureFallback(unit, plate)
  if not fb then
    lastPaintDebug.painted = 0
    lastPaintDebug.parent = "nil"
    return 0
  end
  lastPaintDebug.parent = nativeN > 0 and "nativeRow" or "healthBar"
  local sz, pad = MergeRowIconSize(plate, fb)
  fb._pbPlate = plate
  local auraUnit = useTargetSrc and "target" or unit
  local painted = 0
  local cdN = 0
  for i = 1, #missing do
    if painted >= maxN then
      break
    end
    painted = painted + 1
    local slot = fb.icons[painted]
    if not slot or not slot.SetSize then
      slot = CreateGapAuraButton(fb, sz)
      slot._pbPlate = plate
      fb.icons[painted] = slot
    end
    local okLay = pcall(function()
      if slot._pbSz ~= sz then
        pcall(InitAuraButton, slot, sz)
        slot._pbSz = sz
      end
      slot:ClearAllPoints()
      slot:SetSize(sz, sz)
      slot:SetPoint("LEFT", fb, "LEFT", (painted - 1) * (sz + pad), 0)
    end)
    if not okLay then
      painted = painted - 1
    else
      EnrichGapAuraEntry(missing[i], auraUnit)
      local okVis, cdSet = ApplyGapAuraVisual(slot, missing[i], auraUnit)
      if cdSet then
        cdN = cdN + 1
      end
      if okVis then
        pcall(slot.Show, slot)
      else
        pcall(slot.Hide, slot)
        painted = painted - 1
      end
    end
  end
  for i = painted + 1, #fb.icons do
    local slot = fb.icons[i]
    if slot then
      pcall(slot.Hide, slot)
    end
  end

  if painted == 0 then
    pcall(fb.Hide, fb)
    fb._painted = 0
    return 0
  end

  pcall(function()
    fb:SetSize(math.max(1, painted * (sz + pad)), sz)
    local strata = "MEDIUM"
    pcall(function()
      if nativeList.GetFrameStrata then
        strata = nativeList:GetFrameStrata() or strata
      end
    end)
    fb:SetFrameStrata(strata)
    local lvl = 50
    pcall(function()
      if nativeList.GetFrameLevel then
        lvl = (nativeList:GetFrameLevel() or 1) + 3
      elseif parent then
        lvl = (parent:GetFrameLevel() or 1) + 15
      end
    end)
    fb:SetFrameLevel(lvl)
    pcall(function()
      if fb.SetClipsChildren then
        fb:SetClipsChildren(false)
      end
    end)
    fb:Show()
  end)
  fb._painted = painted
  fb._gapPersonal = stats.personal or 0
  fb._gapForeign = stats.foreign or 0

  pcall(LayoutMergeBesideNative, unit, plate, fb, painted)
  if painted > 0 then
    local kept = {}
    for i = 1, painted do
      kept[i] = missing[i]
    end
    RememberGapSticky(unit, kept, auraUnit)
  end
  lastPaintDebug.painted = painted
  lastPaintDebug.personal = stats.personal
  lastPaintDebug.foreign = stats.foreign
  lastPaintDebug.gapSz = sz
  lastPaintDebug.lockSz = fb._pbLockedSz
  lastPaintDebug.cdN = cdN
  SilentTracePaint("paint", unit, plate)
  return painted
end

UpdateOverlay = function(unit, plate)
  plate = plate or (unit and PlateFor(unit))
  unit = OverlayUnitKey(unit, plate)
  if not ModuleActive() or not unit then
    return
  end
  if not plate and type(unit) == "string" and unit:match("^nameplate%d+") then
    plate = PlateFor(unit)
  end
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
  RestoreNameShift(unit, plate)
  if p.mergeMissing ~= true then
    ClearFallback(unit)
    return
  end

  local okPaint, errPaint = pcall(PaintMergeMissing, unit, plate)
  if not okPaint then
    ClearFallback(unit, false)
    if ns.RecordError then
      ns.RecordError("paint", errPaint)
    end
  end
end

-- Forward decl for auto-diag after RefreshAll
local SnapshotDiagnose
local MaybeAutoDiagnose

RefreshAll = function()
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
  -- Always try target plate explicitly (secret UnitIsUnit / missing nameplate token).
  if ModuleActive() and HasTarget() then
    local tp = PlateFor("target")
  local tu = NameplateUnitFor("target") or (tp and UnitTokenFromPlate(tp))
    tu = OverlayUnitKey(tu, tp)
    if tu and tp then
      live[tu] = true
      UpdateOverlay(tu, tp)
    elseif tp then
      local pk = OverlayUnitKey(nil, tp)
      live[pk] = true
      UpdateOverlay(pk, tp)
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
  if type(SilentTraceSweep) == "function" then
    pcall(SilentTraceSweep, "refresh")
  end
end

EnsureTicker = function()
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

StopTicker = function()
  if ticker then
    pcall(function()
      ticker:Cancel()
    end)
    ticker = nil
  end
end

WatchInterval = function()
  local n = tonumber(Profile().watchInterval) or WATCH_DEFAULT_SEC
  if n < 1 then
    n = 1
  elseif n > 10 then
    n = 10
  end
  return n
end

StopWatchTicker = function()
  if watchTicker then
    pcall(function()
      watchTicker:Cancel()
    end)
    watchTicker = nil
  end
end

EnsureWatchTicker = function()
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

Defer = function(fn)
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
    native = CountPlateHarmfulShown(plate)
  elseif plateCount > 0 then
    for i = 1, #live do
      local n = CountPlateHarmfulShown(live[i].plate)
      if n > native then
        native = n
      end
    end
  end

  local tf = 0
  if targetYes then
    tf = #CollectTargetHarmfulRows(MaxIcons())
    if tf == 0 then
      tf = CountTargetFrameAuras()
    end
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

  local mergeOn = Profile().mergeMissing == true and "1" or "0"
  local lpd = lastPaintDebug or {}
  local card = string.format(
    "PLATEBAND_CARD ver=%s reason=%s target=%s plate=%s plates=%s overlays=%s ac=%s fb=%s kids=%s tf=%s native=%s merge=%s harv=%s miss=%s painted=%s tgtSrc=%s punit=%s acFail=%s enabled=%s safe=%s watch=%s seen=%s upd=%s blocked=%s",
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
    mergeOn,
    tostring(lpd.harv or "?"),
    tostring(lpd.miss or "?"),
    tostring(lpd.painted or "?"),
    tostring(lpd.tgtSrc or "?"),
    tostring(lpd.unit or plateUnit or "?"),
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
    merge = mergeOn,
    acFail = acCreateFailed and 1 or 0,
    seen = platesSeen,
    upd = overlayUpdates,
    blocked = lastBlocked,
  }

  local db = ns.Config.EnsureDB()
  db.lastDiagnose = snap
  db.lastDiag = snap -- alias for older readers

  if ns.SessionLog and ns.SessionLog.Append then
    if opts.forceChat or not SilentTraceEnabled() or reason == "manual" or reason == "watch" then
      pcall(ns.SessionLog.Append, card)
    end
  end

  local sig = string.format("%s|%s|%s|%s|%s|%s",
    snap.target, tostring(snap.plate), tostring(ac), tostring(tf), tostring(native), tostring(plateCount))

  local chatOnChange = Profile().chatOnChange
  if opts.forceChat then
    -- watch ticker always prints via caller
  elseif opts.silent or (SilentTraceEnabled() and reason ~= "manual" and reason ~= "watch") then
    -- session paint trace only — no chat
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
  if p.autoDiag == false and p.paintTraceOn == false and p.silentTrace == false then
    return
  end
  local now = GetTime and GetTime() or 0
  if SilentTraceEnabled() then
    if force or reason == "target" or reason == "manual" then
      pcall(SnapshotDiagnose, reason or "auto", { silent = true })
    end
    return
  end
  if not force and (now - lastDiagAt) < AUTO_DIAG_MIN then
    return
  end
  lastDiagAt = now
  pcall(SnapshotDiagnose, reason or "auto", {})
end

OnEvent = function(_, event, arg1)
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
      local now = GetTime and GetTime() or 0
      if (now - lastAuraRefreshAt) < AURA_DEBOUNCE_SEC then
        return
      end
      lastAuraRefreshAt = now
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
