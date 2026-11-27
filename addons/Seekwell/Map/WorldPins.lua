--[[
  Seekwell.Map — the active hunt and its world map pins.
  Pins go through Blizzard's map canvas only: a data provider (MapCanvasDataProviderMixin) added to
  WorldMapFrame at login and the virtual template SeekwellPinTemplate (Map/Pins.xml). No manual frames,
  no OnUpdate, no global frame names, the addon never opens the map.
  Positions come from Seekwell.Spawns: learned from your own loot, plus original Classic spawn points
  from the optional Seekwell_Locations addon (map.bundled); no position = no pin.
  Hunt: one mob, one item (its best sources) or the whole wishlist of this character.
  /sw hunt <item link|item id|mob name|npc id> | wish | off,  /sw map [on|off|unhide]
]]

Seekwell = Seekwell or {}
local M = {}
Seekwell.Map = M

local addonName = ...
local PIN = "SeekwellPinTemplate"
local SOURCES = 10 -- sources per item

local provider
local hunt -- { kind = "mob"|"item"|"wish", id, label, mobs = { [npcID] = { p, row, item } } }

-- Core.lua (Seekwell.Safe) loads after this file: resolve the error sink at call time.
local function Safe(context, fn)
  return function(...)
    local ok, a, b = pcall(fn, ...)
    if not ok then
      if Seekwell.RecordError then
        Seekwell.RecordError(context, a)
      end
      return nil
    end
    return a, b
  end
end
M.Safe = Safe

local function Print(...)
  if Seekwell.Print then
    Seekwell.Print(...)
  end
end

local function S()
  return Seekwell.Config.Get().map
end

local function Char()
  return Seekwell.Config.Char()
end

local function Hidden()
  local c = Char()
  if type(c.mapHidden) ~= "table" then
    c.mapHidden = {}
  end
  return c.mapHidden
end

local function NpcName(npcID)
  return Seekwell.Registry.NpcName(npcID) or ("npc " .. tostring(npcID))
end

local function ItemName(itemID)
  if C_Item and C_Item.GetItemInfo then
    local n = Seekwell.Secret.Str(Seekwell.Secret.Get(C_Item.GetItemInfo, itemID))
    if n then
      return n
    end
  end
  return "item " .. tostring(itemID)
end

--- Colour of a drop chance: grey < 1, white 1-10, green 10-30, gold > 30, light blue when unknown.
function M.PctColor(p)
  return Seekwell.PinArt.BandColor(p)
end

-- hunt resolution --------------------------------------------------------------------------------

local function AddItemSources(mobs, itemID)
  for _, row in ipairs(Seekwell.Registry.ItemSources(itemID, SOURCES) or {}) do
    local ex = mobs[row.npc]
    if not ex or (row.p or -1) > (ex.p or -1) then
      mobs[row.npc] = { p = row.p, row = row, item = itemID }
    end
  end
end

local function AddEntrances(set, itemID)
  local DJ = Seekwell.DJ
  if not (DJ and DJ.ItemSources) then
    return
  end
  local ok, rows = pcall(DJ.ItemSources, itemID)
  for _, r in ipairs(ok and rows or {}) do
    set[r.dungeon] = true
  end
end

local function Resolve(h)
  local mobs, ents = {}, {}
  h.entrances = ents
  if h.kind == "dungeon" then
    -- keyed by dungeon NAME (a numeric id was a position in a sorted list: ignored)
    local e = type(h.id) == "string" and Seekwell.DJ and Seekwell.DJ.Get(h.id)
    if e then
      ents[e.name] = true
    end
  elseif h.kind == "mob" then
    mobs[h.id] = {}
  elseif h.kind == "item" then
    AddItemSources(mobs, h.id)
    AddEntrances(ents, h.id)
  elseif h.kind == "wish" then
    for _, w in ipairs(Seekwell.Wish.Active()) do
      AddItemSources(mobs, w.id)
      AddEntrances(ents, w.id)
    end
  end
  h.mobs = mobs
  return mobs
end

