--[[
  Seekwell.Zone — the "Zone" window section and /sw zone: the mobs known in your current zone
  (learned loot: learned.npc[].m[uiMapID]; Seekwell.Spawns.MobsInMap when present), their level range,
  your kills and the wished items they drop (star), mobs with wished drops first; wished items obtainable
  here summarised at the top; vendors learned in this zone. Refreshes on zone change only while visible.
]]

Seekwell = Seekwell or {}
local Zone = {}
Seekwell.Zone = Zone

local MAX_ROWS = 30
local STAR = "|cffffd100*|r "
local sec, header, summary, empty, vendorText
local rows = {} -- pooled font strings
local lastView

local function Sec()
  return Seekwell.Secret
end

local function Settings()
  local s = Seekwell.Config.Get()
  return type(s.zone) == "table" and s.zone or {}
end

function Zone.CurrentMap()
  if not (C_Map and C_Map.GetBestMapForUnit) then
    return nil
  end
  return tonumber(Sec().Get(C_Map.GetBestMapForUnit, "player"))
end

function Zone.MapName(mapID)
  local S = Seekwell.Sources
  return S and S.MapName and S.MapName(mapID) or nil
end

local function ItemName(itemID)
  if C_Item and C_Item.GetItemInfo then
    local ok, n = pcall(C_Item.GetItemInfo, itemID)
    n = ok and Sec().Str(n) or nil
    if n then
      return n
    end
    if C_Item.RequestLoadItemDataByID then
      pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
  end
  return "item " .. tostring(itemID)
end
Zone.ItemName = ItemName

--- npc ids from Seekwell.Spawns.MobsInMap (accepts a list of ids, a list of {npc|id}, or a set).
local function SpawnMobs(mapID, add)
  local Sp = Seekwell.Spawns
  if not (Sp and Sp.MobsInMap) then
    return
  end
  local ok, list = pcall(Sp.MobsInMap, mapID)
  if not ok or type(list) ~= "table" then
    return
  end
  for k, v in pairs(list) do
    local id
    if type(v) == "table" then
      id = tonumber(v.npc or v.id or v.npcID)
    elseif type(v) == "number" then
      id = v
    elseif v == true then
      id = tonumber(k)
    end
    if id then
      add(id)
    end
  end
end

