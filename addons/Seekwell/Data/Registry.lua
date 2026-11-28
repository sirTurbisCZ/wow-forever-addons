--[[
  Seekwell.Registry — merges the data sources and labels each value with its origin.
    "forever"  measured Forever drop rates from Tinny (shown with kills n)
    "learned"  your own loot windows (drops / kills)
    "forever_db" the ForeverDB data addon (Data/FDBBridge.lua; label "ForeverDB (kills)")
    "classic"  Tinny's Classic estimates (optional)
  Ranking: learned / Tinny Forever > ForeverDB > Classic > extra providers; a lower source never overwrites a row.
  Per item: Forever beats everything; learned beats Classic once it has LEARNED_MIN kills.
  Percentages are never invented: no value = "—".
]]

Seekwell = Seekwell or {}
local R = {}
Seekwell.Registry = R

local LEARNED_MIN = 10 -- learned kills needed before your own rate replaces a Classic estimate
local ITEM_LRU = 500
local itemCache, itemCount, itemTick = {}, 0, 0
R.LEARNED_MIN = LEARNED_MIN

local function Settings()
  return Seekwell.Config.Get()
end

local function L()
  return Seekwell.L or {}
end

local function FDB()
  local F = Seekwell.FDB
  if F and F.Data and F.Data() then
    return F
  end
  return nil
end

local function TinnyNpc(npcID)
  local T = Seekwell.Tinny
  if not T then
    return nil
  end
  local ok, v = pcall(T.GetNpc, npcID)
  if ok then
    return v
  end
  if Seekwell.RecordError then
    Seekwell.RecordError("tinny.npc", v)
  end
  return nil
end

