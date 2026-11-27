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
local BulkTransfer = BetterBackpack.Modules.BulkTransfer
-- Resolve modules at call time too — load errors must not leave a nil upvalue forever.
local function OC()
  return BetterBackpack.Modules and BetterBackpack.Modules.OpenClose
end
local function BT()
  return BetterBackpack.Modules and BetterBackpack.Modules.BulkTransfer
end
local OpenClose = BetterBackpack.Modules.OpenClose
local Tidy = BetterBackpack.Modules.Tidy
local SessionLog = BetterBackpack.Modules.SessionLog

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

  if SessionLog and SessionLog.Append then
    pcall(SessionLog.Append, string.format("ERROR [%s] %s", ctx, msg))
  end

  if ForeverErrorLog and ForeverErrorLog.Record then
    pcall(ForeverErrorLog.Record, "BetterBackpack:" .. ctx .. " " .. msg, stack)
  end
end

function BetterBackpack.SilentTraceEnabled()
  local p = Config.GetProfile()
  return p.silentTrace ~= false and p.actionTraceOn ~= false
end

--- Diagnostics → SessionLog only. Chat only when opts.forceChat (slash /bb bagkey, etc.).
function BetterBackpack.TraceAction(detail, chatPrefix, opts)
  detail = tostring(detail or "")
  if detail == "" then
    return
  end
  if SessionLog and SessionLog.RecordAction then
    pcall(SessionLog.RecordAction, detail)
  end
  opts = type(opts) == "table" and opts or {}
  if opts.forceChat then
    if Print then
      local msg = chatPrefix and (chatPrefix .. " " .. detail) or detail
      Print(msg)
    end
  end
end

--- Intentional player feedback — always chat (Trash destroy, settings, slash responses).
function BetterBackpack.Say(...)
  Print(...)
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

local function WarmCombatShell(tag)
  if not ModuleWanted() then
    return
  end
  if InCombatLockdown and InCombatLockdown() then
    return
  end
  if Layout and Layout.EnsureCombatShell then
    SafeCall("shell:" .. tostring(tag or "?"), Layout.EnsureCombatShell)
    return
  end
  SafeCall("precreate:" .. tostring(tag or "?"), Slots.PreCreate)
  SafeCall("ensure:" .. tostring(tag or "?"), Layout.EnsureMain)
end

-- One reused callback + pending flag per stage; a stage that fires early (a later event
-- arrived) re-arms for the remainder, so refreshes run ~0.05 s / ~0.55 s after the LAST event.
local bagQ = { last = 0, delays = { 0.05, 0.55 }, pending = {}, cb = {} }
for i = 1, #bagQ.delays do
  bagQ.cb[i] = function()
    local wait = bagQ.delays[i] - (GetTime() - bagQ.last)
    if wait > 0.005 then
      C_Timer.After(wait, bagQ.cb[i])
      return
    end
    bagQ.pending[i] = false
    if InCombatLockdown and InCombatLockdown() then
      return
    end
    if BetterBackpack._sortSuppressRefresh then
      return
    end
    if not (Layout.IsShown and Layout.IsShown()) then
      return
    end
    -- Always Layout.Refresh (it picks DoLayout vs RefreshLight via occ/sig);
    -- RefreshLight-only left emptied sell cells lit.
    if Layout.Refresh then
      Layout.Refresh()
    elseif Layout.RefreshLight then
      Layout.RefreshLight()
    end
  end
end

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
    if Layout.RefreshLight then
      Layout.RefreshLight()
    elseif Layout.Refresh then
      Layout.Refresh()
    end
    return
  end
  bagQ.last = GetTime()
  for i = 1, #bagQ.delays do
    if not bagQ.pending[i] then
      bagQ.pending[i] = true
      C_Timer.After(bagQ.delays[i], bagQ.cb[i])
    end
  end
end

