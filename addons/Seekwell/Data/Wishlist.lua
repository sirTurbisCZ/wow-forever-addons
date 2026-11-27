--[[ Seekwell.Wish — wishlist per character (SeekwellCharDB.wish = { [itemID] = { t = time } }) ]]

Seekwell = Seekwell or {}
local Wish = {}
Seekwell.Wish = Wish
Wish.generation = 0 -- bumped on every change (caches compare it)

local function List()
  return Seekwell.Config.Char().wish
end

function Wish.Has(itemID)
  itemID = tonumber(itemID)
  return itemID ~= nil and List()[itemID] ~= nil
end

--- Toggle; returns true when the item is now on the wishlist.
function Wish.Toggle(itemID)
  itemID = tonumber(itemID)
  if not itemID then
    return false
  end
  local w = List()
  Wish.generation = Wish.generation + 1
  if w[itemID] then
    w[itemID] = nil
    return false
  end
  w[itemID] = { t = (time and time()) or 0 }
  return true
end

function Wish.Remove(itemID)
  List()[tonumber(itemID) or -1] = nil
  Wish.generation = Wish.generation + 1
end

--- Item ids, newest first.
function Wish.Items()
  local out = {}
  for id, e in pairs(List()) do
    out[#out + 1] = { id = id, t = type(e) == "table" and tonumber(e.t) or 0 }
  end
  table.sort(out, function(a, b)
    if a.t ~= b.t then
      return a.t > b.t
    end
    return a.id < b.id
  end)
  return out
end

function Wish.Count()
  local n = 0
  for _ in pairs(List()) do
    n = n + 1
  end
  return n
end

-- ---------------------------------------------------------------------------
-- Owned items: ticked automatically, left out of alerts and hunts (setting wishIgnoreOwned, default on)
-- ---------------------------------------------------------------------------

local ownedSet = {}   -- [itemID] = true when you have at least the wanted quantity
local haveCount = {}  -- [itemID] = how many you have (wishlist items only)
local ownedPending = false

--- Wanted quantity of a wishlist item (default 1).
function Wish.Qty(itemID)
  local e = List()[tonumber(itemID) or -1]
  local q = type(e) == "table" and tonumber(e.q) or 1
  return math.max(1, math.min(9999, math.floor(q or 1)))
end

function Wish.SetQty(itemID, q)
  itemID = tonumber(itemID)
  local e = itemID and List()[itemID]
  q = tonumber(q)
  if not e or not q then
    return false
  end
  if type(e) ~= "table" then
    e = { t = 0 }
    List()[itemID] = e
  end
  e.q = math.max(1, math.min(9999, math.floor(q)))
  Wish.generation = Wish.generation + 1
  return true
end

--- How many of the item you have (cached from the last bag update).
function Wish.Have(itemID)
  return haveCount[tonumber(itemID) or -1] or 0
end

--- How many of the item you carry (bags, and the bank when the client counts it); 0 when unknown.
function Wish.Count_(itemID)
  itemID = tonumber(itemID)
  if not itemID then
    return 0
  end
  local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not fn then
    return 0
  end
  local ok, n = pcall(fn, itemID, true)
  if not ok or (issecretvalue and issecretvalue(n)) or type(n) ~= "number" then
    return 0
  end
  return n
end

--- Do you have at least the wanted quantity?
function Wish.Owned(itemID)
  return Wish.Count_(itemID) >= Wish.Qty(itemID)
end

local function IgnoreOwned()
  local s = Seekwell.Config and Seekwell.Config.Get and Seekwell.Config.Get()
  return not s or s.wishIgnoreOwned ~= false
end

--- Recompute the owned set; bumps generation when it changed (caches of Alerts / Map follow).
function Wish.RefreshOwned()
  local now, changed, counts, countChanged = {}, false, {}, false
  for id in pairs(List()) do
    local n = Wish.Count_(id)
    counts[id] = n
    if haveCount[id] ~= n then
      countChanged = true
    end
    if n >= Wish.Qty(id) then
      now[id] = true
    end
  end
  haveCount = counts
  for id in pairs(now) do
    if not ownedSet[id] then
      changed = true
    end
  end
  for id in pairs(ownedSet) do
    if not now[id] then
      changed = true
    end
  end
  ownedSet = now
  if changed then
    Wish.generation = Wish.generation + 1
  end
  if changed or countChanged then
    if Seekwell.Window and Seekwell.Window.Refresh then
      pcall(Seekwell.Window.Refresh)
    end
  end
  return changed
end

--- Cached answer (refreshed on bag changes); false for items not on the list.
function Wish.IsOwned(itemID)
  return ownedSet[tonumber(itemID) or -1] == true
end

--- On the list and still wanted (not owned, unless the setting says to keep owned ones active).
function Wish.IsWanted(itemID)
  if not Wish.Has(itemID) then
    return false
  end
  return not (IgnoreOwned() and Wish.IsOwned(itemID))
end

--- Items still wanted: for alerts, hunts and the zone summary.
function Wish.Active()
  local out = {}
  for _, w in ipairs(Wish.Items()) do
    if not (IgnoreOwned() and ownedSet[w.id]) then
      out[#out + 1] = w
    end
  end
  return out
end

local function QueueRefresh()
  if ownedPending or not (C_Timer and C_Timer.After) then
    return
  end
  ownedPending = true
  C_Timer.After(1, function()
    ownedPending = false
    pcall(Wish.RefreshOwned)
  end)
end

if Seekwell.RegisterStart then
  Seekwell.RegisterStart("wishlist owned", function()
    local f = CreateFrame("Frame")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function()
      if Wish.Count() > 0 then
        QueueRefresh()
      end
    end)
    Wish.RefreshOwned()
  end)
end

-- ---------------------------------------------------------------------------
-- Add by name / link / id
-- ---------------------------------------------------------------------------

local function CachedName(id)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not fn then
    return nil
  end
  local ok, name = pcall(fn, id)
  if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
    return name
  end
  return nil
end

local idPool, idPoolGen
local requested = {}
local REQUEST_MAX = 50

--- Items matching text (item link, id or part of a name): { {id=, name=} } best first, at most `limit`.
--- Sources of names: Tinny's Classic item table, items you looted (learned), items of the Forever data,
--- and the wishlist, using the client's cache; uncached ones are requested so a second try can find them.
function Wish.Find(text, limit)
  limit = limit or 8
  text = tostring(text or "")
  local id = text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$")
  if id then
    id = tonumber(id)
    return { { id = id, name = CachedName(id) or ("item " .. id) } }
  end
  local q = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[%[%]]", ""):match("^%s*(.-)%s*$"):lower()
  if #q < 2 then
    return {}
  end
  local seen, out = {}, {}
  local function Add(itemID, name)
    if itemID and not seen[itemID] and name and name:lower():find(q, 1, true) then
      seen[itemID] = true
      out[#out + 1] = { id = itemID, name = name }
    end
  end
  local T = Seekwell.Tinny
  if T and T.FindItems then
    for _, e in ipairs(T.FindItems(q, limit)) do
      Add(e.id, e.name)
    end
  end
  local DJ = Seekwell.DJ
  if DJ and DJ.FindItems then
    local ok, lst = pcall(DJ.FindItems, q, limit)
    for _, e in ipairs(ok and lst or {}) do
      Add(e.id, CachedName(e.id) or e.name)
    end
  end
  local F = Seekwell.FDB
  if F and F.NameSearch then -- every ForeverDB item name (Forever-only items too, no client cache needed)
    local ok, lst = pcall(F.NameSearch, q, "item", limit * 4)
    for _, e in ipairs(ok and type(lst) == "table" and lst or {}) do
      Add(e.id, CachedName(e.id) or e.name)
    end
  end
  -- ids known from learned loot, the wishlist and the Forever data: names only from the client cache
  local L = Seekwell.Learned
  local g = L and L.generation or 0
  if not idPool or idPoolGen ~= g then
    idPool, idPoolGen = {}, g
    local set = {}
    local sdb = rawget(_G, "SeekwellDB")
    local learned = type(sdb) == "table" and sdb.learned or nil
    if learned and type(learned.npc) == "table" then
      for _, e in pairs(learned.npc) do
        if type(e) == "table" and type(e.l) == "table" then
          for itemID in pairs(e.l) do
            set[itemID] = true
          end
        end
      end
    end
    local ff = rawget(_G, "TnnysMobLoot_Forever")
    if type(ff) == "table" and type(ff.from) == "table" then
      for itemID in pairs(ff.from) do
        set[itemID] = true
      end
    end
    for itemID in pairs(set) do
      if type(itemID) == "number" then
        idPool[#idPool + 1] = itemID
      end
    end
  end
  local request = C_Item and C_Item.RequestLoadItemDataByID
  local asked = 0
  local function Consider(itemID)
    local name = CachedName(itemID)
    if name then
      Add(itemID, name)
    elseif request and asked < REQUEST_MAX and not requested[itemID] then
      requested[itemID] = true
      asked = asked + 1
      pcall(request, itemID)
    end
  end
  for itemID in pairs(List()) do
    if type(itemID) == "number" then
      Consider(itemID)
    end
  end
  for _, itemID in ipairs(idPool) do
    Consider(itemID)
  end
  table.sort(out, function(a, b)
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
  end)
  while #out > limit do
    out[#out] = nil
  end
  return out
end

--- Add by text. Returns status, info: "added" (item), "exists", "many" (matches), "none".
function Wish.AddByText(text)
  text = tostring(text or "")
  local qty
  local body, n = text:match("^(.-)%s+[xX*](%d+)%s*$")
  if not body then
    n, body = text:match("^%s*(%d+)%s*[xX*]%s+(.+)$")
  end
  if body and n then
    text, qty = body, tonumber(n)
  end
  local found = Wish.Find(text, 8)
  if #found == 0 then
    return "none"
  end
  local q = tostring(text or ""):lower():match("^%s*(.-)%s*$")
  local pick
  if #found == 1 then
    pick = found[1]
  else
    for _, f in ipairs(found) do
      if f.name:lower() == q then
        pick = f
        break
      end
    end
  end
  if not pick then
    return "many", found
  end
  if Wish.Has(pick.id) then
    if qty then
      Wish.SetQty(pick.id, qty)
      Wish.RefreshOwned()
      return "qty", pick
    end
    return "exists", pick
  end
  Wish.Toggle(pick.id)
  if qty then
    Wish.SetQty(pick.id, qty)
  end
  Wish.RefreshOwned()
  return "added", pick
end

--- /sw wish add|del|list <text>
local function Say(msg)
  if Seekwell.Print then
    Seekwell.Print(msg)
  end
end

local function Slash(rest)
  rest = (rest or ""):match("^%s*(.-)%s*$") or ""
  local cmd, arg = rest:match("^(%S+)%s*(.*)$")
  cmd = cmd or ""
  if cmd == "" then
    if Seekwell.Window and Seekwell.Window.Show then
      Seekwell.Window.Show("wishlist")
    end
  elseif cmd == "add" then
    local st, info = Wish.AddByText(arg)
    if st == "added" then
      Say("wishlist: added " .. info.name .. " (item " .. info.id .. ")" .. (Wish.Qty(info.id) > 1 and (" x" .. Wish.Qty(info.id)) or ""))
    elseif st == "qty" then
      Say("wishlist: " .. info.name .. " now wanted x" .. Wish.Qty(info.id))
    elseif st == "exists" then
      Say("wishlist: " .. info.name .. " is already on the list")
    elseif st == "many" then
      Say("wishlist: several items match, be more specific or use the id:")
      for _, f in ipairs(info) do
        Say("  " .. f.name .. "  (/sw wish add " .. f.id .. ")")
      end
    else
      Say("wishlist: no item found for \"" .. arg .. "\" (names of items you have not met may need a second try after the client loads them; links and ids always work)")
    end
    if Seekwell.Window and Seekwell.Window.Refresh then
      pcall(Seekwell.Window.Refresh)
    end
  elseif cmd == "qty" then
    local name, n = arg:match("^(.-)%s+(%d+)$")
    if not name then
      Say("usage: /sw wish qty <name|id> <amount>")
    else
      local found = Wish.Find(name, 8)
      local hit
      for _, f in ipairs(found) do
        if Wish.Has(f.id) then
          hit = f
          break
        end
      end
      if hit and Wish.SetQty(hit.id, n) then
        Wish.RefreshOwned()
        Say("wishlist: " .. hit.name .. " wanted x" .. Wish.Qty(hit.id) .. " (you have " .. Wish.Have(hit.id) .. ")")
      else
        Say("wishlist: nothing on the list matches \"" .. name .. "\"")
      end
    end
  elseif cmd == "del" or cmd == "remove" then
    local found = Wish.Find(arg, 8)
    local hit
    for _, f in ipairs(found) do
      if Wish.Has(f.id) then
        hit = f
        break
      end
    end
    if hit then
      Wish.Remove(hit.id)
      Say("wishlist: removed " .. hit.name)
      if Seekwell.Window and Seekwell.Window.Refresh then
        pcall(Seekwell.Window.Refresh)
      end
    else
      Say("wishlist: nothing on the list matches \"" .. arg .. "\"")
    end
  elseif cmd == "list" then
    local items = Wish.Items()
    Say("wishlist: " .. #items .. " item(s)")
    for _, w in ipairs(items) do
      Say("  " .. (CachedName(w.id) or ("item " .. w.id)) .. "  " .. Wish.Have(w.id) .. "/" .. Wish.Qty(w.id) .. (Wish.IsOwned(w.id) and "  (done)" or ""))
    end
  else
    Say("usage: /sw wish [add <name|link|id> [x20] | qty <name|id> <n> | del <name> | list]")
  end
end

if Seekwell.RegisterSlash then
  Seekwell.RegisterSlash("wish", Slash)
end
