--[[
  BetterBackpack — category-lane bags with CS-RMB (Forever 16001).
  /bb help|on|off|sort|dump|safe|reset|selftest|bags
]]

local addonName = ...

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local L = BetterBackpack.L or {}
local Config = BetterBackpack.Config
local Slots = BetterBackpack.Modules.Slots
local Layout = BetterBackpack.Modules.Layout
local Context = BetterBackpack.Modules.Context
-- Resolve modules at call time too — load errors must not leave a nil upvalue forever.
local function OC()
  return BetterBackpack.Modules and BetterBackpack.Modules.OpenClose
end
local OpenClose = BetterBackpack.Modules.OpenClose
local Tidy = BetterBackpack.Modules.Tidy

local function EnsureDB()
  return Config.EnsureDB()
end

local function Print(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring(select(i, ...))
  end
  print((L.PREFIX or "[BetterBackpack]") .. " " .. table.concat(parts, " "))
end

BetterBackpack.Print = Print

local function Trim(s, maxLen)
  s = tostring(s or "")
  if #s > maxLen then
    return s:sub(1, maxLen - 3) .. "..."
  end
  return s
end

local function Now()
  if time then
    return time()
  end
  return 0
end

function BetterBackpack.RecordError(context, err)
  local db = EnsureDB()
  local msg = Trim(tostring(err or "?"), Config.MAX_MSG)
  local ctx = Trim(tostring(context or "?"), 120)
  local stack = ""
  if debugstack then
    local ok, s = pcall(debugstack, 3)
    if ok then
      stack = Trim(s or "", Config.MAX_MSG)
    end
  end

  local list = db.errors
  for i = 1, #list do
    local e = list[i]
    if e.msg == msg and e.context == ctx then
      e.count = (e.count or 1) + 1
      e.last = Now()
      if stack ~= "" then
        e.stack = stack
      end
      return
    end
  end

  list[#list + 1] = {
    msg = msg,
    context = ctx,
    stack = stack,
    first = Now(),
    last = Now(),
    count = 1,
  }
  while #list > Config.MAX_ERRORS do
    table.remove(list, 1)
  end

  if ForeverErrorLog and ForeverErrorLog.Record then
    pcall(ForeverErrorLog.Record, "BetterBackpack:" .. ctx .. " " .. msg, stack)
  end
end

local function SafeCall(context, fn, ...)
  local ok, a, b, c = pcall(fn, ...)
  if not ok then
    BetterBackpack.RecordError(context, a)
    return nil
  end
  return a, b, c
end

local function ModuleWanted()
  local p = Config.GetProfile()
  return p.enabled and not p.safeMode
end

local bagRefreshToken = 0
local function QueueBagRefresh()
  if InCombatLockdown and InCombatLockdown() then
    if Layout and Layout.IsShown and Layout.IsShown() and Layout.RefreshCooldowns then
      Layout.RefreshCooldowns()
    end
    return
  end
  if BetterBackpack._combatFrozen then
    return
  end
  if BetterBackpack._sortSuppressRefresh then
    return
  end
  if not (Layout and Layout.IsShown and Layout.IsShown()) then
    return
  end
  if not (C_Timer and C_Timer.After) then
    if Layout.Refresh then
      Layout.Refresh()
    end
    return
  end
  bagRefreshToken = bagRefreshToken + 1
  local token = bagRefreshToken
  local delays = { 0.05, 0.25, 0.7, 1.5 }
  for i = 1, #delays do
    local d = delays[i]
    C_Timer.After(d, function()
      if token ~= bagRefreshToken then
        return
      end
      if InCombatLockdown and InCombatLockdown() then
        return
      end
      if BetterBackpack._sortSuppressRefresh then
        return
      end
      if Layout.IsShown and Layout.IsShown() and Layout.Refresh then
        Layout.Refresh()
      end
    end)
  end
end

local function DumpRing()
  local db = EnsureDB()
  local list = db.errors
  local p = db.profile
  Print(string.format(L.DUMP_HEADER or "dump — errors=%d · ver=%s", #list, tostring(Config.VERSION)))
  Print(string.format(
    L.STATUS_LINE or "enabled=%s · safe=%s · replace=%s · schema=%s · ver=%s · open=%s",
    tostring(p.enabled),
    tostring(p.safeMode),
    tostring(p.replaceBlizzard),
    tostring(db.schemaVersion),
    tostring(Config.VERSION),
    tostring(OpenClose and OpenClose.BagsOpen and OpenClose.BagsOpen())
  ))
  if db.lastSelftest and db.lastSelftest.card then
    print("|cffaaaaaa" .. tostring(db.lastSelftest.card) .. "|r")
  end
  if db.lastBlocked then
    print("|cffaaaaaalastBlocked: " .. tostring(db.lastBlocked.func) .. "|r")
  end
  if #list == 0 then
    Print(L.NO_ERRORS or "no errors in ring")
  else
    local from = math.max(1, #list - 9)
    for i = from, #list do
      local e = list[i]
      local n = e.count and e.count > 1 and (" ×" .. e.count) or ""
      print(string.format("|cffd94a4a%d. [%s]%s %s|r", i, e.context or "?", n, e.msg or "?"))
    end
  end
end

local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:RegisterEvent("BAG_UPDATE")
bootFrame:RegisterEvent("BAG_UPDATE_DELAYED")
bootFrame:RegisterEvent("ITEM_LOCK_CHANGED")
bootFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
bootFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
bootFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
bootFrame:RegisterEvent("PLAYER_MONEY")
bootFrame:RegisterEvent("MERCHANT_SHOW")
bootFrame:RegisterEvent("MERCHANT_CLOSED")
bootFrame:RegisterEvent("MAIL_SHOW")
bootFrame:RegisterEvent("MAIL_CLOSED")
bootFrame:RegisterEvent("BANKFRAME_OPENED")
bootFrame:RegisterEvent("BANKFRAME_CLOSED")
bootFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
bootFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
bootFrame:RegisterEvent("ADDON_ACTION_BLOCKED")

local blockedQuietUntil = 0

bootFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= addonName then
      return
    end
    EnsureDB()
    return
  end

  if event == "PLAYER_LOGIN" then
    EnsureDB()
    OpenClose = OC() or OpenClose
    if ModuleWanted() then
      if OpenClose and OpenClose.InstallHooks then
        SafeCall("hooks", OpenClose.InstallHooks)
      else
        Print("ERROR: OpenClose failed to load — check FrameXML.log")
      end
      if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
          SafeCall("precreate", Slots.PreCreate)
          if not (InCombatLockdown and InCombatLockdown()) then
            SafeCall("warmup:ensure", Layout.EnsureMain)
          end
        end)
      else
        SafeCall("precreate", Slots.PreCreate)
      end
    end
    Print(string.format(L.LOADED or "loaded v%s · /bb", tostring(Config.VERSION)))
    return
  end

  if event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "ITEM_LOCK_CHANGED"
      or event == "GET_ITEM_INFO_RECEIVED"
  then
    QueueBagRefresh()
    return
  end

  if event == "UNIT_INVENTORY_CHANGED" then
    local unit = ...
    if unit == "player" then
      QueueBagRefresh()
    end
    return
  end

  if event == "SPELL_UPDATE_COOLDOWN" then
    if Layout and Layout.IsShown and Layout.IsShown() and Layout.RefreshCooldowns then
      Layout.RefreshCooldowns()
    end
    return
  end

  if event == "PLAYER_MONEY" then
    if Layout and Layout.IsShown and Layout.IsShown() and Layout.UpdateMoney then
      Layout.UpdateMoney()
    end
    return
  end

  if event == "MERCHANT_SHOW" then
    if Context then
      Context.SyncSpecialMode()
    end
    if Layout and Layout.IsShown and Layout.IsShown() and Layout.UpdateMoney then
      Layout.UpdateMoney()
    end
    return
  end

  if event == "MERCHANT_CLOSED" or event == "MAIL_CLOSED" or event == "BANKFRAME_CLOSED" then
    if Context and Context.ForceRestoreDeferred then
      Context.ForceRestoreDeferred()
    end
    return
  end

  if event == "MAIL_SHOW" or event == "BANKFRAME_OPENED" then
    if Context then
      Context.SyncSpecialMode()
    end
    return
  end

  if event == "PLAYER_REGEN_DISABLED" then
    BetterBackpack._combatFrozen = true
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    BetterBackpack._combatFrozen = false
    OpenClose = OC() or OpenClose
    if OpenClose and OpenClose.ClearReplaceSuppress then
      OpenClose.ClearReplaceSuppress()
    end
    SafeCall("regen:precreate", Slots.PreCreate)
    SafeCall("regen:attrs", Slots.SyncAllAttrs)
    if Layout and Layout.IsShown and Layout.IsShown() and Layout.Refresh then
      SafeCall("regen:layout", Layout.Refresh)
    end
    return
  end

  if event == "ADDON_ACTION_BLOCKED" then
    local addon, func = ...
    local a = tostring(addon or ""):lower()
    if a == "" or (a ~= addonName:lower() and not a:find("betterbackpack", 1, true)) then
      return
    end
    local t = GetTime and GetTime() or 0
    if t < blockedQuietUntil then
      return
    end
    blockedQuietUntil = t + 3.0
    local db = EnsureDB()
    db.lastBlocked = { func = tostring(func or ""), t = Now() }
    if InCombatLockdown and InCombatLockdown() then
      BetterBackpack._combatFrozen = true
    end
    local p = Config.GetProfile()
    if p.debug then
      Print("BLOCKED soft:", tostring(func), "— /felog list")
    end
    return
  end
end)

SLASH_BETTERBACKPACK1 = "/bb"
SLASH_BETTERBACKPACK2 = "/betterbackpack"
SlashCmdList.BETTERBACKPACK = function(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$") or ""
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower() or ""

  if cmd == "" or cmd == "toggle" then
    if ModuleWanted() then
      SafeCall("toggle", OpenClose.Toggle)
    else
      Print(L.SAFE_ON or "safe/off — /bb on")
    end
    return
  end

  if cmd == "help" or cmd == "?" then
    local lines = L.HELP_LINES or {}
    for i = 1, #lines do
      Print(lines[i])
    end
    local p = Config.GetProfile()
    local db = EnsureDB()
    Print(string.format(
      L.STATUS_LINE or "enabled=%s · safe=%s · replace=%s · schema=%s · ver=%s · open=%s",
      tostring(p.enabled),
      tostring(p.safeMode),
      tostring(p.replaceBlizzard),
      tostring(db.schemaVersion),
      tostring(Config.VERSION),
      tostring(OpenClose.BagsOpen and OpenClose.BagsOpen())
    ))
    return
  end

  if cmd == "on" then
    local p = Config.GetProfile()
    p.enabled = true
    p.safeMode = false
    SafeCall("hooks", OpenClose.InstallHooks)
    SafeCall("precreate", Slots.PreCreate)
    Print(L.ENABLED or "on")
    return
  end

  if cmd == "off" then
    local p = Config.GetProfile()
    p.enabled = false
    SafeCall("shutdown", OpenClose.ShutdownToBlizzard)
    Print(L.DISABLED or "off")
    return
  end

  if cmd == "safe" then
    local p = Config.GetProfile()
    p.safeMode = true
    SafeCall("safe", OpenClose.ShutdownToBlizzard)
    Print(L.SAFE_ON or "safe mode")
    return
  end

  if cmd == "reset" then
    Config.Reset()
    SafeCall("shutdown", OpenClose.ShutdownToBlizzard)
    Print(L.CONFIG_RESET or "config reset")
    return
  end

  if cmd == "settings" or cmd == "config" or cmd == "opts" then
    local S = BetterBackpack.Modules.Settings
    if S and S.Toggle then
      S.Toggle()
    end
    return
  end

  if cmd == "search" or cmd == "find" then
    local Search = BetterBackpack.Modules.Search
    if not Search then
      Print("Search module not loaded")
      return
    end
    Search.SetQuery(rest or "")
    Print("search=", Search.GetQuery() == "" and "(cleared)" or Search.GetQuery())
    return
  end

  if cmd == "filter" then
    local Filter = BetterBackpack.Modules.Filter
    if not Filter then
      Print("Filter module not loaded")
      return
    end
    local key = (rest or ""):match("^(%S+)")
    Filter.SetCategory(key)
    Print("filter=", Filter.GetCategory() or "all")
    return
  end

  if cmd == "trashtest" then
    local Trash = BetterBackpack.Modules.Trash
    if Trash and Trash.RunTest then
      SafeCall("trashtest", Trash.RunTest, rest)
    else
      Print("Trash module not loaded")
    end
    return
  end

  if cmd == "pin" then
    local Pins = BetterBackpack.Modules.Pins
    if not Pins then
      Print("Pins module not loaded")
      return
    end
    local id = tonumber((rest or ""):match("^(%d+)"))
    if not id then
      -- Cursor / tooltip item for smoke testing without typing IDs.
      pcall(function()
        local info = C_Cursor and C_Cursor.GetCursorItem and C_Cursor.GetCursorItem()
        if info and info.GetItemID then
          id = info:GetItemID()
        end
      end)
      if not id and GameTooltip and GameTooltip.GetItem then
        pcall(function()
          local _, link = GameTooltip:GetItem()
          if type(link) == "string" then
            id = tonumber(link:match("item:(%d+)"))
          end
        end)
      end
    end
    if not id then
      Print("usage: /bb pin <itemID> (or hover/cursor item)")
      return
    end
    Pins.Toggle(id)
    Print("pin toggled", id)
    return
  end

  if cmd == "custom" then
    local CC = BetterBackpack.Modules.CustomCategories
    if not CC then
      Print("CustomCategories module not loaded")
      return
    end
    local sub, arg = (rest or ""):match("^(%S+)%s*(.*)$")
    sub = sub and sub:lower() or ""
    if sub == "add" then
      local entry = CC.Add(arg)
      if entry then
        Print("custom category", entry.id, entry.name)
      else
        Print("usage: /bb custom add <name>")
      end
    elseif sub == "del" or sub == "rm" or sub == "remove" then
      CC.Remove(arg:match("^(%S+)"))
      Print("custom removed", arg)
    else
      local list = CC.List() or {}
      Print("custom categories:", #list)
      for i = 1, #list do
        Print(" ", list[i].id, list[i].name)
      end
    end
    return
  end

  if cmd == "assign" then
    local CC = BetterBackpack.Modules.CustomCategories
    if not CC then
      Print("CustomCategories module not loaded")
      return
    end
    local id, cat = (rest or ""):match("^(%d+)%s+(%S+)")
    id = tonumber(id)
    if not id then
      Print("usage: /bb assign <itemID> <cat|clear>")
      return
    end
    if not cat or cat == "clear" or cat == "none" then
      CC.AssignItem(id, nil)
      Print("cleared rule for", id)
    else
      CC.AssignItem(id, cat)
      Print("assigned", id, "→", cat)
    end
    return
  end

  if cmd == "layout" or cmd == "mode" then
    local LM = BetterBackpack.Modules.LayoutModes
    if not LM then
      Print("LayoutModes module not loaded")
      return
    end
    local arg = (rest or ""):match("^(%S+)")
    if arg == "lanes" or arg == "dense" then
      LM.Set(arg)
    else
      LM.Toggle()
    end
    Print("layoutMode=", LM.Get())
    return
  end

  if cmd == "merge" or cmd == "stackmerge" then
    local SM = BetterBackpack.Modules.StackMerge
    if not SM then
      Print("StackMerge module not loaded")
      return
    end
    local arg = (rest or ""):match("^(%S+)")
    if arg == "on" then
      SM.SetEnabled(true)
    elseif arg == "off" then
      SM.SetEnabled(false)
    else
      SM.SetEnabled(not SM.IsEnabled())
    end
    Print("stackMerge=", tostring(SM.IsEnabled()))
    return
  end

  if cmd == "sort" or cmd == "tidy" or cmd == "uklid" then
    SafeCall("sort", Tidy.SortBags)
    return
  end

  if cmd == "stack" then
    SafeCall("stack", Tidy.StackBags)
    return
  end

  if cmd == "dump" then
    DumpRing()
    return
  end

  if cmd == "selftest" or cmd == "test" then
    local ok, card, notes = Layout.RunSelfTest()
    Print(card)
    if notes then
      for i = 1, #notes do
        Print("  ", notes[i])
      end
    end
    if OpenClose.RunOpenCloseSelfTest then
      local ocOk, ocPass, ocFail, ocNotes = OpenClose.RunOpenCloseSelfTest()
      Print(string.format("open/close selftest pass=%s fail=%s", tostring(ocPass), tostring(ocFail)))
      if ocNotes then
        for i = 1, #ocNotes do
          Print("  ", ocNotes[i])
        end
      end
      ok = ok and ocOk
    end
    if ok then
      Print(L.SELFTEST_HINT or "selftest PASS — still need 1× manual combat RMB")
    else
      Print("selftest FAIL")
    end
    return
  end

  if cmd == "bags" then
    local d = Layout.DiagnoseBags and Layout.DiagnoseBags()
    if d then
      Print(string.format(
        "reagent filled=%s/%s inRanges=%s · free=%s/%s",
        tostring(d.reagentFilled),
        tostring(d.reagentSlots),
        tostring(d.reagentInRanges),
        tostring(d.free),
        tostring(d.total)
      ))
    end
    return
  end

  if cmd == "frame" or cmd == "debugopen" then
    local d = Layout.DebugState and Layout.DebugState() or {}
    Print(string.format(
      "frame ver=%s exists=%s shown=%s w=%s h=%s uklid=%s nastav=%s chrome=%s session=%s",
      tostring(d.ver or Config.VERSION),
      tostring(d.exists),
      tostring(d.shown),
      tostring(d.w),
      tostring(d.h),
      tostring(d.uklid),
      tostring(d.nastaveni),
      tostring(d.chromeVer),
      tostring(OpenClose.SessionOpen and OpenClose.SessionOpen())
    ))
    if rest == "open" or cmd == "debugopen" then
      SafeCall("debugopen", OpenClose.OpenOurs)
      d = Layout.DebugState and Layout.DebugState() or {}
      Print(string.format("after open shown=%s w=%s h=%s", tostring(d.shown), tostring(d.w), tostring(d.h)))
    end
    return
  end

  if cmd == "resetpos" then
    if Layout.ResetPosition then
      Layout.ResetPosition()
    end
    Print("position reset")
    return
  end

  if cmd == "debug" then
    local p = Config.GetProfile()
    if rest == "on" then
      p.debug = true
    elseif rest == "off" then
      p.debug = false
    else
      p.debug = not p.debug
    end
    Print("debug=", tostring(p.debug))
    return
  end

  Print(L.UNKNOWN_CMD or "unknown — /bb help")
end
