--[[
  BetterBackpack.OpenClose — B intercept, CombinedBags park (never Hide), watchdog.
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
local TOGGLE_LOCK = 0.6
local guardElapsed = 0
local openBusy = false
local healBusyUntil = 0

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

local function InOpenGrace()
  local t = Now()
  if openedAt > 0 and (t - openedAt) < OPEN_GRACE then
    return true
  end
  return false
end

local function StashFrame(f)
  if not f then
    return
  end
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

local function HideBlizzardBags()
  hidingBlizzard = true
  StashFrame(ContainerFrameCombinedBags)
  for i = 1, 13 do
    StashFrame(_G["ContainerFrame" .. i])
  end
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
  if not bagsOpen and not OursVisible() then
    return
  end
  HideBlizzardBags()
  if Layout and Layout.Raise then
    pcall(Layout.Raise)
  end
end

local OpenOurs

local function HealGhostBlizzardBags()
  if openBusy or BetterBackpack._bbIgnoreBagShow then
    return
  end
  if not Enabled() or not Profile().replaceBlizzard then
    return
  end
  if OpenClose.IsReplaceSuppressed() then
    return
  end
  if OursVisible() or bagsOpen then
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
      if bagsOpen or OursVisible() then
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
        f:SetAlpha(1)
        f:EnableMouse(true)
      end)
    end
  end
end

OpenOurs = function()
  if openBusy then
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
  toggleLockUntil = math.max(toggleLockUntil, openedAt + TOGGLE_LOCK)
  openBusy = false
  PulseHideBlizzard()
  AssertBlizzardStashed()
  return true
end

function OpenClose.CloseOurs(opts)
  opts = opts or {}
  bagsOpen = false
  openedAt = 0
  pulseToken = pulseToken + 1
  OpenClose.SuppressReplace(opts.suppress or 0.35)
  if Layout and Layout.Hide then
    Layout.Hide()
  end
  RestoreBlizzardBags()
  if opts.closeBlizzard ~= false and type(CloseAllBags) == "function" then
    hidingBlizzard = true
    pcall(CloseAllBags)
    hidingBlizzard = false
  end
end

function OpenClose.NotifyHidden()
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
    Layout.Hide()
  end
  RestoreBlizzardBags()
end

function OpenClose.BagsOpen()
  return bagsOpen
end

function OpenClose.Toggle()
  if OursVisible() or bagsOpen then
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
    if openBusy or BetterBackpack._bbIgnoreBagShow then
      return
    end
    guardElapsed = guardElapsed + (elapsed or 0)
    if guardElapsed < 0.25 then
      return
    end
    guardElapsed = 0
    if bagsOpen or OursVisible() then
      AssertBlizzardStashed()
    else
      HealGhostBlizzardBags()
    end
  end)

  local function onToggle()
    local t = Now()
    if t < toggleLockUntil then
      if OursVisible() or bagsOpen then
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

    if OursVisible() or bagsOpen then
      if InOpenGrace() then
        toggleLockUntil = t + TOGGLE_LOCK
        PulseHideBlizzard()
        return
      end
      toggleLockUntil = t + TOGGLE_LOCK
      OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.35 })
    else
      bagsOpen = false
      toggleLockUntil = t + TOGGLE_LOCK
      OpenOurs()
    end
  end

  if type(ToggleAllBags) == "function" then
    hooksecurefunc("ToggleAllBags", onToggle)
  end
  if type(ToggleBackpack) == "function" then
    hooksecurefunc("ToggleBackpack", onToggle)
  end

  if type(OpenAllBags) == "function" then
    hooksecurefunc("OpenAllBags", function()
      if openBusy or BetterBackpack._bbIgnoreBagShow then
        return
      end
      if not Enabled() or not Profile().replaceBlizzard then
        return
      end
      if OpenClose.IsReplaceSuppressed() then
        return
      end
      local t = Now()
      toggleLockUntil = math.max(toggleLockUntil, t + TOGGLE_LOCK)
      if OursVisible() or bagsOpen then
        PulseHideBlizzard()
      else
        openedAt = t
        OpenOurs()
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
      if BetterBackpack._bbIgnoreBagShow or openBusy then
        if bagsOpen or OursVisible() then
          StashFrame(self)
        end
        return
      end
      if OpenClose.IsReplaceSuppressed() then
        return
      end
      if OursVisible() or bagsOpen or InOpenGrace() then
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
          if BetterBackpack._bbIgnoreBagShow or openBusy then
            return
          end
          if bagsOpen or OursVisible() or InOpenGrace() then
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

OpenClose.HideBlizzardBags = HideBlizzardBags
OpenClose.RestoreBlizzardBags = RestoreBlizzardBags
OpenClose.OpenOurs = OpenOurs
