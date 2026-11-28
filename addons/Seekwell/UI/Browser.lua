--[[
  Seekwell.Browser — the Search page of the browser window (fixed section "search", browser mode), a two-pane
  master / detail page:
    left  = search box, mode tabs All / Items / Mobs with live counts, collapsible filters, and a virtual results
            list (20 pooled rows scrolled by offset over up to 300 matches per kind; mouse wheel + slider);
    right = the selected item or mob: header (wishlist toggle + wanted amount, link), map buttons, a zone map
            preview with the known spots (UI/MapPreview.lua) and a zone selector, and below it the sources of
            the item (mobs, vendors, quests) or the drop table of the mob, in its own scroll frame.
  Typing searches after a 0.3 s pause (C_Timer, no OnUpdate); Enter searches at once. Empty search = wishlist +
  recently viewed. Clicking a link in the right pane selects it (history: < Back).
  Seekwell.MobView.Show(id) / Seekwell.ItemView.Show(id) select a mob / an item on this page.
]]

Seekwell = Seekwell or {}
local B = {}
Seekwell.Browser = B
local MV = {}
Seekwell.MobView = MV

local SCAN_CAP = 300
local POOL = 20
local ROW_H = 34
local LEFT_W = 380
local GAP = 16
local RECENT_MAX = 15
local DEBOUNCE = 0.3
local DETAIL_MAX = 150
local DROW_H = 34
local MAX_ZONE_BTNS = 6
local MAX_SRC_MOBS = 200 -- sources of an item whose spots go on the preview (all of them: B.Coverage counts the same list)
local OWN_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
local STAR_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local PIN_ICON = "Interface\\Minimap\\Tracking\\None"
local MOB_ICON = "Interface\\Icons\\INV_Misc_Head_Dragon_01"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local query = ""
local results, total, capped = {}, 0, false
local itemsRes, mobsRes, dungRes = {}, {}, {}
local djBoss -- index of the boss whose loot the dungeon page shows
local offset, visible = 0, 14
local sel -- { kind = "item"|"mob", id }
local stack = {} -- { {view, id} } selections since the last list click
local goingBack = false
local token = 0
local awaitInfo, infoQueued = false, false
local mobIndex
local locMemo = {}
local zones, zoneIdx = {}, 1
local sizeW, sizeH = 900, 600

-- widgets
local sec, L, Rt, box, note, list, slider, fp, filterBtn
local tabs, rows = {}, {}
local hDJ
local hint, body, hIcon, hName, hOwn, hInfo, hWish, hQty, hQtyLabel, hLink, hBack
local bMap, bClear, bWorld, bWp, zoneLabel, preview, dHead, dScroll, dChild, dCover, bLocFirst
local zoneBtns, drows = {}, {}
local settingSlider = false

local function Safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      local rec = Seekwell.RecordError
      if rec then
        pcall(rec, "browser." .. name, err)
      end
    end
  end
end

local function Trim(s)
  return (tostring(s or ""):match("^%s*(.-)%s*$")) or ""
end

local function BS()
  local s = Seekwell.Config.Get()
  if type(s.browser) ~= "table" then
    s.browser = {}
  end
  local b = s.browser
  if (tonumber(b.v) or 0) < 2 then
    -- 0.3.1: a mode left on "mobs" / "items" by an older /sw find made plain searches look empty
    b.mode = "all"
    b.v = 2
  end
  if b.mode ~= "items" and b.mode ~= "mobs" and b.mode ~= "dungeons" then
    b.mode = "all"
  end
  b.minPct = tonumber(b.minPct) or 0
  if b.autoPin == nil then
    b.autoPin = true
  end
  return b
end
B.Settings = BS

local function Recent()
  local c = Seekwell.Config.Char()
  if type(c.recent) ~= "table" then
    c.recent = {}
  end
  return c.recent
end

local function IV()
  return Seekwell.ItemView
end

local function Print(msg)
  if Seekwell.Print then
    Seekwell.Print(msg)
  end
end

-- search -----------------------------------------------------------------------------------------

