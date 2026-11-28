--[[
  Seekwell.Share — opt-in sharing of learned drop data with party / raid / guild (default OFF).
  Wire format (addon prefix "SWKL"): "v1|npcID|kills|itemID:drops,itemID:drops,..." (<= 240 bytes, split by items).
  Each part carries the sender's cumulative totals for that npc, so the receiver REPLACES the sender's
  contribution (idempotent) instead of adding to it. Received data lives in SeekwellDB.shared, never in learned.
  Nothing is registered, sent or received while settings.share is off.
]]

Seekwell = Seekwell or {}
local Share = {}
Seekwell.Share = Share

local PREFIX = "SWKL"
local VERSION_TAG = "v1"
local MAX_MSG = 240
local MAX_ITEMS = 40          -- items per message and per sender contribution
local MAX_ID = 10000000
local MAX_KILLS = 10000
local MAX_SENDERS = 20        -- per npc
local MAX_NPCS = 5000
local MAX_UNION = 60          -- items kept per shared npc
local MIN_KILLS = 5           -- shared data counts only from this many kills
local DAY = 86400
local SEND_GAP = 3            -- seconds between messages
local SEND_PER_MIN = 20
local QUEUE_MAX = 60
local RECV_PER_MIN = 30       -- per sender
local RECV_TOTAL_PER_MIN = 300
local SENDER_TRACK_MAX = 200

Share.PREFIX = PREFIX
Share.MIN_KILLS = MIN_KILLS

local stats = { sent = 0, received = 0, rejected = 0, ignored = 0 } -- memory only
local frame, prefixOK, available = nil, false, nil
local queue = {}              -- { {npc = id, msg = "..."} }
local dirty, dirtyOrder = {}, {}
local pumping = false
local sentTimes = {}          -- GetTime() of recent sends (<= SEND_PER_MIN)
local lastSend = -1000
local senders, senderCount = {}, 0 -- [sender] = { t0, n }
local totalWin = { t0 = -1000, n = 0 }
local hooked = false

local function Sec()
  return Seekwell.Secret
end

local function Settings()
  return Seekwell.Config.Get()
end

local function Now()
  return (GetTime and tonumber(GetTime())) or 0
end

local function Epoch()
  return (time and tonumber(time())) or 0
end

local function Print(msg)
  if Seekwell.Print then
    Seekwell.Print(msg)
  end
end

local function Record(ctx, err)
  if Seekwell.RecordError then
    Seekwell.RecordError(ctx, err)
  end
end

local function Enabled()
  local ok, s = pcall(Settings)
  return ok and s and s.share == true
end
Share.Enabled = Enabled

local function Channels()
  local c = Settings().shareChannels
  if type(c) ~= "table" then
    c = { party = true, guild = true }
    Settings().shareChannels = c
  end
  return c
end

--- Shared store (created lazily, only when data is received).
local function Store(create)
  local db = SeekwellDB
  if type(db) ~= "table" then
    return nil
  end
  if type(db.shared) ~= "table" or type(db.shared.npc) ~= "table" then
    if not create then
      return nil
    end
    db.shared = { npc = {}, count = 0 }
  end
  return db.shared
end

local function BumpCaches()
  if Seekwell.Registry and Seekwell.Registry.ClearCache then
    pcall(Seekwell.Registry.ClearCache)
  end
end

--- Is the C_ChatInfo addon-message API there?
function Share.Available()
  if available == nil then
    available = type(C_ChatInfo) == "table" and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function"
      and type(C_ChatInfo.SendAddonMessage) == "function"
  end
  return available
end

local function RegisterPrefix()
  if prefixOK then
    return true
  end
  if not Share.Available() then
    return false
  end
  local ok, res = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  -- returns true / Enum.RegisterAddonMessagePrefixResult.Success (0) / AlreadyRegistered (1)
  prefixOK = ok and (res == nil or res == true or res == 0 or res == 1)
  return prefixOK
end

-- Sending -------------------------------------------------------------------

