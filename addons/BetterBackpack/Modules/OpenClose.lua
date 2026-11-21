--[[
  BetterBackpack.OpenClose — B + /bb (0.5.58)

  B + ToggleBackpack/ToggleAllBags → onBagKey XOR (0.5.50). Main backpack icon → same combined path.
  Bag-bar slots → native ToggleBag when bagBarNative, else BB bag-focus. Keyring → native only.
  ToggleBag stays Blizzard (not replaced).
  Bag-bar native: never park/blackout ContainerFrame*; RestoreNativeBagFrames on close only.
  (not hooksecurefunc). Forever Toggle* bodies call Open*/Close* first; a
  post-hook XOR then closed what we just opened (or reopened after close) —
  open/close thrash that froze the client on B.

  OpenAllBags / OpenBackpack / OpenBag = open (+ bag focus). Close* close
  ours when session open. CombinedBags OnShow: park; deferred open only if
  still closed after Toggle* (covers non-Toggle Open* paths).
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local OpenClose = {}
BetterBackpack.Modules.OpenClose = OpenClose

local Config = BetterBackpack.Config
local Layout = BetterBackpack.Modules.Layout

local hooksInstalled = false
local inBagKey = false
local inOpenIntent = false
-- 0.5.40: no frame/Open/Close/bag-bar hooks — ToggleAllBags replace only.
local SOFT_BAG_HOOKS = true
local suppressUntil = 0
local bagsOpen = false
local toggleLockUntil = 0
local pulseToken = 0
local openBusy = false
local closeBusy = false
local ignoringBagShow = false
local nativeSession = false
local nativeFocusBag = nil
local backpackBarArmUntil = 0
local TOGGLE_LOCK = 0.28
local BAG_KEY_DEBOUNCE = 0.14
local lastBagKeyHandledAt = 0
local guardElapsed = 0

-- Forward decls (BBKeyringBagIndex / frame helpers run before NormalizeBagID assignment).
local NormalizeBagID
local FocusBagsMatch
local SetFocusBag
local ClearFocusBag
local ClearCategoryFilter
local OpenOurs
local InvokeNativeKeyRing
local onKeyRingToggle
local OpenForeverKeyringIndividual
OpenClose._keyRingInnerOpen = false
OpenClose._mainPackClickAt = 0

local function Now()
  return (GetTime and GetTime()) or 0
end

local function Profile()
  return Config.GetProfile()
end

local function EnabledReplace()
  local p = Profile()
  return p.enabled and not p.safeMode and p.replaceBlizzard
end

local function OverlayAllowed()
  local p = Profile()
  return p.enabled and not p.safeMode
end

local function BagBarNativeEnabled()
  return Profile().bagBarNativeBag ~= false
end

function OpenClose.IsNativeSession()
  return nativeSession
end

local function EndNativeSession()
  nativeSession = false
  nativeFocusBag = nil
end

local function BeginNativeSession(bagID)
  nativeSession = true
  nativeFocusBag = bagID
end

local function RestoreFrameInteractive(f)
  if not f then
    return
  end
  pcall(function()
    f:SetAlpha(1)
    f:EnableMouse(true)
  end)
end

local function RestoreNativeBagFrames()
  if not BagBarNativeEnabled() then
    return
  end
  for i = 1, 13 do
    local cf = _G["ContainerFrame" .. i]
    if cf and not InCombat() and cf.IsShown and cf:IsShown() then
      pcall(function()
        local left = cf:GetLeft()
        if left ~= nil and left < -500 then
          cf:ClearAllPoints()
          cf:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
      end)
    end
    RestoreFrameInteractive(cf)
  end
  for _, name in ipairs(KeyRingFrameNames()) do
    RestoreFrameInteractive(_G[name])
  end
  -- Never restore CombinedBags here — was undoing blackout during B/open.
end

local function FrameOnScreen(f)
  if not f or not f:IsShown() then
    return false
  end
  local a = 1
  pcall(function()
    a = f:GetAlpha() or 1
  end)
  if a < 0.05 then
    return false
  end
  local left
  pcall(function()
    left = f:GetLeft()
  end)
  if left ~= nil and left < -500 then
    return false
  end
  return true
end

local function NativeContainersVisible()
  for i = 1, 13 do
    if FrameOnScreen(_G["ContainerFrame" .. i]) then
      return true
    end
  end
  for _, name in ipairs({
    "KeyRingFrame",
    "ContainerFrame-2",
    "ContainerFrameKeyRing",
    "ContainerFrame-" .. tostring(KEYRING_CONTAINER or -2),
  }) do
    if FrameOnScreen(_G[name]) then
      return true
    end
  end
  return false
end

local function KeyRingFrameNames()
  local names = {
    "KeyRingFrame",
    "ContainerFrameKeyRing",
    "ContainerFrame-2",
  }
  local key = BBKeyringBagIndex()
  if KEYRING_CONTAINER ~= nil then
    names[#names + 1] = "ContainerFrame-" .. tostring(KEYRING_CONTAINER)
  end
  if key ~= nil then
    names[#names + 1] = "ContainerFrame-" .. tostring(key)
  end
  if Enum and Enum.BagIndex and Enum.BagIndex.Keyring ~= nil then
    names[#names + 1] = "ContainerFrame-" .. tostring(Enum.BagIndex.Keyring)
  end
  return names
end

local function KeyRingFrameIsShown()
  for _, name in ipairs(KeyRingFrameNames()) do
    local f = _G[name]
    if f and f.IsShown and f:IsShown() then
      return true, f
    end
  end
  local key = BBKeyringBagIndex()
  local Slots = BetterBackpack.Modules.Slots
  for i = 1, 13 do
    local f = _G["ContainerFrame" .. i]
    if f and f.IsShown and f:IsShown() and f.GetID then
      local id
      pcall(function()
        id = NormalizeBagID(f:GetID())
      end)
      if id ~= nil and (
        (key ~= nil and FocusBagsMatch(id, key))
        or (Slots and Slots.IsKeyringBag and Slots.IsKeyringBag(id))
      ) then
        return true, f
      end
    end
  end
  return false, nil
end

local function NativeKeyRingVisible()
  for _, name in ipairs(KeyRingFrameNames()) do
    if FrameOnScreen(_G[name]) then
      return true
    end
  end
  local key = BBKeyringBagIndex()
  if key ~= nil then
    for i = 1, 13 do
      local f = _G["ContainerFrame" .. i]
      if f and f:IsShown() and f.GetID then
        local id
        pcall(function()
          id = NormalizeBagID(f:GetID())
        end)
        if id ~= nil and FocusBagsMatch(id, key) then
          return FrameOnScreen(f)
        end
      end
    end
  end
  return false
end

local function BBKeyringBagIndex()
  local Slots = BetterBackpack.Modules.Slots
  if Slots and type(Slots.KeyringBagIndex) == "function" then
    local raw = Slots.KeyringBagIndex()
    if type(NormalizeBagID) == "function" then
      local k = NormalizeBagID(raw)
      if k ~= nil then
        return k
      end
    elseif raw ~= nil then
      return raw
    end
  end
  if KEYRING_CONTAINER ~= nil then
    if type(NormalizeBagID) == "function" then
      return NormalizeBagID(KEYRING_CONTAINER)
    end
    return KEYRING_CONTAINER
  end
  return -2
end

local function RestoreShownNativeBags()
  for i = 1, 13 do
    local f = _G["ContainerFrame" .. i]
    if f and f:IsShown() then
      RestoreFrameInteractive(f)
    end
  end
  for _, name in ipairs(KeyRingFrameNames()) do
    local f = _G[name]
    if f and f:IsShown() then
      RestoreFrameInteractive(f)
    end
  end
end

local function KeyRingNativeOpen()
  if NativeKeyRingVisible() then
    return true
  end
  if KeyRingFrameIsShown() then
    return true
  end
  local key = BBKeyringBagIndex()
  if nativeSession and nativeFocusBag ~= nil and key ~= nil and FocusBagsMatch(key, nativeFocusBag) then
    return true
  end
  return false
end

local function CloseNativeBags()
  ignoringBagShow = true
  if type(CloseAllBags) == "function" then
    pcall(CloseAllBags)
  end
  EndNativeSession()
  ignoringBagShow = false
end

local function OrigToggle(name)
  local fn = OpenClose["_orig_" .. name]
  if type(fn) == "function" then
    return fn
  end
  return nil
end

local function CallOrigToggle(name, ...)
  local orig = OpenClose["_blizzard_" .. name] or OrigToggle(name)
  if type(orig) ~= "function" then
    return false
  end
  return pcall(orig, ...)
end

local function CallBlizzardToggleBag(bagID, ...)
  local orig = OpenClose["_orig_ToggleBag"] or OpenClose["_blizzard_ToggleBag"]
  if type(orig) ~= "function" then
    return false
  end
  OpenClose._keyRingInnerOpen = true
  local ok, err = pcall(orig, bagID, ...)
  OpenClose._keyRingInnerOpen = false
  if not ok and BetterBackpack.RecordError then
    BetterBackpack.RecordError("ToggleBag", err)
  end
  return ok
end

function OpenClose.ResetKeyRingGate()
  OpenClose._keyRingInnerOpen = false
end

local function BlackoutCombinedOnly()
  local f = ContainerFrameCombinedBags
  if not f then
    return
  end
  pcall(function()
    f:SetAlpha(0)
    f:EnableMouse(false)
  end)
end

function OpenClose.SuppressReplace(seconds)
  suppressUntil = (seconds and seconds > 0) and (Now() + seconds) or 0
end

function OpenClose.IsReplaceSuppressed()
  return Now() < suppressUntil
end

function OpenClose.ClearReplaceSuppress()
  suppressUntil = 0
end

local function OursVisible()
  return Layout and Layout.IsShown and Layout.IsShown()
end

local function SessionOpen()
  -- Single source of truth: frame visible (bagsOpen alone caused stuck XOR after close).
  return OursVisible()
end

local function BagKeyChat(branch, detail)
  local extra = detail and (" · " .. tostring(detail)) or ""
  local line = "|cffc9a227BetterBackpack|r onBagKey · " .. tostring(branch) .. extra
  if BetterBackpack.Print then
    BetterBackpack.Print(line)
  elseif DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(line)
  end
end

local function KeyRingChat(branch, detail)
  local extra = detail and (" · " .. tostring(detail)) or ""
  local line = "|cff88ccffBetterBackpack|r keyring · " .. tostring(branch) .. extra
  if BetterBackpack.Print then
    BetterBackpack.Print(line)
  elseif DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(line)
  end
end

local function ReleaseStaleBusy()
  if SessionOpen() then
    return
  end
  if openBusy or closeBusy or OpenClose._openBusy then
    openBusy = false
    closeBusy = false
    OpenClose._openBusy = false
  end
end

local function ResetOverlaySessionState()
  bagsOpen = false
  openBusy = false
  inBagKey = false
  inOpenIntent = false
  OpenClose._openBusy = false
  toggleLockUntil = 0
  pcall(function()
    if Layout and Layout.ForceHidden then
      Layout.ForceHidden()
    elseif Layout and Layout.Hide then
      Layout.Hide()
    end
    local g = _G.BetterBackpackFrame
    if g and g.IsShown and g:IsShown() and g.Hide then
      g:Hide()
    end
  end)
end

local function Blackout(f)
  if not f then
    return
  end
  pcall(function()
    f:SetAlpha(0)
    f:EnableMouse(false)
  end)
end

local function BlackoutAll()
  Blackout(ContainerFrameCombinedBags)
  if BagBarNativeEnabled() then
    return
  end
  for i = 1, 13 do
    Blackout(_G["ContainerFrame" .. i])
  end
end

local function Park(f)
  if not f then
    return
  end
  Blackout(f)
  if InCombatLockdown and InCombatLockdown() then
    return
  end
  pcall(function()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -8000, 8000)
  end)
end

local function InCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

local combatTraceOnce = {}

local function CombatTraceOnce(tag, detail)
  if not InCombat() then
    return
  end
  local key = tostring(tag or "?") .. "|" .. tostring(detail or "")
  if combatTraceOnce[key] then
    return
  end
  combatTraceOnce[key] = true
  local line = "combat B · " .. tostring(tag or "?")
  if detail and detail ~= "" then
    line = line .. " — " .. tostring(detail)
  end
  if BetterBackpack.Print then
    BetterBackpack.Print(line)
  elseif DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffc9a227BetterBackpack|r " .. line)
  end
end

function OpenClose.CombatTraceOnce(tag, detail)
  CombatTraceOnce(tag, detail)
end

function OpenClose.ResetCombatTrace()
  combatTraceOnce = {}
end

--- CombinedBags must not win over our overlay (B often opens it via ToggleBackpack).
local function CloseNativeCombinedBags()
  local f = ContainerFrameCombinedBags
  if not f then
    return
  end
  Blackout(f)
  if InCombat() then
    return
  end
  if f.IsShown and f:IsShown() then
    Park(f)
    pcall(function()
      f:Hide()
    end)
  end
end

--- Hide Blizzard bag UI for our overlay. Bag-bar native: CombinedBags only — never touch ContainerFrame*.
local function ParkBlizzardForOverlay()
  local combined = ContainerFrameCombinedBags
  if combined then
    Blackout(combined)
  end
  if not InCombat() and combined and combined.IsShown and combined:IsShown() then
    Park(combined)
  end
  if BagBarNativeEnabled() then
    return
  end
  for i = 1, 13 do
    local cf = _G["ContainerFrame" .. i]
    if cf and cf:IsShown() then
      Blackout(cf)
    end
  end
  if InCombat() then
    return
  end
  for i = 1, 13 do
    local cf = _G["ContainerFrame" .. i]
    if cf and cf:IsShown() then
      Park(cf)
    end
  end
end

local function ParkAllShown()
  ParkBlizzardForOverlay()
end

local function ForceCloseBlizzard()
  ignoringBagShow = true
  BlackoutAll()
  if type(CloseAllBags) == "function" then
    pcall(CloseAllBags)
  end
  BlackoutAll()
  ignoringBagShow = false
end

local function FrameVisible(f)
  if not f or not f:IsShown() then
    return false
  end
  local a = 1
  pcall(function()
    a = f:GetAlpha() or 1
  end)
  if a < 0.05 then
    return false
  end
  local left
  pcall(function()
    left = f:GetLeft()
  end)
  if left ~= nil and left < -500 then
    return false
  end
  return true
end

local function PulsePark()
  pulseToken = pulseToken + 1
  local token = pulseToken
  local delays = { 0, 0.05, 0.15, 0.3 }
  for i = 1, #delays do
    local d = delays[i]
    local function tick()
      if token ~= pulseToken or not SessionOpen() then
        return
      end
      ParkAllShown()
      if Layout and Layout.Raise then
        pcall(Layout.Raise)
      end
    end
    if d == 0 then
      tick()
    elseif C_Timer and C_Timer.After then
      C_Timer.After(d, tick)
    end
  end
end

OpenOurs = function()
  if closeBusy then
    BagKeyChat("open-skip", "closeBusy")
    return SessionOpen()
  end
  if openBusy then
    if not SessionOpen() then
      ReleaseStaleBusy()
    else
      BagKeyChat("open-skip", "openBusy visible")
      return true
    end
  end
  if not OverlayAllowed() then
    if InCombat() then
      local p = Profile()
      CombatTraceOnce("OpenOurs", string.format(
        "off enabled=%s safe=%s",
        tostring(p.enabled),
        tostring(p.safeMode)
      ))
    end
    return false
  end
  -- Allow open after suppress (next B after close).
  if OpenClose.IsReplaceSuppressed() then
    OpenClose.ClearReplaceSuppress()
  end
  openBusy = true
  OpenClose._openBusy = true
  pcall(CloseNativeCombinedBags)
  ParkBlizzardForOverlay()

  if InCombat() then
    local global = _G.BetterBackpackFrame
    local shown = false
    if global then
      if Layout and Layout.ForceCombatShow then
        shown = Layout.ForceCombatShow() and true or false
      elseif Layout and Layout.ShowCombatMinimal then
        shown = Layout.ShowCombatMinimal() and true or false
      else
        pcall(function()
          global:SetAlpha(1)
          global:EnableMouse(true)
          global:Show()
        end)
        shown = global:IsShown() and true or false
      end
    else
      CombatTraceOnce("OpenOurs", "no BetterBackpackFrame global")
    end
    openBusy = false
    OpenClose._openBusy = false
    local visible = OursVisible()
    if shown or visible then
      bagsOpen = true
      toggleLockUntil = Now() + TOGGLE_LOCK
      ParkBlizzardForOverlay()
      if Layout and Layout.Raise then
        pcall(Layout.Raise)
      end
      return true
    end
    bagsOpen = false
    ParkBlizzardForOverlay()
    local built = global and tostring(global._bbBuilt) or "nil"
    local alpha = global and tostring(global:GetAlpha()) or "nil"
    CombatTraceOnce("OpenOurs", string.format("show failed shown=%s visible=%s built=%s alpha=%s", tostring(shown), tostring(visible), built, alpha))
    local t = Now()
    if not OpenClose._combatNoFrameMsgAt or (t - OpenClose._combatNoFrameMsgAt) > 4 then
      OpenClose._combatNoFrameMsgAt = t
      local L = BetterBackpack.L or {}
      local msg = L.COMBAT_NO_FRAME or "combat: open bags once out of combat first"
      if BetterBackpack.Print then
        BetterBackpack.Print(msg)
      elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffc9a227BetterBackpack|r " .. msg)
      end
    end
    return false
  end

  local function tryShow()
    local ok, shown = pcall(function()
      return Layout.Show and Layout.Show()
    end)
    if OursVisible() then
      return true, ok, shown
    end
    return (ok and shown) and true or false, ok, shown
  end

  local okShow, ok, shown = tryShow()
  if not okShow then
    pcall(function()
      if Layout and Layout.EnsureMain then
        Layout.EnsureMain()
      end
    end)
    okShow, ok, shown = tryShow()
  end

  if not okShow or not OursVisible() then
    bagsOpen = false
    openBusy = false
    OpenClose._openBusy = false
    pcall(function()
      if Layout and Layout.Hide then
        Layout.Hide()
      end
    end)
    -- Keep Blizzard parked/closed — Unblackout + shown CombinedBags re-entered
    -- OnShow→OpenOurs and amplified the Toggle open/close thrash.
    pcall(CloseNativeCombinedBags)
    if not InCombat() then
      ForceCloseBlizzard()
    else
      ParkBlizzardForOverlay()
    end
    if BetterBackpack.RecordError and (not OpenClose._lastOpenFailAt or (Now() - OpenClose._lastOpenFailAt) > 5) then
      OpenClose._lastOpenFailAt = Now()
      BetterBackpack.RecordError("OpenOurs", ok and tostring(shown) or tostring(shown))
    end
    return false
  end

  openBusy = false
  OpenClose._openBusy = false
  bagsOpen = OursVisible()
  toggleLockUntil = bagsOpen and (Now() + TOGGLE_LOCK) or toggleLockUntil
  pcall(CloseNativeCombinedBags)
  if bagsOpen then
    if not InCombat() then
      PulsePark()
    else
      ParkBlizzardForOverlay()
    end
    if Layout and Layout.Raise then
      pcall(Layout.Raise)
    end
  end
  return bagsOpen == true
end

local function RestoreCombinedBagsUI()
  local f = ContainerFrameCombinedBags
  if not f then
    return
  end
  RestoreFrameInteractive(f)
  if InCombat() then
    return
  end
  pcall(function()
    if f.IsShown and f:IsShown() then
      f:ClearAllPoints()
      f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
  end)
end

function OpenClose.CloseOurs(opts)
  opts = opts or {}
  if closeBusy then
    if not OursVisible() then
      ReleaseStaleBusy()
    else
      BagKeyChat("close-skip", "closeBusy")
      return
    end
  end
  closeBusy = true
  bagsOpen = false
  openBusy = false
  OpenClose._openBusy = false
  pulseToken = pulseToken + 1
  OpenClose.SuppressReplace(opts.suppress or 0.25)
  ClearFocusBag()

  local ok, err = pcall(function()
    BetterBackpack._bbClosing = true
    if Layout and Layout.Hide then
      pcall(Layout.Hide)
    else
      pcall(function()
        local f = _G.BetterBackpackFrame
        if f and f.Hide then
          f:Hide()
        end
      end)
    end
    BetterBackpack._bbClosing = false

    if not OursVisible() and not InCombat() then
      if opts.closeBlizzard ~= false then
        if BagBarNativeEnabled() then
          RestoreCombinedBagsUI()
        else
          ForceCloseBlizzard()
        end
      else
        RestoreCombinedBagsUI()
      end
    elseif InCombat() then
      ParkBlizzardForOverlay()
    end
    RestoreNativeBagFrames()
    ResetOverlaySessionState()
  end)
  closeBusy = false
  if not ok and BetterBackpack.RecordError then
    BetterBackpack.RecordError("CloseOurs", err)
  end
end

function OpenClose.ResetBagSession()
  ResetOverlaySessionState()
  toggleLockUntil = 0
  OpenClose.ClearReplaceSuppress()
end

function OpenClose.NotifyHidden()
  if BetterBackpack._bbClosing then
    return
  end
  if OursVisible() then
    pcall(OpenClose.CloseOurs, { closeBlizzard = true, suppress = 0.25 })
    return
  end
  ResetOverlaySessionState()
end

function OpenClose.ShutdownToBlizzard()
  bagsOpen = false
  pulseToken = pulseToken + 1
  OpenClose.RestoreBlizzardToggles()
  OpenClose.SuppressReplace(2.0)
  BetterBackpack._bbClosing = true
  if Layout and Layout.Hide then
    pcall(Layout.Hide)
  end
  BetterBackpack._bbClosing = false
  pcall(function()
    local f = ContainerFrameCombinedBags
    if f then
      f:SetAlpha(1)
      f:EnableMouse(true)
    end
  end)
  for i = 1, 13 do
    local f = _G["ContainerFrame" .. i]
    if f then
      pcall(function()
        f:SetAlpha(1)
        f:EnableMouse(true)
      end)
    end
  end
end

function OpenClose.BagsOpen()
  return bagsOpen
end

function OpenClose.SessionOpen()
  return SessionOpen()
end

function OpenClose.Toggle()
  if SessionOpen() then
    OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.25 })
  else
    OpenOurs()
  end
end

function OpenClose.OpenOurs()
  return OpenOurs()
end

--[[ ToggleAllBags (B): BetterBackpack overlay XOR only — no native bag filtering. ]]
local function onBagKey(src)
  src = src or "?"
  if inBagKey then
    BagKeyChat("skip", src .. " inBagKey")
    return
  end
  local t = Now()
  if (t - lastBagKeyHandledAt) < BAG_KEY_DEBOUNCE then
    BagKeyChat("skip", string.format("%s debounce %.0fms", src, (t - lastBagKeyHandledAt) * 1000))
    return
  end
  if not EnabledReplace() then
    BagKeyChat("skip", src .. " replaceOff")
    return
  end
  inBagKey = true
  ReleaseStaleBusy()
  OpenClose.ClearReplaceSuppress()
  lastBagKeyHandledAt = t
  local visible = SessionOpen()
  BagKeyChat("enter", string.format(
    "%s visible=%s busy=%s/%s lock=%.2f",
    src,
    tostring(visible),
    tostring(openBusy),
    tostring(closeBusy),
    math.max(0, toggleLockUntil - t)
  ))
  local ok, err = pcall(function()
    if visible then
      BagKeyChat("close", src)
      OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.05 })
      BagKeyChat("after-close", string.format(
        "visible=%s busy=%s/%s",
        tostring(SessionOpen()),
        tostring(openBusy),
        tostring(closeBusy)
      ))
      return
    end
    BagKeyChat("open", src)
    ClearFocusBag()
    ClearCategoryFilter()
    pcall(CloseNativeCombinedBags)
    pcall(ParkBlizzardForOverlay)
    local opened = OpenOurs()
    BagKeyChat("after-open", string.format(
      "opened=%s visible=%s busy=%s/%s",
      tostring(opened),
      tostring(SessionOpen()),
      tostring(openBusy),
      tostring(closeBusy)
    ))
  end)
  if not ok then
    ReleaseStaleBusy()
    BagKeyChat("error", tostring(err))
    if BetterBackpack.RecordError then
      BetterBackpack.RecordError("onBagKey", err)
    end
  end
  inBagKey = false
