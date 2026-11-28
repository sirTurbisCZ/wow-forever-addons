--[[
  Seekwell.Learned — drops learned from your own loot windows (SeekwellDB.learned).
  learned.npc[npcID] = { n = name, k = kills, l = { [itemID] = drops }, m = { [uiMapID] = lastSeen }, s = lastSeen }
  Item ids only, no links, no positions. About 20000 NPCs at most; the oldest (by last seen) are pruned.
  The item -> npc reverse index is built on first need (never at login) and kept up to date afterwards.
]]

Seekwell = Seekwell or {}
local Learned = {}
Seekwell.Learned = Learned

local CAP = 20000
local PRUNE_TO = 19000
Learned.CAP = CAP

local index -- [itemID] = { [npcID] = true }, nil until needed
Learned.generation = 0 -- bumped on every change (caches compare it)

local function Store()
  return Seekwell.Config.Learned()
end

local function Npcs()
  return Store().npc
end

local function Count()
  local st = Store()
  if type(st.count) ~= "number" then
    local n = 0
    for _ in pairs(st.npc) do
      n = n + 1
    end
    st.count = n
  end
  return st.count
end
Learned.Count = Count

local function IndexAdd(npcID, e)
  if not index then
    return
  end
  for itemID in pairs(e.l or {}) do
    local set = index[itemID]
    if not set then
      set = {}
      index[itemID] = set
    end
    set[npcID] = true
  end
end

local function BuildIndex()
  index = {}
  for npcID, e in pairs(Npcs()) do
    if type(e) == "table" then
      IndexAdd(npcID, e)
    end
  end
end

local function Prune()
  local list = {}
  for id, e in pairs(Npcs()) do
    list[#list + 1] = { id = id, s = (type(e) == "table" and tonumber(e.s)) or 0 }
  end
  if #list <= CAP then
    Store().count = #list
    return
  end
  table.sort(list, function(a, b)
    return a.s < b.s
  end)
  local npc = Npcs()
  local spawn = type(Store().spawn) == "table" and Store().spawn or nil
  for i = 1, #list - PRUNE_TO do
    local id = list[i].id
    npc[id] = nil
    if spawn then
      for mapID, m in pairs(spawn) do
        if type(m) == "table" then
          m[id] = nil
          m[tostring(id)] = nil
        end
      end
    end
  end
  if spawn then
    for mapID, m in pairs(spawn) do
      if type(m) ~= "table" or next(m) == nil then
        spawn[mapID] = nil
      end
    end
  end
  Store().count = PRUNE_TO
  index = nil -- rebuilt on next need
  Learned.generation = Learned.generation + 1
end

-- the full scan + sort must not run inside the loot window event: deferred by one frame, once
local prunePending = false
local function SchedulePrune()
  if prunePending then
    return
  end
  local T = rawget(_G, "C_Timer")
  if not (T and T.After) then
    Prune()
    return
  end
  prunePending = true
  T.After(0, function()
    prunePending = false
    local ok, err = pcall(function()
      if Store().count > CAP then
        Prune()
      end
    end)
    if not ok and Seekwell.RecordError then
      pcall(Seekwell.RecordError, "learned.prune", err)
    end
  end)
end
Learned._Prune = SchedulePrune

--- One loot window's result for one NPC: kills (usually 1), items { [itemID] = drops }.
function Learned.Record(npcID, name, kills, items, mapID, now)
  npcID = tonumber(npcID)
  if not npcID then
    return
  end
  now = now or (time and time()) or 0
  local npc = Npcs()
  local e = npc[npcID]
  if type(e) ~= "table" then
    e = { k = 0, l = {}, m = {} }
    npc[npcID] = e
    Store().count = Count() + 1
  end
  if type(name) == "string" and name ~= "" then
    e.n = name
  end
  e.k = (tonumber(e.k) or 0) + (kills or 1)
  e.l = type(e.l) == "table" and e.l or {}
  for itemID, d in pairs(items or {}) do
    e.l[itemID] = (tonumber(e.l[itemID]) or 0) + d
  end
  e.m = type(e.m) == "table" and e.m or {}
  if mapID then
    e.m[mapID] = now
  end
  e.s = now
  IndexAdd(npcID, e)
  Learned.generation = Learned.generation + 1
  if Store().count > CAP then
    SchedulePrune()
  end
end

function Learned.Get(npcID)
  local e = Npcs()[tonumber(npcID) or -1]
  return type(e) == "table" and e or nil
end

function Learned.Name(npcID)
  local e = Learned.Get(npcID)
  return e and type(e.n) == "string" and e.n or nil
end

--- Drop rows of an NPC: { {id, p, d, k} }, kills.
function Learned.Items(npcID)
  local e = Learned.Get(npcID)
  if not e then
    return nil, 0
  end
  local k = tonumber(e.k) or 0
  local rows = {}
  for itemID, d in pairs(e.l or {}) do
    d = tonumber(d) or 0
    rows[#rows + 1] = { id = itemID, d = d, k = k, p = (k > 0) and math.min(100, d * 100 / k) or nil }
  end
  return rows, k
end

--- NPCs that dropped an item: { {npc, p, d, k} }.
function Learned.From(itemID)
  itemID = tonumber(itemID)
  if not itemID then
    return {}
  end
  if not index then
    BuildIndex()
  end
  local rows = {}
  for npcID in pairs(index[itemID] or {}) do
    local e = Learned.Get(npcID)
    local k = e and tonumber(e.k) or 0
    local d = e and e.l and tonumber(e.l[itemID]) or 0
    if k > 0 and d > 0 then
      rows[#rows + 1] = { npc = npcID, d = d, k = k, p = math.min(100, d * 100 / k) }
    end
  end
  return rows
end

--- { npcs, kills, items, bytes } (walks all data; for the Learned section and /sw status only).
function Learned.Stats()
  local npcs, kills, items, bytes = 0, 0, 0, 0
  for _, e in pairs(Npcs()) do
    if type(e) == "table" then
      npcs = npcs + 1
      kills = kills + (tonumber(e.k) or 0)
      bytes = bytes + 40 + (type(e.n) == "string" and #e.n or 0)
      for _ in pairs(e.l or {}) do
        items = items + 1
        bytes = bytes + 16
      end
      for _ in pairs(e.m or {}) do
        bytes = bytes + 20
      end
    end
  end
  Store().count = npcs
  return { npcs = npcs, kills = kills, items = items, bytes = bytes }
end

function Learned.Clear()
  Seekwell.Config.ResetLearned()
  index = nil
  Learned.generation = Learned.generation + 1
end