local function Score(a, b, q)
  local la, lb = a.name:lower(), b.name:lower()
  local ea, eb = la == q, lb == q
  if ea ~= eb then
    return ea
  end
  local pa, pb = la:sub(1, #q) == q, lb:sub(1, #q) == q
  if pa ~= pb then
    return pa
  end
  if la ~= lb then
    return la < lb
  end
  return a.id < b.id
end

local function MobIndex()
  if mobIndex then
    return mobIndex
  end
  mobIndex = {}
  local seen = {}
  local function Add(id, name)
    id = tonumber(id)
    if id and not seen[id] and type(name) == "string" and name ~= "" then
      seen[id] = true
      mobIndex[#mobIndex + 1] = { id = id, name = name, lower = name:lower() }
    end
  end
  local f = rawget(_G, "TnnysMobLoot_Forever")
  if type(f) == "table" and type(f.npc) == "table" then
    for id, v in pairs(f.npc) do
      if type(v) == "table" then
        Add(id, v[1])
      end
    end
  end
  local st = rawget(_G, "TnnysMobLoot_Starter")
  if type(st) == "table" and type(st.npc) == "table" then
    for id, v in pairs(st.npc) do
      if type(v) == "table" then
        Add(id, v[4])
      end
    end
  end
  return mobIndex
end

local learnedNames, learnedGen
local function LearnedNames()
  local L = Seekwell.Learned
  local g = L and L.generation or 0
  if learnedNames and learnedGen == g then
    return learnedNames
  end
  learnedNames, learnedGen = {}, g
  local l = Seekwell.Config.Learned()
  for id, e in pairs(type(l.npc) == "table" and l.npc or {}) do
    if type(e) == "table" and type(e.n) == "string" then
      learnedNames[#learnedNames + 1] = { id = id, name = e.n, lower = e.n:lower() }
    end
  end
  return learnedNames
end

--- Mobs whose name contains q (case-insensitive): { {id, name} } best first, at most cap; second value = capped.
function B.SearchMobs(q, cap)
  cap = cap or SCAN_CAP
  q = Trim(q):lower()
  local out, seen, hit = {}, {}, false
  local num = tonumber(q)
  if num then
    local R = Seekwell.Registry
    local n = R and R.NpcName(num)
    if n then
      return { { id = num, name = n } }, false
    end
  end
  if #q < 2 then
    return out, false
  end
  local function Try(id, name, lower)
    if #out >= cap then
      hit = true
      return
    end
    id = tonumber(id)
    if id and not seen[id] and type(name) == "string" and (lower or name:lower()):find(q, 1, true) then
      seen[id] = true
      out[#out + 1] = { id = id, name = name }
    end
  end
  for _, e in ipairs(LearnedNames()) do
    Try(e.id, e.name, e.lower)
  end
  for _, e in ipairs(MobIndex()) do
    Try(e.id, e.name, e.lower)
    if hit then
      break
    end
  end
  local F = Seekwell.FDB
  if not hit and F and F.NameSearch then
    local ok, lst = pcall(F.NameSearch, q, "npc", cap)
    for _, e in ipairs(ok and type(lst) == "table" and lst or {}) do
      Try(e.id, e.name)
      if hit then
        break
      end
    end
  end
  table.sort(out, function(a, b)
    return Score(a, b, q)
  end)
  return out, hit
end

--- Items matching q (Seekwell.Wish.Find sources); uncached names are requested by Find itself.
function B.SearchItems(q, cap)
  cap = cap or SCAN_CAP
  local W = Seekwell.Wish
  local out = (W and W.Find) and W.Find(q, cap) or {}
  return out, #out >= cap
end

local function Located(npc)
  local v = locMemo[npc]
  if v == nil then
    v = false
    local Sp = Seekwell.Spawns
    if Sp and Sp.HasAny then
      local ok, has = pcall(Sp.HasAny, npc)
      v = ok and has and true or false
    elseif Sp and Sp.MapsForMob then
      local ok, lst = pcall(Sp.MapsForMob, npc)
      v = ok and type(lst) == "table" and #lst > 0 or false
    end
    if not v then
      local e = Seekwell.Config.Learned().npc
      e = type(e) == "table" and e[npc] or nil
      v = type(e) == "table" and type(e.m) == "table" and next(e.m) ~= nil or false
    end
    locMemo[npc] = v
  end
  return v
end

local FTAG = " |cffe6b422F|r"
local function DJ()
  return Seekwell.DJ
end

local ENTRANCE_ONLY = "entrance only \226\128\148 install ForeverDungeonJournal for bosses"

--- Entrance-only dungeon (ForeverDB, not in the Dungeon Journal): ids are negative session positions in FDB.Dungeons().
local function FdbDungeon(id)
  id = tonumber(id)
  if not (id and id < 0) then
    return nil
  end
  local F = Seekwell.FDB
  if not (F and F.Dungeons) then
    return nil
  end
  local ok, lst = pcall(F.Dungeons)
  local e = ok and type(lst) == "table" and lst[-id] or nil
  return type(e) == "table" and e or nil
end
B.FdbDungeon = FdbDungeon

--- What the map hunt takes for a dungeon: its list position, or the name for an entrance-only one.
local function DungeonArg(kind, id)
  if kind == "dungeon" then
    local fe = FdbDungeon(id)
    if fe then
      return fe.name
    end
  end
  return id
end

local function IsForever(kind, id)
  local F = Seekwell.FDB
  if F and F.IsForeverOnly and (kind == "item" or kind == "mob") then
    local okF, vF = pcall(F.IsForeverOnly, kind, id)
    if okF and vF then
      return true
    end
  end
  local D = DJ()
  if not D then
    return false
  end
  local ok, v
  if kind == "item" then
    ok, v = pcall(D.IsForeverItem, id)
  elseif kind == "mob" then
    ok, v = pcall(D.IsForeverNpc, id)
  else
    return true -- Dungeon Journal dungeons are shown as Forever content
  end
  return ok and v or false
end
B.IsForever = IsForever

--- Width from the label (never narrower than minW), so no label overflows its button.
local function Fit(b, minW)
  local fs = b and b.GetFontString and b:GetFontString()
  local w = fs and fs.GetStringWidth and tonumber(fs:GetStringWidth())
  if w and w > 0 then
    b:SetWidth(math.max(minW or 0, math.ceil(w) + 24))
  end
  return b
end
B.Fit = Fit


local function OriginClass(s)
  if s.origin == "forever" or s.origin == "learned" or s.origin == "forever_db" then
    return 1
  elseif s.origin == "classic" then
    return 2
  end
  return 3
end

--- Drop sources of an item in display order: Registry ranking (Forever / learned, then Classic, by %), and with
--- browser.locatedFirst (default on) the located mobs float above unlocated ones within the same origin class.
function B.OrderSources(srcs)
  local out = {}
  for i, x in ipairs(srcs or {}) do
    out[i] = x
  end
  if BS().locatedFirst == false then
    return out
  end
  local key = {}
  for i, x in ipairs(out) do
    key[x] = { OriginClass(x), (x.npc and Located(x.npc)) and 0 or 1, i }
  end
  table.sort(out, function(a, b)
    local ka, kb = key[a], key[b]
    if ka[1] ~= kb[1] then
      return ka[1] < kb[1]
    end
    if ka[2] ~= kb[2] then
      return ka[2] < kb[2]
    end
    return ka[3] < kb[3]
  end)
  return out
end

local fdbHint -- shown once when the ForeverDB data addon is missing

local function FdbHint()
  if fdbHint ~= nil then
    return nil
  end
  local F = Seekwell.FDB
  local ok, avail = pcall(function()
    return F and F.Enabled() and F.Available()
  end)
  if F and ok and F.Enabled() and not avail then
    fdbHint = false
    return "For full Forever coverage install the ForeverDB data addon (see README)"
  end
  return nil
end
B.FdbHint = FdbHint

--- located, total drop mobs of an item (Dungeon Journal rows are not mobs and are not counted).
function B.Coverage(itemID)
  local srcs = Seekwell.Registry.ItemSources(itemID, 200) or {}
  local nLoc, n = 0, 0
  for _, x in ipairs(srcs) do
    if x.origin ~= "dj" and x.npc then
      n = n + 1
      if Located(x.npc) then
        nLoc = nLoc + 1
      end
    end
  end
  return nLoc, n
end

function B.CoverageText(kind, id)
  local hint = FdbHint()
  if hint then
    return hint
  end
  if kind == "item" then
    local nLoc, n = B.Coverage(id)
    if n == 0 then
      return ""
    end
    if nLoc == n then
      return string.format("Locations known for all %d mob(s) (Classic data + your loot)", n)
    end
    return string.format("Locations known for %d of %d mobs (Classic data + your loot) \226\128\148 the rest: loot them to learn where they live", nLoc, n)
  elseif kind == "mob" then
    if Located(id) then
      return "Location known (Classic data + your loot)"
    end
    return "Location not known yet (no Classic spawn data for this mob) \226\128\148 loot it once to learn where it lives"
  end
  return ""
end

local function ItemSummary(r)
  if r.srcs == nil then
    r.srcs = Seekwell.Registry.ItemSources(r.id, 200)
  end
  return r.srcs
end

local function MobDrops(r)
  if r.drops == nil then
    r.drops = Seekwell.Registry.NpcDrops(r.id) or false
  end
  return r.drops
end

local function ItemLocated(r)
  if r.loc == nil then
    r.loc = false
    local srcs = ItemSummary(r)
    for i = 1, math.min(10, #srcs) do
      if Located(srcs[i].npc) then
        r.loc = true
        break
      end
    end
  end
  return r.loc
end

local function Keep(r, s)
  local W = Seekwell.Wish
  local minP = s.minPct or 0
  if s.foreverOnly and not IsForever(r.kind, r.id) then
    return false
  end
  if r.kind == "dungeon" then
    return not s.onlyWish
  end
  if r.kind == "item" then
    if s.onlyWish and not W.Has(r.id) then
      return false
    end
    local srcs = (minP > 0 or s.onlyLocated) and ItemSummary(r) or nil
    if minP > 0 and not (srcs[1] and (tonumber(srcs[1].p) or 0) >= minP) then
      return false
    end
    if s.onlyLocated then
      return ItemLocated(r)
    end
    return true
  end
  if s.onlyLocated and not Located(r.id) then
    return false
  end
  if s.onlyWish or minP > 0 then
    local d = MobDrops(r)
    local wishMobs = Seekwell.Config.Char().wishMobs
    local wished = type(wishMobs) == "table" and wishMobs[r.id] and true or false
    local n = 0
    for _, row in ipairs(d and d.rows or {}) do
      if (tonumber(row.p) or 0) >= minP then
        n = n + 1
        if W.Has(row.id) then
          wished = true
        end
      end
    end
    if minP > 0 and n == 0 then
      return false
    end
    if s.onlyWish and not wished then
      return false
    end
  end
  return true
end

local Render, RenderDetail

local function Filter(list_, s)
  local out = {}
  for _, r in ipairs(list_) do
    local ok, keep = pcall(Keep, r, s)
    if ok and keep then
      out[#out + 1] = r
    end
  end
  return out
end

--- Pick the list of the current mode (empty query: wishlist + recent in every mode).
local function Pick()
  local s = BS()
  results = {}
  if s.mode == "dungeons" then
    for _, r in ipairs(dungRes) do
      results[#results + 1] = r
    end
  elseif Trim(query) == "" or s.mode == "all" then
    for _, r in ipairs(itemsRes) do
      results[#results + 1] = r
    end
    for _, r in ipairs(mobsRes) do
      results[#results + 1] = r
    end
    if Trim(query) ~= "" then
      for _, r in ipairs(dungRes) do
        results[#results + 1] = r
      end
    end
    if Trim(query) == "" then
      table.sort(results, function(a, b)
        return a.order < b.order
      end)
    end
  elseif s.mode == "items" then
    for _, r in ipairs(itemsRes) do
      results[#results + 1] = r
    end
  else
    for _, r in ipairs(mobsRes) do
      results[#results + 1] = r
    end
  end
  total = #results
  offset = math.max(0, math.min(offset, total - visible))
end

--- Run the search for the current query (rerun = the one repeat after item names arrived).
local function Run(rerun)
  if Seekwell.FDB and Seekwell.FDB.Touch and Trim(query) ~= "" then
    pcall(Seekwell.FDB.Touch)
  end
  token = token + 1
  locMemo = {}
  local s = BS()
  local q = Trim(query)
  local items, mobs = {}, {}
  capped = false
  if q == "" then
    local seen, n = {}, 0
    for _, w in ipairs(Seekwell.Wish.Items()) do
      seen["item" .. w.id] = true
      n = n + 1
      items[#items + 1] = { kind = "item", id = w.id, order = n }
    end
    for _, e in ipairs(Recent()) do
      if e.k == "dungeon" then
        e = {}
      end
      local kind = e.k == "mob" and "mob" or "item"
      local k = kind .. tostring(e.id)
      if not seen[k] and tonumber(e.id) then
        seen[k] = true
        n = n + 1
        local r = { kind = kind, id = tonumber(e.id), recent = true, order = n }
        if kind == "mob" then
          mobs[#mobs + 1] = r
        else
          items[#items + 1] = r
        end
      end
    end
  else
    local fi, c1 = B.SearchItems(q, SCAN_CAP)
    for _, f in ipairs(fi) do
      items[#items + 1] = { kind = "item", id = f.id, name = f.name }
    end
    local fm, c2 = B.SearchMobs(q, SCAN_CAP)
    for _, m in ipairs(fm) do
      mobs[#mobs + 1] = { kind = "mob", id = m.id, name = m.name }
    end
    capped = (c1 and s.mode ~= "mobs") or (c2 and s.mode ~= "items") or false
    if not rerun then
      awaitInfo = true
    end
  end
  local dungs = {}
  if (q ~= "" and #q >= 2) or s.mode == "dungeons" then
    local D = DJ()
    local ok, lst = pcall(function()
      return D and D.Find(q) or {}
    end)
    for _, e in ipairs(ok and lst or {}) do
      dungs[#dungs + 1] = { kind = "dungeon", id = e.index, name = e.name }
    end
    -- ForeverDB dungeons the journal lacks (or all of them without the journal): entrance-only pages
    local F = Seekwell.FDB
    if F and F.Dungeons and F.Enabled and F.Enabled() then
      if s.mode == "dungeons" and F.Touch then
        pcall(F.Touch) -- the Dungeons tab is a real need; never loaded at login
      end
      local okF, fl = pcall(F.Dungeons)
      local ql = q:lower()
      for i, e in ipairs(okF and type(fl) == "table" and fl or {}) do
        if e.mapID and e.name and (ql == "" or e.name:lower():find(ql, 1, true)) then
          local okG, have = pcall(function()
            return D and D.Get(e.name)
          end)
          if not (okG and have) then
            dungs[#dungs + 1] = { kind = "dungeon", id = -i, name = e.name, fdb = true }
          end
        end
      end
    end
  end
  itemsRes, mobsRes, dungRes = Filter(items, s), Filter(mobs, s), Filter(dungs, s)
  if not rerun then
    offset = 0
  end
  Pick()
  Render()
end
B.Run = function()
  Run(false)
end

--- Search after a pause in typing; a newer keystroke cancels the older timer.
local function Debounce()
  token = token + 1
  local my = token
  local go = Safe("debounce", function()
    if my == token then
      Run(false)
    end
  end)
  if C_Timer and C_Timer.After then
    C_Timer.After(DEBOUNCE, go)
  else
    go()
  end
end
B.Debounce = Debounce

function B.SetQuery(text, typed)
  query = tostring(text or "")
  if typed then
    Debounce()
  end
end

function B.Results()
  return results, total, capped
end

--- Counts of the last search: items, mobs, dungeons, Forever results (tab independent).
function B.Counts()
  return #itemsRes, #mobsRes, #dungRes, B.ForeverCount()
end

function B.ForeverCount()
  local n = 0
  for _, l in ipairs({ itemsRes, mobsRes, dungRes }) do
    for _, r in ipairs(l) do
      if r.fv == nil then
        r.fv = IsForever(r.kind, r.id)
      end
      if r.fv then
        n = n + 1
      end
    end
  end
  return n
end

function B.SetMode(m)
  if m ~= "items" and m ~= "mobs" and m ~= "dungeons" then
    m = "all"
  end
  BS().mode = m
  offset = 0
  Pick()
  Render()
end

--- The status line above the list.
function B.StatusText()
  local s = BS()
  local q = Trim(query)
  local ni, nm = #itemsRes, #mobsRes
  local filtered = s.onlyLocated or s.onlyWish or (s.minPct or 0) > 0
  if s.mode == "dungeons" then
    if not (DJ() and DJ().Available()) and #dungRes == 0 then
      return "Dungeons come from the ForeverDungeonJournal addon (not loaded) or the ForeverDB data (entrances only)."
    end
    return string.format("%d dungeon(s)%s", #dungRes, q ~= "" and (" match \"" .. q .. "\"") or "")
  end
  if q == "" then
    if total == 0 then
      return "Type part of an item or mob name. Your wishlist and recently viewed pages appear here."
    end
    return "Wishlist and recently viewed:"
  end
  if #q < 2 and not tonumber(q) then
    return "Type at least 2 letters."
  end
  if ni == 0 and nm == 0 then
    local hint = FdbHint()
    return "Nothing found for \"" .. q .. "\"" .. (filtered and " with these filters." or ".") .. (hint and (" " .. hint) or "")
  end
  if s.mode == "items" and ni == 0 then
    return string.format("No items - %d mob%s match (click Mobs)", nm, nm == 1 and "" or "s")
  elseif s.mode == "mobs" and nm == 0 then
    return string.format("No mobs - %d item%s match (click Items)", ni, ni == 1 and "" or "s")
  elseif s.mode == "all" and ni == 0 then
    return string.format("No items match \"%s\" - %d mob%s do", q, nm, nm == 1 and "" or "s")
  elseif s.mode == "all" and nm == 0 then
    return string.format("%d item%s, no mobs named \"%s\"", ni, ni == 1 and "" or "s", q)
  end
  local nf = B.ForeverCount()
  return string.format("%d%s result(s)%s%s", total, capped and "+" or "", nf > 0 and (" \194\183 Forever " .. nf) or "",
    capped and " - refine your search" or "")
end

-- selection and history --------------------------------------------------------------------------

local function AfterWish()
  Seekwell.Wish.RefreshOwned()
  if Seekwell.TargetPanel and Seekwell.TargetPanel.Render then
    pcall(Seekwell.TargetPanel.Render)
  end
end

local function AutoPin(kind, id)
  if BS().autoPin == false then
    return
  end
  local M = Seekwell.Map
  if M and M.Set then
    pcall(M.Set, kind, DungeonArg(kind, id), true)
  elseif M and M.Hunt then
    pcall(M.Hunt, kind, DungeonArg(kind, id))
  end
end

--- History for Back and the recently viewed list.
function B.Visit(view, id)
  id = tonumber(id)
  if not id then
    return
  end
  local rec = view == "dungeon" and {} or Recent() -- dungeon ids are session list positions: never saved
  for i = #rec, 1, -1 do
    if rec[i].k == view and tonumber(rec[i].id) == id then
      table.remove(rec, i)
    end
  end
  table.insert(rec, 1, { k = view, id = id })
  while #rec > RECENT_MAX do
    rec[#rec] = nil
  end
  if goingBack then
    return
  end
  local top = stack[#stack]
  if not (top and top.view == view and top.id == id) then
    stack[#stack + 1] = { view = view, id = id }
    if #stack > 20 then
      table.remove(stack, 1)
    end
  end
end

local function ShowPage()
  local Win = Seekwell.Window
  if Win then
    if Win.ShowBrowser then
      Win.ShowBrowser("search")
    elseif Win.Show then
      Win.Show("search")
    end
  end
end

--- Select an item or a mob: the right pane shows it (and the map hunt follows it when browser.autoPin is on).
function B.Select(kind, id, fromList)
  id = tonumber(id)
  if not id or (kind ~= "item" and kind ~= "mob" and kind ~= "dungeon") then
    return
  end
  if fromList then
    stack = {}
  end
  if not (sel and sel.kind == kind and sel.id == id) then
    djBoss = nil
  end
  sel = { kind = kind, id = id }
  zoneIdx = nil
  B.Visit(kind, id)
  ShowPage()
  AutoPin(kind, id)
  Safe("detail", RenderDetail)()
  Safe("render", Render)()
end

function B.Selected()
  return sel
end

--- Show the loot of boss i on the selected dungeon page.
function B.SelectBoss(i)
  djBoss = tonumber(i)
  Safe("detail", RenderDetail)()
end

--- Open the Search page; text = new query (searched at once), mode = "all"|"items"|"mobs"|"dungeons".
function B.Open(text, mode)
  stack = {}
  sel = nil
  if mode then
    BS().mode = mode
  end
  ShowPage()
  if text ~= nil then
    query = tostring(text)
    if box then
      box:SetText(query)
    end
    Safe("run", Run)(false)
  else
    B.Render()
  end
  Safe("detail", RenderDetail)()
end

--- Back: the previous selection, else no selection (the search keeps its query).
function B.Back()
  stack[#stack] = nil
  local top = stack[#stack]
  goingBack = true
  local ok, err = pcall(function()
    if top then
      B.Select(top.view, top.id)
    else
      sel = nil
      ShowPage()
      RenderDetail()
      Render()
    end
  end)
  goingBack = false
  if not ok and Seekwell.RecordError then
    Seekwell.RecordError("browser.back", err)
  end
end

function B.Current()
  if sel then
    return { view = sel.kind, id = sel.id, query = query }
  end
  return { view = "search", query = query }
end

function B.Stack()
  return stack
end

function MV.Current()
  return sel and sel.kind == "mob" and sel.id or nil
end

function MV.Show(id)
  B.Select("mob", id)
end

function MV.Render()
  Safe("detail", RenderDetail)()
end

-- left pane: rows ------------------------------------------------------------------------------

local function MakeRow(parent, i, width)
  local r = CreateFrame("Button", nil, parent)
  r:SetSize(width, ROW_H - 2)
  r.hl = r:CreateTexture(nil, "BACKGROUND")
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(1, 1, 1, 0.06)
  r.hl:Hide()
  r.selTex = r:CreateTexture(nil, "BACKGROUND", nil, 1)
  r.selTex:SetAllPoints()
  r.selTex:SetColorTexture(1, 0.82, 0, 0.22)
  r.selTex:Hide()
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(26, 26)
  r.icon:SetPoint("LEFT", 2, 0)
  r.l1 = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.l1:SetPoint("TOPLEFT", 34, -2)
  r.l1:SetWidth(width - 100)
  r.l1:SetJustifyH("LEFT")
  r.l1:SetWordWrap(false)
  r.l2 = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.l2:SetPoint("TOPLEFT", 34, -17)
  r.l2:SetWidth(width - 100)
  r.l2:SetJustifyH("LEFT")
  r.l2:SetWordWrap(false)
  r.pin = r:CreateTexture(nil, "OVERLAY")
  r.pin:SetSize(14, 14)
  r.pin:SetPoint("RIGHT", -46, 0)
  r.pin:SetTexture(PIN_ICON)
  r.star = CreateFrame("Button", nil, r)
  r.star:SetSize(18, 18)
  r.star:SetPoint("RIGHT", -22, 0)
  r.star.tex = r.star:CreateTexture(nil, "ARTWORK")
  r.star.tex:SetAllPoints()
  r.star.tex:SetTexture(STAR_ICON)
  r.star:SetScript("OnClick", Safe("star", function()
    if r.item then
      Seekwell.Wish.Toggle(r.item)
      AfterWish()
      if r.onWish then
        r.onWish()
      end
    end
  end))
  r.own = r:CreateTexture(nil, "OVERLAY")
  r.own:SetSize(16, 16)
  r.own:SetPoint("RIGHT", -2, 0)
  r.own:SetTexture(OWN_ICON)
  r:SetScript("OnEnter", function(self)
    self.hl:Show()
    if self.kind == "item" and self.item and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if not pcall(GameTooltip.SetItemByID, GameTooltip, self.item) then
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.item)
      end
      GameTooltip:Show()
    end
  end)
  r:SetScript("OnLeave", function(self)
    self.hl:Hide()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  return r
end

local function FillItemRow(r, id, fallbackName, sub, located)
  local W = Seekwell.Wish
  local name, quality, icon = IV().ItemName(id)
  r.kind, r.item, r.mob = "item", id, nil
  r.icon:SetTexture(icon or UNKNOWN_ICON)
  r.l1:SetText((name or fallbackName or ("item " .. id)) .. (IsForever("item", id) and FTAG or ""))
  r.l1:SetTextColor(IV().QualityRGB(quality))
  r.l2:SetText(sub or "")
  r.l2:SetTextColor(0.65, 0.65, 0.65)
  r.star:Show()
  r.star.tex:SetAlpha(W.Has(id) and 1 or 0.25)
  r.own:SetShown(W.IsOwned and W.IsOwned(id) or false)
  r.pin:SetShown(located and true or false)
end

local function SourceText(srcs)
  local R = Seekwell.Registry
  local s = srcs[1]
  if not s then
    return "no known source"
  end
  local t = (R.NpcName(s.npc) or ("npc " .. s.npc)) .. " " .. R.FormatPct(s.p)
  if s.origin == "dj" then
    t = tostring(s.dungeon) .. " \226\128\148 " .. tostring(s.boss) .. " (Dungeon Journal)"
  end
  if #srcs > 1 then
    t = t .. " \194\183 +" .. (#srcs - 1) .. " more"
  end
  return t
end

local function LocationText(npc)
  local zs = IV().Where(npc)
  if #zs == 0 then
    return "location unknown"
  end
  return "seen in " .. zs[1] .. (#zs > 1 and (" +" .. (#zs - 1)) or "")
end

local function MobSub(d, npc, minP)
  local parts = {}
  if d and (d.learnedKills or 0) > 0 then
    parts[#parts + 1] = "learned " .. d.learnedKills .. " kills"
  elseif d and d.foreverKills then
    parts[#parts + 1] = "Forever n=" .. tostring(d.foreverKills)
  end
  local n = 0
  for _, row in ipairs(d and d.rows or {}) do
    if (tonumber(row.p) or 0) >= (minP or 0) then
      n = n + 1
    end
  end
  parts[#parts + 1] = n .. " drop(s)"
  parts[#parts + 1] = LocationText(npc)
  return table.concat(parts, " \194\183 ")
end

local function FillMobRow(r, e, minP)
  local R = Seekwell.Registry
  local d = MobDrops(e)
  r.kind, r.mob, r.item = "mob", e.id, nil
  r.icon:SetTexture(MOB_ICON)
  r.l1:SetText((R.NpcName(e.id) or e.name or ("npc " .. e.id)) .. IV().LevelText(d or nil) .. (IsForever("mob", e.id) and FTAG or ""))
  r.l1:SetTextColor(1, 0.82, 0)
  r.l2:SetText(MobSub(d or nil, e.id, minP))
  r.l2:SetTextColor(0.65, 0.65, 0.65)
  r.star:Hide()
  r.own:Hide()
  r.pin:SetShown(Located(e.id))
end

local DUNGEON_ICON = "Interface\\Icons\\INV_Misc_Key_03"

local function FillDungeonRow(r, e)
  local fe = FdbDungeon(e.id)
  if fe then
    r.kind, r.mob, r.item = "dungeon", nil, nil
    r.icon:SetTexture(DUNGEON_ICON)
    r.l1:SetText(fe.name .. FTAG)
    r.l1:SetTextColor(0.95, 0.55, 1)
    r.l2:SetText((IV().MapName(fe.mapID) or ("map " .. tostring(fe.mapID))) .. " \194\183 " .. ENTRANCE_ONLY)
    r.l2:SetTextColor(0.65, 0.65, 0.65)
    r.star:Hide()
    r.own:Hide()
    r.pin:SetShown(true)
    return
  end
  local d = DJ() and DJ().Get(e.id)
  r.kind, r.mob, r.item = "dungeon", nil, nil
  r.icon:SetTexture(DUNGEON_ICON)
  r.l1:SetText((d and d.name or e.name or "?") .. (d and d.level and (" (" .. d.level .. ")") or "") .. FTAG)
  r.l1:SetTextColor(0.95, 0.55, 1)
  local m = d and DJ().Entrance(d.name)
  local zone = m and IV().MapName(m) or (d and d.location) or "entrance not known"
  r.l2:SetText(string.format("%d boss(es) \194\183 %d quest(s) \194\183 %s", d and d.bosses or 0, d and d.quests or 0, zone))
  r.l2:SetTextColor(0.65, 0.65, 0.65)
  r.star:Hide()
  r.own:Hide()
  r.pin:SetShown(m ~= nil)
end

local function SetTab(t, label, on)
  t.text:SetText(label)
  t.on = on
  if on then
    t.text:SetTextColor(1, 0.82, 0)
  else
    t.text:SetTextColor(0.6, 0.6, 0.6)
  end
  t.line:SetShown(on)
  t.bg:SetShown(on)
end

Render = function()
  if not sec then
    return
  end
  local s = BS()
  local ni, nm, nd = #itemsRes, #mobsRes, #dungRes
  if tabs.all then
    SetTab(tabs.all, "All " .. (ni + nm + (Trim(query) ~= "" and nd or 0)), s.mode == "all")
    SetTab(tabs.items, "Items " .. ni, s.mode == "items")
    SetTab(tabs.mobs, "Mobs " .. nm, s.mode == "mobs")
    if tabs.dungeons then
      SetTab(tabs.dungeons, "Dungeons " .. nd, s.mode == "dungeons")
    end
  end
  offset = math.max(0, math.min(offset, total - visible))
  for i = 1, POOL do
    local r = rows[i]
    local e = (i <= visible) and results[offset + i] or nil
    if r and e then
      r.onWish = Render
      if e.kind == "item" then
        FillItemRow(r, e.id, e.name, SourceText(ItemSummary(e)), ItemLocated(e))
      elseif e.kind == "dungeon" then
        FillDungeonRow(r, e)
      else
        FillMobRow(r, e, s.minPct)
      end
      r.entry = e
      r.selTex:SetShown(sel ~= nil and sel.kind == e.kind and sel.id == e.id)
      r:Show()
    elseif r then
      r.kind, r.item, r.mob, r.entry = false, false, false, false
      r.selTex:Hide()
      r:Hide()
    end
  end
  if slider then
    local max = math.max(0, total - visible)
    settingSlider = true
    slider:SetMinMaxValues(0, max)
    slider:SetValue(offset)
    settingSlider = false
    slider:SetShown(max > 0)
  end
  note:SetText(B.StatusText())
  local fs = BS()
  local nOn = (fs.onlyLocated and 1 or 0) + (fs.onlyWish and 1 or 0) + ((fs.minPct or 0) > 0 and 1 or 0) + (fs.foreverOnly and 1 or 0)
  if filterBtn then
    filterBtn.text:SetText((fs.filtersOpen and "[-] " or "[+] ") .. "Filters" .. (nOn > 0 and (" (" .. nOn .. " on)") or ""))
  end
end
B.Render = function()
  Safe("render", Render)()
end

function B.SetOffset(v)
  local o = math.max(0, math.min(math.floor(tonumber(v) or 0), total - visible))
  if o ~= offset then
    offset = o
    Render()
  end
end

function B.Offset()
  return offset, visible
end

--- Visible pooled rows: { {kind, id, row} }.
function B.VisibleRows()
  local out = {}
  for i = 1, POOL do
    local r = rows[i]
    if r and r.entry and r:IsShown() then
      out[#out + 1] = { kind = r.entry.kind, id = r.entry.id, row = r }
    end
  end
  return out
end

-- right pane -------------------------------------------------------------------------------------

local function Learned(npc)
  local l = Seekwell.Config.Learned().npc
  local e = type(l) == "table" and l[npc] or nil
  return type(e) == "table" and e or nil
end

--- Zones of the selection: { {mapID, name, points = {{x, y, label, src, npc}}} }, most spots first.
function B.ZonesFor(kind, id)
  local R = Seekwell.Registry
  local Sp = Seekwell.Spawns
  local npcs, ents = {}, {}
  local D = DJ()
  local fe = kind == "dungeon" and FdbDungeon(id) or nil
  if fe then
    -- entrance-only page: the point is added below (after Zone is defined)
  elseif kind == "dungeon" then
    local e = D and D.Get(id)
    if e then
      ents[1] = e.name
    end
  elseif kind == "mob" then
    npcs[1] = { npc = id }
  else
    local srcs = B.OrderSources(R.ItemSources(id, 200))
    for i = 1, math.min(MAX_SRC_MOBS, #srcs) do
      if srcs[i].origin ~= "dj" then
        npcs[#npcs + 1] = { npc = srcs[i].npc, p = srcs[i].p }
      end
    end
    local seen = {}
    local ok, rows = pcall(function()
      return D and D.ItemSources(id) or {}
    end)
    for _, r in ipairs(ok and rows or {}) do
      if not seen[r.dungeon] then
        seen[r.dungeon] = true
        ents[#ents + 1] = r.dungeon
      end
    end
  end
  local byMap, out = {}, {}
  local function Zone(mapID)
    mapID = tonumber(mapID)
    if not mapID then
      return nil
    end
    local z = byMap[mapID]
    if not z then
      z = { mapID = mapID, name = IV().MapName(mapID) or ("map " .. mapID), points = {} }
      byMap[mapID] = z
      out[#out + 1] = z
    end
    return z
  end
  if fe and fe.mapID then
    local z = Zone(fe.mapID)
    z.points[#z.points + 1] = { x = fe.x, y = fe.y, label = "Dungeon entrance: " .. fe.name, src = "entrance", dungeon = fe.name }
  end
  for _, n in ipairs(npcs) do
    local label = R.NpcName(n.npc) or ("npc " .. tostring(n.npc))
    if n.p then
      label = label .. " " .. R.FormatPct(n.p)
    end
    local maps = {}
    if Sp and Sp.MapsForMob then
      local ok, lst = pcall(Sp.MapsForMob, n.npc)
      if ok and type(lst) == "table" then
        maps = lst
      end
    end
    for _, mapID in ipairs(maps) do
      local z = Zone(mapID)
      local ok, pts = pcall(Sp.ForMob, n.npc, mapID)
      if z and ok and type(pts) == "table" then
        for _, p in ipairs(pts) do
          if type(p) == "table" and tonumber(p.x) and tonumber(p.y) then
            z.points[#z.points + 1] = { x = tonumber(p.x), y = tonumber(p.y), label = label, src = p.src, npc = n.npc, p = n.p }
          end
        end
      end
    end
    local e = Learned(n.npc)
    if e and type(e.m) == "table" then
      for mapID in pairs(e.m) do
        Zone(mapID)
      end
    end
  end
  for _, name in ipairs(D and ents or {}) do
    local ok, m, x, y, label, learned = pcall(D.Entrance, name)
    if ok and m then
      local z = Zone(m)
      z.points[#z.points + 1] = { x = x, y = y, label = D.EntranceTooltip(name), src = "entrance", dungeon = name, learned = learned }
    end
  end
  -- tabs only for zones with spots
  for i = #out, 1, -1 do
    if #out[i].points == 0 then
      table.remove(out, i)
    end
  end
  table.sort(out, function(a, b)
    if #a.points ~= #b.points then
      return #a.points > #b.points
    end
    return a.mapID < b.mapID
  end)
  return out
end

local function PlayerMap()
  if not (C_Map and C_Map.GetBestMapForUnit) then
    return nil
  end
  local S = Seekwell.Secret
  local v = S and S.Get and S.Get(C_Map.GetBestMapForUnit, "player")
  return tonumber(v)
end

local function CurrentZone()
  return zoneIdx and zones[zoneIdx] or nil
end

function B.Zones()
  return zones, zoneIdx
end

function B.Preview()
  return preview
end

local function PaintMap()
  if not preview then
    return
  end
  local z = CurrentZone()
  if z then
    preview:Show(z.mapID, z.points)
  else
    preview:Show(nil, {})
  end
  for i, b in ipairs(zoneBtns) do
    local zz = zones[i]
    if zz and i <= MAX_ZONE_BTNS then
      b.text:SetText(zz.name .. " (" .. #zz.points .. ")")
      local on = i == zoneIdx
      b.text:SetTextColor(on and 1 or 0.7, on and 0.82 or 0.7, on and 0 or 0.7)
      b.line:SetShown(on)
      b:SetWidth(math.min(200, (b.text.GetStringWidth and tonumber(b.text:GetStringWidth()) or 100) + 14))
      b:Show()
    else
      b:Hide()
    end
  end
  local nSpots = 0
  for _, zz in ipairs(zones) do
    nSpots = nSpots + #zz.points
  end
  if #zones == 0 then
    zoneLabel:SetText("No known zone yet \226\128\148 loot or meet it once to learn where it lives.")
  else
    zoneLabel:SetText((#zones > MAX_ZONE_BTNS and ("+" .. (#zones - MAX_ZONE_BTNS) .. " more \194\183 ") or "")
      .. string.format("%d spot(s) in %d zone(s)", nSpots, #zones))
  end
end

--- Select a zone of the selection (index into B.Zones()).
function B.SelectZone(i)
  i = tonumber(i)
  if i and zones[i] then
    zoneIdx = i
    Safe("map", PaintMap)()
  end
end

local function DRow(i)
  local r = drows[i]
  if r then
    return r
  end
  r = CreateFrame("Button", nil, dChild)
  r.hl = r:CreateTexture(nil, "BACKGROUND")
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(1, 1, 1, 0.06)
  r.hl:Hide()
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(24, 24)
  r.icon:SetPoint("TOPLEFT", 0, -4)
  r.l1 = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.l1:SetJustifyH("LEFT")
  r.l1:SetWordWrap(false)
  r.l2 = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.l2:SetJustifyH("LEFT")
  r.l2:SetWordWrap(false)
  r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
  r.btn:SetSize(62, 22)
  r.btn:SetPoint("RIGHT", -76, 0)
  r.btn:SetText("On map")
  r.btn:SetScript("OnClick", Safe("onmap", function()
    if r.npc and Seekwell.Map and Seekwell.Map.Hunt then
      Seekwell.Map.Hunt("mob", r.npc)
    end
  end))
  r.wp = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
  r.wp:SetSize(72, 22)
  r.wp:SetPoint("RIGHT", 0, 0)
  r.wp:SetText("Waypoint")
  r.wp:SetScript("OnClick", Safe("waypoint", function()
    if r.npc then
      IV().WaypointTo(r.npc)
    elseif r.dungeon and DJ() then
      local m, x, y, label = DJ().Entrance(r.dungeon)
      if m and Seekwell.Waypoint then
        Seekwell.Waypoint.Set(m, x, y, label)
      end
    end
  end))
  r.star = CreateFrame("Button", nil, r)
  r.star:SetSize(18, 18)
  r.star:SetPoint("RIGHT", -22, 0)
  r.star.tex = r.star:CreateTexture(nil, "ARTWORK")
  r.star.tex:SetAllPoints()
  r.star.tex:SetTexture(STAR_ICON)
  r.star:SetScript("OnClick", Safe("dstar", function()
    if r.item then
      Seekwell.Wish.Toggle(r.item)
      AfterWish()
      RenderDetail()
      Render()
    end
  end))
  r.own = r:CreateTexture(nil, "OVERLAY")
  r.own:SetSize(16, 16)
  r.own:SetPoint("RIGHT", -2, 0)
  r.own:SetTexture(OWN_ICON)
  r:SetScript("OnClick", Safe("drow", function()
    if r.boss then
      B.SelectBoss(r.boss)
    elseif r.npc then
      B.Select("mob", r.npc)
    elseif r.item then
      B.Select("item", r.item)
    elseif r.dungeon and DJ() then
      local e = DJ().Get(r.dungeon)
      if e then
        B.Select("dungeon", e.index)
      end
    end
  end))
  r:SetScript("OnEnter", function(self)
    if self.npc or self.item or self.dungeon or self.boss then
      self.hl:Show()
    end
    if self.item and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if not pcall(GameTooltip.SetItemByID, GameTooltip, self.item) then
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.item)
      end
      GameTooltip:Show()
    end
  end)
  r:SetScript("OnLeave", function(self)
    self.hl:Hide()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  drows[i] = r
  return r
end

--- One detail row: kind "mob" (buttons), "item" (icon, star, tick) or "text".
local function FillDRow(i, y, width, kind, data)
  local r = DRow(i)
  r:SetSize(width, DROW_H)
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", dChild, "TOPLEFT", 0, y)
  r.npc, r.item, r.dungeon, r.boss = false, false, false, false -- false, not nil: explicit "none"
  local textX, rightPad = 0, 0
  r.icon:Hide()
  r.btn:Hide()
  r.wp:Hide()
  r.star:Hide()
  r.own:Hide()
  if kind == "mob" then
    r.npc = data.npc
    r.btn:Show()
    r.wp:Show()
    r.btn:SetEnabled(data.spots > 0)
    r.wp:SetEnabled(data.spots > 0)
    rightPad = 156
  elseif kind == "item" then
    r.item = data.id
    r.icon:SetTexture(data.icon or UNKNOWN_ICON)
    r.icon:Show()
    r.star:Show()
    r.star.tex:SetAlpha(Seekwell.Wish.Has(data.id) and 1 or 0.25)
    r.own:SetShown(Seekwell.Wish.IsOwned and Seekwell.Wish.IsOwned(data.id) or false)
    textX, rightPad = 30, 48
  elseif kind == "dungeon" then
    r.dungeon = data.dungeon
    r.wp:Show()
    r.wp:SetEnabled(data.entrance and true or false)
    rightPad = 80
  elseif kind == "boss" then
    r.boss = data.boss
  end
  r.l1:ClearAllPoints()
  r.l1:SetPoint("TOPLEFT", textX, -3)
  r.l1:SetWidth(math.max(60, width - textX - rightPad - 4))
  r.l2:ClearAllPoints()
  r.l2:SetPoint("TOPLEFT", textX, -18)
  r.l2:SetWidth(math.max(60, width - textX - rightPad - 4))
  r.l1:SetText(data.l1 or "")
  r.l1:SetTextColor(data.r or 1, data.g or 1, data.b or 1)
  r.l2:SetText(data.l2 or "")
  r.l2:SetTextColor(data.r2 or 0.6, data.g2 or 0.6, data.b2 or 0.6)
  r:Show()
  return r
end

local function DetailRowsItem(id, width)
  local R = Seekwell.Registry
  local n, y = 0, 0
  local srcs = B.OrderSources(R.ItemSources(id, 200))
  local nDrop = 0
  for i = 1, math.min(DETAIL_MAX, #srcs) do
    local s = srcs[i]
    if s.origin == "dj" then
      -- listed below with the other Dungeon Journal sources
    else
    nDrop = nDrop + 1
    local d = R.NpcDrops and R.NpcDrops(s.npc) or nil
    local zs, spots, src = IV().Where(s.npc)
    local l2, r2, g2, b2
    if #zs > 0 then
      l2 = "seen in: " .. table.concat(zs, ", ", 1, math.min(3, #zs)) .. (#zs > 3 and ", ..." or "")
        .. " \194\183 " .. spots .. " known spot(s)" .. (src and (" \194\183 " .. src) or "")
      r2, g2, b2 = 0.55, 0.8, 0.55
    else
      l2 = "location not known yet \226\128\148 loot this mob once to learn it"
    end
    local classic = s.origin == "classic"
    n = n + 1
    FillDRow(n, y, width, "mob", { npc = s.npc, spots = spots,
      l1 = (R.NpcName(s.npc) or ("npc " .. s.npc)) .. IV().LevelText(d) .. "   " .. R.FormatPct(s.p) .. "  \194\183 " .. R.OriginLabel(s),
      r = classic and 0.75 or 0.85, g = classic and 0.75 or 0.95, b = classic and 0.75 or 1,
      l2 = l2, r2 = r2, g2 = g2, b2 = b2 })
    y = y - DROW_H
    end
  end
  local S = Seekwell.Sources
  local lst = S and S.ForItem and S.ForItem(id) or {}
  local nv, nq, nj = 0, 0, 0
  for _, s in ipairs(lst) do
    if n >= DETAIL_MAX then
      break
    end
    n = n + 1
    if s.kind == "dungeon" or s.kind == "djquest" then
      nj = nj + 1
      local m = DJ() and DJ().Entrance(s.dungeon)
      FillDRow(n, y, width, "dungeon", { dungeon = s.dungeon, entrance = m,
        l1 = (s.kind == "dungeon" and "Dungeon: " or "Dungeon quest: ") .. (s.label or "?") .. "   " .. R.FormatPct(nil),
        l2 = "Dungeon Journal" .. (m and (" \194\183 entrance in " .. (IV().MapName(m) or ("map " .. m))) or " \194\183 entrance not known"),
        r = 0.95, g = 0.75, b = 0.35 })
    elseif s.kind == "vendor" then
      nv = nv + 1
      FillDRow(n, y, width, "text", { l1 = "Vendor: " .. (s.name or ("npc " .. tostring(s.npc))),
        l2 = IV().MapName(s.mapID) or "unknown zone", r = 0.9, g = 0.85, b = 0.5 })
    else
      nq = nq + 1
      FillDRow(n, y, width, "text", { l1 = "Quest reward: " .. (s.name or ("quest " .. tostring(s.questID))),
        l2 = s.giverName and ("from " .. s.giverName) or "", r = 0.9, g = 0.85, b = 0.5 })
    end
    y = y - DROW_H
  end
  local head = nDrop > 0 and string.format("Drops from (%d)", nDrop) or "Drops from: no mob is known to drop this item"
  if nj > 0 then
    head = head .. string.format(" \194\183 %d Dungeon Journal", nj)
  end
  if nv > 0 then
    head = head .. string.format(" \194\183 %d vendor(s)", nv)
  end
  if nq > 0 then
    head = head .. string.format(" \194\183 %d quest(s)", nq)
  end
  return n, y, head
end

local function DetailRowsMob(id, width)
  local R = Seekwell.Registry
  local d = R.NpcDrops(id) or {}
  local lst = d.rows or {}
  local n, y = 0, 0
  for i = 1, math.min(DETAIL_MAX, #lst) do
    local row = lst[i]
    if row and row.id then
      local name, quality, icon = IV().ItemName(row.id)
      local rr, gg, bb = IV().QualityRGB(quality)
      n = n + 1
      FillDRow(n, y, width, "item", { id = row.id, icon = icon, l1 = name or ("item " .. row.id), r = rr, g = gg, b = bb,
        l2 = R.FormatPct(row.p) .. " \194\183 " .. R.OriginLabel(row) .. (row.quest and " \194\183 quest item" or "") })
      y = y - DROW_H
    end
  end
  local head = #lst > 0 and string.format("Drops (%d)", #lst) or "Drops: no drop known for this mob"
  if #lst > DETAIL_MAX then
    head = head .. string.format(" \194\183 the best %d are shown", DETAIL_MAX)
  end
  return n, y, head
end

local function DetailRowsDungeon(id, width)
  local fe = FdbDungeon(id)
  if fe then
    FillDRow(1, 0, width, "text", { l1 = ENTRANCE_ONLY, l2 = "ForeverDB data \194\183 " .. (IV().MapName(fe.mapID) or ("map " .. tostring(fe.mapID))),
      r = 0.9, g = 0.85, b = 0.5 })
    return 1, -DROW_H, "Entrance only \194\183 ForeverDB data"
  end
  local p = DJ() and DJ().Page(id)
  local n, y = 0, 0
  if not p then
    return n, y, "Dungeon Journal not loaded"
  end
  local function Item(it, extra)
    local name, quality, icon = IV().ItemName(it.id)
    local rr, gg, bb = IV().QualityRGB(quality or it.quality)
    n = n + 1
    FillDRow(n, y, width, "item", { id = it.id, icon = icon, l1 = "   " .. (name or it.name or ("item " .. it.id)) .. (IsForever("item", it.id) and FTAG or ""),
      r = rr, g = gg, b = bb, l2 = "   " .. (extra or "") })
    y = y - DROW_H
  end
  for _, b in ipairs(p.bosses) do
    if n >= DETAIL_MAX then
      break
    end
    n = n + 1
    local open = djBoss == b.index
    FillDRow(n, y, width, "boss", { boss = b.index, l1 = (open and "[-] " or "[+] ") .. b.name .. (b.trash and " (trash)" or ""),
      l2 = #b.loot .. " item(s) \194\183 click to " .. (open and "hide" or "show") .. " loot", r = 1, g = 0.82, b = 0 })
    y = y - DROW_H
    if open then
      for _, it in ipairs(b.loot) do
        Item(it, (it.slot or "") .. " \194\183 chance unknown (" .. (Seekwell.L and Seekwell.L.UNKNOWN or "-") .. ")")
      end
    end
  end
  for _, q in ipairs(p.quests) do
    if n >= DETAIL_MAX then
      break
    end
    n = n + 1
    FillDRow(n, y, width, "text", { l1 = "Quest: " .. q.name .. (q.level and (" (" .. tostring(q.level) .. ")") or ""),
      l2 = #q.rewards > 0 and (#q.rewards .. " reward item(s)") or "no reward item", r = 0.9, g = 0.85, b = 0.5 })
    y = y - DROW_H
    for _, it in ipairs(q.rewards) do
      Item(it, "quest reward")
    end
  end
  return n, y, string.format("Bosses (%d) \194\183 quests (%d) \194\183 Dungeon Journal", #p.bosses, #p.quests)
end

local function HeaderDungeon(id)
  local D = DJ()
  local fe = FdbDungeon(id)
  local e = (not fe) and D and D.Get(id) or nil
  hName:SetText((e and e.name or "dungeon") .. (e and e.level and (" (" .. e.level .. ")") or "") .. "  |cffe6b422Forever|r")
  hName:SetTextColor(0.95, 0.55, 1)
  hIcon:SetTexture(DUNGEON_ICON)
  hWish:Hide()
  hQty:Hide()
  hQtyLabel:Hide()
  hLink:Hide()
  hOwn:Hide()
  if hDJ then
    hDJ:SetShown((not fe) and D and D.Opener() ~= nil or false)
  end
  if fe then
    hName:SetText(fe.name .. "  |cffe6b422Forever|r")
    hInfo:SetText("entrance: " .. (IV().MapName(fe.mapID) or ("map " .. tostring(fe.mapID))) .. " \194\183 " .. ENTRANCE_ONLY)
    return
  end
  local m, learned
  if D and e then
    local _x, _y, _l
    m, _x, _y, _l, learned = D.Entrance(e.name)
  end
  local txt
  if m then
    txt = "entrance: " .. (IV().MapName(m) or ("map " .. m)) .. (learned and " (learned)" or "")
  else
    txt = "entrance not placed" .. ((e and e.location) and (" \194\183 " .. e.location) or "")
  end
  hInfo:SetText(txt)
end

local function HeaderItem(id)
  local W = Seekwell.Wish
  local name, quality, icon = IV().ItemName(id)
  hName:SetText(name or ("item " .. id))
  hName:SetTextColor(IV().QualityRGB(quality))
  hIcon:SetTexture(icon or UNKNOWN_ICON)
  local on = W.Has(id)
  hWish:SetText(on and "Remove from wishlist" or "Add to wishlist")
  Fit(hWish, 150)
  hWish:Show()
  hQty:SetShown(on)
  hQtyLabel:SetShown(on)
  if on then
    if not (hQty.HasFocus and hQty:HasFocus()) then
      hQty:SetText(tostring(W.Qty(id)))
    end
    hQtyLabel:SetText(string.format("have %d, want", W.Have(id) or 0))
  end
  hLink:Show()
  hOwn:SetShown(W.IsOwned and W.IsOwned(id) or false)
  local srcs = Seekwell.Registry.ItemSources(id, 200)
  hInfo:SetText(#srcs > 0 and ("best source: " .. SourceText(srcs)) or "no known drop source")
  if IsForever("item", id) then
    hName:SetText(hName:GetText() .. "  |cffe6b422Forever|r")
  end
end

local function HeaderMob(id)
  local R = Seekwell.Registry
  local d = R.NpcDrops(id) or {}
  hName:SetText((R.NpcName(id) or d.name or ("npc " .. id)) .. IV().LevelText(d))
  hName:SetTextColor(1, 0.82, 0)
  if IsForever("mob", id) then
    hName:SetText(hName:GetText() .. "  |cffe6b422Forever|r")
  end
  hIcon:SetTexture(MOB_ICON)
  hWish:Hide()
  hQty:Hide()
  hQtyLabel:Hide()
  hLink:Hide()
  hOwn:Hide()
  local parts = { "learned kills: " .. tostring(d.learnedKills or 0) }
  if d.foreverKills then
    parts[#parts + 1] = "Forever kills: " .. tostring(d.foreverKills)
  end
  local zs, spots, src = IV().Where(id)
  if #zs > 0 then
    parts[#parts + 1] = spots .. " known spot(s)" .. (src and (" (" .. src .. ")") or "")
  else
    parts[#parts + 1] = "location not known"
  end
  hInfo:SetText(table.concat(parts, " \194\183 "))
end

RenderDetail = function()
  if not Rt then
    return
  end
  if not sel then
    body:Hide()
    hint:Show()
    zones, zoneIdx = {}, nil
    return
  end
  hint:Hide()
  body:Show()
  hBack:SetEnabled(#stack > 1)
  if hDJ then
    hDJ:Hide()
  end
  if sel.kind == "item" then
    HeaderItem(sel.id)
  elseif sel.kind == "dungeon" then
    HeaderDungeon(sel.id)
  else
    HeaderMob(sel.id)
  end
  -- zones + map preview (only rebuilt here, on selection change)
  local keep = CurrentZone()
  zones = B.ZonesFor(sel.kind, sel.id)
  local idx
  if keep then
    for i, z in ipairs(zones) do
      if z.mapID == keep.mapID then
        idx = i
      end
    end
  end
  if not idx and #zones > 0 then
    local pm = PlayerMap()
    for i, z in ipairs(zones) do
      if z.mapID == pm and #z.points > 0 then
        idx = i
      end
    end
    idx = idx or 1
  end
  zoneIdx = idx
  local anySpot = false
  for _, z in ipairs(zones) do
    if #z.points > 0 then
      anySpot = true
    end
  end
  bWp:SetEnabled(anySpot)
  bMap:SetEnabled(#zones > 0)
  PaintMap()
  local width = (dChild.width or 480)
  local n, y, head
  if sel.kind == "item" then
    n, y, head = DetailRowsItem(sel.id, width)
  elseif sel.kind == "dungeon" then
    n, y, head = DetailRowsDungeon(sel.id, width)
  else
    n, y, head = DetailRowsMob(sel.id, width)
  end
  dHead:SetText(head)
  if dCover then
    dCover:SetText(B.CoverageText(sel.kind, sel.id))
  end
  if bLocFirst then
    bLocFirst:SetShown(sel.kind == "item")
    bLocFirst:SetText("Located first: " .. (BS().locatedFirst == false and "off" or "on"))
  end
  for i = n + 1, #drows do
    drows[i].npc, drows[i].item, drows[i].dungeon, drows[i].boss = false, false, false, false
    drows[i]:Hide()
  end
  dChild:SetHeight(math.max(20, -y + 4))
  if dScroll.SetVerticalScroll then
    dScroll:SetVerticalScroll(0)
  end
end

function B.RenderDetail()
  Safe("detail", RenderDetail)()
end

local function NearestOfSelection()
  if not sel then
    return nil
  end
  if sel.kind == "mob" then
    return sel.id
  elseif sel.kind == "dungeon" then
    return nil
  end
  local srcs = Seekwell.Registry.ItemSources(sel.id, 200)
  for i = 1, math.min(MAX_SRC_MOBS, #srcs) do
    local _, spots = IV().Where(srcs[i].npc)
    if spots > 0 then
      return srcs[i].npc
    end
  end
  return nil
end

function B.OpenWorldMap()
  if InCombatLockdown and InCombatLockdown() then
    Print("the world map can be opened from here only out of combat")
    return false
  end
  local wmf = rawget(_G, "WorldMapFrame")
  local z = CurrentZone()
  local shown = wmf and wmf.IsShown and wmf:IsShown()
  if not shown then
    local toggle = rawget(_G, "ToggleWorldMap")
    if type(toggle) == "function" then
      pcall(toggle)
    elseif wmf and wmf.Show then
      pcall(wmf.Show, wmf)
    end
  end
  if wmf and wmf.SetMapID and z then
    pcall(wmf.SetMapID, wmf, z.mapID)
  end
  -- the browser sits above the world map (DIALOG strata): get out of the way
  if Seekwell.Window and Seekwell.Window.Hide then
    Seekwell.Window.Hide()
  end
  return true
end

-- build ------------------------------------------------------------------------------------------

local function TabButton(parent, id, x, w)
  local t = CreateFrame("Button", nil, parent)
  t:SetSize(w, 24)
  t:SetPoint("TOPLEFT", x, -28)
  t.bg = t:CreateTexture(nil, "BACKGROUND")
  t.bg:SetAllPoints()
  t.bg:SetColorTexture(1, 0.82, 0, 0.12)
  t.line = t:CreateTexture(nil, "ARTWORK")
  t.line:SetPoint("BOTTOMLEFT", 0, 0)
  t.line:SetPoint("BOTTOMRIGHT", 0, 0)
  t.line:SetHeight(2)
  t.line:SetColorTexture(1, 0.82, 0, 1)
  local base = t:CreateTexture(nil, "BACKGROUND", nil, -1)
  base:SetPoint("BOTTOMLEFT", 0, 0)
  base:SetPoint("BOTTOMRIGHT", 0, 0)
  base:SetHeight(1)
  base:SetColorTexture(1, 1, 1, 0.15)
  t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t.text:SetPoint("CENTER", 0, 1)
  t:SetScript("OnClick", Safe("tab", function()
    B.SetMode(id)
  end))
  tabs[id] = t
  return t
end

local function EditBox(parent, w)
  local ok, eb = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
  if not ok or not eb then
    eb = CreateFrame("EditBox", nil, parent)
  end
  eb:SetSize(w, 20)
  eb:SetAutoFocus(false)
  return eb
end

local function ListTop()
  return 82 + (BS().filtersOpen and 74 or 0) + 20
end

--- Reflow to the section size (called by the window on mode change).
local function Layout(s, w, h)
  sizeW, sizeH = tonumber(w) or sizeW, tonumber(h) or sizeH
  if not L then
    return
  end
  L:SetSize(LEFT_W, sizeH)
  local rw = math.max(200, sizeW - LEFT_W - GAP)
  Rt:SetSize(rw, sizeH)
  fp:SetShown(BS().filtersOpen and true or false)
  local top = ListTop()
  note:ClearAllPoints()
  note:SetPoint("TOPLEFT", L, "TOPLEFT", 4, -(top - 18))
  local lh = math.max(ROW_H, sizeH - top - 4)
  list:ClearAllPoints()
  list:SetPoint("TOPLEFT", L, "TOPLEFT", 0, -top)
  list:SetSize(LEFT_W - 18, lh)
  visible = math.max(1, math.min(POOL, math.floor(lh / ROW_H)))
  for i = 1, POOL do
    rows[i]:ClearAllPoints()
    rows[i]:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_H)
  end
  slider:ClearAllPoints()
  slider:SetPoint("TOPLEFT", list, "TOPRIGHT", 2, -2)
  slider:SetSize(14, lh - 4)
  -- right pane
  local pw = math.min(460, rw - 8)
  local ph = math.floor(pw * 300 / 460)
  preview:SetSize(pw, ph)
  preview.frame:ClearAllPoints()
  preview.frame:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -122)
  dHead:ClearAllPoints()
  dHead:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(122 + ph + 8))
  dCover:ClearAllPoints()
  dCover:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(122 + ph + 26))
  dCover:SetWidth(rw - 20)
  bLocFirst:ClearAllPoints()
  bLocFirst:SetPoint("TOPRIGHT", body, "TOPRIGHT", -24, -(122 + ph + 4))
  local dTop = 122 + ph + 44
  dScroll:ClearAllPoints()
  dScroll:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -dTop)
  dScroll:SetSize(rw - 26, math.max(40, sizeH - dTop - 4))
  dChild:SetWidth(rw - 26)
  dChild.width = rw - 30
  hint:SetWidth(rw - 20)
  hInfo:SetWidth(rw - 50)
  hName:SetWidth(rw - 140)
  zoneLabel:SetWidth(rw - 10)
end
B.Layout = Layout

local function OnEvent(_, event)
  if event ~= "GET_ITEM_INFO_RECEIVED" or not (sec and sec:IsShown()) or infoQueued then
    return
  end
  infoQueued = true
  local go = Safe("rerun", function()
    infoQueued = false
    if awaitInfo then
      awaitInfo = false -- one repeat per search
      Run(true)
    else
      Render()
    end
    RenderDetail()
  end)
  if C_Timer and C_Timer.After then
    C_Timer.After(0.5, go)
  else
    go()
  end
end

local function BuildLeft(s, H)
  L = CreateFrame("Frame", nil, s)
  L:SetPoint("TOPLEFT", 0, 0)
  local eb = EditBox(L, LEFT_W - 96)
  eb:SetPoint("TOPLEFT", 8, -2)
  eb:SetMaxLetters(60)
  eb:SetScript("OnTextChanged", Safe("typed", function(self, userInput)
    if userInput then
      B.SetQuery(self:GetText(), true)
    end
  end))
  eb:SetScript("OnEnterPressed", Safe("enter", function(self)
    query = tostring(self:GetText() or "")
    Run(false)
    self:ClearFocus()
  end))
  eb:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  box = eb
  local sb = H.Button(L, "Search", LEFT_W - 82, 0, 76, function()
    query = tostring(box:GetText() or "")
    Run(false)
  end)
  sb:ClearAllPoints()
  sb:SetPoint("TOPLEFT", L, "TOPLEFT", LEFT_W - 82, 0)
  local tw = math.floor((LEFT_W - 12) / 4)
  TabButton(L, "all", 0, tw)
  TabButton(L, "items", tw + 4, tw)
  TabButton(L, "mobs", 2 * (tw + 4), tw)
  TabButton(L, "dungeons", 3 * (tw + 4), tw)
  filterBtn = CreateFrame("Button", nil, L)
  filterBtn:SetSize(200, 18)
  filterBtn:SetPoint("TOPLEFT", 2, -58)
  filterBtn.text = filterBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  filterBtn.text:SetPoint("LEFT", 2, 0)
  filterBtn:SetScript("OnClick", Safe("filters", function()
    local b = BS()
    b.filtersOpen = not b.filtersOpen
    Layout(sec, sizeW, sizeH)
    Render()
  end))
  fp = CreateFrame("Frame", nil, L)
  fp:SetPoint("TOPLEFT", 0, -78)
  fp:SetSize(LEFT_W, 74)
  local c1 = H.Check(fp, "Only with known location", 0, function()
    return BS().onlyLocated
  end, function(on)
    BS().onlyLocated = on
    Run(false)
  end)
  c1:ClearAllPoints()
  c1:SetPoint("TOPLEFT", fp, "TOPLEFT", 2, 0)
  local c2 = H.Check(fp, "Only wishlist", 0, function()
    return BS().onlyWish
  end, function(on)
    BS().onlyWish = on
    Run(false)
  end)
  c2:ClearAllPoints()
  c2:SetPoint("TOPLEFT", fp, "TOPLEFT", 200, 0)
  local c3 = H.Check(fp, "Pin the selection on the map", 0, function()
    return BS().autoPin ~= false
  end, function(on)
    BS().autoPin = on and true or false
    if on and sel then
      AutoPin(sel.kind, sel.id)
    end
  end)
  c3:ClearAllPoints()
  c3:SetPoint("TOPLEFT", fp, "TOPLEFT", 2, -24)
  local sl = H.Slider(fp, "Min drop %", 0, 0, 50, function()
    return BS().minPct or 0
  end, function(v)
    BS().minPct = v
    Debounce()
  end)
  local c4 = H.Check(fp, "Forever content only", 0, function()
    return BS().foreverOnly
  end, function(on)
    BS().foreverOnly = on and true or false
    Run(false)
  end)
  c4:ClearAllPoints()
  c4:SetPoint("TOPLEFT", fp, "TOPLEFT", 2, -48)
  sl:ClearAllPoints()
  sl:SetPoint("TOPLEFT", fp, "TOPLEFT", 206, -40)
  sl:SetWidth(150)
  fp:Hide()
  note = L:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetWidth(LEFT_W - 8)
  note:SetJustifyH("LEFT")
  note:SetWordWrap(false)
  note:SetTextColor(0.9, 0.85, 0.55)
  list = CreateFrame("Frame", nil, L)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", Safe("wheel", function(_, delta)
    B.SetOffset(offset - (tonumber(delta) or 0) * 3)
  end))
  for i = 1, POOL do
    local r = MakeRow(list, i, LEFT_W - 20)
    r:SetScript("OnClick", Safe("row", function(self)
      if self.entry then
        B.Select(self.entry.kind, self.entry.id, true)
      end
    end))
    r:Hide()
    rows[i] = r
  end
  slider = CreateFrame("Slider", nil, L)
  if slider.SetOrientation then
    slider:SetOrientation("VERTICAL")
  end
  local track = slider:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(0, 0, 0, 0.4)
  if slider.SetThumbTexture then
    slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  end
  slider:SetMinMaxValues(0, 0)
  slider:SetValueStep(1)
  if slider.SetObeyStepOnDrag then
    slider:SetObeyStepOnDrag(true)
  end
  slider:EnableMouseWheel(true)
  slider:SetScript("OnMouseWheel", Safe("swheel", function(_, delta)
    B.SetOffset(offset - (tonumber(delta) or 0) * 3)
  end))
  slider:SetScript("OnValueChanged", Safe("slider", function(_, v)
    if not settingSlider then
      B.SetOffset(math.floor((tonumber(v) or 0) + 0.5))
    end
  end))
  slider:Hide()
end

local function CommitQty(self)
  local v = tonumber(self:GetText())
  if sel and sel.kind == "item" and v and v >= 1 and Seekwell.Wish.Has(sel.id) then
    Seekwell.Wish.SetQty(sel.id, v)
    AfterWish()
    RenderDetail()
    Render()
  end
end

local function BuildRight(s, H)
  Rt = CreateFrame("Frame", nil, s)
  Rt:SetPoint("TOPLEFT", s, "TOPLEFT", LEFT_W + GAP, 0)
  local div = s:CreateTexture(nil, "ARTWORK")
  div:SetColorTexture(1, 1, 1, 0.12)
  div:SetWidth(1)
  div:SetPoint("TOPLEFT", s, "TOPLEFT", LEFT_W + GAP / 2, 0)
  div:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", LEFT_W + GAP / 2, 0)
  hint = Rt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  hint:SetPoint("TOPLEFT", 10, -40)
  hint:SetJustifyH("LEFT")
  hint:SetTextColor(0.65, 0.65, 0.65)
  hint:SetText("Select an item or a mob on the left.\n\nHere you will see where it drops, its known spots on a map of the zone, "
    .. "and buttons to pin it on the world map and minimap or set a waypoint.")
  body = CreateFrame("Frame", nil, Rt)
  body:SetAllPoints()
  hIcon = body:CreateTexture(nil, "ARTWORK")
  hIcon:SetSize(34, 34)
  hIcon:SetPoint("TOPLEFT", 0, 0)
  hName = body:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  hName:SetPoint("TOPLEFT", hIcon, "TOPRIGHT", 8, -1)
  hName:SetJustifyH("LEFT")
  hName:SetWordWrap(false)
  hOwn = body:CreateTexture(nil, "OVERLAY")
  hOwn:SetSize(16, 16)
  hOwn:SetPoint("LEFT", hName, "RIGHT", 6, 0)
  hOwn:SetTexture(OWN_ICON)
  hOwn:Hide()
  hInfo = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hInfo:SetPoint("TOPLEFT", hIcon, "TOPRIGHT", 8, -20)
  hInfo:SetJustifyH("LEFT")
  hInfo:SetWordWrap(false)
  hInfo:SetTextColor(0.7, 0.7, 0.7)
  hBack = H.Button(body, "< Back", 0, 0, 64, function()
    B.Back()
  end)
  hBack:ClearAllPoints()
  hBack:SetPoint("TOPRIGHT", body, "TOPRIGHT", -4, 0)
  hWish = H.Button(body, "Add to wishlist", 0, -42, 150, function()
    if sel and sel.kind == "item" then
      Seekwell.Wish.Toggle(sel.id)
      AfterWish()
      RenderDetail()
      Render()
    end
  end)
  hQtyLabel = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hQtyLabel:SetPoint("LEFT", hWish, "RIGHT", 8, 0)
  hQty = EditBox(body, 44)
  hQty:SetPoint("LEFT", hQtyLabel, "RIGHT", 6, 0)
  hQty:SetNumeric(true)
  hQty:SetMaxLetters(4)
  hQty:SetScript("OnEnterPressed", Safe("qty", function(self)
    CommitQty(self)
    self:ClearFocus()
  end))
  hQty:SetScript("OnEditFocusLost", Safe("qtyfocus", CommitQty))
  hQty:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  hDJ = H.Button(body, "Open in DungeonJournal", 0, -42, 180, function()
    local e = sel and sel.kind == "dungeon" and DJ() and DJ().Get(sel.id)
    if e and not DJ().Open(e.name, djBoss) then
      Print("ForeverDungeonJournal could not open that page (not loaded, or in combat)")
    elseif e and Seekwell.Window and Seekwell.Window.Hide then
      Seekwell.Window.Hide()
    end
  end)
  hDJ:Hide()
  hLink = H.Button(body, "Link", 312, -42, 60, function()
    if sel and sel.kind == "item" then
      local TP = Seekwell.TargetPanel
      local _, link = TP and TP.ItemInfo and TP.ItemInfo(sel.id)
      link = link or ("item:" .. sel.id)
      local active = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
      if active and ChatEdit_InsertLink then
        ChatEdit_InsertLink(link)
      elseif ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, link)
      end
    end
  end)
  bMap = H.Button(body, "Show on map", 0, -70, 104, function()
    if sel and Seekwell.Map and Seekwell.Map.Hunt then
      Seekwell.Map.Hunt(sel.kind, DungeonArg(sel.kind, sel.id))
    end
  end)
  bClear = H.Button(body, "Clear map", 108, -70, 84, function()
    if Seekwell.Map and Seekwell.Map.Clear then
      Seekwell.Map.Clear()
    end
  end)
  bWorld = H.Button(body, "Open world map", 196, -70, 124, function()
    B.OpenWorldMap()
  end)
  bWp = H.Button(body, "Waypoint to nearest", 324, -70, 150, function()
    local npc = NearestOfSelection()
    local z = CurrentZone()
    local ep
    for _, pt in ipairs(z and z.points or {}) do
      if pt.src == "entrance" then
        ep = ep or pt
      end
    end
    if (not npc or (sel and sel.kind == "dungeon")) and ep and z then
      Seekwell.Waypoint.Set(z.mapID, ep.x, ep.y, ep.dungeon and (ep.dungeon .. " Entrance") or ep.label)
    elseif npc then
      IV().WaypointTo(npc)
    else
      Print("no known spot for this selection yet")
    end
  end)
  -- one row, each button as wide as its label needs
  local prev
  for _, b in ipairs({ bMap, bClear, bWorld, bWp }) do
    Fit(b, 80)
    if prev then
      b:ClearAllPoints()
      b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    end
    prev = b
  end
  Fit(hBack, 64)
  Fit(hWish, 150)
  Fit(hLink, 60)
  hLink:ClearAllPoints()
  hLink:SetPoint("LEFT", hQty, "RIGHT", 10, 0)
  for i = 1, MAX_ZONE_BTNS do
    local b = CreateFrame("Button", nil, body)
    b:SetSize(100, 20)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER", 0, 1)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetPoint("BOTTOMLEFT", 0, 0)
    b.line:SetPoint("BOTTOMRIGHT", 0, 0)
    b.line:SetHeight(2)
    b.line:SetColorTexture(1, 0.82, 0, 1)
    b:SetScript("OnClick", Safe("zone", function()
      B.SelectZone(i)
    end))
    if i == 1 then
      b:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -98)
    else
      b:SetPoint("LEFT", zoneBtns[i - 1], "RIGHT", 4, 0)
    end
    b:Hide()
    zoneBtns[i] = b
  end
  zoneLabel = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  zoneLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -102)
  zoneLabel:SetJustifyH("RIGHT")
  zoneLabel:SetTextColor(0.6, 0.6, 0.6)
  preview = Seekwell.MapPreview.Create(body, 460, 300)
  dHead = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  dHead:SetJustifyH("LEFT")
  dCover = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dCover:SetJustifyH("LEFT")
  dCover:SetWordWrap(false)
  dCover:SetTextColor(0.55, 0.8, 1)
  bLocFirst = H.Button(body, "Located first: on", 0, 0, 120, function()
    BS().locatedFirst = BS().locatedFirst == false
    RenderDetail()
  end)
  Fit(bLocFirst, 120)
  local okS, sf = pcall(CreateFrame, "ScrollFrame", nil, body, "UIPanelScrollFrameTemplate")
  if not okS or not sf then
    sf = CreateFrame("ScrollFrame", nil, body)
  end
  sf:EnableMouseWheel(true)
  if not (H.Obj and H.Obj(sf.ScrollBar)) then
    sf:SetScript("OnMouseWheel", function(self, delta)
      local max = self:GetVerticalScrollRange() or 0
      self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * 40)))
    end)
  end
  dScroll = sf
  dChild = CreateFrame("Frame", nil, sf)
  dChild:SetSize(480, 20)
  sf:SetScrollChild(dChild)
  body:Hide()
end

local function Build(s, H)
  sec = s
  sizeW, sizeH = H.width or sizeW, H.height or sizeH
  BuildLeft(s, H)
  BuildRight(s, H)
  Layout(s, sizeW, sizeH)
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  ev:SetScript("OnEvent", Safe("event", OnEvent))
  s:SetScript("OnShow", Safe("show", function()
    Render()
    RenderDetail()
  end))
  Safe("run", Run)(false)
  return sizeH
end

if Seekwell.Window and Seekwell.Window.RegisterSection then
  Seekwell.Window.RegisterSection({ id = "search", label = "Search", build = Build, layout = Layout, fixed = true,
    mode = "browser", before = "wishlist" })
end

if Seekwell.RegisterStart then
  Seekwell.RegisterStart("browser.fdbready", function()
    if Seekwell.FDB and Seekwell.FDB.OnReady then
      Seekwell.FDB.OnReady(function()
        if sec and sec:IsShown() and Trim(query) ~= "" then
          Run(true) -- an index finished: repeat the current search without resetting the scroll
        end
      end)
    end
  end)
end

if Seekwell.RegisterSlash then
  Seekwell.RegisterSlash("browse", function(rest)
    rest = Trim(rest)
    B.Open(rest ~= "" and rest or nil)
  end)
end