local function DumpRing()
  local db = EnsureDB()
  local list = db.errors
  local p = db.profile
  Print(string.format(L.DUMP_HEADER or "dump — errors=%d · ver=%s", #list, tostring(Config.VERSION)))
  if SessionLog and SessionLog.Status then
    local st = SessionLog.Status()
    Print(string.format(
      "sessionLog lines=%d · actionTrace=%d · silent=%s",
      st.lines or 0,
      st.actionEntries or 0,
      tostring(BetterBackpack.SilentTraceEnabled())
    ))
    if db.lastActionTrace then
      print("|cff888888lastAction: " .. tostring(db.lastActionTrace) .. "|r")
    end
  end
  Print(string.format(
    L.STATUS_LINE or "enabled=%s · safe=%s · replace=%s · schema=%s · ver=%s · open=%s",
    tostring(p.enabled),
    tostring(p.safeMode),
    tostring(p.replaceBlizzard),
    tostring(db.schemaVersion),
    tostring(Config.VERSION),
    tostring(OpenClose and OpenClose.BagsOpen and OpenClose.BagsOpen())
  ))
  if OpenClose and OpenClose.DumpOpenState then
    Print("|cffaaaaaa" .. OpenClose.DumpOpenState() .. "|r")
  end
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
bootFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
bootFrame:RegisterEvent("BAG_UPDATE")
bootFrame:RegisterEvent("BAG_UPDATE_DELAYED")
bootFrame:RegisterEvent("ITEM_LOCK_CHANGED")
bootFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
bootFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
bootFrame:RegisterEvent("QUEST_ACCEPTED")
bootFrame:RegisterEvent("QUEST_REMOVED")
bootFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
bootFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
bootFrame:RegisterEvent("PLAYER_MONEY")
bootFrame:RegisterEvent("MERCHANT_SHOW")
bootFrame:RegisterEvent("MERCHANT_CLOSED")
bootFrame:RegisterEvent("MAIL_SHOW")
bootFrame:RegisterEvent("MAIL_CLOSED")
bootFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
bootFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
bootFrame:RegisterEvent("BANKFRAME_OPENED")
bootFrame:RegisterEvent("BANKFRAME_CLOSED")
bootFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
bootFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
bootFrame:RegisterEvent("ADDON_ACTION_BLOCKED")

local blockedQuietUntil = 0

-- Vendor / mail / auction / bank: if BetterBackpack was closed when the window opened,
-- it is closed again together with that window (never closes a bag the player had open).
local function NoteInteractionOpened()
  if BetterBackpack._bbOpenedByWindow ~= nil then
    return
  end
  local shown = Layout and Layout.IsShown and Layout.IsShown()
  BetterBackpack._bbOpenedByWindow = not shown
end

local function CloseIfOpenedByInteraction()
  local byWindow = BetterBackpack._bbOpenedByWindow
  BetterBackpack._bbOpenedByWindow = nil
  if byWindow ~= true then
    return
  end
  if InCombatLockdown and InCombatLockdown() then
    return
  end
  OpenClose = OC() or OpenClose
  if Layout and Layout.IsShown and Layout.IsShown() and OpenClose and OpenClose.CloseOurs then
    SafeCall("closeWithWindow", OpenClose.CloseOurs)
  end
end

bootFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == addonName then
      EnsureDB()
      SessionLog = BetterBackpack.Modules.SessionLog or SessionLog
      if SessionLog and SessionLog.BeginSession then
        SafeCall("session:begin", SessionLog.BeginSession)
      end
      BulkTransfer = BT()
      if not BulkTransfer or not BulkTransfer.TransferLane then
        Print("ERROR: BulkTransfer failed to load — check FrameXML.log / TOC")
      end
      return
    end
    if name == "BagShelves" and ModuleWanted() and OpenClose then
      Print(
        "|cffff5050BetterBackpack:|r BagShelves loaded — conflicts with replace bags. Disable BagShelves at login."
      )
      if OpenClose.EnsureBagKeyReplace then
        SafeCall("hooks", OpenClose.EnsureBagKeyReplace)
      end
      if C_Timer and C_Timer.After and OpenClose.EnsureBagKeyReplace then
        C_Timer.After(0.5, function()
          SafeCall("hooks", OpenClose.EnsureBagKeyReplace)
        end)
      end
    end
    if ModuleWanted() and OpenClose and OpenClose.EnsureBagKeyReplace then
      if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
          SafeCall("hooks", OpenClose.EnsureBagKeyReplace)
        end)
      else
        SafeCall("hooks", OpenClose.EnsureBagKeyReplace)
      end
    end
    return
  end

  if event == "PLAYER_LOGIN" then
    EnsureDB()
    OpenClose = OC() or OpenClose
    BulkTransfer = BT() or BulkTransfer
    if BulkTransfer and BulkTransfer.TransferLane and not BetterBackpack.SilentTraceEnabled() then
      Print("BulkTransfer ok · Ctrl+Shift+RMB lane header · Shift+RMB merged stack at vendor/mail")
    end
    if ModuleWanted() then
      if OpenClose and OpenClose.InstallHooks then
        SafeCall("hooks", OpenClose.InstallHooks)
      else
        Print("ERROR: OpenClose failed to load — check FrameXML.log")
      end
      if OpenClose and OpenClose.WarnBagConflicts then
        if C_Timer and C_Timer.After then
          C_Timer.After(0.5, function()
            SafeCall("conflict", OpenClose.WarnBagConflicts)
          end)
        else
          SafeCall("conflict", OpenClose.WarnBagConflicts)
        end
      end
      if Layout and Layout.InstallEscGuard then
        SafeCall("esc", Layout.InstallEscGuard)
      end
      if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
          WarmCombatShell("login")
        end)
        C_Timer.After(0.1, function()
          if Layout and Layout.SyncBagUISpecialFrame then
            SafeCall("esc", Layout.SyncBagUISpecialFrame)
          end
        end)
        for _, delay in ipairs({ 0.5, 2, 5, 15 }) do
          C_Timer.After(delay, function()
            if Layout and Layout.SyncBagUISpecialFrame then
              SafeCall("esc", Layout.SyncBagUISpecialFrame)
            end
          end)
        end
      else
        WarmCombatShell("login")
      end
    end
    Print(string.format(L.LOADED or "loaded v%s · /bb", tostring(Config.VERSION)))
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    if ModuleWanted() and OpenClose and OpenClose.EnsureBagKeyReplace then
      SafeCall("hooks", OpenClose.EnsureBagKeyReplace)
    end
    local CC = BetterBackpack.Modules.CustomCategories
    if CC and CC.OnCharacterActive then
      SafeCall("charLanes", CC.OnCharacterActive)
    end
    return
  end

  if event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "ITEM_LOCK_CHANGED"
      or event == "GET_ITEM_INFO_RECEIVED"
  then
    QueueBagRefresh()
    return
  end

  if event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
    if Layout and Layout.IsShown and Layout.IsShown() and Layout.RefreshQuestBangs then
      SafeCall("questBang", Layout.RefreshQuestBangs)
    end
    return
  end

  if event == "UNIT_QUEST_LOG_CHANGED" then
    local unit = ...
    if unit and unit ~= "player" then
      return
    end
    if Layout and Layout.IsShown and Layout.IsShown() and Layout.RefreshQuestBangs then
      SafeCall("questBang", Layout.RefreshQuestBangs)
    end
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
    if Layout and Layout.IsShown and Layout.IsShown() and Layout.RefreshCooldownsOnly then
      Layout.RefreshCooldownsOnly()
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
    NoteInteractionOpened()
    if Context then
      Context.SyncSpecialMode()
    end
    OpenClose = OC() or OpenClose
    if OpenClose and OpenClose.OnMerchantShow then
      SafeCall("merchantBags", OpenClose.OnMerchantShow)
    end
    if Layout and Layout.IsShown and Layout.IsShown() and Layout.UpdateMoney then
      Layout.UpdateMoney()
    end
    local VJ = BetterBackpack.Modules.VendorJunk
    if VJ and VJ.OnMerchantShow then
      SafeCall("vendorJunk", VJ.OnMerchantShow)
    end
    return
  end

  if event == "MERCHANT_CLOSED" or event == "MAIL_CLOSED" or event == "AUCTION_HOUSE_CLOSED" or event == "BANKFRAME_CLOSED" then
    if Context and Context.ForceRestoreDeferred then
      Context.ForceRestoreDeferred()
    end
    CloseIfOpenedByInteraction()
    if event == "MERCHANT_CLOSED" then
      local VJ = BetterBackpack.Modules.VendorJunk
      if VJ and VJ.OnMerchantClosed then
        VJ.OnMerchantClosed()
      end
    end
    return
  end

  if event == "MAIL_SHOW" or event == "AUCTION_HOUSE_SHOW" or event == "BANKFRAME_OPENED" then
    NoteInteractionOpened()
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
    WarmCombatShell("regen")
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
    BetterBackpack.TraceAction("BLOCKED soft " .. tostring(func or "?"))
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
    local all = (rest or ""):lower() == "all"
    Config.Reset(all and "all" or nil)
    SafeCall("shutdown", OpenClose.ShutdownToBlizzard)
    Print(all and (L.CONFIG_RESET_ALL or "all BetterBackpack data reset (every character)")
      or (L.CONFIG_RESET or "settings + this character reset (other characters kept) — /bb reset all wipes everything"))
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

  if cmd == "sort" or cmd == "tidy" then
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

  if cmd == "bagkey" or cmd == "bkey" then
    if OpenClose and OpenClose.EnsureBagKeyReplace then
      SafeCall("hooks", OpenClose.EnsureBagKeyReplace)
    end
    if OpenClose and OpenClose.DiagnoseBagKey then
      local lines = OpenClose.DiagnoseBagKey()
      for i = 1, #lines do
        Print(lines[i])
      end
    end
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
      Print("merge regression OK (open/close + VisibleGridSignature + sell wiring) — manual: vendor Shift+RMB merged stack")
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
      "frame ver=%s exists=%s shown=%s w=%s h=%s tidy=%s settings=%s chrome=%s session=%s",
      tostring(d.ver or Config.VERSION),
      tostring(d.exists),
      tostring(d.shown),
      tostring(d.w),
      tostring(d.h),
      tostring(d.tidy),
      tostring(d.settings),
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
    Print(
      string.format(
        "debug=%s (SV trace only — chat only via /bb bagkey; silentTrace=%s)",
        tostring(p.debug),
        tostring(BetterBackpack.SilentTraceEnabled())
      )
    )
    return
  end

  Print(L.UNKNOWN_CMD or "unknown — /bb help")
end