--- Messages for one npc's cumulative totals: list of strings, each <= MAX_MSG bytes.
function Share.BuildMessages(npcID, kills, items)
  npcID, kills = tonumber(npcID), tonumber(kills)
  if not npcID or npcID < 1 or npcID > MAX_ID or npcID ~= math.floor(npcID) then
    return {}
  end
  if not kills or kills < 1 then
    return {}
  end
  kills = math.min(MAX_KILLS, math.floor(kills))
  local list = {}
  for rawID, rawD in pairs(items or {}) do
    local itemID, d = tonumber(rawID), tonumber(rawD)
    if itemID and d and itemID >= 1 and itemID <= MAX_ID and itemID == math.floor(itemID) and d >= 1 then
      list[#list + 1] = { id = itemID, d = math.min(kills, math.floor(d)) }
    end
  end
  table.sort(list, function(a, b)
    if a.d ~= b.d then
      return a.d > b.d
    end
    return a.id < b.id
  end)
  local head = VERSION_TAG .. "|" .. npcID .. "|" .. kills .. "|"
  local out, cur, n = {}, {}, 0
  local len = #head
  for i = 1, math.min(MAX_ITEMS, #list) do
    local tok = list[i].id .. ":" .. list[i].d
    local add = #tok + (n > 0 and 1 or 0)
    if n > 0 and len + add > MAX_MSG then
      out[#out + 1] = head .. table.concat(cur, ",")
      cur, n, len = {}, 0, #head
      add = #tok
    end
    n = n + 1
    cur[n] = tok
    len = len + add
  end
  out[#out + 1] = head .. table.concat(cur, ",") -- also a kills-only message when nothing dropped
  return out
end

local function InCombat()
  local Get = Sec().Get
  if InCombatLockdown and Get(InCombatLockdown) then
    return true
  end
  if UnitAffectingCombat and Get(UnitAffectingCombat, "player") then
    return true
  end
  return false
end

--- Targets right now: list of chat types. Nothing inside instances (addon-comm restrictions) or instance groups.
local function Targets()
  local Get = Sec().Get
  local out = {}
  if IsInInstance and Get(IsInInstance) then
    return out
  end
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and Get(C_ChatInfo.InChatMessagingLockdown) then
    return out
  end
  local c = Channels()
  if c.party then
    local instGroup = LE_PARTY_CATEGORY_INSTANCE and IsInGroup and Get(IsInGroup, LE_PARTY_CATEGORY_INSTANCE)
    if not instGroup then
      if IsInRaid and Get(IsInRaid) then
        out[#out + 1] = "RAID"
      elseif IsInGroup and Get(IsInGroup) then
        out[#out + 1] = "PARTY"
      end
    end
  end
  if c.guild and IsInGuild and Get(IsInGuild) then
    out[#out + 1] = "GUILD"
  end
  return out
end
Share.Targets = Targets

local function CanSendNow(now)
  if now - lastSend < SEND_GAP then
    return false, SEND_GAP - (now - lastSend)
  end
  if #sentTimes >= SEND_PER_MIN then
    local oldest = sentTimes[#sentTimes - SEND_PER_MIN + 1]
    if now - oldest < 60 then
      return false, 60 - (now - oldest)
    end
  end
  return true
end

local function NoteSend(now)
  lastSend = now
  sentTimes[#sentTimes + 1] = now
  while #sentTimes > SEND_PER_MIN do
    table.remove(sentTimes, 1)
  end
end

local Pump
local function Schedule(delay)
  if pumping then
    return
  end
  pumping = true
  local run = Seekwell.Safe("share.pump", function()
    pumping = false
    Pump()
  end)
  if C_Timer and C_Timer.After then
    C_Timer.After(math.max(0.1, delay or SEND_GAP), run)
  else
    pumping = false
  end
end

--- Send one queued message (one SendAddonMessage per call to keep within the throttle), then re-schedule.
Pump = function()
  if not Enabled() or #queue == 0 then
    return
  end
  if InCombat() then
    return -- PLAYER_REGEN_ENABLED resumes
  end
  local now = Now()
  local ok, wait = CanSendNow(now)
  if not ok then
    Schedule(wait)
    return
  end
  local targets = Targets()
  if #targets == 0 then
    queue = {} -- nobody to tell; do not keep stale data around
    return
  end
  local item = queue[1]
  item.ti = item.ti or 1
  local chan = targets[item.ti]
  if chan then
    local okS, err = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.msg, chan)
    if okS then
      stats.sent = stats.sent + 1
    else
      Record("share.send", err)
    end
    NoteSend(now)
  end
  item.ti = item.ti + 1
  if item.ti > #targets then
    table.remove(queue, 1)
  end
  if #queue > 0 then
    Schedule(SEND_GAP)
  end
end
Share.Pump = Pump

--- Queue the current totals of one learned npc (replaces anything already queued for it).
function Share.QueueNpc(npcID)
  if not Enabled() or not prefixOK then
    return 0
  end
  local e = Seekwell.Learned and Seekwell.Learned.Get(npcID)
  if not e then
    return 0
  end
  local msgs = Share.BuildMessages(npcID, e.k, e.l)
  local kept = {}
  for _, q in ipairs(queue) do
    if q.npc ~= npcID then
      kept[#kept + 1] = q
    end
  end
  queue = kept
  for _, m in ipairs(msgs) do
    if #queue >= QUEUE_MAX then
      table.remove(queue, 1)
    end
    queue[#queue + 1] = { npc = npcID, msg = m }
  end
  return #msgs
end

--- After a loot window: queue what changed in it.
function Share.Flush()
  if not Enabled() then
    dirty, dirtyOrder = {}, {}
    return
  end
  local list = dirtyOrder
  dirty, dirtyOrder = {}, {}
  for _, id in ipairs(list) do
    Share.QueueNpc(id)
  end
  if #queue > 0 and not InCombat() then
    Schedule(0.1)
  end
end

local function MarkDirty(npcID)
  npcID = tonumber(npcID)
  if npcID and not dirty[npcID] and #dirtyOrder < 50 then
    dirty[npcID] = true
    dirtyOrder[#dirtyOrder + 1] = npcID
  end
end

local function HookLearned()
  if hooked or not Seekwell.Learned then
    return
  end
  hooked = true
  local orig = Seekwell.Learned.Record
  Seekwell.Learned.Record = function(npcID, ...)
    orig(npcID, ...)
    if Enabled() then
      pcall(MarkDirty, npcID)
    end
  end
end

-- Receiving -----------------------------------------------------------------

local function PlayerName()
  local n = Sec().Str(Sec().Get(UnitName, "player"))
  return n
end

local function ShortName(sender)
  if Ambiguate then
    local ok, v = pcall(Ambiguate, sender, "none")
    v = ok and Sec().Str(v) or nil
    if v then
      return v
    end
  end
  return (sender:match("^([^%-]+)")) or sender
end

local function RateOK(sender, now)
  if now - totalWin.t0 >= 60 then
    totalWin.t0, totalWin.n = now, 0
  end
  if totalWin.n >= RECV_TOTAL_PER_MIN then
    return false
  end
  local r = senders[sender]
  if not r then
    if senderCount >= SENDER_TRACK_MAX then
      senders, senderCount = {}, 0
    end
    r = { t0 = now, n = 0 }
    senders[sender] = r
    senderCount = senderCount + 1
  end
  if now - r.t0 >= 60 then
    r.t0, r.n = now, 0
  end
  if r.n >= RECV_PER_MIN then
    return false
  end
  r.n = r.n + 1
  totalWin.n = totalWin.n + 1
  return true
end

local function Int(s, max)
  if type(s) ~= "string" or #s < 1 or #s > 8 or s:find("%D") then
    return nil
  end
  local v = tonumber(s)
  if not v or v < 1 or v > max then
    return nil
  end
  return v
end

--- Parse and validate a message. Returns npcID, kills, items{[id]=d}, nItems or nil, reason.
function Share.Parse(msg)
  if type(msg) ~= "string" or #msg > 255 or #msg < 6 then
    return nil, "length"
  end
  local ver, sNpc, sKills, body = msg:match("^(v%d+)|(%d+)|(%d+)|([%d:,]*)$")
  if not ver then
    return nil, "format"
  end
  if ver ~= VERSION_TAG then
    return nil, "version"
  end
  local npcID, kills = Int(sNpc, MAX_ID), Int(sKills, MAX_KILLS)
  if not npcID or not kills then
    return nil, "range"
  end
  local items, n = {}, 0
  if body ~= "" then
    if body:find(",,") or body:sub(1, 1) == "," or body:sub(-1) == "," then
      return nil, "format"
    end
    for tok in body:gmatch("[^,]+") do
      local a, b = tok:match("^(%d+):(%d+)$")
      local id, d = Int(a, MAX_ID), Int(b, MAX_KILLS)
      if not id or not d or d > kills or items[id] then
        return nil, "item"
      end
      n = n + 1
      if n > MAX_ITEMS then
        return nil, "items"
      end
      items[id] = d
    end
  end
  return npcID, kills, items, n
end

local function Recompute(e)
  local k, l = 0, {}
  for _, c in pairs(e.c) do
    k = k + (tonumber(c.k) or 0)
    for id, d in pairs(c.l) do
      l[id] = (l[id] or 0) + d
    end
  end
  -- keep the MAX_UNION most frequent items
  local list = {}
  for id, d in pairs(l) do
    list[#list + 1] = { id = id, d = d }
  end
  if #list > MAX_UNION then
    table.sort(list, function(a, b)
      if a.d ~= b.d then
        return a.d > b.d
      end
      return a.id < b.id
    end)
    l = {}
    for i = 1, MAX_UNION do
      l[list[i].id] = list[i].d
    end
  end
  e.k, e.l = k, l
end

local function PruneStore(st)
  local list = {}
  for id, e in pairs(st.npc) do
    list[#list + 1] = { id = id, s = tonumber(type(e) == "table" and e.s) or 0 }
  end
  table.sort(list, function(a, b)
    if a.s ~= b.s then
      return a.s < b.s
    end
    return a.id < b.id
  end)
  local drop = #list - math.floor(MAX_NPCS * 0.9)
  for i = 1, math.max(0, drop) do
    st.npc[list[i].id] = nil
  end
  st.count = #list - math.max(0, drop)
end

--- Store one validated message from sender. Returns "stored" | "merged" | "ignored".
function Share.Store(sender, npcID, kills, items, nowEpoch)
  local st = Store(true)
  local now = nowEpoch or Epoch()
  local e = st.npc[npcID]
  if type(e) ~= "table" then
    e = { k = 0, l = {}, from = {}, c = {}, s = now }
    st.npc[npcID] = e
    st.count = (tonumber(st.count) or 0) + 1
  end
  e.from = type(e.from) == "table" and e.from or {}
  e.c = type(e.c) == "table" and e.c or {}
  local c = e.c[sender]
  local result
  if c and c.k == kills then
    -- another part of the same snapshot: set (never add) the items
    local cnt = 0
    for _ in pairs(c.l) do
      cnt = cnt + 1
    end
    for id, d in pairs(items) do
      if not c.l[id] then
        if cnt >= MAX_ITEMS then
          break
        end
        cnt = cnt + 1
      end
      c.l[id] = d
    end
    result = "merged"
  elseif c and (now - (tonumber(e.from[sender]) or 0)) < DAY then
    return "ignored" -- one contribution per sender and npc per day
  else
    if not c then
      local n, oldS, oldT = 0, nil, nil
      for s, t in pairs(e.from) do
        n = n + 1
        if not oldT or t < oldT then
          oldS, oldT = s, t
        end
      end
      if n >= MAX_SENDERS and oldS then
        e.from[oldS], e.c[oldS] = nil, nil
      end
    end
    local l = {}
    for id, d in pairs(items) do
      l[id] = d
    end
    e.c[sender] = { k = kills, l = l }
    e.from[sender] = now
    result = "stored"
  end
  e.s = now
  Recompute(e)
  if (tonumber(st.count) or 0) > MAX_NPCS then
    PruneStore(st)
  end
  BumpCaches()
  return result
end

--- CHAT_MSG_ADDON handler body.
function Share.OnAddonMessage(prefix, msg, channel, sender)
  if not Enabled() then
    return
  end
  local Plain = Sec().Plain
  prefix, msg, channel, sender = Plain(prefix), Plain(msg), Plain(channel), Plain(sender)
  if prefix ~= PREFIX then
    return
  end
  if type(msg) ~= "string" or type(sender) ~= "string" or type(channel) ~= "string" or #sender > 64 or sender == "" then
    stats.rejected = stats.rejected + 1
    return
  end
  local c = Channels()
  local okChan = ((channel == "PARTY" or channel == "RAID") and c.party) or (channel == "GUILD" and c.guild)
  if not okChan then
    stats.ignored = stats.ignored + 1
    return
  end
  local short = ShortName(sender)
  local me = PlayerName()
  if me and (short == me or sender == me) then
    return -- own echo
  end
  if not RateOK(sender, Now()) then
    stats.rejected = stats.rejected + 1
    return
  end
  local npcID, kills, items = Share.Parse(msg)
  if not npcID then
    stats.rejected = stats.rejected + 1
    return
  end
  local r = Share.Store(sender, npcID, kills, items)
  if r == "ignored" then
    stats.ignored = stats.ignored + 1
  else
    stats.received = stats.received + 1
  end
end

-- Lookup (Registry provider) ---------------------------------------------------

local function Entry(npcID)
  local st = Store(false)
  local e = st and st.npc[tonumber(npcID) or -1]
  if type(e) ~= "table" or (tonumber(e.k) or 0) < MIN_KILLS or type(e.l) ~= "table" then
    return nil
  end
  return e
end

local function Players(e)
  local n = 0
  for _ in pairs(e.from or {}) do
    n = n + 1
  end
  return n
end

local function Label(n)
  return "shared (" .. n .. (n == 1 and " player)" or " players)")
end
Share.Label = Label

--- Drop rows of a shared npc: { {id, p, d, n, origin = "shared", label} }, kills.
function Share.NpcDrops(npcID)
  local e = Entry(npcID)
  if not e then
    return {}, 0
  end
  local label = Label(Players(e))
  local rows = {}
  for id, d in pairs(e.l) do
    rows[#rows + 1] = { id = id, p = math.min(100, d / e.k * 100), d = d, n = e.k, origin = "shared", label = label }
  end
  return rows, e.k
end

--- Shared sources of an item: { {npc, p, n, origin = "shared", label} } (no index: shared store is small).
function Share.ItemSources(itemID)
  itemID = tonumber(itemID)
  local st = Store(false)
  local out = {}
  if not itemID or not st then
    return out
  end
  for npcID, e in pairs(st.npc) do
    if type(e) == "table" and type(e.l) == "table" and e.l[itemID] and (tonumber(e.k) or 0) >= MIN_KILLS then
      out[#out + 1] = { npc = npcID, p = math.min(100, e.l[itemID] / e.k * 100), n = e.k, origin = "shared",
        label = Label(Players(e)) }
    end
  end
  return out
end

function Share.Count()
  local st = Store(false)
  return st and (tonumber(st.count) or 0) or 0
end

function Share.Stats()
  return { sent = stats.sent, received = stats.received, rejected = stats.rejected, ignored = stats.ignored,
    npcs = Share.Count(), queued = #queue }
end

function Share.Clear()
  if type(SeekwellDB) == "table" then
    SeekwellDB.shared = nil
  end
  BumpCaches()
end

-- Switching -------------------------------------------------------------------

local function OnEvent(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    Share.OnAddonMessage(...)
  elseif event == "LOOT_CLOSED" then
    Share.Flush()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if #queue > 0 then
      Schedule(1)
    end
  end
end

local function EnsureFrame()
  if not frame then
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", Seekwell.Safe("share", OnEvent))
  end
  return frame
end

local function Activate(on)
  if on then
    if not RegisterPrefix() then
      return false
    end
    HookLearned()
    local f = EnsureFrame()
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("LOOT_CLOSED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
  else
    if frame then
      frame:UnregisterAllEvents()
    end
    queue, dirty, dirtyOrder = {}, {}, {}
  end
  return true
end

--- Turn sharing on / off (settings + events). quiet = no chat note. Returns the effective state.
function Share.Apply(on, quiet)
  local s = Settings()
  local was = s.share == true
  s.share = on and true or false
  local ok = Activate(s.share)
  if s.share and not ok then
    s.share = false
    if not quiet then
      Print("sharing is not available in this client (no addon messages).")
    end
    return false
  end
  if not quiet and was ~= s.share then
    Print(s.share and "sharing ON: your npc ids, kill counts and item drop counts go to your group / guild (nothing about you)."
      or "sharing OFF: nothing is sent or received.")
  end
  if Seekwell.Window and Seekwell.Window.Refresh then
    pcall(Seekwell.Window.Refresh)
  end
  return s.share
end

function Share.StatusText()
  local st = Share.Stats()
  if not Share.Available() then
    return "unavailable (no addon messages)"
  end
  local c = Channels()
  if Settings().shareStats == false then
    return Enabled() and "on" or "off"
  end
  return string.format("%s · party %s · guild %s · sent %d · received %d · rejected %d · shared npc %d",
    Enabled() and "on" or "off", c.party and "on" or "off", c.guild and "on" or "off", st.sent, st.received,
    st.rejected, st.npcs)
end

-- Registration ------------------------------------------------------------------

if Seekwell.Registry and Seekwell.Registry.RegisterExtra then
  Seekwell.Registry.RegisterExtra("shared", { npc = Share.NpcDrops, item = Share.ItemSources })
end

local sectionDone = false
--- UI/Window.lua loads after this file: the section is registered at login (the window is built lazily later).
function Share.RegisterWindowSection()
  if sectionDone or not (Seekwell.Window and Seekwell.Window.RegisterSection) then
    return
  end
  sectionDone = true
  Seekwell.Window.RegisterSection({
    id = "sharing",
    label = "Sharing",
    build = function(sec, H)
      local y = 0
      H.Heading(sec, "Sharing", y)
      y = y - 30
      H.Note(sec, "Off by default. When on, after each loot window Seekwell sends your learned totals for that mob to your party / raid and / or guild: the npc id, your kill count, and item ids with how often they dropped. Nothing about you (no names, positions, zones or character data). Nothing is sent in combat or inside instances, at most one message every 3 s.", y)
      y = y - 62
      H.Note(sec, "Received data from other Seekwell users is kept apart from your own, shown as \"shared (N players)\" below Forever and your learned data, and only once it covers 5 kills.", y)
      y = y - 40
      local statsText
      H.Check(sec, "Share learned data with group / guild", y, function()
        if statsText then
          local st = Share.Stats()
          statsText:SetText(string.format("Sent %d · received %d · rejected %d · shared npc %d%s", st.sent,
            st.received, st.rejected, st.npcs, Share.Available() and "" or " · unavailable in this client"))
        end
        return Enabled()
      end, function(on)
        Share.Apply(on)
      end)
      y = y - 28
      H.Check(sec, "Party / raid", y, function()
        return Channels().party
      end, function(on)
        Channels().party = on
      end)
      y = y - 28
      H.Check(sec, "Guild", y, function()
        return Channels().guild
      end, function(on)
        Channels().guild = on
      end)
      y = y - 32
      statsText = H.Note(sec, "", y)
      y = y - 24
      H.Button(sec, "Clear shared data", 16, y, 160, function()
        Share.Clear()
        Print("shared data cleared.")
        if Seekwell.Window.Refresh then
          Seekwell.Window.Refresh()
        end
      end)
      y = y - 30
      return -y + 50
    end,
  })
end

-- Core.lua (RegisterSlash / RegisterStart / RegisterStatus) and UI/Window.lua load after this file:
-- hook in at ADDON_LOADED, before PLAYER_LOGIN runs the starters.
local wired = false
function Share.Wire()
  if wired or not Seekwell.RegisterSlash then
    return
  end
  wired = true
  Share.RegisterWindowSection()
  if Seekwell.RegisterStart then
    Seekwell.RegisterStart("share", function()
      if Enabled() then
        Share.Apply(true, true)
      end
    end)
  end

  if Seekwell.RegisterStatus then
    Seekwell.RegisterStatus("share", Share.StatusText)
  end

  if Seekwell.RegisterSlash then
    Seekwell.RegisterSlash("share", function(rest)
      rest = rest or ""
      if rest == "on" or rest == "off" then
        Share.Apply(rest == "on")
      elseif rest == "clear" then
        Share.Clear()
        Print("shared data cleared.")
      elseif rest == "status" or rest == "" then
        Print("share: " .. Share.StatusText())
      else
        Print("usage: /sw share on/off/status/clear")
      end
    end)
  end
end

local addonName = ...
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name == addonName or name == "Seekwell" then
    self:UnregisterAllEvents()
    if Seekwell.SafeCall then
      Seekwell.SafeCall("share.wire", Share.Wire)
    else
      pcall(Share.Wire)
    end
  end
end)