-- Extra providers (e.g. Net/Share.lua), consulted after the built-in sources and ranked below them:
--   R.RegisterExtra(name, { npc = fn(npcID) -> rows {id, p, n, d, origin, label}, item = fn(itemID) -> rows {npc, p, n, origin, label} })
local extras = {}
function R.RegisterExtra(name, def)
  if type(def) == "table" then
    extras[#extras + 1] = { name = name, npc = def.npc, item = def.item }
  end
end

local function ExtraRows(kind, id)
  local out = {}
  for _, x in ipairs(extras) do
    if type(x[kind]) == "function" then
      local ok, rows = pcall(x[kind], id)
      if ok and type(rows) == "table" then
        for _, r in ipairs(rows) do
          out[#out + 1] = r
        end
      elseif not ok and Seekwell.RecordError then
        Seekwell.RecordError("registry.extra." .. tostring(x.name), rows)
      end
    end
  end
  return out
end

function R.NpcName(npcID)
  local n = Seekwell.Loot and Seekwell.Loot.CachedName and Seekwell.Loot.CachedName(npcID)
  if n then
    return n
  end
  n = Seekwell.Learned.Name(npcID)
  if n then
    return n
  end
  local T = Seekwell.Tinny
  if T then
    local ok, v = pcall(T.NpcName, npcID)
    if ok and v then
      return v
    end
  end
  local F = FDB()
  if F then
    local v = F.NpcName(npcID)
    if v then
      return v
    end
  end
  local DJ = Seekwell.DJ
  if DJ and DJ.NpcName then
    local ok, v = pcall(DJ.NpcName, npcID)
    if ok and v then
      return v
    end
  end
  return nil
end

local function SortRows(rows)
  table.sort(rows, function(a, b)
    local pa, pb = a.p or -1, b.p or -1
    if pa ~= pb then
      return pa > pb
    end
    return a.id < b.id
  end)
end

--- Drop table of an NPC: { id, name, foreverKills, learnedKills, minLevel, maxLevel,
---   hasForever, hasClassic, hasLearned, rows = { {id, p, origin, n, d, quest, skin, mine = {d, k}} } }
function R.NpcDrops(npcID)
  npcID = tonumber(npcID)
  if not npcID then
    return nil
  end
  local s = Settings()
  local tn = TinnyNpc(npcID)
  local lrows, lk = Seekwell.Learned.Items(npcID)
  local out = {
    id = npcID, name = R.NpcName(npcID), learnedKills = lk or 0,
    foreverKills = tn and tn.foreverKills, minLevel = tn and tn.minLevel, maxLevel = tn and tn.maxLevel,
  }
  local F = FDB()
  if F and not (out.minLevel and out.maxLevel) then
    local fn = F.Npc(npcID)
    if fn then
      out.minLevel, out.maxLevel = out.minLevel or fn.minLv, out.maxLevel or fn.maxLv
    end
  end
  local byId, rows = {}, {}
  local function Add(row)
    byId[row.id] = row
    rows[#rows + 1] = row
  end
  if tn and tn.forever and #tn.forever > 0 then
    out.hasForever = true
    for _, r in ipairs(tn.forever) do
      if not byId[r.id] then
        Add({ id = r.id, p = r.p, origin = "forever", n = r.k or tn.foreverKills, d = r.d })
      end
    end
  end
  if lrows and #lrows > 0 then
    out.hasLearned = true
    for _, r in ipairs(lrows) do
      local ex = byId[r.id]
      if ex then
        ex.mine = { d = r.d, k = r.k }
      else
        Add({ id = r.id, p = r.p, origin = "learned", n = r.k, d = r.d, mine = { d = r.d, k = r.k } })
      end
    end
  end
  local fdrops = F and F.Drops(npcID)
  if fdrops and #fdrops > 0 then
    out.hasFdb = true -- ForeverDB: below Tinny Forever and learned, above Classic estimates
    local n = F.Kills(npcID)
    for _, r in ipairs(fdrops) do
      if not byId[r.item] then
        Add({ id = r.item, p = r.p, origin = "forever_db", n = n, label = F.Label(npcID) })
      end
    end
  end
  if tn and tn.classic and #tn.classic > 0 then
    for _, r in ipairs(tn.classic) do
      local ex = byId[r.id]
      if ex then
        if r.quest then
          ex.quest = true -- the quest marker is used even when estimates are off
        end
        if s.classic and ex.origin == "learned" and (lk or 0) < LEARNED_MIN then
          ex.origin, ex.p, ex.n, ex.skin = "classic", r.p, nil, r.skin
        end
      elseif s.classic then
        out.hasClassic = true
        Add({ id = r.id, p = r.p, origin = "classic", quest = r.quest, skin = r.skin })
      end
    end
    if s.classic then
      out.hasClassic = true
    end
  end
  if s.hideQuest then
    local kept = {}
    for _, r in ipairs(rows) do
      if not r.quest then
        kept[#kept + 1] = r
      end
    end
    rows = kept
  end
  SortRows(rows)
  local extra = {}
  for _, r in ipairs(ExtraRows("npc", npcID)) do
    if r.id and not byId[r.id] then
      byId[r.id] = r
      extra[#extra + 1] = r
    end
  end
  if #extra > 0 then
    out.hasExtra = true
    SortRows(extra) -- extra rows stay below every built-in row
    for _, r in ipairs(extra) do
      rows[#rows + 1] = r
    end
  end
  out.rows = rows
  out.name = out.name or (tn and (tn.name or tn.classicName)) or (F and F.NpcName(npcID))
  return out
end

-- Cheap eviction: when the cache is full it is dropped as a whole (the old oldest-entry scan walked every entry on each
-- insert, 60k steps for one filtered search).
local function EvictItem()
  itemCache, itemCount = {}, 0
end

local function BuildSources(itemID, limit)
  local s = Settings()
  local ff, sf = {}, {}
  local T = Seekwell.Tinny
  if T then
    local ok, a, b = pcall(T.From, itemID, limit)
    if ok then
      ff, sf = a or {}, b or {}
    elseif Seekwell.RecordError then
      Seekwell.RecordError("tinny.from", a)
    end
  end
  local byNpc, rows = {}, {}
  for _, r in ipairs(ff) do
    if not byNpc[r.npc] then
      local row = { npc = r.npc, p = r.p, origin = "forever", rank = 1 }
      byNpc[r.npc] = row
      rows[#rows + 1] = row
    end
  end
  local classicBy = {}
  if s.classic then
    for _, r in ipairs(sf) do
      classicBy[r.npc] = r
    end
  end
  for _, r in ipairs(Seekwell.Learned.From(itemID)) do
    local ex = byNpc[r.npc]
    local cr = classicBy[r.npc]
    if ex then
      ex.mine = { d = r.d, k = r.k }
    elseif cr and (r.k or 0) < LEARNED_MIN then
      -- too few own kills: keep the Classic estimate (as the mob page does), but remember the own numbers
      local row = { npc = r.npc, p = cr.p, origin = "classic", skin = cr.skin, rank = 3, mine = { d = r.d, k = r.k } }
      byNpc[r.npc] = row
      rows[#rows + 1] = row
    else
      local row = { npc = r.npc, p = r.p, origin = "learned", n = r.k, rank = 1, mine = { d = r.d, k = r.k } }
      byNpc[r.npc] = row
      rows[#rows + 1] = row
    end
  end
  local F = FDB()
  if F then
    for _, r in ipairs(F.ItemSources(itemID, limit) or {}) do
      if not byNpc[r.npc] then
        r.rank = 2
        byNpc[r.npc] = r
        rows[#rows + 1] = r
      end
    end
  end
  if s.classic then
    for _, r in ipairs(sf) do
      if not byNpc[r.npc] then
        local row = { npc = r.npc, p = r.p, origin = "classic", skin = r.skin, rank = 3 }
        byNpc[r.npc] = row
        rows[#rows + 1] = row
      end
    end
  end
  for _, r in ipairs(ExtraRows("item", itemID)) do
    if r.npc and not byNpc[r.npc] then
      r.rank = 4
      byNpc[r.npc] = r
      rows[#rows + 1] = r
    end
  end
  table.sort(rows, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    if (a.p or -1) ~= (b.p or -1) then
      return (a.p or -1) > (b.p or -1)
    end
    return a.npc < b.npc
  end)
  local out = {}
  for i = 1, math.min(limit, #rows) do
    out[i] = rows[i]
  end
  return out
end

--- Best sources of an item: { {npc, p, origin, n, skin, mine} }, Forever / learned before Classic. Cached.
function R.ItemSources(itemID, limit)
  itemID = tonumber(itemID)
  limit = math.max(1, math.min(200, tonumber(limit) or 5))
  if not itemID then
    return {}
  end
  local s = Settings()
  local gen = Seekwell.Learned.generation
  itemTick = itemTick + 1
  local e = itemCache[itemID]
  local fgen = Seekwell.FDB and Seekwell.FDB.Generation and Seekwell.FDB.Generation() or 0
  if e and e.gen == gen and e.fgen == fgen and e.classic == s.classic and e.limit >= limit then
    e.t = itemTick
    if e.limit == limit then
      return e.rows
    end
    local cut = {}
    for i = 1, math.min(limit, #e.rows) do
      cut[i] = e.rows[i]
    end
    return cut
  end
  local rows = BuildSources(itemID, limit)
  if not e then
    if itemCount >= ITEM_LRU then
      EvictItem()
    end
    itemCount = itemCount + 1
  end
  itemCache[itemID] = { rows = rows, gen = gen, fgen = fgen, classic = s.classic, limit = limit, t = itemTick }
  return rows
end

function R.ClearCache()
  itemCache, itemCount = {}, 0
end

--- "12.5 %", "0.34 %", or "—".
function R.FormatPct(p)
  p = tonumber(p)
  if not p then
    return L().UNKNOWN or "-"
  end
  local s
  if p >= 1 then
    s = string.format("%.1f", p)
  else
    s = string.format("%.2f", p)
  end
  s = s:gsub("(%.%d-)0+$", "%1"):gsub("%.$", "")
  return s .. " %"
end

--- "Forever n=55", "Classic estimate", "learned 2/15".
function R.OriginLabel(row)
  local Lx = L()
  if not row or not row.origin then
    return Lx.UNKNOWN or "-"
  end
  if row.origin == "forever" then
    return (Lx.ORIGIN_FOREVER or "Forever") .. (row.n and (" n=" .. tostring(row.n)) or "")
  elseif row.origin == "learned" then
    local m = row.mine
    if m and m.k then
      return "learned " .. tostring(m.d or 0) .. "/" .. tostring(m.k)
    end
    return Lx.ORIGIN_LEARNED or "learned (yours)"
  elseif row.origin == "classic" then
    return (Lx.ORIGIN_CLASSIC or "Classic estimate") .. (row.skin and " (skinning)" or "")
  elseif type(row.label) == "string" then
    return row.label
  end
  return Lx.UNKNOWN or "-"
end