end

--[[
  Replace Toggle* instead of hooksecurefunc. Post-hooks run AFTER Blizzard
  Open*/Close* (and our Open*/Close* hooks), so XOR always fought the body.
]]
local BLIZZARD_TOGGLES = { "ToggleBag", "ToggleBackpack", "ToggleKeyRing", "ToggleAllBags" }

local function CaptureBlizzardToggles()
  for i = 1, #BLIZZARD_TOGGLES do
    local name = BLIZZARD_TOGGLES[i]
    local key = "_blizzard_" .. name
    if type(OpenClose[key]) ~= "function" then
      local fn = _G[name]
      if type(fn) == "function" then
        OpenClose[key] = fn
      end
    end
  end
end

local function RestoreBlizzardToggle(globalName)
  local orig = OpenClose["_blizzard_" .. globalName] or OpenClose["_orig_" .. globalName]
  if type(orig) ~= "function" then
    return
  end
  _G[globalName] = orig
  OpenClose["_orig_" .. globalName] = nil
  OpenClose["_replaced_" .. globalName] = nil
end

function OpenClose.RestoreBlizzardToggles()
  CaptureBlizzardToggles()
  for i = 1, #BLIZZARD_TOGGLES do
    RestoreBlizzardToggle(BLIZZARD_TOGGLES[i])
  end