-- hunt.mobs was resolved once when the hunt was set: re-resolve when the wishlist or ForeverDB changed (at once) or when
-- new learned data came in (at most every 60 s, a loot must not trigger the whole resolve).
local function FreshMobs(h)
  local F, W, Ld = Seekwell.FDB, Seekwell.Wish, Seekwell.Learned
  local sig = tostring(W and W.generation or 0) .. ":" .. tostring(F and F.Generation and F.Generation() or 0)
  local lg = Ld and Ld.generation or 0
  local now = (GetTime and GetTime()) or 0
  if not h.mobs then
    h.rsig, h.rlg, h.rt = sig, lg, now
    return Resolve(h)
  end
  if h.rsig ~= sig or (h.rlg ~= lg and now - (h.rt or 0) > 60) then
    h.rsig, h.rlg, h.rt = sig, lg, now
    return Resolve(h)
  end
  return h.mobs
end

local function PositionCount(mobs)
  local cells, maps = 0, {}
  for npcID in pairs(mobs) do
    for _, mapID in ipairs(Seekwell.Spawns.MapsForMob(npcID)) do
      cells = cells + #Seekwell.Spawns.ForMob(npcID, mapID)
      maps[mapID] = true
    end
  end
  local nm = 0
  for _ in pairs(maps) do
    nm = nm + 1
  end
  return cells, nm
end

-- The minimap redraws 10x per second during a hunt and asks for the points each time. Building them (spawns of every
-- source mob merged from learned / ForeverDB / Classic, then clustered) is expensive, so the result is cached per
-- hunt and map and rebuilt only when the data, the wishlist or the filters changed.
local ptsCache = {}
local ptsVersion = 0

local function PointsSig(mapID)
  local s = S()
  local F, W, Ld = Seekwell.FDB, Seekwell.Wish, Seekwell.Learned
  local nHidden = 0
  for _ in pairs(Hidden()) do
    nHidden = nHidden + 1
  end
  return table.concat({ tostring(mapID), tostring(Seekwell.Spawns.generation or 0), tostring(F and F.Generation and F.Generation() or 0),
    tostring(W and W.generation or 0), tostring(Ld and Ld.generation or 0), tostring(nHidden), tostring(s.minPct), tostring(s.cellYards) }, ":")
end

--- Bumped whenever the points were rebuilt (the minimap skips redrawing while it is unchanged).
function M.PointsVersion()
  return ptsVersion
end

function M.PointsForMap(mapID)
  if not hunt or not mapID then
    return {}
  end
  local sig = PointsSig(mapID)
  local c = ptsCache[mapID]
  if c and c.hunt == hunt and c.sig == sig then
    return c.out
  end
  local out = M.BuildPointsForMap(mapID)
  ptsCache = { [mapID] = { hunt = hunt, sig = sig, out = out } }
  ptsVersion = ptsVersion + 1
  return out
end

