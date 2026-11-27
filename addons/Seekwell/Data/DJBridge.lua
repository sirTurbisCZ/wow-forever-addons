--[[
  Seekwell.DJ — read-only RUNTIME bridge to the ForeverDungeonJournal addon (optional, never required, nothing copied).
  Reads only the global ForeverDungeonJournal_NS: .DB[dungeonName] = { level = "13-20", location = "text",
    quests = { {id, name, level, rewardItems = { {itemID, name, quality} }, noteItem = {itemID, name, ...}} },
    bosses = { {name, npcID, loot = { {itemID, name, slot, quality} }, trash, recipeTab} },
    entrance = { mapID, x, y, label, detail } (set by its Data/DungeonEntrances.lua) },
  and .SHARED_BY_BOSS[dungeon][boss] = { {itemID, name, slot, quality} } (Data/SharedLoot.lua).
  Not loaded / disabled (settings.forever.dj = false) -> every call returns empty, never errors.

    DJ.Available(), DJ.Dungeons() -> sorted { {name, level, location, bosses = n, quests = n, entrance} }
    DJ.ItemSources(itemID) -> { {source="dungeon"|"djquest", dungeon, boss, bossIndex, questID, quest, label} }
    DJ.QuestRewards(itemID), DJ.Entrance(name) -> mapID, x, y, label, learned
    DJ.Find(q) dungeon name match, DJ.Page(name) per-dungeon page data, DJ.ItemName(id), DJ.NpcName(id)
    DJ.Open(name, bossIndex) opens the journal through FDJ.OpenBossPage when it exists
  The item index is built once, lazily (a few ms for ~40 dungeons), compact: item -> list of small records.
]]

Seekwell = Seekwell or {}
local DJ = {}
Seekwell.DJ = DJ

local idx -- { item = {[id] = {rec...}}, names = {[id] = name}, npc = {[id] = name}, list = {dungeon...}, byName = {} }
local builtFor

local function Settings()
  local ok, s = pcall(Seekwell.Config.Get)
  return ok and s or {}
end

local function Enabled()
  local f = Settings().forever
  return not (type(f) == "table" and f.dj == false)
end

local function NS()
  if not Enabled() then
    return nil
  end
  local ns = rawget(_G, "ForeverDungeonJournal_NS")
  if type(ns) == "table" and type(ns.DB) == "table" then
    return ns
  end
  return nil
end
DJ.NS = NS

function DJ.Available()
  return NS() ~= nil
end