end

OpenClose.RestoreAllBlizzardBagToggles = OpenClose.RestoreBlizzardToggles

local function ReplaceToggle(globalName, handler)
  local orig = _G[globalName]
  if type(orig) ~= "function" then
    return false
  end
  if OpenClose["_replaced_" .. globalName] then
    return true
  end
  OpenClose["_replaced_" .. globalName] = true
  OpenClose["_orig_" .. globalName] = orig
  _G[globalName] = function(...)
    if not EnabledReplace() then
      return orig(...)
    end
    local ok, err = pcall(handler, ...)
    if not ok then
      if BetterBackpack and BetterBackpack.RecordError then
        BetterBackpack.RecordError(globalName, err)
      elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5050BetterBackpack|r " .. tostring(globalName) .. ": " .. tostring(err))
      end
    end
  end
  return true
end

local hooksLogged = false
local bagPathLogged = false

local function LogHooksOnce(detail)
  if hooksLogged then
    return
  end
  hooksLogged = true
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(
      "|cff88ff88BetterBackpack|r hooks ok · " .. tostring(detail or "bag-bar")
    )
  end
end

local function LogBagPathOnce(which, bagID)
  if bagPathLogged then
    return
  end
  bagPathLogged = true
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(
      string.format(
        "|cff88ff88BetterBackpack|r bag path · %s bag=%s",
        tostring(which or "?"),
        tostring(bagID)
      )
    )
  end
