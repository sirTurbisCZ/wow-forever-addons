--[[
  BetterBackpack.OpenClose — B intercept, CombinedBags park (never Hide while ours open).

  0.1.1 close fix: one B must close ours + Blizzard state.
  Bug: CombinedBags Hidden while ours open → ToggleAllBags calls OpenAllBags first;
  OpenAllBags hook extended toggleLock → onToggle PulseHide-only → needs 2× B.
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local OpenClose = {}
BetterBackpack.Modules.OpenClose = OpenClose

local Config = BetterBackpack.Config
local Layout = BetterBackpack.Modules.Layout

local hooksInstalled = false
local suppressReplaceUntil = 0
local hidingBlizzard = false
local bagsOpen = false
local toggleLockUntil = 0
local openedAt = 0
local pulseToken = 0
local OPEN_GRACE = 0.6
local TOGGLE_LOCK = 0.45
local guardElapsed = 0
local openBusy = false
local closeBusy = false
local healBusyUntil = 0
local savedPoints = {} -- frame → {point, relativeTo, relativePoint, x, y} or false

local function Now()
  if GetTime then
    return GetTime()
  end
  return 0
end

local function Profile()
  return Config.GetProfile()
end

local function Enabled()
  local p = Profile()
  return p.enabled and not p.safeMode
end

function OpenClose.SuppressReplace(seconds)
  if not seconds or seconds <= 0 then
    suppressReplaceUntil = 0
    return
  end
  suppressReplaceUntil = Now() + seconds
end

function OpenClose.IsReplaceSuppressed()
  return Now() < suppressReplaceUntil
end

function OpenClose.ClearReplaceSuppress()
  suppressReplaceUntil = 0
end

local function CanReplace()
  if OpenClose.IsReplaceSuppressed() then
    return false
  end
  if not Enabled() or not Profile().replaceBlizzard then
    return false
  end
  return true
end

local function OursVisible()
  return Layout and Layout.IsShown and Layout.IsShown()
end

local function SessionOpen()
  return bagsOpen or OursVisible()
end

local function InOpenGrace()
  local t = Now()
  if openedAt > 0 and (t - openedAt) < OPEN_GRACE then
    return true
  end
  return false
end

local function RememberPoint(f)
  if not f or savedPoints[f] ~= nil then
    return
  end
  local ok, point, relativeTo, relativePoint, x, y = pcall(function()
    return f:GetPoint(1)
  end)
  if ok and point then
    savedPoints[f] = {
      point = point,
      relativeTo = relativeTo,
      relativePoint = relativePoint,
      x = x,
      y = y,
    }
  else
    savedPoints[f] = false
  end
end

local function RestorePoint(f)
  local saved = savedPoints[f]
  savedPoints[f] = nil
  if not f or saved == nil then
    return
  end
  if saved == false then
    return
  end
  pcall(function()
    f:ClearAllPoints()
    f:SetPoint(saved.point, saved.relativeTo or UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
  end)
end

local function StashFrame(f)
  if not f then
    return
  end
  RememberPoint(f)
  if InCombatLockdown and InCombatLockdown() then
    pcall(function()
      f:SetAlpha(0)
      f:EnableMouse(false)
    end)
    return
  end
  pcall(function()
    f:SetAlpha(0)
    f:EnableMouse(false)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -8000, 8000)
  end)
end

--[[
  While we own the session, CombinedBags must stay IsShown (parked).
  If it is Hidden, next B runs OpenAllBags instead of CloseAllBags → 2× B close.
]]
local function EnsureCombinedBagsShownParked()
  local f = ContainerFrameCombinedBags
  if not f then
    return
  end
  local shown = false
  pcall(function()
    shown = f:IsShown() and true or false
  end)
  if not shown then
    BetterBackpack._bbIgnoreBagShow = true
    hidingBlizzard = true
    pcall(function()
      f:Show()
    end)
    hidingBlizzard = false
    BetterBackpack._bbIgnoreBagShow = false
  end
  StashFrame(f)
  for i = 1, 13 do
    local cf = _G["ContainerFrame" .. i]
    if cf then
      local cfShown = false
      pcall(function()
        cfShown = cf:IsShown() and true or false
      end)
      if cfShown then
        StashFrame(cf)
      end
    end
  end
end

local function HideBlizzardBags()
  hidingBlizzard = true
  EnsureCombinedBagsShownParked()
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      hidingBlizzard = false
    end)
  else
    hidingBlizzard = false
  end
end

local function FrameVisiblyOnScreen(f)
  if not f or not f.IsShown or not f:IsShown() then
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

local function AnyBlizzardBagVisible()
  if FrameVisiblyOnScreen(ContainerFrameCombinedBags) then
    return true
  end
  for i = 1, 13 do
    if FrameVisiblyOnScreen(_G["ContainerFrame" .. i]) then
      return true
    end
  end
  return false
end

local function AssertBlizzardStashed()
  if not SessionOpen() then
    return
  end
  EnsureCombinedBagsShownParked()
  if Layout and Layout.Raise then
    pcall(Layout.Raise)
  end
end

local OpenOurs

local function HealGhostBlizzardBags()
  if openBusy or closeBusy or BetterBackpack._bbIgnoreBagShow then
    return
  end
  if not Enabled() or not Profile().replaceBlizzard then
    return
  end
  if OpenClose.IsReplaceSuppressed() then
    return
  end
  if SessionOpen() then
    AssertBlizzardStashed()
    return
  end
  if not AnyBlizzardBagVisible() then
    return
  end
  local t = Now()
  if t < healBusyUntil then
    return
  end
  healBusyUntil = t + 1.0
  OpenOurs()
end

local function PulseHideBlizzard()
  pulseToken = pulseToken + 1
  local token = pulseToken
  local delays = { 0, 0.05, 0.1, 0.2, 0.35, 0.5, 0.75, 1.0 }
  for i = 1, #delays do
    local d = delays[i]
    local function tick()
      if token ~= pulseToken then
        return
      end
      if SessionOpen() then
        AssertBlizzardStashed()
      end
    end
    if d == 0 then
      tick()
    elseif C_Timer and C_Timer.After then
      C_Timer.After(d, tick)
    end
  end
end

local function RestoreBlizzardBags()
  pulseToken = pulseToken + 1
  pcall(function()
    local f = ContainerFrameCombinedBags
    if f then
      RestorePoint(f)
      f:SetAlpha(1)
      f:EnableMouse(true)
      if type(f.Update) == "function" then
        f:Update()
      end
    end
  end)
  for i = 1, 13 do
    local f = _G["ContainerFrame" .. i]
    if f then
      pcall(function()
        RestorePoint(f)
        f:SetAlpha(1)
        f:EnableMouse(true)
      end)
    end
  end
end

OpenOurs = function()
  if openBusy or closeBusy then
    return bagsOpen or OursVisible()
  end
  if not CanReplace() then
    return false
  end
  openBusy = true
  local okCall, okShow = pcall(function()
    return Layout.Show and Layout.Show()
  end)
  local ok = okCall and okShow
  if not ok or not OursVisible() then
    bagsOpen = false
    openBusy = false
    RestoreBlizzardBags()
    return false
  end
  bagsOpen = true
  openedAt = Now()
  -- Lock only for same-press ToggleAllBags+ToggleBackpack / OnShow races — not for later close.
  toggleLockUntil = math.max(toggleLockUntil, openedAt + TOGGLE_LOCK)
  openBusy = false
  -- Keep CombinedBags IsShown+parked so next B takes CloseAllBags path (one press close).
  PulseHideBlizzard()
  AssertBlizzardStashed()
  return true
end

function OpenClose.CloseOurs(opts)
  opts = opts or {}
  if closeBusy then
    return
  end
  closeBusy = true
  bagsOpen = false
  openedAt = 0
  pulseToken = pulseToken + 1
  OpenClose.SuppressReplace(opts.suppress or 0.35)
  if Layout and Layout.Hide then
    -- Avoid NotifyHidden re-entry treating Esc mid-close as a second close.
    BetterBackpack._bbClosing = true
    Layout.Hide()
    BetterBackpack._bbClosing = false
  end
  RestoreBlizzardBags()
  if opts.closeBlizzard ~= false and type(CloseAllBags) == "function" then
    hidingBlizzard = true
    BetterBackpack._bbIgnoreBagShow = true
    pcall(CloseAllBags)
    BetterBackpack._bbIgnoreBagShow = false
    hidingBlizzard = false
  end
  -- Ensure CombinedBags ends Hidden so next B opens cleanly (not 2×).
  pcall(function()
    local f = ContainerFrameCombinedBags
    if f and f:IsShown() and type(f.Hide) == "function" then
      -- CloseAllBags should have hidden; if still shown, leave alpha restored for Blizzard.
      -- Do not force :Hide() here if CloseAllBags already did — UpdateNewItemList risk only if we Hide mid-update.
    end
  end)
  closeBusy = false
end

function OpenClose.NotifyHidden()
  if BetterBackpack._bbClosing then
    return
  end
  -- Esc / UISpecialFrames: full release so CombinedBags is not left Shown+parked (would need 2× B).
  if bagsOpen or OursVisible() then
    OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.35 })
    return
  end
  bagsOpen = false
  openedAt = 0
  pulseToken = pulseToken + 1
