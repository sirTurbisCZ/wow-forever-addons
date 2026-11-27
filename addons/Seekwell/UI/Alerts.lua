--[[
  Seekwell.Alerts — wishlist "hunt mode".
  Wanted mob: a mob that drops a wished item (or one added with /sw alert mob) becomes the target,
  the mouseover or (optional) shows a nameplate -> one toast, throttled per npc.
  Wanted drop: a wished item in the loot window / own loot message -> "Got <item>" (optionally
  removed from the wishlist). Own non-secure frames only, events registered only while enabled.
]]

Seekwell = Seekwell or {}
local A = {}
Seekwell.Alerts = A

local STAR = "|TInterface\\Common\\ReputationStar:14:14:0:0:32:32:0:16:0:16|t"
local TOAST_SECONDS = 4
local MAX_LIST = 12

local function S()
  local s = Seekwell.Config.Get()
  if type(s.alerts) ~= "table" then
    s.alerts = {}
    Seekwell.Config.Fill(s.alerts, Seekwell.Config.SettingsDefaults().alerts)
  end
  return s.alerts
end
A.Settings = S

--- pcall boundary; Seekwell.Safe / RecordError live in Core.lua, which loads after this file.
local function Safe(context, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok and Seekwell.RecordError then
      Seekwell.RecordError(context, err)
    end
  end
end

local function Sec()
  return Seekwell.Secret
end

local function Print(...)
  if Seekwell.Print then
    Seekwell.Print(...)
  end
end

local function Now()
  local t = Sec().Get(GetTime)
  return tonumber(t) or 0
end

local function WishMobs()
  local c = Seekwell.Config.Char()
  if type(c.wishMobs) ~= "table" then
    c.wishMobs = {}
  end
  return c.wishMobs
end

-- reverse index npc -> { {item, p}, ... } (best chance first) ---------------------------------
local index, indexKey, indexLearnedGen, indexTime
local mobsGen = 0
local LEARNED_REFRESH = 120 -- seconds between rebuilds caused by newly learned data only

local function IndexKey()
  local W, Ld = Seekwell.Wish, Seekwell.Learned
  -- Learned.generation is deliberately not part of the key: it changes with every loot, and rebuilding the
  -- index (item sources of every wished item) right while the loot window opens made looting lag. New learned
  -- data is picked up by the timed refresh in A.WantedItems instead.
  return table.concat({ tostring(W.generation or 0), tostring(W.Count()), tostring(Seekwell.Config.Get().classic and 1 or 0) }, ":")
end

local function BuildIndex()
  local idx = {}
  for _, it in ipairs(Seekwell.Wish.Active()) do
    local ok, rows = pcall(Seekwell.Registry.ItemSources, it.id, 10)
    if ok and type(rows) == "table" then
      for _, r in ipairs(rows) do
        local npc = tonumber(r.npc)
        if npc then
          local e = idx[npc]
          if not e then
            e = {}
            idx[npc] = e
          end
          e[#e + 1] = { item = it.id, p = r.p }
        end
      end
    end
  end
  for _, e in pairs(idx) do
    table.sort(e, function(a, b)
      if (a.p or -1) ~= (b.p or -1) then
        return (a.p or -1) > (b.p or -1)
      end
      return a.item < b.item
    end)
  end
  return idx
end

--- Wished items dropped by npcID, or nil. Built lazily, rebuilt when the wishlist or data changed.
function A.WantedItems(npcID)
  local key = IndexKey()
  local lg = Seekwell.Learned and Seekwell.Learned.generation or 0
  local now = (GetTime and GetTime()) or 0
  local stale = index and lg ~= indexLearnedGen and now - (indexTime or 0) > LEARNED_REFRESH
    and not (InCombatLockdown and InCombatLockdown())
  if not index or key ~= indexKey or stale then
    index, indexKey, indexLearnedGen, indexTime = BuildIndex(), key, lg, now
  end
  return index[tonumber(npcID) or -1]
end

function A.Invalidate()
  index, indexKey, indexLearnedGen, indexTime = nil, nil, nil, nil
end

-- toast ------------------------------------------------------------------------------------
local toast, toastToken = nil, 0

local function HideToast()
  if toast then
    toast:Hide()
  end
end

local function EnsureToast()
  if toast then
    return toast
  end
  local f = CreateFrame("Frame", "SeekwellAlertToast", UIParent)
  f:SetSize(460, 34)
  f:SetPoint("TOP", UIParent, "TOP", 0, -150)
  f:SetFrameStrata("HIGH")
  f:EnableMouse(false) -- click-through
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.6)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetPoint("CENTER")
  fs:SetWidth(450)
  f.text = fs
  local okA, ag = pcall(f.CreateAnimationGroup, f)
  if okA and ag then
    local okF = pcall(function()
      local fade = ag:CreateAnimation("Alpha")
      fade:SetFromAlpha(1)
      fade:SetToAlpha(0)
      fade:SetStartDelay(TOAST_SECONDS - 1)
      fade:SetDuration(1)
      ag:SetScript("OnFinished", HideToast)
    end)
    if okF then
      f.anim = ag
    end
  end
  f:Hide()
  toast = f
  return f
end

local function PlayAlertSound()
  if not S().sound or type(PlaySound) ~= "function" then
    return
  end
  local kit = (type(SOUNDKIT) == "table" and tonumber(SOUNDKIT.RAID_WARNING)) or 8959
  pcall(PlaySound, kit, "Master")
end

--- Show the toast text (also used by the test button).
function A.Show(text)
  local f = EnsureToast()
  f.text:SetText(text)
  f:SetAlpha(1)
  f:Show()
  toastToken = toastToken + 1
  if f.anim then
    f.anim:Stop()
    f.anim:Play()
  elseif C_Timer and C_Timer.After then
    local token = toastToken
    C_Timer.After(TOAST_SECONDS, function()
      if token == toastToken then
        HideToast()
      end
    end)
  end
  PlayAlertSound()
  A.last = text
end

local function ItemText(itemID)
  local Sx = Sec()
  if C_Item and C_Item.GetItemInfo then
    local ok, name, link = pcall(C_Item.GetItemInfo, itemID)
    if ok then
      link, name = Sx.Str(link), Sx.Str(name)
      if link then
        return link
      end
      if name then
        return name
      end
    end
    if C_Item.RequestLoadItemDataByID then
      pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
  end
  return "item " .. tostring(itemID)
end
A.ItemText = ItemText

-- wanted mob -------------------------------------------------------------------------------
local lastSeen, lastCount = {}, 0

local function Throttled(npcID)
  local now = Now()
  local t = lastSeen[npcID]
  local gap = tonumber(S().throttleSec) or 60
  if t and now - t < gap then
    return true
  end
  if lastCount >= 200 then
    lastSeen, lastCount = {}, 0
  end
  if not t then
    lastCount = lastCount + 1
  end
  lastSeen[npcID] = now
  return false
end

function A.ResetThrottle()
  lastSeen, lastCount = {}, 0
end

--- Alert text for npcID or nil when it is not wanted.
function A.MobText(npcID, name)
  local items = A.WantedItems(npcID)
  local explicit = WishMobs()[npcID]
  if not items and not explicit then
    return nil
  end
  name = name or (Seekwell.Registry.NpcName and Seekwell.Registry.NpcName(npcID)) or ("npc " .. npcID)
  if not items then
    return STAR .. " Wanted: " .. name
  end
  local top = items[1]
  local text = STAR .. " Wanted: " .. name .. " drops " .. ItemText(top.item)
  if top.p then
    text = text .. " (" .. Seekwell.Registry.FormatPct(top.p) .. ")"
  end
  if #items > 1 then
    text = text .. " +" .. (#items - 1) .. " more"
  end
  return text
end

function A.CheckUnit(unit)
  local s = S()
  if not s.enabled or not s.wantedMob or type(unit) ~= "string" then
    return
  end
  local Sx = Sec()
  if not Sx.Get(UnitExists, unit) then
    return
  end
  if Sx.Get(UnitIsPlayer, unit) or Sx.Get(UnitPlayerControlled, unit) or Sx.Get(UnitIsDead, unit) then
    return
  end
  local okG, guid = pcall(UnitGUID, unit)
  if not okG or Sx.GUIDKind(guid) ~= "creature" then
    return -- also secret GUIDs
  end
  local npcID = Sx.NpcIDFromGUID(guid)
  if not npcID then
    return
  end
  if not A.WantedItems(npcID) and not WishMobs()[npcID] then
    return
  end
  if Throttled(npcID) then
    return
  end
  local text = A.MobText(npcID, Sx.Str(Sx.Get(UnitName, unit)))
  if text then
    A.Show(text)
  end
end

-- wanted drop ------------------------------------------------------------------------------
local recentGot = {}

local function GotItem(itemID, link)
  if not itemID or not Seekwell.Wish.Has(itemID) then
    return
  end
  local now = Now()
  if recentGot[itemID] and now - recentGot[itemID] < 10 then
    return
  end
  recentGot[itemID] = now
  local text = STAR .. " Got " .. (link or ItemText(itemID))
  if S().removeOnLoot then
    Seekwell.Wish.Remove(itemID)
    text = text .. " (removed from wishlist)"
    if Seekwell.Window and Seekwell.Window.Refresh then
      pcall(Seekwell.Window.Refresh)
    end
  end
  A.Show(text)
end
A.GotItem = GotItem

function A.OnLootOpened()
  local Sx = Sec()
  local n = tonumber(Sx.Get(GetNumLootItems)) or 0
  for slot = 1, n do
    local link = Sx.Str(Sx.Get(GetLootSlotLink, slot))
    local itemID = link and Sx.ItemIDFromLink(link)
    if itemID then
      GotItem(itemID, link)
    end
  end
end

local selfPrefixes
local function SelfPrefixes()
  if selfPrefixes then
    return selfPrefixes
  end
  local out = {}
  for _, g in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }) do
    local v = Sec().Str(_G[g])
    local pre = v and v:match("^(.-)%%s")
    if pre and pre ~= "" then
      out[#out + 1] = pre
    end
  end
  if #out == 0 then
    out[1] = "You receive loot: "
    out[2] = "You receive item: "
  end
  selfPrefixes = out
  return out
end

function A.OnChatLoot(msg)
  msg = Sec().Str(msg)
  if not msg then
    return
  end
  for _, pre in ipairs(SelfPrefixes()) do
    if msg:find(pre, 1, true) == 1 then
      GotItem(Sec().ItemIDFromLink(msg))
      return
    end
  end
end

-- events -----------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", Safe("alerts.event", function(_, event, arg1)
  if event == "PLAYER_TARGET_CHANGED" then
    A.CheckUnit("target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    A.CheckUnit("mouseover")
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    A.CheckUnit(arg1)
  elseif event == "CHAT_MSG_LOOT" then
    A.OnChatLoot(arg1)
  end
end))
A.frame = ev