end

SetFocusBag = function(bagID)
  if Layout and Layout.SetBagFocus then
    pcall(Layout.SetBagFocus, bagID)
  end
end

ClearFocusBag = function()
  if Layout and Layout.ClearBagFocus then
    pcall(Layout.ClearBagFocus)
  end
end

FocusBagsMatch = function(a, b)
  if a == nil or b == nil then
    return false
  end
  local Slots = BetterBackpack.Modules.Slots
  if Slots and Slots.IsReagentBag and Slots.IsReagentBag(a) and Slots.IsReagentBag(b) then
    return true
  end
  return a == b
end

ClearCategoryFilter = function()
  local Filter = BetterBackpack.Modules.Filter
  if Filter and Filter.SetCategory then
    pcall(Filter.SetCategory, "all")
  end
end

local function IsMainBackpackBarButton(btn)
  if not btn then
    return false
  end
  local name
  pcall(function()
    name = btn.GetName and btn:GetName()
  end)
  return name == "MainMenuBarBackpackButton"
end

NormalizeBagID = function(bagID)
  local Slots = BetterBackpack.Modules.Slots
  if Slots and Slots.SafeNum then
    local plain = Slots.SafeNum(bagID, nil)
    if plain ~= nil then
      return plain
    end
  end
  if type(bagID) == "number" then
    if Slots and Slots.SafeNum and Slots.SafeNum(bagID, nil) == nil then
      -- Forever secret bag index — keep opaque value for Blizzard ToggleBag/OpenBag.
      return bagID
    end
    return bagID
  end
  if type(bagID) == "string" then
    local n = tonumber(bagID)
    if n then
      return n
    end
  end
  return nil
