--[[
  Seekwell.Vendor — learns vendors from merchant windows you open (MERCHANT_SHOW).
  learned.vendor[npcID] = { n = name, m = uiMapID, x = %, y = % (player position, 0.5 % grid), i = { [itemID] = true }, s = lastSeen }
  Secret GUIDs / names / positions / item links are skipped. About 2000 vendors at most (oldest pruned).

  Seekwell.Sources — non-drop sources of an item from learned data (vendors, quest rewards):
    Sources.ForItem(itemID) -> { {kind="vendor", npc, name, mapID, x, y}, {kind="quest", questID, name, giver, giverName} }
    Sources.Count() -> vendors, quests
  /sw item <item link|id> prints drops (Registry) + vendors + quests in chat.
]]

Seekwell = Seekwell or {}
local Vendor = {}
Seekwell.Vendor = Vendor
local Sources = {}
Seekwell.Sources = Sources

local CAP, PRUNE_TO, ITEMS_MAX = 2000, 1900, 300
Vendor.CAP = CAP
Vendor.generation = 0
local frame

local function Sec()
  return Seekwell.Secret
end

local function Store()
  local l = Seekwell.Config.Learned()
  if type(l.vendor) ~= "table" then
    l.vendor = {}
  end
  return l.vendor
end
Vendor.Store = Store

local function LearnOn(key)
  local s = Seekwell.Config.Get()
  if not s.learn then
    return false
  end
  local z = type(s.zone) == "table" and s.zone or {}
  return z[key] ~= false
end
Vendor.LearnOn = LearnOn

--- Player's uiMapID and position in percent on a 0.5 % grid (x, y may be nil).
function Vendor.PlayerPos()
  local S = Sec()
  if not (C_Map and C_Map.GetBestMapForUnit) then
    return nil
  end
  local mapID = tonumber(S.Get(C_Map.GetBestMapForUnit, "player"))
  if not mapID then
    return nil
  end
  local x, y
  if C_Map.GetPlayerMapPosition then
    local pos = S.Get(C_Map.GetPlayerMapPosition, mapID, "player")
    if pos and pos.GetXY then
      local ok, px, py = pcall(pos.GetXY, pos)
      px, py = ok and S.Plain(px), ok and S.Plain(py)
      if type(px) == "number" and type(py) == "number" and (px > 0 or py > 0) then
        x = math.floor(px * 200 + 0.5) / 2
        y = math.floor(py * 200 + 0.5) / 2
      end
    end
  end
  return mapID, x, y
end

