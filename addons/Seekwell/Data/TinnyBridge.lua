--[[
  Seekwell.Tinny — read-only bridge to the TnnysMobLoot runtime data tables.
  Only the globals TnnysMobLoot_Forever and TnnysMobLoot_Starter are read (never Tinny's SavedVariables),
  nothing is copied or saved. An NPC's packed string is parsed when asked for and kept in a small LRU.

  Forever: npc[npcID] = { "name", "itemID:percent:drops:kills,..." }, from[itemID] = "npcID:percent,..." (best first)
  Starter: npc[npcID] = { "itemID:percent[:q],...", "skinning list", worldDrops, "Name", minLevel, maxLevel, map },
           from[itemID] = "npcID:percent[:s],..." (s = skinning, best first)
  Percent values are percent (12.5 = 12.5 %).
]]

Seekwell = Seekwell or {}
local T = {}
Seekwell.Tinny = T

local LRU_MAX = 200
local npcCache, npcCount, tick = {}, 0, 0
local counts -- { forever = n, starter = n } counted once on request

local function Forever()
  local t = rawget(_G, "TnnysMobLoot_Forever")
  return type(t) == "table" and t or nil
end

local function Starter()
  local t = rawget(_G, "TnnysMobLoot_Starter")
  return type(t) == "table" and t or nil
end

local function Sub(t, key)
  local v = t and t[key]
  return type(v) == "table" and v or nil
end

function T.HasForever()
  return Sub(Forever(), "npc") ~= nil
end

function T.HasStarter()
  return Sub(Starter(), "npc") ~= nil
end

function T.Available()
  return T.HasForever() or T.HasStarter()
end

function T.AsOf()
  local f = Forever()
  local a = f and f.asOf
  return type(a) == "string" and a or nil
end

local function CountKeys(t)
  local n = 0
  if t then
    for _ in pairs(t) do
      n = n + 1
    end
  end
  return n
end

--- { forever = n, starter = n, foreverFrom = n } (counted once, on request only).
function T.Counts()
  if not counts then
    counts = {
      forever = CountKeys(Sub(Forever(), "npc")),
      starter = CountKeys(Sub(Starter(), "npc")),
      foreverFrom = CountKeys(Sub(Forever(), "from")),
    }
  end
  return counts
end

-- "itemID:percent:drops:kills,..." -> { {id, p, d, k}, ... }, max kills
local function ParseForeverList(s)
  local rows, maxK = {}, 0
  if type(s) ~= "string" or s == "" then
    return rows, nil
  end
  for part in s:gmatch("[^,]+") do
    local id, pct, d, k = part:match("^(%d+):([%d%.]+):?(%d*):?(%d*)$")
    id, pct = tonumber(id), tonumber(pct)
    if id and pct then
      local kills = tonumber(k)
      rows[#rows + 1] = { id = id, p = pct, d = tonumber(d), k = kills }
      if kills and kills > maxK then
        maxK = kills
      end
    end
  end
  return rows, (maxK > 0) and maxK or nil
end
T.ParseForeverList = ParseForeverList

-- "itemID:percent[:q],..." -> { {id, p, quest}, ... }; skin = true marks the skinning list
local function ParseStarterList(s, skin)
  local rows = {}
  if type(s) ~= "string" or s == "" then
    return rows
  end
  for part in s:gmatch("[^,]+") do
    local id, pct, flag = part:match("^(%d+):([%d%.]+):?(%a?)$")
    id, pct = tonumber(id), tonumber(pct)
    if id and pct then
      rows[#rows + 1] = { id = id, p = pct, quest = (flag == "q"), skin = skin or nil }
    end
  end
  return rows
end
T.ParseStarterList = ParseStarterList

local function Evict()
  local oldK, oldT
  for k, e in pairs(npcCache) do
    if not oldT or e.t < oldT then
      oldK, oldT = k, e.t
    end
  end
  if oldK then
    npcCache[oldK] = nil
    npcCount = npcCount - 1
  end
end

local function Parse(npcID)
  local out = { id = npcID }
  local f = Sub(Forever(), "npc")
  local fv = f and f[npcID]
  if type(fv) == "table" then
    local name = fv[1]
    if type(name) == "string" and name ~= "" then
      out.name = name
    end
    out.forever, out.foreverKills = ParseForeverList(fv[2])
  end
  local s = Sub(Starter(), "npc")
  local st = s and s[npcID]
  if type(st) == "table" then
    out.classic = ParseStarterList(st[1])
    local skin = ParseStarterList(st[2], true)
    for i = 1, #skin do
      out.classic[#out.classic + 1] = skin[i]
    end
    if type(st[4]) == "string" and st[4] ~= "" then
      out.classicName = st[4]
    end
    out.minLevel = tonumber(st[5])
    out.maxLevel = tonumber(st[6])
  end
  if not out.forever and not out.classic then
    return false
  end
  return out
end

--- Parsed Tinny data for an NPC, or nil. { name, forever = rows, foreverKills, classic = rows, classicName, minLevel, maxLevel }
function T.GetNpc(npcID)
  npcID = tonumber(npcID)
  if not npcID then
    return nil
  end
  tick = tick + 1
  local e = npcCache[npcID]
  if e then
    e.t = tick
    return e.v or nil
  end
  local v = Parse(npcID)
  if npcCount >= LRU_MAX then
    Evict()
  end
  npcCache[npcID] = { v = v, t = tick }
  npcCount = npcCount + 1
  return v or nil
end

function T.CacheSize()
  return npcCount
end

function T.NpcName(npcID)
  local f = Sub(Forever(), "npc")
  local fv = f and f[npcID]
  if type(fv) == "table" and type(fv[1]) == "string" and fv[1] ~= "" then
    return fv[1]
  end
  local s = Sub(Starter(), "npc")
  local st = s and s[npcID]
  if type(st) == "table" and type(st[4]) == "string" and st[4] ~= "" then
    return st[4]
  end
  return nil
end

-- "npcID:percent[:s],..." -> up to limit { npc, p, skin }; the lists are best first, so parsing stops early.
local function ParseFrom(s, limit)
  local rows = {}
  if type(s) ~= "string" or s == "" then
    return rows
  end
  for part in s:gmatch("[^,]+") do
    local id, pct, flag = part:match("^(%d+):([%d%.]+):?(%a?)$")
    id, pct = tonumber(id), tonumber(pct)
    if id and pct then
      rows[#rows + 1] = { npc = id, p = pct, skin = (flag == "s") or nil }
      if #rows >= limit then
        break
      end
    end
  end
  return rows
end
T.ParseFrom = ParseFrom

--- Best sources of an item: forever rows, classic rows (each up to limit).
function T.From(itemID, limit)
  itemID = tonumber(itemID)
  limit = limit or 5
  if not itemID then
    return {}, {}
  end
  local ff = Sub(Forever(), "from")
  local sf = Sub(Starter(), "from")
  return ParseFrom(ff and ff[itemID], limit), ParseFrom(sf and sf[itemID], limit)
end

local itemNames -- lazily built { {id, name, lower} } from Starter.item (Classic items only)

--- Items whose name contains `lower` (already lowercase), from Tinny's Starter item table: { {id=, name=} }.
function T.FindItems(lower, limit)
  limit = limit or 40
  if not itemNames then
    itemNames = {}
    local it = Sub(Starter(), "item")
    if it then
      for id, e in pairs(it) do
        local name = type(e) == "table" and e[2]
        if type(id) == "number" and type(name) == "string" and name ~= "" then
          itemNames[#itemNames + 1] = { id = id, name = name, lower = name:lower() }
        end
      end
    end
  end
  local out = {}
  for _, e in ipairs(itemNames) do
    if e.lower:find(lower, 1, true) then
      out[#out + 1] = { id = e.id, name = e.name }
      if #out >= limit * 4 then
        break
      end
    end
  end
  return out
end

--- Forget parsed entries (e.g. after Tinny data appeared later).
function T.ClearCache()
  npcCache, npcCount, counts, itemNames = {}, 0, nil, nil
end