end

--- Plain number when possible; otherwise raw bag token (incl. secret Enum indices).
local function BagIDForNative(bagID)
  local plain = NormalizeBagID(bagID)
  if plain ~= nil then
    return plain
  end
  if bagID ~= nil then
    return bagID
  end
  return nil
end

local function BagIdFromButtonName(btn)
  if not btn then
    return nil
  end
  local name
  pcall(function()
    name = btn.GetName and btn:GetName()
  end)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local Slots = BetterBackpack.Modules.Slots
  if name == "MainMenuBarBackpackButton" then
    return 0
  end
  local n = name:match("^CharacterBag(%d+)Slot$")
  if n then
    return tonumber(n)
  end
  n = name:match("^MainMenuBarBagButton(%d+)$")
  if n then
    local i = tonumber(n)
    if i == 5 and Slots and Slots.ReagentBagIndex then
      return Slots.ReagentBagIndex()
    end
    if i and i >= 1 then
      return i
    end
    return i
  end
  n = name:match("^MultiBag(%d+)$")
  if n then
    return tonumber(n)
  end
  if name:find("KeyRing", 1, true) or name:find("Keyring", 1, true) then
    return BBKeyringBagIndex()
  end
  return nil
end

local function IsKeyringBarButton(btn)
  if not btn then
    return false
  end
  local name
  pcall(function()
    name = btn.GetName and btn:GetName()
  end)
  if type(name) == "string" and (name:find("KeyRing", 1, true) or name:find("Keyring", 1, true)) then
    return true
  end
  local Slots = BetterBackpack.Modules.Slots
  local id = BagIdFromButton(btn)
  return Slots and Slots.IsKeyringBag and id ~= nil and Slots.IsKeyringBag(id)
end

local function IsKnownBagID(bagID)
  local raw = bagID
  if raw == nil then
    return false, nil
  end
  local Slots = BetterBackpack.Modules.Slots
  if Slots and Slots.IsKeyringBag and Slots.IsKeyringBag(raw) then
    local key = BBKeyringBagIndex()
    return true, key or raw
  end
  if Slots and Slots.IsReagentBag and Slots.IsReagentBag(raw) then
    local reb = Slots.ReagentBagIndex and Slots.ReagentBagIndex() or 5
    return true, reb or raw
  end
  local plain = nil
  if Slots and Slots.SafeNum then
    plain = Slots.SafeNum(raw, nil)
  elseif type(raw) == "number" and (not Slots or not Slots.IsSecret or not Slots.IsSecret(raw)) then
    plain = raw
  end
  if plain ~= nil then
    local max = 4
    pcall(function()
      if NUM_BAG_SLOTS ~= nil then
        local n = Slots and Slots.SafeNum and Slots.SafeNum(NUM_BAG_SLOTS, nil) or NUM_BAG_SLOTS
        if type(n) == "number" then
          max = n
        end
      end
    end)
    if plain >= 0 and plain <= math.max(max, 4) then
      return true, plain
    end
    if plain >= -4 and plain <= 13 then
      return true, plain
    end
  end
  -- Secret or opaque bag index from BagsBar / ToggleBag — pass through to Blizzard.
  return true, raw
end

local function FinishNativeOpen()
  OpenClose._nativeOpening = false
  RestoreShownNativeBags()
  if type(UpdateContainerFrameAnchors) == "function" then
    pcall(UpdateContainerFrameAnchors)
  end
  if type(UpdateInventoryAndQuestFlags) == "function" then
    pcall(UpdateInventoryAndQuestFlags)
  end
  ignoringBagShow = false
end

local function KeyRingContainerBagID()
  if KEYRING_CONTAINER ~= nil then
    return KEYRING_CONTAINER
  end
  if Enum and Enum.BagIndex and Enum.BagIndex.Keyring ~= nil then
    return Enum.BagIndex.Keyring
  end
  return BBKeyringBagIndex()
end

local function IsForeverKeyringBag(bagID)
  if bagID == nil then
    return false
  end
  local bag = KeyRingContainerBagID()
  if bag ~= nil and FocusBagsMatch(bagID, bag) then
    return true
  end
  local Slots = BetterBackpack.Modules.Slots
  return Slots and Slots.IsKeyringBag and Slots.IsKeyringBag(bagID)
end

local function ForeverKeyringShouldShow()
  if C_ActionBar and type(C_ActionBar.ShouldShowKeyring) == "function" then
    local ok, show = pcall(C_ActionBar.ShouldShowKeyring)
    if ok and not show then
      return false
    end
  end
  if GetCVarBool and type(GetCVarBool) == "function" then
    local ok, show = pcall(GetCVarBool, "showKeyring")
    if ok and show == false then
      return false
    end
  end
  return true
end

local function FindKeyringContainerFrame()
  local bag = KeyRingContainerBagID()
  if bag == nil then
    return nil, false
  end
  if type(ContainerFrameUtil_GetShownFrameForID) == "function" then
    local f, shown = ContainerFrameUtil_GetShownFrameForID(bag)
    if f then
      local vis = shown
      if vis == nil and f.IsShown then
        vis = f:IsShown()
      end
      return f, vis and true or false
    end
  end
  if ContainerFrameUtil and type(ContainerFrameUtil.GetShownFrameForID) == "function" then
    local f = ContainerFrameUtil.GetShownFrameForID(bag)
    if f then
      return f, f.IsShown and f:IsShown() and true or false
    end
  end
  if type(IsBagOpen) == "function" then
    local idx = IsBagOpen(bag)
    if idx then
      local f = _G["ContainerFrame" .. tostring(idx)]
      if f then
        return f, f.IsShown and f:IsShown() and true or false
      end
    end
  end
  return KeyRingFrameIsShown()
end