--- View model of a map: { mapID, name, mobs = {{npc, name, minLevel, maxLevel, kills, wished = {{id, p}}}},
---   wished = {{id, mobs = {names}, vendors = {names}}}, vendors = {{npc, name, x, y, items}}, truncated }
function Zone.Compute(mapID)
  local view = { mapID = mapID, name = mapID and Zone.MapName(mapID), mobs = {}, wished = {}, vendors = {} }
  if not mapID then
    return view
  end
  local maxMobs = tonumber(Settings().maxMobs) or 300
  local ids, seen, n = {}, {}, 0
  local function add(id)
    if not seen[id] then
      seen[id] = true
      if n < maxMobs then
        n = n + 1
        ids[n] = id
      else
        view.truncated = true
      end
    end
  end
  local npcs = Seekwell.Config.Learned().npc or {}
  for npcID, e in pairs(npcs) do
    if type(e) == "table" and type(e.m) == "table" and e.m[mapID] then
      add(npcID)
    end
  end
  SpawnMobs(mapID, add)
  local R, Wish = Seekwell.Registry, Seekwell.Wish
  local wishIdx = {}
  for _, npcID in ipairs(ids) do
    local ok, d = pcall(R.NpcDrops, npcID)
    d = ok and d or nil
    local le = type(npcs[npcID]) == "table" and npcs[npcID] or nil
    local mob = { npc = npcID, name = (d and d.name) or (le and le.n) or ("npc " .. npcID),
      minLevel = d and d.minLevel, maxLevel = d and d.maxLevel, kills = (le and tonumber(le.k)) or 0, wished = {} }
    for _, r in ipairs(d and d.rows or {}) do
      if Wish.IsWanted(r.id) then
        mob.wished[#mob.wished + 1] = { id = r.id, p = r.p }
        local w = wishIdx[r.id]
        if not w then
          w = { id = r.id, mobs = {}, vendors = {} }
          wishIdx[r.id] = w
          view.wished[#view.wished + 1] = w
        end
        w.mobs[#w.mobs + 1] = mob.name
      end
    end
    view.mobs[#view.mobs + 1] = mob
  end
  table.sort(view.mobs, function(a, b)
    local wa, wb = #a.wished > 0, #b.wished > 0
    if wa ~= wb then
      return wa
    end
    if a.kills ~= b.kills then
      return a.kills > b.kills
    end
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.npc < b.npc
  end)
  local V = Seekwell.Vendor
  view.vendors = V and V.InMap(mapID) or {}
  for _, v in ipairs(view.vendors) do
    local e = V.Get(v.npc)
    for itemID in pairs(e and e.i or {}) do
      if Wish.IsWanted(itemID) then
        local w = wishIdx[itemID]
        if not w then
          w = { id = itemID, mobs = {}, vendors = {} }
          wishIdx[itemID] = w
          view.wished[#view.wished + 1] = w
        end
        w.vendors[#w.vendors + 1] = v.name or ("npc " .. v.npc)
      end
    end
  end
  table.sort(view.wished, function(a, b)
    return a.id < b.id
  end)
  return view
end

local function Levels(m)
  if m.minLevel and m.maxLevel and m.minLevel ~= m.maxLevel then
    return " [" .. m.minLevel .. "-" .. m.maxLevel .. "]"
  elseif m.minLevel or m.maxLevel then
    return " [" .. tostring(m.minLevel or m.maxLevel) .. "]"
  end
  return ""
end

--- One mob row as text.
function Zone.RowText(m)
  local R = Seekwell.Registry
  local parts = {}
  for i = 1, math.min(3, #m.wished) do
    local w = m.wished[i]
    parts[#parts + 1] = ItemName(w.id) .. " " .. R.FormatPct(w.p)
  end
  if #m.wished > 3 then
    parts[#parts + 1] = "+" .. (#m.wished - 3)
  end
  return string.format("%s%s%s · %d kill%s%s", #m.wished > 0 and STAR or "", m.name, Levels(m), m.kills,
    m.kills == 1 and "" or "s", #parts > 0 and (" · " .. table.concat(parts, ", ")) or "")
end

--- Text blocks of a view: header, summary, rows (strings), vendors, empty.
function Zone.Texts(view)
  local out = { rows = {} }
  if not view.mapID then
    out.header = "Zone: unknown"
    out.empty = "Your zone is not known right now (no map for this area)."
    return out
  end
  out.header = "Zone: " .. (view.name or ("map " .. view.mapID))
  if #view.wished > 0 then
    local lines = {}
    for _, w in ipairs(view.wished) do
      local src = {}
      if #w.mobs > 0 then
        src[#src + 1] = table.concat(w.mobs, ", ", 1, math.min(3, #w.mobs)) .. (#w.mobs > 3 and " ..." or "")
      end
      if #w.vendors > 0 then
        src[#src + 1] = "vendor " .. table.concat(w.vendors, ", ", 1, math.min(2, #w.vendors))
      end
      lines[#lines + 1] = STAR .. ItemName(w.id) .. " — " .. table.concat(src, "; ")
    end
    out.summary = "Wished items obtainable here:\n" .. table.concat(lines, "\n")
  else
    out.summary = "No wished item is known to come from this zone."
  end
  for i = 1, math.min(MAX_ROWS, #view.mobs) do
    out.rows[i] = Zone.RowText(view.mobs[i])
  end
  if #view.mobs > MAX_ROWS or view.truncated then
    out.more = string.format("... and more (%d shown)", math.min(MAX_ROWS, #view.mobs))
  end
  if #view.mobs == 0 then
    out.empty = "Nothing learned in this zone yet — loot mobs here."
  end
  if #view.vendors > 0 then
    local lines = { "Vendors learned here:" }
    for i = 1, math.min(10, #view.vendors) do
      local v = view.vendors[i]
      local xy = (v.x and v.y) and string.format(" (%.1f, %.1f)", v.x, v.y) or ""
      lines[#lines + 1] = string.format("  %s%s · %d item%s", v.name or ("npc " .. v.npc), xy, v.items, v.items == 1 and "" or "s")
    end
    if #view.vendors > 10 then
      lines[#lines + 1] = "  ... " .. (#view.vendors - 10) .. " more"
    end
    out.vendors = table.concat(lines, "\n")
  else
    out.vendors = "No vendor learned in this zone yet — open a vendor's window to learn it."
  end
  return out
end

-- window section -------------------------------------------------------------

local function Row(i, width)
  local fs = rows[i]
  if not fs then
    fs = sec:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    rows[i] = fs
  end
  fs:SetWidth(width - 40)
  return fs
end

local secWidth = 400
local LINE = 14

local function Lines(text)
  local n = 1
  for _ in tostring(text or ""):gmatch("\n") do
    n = n + 1
  end
  return n
end

function Zone.Render()
  if not sec then
    return
  end
  local view = Zone.Compute(Zone.CurrentMap())
  lastView = view
  local t = Zone.Texts(view)
  local y = -30
  local Win = Seekwell.Window
  if Win and Win.ContentWidth then
    secWidth = Win.ContentWidth("browser") or secWidth
  end
  for _, fs in ipairs({ summary, empty, vendorText }) do
    fs:SetWidth(secWidth - 40)
  end
  header:SetText(t.header)
  summary:ClearAllPoints()
  summary:SetPoint("TOPLEFT", 18, y)
  summary:SetText(t.summary or "")
  y = y - Lines(t.summary) * LINE - 10
  empty:ClearAllPoints()
  empty:SetPoint("TOPLEFT", 18, y)
  if t.empty then
    empty:SetText(t.empty)
    empty:Show()
    y = y - 24
  else
    empty:SetText("")
    empty:Hide()
  end
  local shown = #t.rows + (t.more and 1 or 0)
  for i = 1, math.max(shown, #rows) do
    if i <= shown then
      local fs = Row(i, secWidth)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", 18, y)
      fs:SetText(t.rows[i] or t.more)
      fs:Show()
      y = y - LINE - 2
    elseif rows[i] then
      rows[i]:SetText("")
      rows[i]:Hide()
    end
  end
  y = y - 8
  vendorText:ClearAllPoints()
  vendorText:SetPoint("TOPLEFT", 18, y)
  vendorText:SetText(t.vendors)
  y = y - Lines(t.vendors) * LINE - 10
  sec.checksY = y
  if sec.checks then
    for i, cb in ipairs(sec.checks) do
      cb:ClearAllPoints()
      cb:SetPoint("TOPLEFT", 14, y - (i - 1) * 28)
    end
    y = y - #sec.checks * 28
  end
  sec.height = -y + 30
  return view
end

local function OnEvent()
  if sec and sec:IsShown() then
    Zone.Render()
    if Seekwell.Window and Seekwell.Window.Refresh then
      Seekwell.Window.Refresh()
    end
  end
end

local function Build(s, H)
  sec = s
  secWidth = H.width or secWidth
  header = H.Heading(s, "Zone", 0)
  summary = H.Note(s, "", -30)
  summary:SetTextColor(1, 1, 1)
  empty = H.Note(s, "", -60)
  vendorText = H.Note(s, "", -90)
  local function Toggle(key)
    return function()
      return Settings()[key] ~= false
    end, function(on)
      Settings()[key] = on and true or false
    end
  end
  local g1, s1 = Toggle("vendors")
  local g2, s2 = Toggle("quests")
  s.checks = {
    H.Check(s, "Learn vendors from merchant windows", -120, g1, s1),
    H.Check(s, "Learn quests and their item rewards", -148, g2, s2),
  }
  local ev = CreateFrame("Frame")
  ev:SetScript("OnEvent", Seekwell.Safe("zone.event", OnEvent))
  s:SetScript("OnShow", Seekwell.Safe("zone.show", function()
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    Zone.Render()
  end))
  s:SetScript("OnHide", function()
    ev:UnregisterAllEvents()
  end)
  Zone.eventFrame = ev
  return 200
end

if Seekwell.Window and Seekwell.Window.RegisterSection then
  Seekwell.Window.RegisterSection({ id = "zone", label = "Zone", build = Build, mode = "browser" })
end

function Zone.Last()
  return lastView
end

local function Slash()
  local view = Zone.Compute(Zone.CurrentMap())
  local t = Zone.Texts(view)
  Seekwell.Print(t.header .. string.format(" · %d mob(s) known · %d vendor(s) · %d wished item(s) here", #view.mobs, #view.vendors, #view.wished))
  if t.empty then
    Seekwell.Print(t.empty)
  end
  if Seekwell.Window then
    Seekwell.Window.Show("zone")
  end
end
Zone.Slash = Slash

Seekwell.RegisterSlash("zone", Slash)
Seekwell.RegisterStatus("zone", function()
  local view = Zone.Compute(Zone.CurrentMap())
  return string.format("%s · %d mob(s) known · %d vendor(s) · %d wished item(s) here", view.name or "unknown zone",
    #view.mobs, #view.vendors, #view.wished)
end)