local function Rec(t, id, r)
  id = tonumber(id)
  if not id then
    return
  end
  local l = t[id]
  if not l then
    l = {}
    t[id] = l
  end
  for _, x in ipairs(l) do
    if x.d == r.d and x.b == r.b and x.q == r.q then
      return
    end
  end
  l[#l + 1] = r
end

local function Build(ns)
  local out = { item = {}, names = {}, npc = {}, list = {}, byName = {}, byLower = {}, nLoot = 0, nQuestItems = 0, nBoss = 0, nQuest = 0, nEnt = 0 }
  local names = {}
  for name, d in pairs(ns.DB) do
    if type(name) == "string" and type(d) == "table" then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  local lootSeen, questSeen = {}, {}
  local shared = type(ns.SHARED_BY_BOSS) == "table" and ns.SHARED_BY_BOSS or {}
  for di, name in ipairs(names) do
    local d = ns.DB[name]
    local e = { name = name, index = di, level = type(d.level) == "string" and d.level or (d.level and tostring(d.level)),
      location = type(d.location) == "string" and d.location or nil, bosses = 0, quests = 0 }
    local ent = d.entrance
    if type(ent) == "table" and tonumber(ent.mapID) and tonumber(ent.x) and tonumber(ent.y) then
      e.entrance = { mapID = tonumber(ent.mapID), x = tonumber(ent.x), y = tonumber(ent.y), label = ent.label, detail = ent.detail }
      out.nEnt = out.nEnt + 1
    end
    local function AddLoot(it, bossName, bi, trash)
      if type(it) == "table" and tonumber(it[1]) then
        local id = tonumber(it[1])
        Rec(out.item, id, { k = "boss", d = name, b = bossName, bi = bi, t = trash or nil })
        if type(it[2]) == "string" and not out.names[id] then
          out.names[id] = it[2]
        end
        if not lootSeen[id] then
          lootSeen[id] = true
          out.nLoot = out.nLoot + 1
        end
      end
    end
    for bi, b in ipairs(type(d.bosses) == "table" and d.bosses or {}) do
      if type(b) == "table" and type(b.name) == "string" and not b.recipeTab then
        if not b.trash then
          e.bosses = e.bosses + 1
          out.nBoss = out.nBoss + 1
        end
        if tonumber(b.npcID) then
          out.npc[tonumber(b.npcID)] = b.name
        end
        for _, it in ipairs(type(b.loot) == "table" and b.loot or {}) do
          AddLoot(it, b.name, bi, b.trash)
        end
        local sh = type(shared[name]) == "table" and shared[name][b.name]
        for _, it in ipairs(type(sh) == "table" and sh or {}) do
          AddLoot(it, b.name, bi, b.trash)
        end
      end
    end
    for _, q in ipairs(type(d.quests) == "table" and d.quests or {}) do
      if type(q) == "table" then
        e.quests = e.quests + 1
        out.nQuest = out.nQuest + 1
        for _, it in ipairs(type(q.rewardItems) == "table" and q.rewardItems or {}) do
          if type(it) == "table" and tonumber(it[1]) then
            local id = tonumber(it[1])
            Rec(out.item, id, { k = "quest", d = name, q = tonumber(q.id), qn = type(q.name) == "string" and q.name or nil })
            if type(it[2]) == "string" and not out.names[id] then
              out.names[id] = it[2]
            end
            if not questSeen[id] then
              questSeen[id] = true
              out.nQuestItems = out.nQuestItems + 1
            end
          end
        end
      end
    end
    out.list[di] = e
    out.byName[name] = e
    out.byLower[name:lower()] = e
  end
  return out
end

local function Index()
  local ns = NS()
  if not ns then
    return nil
  end
  if idx and builtFor == ns.DB then
    return idx
  end
  local ok, r = pcall(Build, ns)
  if ok then
    idx, builtFor = r, ns.DB
    return idx
  end
  if Seekwell.RecordError then
    Seekwell.RecordError("dj.build", r)
  end
  return nil
end
DJ.Index = Index

function DJ.Reset()
  idx, builtFor = nil, nil
end

function DJ.Counts()
  local x = Index()
  if not x then
    return nil
  end
  return { dungeons = #x.list, bosses = x.nBoss, loot = x.nLoot, quests = x.nQuest, questItems = x.nQuestItems, entrances = x.nEnt }
end

function DJ.Dungeons()
  local x = Index()
  return x and x.list or {}
end

function DJ.Get(nameOrIndex)
  local x = Index()
  if not x then
    return nil
  end
  if type(nameOrIndex) == "number" then
    return x.list[nameOrIndex]
  end
  if type(nameOrIndex) ~= "string" then
    return nil
  end
  return x.byName[nameOrIndex] or (x.byLower and x.byLower[nameOrIndex:lower()])
end

--- Name normalised for matching: lower case, letters and digits only, no leading "the".
local function Norm(s)
  s = tostring(s or ""):lower():gsub("^the%s+", "")
  return (s:gsub("[^%w]", ""))
end
DJ.Norm = Norm

--- Fuzzy match of two instance names (exact after Norm, or one contains the other, at least 6 letters).
function DJ.NamesMatch(a, b)
  local x, y = Norm(a), Norm(b)
  if x == "" or y == "" then
    return false
  end
  if x == y then
    return true
  end
  if #x >= 6 and #y >= 6 and (x:find(y, 1, true) or y:find(x, 1, true)) then
    return true
  end
  return false
end

--- Journal entry for an instance name from GetInstanceInfo (exact, case-insensitive, then fuzzy).
function DJ.FindByInstance(name)
  local e = DJ.Get(name)
  if e or type(name) ~= "string" then
    return e
  end
  for _, d in ipairs(DJ.Dungeons()) do
    if DJ.NamesMatch(d.name, name) then
      return d
    end
  end
  return nil
end

--- Learned entrance (Learn/Position.lua) of a dungeon: mapID, x, y (0..1).
local function LearnedEntrance(name)
  local db = rawget(_G, "SeekwellDB")
  local le = type(db) == "table" and type(db.learned) == "table" and db.learned.entrance
  if type(le) ~= "table" or type(name) ~= "string" then
    return nil
  end
  local function Ok(e)
    return type(e) == "table" and tonumber(e.m) and tonumber(e.x) and tonumber(e.y)
  end
  local e = le[name]
  if not Ok(e) then
    e = le[name:lower()]
  end
  if not Ok(e) then
    -- case-insensitive, then fuzzy (e.g. "Scarlet Monastery" learned for the journal's wing pages)
    local lower, best = name:lower(), nil
    for k, v in pairs(le) do
      if type(k) == "string" and Ok(v) then
        if k:lower() == lower then
          best = v
          break
        elseif not best and DJ.NamesMatch(k, name) then
          best = v
        end
      end
    end
    e = best
  end
  if Ok(e) then
    return tonumber(e.m), tonumber(e.x), tonumber(e.y)
  end
  return nil
end
DJ.LearnedEntrance = LearnedEntrance

--- mapID, x, y, label, learned (true when it came from your own play).
function DJ.Entrance(name)
  local e = DJ.Get(name)
  if e and e.entrance then
    return e.entrance.mapID, e.entrance.x, e.entrance.y, e.entrance.label or (e.name .. " Entrance"), false
  end
  if type(name) ~= "string" then
    name = e and e.name
  end
  if not name then
    return nil
  end
  local m, x, y = LearnedEntrance(name)
  if m then
    return m, x, y, name .. " Entrance (learned)", true
  end
  local F = Seekwell.FDB
  if F and F.Entrance then
    local fm, fx, fy, fname = F.Entrance(name)
    if fm then
      return fm, fx, fy, (fname or name) .. " Entrance (ForeverDB)", false
    end
  end
  return nil
end

function DJ.EntranceTooltip(name)
  local e = DJ.Get(name)
  if not e then
    return "Dungeon entrance: " .. tostring(name)
  end
  return string.format("Dungeon entrance: %s (%s%d bosses)", e.name, e.level and ("levels " .. e.level .. ", ") or "", e.bosses)
end

local function Label(r)
  if r.k == "quest" then
    return r.d .. " \226\128\148 quest: " .. (r.qn or ("quest " .. tostring(r.q)))
  end
  return r.d .. " \226\128\148 " .. (r.b or "?")
end

--- Dungeon Journal sources of an item (bosses and dungeon quest rewards).
function DJ.ItemSources(itemID)
  local x = Index()
  local l = x and x.item[tonumber(itemID) or -1]
  local out = {}
  for _, r in ipairs(l or {}) do
    out[#out + 1] = { source = r.k == "quest" and "djquest" or "dungeon", dungeon = r.d, boss = r.b, bossIndex = r.bi,
      questID = r.q, quest = r.qn, trash = r.t, label = Label(r), origin = "dj" }
  end
  return out
end

function DJ.QuestRewards(itemID)
  local out = {}
  for _, r in ipairs(DJ.ItemSources(itemID)) do
    if r.source == "djquest" then
      out[#out + 1] = r
    end
  end
  return out
end

--- Registry extra rows: bosses with an npc id become a normal drop source (rank 3, chance unknown).
function DJ.RegistryRows(itemID)
  local out, seen = {}, {}
  local x = Index()
  if not x then
    return out
  end
  local ns = NS()
  for _, r in ipairs(DJ.ItemSources(itemID)) do
    if r.source == "dungeon" and r.bossIndex then
      local d = ns.DB[r.dungeon]
      local b = d and type(d.bosses) == "table" and d.bosses[r.bossIndex]
      local npc = type(b) == "table" and tonumber(b.npcID)
      if npc and not seen[npc] then
        seen[npc] = true
        out[#out + 1] = { npc = npc, p = nil, origin = "dj", source = "dungeon", dungeon = r.dungeon, boss = r.boss,
          label = "Dungeon Journal: " .. r.label }
      end
    end
  end
  return out
end

function DJ.ItemName(id)
  local x = Index()
  return x and x.names[tonumber(id) or -1] or nil
end

function DJ.NpcName(id)
  local x = Index()
  return x and x.npc[tonumber(id) or -1] or nil
end

function DJ.HasItem(id)
  local x = Index()
  return x and x.item[tonumber(id) or -1] ~= nil or false
end

function DJ.HasNpc(id)
  local x = Index()
  return x and x.npc[tonumber(id) or -1] ~= nil or false
end

--- Items whose DJ name contains lower: { {id, name} }.
function DJ.FindItems(lower, limit)
  local x = Index()
  local out = {}
  if not x or type(lower) ~= "string" or lower == "" then
    return out
  end
  limit = limit or 40
  for id, n in pairs(x.names) do
    if n:lower():find(lower, 1, true) then
      out[#out + 1] = { id = id, name = n }
      if #out >= limit * 4 then
        break
      end
    end
  end
  return out
end

--- Dungeons whose name (or location) contains q: list of dungeon entries, name matches first.
function DJ.Find(q)
  local out = {}
  q = tostring(q or ""):lower():match("^%s*(.-)%s*$")
  for _, e in ipairs(DJ.Dungeons()) do
    local n = e.name:lower()
    if q == "" or n:find(q, 1, true) then
      out[#out + 1] = e
    end
  end
  return out
end

--- Page data: { name, level, location, entrance, bosses = { {name, npcID, index, trash, loot = { {id, name, slot, quality} }} },
---   quests = { {id, name, level, rewards = { {id, name, quality} }} } }
function DJ.Page(nameOrIndex)
  local e = DJ.Get(nameOrIndex)
  local ns = NS()
  if not (e and ns) then
    return nil
  end
  local d = ns.DB[e.name]
  local page = { name = e.name, index = e.index, level = e.level, location = e.location, bosses = {}, quests = {} }
  page.mapID, page.x, page.y, page.entranceLabel, page.learned = DJ.Entrance(e.name)
  local shared = type(ns.SHARED_BY_BOSS) == "table" and type(ns.SHARED_BY_BOSS[e.name]) == "table" and ns.SHARED_BY_BOSS[e.name] or {}
  for bi, b in ipairs(type(d.bosses) == "table" and d.bosses or {}) do
    if type(b) == "table" and type(b.name) == "string" and not b.recipeTab then
      local pb = { name = b.name, npcID = tonumber(b.npcID), index = bi, trash = b.trash and true or nil, loot = {} }
      local function Add(it)
        if type(it) == "table" and tonumber(it[1]) then
          pb.loot[#pb.loot + 1] = { id = tonumber(it[1]), name = it[2], slot = it[3], quality = tonumber(it[4]) }
        end
      end
      for _, it in ipairs(type(b.loot) == "table" and b.loot or {}) do
        Add(it)
      end
      for _, it in ipairs(type(shared[b.name]) == "table" and shared[b.name] or {}) do
        Add(it)
      end
      page.bosses[#page.bosses + 1] = pb
    end
  end
  for _, q in ipairs(type(d.quests) == "table" and d.quests or {}) do
    if type(q) == "table" then
      local pq = { id = tonumber(q.id), name = type(q.name) == "string" and q.name or ("quest " .. tostring(q.id)), level = q.level, rewards = {} }
      for _, it in ipairs(type(q.rewardItems) == "table" and q.rewardItems or {}) do
        if type(it) == "table" and tonumber(it[1]) then
          pq.rewards[#pq.rewards + 1] = { id = tonumber(it[1]), name = it[2], quality = tonumber(it[3]) }
        end
      end
      page.quests[#page.quests + 1] = pq
    end
  end
  return page
end

--- The journal's own public opener, or nil when that addon does not expose one.
function DJ.Opener()
  local ns = NS()
  if ns and type(ns.OpenBossPage) == "function" then
    return ns.OpenBossPage
  end
  return nil
end

function DJ.Open(name, bossIndex)
  local fn = DJ.Opener()
  if not fn then
    return false
  end
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  local ok, err = pcall(fn, name, bossIndex or 1)
  if not ok and Seekwell.RecordError then
    Seekwell.RecordError("dj.open", err)
  end
  return ok
end

-- Forever content --------------------------------------------------------------------------------

local function Sub(g, k)
  local t = rawget(_G, g)
  return type(t) == "table" and type(t[k]) == "table" and t[k] or nil
end

--- An item is Forever content only when Tinny's Starter (Classic) item table is loaded and lacks it while
--- Tinny's Forever data or the Dungeon Journal has it. No Starter data = no Forever badge at all.
function DJ.IsForeverItem(id)
  id = tonumber(id)
  if not id then
    return false
  end
  local sItem = Sub("TnnysMobLoot_Starter", "item")
  if not sItem then
    -- without Tinny's Classic (Starter) item table nothing tells Classic from Forever: no badge
    return false
  end
  if sItem[id] then
    return false
  end
  local ff = Sub("TnnysMobLoot_Forever", "from")
  if ff and ff[id] then
    return true
  end
  return DJ.HasItem(id) and true or false
end

function DJ.IsForeverNpc(id)
  id = tonumber(id)
  if not id then
    return false
  end
  local sNpc = Sub("TnnysMobLoot_Starter", "npc")
  if not sNpc then
    return false -- see IsForeverItem
  end
  if sNpc[id] then
    return false
  end
  local fn = Sub("TnnysMobLoot_Forever", "npc")
  if fn and fn[id] then
    return true
  end
  return DJ.HasNpc(id) and true or false
end

-- Registry + status (Util/Ext.lua extension points, at file load) --------------------------------

if Seekwell.Registry and Seekwell.Registry.RegisterExtra then
  Seekwell.Registry.RegisterExtra("dj", { item = DJ.RegistryRows })
end

if Seekwell.RegisterStatus then
  Seekwell.RegisterStatus("dungeon journal", function()
    if not Enabled() then
      return "Dungeon Journal bridge: off (settings.forever.dj)"
    end
    local c = DJ.Counts()
    if not c then
      return "Dungeon Journal bridge: ForeverDungeonJournal not loaded"
    end
    return string.format("Dungeon Journal: %d dungeons, %d bosses, %d loot items, %d quest reward items, %d entrances",
      c.dungeons, c.bosses, c.loot, c.questItems, c.entrances)
  end)
end

-- Forever content: status, slash commands, settings note ----------------------------------------

local function TinnyForeverNpcs()
  local t = Sub("TnnysMobLoot_Forever", "npc")
  local n = 0
  for _ in pairs(t or {}) do
    n = n + 1
  end
  return n
end

--- Lines describing which Forever bridges are active (settings note, /sw forever, tests).
function DJ.BridgeLines()
  local out = {}
  local nT = TinnyForeverNpcs()
  out[#out + 1] = nT > 0 and string.format("Tinny Forever data: %d npcs (measured drop rates)", nT) or "Tinny Forever data: not loaded"
  local c = DJ.Counts()
  if not Enabled() then
    out[#out + 1] = "Dungeon Journal: off (settings.forever.dj)"
  elseif c then
    out[#out + 1] = string.format("Dungeon Journal: %d dungeons / %d loot items, %d quest reward items, %d entrances", c.dungeons, c.loot,
      c.questItems, c.entrances)
  else
    out[#out + 1] = "Dungeon Journal: ForeverDungeonJournal not loaded"
  end
  if Seekwell.FDB and Seekwell.FDB.BridgeLine then
    local ok, l = pcall(Seekwell.FDB.BridgeLine)
    if ok and l then
      out[#out + 1] = l
    end
  end
  out[#out + 1] = "GatherLite: no (its node data is private to that addon and keyed by object id, not item: not used)"
  local db = rawget(_G, "SeekwellDB")
  local le = type(db) == "table" and type(db.learned) == "table" and db.learned.entrance
  local n = 0
  for _ in pairs(type(le) == "table" and le or {}) do
    n = n + 1
  end
  out[#out + 1] = string.format("Learned dungeon entrances: %d", n)
  return out
end

local function Browser()
  return Seekwell.Browser
end

if Seekwell.RegisterSlash then
  Seekwell.RegisterSlash("dungeon", function(rest)
    rest = tostring(rest or ""):match("^%s*(.-)%s*$")
    if not DJ.Available() then
      Seekwell.Print("Dungeons need the ForeverDungeonJournal addon (not loaded or settings.forever.dj off)")
    end
    local B = Browser()
    if B and B.Open then
      B.Open(rest, "dungeons")
      local hits = DJ.Find(rest)
      if rest ~= "" and #hits == 1 and B.Select then
        B.Select("dungeon", hits[1].index, true)
      end
    end
  end)
  Seekwell.RegisterSlash("forever", function(rest)
    rest = tostring(rest or ""):lower():match("^%s*(.-)%s*$")
    local s = Seekwell.Config.Get()
    if type(s.browser) ~= "table" then
      s.browser = {}
    end
    if rest == "on" or rest == "off" then
      s.browser.foreverOnly = rest == "on"
      Seekwell.Print("browser filter \"Forever content only\": " .. rest)
      local B = Browser()
      if B and B.Run then
        pcall(B.Run)
      end
    else
      Seekwell.Print("Forever content only: " .. (s.browser.foreverOnly and "on" or "off") .. " (/sw forever on|off)")
      for _, l in ipairs(DJ.BridgeLines()) do
        Seekwell.Print("  " .. l)
      end
    end
  end)
end

if Seekwell.RegisterStatus then
  Seekwell.RegisterStatus("forever", function()
    local s = Seekwell.Config.Get()
    return string.format("Forever content filter %s · %s", (type(s.browser) == "table" and s.browser.foreverOnly) and "on" or "off",
      DJ.BridgeLines()[1])
  end)
end

if Seekwell.RegisterStart then
  Seekwell.RegisterStart("forever.section", function()
    if Seekwell.Window and Seekwell.Window.RegisterSection then
      Seekwell.Window.RegisterSection({ id = "forever", label = "Forever", build = function(sec, H)
        local y = 0
        H.Heading(sec, "Forever content", y)
        y = y - 30
        H.Note(sec, "Forever-only items, mobs and dungeons come from other addons read at runtime (never copied) and from your own play. Active bridges:", y)
        y = y - 34
        for _, l in ipairs(DJ.BridgeLines()) do
          H.Note(sec, "\194\183 " .. l, y)
          y = y - 18
        end
        y = y - 8
        H.Check(sec, "Use ForeverDungeonJournal (dungeon bosses, quest rewards, entrances)", y, function()
          return Enabled()
        end, function(on)
          Seekwell.Config.Get().forever.dj = on and true or false
          DJ.Reset()
          if Seekwell.Registry and Seekwell.Registry.ClearCache then
            Seekwell.Registry.ClearCache()
          end
        end)
        y = y - 28
        H.Check(sec, "Use the ForeverDB data addon (more Forever data, about 100 MB of memory; /sw fdb)", y, function()
          return Seekwell.Config.Get().forever.fdbData ~= false
        end, function(on)
          if Seekwell.FDB and Seekwell.FDB.Slash then
            Seekwell.FDB.Slash(on and "on" or "off")
          else
            Seekwell.Config.Get().forever.fdbData = on and true or false
          end
        end)
        y = y - 28
        H.Check(sec, "Search: Forever content only (/sw forever on|off)", y, function()
          return Seekwell.Config.Get().browser.foreverOnly
        end, function(on)
          Seekwell.Config.Get().browser.foreverOnly = on and true or false
        end)
        y = y - 28
        H.Check(sec, "Learn dungeon entrances (a position read every 5 s while outdoors)", y, function()
          return Seekwell.Config.Get().forever.learnEntrances ~= false
        end, function(on)
          Seekwell.Config.Get().forever.learnEntrances = on and true or false
          if Seekwell.Position and Seekwell.Position.UpdateTicker then
            Seekwell.Position.UpdateTicker()
          end
        end)
        return -y + 30
      end })
    end
  end)
end

if Seekwell.L and type(Seekwell.L.HELP_LINES) == "table" then
  table.insert(Seekwell.L.HELP_LINES, "/sw dungeon [name] — Forever dungeons (bosses, loot, quests, entrance) from ForeverDungeonJournal")
  table.insert(Seekwell.L.HELP_LINES, "/sw forever on|off — Search shows only Forever content; without an argument: active Forever bridges")
end