end

function OpenClose.ShutdownToBlizzard(opts)
  opts = opts or {}
  bagsOpen = false
  openedAt = 0
  pulseToken = pulseToken + 1
  OpenClose.SuppressReplace(2.0)
  if Layout and Layout.Hide then
    BetterBackpack._bbClosing = true
    Layout.Hide()
    BetterBackpack._bbClosing = false
  end
  RestoreBlizzardBags()
end

function OpenClose.BagsOpen()
  return bagsOpen
end

function OpenClose.SessionOpen()
  return SessionOpen()
end

function OpenClose.Toggle()
  if SessionOpen() then
    OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.35 })
  else
    OpenOurs()
  end
end

function OpenClose.InstallHooks()
  if hooksInstalled then
    return
  end
  hooksInstalled = true

  local guard = CreateFrame("Frame")
  guard:SetScript("OnUpdate", function(_, elapsed)
    if not (Enabled() and Profile().replaceBlizzard) then
      guardElapsed = 0
      return
    end
    if openBusy or closeBusy or BetterBackpack._bbIgnoreBagShow then
      return
    end
    guardElapsed = guardElapsed + (elapsed or 0)
    if guardElapsed < 0.25 then
      return
    end
    guardElapsed = 0
    if SessionOpen() then
      AssertBlizzardStashed()
    else
      HealGhostBlizzardBags()
    end
  end)

  local function onToggle()
    local t = Now()
    local ours = SessionOpen()

    -- Same press as open (OnShow/OpenAllBags → Toggle*): keep open, restash.
    if ours and InOpenGrace() then
      toggleLockUntil = math.max(toggleLockUntil, t + TOGGLE_LOCK)
      PulseHideBlizzard()
      return
    end

    -- Debounce ToggleAllBags + ToggleBackpack on one keypress.
    if t < toggleLockUntil then
      if ours then
        PulseHideBlizzard()
      end
      return
    end

    if not CanReplace() then
      if OpenClose.IsReplaceSuppressed() and Enabled() and Profile().replaceBlizzard then
        OpenClose.ClearReplaceSuppress()
        bagsOpen = false
        toggleLockUntil = t + TOGGLE_LOCK
        OpenOurs()
      end
      return
    end

    toggleLockUntil = t + TOGGLE_LOCK
    if ours then
      -- One B close: own UI + CloseAllBags so CombinedBags is not left Shown+parked.
      OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.35 })
    else
      bagsOpen = false
      OpenOurs()
    end
  end

  if type(ToggleAllBags) == "function" then
    hooksecurefunc("ToggleAllBags", onToggle)
  end
  if type(ToggleBackpack) == "function" then
    hooksecurefunc("ToggleBackpack", onToggle)
  end

  -- OpenAllBags: take over only when we are closed.
  -- CRITICAL: if already open, restash only — do NOT extend toggleLockUntil
  -- (that blocked onToggle CloseOurs when CombinedBags was Hidden → 2× B).
  if type(OpenAllBags) == "function" then
    hooksecurefunc("OpenAllBags", function()
      if openBusy or closeBusy or BetterBackpack._bbIgnoreBagShow then
        return
      end
      if not Enabled() or not Profile().replaceBlizzard then
        return
      end
      if OpenClose.IsReplaceSuppressed() then
        return
      end
      if SessionOpen() then
        PulseHideBlizzard()
        return
      end
      local t = Now()
      openedAt = t
      toggleLockUntil = math.max(toggleLockUntil, t + TOGGLE_LOCK)
      OpenOurs()
    end)
  end

  if type(CloseAllBags) == "function" then
    hooksecurefunc("CloseAllBags", function()
      if hidingBlizzard or closeBusy or BetterBackpack._bbClosing then
        return
      end
      if OpenClose.IsReplaceSuppressed() then
        return
      end
      -- Blizzard closed CombinedBags while we still show ours (e.g. first half of a bad toggle).
      -- Keep ours up and re-Show+park CombinedBags so a *single* following onToggle can close,
      -- OR if onToggle already ran CloseOurs, bagsOpen is false and we no-op.
      if SessionOpen() and not InOpenGrace() then
        -- Re-park so Blizzard IsShown stays true until our CloseOurs runs in onToggle.
        -- If ToggleAllBags order is CloseAllBags then onToggle, onToggle will CloseOurs next.
        -- Lua 5.1: expression statements must be calls/assignments — not `a and b and f()`.
        if C_Timer and C_Timer.After then
          C_Timer.After(0, function()
            if SessionOpen() and not closeBusy then
              AssertBlizzardStashed()
            end
          end)
        end
      end
    end)
  end

  local function hookCombinedOnShow()
    local f = ContainerFrameCombinedBags
    if not f or f.BetterBackpackHooked then
      return
    end
    f.BetterBackpackHooked = true
    f:HookScript("OnShow", function(self)
      if BetterBackpack._bbIgnoreBagShow or openBusy or closeBusy then
        if SessionOpen() then
          StashFrame(self)
        end
        return
      end
      if OpenClose.IsReplaceSuppressed() then
        return
      end
      if SessionOpen() or InOpenGrace() then
        StashFrame(self)
        PulseHideBlizzard()
        return
      end
      if CanReplace() then
        OpenOurs()
      end
    end)
  end

  local function hookContainerFrames()
    for i = 1, 13 do
      local f = _G["ContainerFrame" .. i]
      if f and not f.BetterBackpackHooked then
        f.BetterBackpackHooked = true
        f:HookScript("OnShow", function(self)
          if BetterBackpack._bbIgnoreBagShow or openBusy or closeBusy then
            return
          end
          if SessionOpen() or InOpenGrace() then
            StashFrame(self)
          end
        end)
      end
    end
  end

  hookCombinedOnShow()
  hookContainerFrames()
  if C_Timer and C_Timer.After then
    C_Timer.After(1, function()
      hookCombinedOnShow()
      hookContainerFrames()
    end)
    C_Timer.After(3, function()
      hookCombinedOnShow()
      hookContainerFrames()
    end)
  end
