--[[
  BetterBackpack.OpenClose — B key ownership (0.1.4)

  One B close: session XOR only — NO InOpenGrace on Toggle close path.
  CombinedBags OnShow: park only — NEVER OpenOurs (opens fight Toggle close).
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
local TOGGLE_LOCK = 0.22
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
  BlackoutAll()
  ParkAllShown()

  local ok, shown = pcall(function()
    return Layout.Show and Layout.Show()
  end)
  if not ok or not shown or not OursVisible() then
    bagsOpen = false
    openBusy = false
    ForceCloseBlizzard()
    if BetterBackpack.RecordError then
      BetterBackpack.RecordError("OpenOurs", tostring(shown))
    end
    return false
  end

  bagsOpen = true
  toggleLockUntil = Now() + TOGGLE_LOCK
  openBusy = false
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
  Sole B owner. Session XOR — close always closes (no open-grace on Toggle).
]]
local function onBagKey()
  if not EnabledReplace() then
    return
  end

  local t = Now()
  BlackoutAll()

  -- Debounce ToggleAllBags + ToggleBackpack on the same keypress only.
  if t < toggleLockUntil then
    ParkAllShown()
    return
  end
  toggleLockUntil = t + TOGGLE_LOCK

  if SessionOpen() then
    -- One B close — never PulsePark-as-close.
    OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.25 })
  else
    OpenOurs()
  end
end

function OpenClose.InstallHooks()
  if hooksInstalled then
    return
  end
  hooksInstalled = true

  if type(ToggleAllBags) == "function" then
    hooksecurefunc("ToggleAllBags", onBagKey)
  end
  if type(ToggleBackpack) == "function" then
    hooksecurefunc("ToggleBackpack", onBagKey)
  end

  if type(OpenAllBags) == "function" then
    hooksecurefunc("OpenAllBags", function()
      if ignoringBagShow or closeBusy then
        return
      end
      if not EnabledReplace() then
        return
      end
      BlackoutAll()
      if SessionOpen() or openBusy then
        ParkAllShown()
      end
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

    f:HookScript("OnShow", function(self)
      if ignoringBagShow then
        Blackout(self)
        return
      end
      if not EnabledReplace() then
        return
      end
      -- Park only — NEVER OpenOurs (OnShow open + Toggle close = 2× B / empty UI).
      Blackout(self)
      Park(self)
      if SessionOpen() or openBusy then
        PulsePark()
      end
    end)
  end

  local function hookContainers()
    for i = 1, 13 do
      local f = _G["ContainerFrame" .. i]
      if f and not f.BetterBackpackHooked then
        f.BetterBackpackHooked = true
        f:HookScript("OnShow", function(self)
          if ignoringBagShow or not EnabledReplace() then
            return
          end
          if SessionOpen() or openBusy then
            Park(self)
          elseif EnabledReplace() then
            Blackout(self)
            Park(self)
          end
        end)
      end
    end
  end

  hookCombined()
  hookContainers()

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

  if C_Timer and C_Timer.After then
    C_Timer.After(1, function()
      hookCombined()
      hookContainers()
    end)
    C_Timer.After(3, function()
      hookCombined()
      hookContainers()
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

OpenClose.ForceCloseBlizzard = ForceCloseBlizzard
OpenClose.ParkAllShown = ParkAllShown
OpenClose.BlackoutAll = BlackoutAll
