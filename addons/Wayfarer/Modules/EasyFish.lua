--[[
  Wayfarer.EasyFish — one key for fishing. Every press does exactly one thing, chosen by the state the
  game is in at the time of the press (nothing here acts on its own: the client gives addons no "a fish
  bit" signal, and hooking by sound or animation would be botting). First match wins:
    loot  a fishing loot window is open (Auto Loot off): our loot button takes every slot
    reel  the soft-interact target is our bobber: the key is INTERACTTARGET (Blizzard's Interact Key)
    cast  otherwise: our SecureActionButton with "/cast [conditions] <Fishing>"
  The key is an override binding owned by our own frame (the player's keybinds are never written) and is
  changed only out of combat; a change wanted in combat waits for PLAYER_REGEN_ENABLED. Turning the module
  off or clearing the key releases the override.
  A "session" is one cast: from the press (or the channel start) to the channel stop. During it the module
  may raise the interact reach (SoftTargetInteract*) and play effects louder (Sound_*), and puts every CVar
  it changed back afterwards, only where the CVar still holds our value. No OnUpdate; events are
  registered only while the module is on.
]]

Wayfarer = Wayfarer or {}
Wayfarer.Modules = Wayfarer.Modules or {}

local Mod = {}
Wayfarer.Modules.EasyFish = Mod

local OWNER_NAME = "WayfarerFishBinder"
local CAST_BUTTON = "WayfarerFishCast"
local LOOT_BUTTON = "WayfarerFishLoot"
local FISHING_ID = 7620 -- Fishing (rank 1) on WoW: Forever; "/cast <name>" uses the highest rank known
local FALLBACK_NAME = "Fishing"
local BOBBER_ID = 35591 -- GameObject entry of the fishing bobber
local CHANNEL_IDS = { [7620] = true, [7731] = true, [7732] = true, [18248] = true, [131476] = true, [131490] = true }
local CAST_CONDITIONS = "[nocombat,noswimming,nomounted,novehicleui]"
local CAST_WAIT = 3 -- seconds after a press for its channel to start before the session ends
local LOOT_WINDOW = 10 -- seconds after a fishing channel in which a loot window counts as fishing loot
local REACH = 30 -- SoftTargetInteractRange during a session (yards)
local MAIN_HAND = INVSLOT_MAINHAND or 16
local FORBIDDEN_KEYS = { BUTTON1 = true, BUTTON2 = true, ESCAPE = true, PRINTSCREEN = true }
local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
  LMETA = true, RMETA = true, UNKNOWN = true }
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local started, enabledNow = false, false
local ev, owner, castBtn, lootBtn
local applied, appliedKey = nil, nil -- what the key is bound to now ("cast" | "reel" | "loot" | nil)
local pending = false -- a binding change waits for the end of combat
local restorePending = false -- CVars to put back wait for the end of combat
local channeling, inReach, lootOpen = false, false, false
local lastChannelEnd = -100
local sessionOn, sessionToken = false, 0
local saved = {} -- [cvar] = { o = old value, s = value we set }

local function Cfg()
  return Wayfarer.Config.GetProfile().easyFish
end

local function Err(context, err)
  if Wayfarer.RecordError then
    Wayfarer.RecordError("easyfish:" .. tostring(context), err)
  end
end

local function Safe(context, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    Err(context, err)
  end
  return ok, err
end

local function Print(msg)
  if Wayfarer.Print then
    Wayfarer.Print(msg)
  end
end

local function InCombat()
  return InCombatLockdown and InCombatLockdown() or false
end

local function IsSecret(v)
  return issecretvalue and issecretvalue(v) or false
end

local function Now()
  return GetTime and GetTime() or 0
end

local function RefreshSettings()
  if Wayfarer.Settings and Wayfarer.Settings.Refresh then
    pcall(Wayfarer.Settings.Refresh)
  end
end

-------------------------------------------------------------------------------
-- Game lookups
-------------------------------------------------------------------------------

--- Localised name of Fishing (by spell id), English only as the last resort.
local function FishingName()
  local name
  if C_Spell and C_Spell.GetSpellName then
    local ok, n = pcall(C_Spell.GetSpellName, FISHING_ID)
    if ok and type(n) == "string" and n ~= "" then
      name = n
    end
  end
  if not name and C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, FISHING_ID)
    if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
      name = info.name
    end
  end
  if not name and GetSpellInfo then
    local ok, n = pcall(GetSpellInfo, FISHING_ID)
    if ok and type(n) == "string" and n ~= "" then
      name = n
    end
  end
  return name or FALLBACK_NAME
end

local function IsFishingChannel(spellID)
  if IsSecret(spellID) or type(spellID) ~= "number" then
    return false
  end
  if CHANNEL_IDS[spellID] then
    return true
  end
  local name
  if C_Spell and C_Spell.GetSpellName then
    local ok, n = pcall(C_Spell.GetSpellName, spellID)
    name = ok and n or nil
  elseif GetSpellInfo then
    local ok, n = pcall(GetSpellInfo, spellID)
    name = ok and n or nil
  end
  return name ~= nil and name == FishingName()
end

local function IsBobber(guid)
  if IsSecret(guid) or type(guid) ~= "string" then
    return false
  end
  local kind, _, _, _, _, id = strsplit("-", guid)
  return kind == "GameObject" and tonumber(id) == BOBBER_ID
end

local function SoftInteractGUID()
  if not UnitGUID then
    return nil
  end
  local ok, guid = pcall(UnitGUID, "softinteract")
  return ok and guid or nil
end

local function PoleEquipped()
  if not GetInventoryItemID then
    return true -- cannot tell: do not hold the key back
  end
  local id = GetInventoryItemID("player", MAIN_HAND)
  if not id then
    return false
  end
  local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not info then
    return true
  end
  local ok, _, _, _, _, _, classID, subclassID = pcall(info, id)
  if not ok or classID == nil then
    return true
  end
  local weapon = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
  local pole = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole) or 20
  return classID == weapon and subclassID == pole
end

local function AddonLoaded(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
    return ok and loaded and true or false
  end
  if IsAddOnLoaded then
    local ok, loaded = pcall(IsAddOnLoaded, name)
    return ok and loaded and true or false
  end
  return false
end

--- SKTools' Easy Fishing is on: SKTools loaded with SKToolsDB.fishing == true, or its standalone
--- SKEasyFishing module loaded (that one is on while installed). Informational only.
function Mod.SKToolsActive()
  local db = rawget(_G, "SKToolsDB")
  if AddonLoaded("SKEasyFishing") then
    return true
  end
  if AddonLoaded("SKTools") and type(db) == "table" and db.fishing == true then
    return true
  end
  return false
end

local function KeyText(key)
  if type(key) ~= "string" or key == "" then
    return "not set"
  end
  if GetBindingText then
    local ok, t = pcall(GetBindingText, key)
    if ok and type(t) == "string" and t ~= "" then
      return t
    end
  end
  return key
end

--- The player's own binding of a key ("" when it has none).
local function BoundTo(key)
  if not GetBindingAction or type(key) ~= "string" then
    return ""
  end
  local ok, action = pcall(GetBindingAction, key)
  if not ok or type(action) ~= "string" then
    return ""
  end
  if action ~= "" and GetBindingName then
    local okN, name = pcall(GetBindingName, action)
    if okN and type(name) == "string" and name ~= "" then
      return name
    end
  end
  return action
end

--- Normalise a key string ("alt-f" -> "ALT-F"); nil when it cannot be a fishing key.
function Mod.NormalizeKey(key)
  if type(key) ~= "string" then
    return nil
  end
  key = key:match("^%s*(.-)%s*$"):upper()
  if key == "" or key:find("%s") or key:find("[%c\"|]") then
    return nil
  end
  local mods, base = {}, key
  while true do
    local m, rest = base:match("^(%u+)%-(.+)$")
    if m == "ALT" or m == "CTRL" or m == "SHIFT" or m == "META" then
      mods[m] = true
      base = rest
    else
      break
    end
  end
  if base == "" or base:find("%-") and base ~= "-" or MODIFIERS[base] or FORBIDDEN_KEYS[base] then
    return nil
  end
  local parts = {}
  for _, m in ipairs({ "ALT", "CTRL", "SHIFT", "META" }) do
    if mods[m] then
      parts[#parts + 1] = m
    end
  end
  parts[#parts + 1] = base
  return table.concat(parts, "-")
end

-------------------------------------------------------------------------------
-- CVars of a session (changed only out of combat, put back only where still ours)
-------------------------------------------------------------------------------

local function CVarExists(cvar)
  if not GetCVar then
    return false
  end
  local ok, v = pcall(GetCVar, cvar)
  return ok and v ~= nil
end

local function Mirror()
  local cfg = Cfg()
  if next(saved) then
    local copy = {}
    for k, e in pairs(saved) do
      copy[k] = { o = e.o, s = e.s }
    end
    cfg.restore = copy
  else
    cfg.restore = nil
  end
end

local function Change(cvar, want)
  if saved[cvar] or not CVarExists(cvar) then
    return
  end
  local old = GetCVar(cvar)
  local value = want(old)
  if value == nil or tostring(value) == tostring(old) then
    return
  end
  value = tostring(value)
  if pcall(SetCVar, cvar, value) then
    saved[cvar] = { o = old, s = value }
  end
end

local function Exactly(v)
  return function()
    return v
  end
end

local function AtLeast(v)
  return function(old)
    local n = tonumber(old)
    if n and n >= v then
      return nil
    end
    return v
  end
end

--- Put back every CVar we changed (also those a crash left in the profile).
local function RestoreCVars()
  if InCombat() then
    restorePending = true
    if ev then
      pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
    end
    return
  end
  restorePending = false
  local cfg = Cfg()
  if type(cfg.restore) == "table" then
    for k, e in pairs(cfg.restore) do
      if not saved[k] and type(e) == "table" then
        saved[k] = { o = e.o, s = e.s }
      end
    end
  end
  for cvar, e in pairs(saved) do
    local okG, cur = pcall(GetCVar, cvar)
    if okG and cur ~= nil and tostring(cur) == tostring(e.s) and e.o ~= nil then
      pcall(SetCVar, cvar, e.o)
    end
    saved[cvar] = nil
  end
  Mirror()
end

local function BeginSession()
  sessionToken = sessionToken + 1
  if sessionOn or InCombat() then
    return
  end
  sessionOn = true
  local cfg = Cfg()
  if cfg.reach ~= false then
    Change("SoftTargetInteract", Exactly(3)) -- keyboard and gamepad
    Change("SoftTargetInteractRange", AtLeast(REACH))
  end
  if cfg.loud then
    Change("Sound_EnableSFX", Exactly(1))
    Change("Sound_SFXVolume", Exactly(1))
    Change("Sound_EnableSoundWhenGameIsInBG", Exactly(1))
  end
  Mirror()
end

local function EndSession()
  sessionOn = false
  RestoreCVars()
end

--- A press whose cast never started must not leave the CVars changed.
local function EndSessionLater()
  local token = sessionToken
  if C_Timer and C_Timer.After then
    C_Timer.After(CAST_WAIT, function()
      if token == sessionToken and sessionOn and not channeling then
        Safe("session timeout", EndSession)
      end
    end)
  end
end

-------------------------------------------------------------------------------
-- Frames and the binding
-------------------------------------------------------------------------------

local function LootAll()
  if not GetNumLootItems or not LootSlot then
    return
  end
  for i = (GetNumLootItems() or 0), 1, -1 do
    pcall(LootSlot, i)
  end
end

local function EnsureFrames()
  if not owner then
    owner = CreateFrame("Frame", OWNER_NAME, UIParent)
  end
  if not lootBtn then
    lootBtn = CreateFrame("Button", LOOT_BUTTON, UIParent)
    lootBtn:RegisterForClicks("AnyDown")
    lootBtn:SetScript("OnClick", function()
      Safe("loot", LootAll)
    end)
  end
  if not castBtn and not InCombat() then
    castBtn = CreateFrame("Button", CAST_BUTTON, UIParent, "SecureActionButtonTemplate")
    castBtn:RegisterForClicks("AnyDown")
    castBtn:SetAttribute("useOnKeyDown", true)
    castBtn:SetAttribute("type", "macro")
    castBtn:SetScript("PreClick", function()
      Safe("preclick", function()
        if not enabledNow or InCombat() then
          return
        end
        local castable = true
        if SecureCmdOptionParse then
          castable = SecureCmdOptionParse(CAST_CONDITIONS .. " 1") ~= nil
        end
        if castable then
          BeginSession()
          if not channeling then
            EndSessionLater()
          end
        end
      end)
    end)
  end
end

--- The cast macro, by the spell's localised name (spell data can arrive after login).
local function UpdateMacro()
  if castBtn and not InCombat() then
    local text = "/cast " .. CAST_CONDITIONS .. " " .. FishingName()
    if castBtn:GetAttribute("macrotext") ~= text then
      castBtn:SetAttribute("macrotext", text)
    end
  end
end

local function FishingLootNow()
  if IsFishingLoot then
    local ok, yes = pcall(IsFishingLoot)
    if ok and not IsSecret(yes) then
      return yes and true or false
    end
  end
  return channeling or (Now() - lastChannelEnd) <= LOOT_WINDOW
end

--- What the key should do now.
local function Wanted()
  local cfg = Cfg()
  local key = cfg.key
  if not enabledNow or type(key) ~= "string" or key == "" then
    return nil
  end
  if lootOpen then
    return "loot", key
  end
  if channeling and inReach then
    return "reel", key
  end
  if cfg.poleOnly ~= false and not PoleEquipped() then
    return nil
  end
  return "cast", key
end

local function WatchRegen()
  pending = true
  if ev then
    pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
  end
end

--- Bring the override binding in line with Wanted(); out of combat only.
local function ApplyBinding()
  local want, key = Wanted()
  if want == applied and key == appliedKey and not (want == "cast" and not castBtn) then
    pending = false
    if want == "cast" then
      UpdateMacro()
    end
    return
  end
  if InCombat() then
    WatchRegen()
    return
  end
  pending = false
  EnsureFrames()
  UpdateMacro()
  ClearOverrideBindings(owner)
  if want == "reel" then
    SetOverrideBinding(owner, true, key, "INTERACTTARGET")
  elseif want == "loot" then
    SetOverrideBindingClick(owner, true, key, LOOT_BUTTON, "LeftButton")
  elseif want == "cast" then
    SetOverrideBindingClick(owner, true, key, CAST_BUTTON, "LeftButton")
  end
  applied, appliedKey = want, want and key or nil
end

local function Rebind(context)
  Safe(context or "bind", ApplyBinding)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local function SetReach(guid)
  inReach = channeling and IsBobber(guid) or false
  Rebind("reach")
end

local function OnEvent(_, event, ...)
  if event == "UNIT_SPELLCAST_CHANNEL_START" then
    local unit, _, spellID = ...
    if unit == "player" and IsFishingChannel(spellID) then
      channeling = true
      inReach = false
      BeginSession()
      pcall(ev.RegisterEvent, ev, "PLAYER_SOFT_INTERACT_CHANGED")
      SetReach(SoftInteractGUID())
    end
  elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
    local unit, _, spellID = ...
    if unit == "player" and channeling and (IsFishingChannel(spellID) or IsSecret(spellID)) then
      channeling, inReach = false, false
      lastChannelEnd = Now()
      pcall(ev.UnregisterEvent, ev, "PLAYER_SOFT_INTERACT_CHANGED")
      Rebind("channel stop")
      EndSession()
    end
  elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
    if channeling then
      local _, newTarget = ...
      SetReach(newTarget)
    end
  elseif event == "LOOT_OPENED" then
    local autoLoot = ...
    if autoLoot == true or autoLoot == 1 then
      return
    end
    if FishingLootNow() then
      lootOpen = true
      Rebind("loot opened")
    end
  elseif event == "LOOT_CLOSED" then
    if lootOpen then
      lootOpen = false
      Rebind("loot closed")
    end
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    local slot = ...
    if slot == MAIN_HAND then
      Rebind("equipment")
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if restorePending then
      RestoreCVars()
    end
    if pending then
      Rebind("regen")
    end
    if not pending and not restorePending then
      pcall(ev.UnregisterEvent, ev, "PLAYER_REGEN_ENABLED")
    end
  elseif event == "PLAYER_LOGOUT" then
    sessionOn = false
    restorePending = false
    for cvar, e in pairs(saved) do
      local okG, cur = pcall(GetCVar, cvar)
      if okG and cur ~= nil and tostring(cur) == tostring(e.s) and e.o ~= nil then
        pcall(SetCVar, cvar, e.o)
      end
      saved[cvar] = nil
    end
    Mirror()
  end
end

local ACTIVE_EVENTS = { "LOOT_OPENED", "LOOT_CLOSED", "PLAYER_EQUIPMENT_CHANGED" }

local function SetActive(on)
  if on == enabledNow then
    return
  end
  enabledNow = on
  if on then
    for _, e in ipairs(ACTIVE_EVENTS) do
      pcall(ev.RegisterEvent, ev, e)
    end
    if ev.RegisterUnitEvent then
      pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_CHANNEL_START", "player")
      pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
    else
      pcall(ev.RegisterEvent, ev, "UNIT_SPELLCAST_CHANNEL_START")
      pcall(ev.RegisterEvent, ev, "UNIT_SPELLCAST_CHANNEL_STOP")
    end
  else
    for _, e in ipairs(ACTIVE_EVENTS) do
      pcall(ev.UnregisterEvent, ev, e)
    end
    pcall(ev.UnregisterEvent, ev, "UNIT_SPELLCAST_CHANNEL_START")
    pcall(ev.UnregisterEvent, ev, "UNIT_SPELLCAST_CHANNEL_STOP")
    pcall(ev.UnregisterEvent, ev, "PLAYER_SOFT_INTERACT_CHANGED")
    channeling, inReach, lootOpen = false, false, false
    if sessionOn or next(saved) then
      EndSession()
    end
  end
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

function Mod.Apply()
  if not started then
    return
  end
  Safe("apply", function()
    local cfg = Cfg()
    -- events only while there is something to do: switched on and a key chosen
    SetActive(cfg.enabled and type(cfg.key) == "string" and cfg.key ~= "" or false)
    if not cfg.enabled and (sessionOn or next(saved) or type(cfg.restore) == "table") then
      EndSession()
    end
    ApplyBinding()
  end)
end

function Mod.Start()
  if started then
    return
  end
  started = true
  ev = CreateFrame("Frame")
  ev:SetScript("OnEvent", function(self, event, ...)
    local ok, err = pcall(OnEvent, self, event, ...)
    if not ok then
      Err(event, err)
    end
  end)
  pcall(ev.RegisterEvent, ev, "PLAYER_LOGOUT")
  -- a crash or Alt-F4 mid-session left changed CVars in the profile: put them back
  if type(Cfg().restore) == "table" then
    Safe("restore at login", RestoreCVars)
  end
  if not InCombat() then
    Safe("frames", function()
      EnsureFrames()
      UpdateMacro()
    end)
  end
  Mod.Apply()
end

--- Save a fishing key (nil clears it). Returns the stored key, or nil and a reason.
function Mod.SetKey(key)
  local cfg = Cfg()
  if key == nil then
    cfg.key = nil
  else
    local norm = Mod.NormalizeKey(key)
    if not norm then
      return nil, "not a usable key: " .. tostring(key)
    end
    cfg.key = norm
  end
  Mod.Apply()
  RefreshSettings()
  return cfg.key
end

function Mod.SetEnabled(on)
  Cfg().enabled = on and true or false
  Mod.Apply()
  RefreshSettings()
end

function Mod.Status()
  local cfg = Cfg()
  local parts = {
    "enabled=" .. tostring(cfg.enabled and true or false),
    "key=" .. (cfg.key or "none"),
    "bound=" .. (applied or "nothing"),
  }
  if pending then
    parts[#parts + 1] = "pending=after combat"
  end
  if channeling then
    parts[#parts + 1] = inReach and "bobber=in reach" or "bobber=searching"
  end
  if sessionOn then
    parts[#parts + 1] = "session=on"
  end
  if cfg.poleOnly ~= false and cfg.key and cfg.enabled and not PoleEquipped() then
    parts[#parts + 1] = "waiting for a fishing pole"
  end
  if Mod.SKToolsActive() then
    parts[#parts + 1] = "note: another addon with its own fishing key is active and may conflict (turn its fishing off)"
  end
  return table.concat(parts, " ")
end

local HELP = {
  "/wf fish on|off - switch one-key fishing",
  "/wf fish key - show the fishing key; /wf fish key <KEY> - set it (e.g. F, ALT-F, BUTTON4)",
  "/wf fish clear - remove the key (the override is released)",
  "/wf fish status - state of the module",
}

function Mod.Slash(rest)
  rest = (rest or ""):match("^%s*(.-)%s*$") or ""
  local cmd, arg = rest:match("^(%S+)%s*(.*)$")
  cmd = (cmd or ""):lower()
  if cmd == "" or cmd == "help" or cmd == "?" then
    for _, line in ipairs(HELP) do
      Print(line)
    end
  elseif cmd == "on" or cmd == "off" then
    Mod.SetEnabled(cmd == "on")
    Print("fishing: " .. (cmd == "on" and "on" or "off") .. (pending and " (applied after combat)" or ""))
  elseif cmd == "key" then
    if arg == nil or arg == "" then
      Print("fishing key: " .. KeyText(Cfg().key))
    else
      local key, why = Mod.SetKey(arg)
      if key then
        local bound = BoundTo(key)
        Print("fishing key: " .. KeyText(key) .. (pending and " (applied after combat)" or "")
          .. (bound ~= "" and (" - overrides your binding '" .. bound .. "' while fishing is on") or ""))
      else
        Print(why)
      end
    end
  elseif cmd == "clear" then
    Mod.SetKey(nil)
    Print("fishing key cleared" .. (pending and " (released after combat)" or ""))
  elseif cmd == "status" then
    Print("fishing: " .. Mod.Status())
  else
    Print("usage: /wf fish on|off|key [KEY]|clear|status")
  end
end

-------------------------------------------------------------------------------
-- Settings section
-------------------------------------------------------------------------------

local capFrame, capOnKey

--- A full-screen frame that takes the next key while a key is being picked (shown only then).
local function CaptureFrame()
  if capFrame then
    return capFrame
  end
  capFrame = CreateFrame("Frame", nil, UIParent)
  capFrame:SetFrameStrata("TOOLTIP")
  capFrame:SetAllPoints(UIParent)
  capFrame:EnableMouse(false)
  capFrame:Hide()
  capFrame:SetScript("OnKeyDown", function(_, key)
    if capOnKey then
      Safe("capture", capOnKey, key)
    end
  end)
  pcall(capFrame.EnableKeyboard, capFrame, true)
  return capFrame
end

local function Chord(key)
  if type(key) ~= "string" or key == "" or MODIFIERS[key] then
    return nil
  end
  local parts = {}
  if IsAltKeyDown and IsAltKeyDown() then
    parts[#parts + 1] = "ALT"
  end
  if IsControlKeyDown and IsControlKeyDown() then
    parts[#parts + 1] = "CTRL"
  end
  if IsShiftKeyDown and IsShiftKeyDown() then
    parts[#parts + 1] = "SHIFT"
  end
  if IsMetaKeyDown and IsMetaKeyDown() then
    parts[#parts + 1] = "META"
  end
  parts[#parts + 1] = key
  return table.concat(parts, "-")
end

function Mod.BuildSettings(sec, H)
  local y = 0
  H.Heading(sec, "One-key fishing", y)
  y = y - 30
  H.Check(sec, "Fish with one key", y, function()
    return Cfg().enabled
  end, function(on)
    Mod.SetEnabled(on)
  end)
  y = y - 32

  local label = sec:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", 18, y)
  label:SetText("Fishing key")
  local btn = CreateFrame("Button", nil, sec, "UIPanelButtonTemplate")
  btn:SetSize(150, 22)
  btn:SetPoint("TOPLEFT", 110, y + 4)
  btn:RegisterForClicks("AnyUp")
  local clear = CreateFrame("Button", nil, sec, "UIPanelButtonTemplate")
  clear:SetSize(70, 22)
  clear:SetPoint("LEFT", btn, "RIGHT", 8, 0)
  clear:SetText("Clear")
  y = y - 26
  local keyNote = H.Note(sec, "", y)
  keyNote:SetTextColor(0.85, 0.7, 0.3)

  local capturing = false
  local function Show()
    btn:SetText(capturing and "Press a key..." or KeyText(Cfg().key))
    clear:SetEnabled(Cfg().key ~= nil and not capturing)
    local key = Cfg().key
    local text = ""
    if capturing then
      text = "Press a key or a middle / side mouse button. Escape or a left / right click cancels."
    elseif key then
      local bound = BoundTo(key)
      if bound ~= "" then
        text = "This key is also bound to " .. bound .. ". Wayfarer overrides it while fishing is on; your own binding is not changed."
      end
      if pending then
        text = (text ~= "" and (text .. " ") or "") .. "The change is applied after combat."
      end
    end
    keyNote:SetText(text)
  end
  local function Stop()
    if not capturing then
      return
    end
    capturing = false
    capOnKey = nil
    if capFrame then
      capFrame:Hide()
    end
    Show()
  end
  local function Take(key)
    Stop()
    local stored, why = Mod.SetKey(key)
    if not stored and why then
      Print(why)
    end
    Show()
  end
  btn:SetScript("OnClick", function(_, button)
    Safe("key button", function()
      if capturing then
        local mk = MOUSE_KEYS[button]
        if mk then
          Take(Chord(mk))
        else
          Stop()
        end
        return
      end
      if button ~= "LeftButton" then
        return
      end
      if InCombat() then
        Print("leave combat to pick a fishing key")
        return
      end
      capturing = true
      capOnKey = function(key)
        if key == "ESCAPE" then
          Stop()
          return
        end
        local chord = Chord(key)
        if chord then
          Take(chord)
        end
      end
      CaptureFrame():Show()
      Show()
    end)
  end)
  btn:SetScript("OnHide", function()
    Safe("key button hide", Stop)
  end)
  clear:SetScript("OnClick", function()
    Safe("key clear", function()
      Stop()
      Mod.SetKey(nil)
      Show()
    end)
  end)
  H.Register(Show)
  Show()
  y = y - 30

  H.Check(sec, "Only while a fishing pole is equipped", y, function()
    return Cfg().poleOnly ~= false
  end, function(on)
    Cfg().poleOnly = on
    Mod.Apply()
  end)
  y = y - 28
  H.Check(sec, "Reach the bobber with the key (interact range while fishing)", y, function()
    return Cfg().reach ~= false
  end, function(on)
    Cfg().reach = on
  end)
  y = y - 28
  H.Check(sec, "Louder splash (sound effects at full volume while fishing)", y, function()
    return Cfg().loud and true or false
  end, function(on)
    Cfg().loud = on
  end)
  y = y - 34
  H.Note(sec, "Press the key to cast. When you see or hear the splash, press it again to reel in; with Auto Loot off, the next press takes the loot. One press is always one action: Wayfarer never hooks the fish for you. Changed sound and interact settings are put back when the cast ends.", y)
  y = y - 56
  local skNote = H.Note(sec, "", y)
  skNote:SetTextColor(1, 0.55, 0.2)
  H.Register(function()
    skNote:SetText(Mod.SKToolsActive() and "Another addon with its own one-key fishing is active. Both would take a fishing key and may conflict; turn the other one off to use this one." or "")
  end)
  y = y - 30
  return -y + 40
end