local function Reg(e)
  pcall(ev.RegisterEvent, ev, e)
end

--- (Re)register events from the settings; nothing is registered while alerts are off.
function A.Apply()
  ev:UnregisterAllEvents()
  local s = S()
  if not s.enabled then
    HideToast()
    return
  end
  if s.wantedMob then
    Reg("PLAYER_TARGET_CHANGED")
    Reg("UPDATE_MOUSEOVER_UNIT")
    if s.nameplates then
      Reg("NAME_PLATE_UNIT_ADDED")
    end
  end
  if s.wantedDrop then
    Reg("CHAT_MSG_LOOT")
  end
end

local function MobCount()
  local n = 0
  for _ in pairs(WishMobs()) do
    n = n + 1
  end
  return n
end

function A.Status()
  local s = S()
  local parts = { s.enabled and "on" or "off" }
  parts[#parts + 1] = "mob " .. (s.wantedMob and "on" or "off")
  parts[#parts + 1] = "drop " .. (s.wantedDrop and "on" or "off")
  parts[#parts + 1] = "nameplates " .. (s.nameplates and "on" or "off")
  parts[#parts + 1] = "sound " .. (s.sound and "on" or "off")
  parts[#parts + 1] = "remove on loot " .. (s.removeOnLoot and "on" or "off")
  parts[#parts + 1] = "throttle " .. tostring(tonumber(s.throttleSec) or 60) .. " s"
  parts[#parts + 1] = MobCount() .. " wanted mob(s)"
  return table.concat(parts, " · ")
end

-- wanted mobs list -------------------------------------------------------------------------
local refreshList -- set by the window section

local function ListChanged()
  mobsGen = mobsGen + 1
  if refreshList then
    pcall(refreshList)
  end
  if Seekwell.Window and Seekwell.Window.Refresh then
    pcall(Seekwell.Window.Refresh)
  end
end

local function TargetNpc()
  local Sx = Sec()
  if not Sx.Get(UnitExists, "target") then
    return nil, "no target"
  end
  local okG, guid = pcall(UnitGUID, "target")
  local kind = Sx.GUIDKind(okG and guid or nil)
  if kind == "secret" then
    return nil, "the game hides this unit's identity"
  end
  local npc = Sx.NpcIDFromGUID(okG and guid or nil)
  if not npc then
    return nil, "target is not a creature"
  end
  return npc, Sx.Str(Sx.Get(UnitName, "target"))
end

local function MobName(npcID)
  return (Seekwell.Registry.NpcName and Seekwell.Registry.NpcName(npcID)) or ("npc " .. npcID)
end

function A.AddMob(npcID)
  npcID = tonumber(npcID)
  if not npcID or npcID <= 0 then
    return false
  end
  WishMobs()[npcID] = true
  ListChanged()
  return true
end

function A.RemoveMob(npcID)
  npcID = tonumber(npcID)
  if not npcID or not WishMobs()[npcID] then
    return false
  end
  WishMobs()[npcID] = nil
  lastSeen[npcID] = nil
  ListChanged()
  return true
end

function A.Mobs()
  local out = {}
  for id in pairs(WishMobs()) do
    out[#out + 1] = id
  end
  table.sort(out)
  return out
end

local function ResolveNpc(arg)
  if arg == "target" or arg == "" or arg == nil then
    return TargetNpc()
  end
  local id = tonumber(arg)
  if not id then
    return nil, "not an npc id: " .. tostring(arg)
  end
  return id
end

local USAGE = "usage: /sw alert on|off|test|status|nameplates on|off|sound on|off|remove on|off|mob add|del <npcID|target>|mob list"

local function Toggle(key, val, label)
  if val ~= "on" and val ~= "off" then
    Print(USAGE)
    return
  end
  S()[key] = val == "on"
  A.Apply()
  Print("alerts: " .. label .. " " .. val)
  if Seekwell.Window and Seekwell.Window.Refresh then
    pcall(Seekwell.Window.Refresh)
  end
end

local function Slash(rest)
  rest = (rest or ""):match("^%s*(.-)%s*$") or ""
  local cmd, arg = rest:match("^(%S+)%s*(.*)$")
  cmd = cmd or ""
  if cmd == "on" or cmd == "off" then
    Toggle("enabled", cmd, "alerts")
  elseif cmd == "test" then
    A.Show(STAR .. " Wanted: Test Mob drops " .. ItemText(2589) .. " (12.5 %)")
  elseif cmd == "status" or cmd == "" then
    Print("alerts: " .. A.Status())
  elseif cmd == "nameplates" then
    Toggle("nameplates", arg, "nameplates")
  elseif cmd == "sound" then
    Toggle("sound", arg, "sound")
  elseif cmd == "remove" then
    Toggle("removeOnLoot", arg, "remove from wishlist when looted")
  elseif cmd == "mob" then
    local sub, a2 = arg:match("^(%S*)%s*(.*)$")
    if sub == "list" then
      local ids = A.Mobs()
      if #ids == 0 then
        Print("alerts: no wanted mobs (add one with /sw alert mob add target)")
      end
      for _, id in ipairs(ids) do
        Print("  " .. id .. "  " .. MobName(id))
      end
    elseif sub == "del" or sub == "remove" then
      local id, err = ResolveNpc(a2)
      if not id then
        Print("alerts: " .. tostring(err))
      elseif A.RemoveMob(id) then
        Print("alerts: removed wanted mob " .. id)
      else
        Print("alerts: " .. id .. " is not on the list")
      end
    else
      local target = sub
      if sub == "add" then
        target = a2
      end
      local id, nameOrErr = ResolveNpc(target)
      if not id then
        Print("alerts: " .. tostring(nameOrErr))
      else
        A.AddMob(id)
        Print("alerts: wanted mob " .. id .. " " .. (nameOrErr or MobName(id)))
      end
    end
  else
    Print(USAGE)
  end
end
A.Slash = Slash

-- window section ---------------------------------------------------------------------------
local function Build(sec, H)
  local y = -10
  H.Heading(sec, "Alerts", y)
  y = y - 26
  H.Note(sec, "Hunt mode: a toast when a mob that drops an item of your wishlist is your target or under the mouse, and when a wished item drops.", y)
  y = y - 34
  local function Opt(label, key)
    H.Check(sec, label, y, function()
      return S()[key]
    end, function(v)
      S()[key] = v
      A.Apply()
    end)
    y = y - 26
  end
  Opt("Alerts on", "enabled")
  Opt("Wanted mob: target / mouseover", "wantedMob")
  Opt("Also nameplates (more events)", "nameplates")
  Opt("Wanted drop: \"Got <item>\"", "wantedDrop")
  Opt("Remove from wishlist when looted", "removeOnLoot")
  Opt("Play a sound", "sound")
  y = y - 8
  H.Slider(sec, "Once per mob every (s)", y, 10, 300, function()
    return tonumber(S().throttleSec) or 60
  end, function(v)
    S().throttleSec = v
  end)
  y = y - 44
  H.Button(sec, "Test alert", 14, y, 120, function()
    Slash("test")
  end)
  H.Button(sec, "Add target", 140, y, 120, function()
    Slash("mob add target")
  end)
  y = y - 32
  H.Heading(sec, "Wanted mobs", y)
  y = y - 24
  local empty = H.Note(sec, "None. Target a mob and click \"Add target\", or /sw alert mob <npcID|target>.", y)
  local rows = {}
  for i = 1, MAX_LIST do
    local ry = y - (i - 1) * 24
    local fs = sec:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 18, ry - 4)
    local b = H.Button(sec, "Remove", 300, ry, 80, function(self)
      local id = self and self.npcID
      if id then
        A.RemoveMob(id)
      end
    end)
    fs:Hide()
    b:Hide()
    rows[i] = { fs = fs, b = b }
  end
  local more = H.Note(sec, "", y - MAX_LIST * 24)
  refreshList = function()
    local ids = A.Mobs()
    empty:SetShown(#ids == 0)
    for i = 1, MAX_LIST do
      local r, id = rows[i], ids[i]
      if id then
        r.fs:SetText(id .. "  " .. MobName(id))
        r.b.npcID = id
        r.fs:Show()
        r.b:Show()
      else
        r.b.npcID = nil
        r.fs:Hide()
        r.b:Hide()
      end
    end
    more:SetText(#ids > MAX_LIST and ("+" .. (#ids - MAX_LIST) .. " more (/sw alert mob list)") or "")
  end
  if sec.HookScript then
    sec:HookScript("OnShow", Safe("alerts.list", refreshList))
  end
  pcall(refreshList)
  return -(y - MAX_LIST * 24) + 30
end

if Seekwell.Window and Seekwell.Window.RegisterSection then
  Seekwell.Window.RegisterSection({ id = "alerts", label = "Alerts", build = Build })
end
-- Core.lua (with RegisterSlash / RegisterStart / RegisterStatus) loads after this file: hook in at ADDON_LOADED.
local hooked = false
local function Hook()
  if hooked or not Seekwell.RegisterSlash then
    return
  end
  hooked = true
  Seekwell.RegisterSlash("alert", Slash)
  Seekwell.RegisterSlash("alerts", Slash)
  Seekwell.RegisterStart("alerts", A.Apply)
  Seekwell.RegisterStatus("alerts", A.Status)
end
A.Hook = Hook
Hook()
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", Safe("alerts.load", function(self)
  Hook()
  if hooked then
    self:UnregisterAllEvents()
  end
end))