local function CloseForeverKeyring()
  local bag = KeyRingContainerBagID()
  if type(CloseBag) == "function" and bag ~= nil then
    pcall(CloseBag, bag)
  end
  local frame, shown = FindKeyringContainerFrame()
  if shown and frame and frame.Hide then
    pcall(function()
      frame:Hide()
    end)
  elseif bag ~= nil then
    CallBlizzardToggleBag(bag)
  end
  EndNativeSession()
end

OpenForeverKeyringIndividual = function()
  if not ForeverKeyringShouldShow() then
    KeyRingChat("skip", "Forever keyring gated off")
    return false
  end
  local bag = KeyRingContainerBagID()
  KeyRingChat("open-forever", "KEYRING=" .. tostring(bag))
  BlackoutCombinedOnly()
  if type(ContainerFrame_AllowedToOpenBags) == "function" then
    local ok, allowed = pcall(ContainerFrame_AllowedToOpenBags)
    KeyRingChat("allowed", tostring(ok and allowed))
    if ok and not allowed then
      return false
    end
  end
  if type(OpenBag) == "function" and bag ~= nil then
    pcall(OpenBag, bag, true)
  end
  local frame, shown = FindKeyringContainerFrame()
  if not shown and bag ~= nil then
    CallBlizzardToggleBag(bag)
    frame, shown = FindKeyringContainerFrame()
  end
  if frame then
    pcall(function()
      RestoreFrameInteractive(frame)
      if frame.Show and not frame:IsShown() then
        frame:Show()
      end
      local left
      pcall(function()
        left = frame:GetLeft()
      end)
      if left == nil or left < -500 then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      end
    end)
  end
  if type(SetButtonPulse) == "function" and KeyRingButton then
    pcall(SetButtonPulse, KeyRingButton, 0, 1)
  end
  if type(UpdateContainerFrameAnchors) == "function" then
    pcall(UpdateContainerFrameAnchors)
  end
  shown = NativeKeyRingVisible() or KeyRingFrameIsShown()
  KeyRingChat("opened", string.format(
    "frame=%s onScreen=%s",
    tostring(frame and frame.GetName and frame:GetName()),
    tostring(shown)
  ))
  return shown and true or false
end
OpenClose.OpenForeverKeyringIndividual = OpenForeverKeyringIndividual
OpenClose.ForceKeyRingContainerFrame = OpenForeverKeyringIndividual

local function ForceKeyRingFrameShow()
  local Slots = BetterBackpack.Modules.Slots
  local key = BBKeyringBagIndex()
  for _, name in ipairs(KeyRingFrameNames()) do
    local f = _G[name]
    if f then
      pcall(function()
        RestoreFrameInteractive(f)
        if f.Show then
          f:Show()
        end
        local left
        pcall(function()
          left = f:GetLeft()
        end)
        if left == nil or left < -500 then
          f:ClearAllPoints()
          f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
      end)
    end
  end
  for i = 1, 13 do
    local f = _G["ContainerFrame" .. i]
    if f and f.GetID then
      local id
      pcall(function()
        id = f:GetID()
      end)
      if id ~= nil and key ~= nil and (
        FocusBagsMatch(id, key)
        or (Slots and Slots.IsKeyringBag and Slots.IsKeyringBag(id))
      ) then
        pcall(function()
          RestoreFrameInteractive(f)
          f:Show()
        end)
      end
    end
  end
  if type(UpdateContainerFrameAnchors) == "function" then
    pcall(UpdateContainerFrameAnchors)
  end
end

OpenClose.ForceKeyRingFrameShow = ForceKeyRingFrameShow

InvokeNativeKeyRing = function()
  ignoringBagShow = true
  OpenClose._nativeOpening = true
  pcall(OpenForeverKeyringIndividual)
  ForceKeyRingFrameShow()
  RestoreShownNativeBags()
  local function finish()
    ForceKeyRingFrameShow()
    FinishNativeOpen()
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, finish)
    C_Timer.After(0.05, finish)
  else
    finish()
  end
end

onKeyRingToggle = function(src)
  src = src or "ToggleKeyRing"
  KeyRingChat("toggle", src)
  if SessionOpen() or OursVisible() then
    OpenClose.CloseOurs({ closeBlizzard = false, suppress = 0.05 })
  end
  if KeyRingNativeOpen() then
    KeyRingChat("close", src)
    CloseForeverKeyring()
    return
  end
  KeyRingChat("open", src)
  BeginNativeSession(BBKeyringBagIndex())
  pcall(InvokeNativeKeyRing)
end

local function onToggleBagRoute(bagID, ...)
  if IsForeverKeyringBag(bagID) then
    if OpenClose._keyRingInnerOpen then
      CallBlizzardToggleBag(bagID, ...)
      return
    end
    onKeyRingToggle("ToggleBag")
    return
  end
  if EnabledReplace() and (Now() - (OpenClose._mainPackClickAt or 0)) < 0.2 then
    local Slots = BetterBackpack.Modules.Slots
    local p = Slots and Slots.SafeNum and Slots.SafeNum(bagID, nil)
    if p == 0 then
      BagKeyChat("skip", "ToggleBag(0) after main-pack combined")
      return
    end
  end
  if not EnabledReplace() or not BagBarNativeEnabled() then
    CallOrigToggle("ToggleBag", bagID, ...)
    return
  end
  if SessionOpen() or OursVisible() then
    OpenClose.CloseOurs({ closeBlizzard = false, suppress = 0.05 })
  end
  BlackoutCombinedOnly()
  CallOrigToggle("ToggleBag", bagID, ...)
end

local function InvokeNativeToggleBag(bagID)
  local raw = bagID
  local Slots = BetterBackpack.Modules.Slots
  if Slots and Slots.IsKeyringBag and raw ~= nil and Slots.IsKeyringBag(raw) then
    InvokeNativeKeyRing()
    return
  end
  local apiBag = BagIDForNative(raw)
  ignoringBagShow = true
  OpenClose._nativeOpening = true
  BlackoutCombinedOnly()
  if apiBag ~= nil and not CallOrigToggle("ToggleBag", apiBag) and type(OpenBag) == "function" then
    pcall(OpenBag, apiBag)
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, FinishNativeOpen)
    C_Timer.After(0.05, FinishNativeOpen)
  else
    FinishNativeOpen()
  end
end

local function ArmBackpackBarNative()
  backpackBarArmUntil = Now() + 0.2
end

local function onBackpackToggle(...)
  if not EnabledReplace() then
    CallOrigToggle("ToggleBackpack", ...)
    return
  end
  onBagKey("ToggleBackpack")
end