local function Prune(store)
  local list = {}
  for id, e in pairs(store) do
    list[#list + 1] = { id = id, s = (type(e) == "table" and tonumber(e.s)) or 0 }
  end
  if #list <= CAP then
    return
  end
  table.sort(list, function(a, b)
    return a.s < b.s
  end)
  for i = 1, #list - PRUNE_TO do
    store[list[i].id] = nil
  end
end

local function MerchantItemID(i)
  local S = Sec()
  local id = GetMerchantItemID and tonumber(S.Get(GetMerchantItemID, i))
  if id and id > 0 then
    return id
  end
  if GetMerchantItemLink then
    return S.ItemIDFromLink(S.Get(GetMerchantItemLink, i))
  end
  return nil
end

--- Record the vendor behind the open merchant window. Returns npcID or nil.
function Vendor.OnMerchantShow()
  if not LearnOn("vendors") then
    return nil
  end
  local S = Sec()
  local npcID = S.NpcIDFromGUID(S.Get(UnitGUID, "npc"))
  if not npcID then
    return nil -- no npc, not a creature, or secret
  end
  local store = Store()
  local now = (time and time()) or 0
  local e = store[npcID]
  if type(e) ~= "table" then
    e = { i = {} }
    store[npcID] = e
  end
  local name = S.Str(S.Get(UnitName, "npc"))
  if name and name ~= "" then
    e.n = name
  end
  local mapID, x, y = Vendor.PlayerPos()
  if mapID then
    e.m, e.x, e.y = mapID, x, y
  end
  e.i = type(e.i) == "table" and e.i or {}
  local n = tonumber(S.Get(GetMerchantNumItems)) or 0
  local count = 0
  for _ in pairs(e.i) do
    count = count + 1
  end
  for i = 1, math.min(n, ITEMS_MAX) do
    local id = MerchantItemID(i)
    if id and not e.i[id] and count < ITEMS_MAX then
      e.i[id] = true
      count = count + 1
    end
  end
  e.s = now
  Prune(store)
  Vendor.generation = Vendor.generation + 1
  return npcID
end

function Vendor.Get(npcID)
  local e = Store()[tonumber(npcID) or -1]
  return type(e) == "table" and e or nil
end

--- Vendors learned on a map: { {npc, name, x, y, items} }, by name.
function Vendor.InMap(mapID)
  local out = {}
  mapID = tonumber(mapID)
  if not mapID then
    return out
  end
  for npcID, e in pairs(Store()) do
    if type(e) == "table" and e.m == mapID then
      local items = 0
      for _ in pairs(e.i or {}) do
        items = items + 1
      end
      out[#out + 1] = { npc = npcID, name = e.n, x = e.x, y = e.y, items = items }
    end
  end
  table.sort(out, function(a, b)
    if (a.name or "") ~= (b.name or "") then
      return (a.name or "") < (b.name or "")
    end
    return a.npc < b.npc
  end)
  return out
end

function Vendor.Start()
  if frame then
    return
  end
  frame = CreateFrame("Frame")
  frame:RegisterEvent("MERCHANT_SHOW")
  frame:SetScript("OnEvent", Seekwell.Safe("vendor", function(_, event)
    if event == "MERCHANT_SHOW" then
      Vendor.OnMerchantShow()
    end
  end))
end

-- Sources ------------------------------------------------------------------

local function Count(t)
  local n = 0
  for _, e in pairs(t or {}) do
    if type(e) == "table" then
      n = n + 1
    end
  end
  return n
end

function Sources.Count()
  local l = Seekwell.Config.Learned()
  return Count(l.vendor), Count(l.quest)
end

--- Non-drop sources of an item from learned vendors and quest rewards.
function Sources.ForItem(itemID)
  itemID = tonumber(itemID)
  local out = {}
  if not itemID then
    return out
  end
  local l = Seekwell.Config.Learned()
  local vendors, quests = {}, {}
  for npcID, e in pairs(type(l.vendor) == "table" and l.vendor or {}) do
    if type(e) == "table" and type(e.i) == "table" and e.i[itemID] then
      vendors[#vendors + 1] = { kind = "vendor", npc = npcID, name = e.n, mapID = e.m, x = e.x, y = e.y, s = tonumber(e.s) or 0 }
    end
  end
  table.sort(vendors, function(a, b)
    if a.s ~= b.s then
      return a.s > b.s
    end
    return a.npc < b.npc
  end)
  for qid, e in pairs(type(l.quest) == "table" and l.quest or {}) do
    if type(e) == "table" and type(e.r) == "table" then
      for _, rid in ipairs(e.r) do
        if rid == itemID then
          quests[#quests + 1] = { kind = "quest", questID = qid, name = e.n, giver = e.g, giverName = e.gn }
          break
        end
      end
    end
  end
  table.sort(quests, function(a, b)
    return a.questID < b.questID
  end)
  for _, v in ipairs(vendors) do
    v.s = nil
    out[#out + 1] = v
  end
  local F = Seekwell.FDB
  local fdb = F and F.Data and F.Data() and F or nil
  if fdb then -- ForeverDB vendors after the learned ones
    local have = {}
    for _, v in ipairs(vendors) do
      have[v.npc] = true
    end
    for _, npc in ipairs(fdb.Vendors(itemID) or {}) do
      if not have[npc] then
        have[npc] = true
        local sp = fdb.Spawns(npc) or {}
        local m = sp[1]
        local p = m and m.points[1]
        out[#out + 1] = { kind = "vendor", npc = npc, name = fdb.NpcName(npc), mapID = m and m.mapID, x = p and p.x * 100, y = p and p.y * 100,
          origin = "forever_db" }
      end
    end
  end
  for _, q in ipairs(quests) do
    out[#out + 1] = q
  end
  if fdb then -- ForeverDB quest rewards (rew + quest titles + givers)
    local have = {}
    for _, q in ipairs(quests) do
      have[q.questID] = true
    end
    for _, r in ipairs(fdb.QuestRewards(itemID) or {}) do
      if not have[r.questID] then
        have[r.questID] = true
        out[#out + 1] = { kind = "quest", questID = r.questID, name = r.name, giver = r.giver, giverName = r.giverName, origin = "forever_db" }
      end
    end
  end
  local DJ = Seekwell.DJ
  if DJ and DJ.ItemSources then
    local ok, rows = pcall(DJ.ItemSources, itemID)
    for _, r in ipairs(ok and rows or {}) do
      out[#out + 1] = { kind = r.source, dungeon = r.dungeon, boss = r.boss, bossIndex = r.bossIndex, questID = r.questID,
        name = r.quest, label = r.label }
    end
  end
  return out
end

--- "Elwynn Forest" or nil.
function Sources.MapName(mapID)
  mapID = tonumber(mapID)
  if not (mapID and C_Map and C_Map.GetMapInfo) then
    return nil
  end
  local info = Sec().Get(C_Map.GetMapInfo, mapID)
  return type(info) == "table" and Sec().Str(info.name) or nil
end

local function NpcName(npcID)
  if not npcID then
    return nil
  end
  local R = Seekwell.Registry
  local n = R and R.NpcName and R.NpcName(npcID)
  if not n then
    local v = Vendor.Get(npcID)
    n = v and v.n
  end
  return n
end
Sources.NpcName = NpcName

local function ItemLabel(itemID)
  local name
  if C_Item and C_Item.GetItemInfo then
    local ok, n, link = pcall(C_Item.GetItemInfo, itemID)
    if ok then
      link = Sec().Str(link)
      name = link or Sec().Str(n)
    end
    if not name and C_Item.RequestLoadItemDataByID then
      pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
  end
  return name or ("item " .. tostring(itemID))
end

local function Coords(x, y)
  if x and y then
    return string.format(" (%.1f, %.1f)", x, y)
  end
  return ""
end

--- Lines for /sw item (also used by the tests).
function Sources.ItemLines(itemID)
  local lines = {}
  local R = Seekwell.Registry
  lines[1] = ItemLabel(itemID) .. " — sources:"
  local drops = R and R.ItemSources(itemID, 5) or {}
  local nd = 0
  for _, r in ipairs(drops) do
    if r.origin ~= "dj" then -- Dungeon Journal bosses are listed below as "dungeon"
      nd = nd + 1
      lines[#lines + 1] = string.format("  drop: %s %s (%s)", NpcName(r.npc) or ("npc " .. r.npc), R.FormatPct(r.p), R.OriginLabel(r))
    end
  end
  local list = Sources.ForItem(itemID)
  for _, s in ipairs(list) do
    if s.kind == "dungeon" or s.kind == "djquest" then
      local mapID = Seekwell.DJ and Seekwell.DJ.Entrance(s.dungeon)
      lines[#lines + 1] = string.format("  %s: %s %s (Dungeon Journal)%s", s.kind == "dungeon" and "dungeon" or "quest",
        s.label or "?", s.kind == "dungeon" and R.FormatPct(nil) or "", mapID and (" · entrance in " .. (Sources.MapName(mapID) or ("map " .. mapID))) or "")
    elseif s.kind == "vendor" then
      lines[#lines + 1] = string.format("  vendor: %s · %s%s", s.name or NpcName(s.npc) or ("npc " .. s.npc),
        Sources.MapName(s.mapID) or "unknown zone", Coords(s.x, s.y))
    else
      local giver = s.giverName or (s.giver and (NpcName(s.giver) or ("npc " .. s.giver)))
      lines[#lines + 1] = string.format("  quest: %s%s", s.name or ("quest " .. s.questID), giver and (" · from " .. giver) or "")
    end
  end
  if nd == 0 and #list == 0 then
    lines[#lines + 1] = "  nothing known yet (no drop data; no learned vendor or quest reward)"
  end
  return lines
end

local function ParseItem(rest)
  rest = rest or ""
  return tonumber(rest:match("item:(%d+)")) or tonumber(rest:match("^%s*(%d+)%s*$"))
end
Sources.ParseItem = ParseItem

-- Util/Ext.lua (loaded early) provides the extension points at file load.
local function Register()
  Seekwell.RegisterSlash("item", function(rest)
    local id = ParseItem(rest)
    if not id then
      Seekwell.Print("usage: /sw item <item link/item id>")
      return
    end
    for _, line in ipairs(Sources.ItemLines(id)) do
      Seekwell.Print(line)
    end
  end)

  Seekwell.RegisterStart("vendor", Vendor.Start)
  Seekwell.RegisterStatus("vendors/quests", function()
    local v, q = Sources.Count()
    return string.format("%d vendor(s) · %d quest(s) learned · learning vendors %s, quests %s", v, q,
      LearnOn("vendors") and "on" or "off", LearnOn("quests") and "on" or "off")
  end)
end

Register()

if Seekwell.L and type(Seekwell.L.HELP_LINES) == "table" then
  table.insert(Seekwell.L.HELP_LINES, "/sw item <link/id> — all known sources of an item (drops, vendors, quests)")
  table.insert(Seekwell.L.HELP_LINES, "/sw zone — the Zone view: mobs, wished drops and vendors in your zone")
end
