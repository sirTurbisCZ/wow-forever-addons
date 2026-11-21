--[[
  BetterBackpack.OpenClose — B overlay + bag-bar native (0.5.30)

  ToggleAllBags / ToggleBackpack / ToggleBag / ToggleKeyRing are *replaced*
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
  for _, name in ipairs({ "KeyRingFrame", "ContainerFrame-2", "ContainerFrameKeyRing" }) do
    if FrameOnScreen(_G[name]) then
      return true
    end
  end
  return false
end

local function RestoreShownNativeBags()
  for i = 1, 13 do
    local f = _G["ContainerFrame" .. i]
    if f and f:IsShown() then
      RestoreFrameInteractive(f)
    end
  end
  for _, name in ipairs({ "KeyRingFrame", "ContainerFrame-2", "ContainerFrameKeyRing" }) do
    local f = _G[name]
    if f and f:IsShown() then
      RestoreFrameInteractive(f)
    end
  end
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
  return OpenClose["_orig_" .. name]
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

local function ParkAllShown()
  BlackoutAll()
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

local OpenOurs
local SetFocusBag
local ClearFocusBag
local NormalizeBagID
local ClearCategoryFilter
local FocusBagsMatch

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
    return SessionOpen()
  end
  if not EnabledReplace() then
    return false
  end
  -- Allow open after suppress (next B after close).
  if OpenClose.IsReplaceSuppressed() then
    OpenClose.ClearReplaceSuppress()
  end
  openBusy = true
  OpenClose._openBusy = true
  BlackoutAll()
  ParkAllShown()

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
    ForceCloseBlizzard()
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
  PulsePark()
  if Layout and Layout.Raise then
    pcall(Layout.Raise)
  end
  return true
end

function OpenClose.CloseOurs(opts)
  opts = opts or {}
  if closeBusy then
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

  if opts.closeBlizzard ~= false then
    ForceCloseBlizzard()
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

--[[
  ToggleAllBags (B): BetterBackpack combined XOR. Never blocked by bag-bar toggleLockUntil.
  Native bag open + B => close native and open combined (not close-only).
]]
local function onBagKey()
  if not EnabledReplace() then
    return
  end

  BlackoutAll()

  local overlayOpen = SessionOpen()
  local nativeOpen = nativeSession or NativeContainersVisible()

  if overlayOpen then
    ClearFocusBag()
    ClearCategoryFilter()
    CloseNativeBags()
    toggleLockUntil = Now() + TOGGLE_LOCK
    OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.25 })
    return
  end

  ClearFocusBag()
  ClearCategoryFilter()
  OpenClose.ClearReplaceSuppress()
  ignoringBagShow = true
  if nativeOpen then
    CloseNativeBags()
  end
  ignoringBagShow = false
  OpenOurs()
end

local function onKeyRingToggle()
  if not EnabledReplace() then
    return
  end
  local Slots = BetterBackpack.Modules.Slots
  local key
  pcall(function()
    key = NormalizeBagID(Slots and Slots.KeyringBagIndex and Slots.KeyringBagIndex())
  end)
  local t = Now()
  if BagBarNativeEnabled() then
    BlackoutCombinedOnly()
  else
    BlackoutAll()
  end
  if not BagBarNativeEnabled() and t < toggleLockUntil then
    ParkAllShown()
    return
  end
  if not BagBarNativeEnabled() then
    toggleLockUntil = t + TOGGLE_LOCK
  end

  if not BagBarNativeEnabled() then
    if SessionOpen() then
      ClearFocusBag()
      ClearCategoryFilter()
      OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.25 })
    else
      if key ~= nil then
        SetFocusBag(key)
      end
      local Filter = BetterBackpack.Modules.Filter
      if Filter and Filter.SetCategory then
        pcall(Filter.SetCategory, "keys")
      end
      OpenOurs()
    end
    return
  end

  if OursVisible() or bagsOpen then
    OpenClose.CloseOurs({ closeBlizzard = false, suppress = 0.35 })
  end
  ClearFocusBag()
  ClearCategoryFilter()
  OpenClose.SuppressReplace(0.45)
  local orig = OrigToggle("ToggleKeyRing")
  if (nativeSession or NativeContainersVisible()) and key ~= nil and nativeFocusBag ~= nil and FocusBagsMatch(key, nativeFocusBag) then
    ignoringBagShow = true
    if orig then
      pcall(orig)
    elseif type(CloseAllBags) == "function" then
      pcall(CloseAllBags)
    end
    EndNativeSession()
    ignoringBagShow = false
    return
  end
  if key ~= nil then
    BeginNativeSession(key)
  end
  InvokeNativeKeyRing()
end

