--[[
  Seekwell.SelfTest — /sw selftest: checks the pieces inside the running game and prints one
  PASS / WARN / FAIL / SKIP line each plus a summary. Restores anything it toggles (wishlist round trip),
  writes only its own run counter (SeekwellDB.selftestRuns), and skips the parts that load addons or
  create frames while in combat.
]]

Seekwell = Seekwell or {}
local ST = {}
Seekwell.SelfTest = ST

local COLOR = { PASS = "|cff33ff33", WARN = "|cffffcc00", FAIL = "|cffff4444", SKIP = "|cff999999" }
local CLASSIC_NPC = 3 -- Flesh Eater (Duskwood), present in the original Classic spawn data
local TEST_ITEMS = { 2589, 2592, 4306, 4338 }

local function G(name)
  return rawget(_G, name)
end

local function InCombat()
  local f = G("InCombatLockdown")
  return type(f) == "function" and f() and true or false
end

local function Count(t)
  local n = 0
  for _ in pairs(type(t) == "table" and t or {}) do
    n = n + 1
  end
  return n
end

--- Runs every check: returns { {status, name, detail} } and the counts { PASS = n, ... }.
function ST.Run()
  local out = {}
  local function Add(status, name, detail)
    out[#out + 1] = { status, name, detail or "" }
  end
  local function Try(name, fn)
    local ok, err = pcall(fn)
    if not ok then
      Add("FAIL", name, "error: " .. tostring(err))
    end
  end
  local combat = InCombat()
  local Config = Seekwell.Config

  Try("Tinny data", function()
    local T = Seekwell.Tinny
    local c = T and T.Counts and T.Counts() or {}
    local f, s = tonumber(c.forever) or 0, tonumber(c.starter) or 0
    if f > 0 and s > 0 then
      Add("PASS", "Tinny data", string.format("Forever %d npc, Starter (Classic) %d npc", f, s))
    elseif f > 0 or s > 0 then
      Add("WARN", "Tinny data", string.format("Forever %d npc, Starter %d npc (one table missing: no Forever badge without Starter)", f, s))
    else
      Add("FAIL", "Tinny data", "TnnysMobLoot not loaded (no drop tables)")
    end
  end)

  Try("item name index", function()
    local T = Seekwell.Tinny
    local hits = T and T.FindItems and T.FindItems("cloth", 5) or {}
    Add(#hits > 0 and "PASS" or "FAIL", "item name index", string.format("FindItems(\"cloth\") = %d hit(s)", #hits))
  end)

  Try("Registry", function()
    local rows = Seekwell.Registry.ItemSources(2589, 200) or {}
    Add(#rows > 0 and "PASS" or "FAIL", "Registry", string.format("ItemSources(2589 Linen Cloth) = %d source(s)", #rows))
  end)

  Try("ForeverDB data", function()
    local F = Seekwell.FDB
    if not F then
      Add("SKIP", "ForeverDB data", "Data/FDBBridge.lua not loaded")
      return
    end
    if not F.Enabled() then
      Add("SKIP", "ForeverDB data", "off (settings.forever.fdbData; /sw fdb on)")
      return
    end
    if not F.Available() then
      Add("WARN", "ForeverDB data", "ForeverDBData addon not installed (see README): Forever-only items / mobs need it")
      return
    end
    Add("PASS", "ForeverDB addon", "found")
    if not F.Loaded() then
      if combat then
        Add("SKIP", "ForeverDB load", "in combat (loaded out of combat only)")
        return
      end
      F.Load()
    end
    if not F.Loaded() then
      Add("FAIL", "ForeverDB load", tostring(F.Status()))
      return
    end
    local i = F.Info() or {}
    Add("PASS", "ForeverDB load", string.format("build %s, %s ms", tostring(i.build), i.ms and string.format("%.0f", i.ms) or "?"))
    local n = F.Npc(CLASSIC_NPC)
    Add(n and n.name and "PASS" or "FAIL", "ForeverDB npc", n and string.format("npc %d = %s (%s-%s)", CLASSIC_NPC, tostring(n.name),
      tostring(n.minLv), tostring(n.maxLv)) or ("npc " .. CLASSIC_NPC .. " missing"))
    local iname = F.ItemName(2589)
    Add(iname and "PASS" or "FAIL", "ForeverDB item", "item 2589 = " .. tostring(iname))
    local sp = F.Spawns(CLASSIC_NPC) or {}
    local okPos = sp[1] and sp[1].points[1]
    local info = okPos and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(sp[1].mapID)
    if okPos then
      Add(info and "PASS" or "WARN", "ForeverDB spawns", string.format("npc %d: %d map(s), first map %d (%s) %.3f, %.3f", CLASSIC_NPC, #sp, sp[1].mapID,
        info and tostring(info.name) or "unknown map", okPos.x, okPos.y))
    else
      Add("FAIL", "ForeverDB spawns", "no spm / spw positions converted for npc " .. CLASSIC_NPC)
    end
    Add("PASS", "ForeverDB status", tostring(F.Status()))
  end)

  Try("Classic spawn data", function()
    local L = Seekwell.Locations
    if not (L and L.Available and L.Available()) then
      Add("WARN", "Classic spawn data", "Seekwell_Locations not installed or disabled: pins only from your own loot")
      return
    end
    if combat then
      Add("SKIP", "Classic spawn data", "in combat (the addon is loaded out of combat only)")
      return
    end
    L.Load()
    local mapID, pts = L.ForMob(CLASSIC_NPC)
    mapID = tonumber(mapID)
    local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    if mapID and type(pts) == "table" and #pts > 0 and info then
      Add("PASS", "Classic spawn data", string.format("npc %d: %d point(s) on map %d (%s)", CLASSIC_NPC, #pts, mapID,
        tostring(type(info) == "table" and info.name or "?")))
    elseif mapID and type(pts) == "table" and #pts > 0 then
      Add("WARN", "Classic spawn data", string.format("npc %d: %d point(s) but map %d unknown to C_Map.GetMapInfo", CLASSIC_NPC, #pts, mapID))
    else
      Add("FAIL", "Classic spawn data", string.format("loaded, but no points for npc %d", CLASSIC_NPC))
    end
  end)

  Try("world map provider", function()
    local M = Seekwell.Map
    local p = M and M.Provider
    local wmf = G("WorldMapFrame")
    if not p then
      Add("FAIL", "world map provider", "Seekwell.Map.Provider missing (MapCanvasDataProviderMixin not available?)")
    elseif wmf and type(wmf.dataProviders) == "table" then
      Add(wmf.dataProviders[p] and "PASS" or "FAIL", "world map provider", wmf.dataProviders[p] and "registered on WorldMapFrame" or "not in WorldMapFrame.dataProviders")
    else
      Add("WARN", "world map provider", "provider exists; WorldMapFrame providers not inspectable")
    end
  end)

  Try("pin template", function()
    local xu = G("C_XMLUtil")
    if xu and xu.GetTemplateInfo then
      local info = xu.GetTemplateInfo("SeekwellPinTemplate")
      Add(info and "PASS" or "FAIL", "pin template", info and "SeekwellPinTemplate registered" or "SeekwellPinTemplate missing (Map/Pins.xml not loaded)")
      return
    end
    if combat then
      Add("SKIP", "pin template", "in combat (test frame not created)")
      return
    end
    if not ST.pinProbe then
      local ok, f = pcall(CreateFrame, "Frame", nil, UIParent, "SeekwellPinTemplate")
      ST.pinProbe = ok and f or false
      if ok and f and f.Hide then
        f:Hide()
      end
    end
    Add(ST.pinProbe and "PASS" or "FAIL", "pin template", ST.pinProbe and "CreateFrame with SeekwellPinTemplate works" or "CreateFrame with SeekwellPinTemplate failed")
  end)

  Try("pin art", function()
    local PA = Seekwell.PinArt
    Add(PA and PA.Apply and "PASS" or "FAIL", "pin art", PA and "skull / coin / ! / portal glyphs, % colour discs" or "Map/PinArt.lua not loaded")
  end)

  Try("minimap pins", function()
    local MP = Seekwell.MinimapPins
    if MP and MP.Draw and G("Minimap") then
      Add("PASS", "minimap pins", string.format("ready (ticker %s, %d pooled)", MP.Running() and "running" or "idle", MP.PoolSize()))
    else
      Add("FAIL", "minimap pins", "module or Minimap missing")
    end
  end)

  Try("map art", function()
    if not (C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then
      Add("WARN", "map art", "C_Map.GetMapArtLayers / GetMapArtLayerTextures missing: the preview shows a grid")
      return
    end
    local art = Seekwell.MapPreview and Seekwell.MapPreview.ArtInfo(1429)
    if art then
      Add("PASS", "map art", string.format("map 1429: %d tile(s) %dx%d", #art.textures, art.w, art.h))
    else
      Add("WARN", "map art", "API present but no art for map 1429: the preview shows a grid")
    end
  end)

  Try("waypoint API", function()
    local can = C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.SetUserWaypoint and G("UiMapPoint")
    local st = G("C_SuperTrack")
    if can then
      local ok, v = pcall(C_Map.CanSetUserWaypointOnMap, 1429)
      Add("PASS", "waypoint API", "user waypoints" .. ((ok and v) and "" or " (not allowed on map 1429)")
        .. ((st and st.SetSuperTrackedUserWaypoint) and " + super track" or ", no C_SuperTrack"))
    elseif G("TomTom") then
      Add("PASS", "waypoint API", "TomTom")
    else
      Add("WARN", "waypoint API", "no user waypoints: coordinates are printed instead")
    end
  end)

  Try("Dungeon Journal", function()
    local DJ = Seekwell.DJ
    local c = DJ and DJ.Counts and DJ.Counts()
    if c then
      Add(c.dungeons > 0 and "PASS" or "WARN", "Dungeon Journal", string.format("%d dungeon(s), %d entrance(s) placed, %d learned", c.dungeons, c.entrances,
        Count(type(G("SeekwellDB")) == "table" and type(SeekwellDB.learned) == "table" and SeekwellDB.learned.entrance)))
    else
      Add("WARN", "Dungeon Journal", "ForeverDungeonJournal not loaded or settings.forever.dj off")
    end
  end)

  Try("tooltip", function()
    local mode = Seekwell.Tooltip and Seekwell.Tooltip.Mode and Seekwell.Tooltip.Mode()
    Add(mode and "PASS" or "FAIL", "tooltip", mode and ("post-call installed (" .. mode .. ")") or "item tooltip hook not installed")
  end)

  Try("key binding", function()
    local named = G("BINDING_NAME_SEEKWELL_TARGET") ~= nil
    local key = G("GetBindingKey") and GetBindingKey("SEEKWELL_TARGET")
    if named and key then
      Add("PASS", "key binding", "SEEKWELL_TARGET on " .. tostring(key))
    elseif named then
      Add("WARN", "key binding", "SEEKWELL_TARGET registered, no key bound (Key Bindings > AddOns)")
    else
      Add("FAIL", "key binding", "BINDING_NAME_SEEKWELL_TARGET missing (Bindings.xml / locale)")
    end
  end)

  Try("SavedVariables", function()
    local db = G("SeekwellDB")
    if type(db) ~= "table" then
      Add("FAIL", "SavedVariables", "SeekwellDB is not a table")
      return
    end
    local before = tonumber(db.selftestRuns) or 0
    db.selftestRuns = before + 1
    Add(db.selftestRuns == before + 1 and "PASS" or "FAIL", "SavedVariables", "writable (selftest run #" .. tostring(db.selftestRuns) .. ")")
  end)

  Try("learning", function()
    local s = Config.Get()
    local ent = not (type(s.forever) == "table" and s.forever.learnEntrances == false)
    local tick = Seekwell.Position and Seekwell.Position.TickerRunning and Seekwell.Position.TickerRunning()
    Add(s.learn and "PASS" or "WARN", "learning", string.format("loot learning %s · entrance learning %s (5 s ticker %s)", s.learn and "on" or "OFF",
      ent and "on" or "off", tick and "running" or "stopped"))
  end)

  Try("wishlist", function()
    local W = Seekwell.Wish
    local id
    for _, x in ipairs(TEST_ITEMS) do
      if not W.Has(x) then
        id = x
        break
      end
    end
    if not id then
      Add("SKIP", "wishlist", "all test items are on your wishlist (not touched)")
      return
    end
    local on = W.Toggle(id)
    local has = W.Has(id)
    W.Remove(id)
    local gone = not W.Has(id)
    Add((on and has and gone) and "PASS" or "FAIL", "wishlist", string.format("toggle item %d on and off again (%s)", id, gone and "restored" or "NOT restored"))
  end)

  Try("alerts", function()
    local A = Seekwell.Alerts
    Add(A and A.Status and "PASS" or "FAIL", "alerts", A and A.Status and tostring(A.Status()) or "module missing")
  end)

  Try("sharing", function()
    local def = Config.SettingsDefaults and Config.SettingsDefaults().share
    local cur = Config.Get().share
    if def ~= false then
      Add("FAIL", "sharing", "default is not OFF")
    elseif cur then
      Add("WARN", "sharing", "ON (you turned it on; default OFF)")
    else
      Add("PASS", "sharing", "OFF (default)")
    end
  end)

  Try("error log", function()
    local fe = G("ForeverErrorLog")
    if not (fe and fe.GetErrors) then
      Add("SKIP", "error log", "ForeverErrorLog not installed")
      return
    end
    local n, last = 0, nil
    for _, e in ipairs(fe.GetErrors() or {}) do
      local msg = type(e) == "table" and (e.msg or e.message or e.text or e[1]) or e
      msg = tostring(msg or "")
      if msg:find("Seekwell:", 1, true) then
        n = n + 1
        last = msg
      end
    end
    Add(n == 0 and "PASS" or "WARN", "error log", n == 0 and "no Seekwell: entries" or string.format("%d Seekwell: entr%s, last: %s", n, n == 1 and "y" or "ies", last:sub(1, 120)))
  end)

  local sum = { PASS = 0, WARN = 0, FAIL = 0, SKIP = 0 }
  for _, r in ipairs(out) do
    sum[r[1]] = (sum[r[1]] or 0) + 1
  end
  return out, sum
end

function ST.Print()
  local P = Seekwell.Print or print
  local out, sum = ST.Run()
  P("selftest v" .. tostring(Seekwell.Config.VERSION) .. ":")
  for _, r in ipairs(out) do
    P(string.format("  %s%s|r %s \226\128\148 %s", COLOR[r[1]] or "", r[1], r[2], r[3]))
  end
  P(string.format("selftest: %s%d PASS|r, %s%d WARN|r, %s%d FAIL|r, %s%d SKIP|r", COLOR.PASS, sum.PASS, COLOR.WARN, sum.WARN, COLOR.FAIL,
    sum.FAIL, COLOR.SKIP, sum.SKIP))
  return out, sum
end

if Seekwell.RegisterSlash then
  Seekwell.RegisterSlash("selftest", function()
    ST.Print()
  end)
end
if Seekwell.L and type(Seekwell.L.HELP_LINES) == "table" then
  table.insert(Seekwell.L.HELP_LINES, "/sw selftest — check every piece in the running game (PASS / WARN / FAIL per line)")
end

-- /sw perf: which addons use the most memory (and CPU when the script profiler is on) -----------------
local function PerfCall(name, ...)
  local f = (C_AddOns and C_AddOns[name]) or _G[name]
  if type(f) ~= "function" then
    return nil
  end
  local ok, a, b = pcall(f, ...)
  if ok then
    return a, b
  end
  return nil
end

function ST.Perf()
  local P = Seekwell.Print or print
  PerfCall("UpdateAddOnMemoryUsage")
  PerfCall("UpdateAddOnCPUUsage")
  local n = tonumber(PerfCall("GetNumAddOns")) or 0
  local rows, haveCpu = {}, false
  for i = 1, n do
    local name = PerfCall("GetAddOnInfo", i)
    if type(name) == "string" then
      local mem = tonumber(PerfCall("GetAddOnMemoryUsage", i)) or 0
      local cpu = tonumber(PerfCall("GetAddOnCPUUsage", i)) or 0
      if cpu > 0 then
        haveCpu = true
      end
      rows[#rows + 1] = { name = name, mem = mem, cpu = cpu }
    end
  end
  table.sort(rows, function(a, b)
    return a.mem > b.mem
  end)
  P("perf: memory by addon (top 8):")
  for i = 1, math.min(8, #rows) do
    P(string.format("  %-28s %7.1f MB", rows[i].name, rows[i].mem / 1024))
  end
  if haveCpu then
    table.sort(rows, function(a, b)
      return a.cpu > b.cpu
    end)
    P("perf: CPU since reload / last reset (top 8, ms):")
    for i = 1, math.min(8, #rows) do
      P(string.format("  %-28s %9.0f ms", rows[i].name, rows[i].cpu))
    end
  else
    P("perf: CPU is not measured. Type /console scriptProfile 1, then /reload, loot a few mobs and run /sw perf again (turn it off with /console scriptProfile 0).")
  end
  local fps = GetFramerate and GetFramerate() or 0
  local _, _, home, world = GetNetStats and GetNetStats()
  P(string.format("perf: %.0f fps, latency home %s ms / world %s ms", tonumber(fps) or 0, tostring(home), tostring(world)))
end

if Seekwell.RegisterSlash then
  Seekwell.RegisterSlash("perf", function()
    ST.Perf()
  end)
end
if Seekwell.L and type(Seekwell.L.HELP_LINES) == "table" then
  table.insert(Seekwell.L.HELP_LINES, "/sw perf — top addons by memory and CPU, FPS and latency (finds what slows the game)")
end
