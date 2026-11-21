--[[
  BetterBackpack.OpenClose — B + /bb (0.5.44)

  Only ToggleAllBags is *replaced* (BetterBackpack combined XOR via onBagKey). ToggleBag/ToggleBackpack/ToggleKeyRing stay Blizzard.
  No bag-bar OnClick hooks in InstallHooks.
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
local guardElapsed = 0

-- Forward decls (BBKeyringBagIndex / frame helpers run before NormalizeBagID assignment).
local NormalizeBagID
local FocusBagsMatch
local SetFocusBag
local ClearFocusBag
local ClearCategoryFilter
local OpenOurs
local InvokeNativeKeyRing

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
  return bagsOpen or OursVisible()
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

--- Hide Blizzard bag UI for our overlay. In combat: alpha/mouse only (no ClearAllPoints).
local function ParkBlizzardForOverlay()
  Blackout(ContainerFrameCombinedBags)
  if BagBarNativeEnabled() then
    if InCombat() then
      return
    end
    local f = ContainerFrameCombinedBags
    if f and f:IsShown() then
      Park(f)
    end
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
  local f = ContainerFrameCombinedBags
  if f and f:IsShown() then
    Park(f)
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
  if openBusy or closeBusy then
    if InCombat() then
      CombatTraceOnce("OpenOurs", "busy open=" .. tostring(openBusy) .. " close=" .. tostring(closeBusy))
    end
    return SessionOpen()
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

  bagsOpen = true
  toggleLockUntil = Now() + TOGGLE_LOCK
  openBusy = false
  OpenClose._openBusy = false
  if not InCombat() then
    PulsePark()
  else
    ParkBlizzardForOverlay()
  end
  if Layout and Layout.Raise then
    pcall(Layout.Raise)
  end
  return true
end

function OpenClose.CloseOurs(opts)
  opts = opts or {}
  if closeBusy then
    if InCombat() then
      CombatTraceOnce("CloseOurs", "closeBusy")
    end
    return
  end
  closeBusy = true
  bagsOpen = false
  pulseToken = pulseToken + 1
  OpenClose.SuppressReplace(opts.suppress or 0.25)
  ClearFocusBag()

  BlackoutAll()
  BetterBackpack._bbClosing = true
  if Layout and Layout.Hide then
    pcall(Layout.Hide)
  end
  BetterBackpack._bbClosing = false

  if opts.closeBlizzard ~= false and not InCombat() then
    ForceCloseBlizzard()
  elseif InCombat() then
    ParkBlizzardForOverlay()
  end
  closeBusy = false
end

function OpenClose.NotifyHidden()
  if BetterBackpack._bbClosing then
    return
  end
  if SessionOpen() then
    OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.25 })
  else
    bagsOpen = false
  end
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
local function onBagKey()
  if inBagKey then
    return
  end
  if not EnabledReplace() then
    CombatTraceOnce("onBagKey", "EnabledReplace=false")
    return
  end
  inBagKey = true
  OpenClose.ClearReplaceSuppress()
  if SessionOpen() then
    pcall(OpenClose.CloseOurs, { closeBlizzard = false, suppress = 0.25 })
    inBagKey = false
    return
  end
  pcall(ParkBlizzardForOverlay)
  pcall(OpenOurs)
  inBagKey = false
end

local function onKeyRingToggle()
  if not EnabledReplace() then
    CallOrigToggle("ToggleKeyRing")
    return
  end
  if BagBarNativeEnabled() then
    if SessionOpen() or bagsOpen or OursVisible() then
      OpenClose.CloseOurs({ closeBlizzard = false, suppress = 0.2 })
    end
    BlackoutCombinedOnly()
    CallOrigToggle("ToggleKeyRing")
    return
  end
  if SessionOpen() then
    ClearFocusBag()
    ClearCategoryFilter()
    OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.25 })
  else
    if BBKeyringBagIndex() ~= nil then
      SetFocusBag(BBKeyringBagIndex())
    end
    local Filter = BetterBackpack.Modules.Filter
    if Filter and Filter.SetCategory then
      pcall(Filter.SetCategory, "keys")
    end
    OpenOurs()
  end
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

InvokeNativeKeyRing = function()
  local key = BBKeyringBagIndex()
  ignoringBagShow = true
  OpenClose._nativeOpening = true
  BlackoutCombinedOnly()

  local function opened()
    if NativeKeyRingVisible() or KeyRingFrameIsShown() then
      return true
    end
    return false
  end

  if not CallOrigToggle("ToggleKeyRing") and key ~= nil then
    CallOrigToggle("ToggleBag", key)
  end
  if not opened() and key ~= nil then
    if not CallOrigToggle("ToggleBag", key) and type(OpenBag) == "function" then
      pcall(OpenBag, key)
    end
  end
  if not opened() and type(OpenKeyRing) == "function" then
    pcall(OpenKeyRing)
  end

  local _, krFrame = KeyRingFrameIsShown()
  if krFrame then
    RestoreFrameInteractive(krFrame)
  end
  RestoreShownNativeBags()

  if C_Timer and C_Timer.After then
    C_Timer.After(0, FinishNativeOpen)
    C_Timer.After(0.05, FinishNativeOpen)
  else
    FinishNativeOpen()
  end
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

local function onBackpackToggle()
  if not EnabledReplace() then
    CallOrigToggle("ToggleBackpack")
    return
  end
  if BagBarNativeEnabled() and Now() < backpackBarArmUntil then
    if SessionOpen() or bagsOpen or OursVisible() then
      OpenClose.CloseOurs({ closeBlizzard = false, suppress = 0.2 })
    end
    BlackoutCombinedOnly()
    CallOrigToggle("ToggleBackpack")
    return
  end
  onBagKey()
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
    if SessionOpen() or bagsOpen or OursVisible() then
      OpenClose.CloseOurs({ closeBlizzard = false, suppress = 0.2 })
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

--[[ Bag-bar: orig Blizzard ToggleBag only (raw id, incl. secret Enum). Overlay mode: focus lane. ]]
local function onBagToggle(bagID, src)
  if not EnabledReplace() then
    CallOrigToggle("ToggleBag", bagID)
    return
  end
  if BagBarNativeEnabled() then
    if SessionOpen() or bagsOpen or OursVisible() then
      OpenClose.CloseOurs({ closeBlizzard = false, suppress = 0.2 })
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
      OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.25 })
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
    if BagBarNativeEnabled() then
      -- Blizzard Toggle* replace forwards to orig; avoid filtered BagIdFromButton.
      if IsKeyringBarButton(self or btn) then
        onKeyRingToggle()
        return
      end
      local raw
      pcall(function()
        local b = self or btn
        if b and b.GetBagID then
          raw = b:GetBagID()
        end
      end)
      if raw ~= nil then
        onBagToggle(raw, "bag-bar")
      else
        CallOrigToggle("ToggleBackpack")
      end
      return
    end
    onBagToggle(BagIdFromButton(self or btn), "bag-bar")
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

local function HookBagBarButtons()
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

function OpenClose.InstallHooks()
  if hooksInstalled then
    return
  end
  local ok, err = pcall(function()
    CaptureBlizzardToggles()
    OpenClose.RestoreBlizzardToggles()
    ReplaceToggle("ToggleAllBags", onBagKey)
  end)
  hooksInstalled = true
  if ok then
    if OpenClose._replaced_ToggleAllBags then
      LogHooksOnce("B → BetterBackpack XOR · bag bar = Blizzard")
    else
      LogHooksOnce("ToggleAllBags missing · /bb only")
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