--[[
  Replace Toggle* instead of hooksecurefunc. Post-hooks run AFTER Blizzard
  Open*/Close* (and our Open*/Close* hooks), so XOR always fought the body.
]]
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
    handler(...)
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
  return nil
end

local function IsKnownBagID(bagID)
  bagID = NormalizeBagID(bagID)
  if bagID == nil then
    return false, nil
  end
  local Slots = BetterBackpack.Modules.Slots
  if Slots then
    if Slots.IsReagentBag and Slots.IsReagentBag(bagID) then
      return true, bagID
    end
    if Slots.IsKeyringBag and Slots.IsKeyringBag(bagID) then
      return true, bagID
    end
  end
  local max = 4
  pcall(function()
    if NUM_BAG_SLOTS ~= nil then
      max = NUM_BAG_SLOTS
    end
  end)
  if bagID >= 0 and bagID <= math.max(max, 4) then
    return true, bagID
  end
  if type(bagID) == "number" and bagID >= -4 and bagID <= 13 then
    return true, bagID
  end
  return false, nil
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

local function InvokeNativeToggleBag(bagID)
  bagID = NormalizeBagID(bagID)
  local orig = OrigToggle("ToggleBag")
  ignoringBagShow = true
  OpenClose._nativeOpening = true
  BlackoutCombinedOnly()
  if orig then
    pcall(orig, bagID)
  elseif type(OpenBag) == "function" and bagID ~= nil then
    pcall(OpenBag, bagID)
  elseif type(ToggleBag) == "function" and OpenClose._orig_ToggleBag then
    pcall(OpenClose._orig_ToggleBag, bagID)
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, FinishNativeOpen)
    C_Timer.After(0.05, FinishNativeOpen)
  else
    FinishNativeOpen()
  end
end

local function InvokeNativeKeyRing()
  local orig = OrigToggle("ToggleKeyRing")
  ignoringBagShow = true
  OpenClose._nativeOpening = true
  BlackoutCombinedOnly()
  if orig then
    pcall(orig)
  elseif type(ToggleKeyRing) == "function" and OpenClose._orig_ToggleKeyRing then
    pcall(OpenClose._orig_ToggleKeyRing)
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
    return
  end
  if BagBarNativeEnabled() and Now() < backpackBarArmUntil then
    onBagToggle(0, "ToggleBackpack-bar")
    return
  end
  onBagKey()
end

--[[
  Open-only (OpenAllBags / OpenBag / CombinedBags fallback): open if closed;
  if open, park Blizzard + refresh focus.
]]
local function onOpenIntent(bagID)
  if ignoringBagShow or closeBusy then
    return
  end
  if not EnabledReplace() then
    return
  end
  bagID = NormalizeBagID(bagID)

  if bagID ~= nil and BagBarNativeEnabled() then
    if OursVisible() or bagsOpen then
      OpenClose.CloseOurs({ closeBlizzard = false, suppress = 0.35 })
    end
    ClearFocusBag()
    ClearCategoryFilter()
    BeginNativeSession(bagID)
    InvokeNativeToggleBag(bagID)
    return
  end

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
    return
  end
  if OpenClose.IsReplaceSuppressed() then
    OpenClose.ClearReplaceSuppress()
  end
  local t = Now()
  if t < toggleLockUntil then
    ParkAllShown()
    return
  end
  toggleLockUntil = t + TOGGLE_LOCK
  OpenOurs()
end

-- ToggleBag + bag-bar OnClick often fire together — debounce to one XOR.
local lastBagToggleAt = 0

