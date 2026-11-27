--[[
  Seekwell.FDB — read-only RUNTIME bridge to the forever-db DATA addon (github.com/foreverfraddons/forever-db, GPL-3.0,
  sources in its LICENSE-DATA.txt). Installed as the LoadOnDemand game folder "ForeverDBData" (also "ForeverDB_Data");
  it defines the global table ForeverDB. Nothing is copied into Seekwell or its SavedVariables.
  The game folder "ForeverDB" is usually a DIFFERENT addon (ForeverDB.net helper): it is used only as a last resort,
  only when it is LoadOnDemand, and only when the global afterwards has the data layout (meta.build + npc).

  Loading: never at login. F.Load() is called on first real need (search, hunt, target panel, /sw fdb), never in
  combat (queued until PLAYER_REGEN_ENABLED). Lookups never load by themselves: before the load they return nil / {}.
  Indexes (npc -> items, names, per-map mobs) are built lazily in ~4 ms C_Timer slices; until ready they return
  what is possible and Status() shows progress.

  Tables read: npc[id] = {name, sub, minLv, maxLv, rank}; item[id] = {name, quality, ...};
  drop/skin[item] = {npc, chance per 10000, ...} (0 = drops, rate unknown); vend[item] = {npc, ...};
  rew[item] = {quest, ...}; quest[id] = {title, level, minLevel}; qg[quest] = {"c123", "o45"};
  spm["c<npc>"] = {[uiMap] = {x, y, ...}} (0-1000); spw["c<npc>"] = { {continent, x, y, x, y, ...}, ... } world yards;
  dng[area] = {name, parentArea, {uiMap, x, y, ...}} (0-1000); gold[npc] = {avg, min, max, kills}.

  World -> map: C_Map.GetMapPosFromWorldPos(continent, CreateVector2D(a, b)) with (a, b) = the pair as stored
  (MaNGOS position_x, position_y = the client's world vector x, y; same order HereBeDragons reads with GetXY()).

  Forever-only rule (IsForeverOnly): present in forever-db AND (id >= 211000, or Tinny's Classic Starter table is
  loaded and does not have the id). Without Tinny only the id rule applies.
]]

Seekwell = Seekwell or {}
local F = {}
Seekwell.FDB = F

local FOLDERS = { "ForeverDBData", "ForeverDB_Data" }
local LAST_RESORT = "ForeverDB"
local FOREVER_ID = 211000
local SLICE_MS = 4
local SLICE_N = 1500 -- entries per slice when debugprofilestop is missing
local PTS_CAP = 60 -- converted world points per npc and continent group
local SPAWN_LRU = 600

local st = { loaded = false, tried = false, failed = nil, waiting = false, folder = nil, ms = nil, kb = nil, noted = false }
local gen = 0
local epoch = 0 -- bumped when the indexes are reset: older sliced jobs stop
local jobs = {} -- name -> { done, n, total }
local fails = {} -- job name -> failed runs (a failed job may restart twice)
local readyFns = {}
local idx = {} -- npcItems, itemIds/itemLower, npcIds/npcLower, mapMobs, dng
local spawnCache, spawnCount, spawnTick = {}, 0, 0
local mapTypeCache = {}

local function Err(context, err)
  local f = Seekwell.RecordError
  if f then
    pcall(f, "fdb." .. context, err)
  end
end

local function Guard(context, fn)
  return function(...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then
      Err(context, a)
      return nil
    end
    return a, b, c, d
  end
end

local function G(n)
  return rawget(_G, n)
end

local function Enabled()
  local ok, s = pcall(function()
    return Seekwell.Config.Get().forever
  end)
  return not (ok and type(s) == "table" and s.fdbData == false)
end
F.Enabled = Enabled

local function Valid(d)
  return type(d) == "table" and type(d.meta) == "table" and d.meta.build ~= nil and type(d.npc) == "table"
end

--- The data table when loaded and enabled (never loads).
local function Data()
  if not (st.loaded and Enabled()) then
    return nil
  end
  local d = G("ForeverDB")
  return Valid(d) and d or nil
end
F.Data = Data

local function Sub(name)
  local d = Data()
  local t = d and d[name]
  return type(t) == "table" and t or nil
end

local function Exists(name)
  local api = G("C_AddOns")
  if api and api.DoesAddOnExist then
    local ok, v = pcall(api.DoesAddOnExist, name)
    return ok and v and true or false
  end
  local info = (api and api.GetAddOnInfo) or G("GetAddOnInfo")
  if info then
    local ok, n, _, _, _, reason = pcall(info, name)
    return ok and n ~= nil and reason ~= "MISSING"
  end
  return false
end

local function IsLOD(name)
  local api = G("C_AddOns")
  local f = (api and api.IsAddOnLoadOnDemand) or G("IsAddOnLoadOnDemand")
  if not f then
    return false
  end
  local ok, v = pcall(f, name)
  return ok and v and true or false
end

--- Folder to load: ForeverDBData / ForeverDB_Data, else "ForeverDB" only when it is LoadOnDemand.
local function Folder()
  for _, n in ipairs(FOLDERS) do
    if Exists(n) then
      return n, false
    end
  end
  if Exists(LAST_RESORT) and IsLOD(LAST_RESORT) then
    return LAST_RESORT, true
  end
  return nil
end

--- true when the data addon folder is present (or its data already is).
F.Available = Guard("available", function()
  if Valid(G("ForeverDB")) then
    return true
  end
  return Folder() ~= nil
end)

function F.Loaded()
  return Data() ~= nil
end

function F.Generation()
  return gen
end

local function Now()
  local f = G("debugprofilestop")
  return f and f() or nil
end

local function After(fn)
  local T = G("C_Timer")
  if T and T.After then
    T.After(0, fn)
  else
    fn()
  end
end

--- Calls fn() every time an index finishes building (a 'building' answer can be asked again).
function F.OnReady(fn)
  if type(fn) == "function" then
    readyFns[#readyFns + 1] = fn
  end
end

local function FireReady()
  for _, fn in ipairs(readyFns) do
    local ok, e = pcall(fn)
    if not ok then
      Err("onready", e)
    end
  end
end

-- sliced job runner: iterates t with next() in slices of ~SLICE_MS, calls each(k, v); done() at the end
local function Job(name, t, each, done)
  if jobs[name] or type(t) ~= "table" then
    return
  end
  local j = { done = false, n = 0 }
  jobs[name] = j
  local k
  local myEpoch = epoch
  local function Step()
    if myEpoch ~= epoch then
      return
    end
    local ok, err = pcall(function()
      local t0 = Now()
      local c = 0
      while true do
        local v
        k, v = next(t, k)
        if k == nil then
          j.done = true
          break
        end
        each(k, v)
        j.n = j.n + 1
        c = c + 1
        if t0 then
          if c % 64 == 0 and Now() - t0 > SLICE_MS then
            break
          end
        elseif c >= SLICE_N then
          break
        end
      end
    end)
    if not ok then
      j.done, j.failed = true, true
      Err("job." .. name, err)
      fails[name] = (fails[name] or 0) + 1
      if fails[name] < 2 and jobs[name] == j then
        jobs[name] = nil -- the next request builds it again
      end
      return
    end
    if j.done then
      if done then
        local ok2, e2 = pcall(done)
        if not ok2 then
          Err("job." .. name .. ".done", e2)
        end
      end
    else
      After(Step)
    end
  end
  After(Step)
end

local function Ready(name)
  return jobs[name] and jobs[name].done and not jobs[name].failed
end

local function Bump()
  gen = gen + 1
  if Seekwell.Spawns then
    Seekwell.Spawns.generation = (Seekwell.Spawns.generation or 0) + 1
  end
  if Seekwell.Registry and Seekwell.Registry.ClearCache then
    pcall(Seekwell.Registry.ClearCache)
  end
end

local function ResetIndexes()
  epoch = epoch + 1
  jobs, idx, fails = {}, {}, {}
  spawnCache, spawnCount = {}, 0
  mapTypeCache = {}
end

-- indexes ---------------------------------------------------------------------------------------------------

local function BuildNpcItems()
  local drop = Sub("drop")
  if not drop or jobs.npcItems then
    return
  end
  local out = {}
  Job("npcItems", drop, function(item, v)
    if type(item) == "number" and type(v) == "table" then
      for i = 1, #v - 1, 2 do
        local npc, ch = v[i], v[i + 1]
        if type(npc) == "number" then
          local l = out[npc]
          if not l then
            l = {}
            out[npc] = l
          end
          l[#l + 1] = item
          l[#l + 1] = tonumber(ch) or 0
        end
      end
    end
  end, function()
    idx.npcItems = out
    gen = gen + 1
    if Seekwell.Registry and Seekwell.Registry.ClearCache then
      pcall(Seekwell.Registry.ClearCache)
    end
    FireReady()
  end)
end

local function BuildNames(kind)
  local key = kind == "item" and "itemNames" or "npcNames"
  local t = Sub(kind == "item" and "item" or "npc")
  if not t or jobs[key] then
    return
  end
  local ids, lowers = {}, {}
  Job(key, t, function(id, v)
    local n = type(v) == "table" and v[1]
    if type(id) == "number" and type(n) == "string" and n ~= "" then
      ids[#ids + 1] = id
      lowers[#lowers + 1] = n:lower()
    end
  end, function()
    idx[key] = { ids = ids, lower = lowers }
    FireReady()
  end)
end

local function NpcKey(id)
  return "c" .. tostring(id)
end

local function Plain(v)
  local f = G("issecretvalue")
  if f and f(v) then
    return nil
  end
  return v
end

-- continent mapType check (cached): a zone is wanted, not the continent map
local function MapType(uiMap)
  local v = mapTypeCache[uiMap]
  if v == nil then
    v = false
    local C = G("C_Map")
    if C and C.GetMapInfo then
      local ok, info = pcall(C.GetMapInfo, uiMap)
      if ok and type(info) == "table" then
        v = Plain(info.mapType) or false
      end
    end
    mapTypeCache[uiMap] = v
  end
  return v
end

--- uiMapID, x, y (0..1) for a world position, or nil.
local function WorldToMap(cont, a, b)
  local C = G("C_Map")
  local V = G("CreateVector2D")
  if not (C and C.GetMapPosFromWorldPos and V) then
    return nil
  end
  local ok, uiMap, pos = pcall(C.GetMapPosFromWorldPos, cont, V(a, b))
  if not ok or not pos then
    return nil
  end
  uiMap = Plain(uiMap)
  local x, y = Plain(pos.x), Plain(pos.y)
  if type(uiMap) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
    return nil
  end
  if MapType(uiMap) == 2 and C.GetMapInfoAtPosition then -- Enum.UIMapType.Continent: move to the zone there
    local ok2, zone = pcall(C.GetMapInfoAtPosition, uiMap, x, y)
    local zid = ok2 and type(zone) == "table" and Plain(zone.mapID)
    if type(zid) == "number" and zid ~= uiMap then
      local ok3, _, zpos = pcall(C.GetMapPosFromWorldPos, cont, V(a, b), zid)
      local zx, zy = ok3 and zpos and Plain(zpos.x), ok3 and zpos and Plain(zpos.y)
      if type(zx) == "number" and type(zy) == "number" then
        uiMap, x, y = zid, zx, zy
      end
    end
  end
  if x < 0 or x > 1 or y < 0 or y > 1 then
    return nil
  end
  return uiMap, x, y
end
F.WorldToMap = WorldToMap

local function BuildMapMobs()
  local spm, spw = Sub("spm"), Sub("spw")
  if jobs.mapMobs or not (spm or spw) then
    return
  end
  local out, seen = {}, {}
  local function Put(mapID, npc)
    local k = mapID .. ":" .. npc
    if not seen[k] then
      seen[k] = true
      local l = out[mapID]
      if not l then
        l = {}
        out[mapID] = l
      end
      l[#l + 1] = npc
    end
  end
  local function Npc(key)
    return type(key) == "string" and key:sub(1, 1) == "c" and tonumber(key:sub(2)) or nil
  end
  local function Finish()
    for _, l in pairs(out) do
      table.sort(l)
    end
    idx.mapMobs = out
    gen = gen + 1
    FireReady()
  end
  local function DoSpw()
    if spw then
      Job("mapMobsW", spw, function(key, groups)
        local npc = Npc(key)
        if npc and type(groups) == "table" then
          for _, g in ipairs(groups) do
            if type(g) == "table" and type(g[1]) == "number" and g[2] and g[3] then
              local m = WorldToMap(g[1], g[2], g[3])
              if m then
                Put(m, npc)
              end
            end
          end
        end
      end, Finish)
    else
      Finish()
    end
  end
  if spm then
    Job("mapMobs", spm, function(key, maps)
      local npc = Npc(key)
      if npc and type(maps) == "table" then
        for m in pairs(maps) do
          if type(m) == "number" then
            Put(m, npc)
          end
        end
      end
    end, DoSpw)
  else
    jobs.mapMobs = { done = true, n = 0 }
    DoSpw()
  end
end

local function StartIndexes()
  BuildNpcItems()
end

-- loading ---------------------------------------------------------------------------------------------------

local function InCombat()
  local f = G("InCombatLockdown")
  return f and f() and true or false
end

local waiter
local function DeferUntilCombatEnds()
  if st.waiting or not G("CreateFrame") then
    return
  end
  if not waiter then
    waiter = CreateFrame("Frame")
    waiter:SetScript("OnEvent", function(self)
      self:UnregisterEvent("PLAYER_REGEN_ENABLED")
      st.waiting = false
      F.Load()
    end)
  end
  st.waiting = true
  waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function Note(msg)
  if Seekwell.Print then
    Seekwell.Print(msg)
  else
    print(msg)
  end
end

local function MemKB(folder)
  local U, Gm = G("UpdateAddOnMemoryUsage"), G("GetAddOnMemoryUsage")
  local api = G("C_AddOns")
  Gm = (api and api.GetAddOnMemoryUsage) or Gm
  if U and Gm and folder then
    local ok = pcall(U)
    local ok2, kb = pcall(Gm, folder)
    if ok and ok2 and tonumber(kb) and kb > 0 then
      return kb
    end
  end
  return nil
end

local function Finish()
  st.loaded = true
  Bump()
  StartIndexes()
  return true
end

--- Load the data addon once (out of combat). Returns true when the data is present.
F.Load = Guard("load", function()
  if not Enabled() then
    return false
  end
  if st.loaded then
    return Data() ~= nil
  end
  if Valid(G("ForeverDB")) then -- already loaded by another addon
    st.folder = st.folder or "(already loaded)"
    return Finish()
  end
  if st.tried then
    return false
  end
  if InCombat() then
    DeferUntilCombatEnds()
    return false
  end
  local folder, lastResort = Folder()
  if not folder then
    st.tried, st.failed = true, "MISSING"
    return false
  end
  st.tried, st.folder = true, folder
  local api = G("C_AddOns")
  local load = (api and api.LoadAddOn) or G("LoadAddOn")
  if not load then
    st.failed = "NO_API"
    return false
  end
  if not st.noted then
    st.noted = true
    Note("loading Forever database...")
  end
  local t0 = Now()
  local ok, res, reason = pcall(load, folder)
  local t1 = Now()
  st.ms = (t0 and t1) and (t1 - t0) or nil
  if not ok then
    st.failed = "ERROR"
    Err("loadaddon", res)
    return false
  end
  if not Valid(G("ForeverDB")) then
    st.failed = lastResort and "NOT_DATA (folder ForeverDB is not the data addon)" or tostring(reason or (res and "NO_DATA" or "FAILED"))
    return false
  end
  st.kb = MemKB(folder)
  return Finish()
end)

--- Called by the UI on first real need (search, hunt, target panel): starts the load once.
function F.Touch()
  if not st.loaded and not st.tried and Enabled() then
    F.Load()
  end
  return Data() ~= nil
end

-- lookups ---------------------------------------------------------------------------------------------------

--- { name, sub, minLv, maxLv, rank } or nil.
F.Npc = Guard("npc", function(id)
  local t = Sub("npc")
  local v = t and t[tonumber(id) or -1]
  if type(v) ~= "table" then
    return nil
  end
  return { name = v[1], sub = v[2], minLv = tonumber(v[3]), maxLv = tonumber(v[4]), rank = tonumber(v[5]) }
end)

F.NpcName = Guard("npcname", function(id)
  local t = Sub("npc")
  local v = t and t[tonumber(id) or -1]
  local n = type(v) == "table" and v[1]
  return type(n) == "string" and n ~= "" and n or nil
end)

--- name, quality
F.ItemInfo = Guard("iteminfo", function(id)
  local t = Sub("item")
  local v = t and t[tonumber(id) or -1]
  if type(v) ~= "table" or type(v[1]) ~= "string" then
    return nil
  end
  return v[1], tonumber(v[2])
end)

function F.ItemName(id)
  local n = F.ItemInfo(id)
  return n
end

local function Pct(ch)
  ch = tonumber(ch)
  if not ch or ch <= 0 then
    return nil
  end
  return ch / 100
end
F.Pct = Pct

--- Kills behind an npc's Drop Tables numbers (gold table), or nil.
local function Kills(npc)
  local g = Sub("gold")
  local v = g and g[npc]
  return type(v) == "table" and tonumber(v[4]) or nil
end
F.Kills = Kills

--- Drops of an npc: { {item, p} } (p in percent, nil = drops, rate unknown), best first; second value "building"
--- while the npc -> items index is still being built (nil + "building"), nil when not loaded.
F.Drops = Guard("drops", function(npcID)
  npcID = tonumber(npcID)
  if not (npcID and Data()) then
    return nil
  end
  if not idx.npcItems then
    BuildNpcItems()
    if not idx.npcItems then
      return nil, "building"
    end
  end
  local l = idx.npcItems[npcID]
  local out = {}
  if l then
    for i = 1, #l - 1, 2 do
      out[#out + 1] = { item = l[i], p = Pct(l[i + 1]) }
    end
    table.sort(out, function(a, b)
      if (a.p or -1) ~= (b.p or -1) then
        return (a.p or -1) > (b.p or -1)
      end
      return a.item < b.item
    end)
  end
  return out
end)

local function Label(npc)
  local k = Kills(npc)
  return "ForeverDB" .. (k and (" (" .. k .. ")") or "")
end
F.Label = Label

--- Sources of an item: { {npc, p, origin = "forever_db", label, n, skin} } best first (lists are stored best first).
F.ItemSources = Guard("itemsources", function(itemID, limit)
  itemID = tonumber(itemID)
  limit = tonumber(limit) or 40
  local out = {}
  if not itemID then
    return out
  end
  local seen = {}
  local function From(t, skin)
    local v = t and t[itemID]
    if type(v) ~= "table" then
      return
    end
    for i = 1, #v - 1, 2 do
      local npc = v[i]
      if type(npc) == "number" and not seen[npc] and #out < limit then
        seen[npc] = true
        out[#out + 1] = { npc = npc, p = Pct(v[i + 1]), origin = "forever_db", label = Label(npc), n = Kills(npc), skin = skin or nil }
      end
    end
  end
  From(Sub("drop"), false)
  From(Sub("skin"), true)
  return out
end)

--- { vendorNpcID, ... }
F.Vendors = Guard("vendors", function(itemID)
  local t = Sub("vend")
  local v = t and t[tonumber(itemID) or -1]
  local out = {}
  for _, id in ipairs(type(v) == "table" and v or {}) do
    if type(id) == "number" then
      out[#out + 1] = id
    end
  end
  return out
end)

--- { {npc, p} } skinning sources
F.Skin = Guard("skin", function(itemID)
  local t = Sub("skin")
  local v = t and t[tonumber(itemID) or -1]
  local out = {}
  if type(v) == "table" then
    for i = 1, #v - 1, 2 do
      out[#out + 1] = { npc = v[i], p = Pct(v[i + 1]) }
    end
  end
  return out
end)

--- { {questID, name, level, giver (npc id), giverName} } from rew + quest + qg
F.QuestRewards = Guard("questrewards", function(itemID)
  local rew, quest, qg = Sub("rew"), Sub("quest"), Sub("qg")
  local v = rew and rew[tonumber(itemID) or -1]
  local out = {}
  for _, q in ipairs(type(v) == "table" and v or {}) do
    if type(q) == "number" then
      local e = quest and quest[q]
      local g = qg and qg[q]
      local giver = type(g) == "table" and type(g[1]) == "string" and g[1]:match("^c(%d+)$")
      giver = tonumber(giver)
      out[#out + 1] = { questID = q, name = type(e) == "table" and e[1] or nil, level = type(e) == "table" and tonumber(e[2]) or nil,
        giver = giver, giverName = giver and F.NpcName(giver) or nil }
    end
  end
  return out
end)

local function EvictSpawn()
  local oldK, oldT
  for k, e in pairs(spawnCache) do
    if not oldT or e.t < oldT then
      oldK, oldT = k, e.t
    end
  end
  if oldK then
    spawnCache[oldK] = nil
    spawnCount = spawnCount - 1
  end
end

--- { {mapID, points = { {x, y} }} } (0..1), from spm (/1000) and spw (converted); cached per npc.
F.Spawns = Guard("spawns", function(npcID)
  npcID = tonumber(npcID)
  if not (npcID and Data()) then
    return {}
  end
  spawnTick = spawnTick + 1
  local e = spawnCache[npcID]
  if e then
    e.t = spawnTick
    return e.v
  end
  local byMap, list = {}, {}
  local function Map(m)
    local x = byMap[m]
    if not x then
      x = { mapID = m, points = {} }
      byMap[m] = x
      list[#list + 1] = x
    end
    return x
  end
  local key = NpcKey(npcID)
  local spm = Sub("spm")
  local mv = spm and spm[key]
  if type(mv) == "table" then
    for m, c in pairs(mv) do
      if type(m) == "number" and type(c) == "table" then
        local pts = Map(m).points
        for i = 1, #c - 1, 2 do
          local x, y = tonumber(c[i]), tonumber(c[i + 1])
          if x and y and #pts < PTS_CAP then
            x, y = x / 1000, y / 1000
            if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
              pts[#pts + 1] = { x = x, y = y }
            end
          end
        end
      end
    end
  end
  local spw = Sub("spw")
  local wv = spw and spw[key]
  if type(wv) == "table" then
    for _, g in ipairs(wv) do
      if type(g) == "table" and type(g[1]) == "number" then
        local n = 0
        for i = 2, #g - 1, 2 do
          if n >= PTS_CAP then
            break
          end
          local m, x, y = WorldToMap(g[1], g[i], g[i + 1])
          if m then
            n = n + 1
            local pts = Map(m).points
            if #pts < PTS_CAP then
              pts[#pts + 1] = { x = x, y = y }
            end
          end
        end
      end
    end
  end
  local out = {}
  for _, x in ipairs(list) do
    if #x.points > 0 then
      out[#out + 1] = x
    end
  end
  table.sort(out, function(a, b)
    return #a.points > #b.points
  end)
  if spawnCount >= SPAWN_LRU then
    EvictSpawn()
  end
  spawnCache[npcID] = { v = out, t = spawnTick }
  spawnCount = spawnCount + 1
  return out
end)

--- points { {x, y} } of an npc on one map, or nil.
function F.SpawnsOn(npcID, mapID)
  mapID = tonumber(mapID)
  for _, e in ipairs(F.Spawns(npcID) or {}) do
    if e.mapID == mapID then
      return e.points
    end
  end
  return nil
end

F.MapsForNpc = Guard("mapsfornpc", function(npcID)
  local out = {}
  for _, e in ipairs(F.Spawns(npcID) or {}) do
    out[#out + 1] = e.mapID
  end
  table.sort(out)
  return out
end)

--- { npcID, ... } with ForeverDB spawns on that map (index built in slices; {} + "building" until ready).
F.MobsInMap = Guard("mobsinmap", function(mapID)
  mapID = tonumber(mapID)
  if not (mapID and Data()) then
    return {}
  end
  if not idx.mapMobs then
    BuildMapMobs()
    if not idx.mapMobs then
      return {}, "building"
    end
  end
  return idx.mapMobs[mapID] or {}
end)

local function DngIndex()
  if idx.dng then
    return idx.dng
  end
  local t = Sub("dng")
  if not t then
    return nil
  end
  local x = { list = {}, byLower = {} }
  for area, v in pairs(t) do
    if type(v) == "table" and type(v[1]) == "string" then
      local lower = v[1]:lower()
      local e = x.byLower[lower]
      if not e then
        e = { name = v[1], area = area }
        x.byLower[lower] = e
        x.list[#x.list + 1] = e
      end
      local c = v[3]
      if not e.mapID and type(c) == "table" and tonumber(c[1]) and tonumber(c[2]) and tonumber(c[3]) then
        e.mapID, e.x, e.y = tonumber(c[1]), tonumber(c[2]) / 1000, tonumber(c[3]) / 1000
      end
    end
  end
  table.sort(x.list, function(a, b)
    return a.name < b.name
  end)
  idx.dng = x
  return x
end

--- mapID, x, y (0..1), name for a dungeon name (case-insensitive), or nil.
F.Entrance = Guard("entrance", function(name)
  local x = type(name) == "string" and DngIndex()
  local e = x and x.byLower[name:lower()]
  if e and e.mapID then
    return e.mapID, e.x, e.y, e.name
  end
  return nil
end)

--- sorted { {name, area, mapID, x, y} }
F.Dungeons = Guard("dungeons", function()
  local x = DngIndex()
  return x and x.list or {}
end)

--- Name search: kind "item" | "npc"; { {id, name} } at most limit; second value "building" while the index builds.
F.NameSearch = Guard("namesearch", function(text, kind, limit)
  limit = tonumber(limit) or 40
  local q = tostring(text or ""):lower():match("^%s*(.-)%s*$")
  if #q < 2 or not Data() then
    return {}
  end
  local key = kind == "item" and "itemNames" or "npcNames"
  if not idx[key] then
    BuildNames(kind == "item" and "item" or "npc")
    if not idx[key] then
      return {}, "building"
    end
  end
  local t = Sub(kind == "item" and "item" or "npc")
  local x, out = idx[key], {}
  for i = 1, #x.ids do
    if x.lower[i]:find(q, 1, true) then
      local v = t[x.ids[i]]
      out[#out + 1] = { id = x.ids[i], name = type(v) == "table" and v[1] or "?" }
      if #out >= limit then
        break
      end
    end
  end
  return out
end)

--- true when the id is in forever-db and is Forever-only (see the rule in the header). kind "item" | "npc" | "mob".
F.IsForeverOnly = Guard("isforeveronly", function(kind, id)
  id = tonumber(id)
  local isItem = kind == "item"
  local t = Sub(isItem and "item" or "npc")
  if not (id and t and t[id]) then
    return false
  end
  if id >= FOREVER_ID then
    return true
  end
  local s = G("TnnysMobLoot_Starter")
  local sub = type(s) == "table" and s[isItem and "item" or "npc"]
  if type(sub) == "table" and next(sub) ~= nil then
    return sub[id] == nil
  end
  return false
end)

-- status ----------------------------------------------------------------------------------------------------

local function JobText(name, total)
  local j = jobs[name]
  if not j then
    return "idle"
  end
  if j.failed then
    return "failed"
  end
  if j.done then
    return "ready"
  end
  return total and string.format("%d%%", math.floor(100 * j.n / math.max(1, total))) or (j.n .. "...")
end

--- { build, counts, ms, kb, folder, state, indexes } or a text line with text = true.
F.Info = Guard("info", function()
  local d = Data()
  local c = d and type(d.meta.counts) == "table" and d.meta.counts or {}
  return {
    available = F.Available() and true or false, enabled = Enabled(), loaded = d ~= nil, failed = st.failed, waiting = st.waiting,
    folder = st.folder, ms = st.ms, kb = st.kb, build = d and tostring(d.meta.build) or nil,
    npcs = tonumber(c.npc), items = tonumber(c.item), drops = tonumber(c.drop), vendors = tonumber(c.vend),
    quests = tonumber(c.quest), spawns = tonumber(c.spw), dungeons = tonumber(c.dng),
    idxDrops = JobText("npcItems", tonumber(c.drop)), idxItems = JobText("itemNames", tonumber(c.item)),
    idxNpcs = JobText("npcNames", tonumber(c.npc)),
    idxMaps = jobs.mapMobsW and JobText("mapMobsW", tonumber(c.spw)) or JobText("mapMobs", tonumber(c.spm)),
  }
end)

F.Status = Guard("status", function()
  local i = F.Info() or {}
  if not i.enabled then
    return "ForeverDB data off (/sw fdb on)"
  end
  if not i.available then
    return "ForeverDB data not installed (folder ForeverDBData; see README)"
  end
  if not i.loaded then
    local extra = i.failed and (" · load failed: " .. tostring(i.failed)) or (i.waiting and " · waiting for combat to end" or " · loads on first search / hunt / target panel")
    return "ForeverDB data: not loaded" .. extra
  end
  return string.format("ForeverDB data build %s · %s npcs, %s items, %s drop tables, %s vendors, %s quests, %s spawns, %s dungeons · loaded from %s in %s ms%s · index drops %s, item names %s, npc names %s, maps %s",
    tostring(i.build), tostring(i.npcs or "?"), tostring(i.items or "?"), tostring(i.drops or "?"), tostring(i.vendors or "?"),
    tostring(i.quests or "?"), tostring(i.spawns or "?"), tostring(i.dungeons or "?"), tostring(i.folder or "?"),
    i.ms and string.format("%.0f", i.ms) or "?", i.kb and string.format(" · ~%.1f MB in memory", i.kb / 1024) or " · ~12 MB file data in memory",
    i.idxDrops, i.idxItems, i.idxNpcs, i.idxMaps)
end)

--- Short lines for Settings > Forever.
function F.BridgeLine()
  local i = F.Info() or {}
  if not i.enabled then
    return "ForeverDB data: off"
  elseif not i.available then
    return "ForeverDB data: not installed (install the ForeverDBData addon, see README)"
  elseif not i.loaded then
    return "ForeverDB data: installed, loads on first search / hunt / target panel"
  end
  return string.format("ForeverDB data: build %s, %s npcs, %s items, %s drop tables, %s spawns, %s dungeons", tostring(i.build),
    tostring(i.npcs or "?"), tostring(i.items or "?"), tostring(i.drops or "?"), tostring(i.spawns or "?"), tostring(i.dungeons or "?"))
end

-- slash -----------------------------------------------------------------------------------------------------

F.Slash = Guard("slash", function(rest)
  local cmd = (tostring(rest or ""):match("^%s*(%S*)") or ""):lower()
  local f = Seekwell.Config.Get().forever
  if cmd == "on" or cmd == "off" then
    f.fdbData = (cmd == "on")
    Bump()
    if f.fdbData then
      st.tried = false
      F.Load()
    end
    Note("ForeverDB data " .. cmd)
  elseif cmd == "reload" then
    st.tried, st.failed = false, nil
    ResetIndexes()
    if st.loaded then
      Bump()
      StartIndexes()
    else
      F.Load()
    end
    Note((F.Status()))
  elseif cmd == "" or cmd == "status" then
    Note((F.Status()))
  else
    Note("usage: /sw fdb status|on|off|reload")
  end
end)

--- test hook: forget load state and indexes (the global stays)
function F._Reset()
  st = { loaded = false, tried = false, failed = nil, waiting = false, folder = nil, ms = nil, kb = nil, noted = false }
  ResetIndexes()
  gen = gen + 1
end

if Seekwell.RegisterSlash then
  Seekwell.RegisterSlash("fdb", function(rest)
    F.Slash(rest)
  end)
end
if Seekwell.RegisterStatus then
  Seekwell.RegisterStatus("fdb", function()
    return (F.Status())
  end)
end
if Seekwell.L and type(Seekwell.L.HELP_LINES) == "table" then
  table.insert(Seekwell.L.HELP_LINES, "/sw fdb [status|on|off|reload] — ForeverDB data addon (ForeverDBData): Forever drops, names, spawns")
end
