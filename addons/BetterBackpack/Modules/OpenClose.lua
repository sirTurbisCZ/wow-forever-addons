--[[
  BetterBackpack.OpenClose — B intercept, CombinedBags park (never Hide while ours open).

  0.1.2: never flash Blizzard bags — blackout alpha=0 on Show/toggle BEFORE paint;
  CloseOurs must NOT RestoreBlizzardBags (alpha 1) before CloseAllBags.
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
local OPEN_GRACE = 0.55
local TOGGLE_LOCK = 0.4
local guardElapsed = 0
local openBusy = false
local closeBusy = false
local healBusyUntil = 0
local savedPoints = {}

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
  return openedAt > 0 and (t - openedAt) < OPEN_GRACE
end

local function ShouldParkBlizzard()
  if BetterBackpack._bbIgnoreBagShow then
    return SessionOpen()
  end
  if not Enabled() or not Profile().replaceBlizzard then
    return false
  end
  if OpenClose.IsReplaceSuppressed() and not SessionOpen() then
    return false
  end
  return true
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
  if not f or not saved or saved == false then
    return
  end
  pcall(function()
    f:ClearAllPoints()
    f:SetPoint(saved.point, saved.relativeTo or UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
  end)
end

local function ClearSavedPoints()
  for k in pairs(savedPoints) do
    savedPoints[k] = nil
  end
end

--[[ Instant anti-flash: alpha 0 before any layout paint. Safe in combat. ]]
local function BlackoutFrame(f)
  if not f then
    return
  end
  pcall(function()
    f:SetAlpha(0)
    f:EnableMouse(false)
  end)
end

local function BlackoutAllBlizzard()
  BlackoutFrame(ContainerFrameCombinedBags)
  for i = 1, 13 do
    BlackoutFrame(_G["ContainerFrame" .. i])
  end
end

local function ParkFrame(f)
  if not f then
    return
  end
  BlackoutFrame(f)
  RememberPoint(f)
  if InCombatLockdown and InCombatLockdown() then
    return
  end
  pcall(function()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -8000, 8000)
  end)
end

--[[
  While we own the session, CombinedBags stays IsShown (parked).
  Always blackout first so Show never paints a visible frame.
]]
local function EnsureCombinedBagsShownParked()
  local f = ContainerFrameCombinedBags
  if not f then
    return
  end
  BlackoutFrame(f)
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
    BlackoutFrame(f)
  end
  ParkFrame(f)
  for i = 1, 13 do
    local cf = _G["ContainerFrame" .. i]
    if cf then
      local cfShown = false
      pcall(function()
        cfShown = cf:IsShown() and true or false
      end)
      if cfShown then
        ParkFrame(cf)
      else
        BlackoutFrame(cf)
      end
    end
  end
end

local function HideBlizzardBags()
  hidingBlizzard = true
  BlackoutAllBlizzard()
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
  BlackoutAllBlizzard()
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
  local delays = { 0, 0.05, 0.1, 0.2, 0.35, 0.5 }
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

--[[ Only for /bb off / safe — never call on normal CloseOurs (causes CombinedBags flash). ]]
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
  BlackoutAllBlizzard()
  local okCall, okShow = pcall(function()
    return Layout.Show and Layout.Show()
  end)
  local ok = okCall and okShow
  if not ok or not OursVisible() then
    bagsOpen = false
    openBusy = false
    -- Fail soft: close Blizzard while still blacked out — never alpha=1 flash.
    BlackoutAllBlizzard()
    if type(CloseAllBags) == "function" then
      hidingBlizzard = true
      BetterBackpack._bbIgnoreBagShow = true
      pcall(CloseAllBags)
      BetterBackpack._bbIgnoreBagShow = false
      hidingBlizzard = false
    end
    ClearSavedPoints()
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
  if closeBusy then
    return
  end
  closeBusy = true
  bagsOpen = false
  openedAt = 0
  pulseToken = pulseToken + 1
  OpenClose.SuppressReplace(opts.suppress or 0.35)

  -- Stay blacked out through the whole close — never RestoreBlizzardBags here.
  BlackoutAllBlizzard()

  if Layout and Layout.Hide then
    BetterBackpack._bbClosing = true
    Layout.Hide()
    BetterBackpack._bbClosing = false
  end

  if opts.closeBlizzard ~= false and type(CloseAllBags) == "function" then
    hidingBlizzard = true
    BetterBackpack._bbIgnoreBagShow = true
    pcall(CloseAllBags)
    BetterBackpack._bbIgnoreBagShow = false
    hidingBlizzard = false
  end

  -- Drop park anchors so next Blizzard open is clean; keep alpha 0 until real open.
  ClearSavedPoints()
  BlackoutAllBlizzard()
  closeBusy = false
end

function OpenClose.NotifyHidden()
  if BetterBackpack._bbClosing then
    return
  end
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
    if guardElapsed < 0.2 then
      return
    end
    guardElapsed = 0
    if SessionOpen() then
      AssertBlizzardStashed()
    else
      -- Closed: if CombinedBags peeks visible, blackout+heal into ours (replace on).
      if AnyBlizzardBagVisible() then
        BlackoutAllBlizzard()
        HealGhostBlizzardBags()
      end
    end
  end)

  local function onToggle()
    local t = Now()
    -- Blackout first on every B so Blizzard never paints a visible frame this press.
    if ShouldParkBlizzard() or SessionOpen() then
      BlackoutAllBlizzard()
    end

    local ours = SessionOpen()

    if ours and InOpenGrace() then
      toggleLockUntil = math.max(toggleLockUntil, t + TOGGLE_LOCK)
      PulseHideBlizzard()
      return
    end

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

  if type(OpenAllBags) == "function" then
    hooksecurefunc("OpenAllBags", function()
      if openBusy or closeBusy or BetterBackpack._bbIgnoreBagShow then
        BlackoutAllBlizzard()
        return
      end
      if not Enabled() or not Profile().replaceBlizzard then
        return
      end
      BlackoutAllBlizzard()
      if OpenClose.IsReplaceSuppressed() then
        return
      end
      if SessionOpen() then
        -- Already open: restash only — do NOT extend toggleLock (blocks one-B close).
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
      -- Do NOT re-Show CombinedBags here — that flashes and fights one-B close.
      -- onToggle (same press) will CloseOurs when SessionOpen.
      if SessionOpen() then
        BlackoutAllBlizzard()
      end
    end)
  end

  local function hookCombinedOnShow()
    local f = ContainerFrameCombinedBags
    if not f or f.BetterBackpackHooked then
      return
    end
    f.BetterBackpackHooked = true

    -- Show() hook: blackout before OnShow scripts paint (anti-flash).
    if type(f.Show) == "function" then
      pcall(hooksecurefunc, f, "Show", function(self)
        if ShouldParkBlizzard() or SessionOpen() or openBusy then
          BlackoutFrame(self)
        end
      end)
    end

    f:HookScript("OnShow", function(self)
      -- First line: never let CombinedBags paint opaque while we replace.
      if ShouldParkBlizzard() or SessionOpen() or openBusy or closeBusy then
        BlackoutFrame(self)
      end
      if BetterBackpack._bbIgnoreBagShow or openBusy or closeBusy then
        if SessionOpen() then
          ParkFrame(self)
        end
        return
      end
      if OpenClose.IsReplaceSuppressed() then
        return
      end
      if SessionOpen() or InOpenGrace() then
        ParkFrame(self)
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
        if type(f.Show) == "function" then
          pcall(hooksecurefunc, f, "Show", function(self)
            if ShouldParkBlizzard() or SessionOpen() or openBusy then
              BlackoutFrame(self)
            end
          end)
        end
        f:HookScript("OnShow", function(self)
          if ShouldParkBlizzard() or SessionOpen() or openBusy then
            BlackoutFrame(self)
          end
          if BetterBackpack._bbIgnoreBagShow or openBusy or closeBusy then
            return
          end
          if SessionOpen() or InOpenGrace() then
            ParkFrame(self)
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

  if SessionOpen() then
    OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.05 })
  end

  local opened = OpenOurs()
  ok(opened == true, "OpenOurs returned false")
  ok(SessionOpen(), "session not open after OpenOurs")
  ok(OursVisible(), "Layout not shown after OpenOurs")

  local cb = ContainerFrameCombinedBags
  ok(cb and cb:IsShown(), "CombinedBags not IsShown while ours open")
  ok(not FrameVisiblyOnScreen(cb), "CombinedBags still visible on screen while ours open")
  local a = 1
  pcall(function()
    a = cb:GetAlpha() or 1
  end)
  ok(a < 0.05, "CombinedBags alpha not ~0 while ours open")

  OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.05 })
  ok(not SessionOpen(), "session still open after CloseOurs")
  ok(not OursVisible(), "Layout still shown after CloseOurs")
  ok(not (cb and cb:IsShown() and FrameVisiblyOnScreen(cb)), "CombinedBags visible after close")

  OpenClose.ClearReplaceSuppress()
  return fail == 0, pass, fail, notes
end

OpenClose.HideBlizzardBags = HideBlizzardBags
OpenClose.RestoreBlizzardBags = RestoreBlizzardBags
OpenClose.OpenOurs = OpenOurs
OpenClose.FrameVisiblyOnScreen = FrameVisiblyOnScreen
OpenClose.BlackoutAllBlizzard = BlackoutAllBlizzard