end

--[[
  Self-check open/close wiring (no hardware B). Proves CombinedBags stays Shown while ours open.
]]
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
    ok(true, "combat — skip open/close mutate checks")
    return fail == 0, pass, fail, notes
  end

  local wasOpen = SessionOpen()
  if wasOpen then
    OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.05 })
  end

  local opened = OpenOurs()
  ok(opened == true, "OpenOurs returned false")
  ok(SessionOpen(), "session not open after OpenOurs")
  ok(OursVisible(), "Layout not shown after OpenOurs")

  local cb = ContainerFrameCombinedBags
  local cbShown = cb and cb:IsShown()
  ok(cbShown == true, "CombinedBags not IsShown while ours open (causes 2× B close)")
  ok(not FrameVisiblyOnScreen(cb), "CombinedBags still visible on screen while ours open")

  OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.05 })
  ok(not SessionOpen(), "session still open after CloseOurs")
  ok(not OursVisible(), "Layout still shown after CloseOurs")

  -- Clear short suppress for playability
  OpenClose.ClearReplaceSuppress()

  return fail == 0, pass, fail, notes
end

OpenClose.HideBlizzardBags = HideBlizzardBags
OpenClose.RestoreBlizzardBags = RestoreBlizzardBags
OpenClose.OpenOurs = OpenOurs
OpenClose.FrameVisiblyOnScreen = FrameVisiblyOnScreen