--[[
  Open-only (OpenAllBags / OpenBag / CombinedBags fallback): open if closed;
  if open, park Blizzard + refresh focus.
]]
local function onOpenIntent(bagID)
  if inOpenIntent or inBagKey or ignoringBagShow or closeBusy or openBusy then
    return
  end
  if not EnabledReplace() then
    return
  end
  if BagBarNativeEnabled() then
    if SessionOpen() or OursVisible() then
      OpenClose.CloseOurs({ closeBlizzard = false, suppress = 0.05 })
    end
    return
  end
  inOpenIntent = true
  bagID = NormalizeBagID(bagID)

  BlackoutAll()
  CloseNativeBags()
  if bagID ~= nil then
    SetFocusBag(bagID)
    ClearCategoryFilter()
  else
    ClearFocusBag()
    ClearCategoryFilter()
  end
  if SessionOpen() or openBusy then
    ParkAllShown()
    if Layout and Layout.Raise then
      pcall(Layout.Raise)
    end
    if Layout and Layout.Relayout then
      pcall(Layout.Relayout)
    end
    inOpenIntent = false
    return
  end
  if OpenClose.IsReplaceSuppressed() then
    OpenClose.ClearReplaceSuppress()
  end
  local t = Now()
  if t < toggleLockUntil then
    ParkAllShown()
    inOpenIntent = false
    return
  end
  toggleLockUntil = t + TOGGLE_LOCK
  pcall(OpenOurs)
  inOpenIntent = false
end

-- ToggleBag + bag-bar OnClick often fire together — debounce to one XOR.
local lastBagToggleAt = 0

--[[ Bag-bar: native ToggleBag when bagBarNative; overlay single-bag focus XOR. ]]
local function onBagToggle(bagID, src)
  if not EnabledReplace() then
    CallOrigToggle("ToggleBag", bagID)
    return
  end
  if BagBarNativeEnabled() then
    if SessionOpen() or OursVisible() then
      OpenClose.CloseOurs({ closeBlizzard = false, suppress = 0.05 })
    end
    BlackoutCombinedOnly()
    CallOrigToggle("ToggleBag", bagID)
    return
  end
  if closeBusy then
    return
  end
  bagID = BagIDForNative(bagID)
  if bagID == nil then
    return
  end
  local t = Now()
  if (t - lastBagToggleAt) < 0.08 then
    return
  end
  lastBagToggleAt = t
  if t < toggleLockUntil then
    ParkBlizzardForOverlay()
    return
  end
  toggleLockUntil = t + TOGGLE_LOCK
  ParkBlizzardForOverlay()
  if SessionOpen() then
    local focused = Layout and Layout.GetBagFocus and Layout.GetBagFocus()
    if focused ~= nil and FocusBagsMatch(bagID, focused) then
      OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.05 })
    else
      SetFocusBag(bagID)
      ClearCategoryFilter()
      if Layout and Layout.Relayout then
        pcall(Layout.Relayout)
      end
    end
  else
    SetFocusBag(bagID)
    ClearCategoryFilter()
    OpenOurs()
  end
end

local function onCloseIntent()
  if ignoringBagShow or closeBusy then
    return
  end
  if not EnabledReplace() then
    return
  end
  if SessionOpen() then
    ClearFocusBag()
    OpenClose.CloseOurs({ closeBlizzard = false, suppress = 0.25 })
  elseif nativeSession or NativeContainersVisible() then
    EndNativeSession()
  end
end

local function FrameSupportsOnClick(btn)
  if not btn or type(btn.HookScript) ~= "function" then
    return false
  end
  local ok, supported = pcall(function()
    return btn.HasScript and btn:HasScript("OnClick")
  end)
  if ok and supported then
    return true
  end
  -- Bag-bar slots are often Buttons without HasScript until shown.
  local ot
  pcall(function()
    ot = btn.GetObjectType and btn:GetObjectType()
  end)
  return ot == "Button" or ot == "CheckButton"
end

local function SafeHookOnClick(btn, handler)
  if not btn or btn.BetterBackpackClickHooked then
    return false
  end
  if not FrameSupportsOnClick(btn) then
    return false
  end
  local ok = pcall(function()
    btn:HookScript("OnClick", handler)
  end)
  if ok then
    btn.BetterBackpackClickHooked = true
  end
  return ok
end

local function BagIdFromButton(btn)
  if not btn then
    return nil
  end
  local bagID
  pcall(function()
    if btn.GetBagID then
      bagID = btn:GetBagID()
    elseif btn.bagID ~= nil then
      bagID = btn.bagID
    elseif btn.id ~= nil then
      bagID = btn.id
    end
  end)
  local fromApi = NormalizeBagID(bagID)
  if fromApi ~= nil then
    return fromApi
  end
  return NormalizeBagID(BagIdFromButtonName(btn))
end

local function onBagBarClick(btn)
  return function(self)
    if not EnabledReplace() then
      return
    end
    local b = self or btn
    if IsMainBackpackBarButton(b) then
      onBagKey("bag-bar/backpack")
      return
    end
    if IsKeyringBarButton(b) then
      if BagBarNativeEnabled() then
        KeyRingChat("bag-bar", "native → ToggleBag hook")
        return
      end
      onKeyRingToggle("bag-bar")
      return
    end
    if BagBarNativeEnabled() then
      local raw
      pcall(function()
        if b and b.GetBagID then
          raw = b:GetBagID()
        end
      end)
      if raw ~= nil then
        onBagToggle(raw, "bag-bar")
      else
        onBagKey("bag-bar/fallback")
      end
      return
    end
    onBagToggle(BagIdFromButton(b), "bag-bar")
  end
end

local function HookOneBackpackArm(btn)
  if not btn or btn.BetterBackpackArmNative then
    return false
  end
  local ok = pcall(function()
    btn:HookScript("OnMouseDown", function()
      if EnabledReplace() and BagBarNativeEnabled() then
        ArmBackpackBarNative()
      end
    end)
  end)
  if ok then
    btn.BetterBackpackArmNative = true
  end
  return ok
end

local function HookBackpackBarMouseDown()
  local n = 0
  if HookOneBackpackArm(_G.MainMenuBarBackpackButton) then
    n = n + 1
  end
  if HookOneBackpackArm(_G.CharacterBag0Slot) then
    n = n + 1
  end
  return n > 0
end

local KEYRING_BAR_NAMES = {
  "KeyRingButton",
  "KeyringButton",
  "KeyRingFrameButton",
  "CharacterBagKeyringButton",
  "MainMenuBarKeyRingButton",
}

local function HookMainBackpackCombined()
  local btn = _G.MainMenuBarBackpackButton
  if not btn or btn.BetterBackpackMainPackHooked then
    return false
  end
  local hookOk = pcall(function()
    btn:HookScript("OnClick", function()
      if not EnabledReplace() then
        return
      end
      OpenClose._mainPackClickAt = Now()
      BagKeyChat("main-pack", "MainMenuBarBackpack OnClick")
      onBagKey("MainMenuBarBackpackButton")
    end)
  end)
  if hookOk then
    btn.BetterBackpackMainPackHooked = true
  end
  return hookOk
end

