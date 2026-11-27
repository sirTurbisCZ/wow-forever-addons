--[[
  Wayfarer — one addon, one minimap button, one settings window.
  /wayfarer or /wf: help|marks|minimap|status|reset
]]

local addonName = ...

Wayfarer = Wayfarer or {}
Wayfarer.Modules = Wayfarer.Modules or {}

local L = Wayfarer.L or {}
local Config = Wayfarer.Config

local function Print(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring(select(i, ...))
  end
  print((L.PREFIX or "[Wayfarer]") .. " " .. table.concat(parts, " "))
end
Wayfarer.Print = Print

--- Error boundary: report to ForeverErrorLog when it is installed, never throw into the game.
function Wayfarer.RecordError(context, err)
  if ForeverErrorLog and ForeverErrorLog.Record then
    pcall(ForeverErrorLog.Record, "Wayfarer:" .. tostring(context) .. " " .. tostring(err), "")
  end
end

local function SafeCall(context, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    Wayfarer.RecordError(context, err)
  end
  return ok
end

local booted = false
local function Boot()
  if booted then
    return
  end
  booted = true
  Config.EnsureDB()
  local M = Wayfarer.Modules
  if M.Minimap then
    SafeCall("minimap", M.Minimap.Create)
  end
  if M.PartyMarks then
    SafeCall("partymarks", M.PartyMarks.Start)
  end
  if M.ProcHUD and M.ProcHUD.Start then
    SafeCall("prochud", M.ProcHUD.Start)
  end
  if M.EasyFish and M.EasyFish.Start then
    SafeCall("easyfish", M.EasyFish.Start)
  end
  Print(string.format(L.LOADED or "loaded v%s", tostring(Config.VERSION)))
end

local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == addonName then
    Config.EnsureDB()
  elseif event == "PLAYER_LOGIN" then
    SafeCall("boot", Boot)
  end
end)

SLASH_WAYFARER1 = "/wayfarer"
SLASH_WAYFARER2 = "/wf"
SlashCmdList.WAYFARER = function(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$") or ""
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = (cmd or ""):lower()
  rest = (rest or ""):lower()
  local M = Wayfarer.Modules
  local p = Config.GetProfile()

  if cmd == "" then
    if Wayfarer.Settings then
      Wayfarer.Settings.Toggle()
    end
    return
  end
  if cmd == "help" or cmd == "?" then
    for _, line in ipairs(L.HELP_LINES or {}) do
      Print(line)
    end
    return
  end
  if cmd == "marks" then
    if rest == "on" or rest == "off" then
      p.partyMarks.enabled = rest == "on"
      if M.PartyMarks then
        M.PartyMarks.Apply()
      end
      Print(p.partyMarks.enabled and L.MARKS_ON or L.MARKS_OFF)
      if Wayfarer.Settings then
        Wayfarer.Settings.Refresh()
      end
    else
      Print("usage: /wf marks on|off")
    end
    return
  end
  if cmd == "minimap" then
    if rest == "reset" then
      M.Minimap.Reset()
      Print(L.MINIMAP_RESET)
    elseif rest == "on" or rest == "off" then
      M.Minimap.SetShown(rest == "on")
      Print(rest == "on" and L.MINIMAP_SHOWN or L.MINIMAP_HIDDEN)
    else
      Print("usage: /wf minimap on|off|reset")
    end
    return
  end
  -- Module slash commands: Mod.Slash(rest) prints its own output.
  local slashMods = { proc = "ProcHUD", procs = "ProcHUD", fish = "EasyFish" }
  if slashMods[cmd] then
    local mod = M[slashMods[cmd]]
    if mod and mod.Slash then
      SafeCall("slash " .. cmd, mod.Slash, rest)
    else
      Print("module not available")
    end
    return
  end
  if cmd == "status" then
    Print(string.format("v%s · schema %s", tostring(Config.VERSION), tostring(Config.CURRENT_SCHEMA)))
    Print("minimap: " .. (p.minimap.show == false and "hidden" or "shown") .. " · angle " .. string.format("%.0f", p.minimap.angle or 0))
    if M.PartyMarks then
      Print("party marks: " .. M.PartyMarks.Status())
    end
    if M.ProcHUD and M.ProcHUD.Status then
      Print("procs: " .. M.ProcHUD.Status())
    end
    if M.EasyFish and M.EasyFish.Status then
      Print("fishing: " .. M.EasyFish.Status())
    end
    return
  end
  if cmd == "reset" then
    Config.Reset()
    if M.PartyMarks then
      M.PartyMarks.Apply()
    end
    if M.Minimap then
      M.Minimap.Apply()
    end
    if M.ProcHUD and M.ProcHUD.Apply then
      M.ProcHUD.Apply()
    end
    if M.EasyFish and M.EasyFish.Apply then
      M.EasyFish.Apply()
    end
    if Wayfarer.Settings then
      Wayfarer.Settings.Refresh()
    end
    Print(L.CONFIG_RESET)
    return
  end
  Print(L.UNKNOWN_CMD)
end