--- Points of the active hunt on a map: { {x, y, count, npc, p, row, item} } (clustered per mob).
function M.BuildPointsForMap(mapID)
  local out = {}
  if not hunt or not mapID then
    return out
  end
  local s = S()
  local minPct = tonumber(s.minPct) or 0
  local hidden = Hidden()
  for npcID, e in pairs(FreshMobs(hunt)) do
    if not hidden[npcID] and (minPct <= 0 or e.p == nil or e.p >= minPct) then
      local pts = Seekwell.Spawns.ForMob(npcID, mapID)
      if #pts > 0 then
        for _, c in ipairs(Seekwell.Cluster.Cluster(pts, tonumber(s.cellYards) or 40, mapID)) do
          out[#out + 1] = { x = c.x, y = c.y, count = c.count, npc = npcID, p = e.p, row = e.row, item = e.item, src = c.src }
        end
      end
    end
  end
  local DJ = Seekwell.DJ
  if DJ and hunt.entrances then
    for name in pairs(hunt.entrances) do
      local ok, m, x, y, label = pcall(DJ.Entrance, name)
      if ok and m == mapID then
        out[#out + 1] = { x = x, y = y, count = 1, kind = "entrance", dungeon = name, label = label, src = "entrance" }
      end
    end
  end
  return out
end
M.ENTRANCE_RGB = { 0.95, 0.55, 1.0 } -- violet "door" pins (dungeon entrances)

-- world map pins ---------------------------------------------------------------------------------

SeekwellPinMixin = SeekwellPinMixin or {}
local Pin = SeekwellPinMixin
if MapCanvasPinMixin and Mixin then
  Mixin(Pin, MapCanvasPinMixin)
end

M.PIN_SIZE = 20

local function Setup(self)
  if rawget(self, "_swSetup") then
    return
  end
  rawset(self, "_swSetup", true)
  if self.UseFrameLevelType then
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
  end
  if self.SetScalingLimits then
    -- readable when zoomed out, not huge when zoomed in
    self:SetScalingLimits(1, 1.0, 1.35)
  end
  Seekwell.PinArt.Build(self, M.PIN_SIZE)
end

function Pin:OnLoad()
  Setup(self)
end

function Pin:OnAcquired(pt)
  Setup(self)
  self.pt = pt
  self:SetPosition(pt.x, pt.y)
  Seekwell.PinArt.Apply(self, pt, M.PIN_SIZE)
end

function Pin:CheckMouseButtonPassthrough(...)
  if InCombatLockdown and InCombatLockdown() then
    return
  end
  if MapCanvasPinMixin and MapCanvasPinMixin.CheckMouseButtonPassthrough then
    MapCanvasPinMixin.CheckMouseButtonPassthrough(self, ...)
  end
end

function M.FillTooltip(tt, pt)
  if pt.kind == "entrance" then
    tt:SetText(Seekwell.DJ and Seekwell.DJ.EntranceTooltip(pt.dungeon) or ("Dungeon entrance: " .. tostring(pt.dungeon)))
    tt:AddLine(pt.src == "learned" and "entrance learned from your own play" or "position from ForeverDungeonJournal", 0.6, 0.6, 0.6)
    tt:AddLine("Left-click: waypoint", 0.5, 1, 0.5)
    return
  end
  local d = Seekwell.Registry.NpcDrops(pt.npc)
  tt:SetText(NpcName(pt.npc))
  if d and d.minLevel then
    local lv = tostring(d.minLevel)
    if d.maxLevel and d.maxLevel ~= d.minLevel then
      lv = lv .. "-" .. tostring(d.maxLevel)
    end
    tt:AddLine("Level " .. lv, 1, 1, 1)
  end
  if pt.item then
    local r, g, b = M.PctColor(pt.p)
    tt:AddLine(ItemName(pt.item) .. ": " .. Seekwell.Registry.FormatPct(pt.p) .. " (" .. Seekwell.Registry.OriginLabel(pt.row) .. ")", r, g, b)
  elseif d and d.rows and d.rows[1] then
    for i = 1, math.min(3, #d.rows) do
      local row = d.rows[i]
      tt:AddLine(ItemName(row.id) .. ": " .. Seekwell.Registry.FormatPct(row.p) .. " (" .. Seekwell.Registry.OriginLabel(row) .. ")", 1, 1, 1)
    end
  end
  if (pt.count or 1) > 1 then
    tt:AddLine(pt.count .. (pt.src == "learned" and " learned spots here" or " spots here"), 0.8, 0.8, 0.8)
  end
  if pt.src == "classic" then
    tt:AddLine("Classic spawn data (approximate)", 0.6, 0.6, 0.6)
  elseif pt.src == "fdb" then
    tt:AddLine("ForeverDB spawn data (approximate)", 0.6, 0.6, 0.6)
  elseif pt.src == "mixed" then
    tt:AddLine("position: learned + Classic spawn data (approximate)", 0.6, 0.6, 0.6)
  else
    tt:AddLine("position learned from your loot (approximate)", 0.6, 0.6, 0.6)
  end
  tt:AddLine("Left-click: waypoint · Right-click: hide this mob", 0.5, 1, 0.5)
end

Pin.OnMouseEnter = Safe("map.pin.enter", function(self)
  Seekwell.PinArt.Highlight(self, true)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  M.FillTooltip(GameTooltip, self.pt)
  GameTooltip:Show()
end)

function Pin:OnMouseLeave()
  Seekwell.PinArt.Highlight(self, false)
  GameTooltip:Hide()
end

--- LMB waypoint, RMB hide that mob for this character.
function M.PinClick(pt, button, mapID)
  if not pt then
    return
  end
  if pt.kind == "entrance" then
    if button ~= "RightButton" then
      Seekwell.Waypoint.Set(mapID, pt.x, pt.y, pt.label or tostring(pt.dungeon))
    end
    return
  end
  if button == "RightButton" then
    Hidden()[pt.npc] = true
    Print(string.format("%s hidden on the map (/sw map unhide to show it again)", NpcName(pt.npc)))
    M.Refresh()
  else
    Seekwell.Waypoint.Set(mapID, pt.x, pt.y, NpcName(pt.npc))
  end
end

Pin.OnMouseClickAction = Safe("map.pin.click", function(self, button)
  local mapID = self.GetMap and self:GetMap() and self:GetMap():GetMapID()
  M.PinClick(self.pt, button, mapID)
end)

if CreateFromMixins and MapCanvasDataProviderMixin then
  provider = CreateFromMixins(MapCanvasDataProviderMixin)

  function provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(PIN)
  end

  provider.RefreshAllData = Safe("map.refresh", function(self)
    self:RemoveAllData()
    local map = self:GetMap()
    if not map:IsShown() or not S().enabled or not hunt then
      return
    end
    local mapID = tonumber(Seekwell.Secret.Plain(map:GetMapID()))
    if not mapID then
      return
    end
    for _, pt in ipairs(M.PointsForMap(mapID)) do
      map:AcquirePin(PIN, pt)
    end
  end)
end
M.Provider = provider

local registered = false
function M.Start()
  if registered or not provider then
    return
  end
  if WorldMapFrame and WorldMapFrame.AddDataProvider then
    WorldMapFrame:AddDataProvider(provider)
    registered = true
  end
  M.Restore()
end

--- Restore the saved hunt of this character (a 0.4.0 dungeon hunt saved a list position: dropped safely).
function M.Restore()
  local h = Char().hunt
  if type(h) == "table" and h.kind == "dungeon" and type(h.id) ~= "string" then
    Char().hunt = nil
    return false
  elseif type(h) == "table" and h.kind then
    -- never load the big ForeverDB data during login: it is loaded a little later (and out of combat)
    local ok = M.Set(h.kind, h.id, true, true)
    if ok and Seekwell.FDB and Seekwell.FDB.Touch and C_Timer and C_Timer.After then
      C_Timer.After(20, function()
        pcall(Seekwell.FDB.Touch)
      end)
    end
    return ok
  end
  return false
end

-- hunt API ---------------------------------------------------------------------------------------

function M.Refresh()
  if provider and registered and WorldMapFrame and WorldMapFrame:IsShown() then
    provider:RefreshAllData()
  end
  if Seekwell.MinimapPins then
    Seekwell.MinimapPins.Update()
  end
end

function M.OnDataChanged()
  if hunt then
    M.Refresh()
  end
end

function M.Set(kind, id, quiet, noLoad)
  if not noLoad and Seekwell.FDB and Seekwell.FDB.Touch then
    pcall(Seekwell.FDB.Touch)
  end
  local label
  if kind == "mob" then
    id = tonumber(id)
    label = NpcName(id)
  elseif kind == "item" then
    id = tonumber(id)
    label = ItemName(id)
  elseif kind == "wish" then
    id = nil
    label = "wishlist"
  elseif kind == "dungeon" then
    -- a number is a row of the current Dungeon Journal list (browser, this session only); saved by NAME
    local e = Seekwell.DJ and Seekwell.DJ.Get(tonumber(id) or id)
    if not e then
      return false
    end
    id = e.name
    label = e.name
  else
    return false
  end
  if kind ~= "wish" and not id then
    return false
  end
  hunt = { kind = kind, id = id, label = label }
  Char().hunt = { kind = kind, id = id }
  local mobs = Resolve(hunt)
  M.Refresh()
  if quiet then
    return true
  end
  local nMobs = 0
  for _ in pairs(mobs) do
    nMobs = nMobs + 1
  end
  local cells, maps = PositionCount(mobs)
  if kind == "dungeon" then
    local m = Seekwell.DJ.Entrance(label)
    Print(m and string.format("dungeon entrance of %s on the map", label) or string.format("the entrance of %s is not known yet (enter it once to learn it)", label))
    return true
  end
  if kind == "wish" and Seekwell.Wish.Count() == 0 then
    Print("your wishlist is empty: star items in the target panel first")
  elseif nMobs == 0 then
    Print(string.format("no known sources for %s", label))
  elseif cells == 0 then
    Print(string.format("no positions learned yet for %s — loot it in the world to learn where it lives", label))
  else
    Print(string.format("hunting %s: %d spot(s) in %d zone(s), %d mob(s) — open the world map", label, cells, maps, nMobs))
  end
  return true
end

function M.Hunt(kind, id)
  return M.Set(kind, id)
end

function M.HuntWished(on)
  if on == false then
    return M.Clear()
  end
  return M.Set("wish")
end

function M.Clear()
  hunt = nil
  Char().hunt = nil
  M.Refresh()
  return true
end

function M.Active()
  if not hunt then
    return nil
  end
  return hunt.kind .. ": " .. tostring(hunt.label)
end

function M.Current()
  return hunt
end

--- All npc ids of the active hunt (not hidden), for the minimap.
function M.HuntMobs()
  return hunt and FreshMobs(hunt) or nil
end

-- slash ------------------------------------------------------------------------------------------

local function Lower(s)
  return type(s) == "string" and s:lower() or nil
end

--- npcID by name (case-insensitive): learned names, then Tinny names. Exact match beats a substring.
function M.FindMob(name)
  name = Lower(name)
  if not name or name == "" then
    return nil
  end
  local best, bestScore
  local function Try(id, n)
    n = Lower(n)
    id = tonumber(id)
    if not n or not id then
      return
    end
    local score
    if n == name then
      score = 3
    elseif n:find(name, 1, true) then
      score = 1
    end
    if score then
      if #Seekwell.Spawns.MapsForMob(id) > 0 then
        score = score + 1
      end
      if not bestScore or score > bestScore or (score == bestScore and id < best) then
        best, bestScore = id, score
      end
    end
  end
  for id, e in pairs(Seekwell.Config.Learned().npc or {}) do
    if type(e) == "table" then
      Try(id, e.n)
    end
  end
  if bestScore and bestScore >= 3 then
    return best
  end
  local f = rawget(_G, "TnnysMobLoot_Forever")
  if type(f) == "table" and type(f.npc) == "table" then
    for id, v in pairs(f.npc) do
      if type(v) == "table" then
        Try(id, v[1])
      end
    end
  end
  local st = rawget(_G, "TnnysMobLoot_Starter")
  if type(st) == "table" and type(st.npc) == "table" then
    for id, v in pairs(st.npc) do
      if type(v) == "table" then
        Try(id, v[4])
      end
    end
  end
  return best
end

local function IsKnownNpc(id)
  return Seekwell.Registry.NpcName(id) ~= nil or #Seekwell.Spawns.MapsForMob(id) > 0
end

function M.SlashHunt(rest)
  rest = (rest or ""):match("^%s*(.-)%s*$") or ""
  if rest == "" then
    Print("hunt: " .. (M.Active() or "none") .. " · /sw hunt <item link|item id|mob name|npc id> | wish | off")
    return
  end
  if rest == "off" or rest == "clear" then
    M.Clear()
    Print("hunt cleared")
    return
  end
  if rest == "wish" or rest == "wishlist" then
    M.HuntWished(true)
    return
  end
  local link = rest:match("item:(%d+)")
  if link then
    M.Hunt("item", tonumber(link))
    return
  end
  local kind, num = rest:match("^(%a+)%s+(%d+)$")
  if num and (kind == "item" or kind == "mob" or kind == "npc") then
    M.Hunt(kind == "item" and "item" or "mob", tonumber(num))
    return
  end
  num = tonumber(rest:match("^(%d+)$"))
  if num then
    local src = Seekwell.Registry.ItemSources(num, 1)
    if src and src[1] then
      M.Hunt("item", num)
    elseif IsKnownNpc(num) then
      M.Hunt("mob", num)
    else
      Print(string.format("%d is neither a known item source nor a known mob (try /sw hunt item %d or /sw hunt npc %d)", num, num, num))
    end
    return
  end
  local id = M.FindMob(rest)
  if id then
    M.Hunt("mob", id)
  else
    Print(string.format("no mob named \"%s\" found in learned or Tinny data", rest))
  end
end

function M.SlashMap(rest)
  local s = S()
  rest = (rest or ""):match("^%s*(.-)%s*$") or ""
  if rest == "unhide" then
    Char().mapHidden = {}
    Print("all hidden mobs are shown again")
  elseif rest == "on" or rest == "off" then
    s.enabled = rest == "on"
  elseif rest == "" then
    s.enabled = not s.enabled
  else
    Print("usage: /sw map [on|off|unhide]")
    return
  end
  if rest ~= "unhide" then
    Print("map pins " .. (s.enabled and "on" or "off"))
  end
  M.Refresh()
end

function M.Status()
  local s = S()
  local cells, pairsN = Seekwell.Spawns.Count()
  return string.format("pins %s · minimap %s · hunt %s · %d learned spot(s) for %d mob+zone pair(s)",
    s.enabled and "on" or "off", s.minimap and "on" or "off", M.Active() or "none", cells, pairsN)
end

-- window section ---------------------------------------------------------------------------------

function M.BuildSection(sec, H)
  local s = S
  local y = -10
  H.Heading(sec, "Map pins", y)
  y = y - 30
  H.Note(sec, "Pins show where YOU looted a mob, plus original Classic spawn points when Seekwell_Locations is installed (/sw locations on|off). All approximate.", y)
  y = y - 32
  H.Check(sec, "Show pins on the world map", y, function() return s().enabled end, function(v)
    s().enabled = v
    M.Refresh()
  end)
  y = y - 28
  H.Check(sec, "Show pins on the minimap (only while hunting)", y, function() return s().minimap end, function(v)
    s().minimap = v
    M.Refresh()
  end)
  y = y - 44
  H.Slider(sec, "Minimum drop %", y, 0, 50, function() return tonumber(s().minPct) or 0 end, function(v)
    s().minPct = v
    M.Refresh()
  end)
  y = y - 34
  H.Note(sec, "Pin disc: grey < 1 %, white 1-10 %, green 10-30 %, gold > 30 %, light blue = unknown. Skull = mob, portal = dungeon entrance; cyan ring = learned by you, thin dark ring = Classic data; a number = clustered spots.", y)
  y = y - 40
  local info = H.Note(sec, "", y)
  local function Update()
    local cells, pairsN = Seekwell.Spawns.Count()
    info:SetText(string.format("Hunt: %s\nLearned spots: %d (%d mob+zone pairs)", M.Active() or "none", cells, pairsN))
  end
  M.sectionUpdate = Update
  Update()
  if sec.HookScript then
    sec:HookScript("OnShow", Safe("map.section", Update))
  end
  y = y - 40
  H.Button(sec, "Hunt wishlist", 16, y, 130, function()
    M.HuntWished(true)
    Update()
  end)
  H.Button(sec, "Clear hunt", 156, y, 130, function()
    M.Clear()
    Update()
  end)
  H.Button(sec, "Unhide mobs", 296, y, 110, function()
    M.SlashMap("unhide")
    Update()
  end)
  return -y + 34
end

-- registration: Util/Ext.lua (loaded early) takes slash / start / status at file load;
-- UI/Window.lua loads after this file, so the window section is added once the addon has loaded.
Seekwell.RegisterSlash("hunt", Safe("slash.hunt", function(rest) M.SlashHunt(rest) end))
Seekwell.RegisterSlash("map", Safe("slash.map", function(rest) M.SlashMap(rest) end))
Seekwell.RegisterStart("map", M.Start)
Seekwell.RegisterStatus("map", M.Status)

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name == addonName then
    self:UnregisterAllEvents()
    if Seekwell.Window and Seekwell.Window.RegisterSection then
      local ok, err = pcall(Seekwell.Window.RegisterSection, { id = "map", label = "Map", build = M.BuildSection })
      if not ok and Seekwell.RecordError then
        Seekwell.RecordError("map.section", err)
      end
    end
  end
end)