local function HookKeyRingBarButtons()
  local hooked = 0
  for i = 1, #KEYRING_BAR_NAMES do
    local btn = _G[KEYRING_BAR_NAMES[i]]
    if btn and not btn.BetterBackpackKeyRingTraced then
      local hookOk = pcall(function()
        btn:HookScript("OnClick", function(self)
          local bname = (self and self.GetName and self:GetName()) or KEYRING_BAR_NAMES[i]
          KeyRingChat("OnClick", bname)
        end)
      end)
      if hookOk then
        btn.BetterBackpackKeyRingTraced = true
        hooked = hooked + 1
      end
    end
  end
  for _, rootName in ipairs({ "BagsBar", "MainMenuBarBagButtons", "MicroButtonAndBagsBar" }) do
    local root = _G[rootName]
    if root and root.GetChildren then
      local kids = { root:GetChildren() }
      for j = 1, #kids do
        local kid = kids[j]
        if kid and IsKeyringBarButton(kid) and not kid.BetterBackpackKeyRingTraced then
          pcall(function()
            kid:HookScript("OnClick", function(self)
              local bname = (self and self.GetName and self:GetName()) or "keyring-child"
              KeyRingChat("OnClick", bname)
            end)
            kid.BetterBackpackKeyRingTraced = true
            hooked = hooked + 1
          end)
        end
      end
    end
  end
  if hooked > 0 then
    KeyRingChat("hooks", tostring(hooked) .. " KeyRingButton(s)")
  end
  return hooked
end

local function HookBagBarButtons()
  pcall(HookKeyRingBarButtons)
  pcall(HookMainBackpackCombined)
  if BagBarNativeEnabled() then
    return 0
  end
  HookBackpackBarMouseDown()
  local hooked = 0
  local names = {
    "MainMenuBarBackpackButton",
    "MainMenuBarBagButton1",
    "MainMenuBarBagButton2",
    "MainMenuBarBagButton3",
    "MainMenuBarBagButton4",
    "MainMenuBarBagButton5",
    "CharacterBag0Slot",
    "CharacterBag1Slot",
    "CharacterBag2Slot",
    "CharacterBag3Slot",
    "CharacterReagentBag0Slot",
    "ReagentBagSlot",
    "KeyRingButton",
    "KeyringButton",
    "KeyRingFrameButton",
    "CharacterBagKeyringButton",
    "MainMenuBarKeyRingButton",
    "MultiBag1",
    "MultiBag2",
    "MultiBag3",
    "MultiBag4",
    "MultiBag5",
  }
  for i = 1, #names do
    if SafeHookOnClick(_G[names[i]], onBagBarClick(_G[names[i]])) then
      hooked = hooked + 1
    end
  end
  for i = 0, 12 do
    local n = "MultiBag" .. i
    if SafeHookOnClick(_G[n], onBagBarClick(_G[n])) then
      hooked = hooked + 1
    end
  end
  for _, rootName in ipairs({ "BagsBar", "MainMenuBarBagButtons", "MicroButtonAndBagsBar" }) do
    local root = _G[rootName]
    if root and root.GetChildren then
      local kids = { root:GetChildren() }
      for i = 1, #kids do
        if SafeHookOnClick(kids[i], onBagBarClick(kids[i])) then
          hooked = hooked + 1
        end
      end
    end
  end
  return hooked
end

local BAG_KEY_TOGGLES = { "ToggleAllBags", "ToggleBackpack" }

local function ApplyBagKeyReplace()
  CaptureBlizzardToggles()
  OpenClose.RestoreBlizzardToggles()
  ReplaceToggle("ToggleAllBags", function(...)
    onBagKey("ToggleAllBags")
  end)
  ReplaceToggle("ToggleBackpack", onBackpackToggle)
  ReplaceToggle("ToggleBag", onToggleBagRoute)
  ReplaceToggle("ToggleKeyRing", function(...)
    onKeyRingToggle("ToggleKeyRing")
  end)
end

function OpenClose.EnsureBagKeyReplace()
  pcall(ApplyBagKeyReplace)
end

function OpenClose.InstallHooks()
  if hooksInstalled then
    return
  end
  hooksInstalled = true
  local ok, err = pcall(ApplyBagKeyReplace)
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      pcall(ApplyBagKeyReplace)
    end)
    C_Timer.After(1, function()
      pcall(ApplyBagKeyReplace)
    end)
  end
  pcall(HookKeyRingBarButtons)
  pcall(HookMainBackpackCombined)
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      pcall(HookKeyRingBarButtons)
      pcall(HookMainBackpackCombined)
      pcall(HookBagBarButtons)
    end)
    C_Timer.After(1, function()
      pcall(HookKeyRingBarButtons)
      pcall(HookMainBackpackCombined)
    end)
  else
    pcall(HookBagBarButtons)
  end
  if ok then
    local n = 0
    if OpenClose._replaced_ToggleAllBags then
      n = n + 1
    end
    if OpenClose._replaced_ToggleBackpack then
      n = n + 1
    end
    if n > 0 then
      LogHooksOnce(string.format(
        "B XOR · ToggleBag keyring→individual OpenBag · %d/%d B toggles",
        n,
        #BAG_KEY_TOGGLES
      ))
    else
      LogHooksOnce("bag-key toggles missing · /bb only")
    end
  elseif BetterBackpack and BetterBackpack.RecordError then
    BetterBackpack.RecordError("hooks", err)
  end
end


function OpenClose.RunOpenCloseSelfTest()
  local pass, fail, notes = 0, 0, {}
  local function ok(cond, msg)
    if cond then
      pass = pass + 1
    else
      fail = fail + 1
      notes[#notes + 1] = msg
    end
  end
  if InCombatLockdown and InCombatLockdown() then
    ok(true, "combat skip")
    return fail == 0, pass, fail, notes
  end
  if SessionOpen() then
    OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.05 })
  end
  ok(OpenOurs() == true, "OpenOurs failed")
  ok(OursVisible(), "frame not shown")
  -- Simulate one close (no grace)
  OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.05 })
  ok(not SessionOpen(), "still open after one CloseOurs")
  ok(not OursVisible(), "frame still shown after close")
  OpenClose.ClearReplaceSuppress()
  return fail == 0, pass, fail, notes
end

function OpenClose.DumpOpenState()
  local lockRem = math.max(0, toggleLockUntil - Now())
  local supRem = math.max(0, suppressUntil - Now())
  local kr = KeyRingNativeOpen() and "open" or "closed"
  local krKey = tostring(BBKeyringBagIndex())
  return string.format(
    "open overlay=%s session=%s layout=%s · native sess=%s focus=%s ui=%s · keyring=%s idx=%s · lock=%.2fs suppress=%.2fs · busy o/c=%s/%s · bagBarNative=%s",
    tostring(bagsOpen),
    tostring(SessionOpen()),
    tostring(OursVisible()),
    tostring(nativeSession),
    tostring(nativeFocusBag),
    tostring(NativeContainersVisible()),
    kr,
    krKey,
    lockRem,
    supRem,
    tostring(openBusy),
    tostring(closeBusy),
    tostring(BagBarNativeEnabled())
  )
end

OpenClose.ForceCloseBlizzard = ForceCloseBlizzard
OpenClose.ParkAllShown = ParkAllShown
OpenClose.BlackoutAll = BlackoutAll