--[[
  Bag-bar / ToggleBag: native single ContainerFrame when bagBarNativeBag (default);
  else BetterBackpack overlay with bag focus highlight.
]]
local function onBagToggle(bagID, src)
  if ignoringBagShow or closeBusy then
    return
  end
  if not EnabledReplace() then
    return
  end

  bagID = NormalizeBagID(bagID)
  if BagBarNativeEnabled() and bagID == nil then
    return
  end
  if BagBarNativeEnabled() then
    local okId, canon = IsKnownBagID(bagID)
    if not okId then
      return
    end
    bagID = canon
  end
  LogBagPathOnce(src or "ToggleBag", bagID)

  local t = Now()
  if (t - lastBagToggleAt) < 0.08 then
    return
  end
  lastBagToggleAt = t

  if not BagBarNativeEnabled() and t < toggleLockUntil then
    BlackoutAll()
    ParkAllShown()
    return
  end
  if not BagBarNativeEnabled() then
    toggleLockUntil = t + TOGGLE_LOCK
  end

  if BagBarNativeEnabled() then
    if OursVisible() or bagsOpen then
      OpenClose.CloseOurs({ closeBlizzard = false, suppress = 0.35 })
    end
    ClearFocusBag()
    ClearCategoryFilter()
    local orig = OrigToggle("ToggleBag")
    if bagID ~= nil and (nativeSession or NativeContainersVisible()) and nativeFocusBag ~= nil and FocusBagsMatch(bagID, nativeFocusBag) then
      ignoringBagShow = true
      OpenClose._nativeOpening = true
      if orig then
        pcall(orig, bagID)
      elseif type(CloseBag) == "function" then
        pcall(CloseBag, bagID)
      end
      EndNativeSession()
      FinishNativeOpen()
      return
    end
    if bagID ~= nil then
      BeginNativeSession(bagID)
    end
    InvokeNativeToggleBag(bagID)
    return
  end

  BlackoutAll()

  if SessionOpen() then
    local focused = Layout and Layout.GetBagFocus and Layout.GetBagFocus()
    if bagID ~= nil and focused ~= nil and FocusBagsMatch(bagID, focused) then
      ClearFocusBag()
      ClearCategoryFilter()
      OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.25 })
    elseif bagID ~= nil then
      SetFocusBag(bagID)
      ClearCategoryFilter()
      ParkAllShown()
      if Layout and Layout.Raise then
        pcall(Layout.Raise)
      end
      if Layout and Layout.Relayout then
        pcall(Layout.Relayout)
      end
    else
      ClearFocusBag()
      ClearCategoryFilter()
      OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.25 })
    end
  else
    if bagID ~= nil then
      SetFocusBag(bagID)
    end
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
    -- ToggleBag replace handles open; only assist when we can resolve a bag id (no nil debounce).
    if not BagBarNativeEnabled() then
      onBagToggle(BagIdFromButton(self or btn), "bag-bar")
      return
    end
    local id = BagIdFromButton(self or btn)
    if id ~= nil then
      onBagToggle(id, "bag-bar")
    end
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

  -- Replace Toggle* (do not hooksecurefunc): post-hooks fight Open*/Close* inside the body.
  ReplaceToggle("ToggleAllBags", onBagKey)
  ReplaceToggle("ToggleBackpack", onBackpackToggle)
  ReplaceToggle("ToggleBag", function(id)
    onBagToggle(id, "ToggleBag")
  end)
  ReplaceToggle("ToggleKeyRing", onKeyRingToggle)

  if type(OpenAllBags) == "function" then
    hooksecurefunc("OpenAllBags", function()
      onOpenIntent(nil)
    end)
  end
  if type(OpenBackpack) == "function" then
    hooksecurefunc("OpenBackpack", function()
      onOpenIntent(0)
    end)
  end
  if type(OpenBag) == "function" then
    hooksecurefunc("OpenBag", function(id)
      if ignoringBagShow or OpenClose._nativeOpening or OpenClose.IsReplaceSuppressed() then
        return
      end
      LogBagPathOnce("OpenBag", id)
      if BagBarNativeEnabled() and NormalizeBagID(id) ~= nil then
        onBagToggle(id, "OpenBag-hook")
        return
      end
      onOpenIntent(id)
    end)
  end
  if type(CloseBag) == "function" then
    hooksecurefunc("CloseBag", function()
      onCloseIntent()
    end)
  end
  if type(CloseAllBags) == "function" then
    hooksecurefunc("CloseAllBags", function()
      onCloseIntent()
    end)
  end
  if type(CloseBackpack) == "function" then
    hooksecurefunc("CloseBackpack", function()
      onCloseIntent()
    end)
  end

  local function hookCombined()
    local f = ContainerFrameCombinedBags
    if not f or f.BetterBackpackHooked then
      return
    end
    f.BetterBackpackHooked = true

    if type(f.Show) == "function" then
      pcall(hooksecurefunc, f, "Show", function(self)
        if EnabledReplace() or SessionOpen() or openBusy then
          Blackout(self)
        end
      end)
    end

    pcall(function()
      f:HookScript("OnShow", function(self)
        if ignoringBagShow then
          Blackout(self)
          return
        end
        if not EnabledReplace() then
          return
        end
        Blackout(self)
        Park(self)
        if SessionOpen() or openBusy then
          PulsePark()
          return
        end
        -- Defer: ToggleBackpack body Shows CombinedBags BEFORE hooksecurefunc
        -- onBagKey. Opening here would let onBagKey XOR-close immediately (B crash).
        local function afterToggle()
          if ignoringBagShow or closeBusy or not EnabledReplace() then
            return
          end
          if SessionOpen() or openBusy then
            ParkAllShown()
            PulsePark()
            return
          end
          if not BagBarNativeEnabled() then
            onOpenIntent(nil)
          end
        end
        if C_Timer and C_Timer.After then
          C_Timer.After(0, afterToggle)
        else
          afterToggle()
        end
      end)
    end)
  end

  local function hookContainers()
    for i = 1, 13 do
      local f = _G["ContainerFrame" .. i]
      if f and not f.BetterBackpackHooked then
        f.BetterBackpackHooked = true
        pcall(function()
          f:HookScript("OnShow", function(self)
            if not EnabledReplace() then
              return
            end
            if (ignoringBagShow or OpenClose._nativeOpening) and nativeSession and not SessionOpen() then
              RestoreFrameInteractive(self)
              return
            end
            if ignoringBagShow or OpenClose._nativeOpening then
              return
            end
            if nativeSession and not SessionOpen() and not openBusy then
              RestoreFrameInteractive(self)
              return
            end
            Blackout(self)
            Park(self)
            if SessionOpen() or openBusy then
              PulsePark()
              return
            end
            local function afterToggle()
              if ignoringBagShow or closeBusy or not EnabledReplace() then
                return
              end
              if nativeSession and not SessionOpen() then
                RestoreShownNativeBags()
                return
              end
              if SessionOpen() or openBusy then
                ParkAllShown()
                PulsePark()
                return
              end
              if not BagBarNativeEnabled() then
                onOpenIntent(nil)
              end
            end
            if C_Timer and C_Timer.After then
              C_Timer.After(0, afterToggle)
            else
              afterToggle()
            end
          end)
        end)
      end
    end
  end

  local function hookKeyRingFrames()
    for _, name in ipairs({ "KeyRingFrame", "ContainerFrameKeyRing", "ContainerFrame-2" }) do
      local f = _G[name]
      if f and not f.BetterBackpackKeyRingHooked then
        f.BetterBackpackKeyRingHooked = true
        pcall(function()
          f:HookScript("OnShow", function(self)
            if not EnabledReplace() then
              return
            end
            if (ignoringBagShow or OpenClose._nativeOpening) and nativeSession then
              RestoreFrameInteractive(self)
              return
            end
            if ignoringBagShow or OpenClose._nativeOpening then
              return
            end
            if nativeSession and not SessionOpen() then
              RestoreFrameInteractive(self)
              return
            end
            if SessionOpen() or openBusy then
              Blackout(self)
              Park(self)
            end
          end)
        end)
      end
    end
  end

  hookCombined()
  hookContainers()
  hookKeyRingFrames()
  local nBag = HookBagBarButtons()
  -- Forever BagsBar: some slots fire BagSlotOnClick / ToggleBag only — already hooked.
  -- Re-run bag-bar hooks after BagsBar exists.
  pcall(function()
    if BagSlotButtonMixin and BagSlotButtonMixin.OnClick and not OpenClose._bagSlotHooked then
      OpenClose._bagSlotHooked = true
      hooksecurefunc(BagSlotButtonMixin, "OnClick", function(self)
        if not EnabledReplace() then
          return
        end
        local id = BagIdFromButton(self)
        if id ~= nil then
          onBagToggle(id, "BagSlotMixin")
        end
      end)
      nBag = (nBag or 0) + 1
    end
  end)

  local guard = CreateFrame("Frame")
  guard:SetScript("OnUpdate", function(_, elapsed)
    if not EnabledReplace() or not SessionOpen() then
      return
    end
    if openBusy or closeBusy or ignoringBagShow then
      return
    end
    guardElapsed = guardElapsed + (elapsed or 0)
    if guardElapsed < 0.2 then
      return
    end
    guardElapsed = 0
    if FrameVisible(ContainerFrameCombinedBags) then
      ParkAllShown()
    else
      for i = 1, 13 do
        if FrameVisible(_G["ContainerFrame" .. i]) then
          ParkAllShown()
          break
        end
      end
    end
  end)

  hooksInstalled = true
  LogHooksOnce(string.format("Toggle* replaced · Open/Close hooks · bagBtns=%d", nBag or 0))

  if C_Timer and C_Timer.After then
    C_Timer.After(1, function()
      hookCombined()
      hookContainers()
      hookKeyRingFrames()
      HookBagBarButtons()
    end)
    C_Timer.After(3, function()
      hookCombined()
      hookContainers()
      hookKeyRingFrames()
      HookBagBarButtons()
    end)
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
  return string.format(
    "open overlay=%s session=%s layout=%s · native sess=%s focus=%s ui=%s · lock=%.2fs suppress=%.2fs · busy o/c=%s/%s · bagBarNative=%s",
    tostring(bagsOpen),
    tostring(SessionOpen()),
    tostring(OursVisible()),
    tostring(nativeSession),
    tostring(nativeFocusBag),
    tostring(NativeContainersVisible()),
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
