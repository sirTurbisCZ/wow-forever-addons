--[[
  Seekwell — what drops from your target, item sources on tooltips, learning from your own loot.
  /seekwell or /sw: help|target|status|probe|minimap|reset|reset learned|dev on|off
]]

local addonName = ...

Seekwell = Seekwell or {}
Seekwell.Modules = Seekwell.Modules or {}

local L = Seekwell.L or {}
local Config = Seekwell.Config

local function Print(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring(select(i, ...))
  end
  print((L.PREFIX or "[Seekwell]") .. " " .. table.concat(parts, " "))
end
Seekwell.Print = Print

function Seekwell.Debug(...)
  local ok, s = pcall(Config.Get)
  if ok and s and s.dev then
    Print("|cff999999debug|r", ...)
  end
end

local reported = {} -- each error once per session
local reportedCount = 0

--- Error boundary: report to ForeverErrorLog when it is installed, never throw into the game.
function Seekwell.RecordError(context, err)
  local key = tostring(context) .. " " .. tostring(err)
  if reported[key] then
    return
  end
  if reportedCount >= 200 then
    reported, reportedCount = {}, 0 -- cap: start over, so de-duplication never stops
  end
  reported[key] = true
  reportedCount = reportedCount + 1
  if ForeverErrorLog and ForeverErrorLog.Record then
    pcall(ForeverErrorLog.Record, "Seekwell:" .. key, "")
  end
  local ok, s = pcall(Config.Get)
  if ok and s and s.dev then
    print("|cffff5555[Seekwell] error|r " .. key)
  end
end

--- Wrap fn in a pcall boundary; errors go to RecordError(context, err).
function Seekwell.Safe(context, fn)
  return function(...)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
      Seekwell.RecordError(context, a)
      return nil
    end
    return a, b, c
  end
end

local function SafeCall(context, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    Seekwell.RecordError(context, err)
  end
  return ok
end
Seekwell.SafeCall = SafeCall

local booted = false
local function Boot()
  if booted then
    return
  end
  booted = true
  Config.EnsureDB()
  Config.EnsureCharDB()
  if Seekwell.Loot then
    SafeCall("loot.start", Seekwell.Loot.Start)
  end
  if Seekwell.Tooltip then
    SafeCall("tooltip.install", Seekwell.Tooltip.Install)
  end
  local M = Seekwell.Modules
  if M.Minimap then
    SafeCall("minimap", M.Minimap.Create)
  end
  for _, st in ipairs(Seekwell._starters or {}) do
    SafeCall("start." .. st.name, st.fn)
  end
  local tinny = Seekwell.Tinny and Seekwell.Tinny.Available()
  Print(string.format(L.LOADED or "v%s · /sw", tostring(Config.VERSION)) .. " · " .. (tinny and (L.TINNY_YES or "Tinny data: yes") or (L.TINNY_NO or "no Tinny data")))
end

local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == addonName then
    SafeCall("db", Config.EnsureDB)
    SafeCall("chardb", Config.EnsureCharDB)
  elseif event == "PLAYER_LOGIN" then
    SafeCall("boot", Boot)
  end
end)

local function Has(path)
  local t = _G
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then
      return false
    end
    t = t[part]
  end
  return t ~= nil
end

local PROBE_APIS = {
  "C_Map.SetUserWaypoint", "C_SuperTrack", "C_SuperTrack.SetSuperTrackedUserWaypoint",
  "EJ_GetNumTiers", "C_EncounterJournal", "C_Item.GetItemInfoInstant", "C_Item.GetItemInfo",
  "C_Item.RequestLoadItemDataByID", "C_Item.GetItemCount", "GetItemCount", "C_AddOns.LoadAddOn",
  "C_TradeSkillUI.GetRecipeSchematic", "TooltipDataProcessor", "TooltipDataProcessor.AddTooltipPostCall",
  "GetMerchantItemID", "GetQuestItemLink", "GetLootSourceInfo", "C_Map.GetBestMapForUnit",
  "C_Map.GetPlayerMapPosition", "C_Map.GetWorldPosFromMapPos", "issecretvalue",
}

local function Probe()
  Print("probe — client APIs (yes = present):")
  local line = {}
  for i, api in ipairs(PROBE_APIS) do
    line[#line + 1] = api .. "=" .. (Has(api) and "|cff55ff55yes|r" or "|cffff5555no|r")
    if #line == 3 or i == #PROBE_APIS then
      Print("  " .. table.concat(line, "  "))
      line = {}
    end
  end
  Print("  GLOBAL_MOUSE_DOWN: not needed (no click-on-mob in 0.1.0)")
  local T = Seekwell.Tinny
  local c = T.Counts()
  Print(string.format("  TnnysMobLoot_Forever: %s (npc %d, from %d, asOf %s)", T.HasForever() and "yes" or "no",
    c.forever, c.foreverFrom, tostring(T.AsOf() or "-")))
  Print(string.format("  TnnysMobLoot_Starter: %s (npc %d)", T.HasStarter() and "yes" or "no", c.starter))
  local Sec = Seekwell.Secret
  if Sec.Get(UnitExists, "target") then
    local okG, guid = pcall(UnitGUID, "target")
    local secret = okG and issecretvalue and Sec.IsSecret(guid)
    Print("  issecretvalue(UnitGUID(\"target\")) = " .. tostring(secret and true or false) .. " · kind " .. Sec.GUIDKind(okG and guid or nil))
  else
    Print("  no target (target a mob to test issecretvalue on its GUID)")
  end
end

local function Status()
  local T = Seekwell.Tinny
  local c = T.Counts()
  Print(string.format("v%s · schema %d", tostring(Config.VERSION), Config.CURRENT_SCHEMA))
  if T.Available() then
    Print(string.format("Tinny data: Forever %d npc (asOf %s) · Classic %d npc", c.forever, tostring(T.AsOf() or "-"), c.starter))
  else
    Print(L.TINNY_MISSING or "Tinny data not available")
  end
  local st = Seekwell.Learned.Stats()
  Print(string.format("learned: %d npc · %d kills · %d drops · ~%d KB · learning %s", st.npcs, st.kills, st.items,
    math.floor(st.bytes / 1024 + 0.5), Config.Get().learn and "on" or "off"))
  Print(string.format("wishlist: %d item(s) · tooltip lines %s (%d) · Classic estimates %s", Seekwell.Wish.Count(),
    Config.Get().tooltip.enabled and "on" or "off", tonumber(Config.Get().tooltip.max) or 3, Config.Get().classic and "on" or "off"))
  for _, st in ipairs(Seekwell._status or {}) do
    local ok, text = pcall(st.fn)
    Print(st.name .. ": " .. (ok and tostring(text) or ("error " .. tostring(text))))
  end
end

local function RefreshUI()
  if Seekwell.Modules.Minimap then
    Seekwell.Modules.Minimap.Apply()
  end
  if Seekwell.Window and Seekwell.Window.Refresh then
    Seekwell.Window.Refresh()
  end
  if Seekwell.TargetPanel and Seekwell.TargetPanel.Refresh then
    Seekwell.TargetPanel.Refresh()
  end
end

local function Slash(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$") or ""
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = (cmd or ""):lower()
  rest = (rest or ""):lower()
  local s = Config.Get()

  if cmd == "" then
    if Seekwell.Window then
      Seekwell.Window.Toggle()
    end
  elseif cmd == "help" or cmd == "?" then
    for _, line in ipairs(L.HELP_LINES or {}) do
      Print(line)
    end
  elseif cmd == "settings" or cmd == "options" then
    if Seekwell.Window and Seekwell.Window.ShowSettings then
      Seekwell.Window.ShowSettings(rest ~= "" and rest or nil)
    elseif Seekwell.Window then
      Seekwell.Window.Toggle()
    end
  elseif cmd == "target" then
    Seekwell.TargetPanel.Toggle()
  elseif cmd == "probe" then
    Probe()
  elseif cmd == "status" then
    Status()
  elseif cmd == "minimap" then
    local M = Seekwell.Modules.Minimap
    if rest == "reset" then
      M.Reset()
      Print(L.MINIMAP_RESET)
    elseif rest == "on" or rest == "off" then
      M.SetShown(rest == "on")
      Print(rest == "on" and L.MINIMAP_SHOWN or L.MINIMAP_HIDDEN)
    else
      Print("usage: /sw minimap on/off/reset")
    end
  elseif cmd == "reset" then
    if rest == "learned" then
      Seekwell.Learned.Clear()
      Seekwell.Registry.ClearCache()
      Print(L.LEARNED_RESET)
    elseif rest == "" then
      Config.Reset()
      Seekwell.Registry.ClearCache()
      Print(L.CONFIG_RESET)
    else
      Print("usage: /sw reset | /sw reset learned")
      return
    end
    RefreshUI()
  elseif cmd == "dev" then
    if rest == "on" or rest == "off" then
      s.dev = rest == "on"
      Print(s.dev and L.DEV_ON or L.DEV_OFF)
    else
      Print("usage: /sw dev on/off (now " .. (s.dev and "on" or "off") .. ")")
    end
  elseif Seekwell._slash and Seekwell._slash[cmd] then
    SafeCall("slash " .. cmd, Seekwell._slash[cmd], rest)
  else
    Print(L.UNKNOWN_CMD)
  end
end

SLASH_SEEKWELL1 = "/seekwell"
SLASH_SEEKWELL2 = "/sw"
SlashCmdList.SEEKWELL = function(msg)
  SafeCall("slash", Slash, msg)
end
