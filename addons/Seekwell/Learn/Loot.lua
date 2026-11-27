--[[
  Seekwell.Loot — learns drops from your own loot windows.
  LOOT_OPENED: for each slot, GetLootSourceInfo gives (GUID, quantity) pairs; a creature GUID gives the npcID.
  A GUID counts as one kill once per session (re-opening or skinning the same corpse is not a new kill);
  money slots count the kill but no item. Secret values are skipped (nothing is learned from them).
  Names come from a small name cache filled from target / mouseover.
]]

Seekwell = Seekwell or {}
local Loot = {}
Seekwell.Loot = Loot

local NAME_CACHE_MAX = 500
local SEEN_MAX = 3000
local nameCache, nameCount = {}, 0
local seen, seenCount = {}, 0 -- [GUID] = true, this session
local lastWindow = nil -- summary of the last learned window (for /sw status and tests)
local frame

local function S()
  return Seekwell.Secret
end

function Loot.CachedName(npcID)
  return nameCache[npcID]
end

--- Remember the name of a creature unit (target / mouseover). Returns npcID or nil.
function Loot.RememberUnit(unit)
  local Sec = S()
  if not Sec.Get(UnitExists, unit) then
    return nil
  end
  if Sec.Get(UnitIsPlayer, unit) then
    return nil
  end
  local id = Sec.NpcIDFromGUID(Sec.Get(UnitGUID, unit))
  if not id then
    return nil
  end
  local name = Sec.Str(Sec.Get(UnitName, unit))
  if name and name ~= "" then
    if not nameCache[id] then
      if nameCount >= NAME_CACHE_MAX then
        nameCache, nameCount = {}, 0
      end
      nameCount = nameCount + 1
    end
    nameCache[id] = name
  end
  return id
end

local function MapID()
  local Sec = S()
  if not (C_Map and C_Map.GetBestMapForUnit) then
    return nil
  end
  local id = Sec.Get(C_Map.GetBestMapForUnit, "player")
  return tonumber(id)
end

local function IsMoneySlot(slot)
  if not GetLootSlotType then
    return false
  end
  local t = S().Get(GetLootSlotType, slot)
  local money = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or LOOT_SLOT_MONEY or 2
  return t == money
end

local function SlotItemID(slot)
  local Sec = S()
  local link = Sec.Get(GetLootSlotLink, slot)
  local id = Sec.ItemIDFromLink(link)
  if id then
    return id
  end
  return nil
end

local function SlotSources(slot)
  if not GetLootSourceInfo then
    return {}
  end
  local res = { pcall(GetLootSourceInfo, slot) }
  if not res[1] then
    return {}
  end
  local out = {}
  local Plain = S().Plain
  for i = 2, #res, 2 do
    local guid, qty = Plain(res[i]), Plain(res[i + 1])
    if type(guid) == "string" then
      out[#out + 1] = { guid = guid, qty = tonumber(qty) or 1 }
    end
  end
  return out
end

--- Read the open loot window and record what each creature dropped.
function Loot.OnLootOpened()
  local s = Seekwell.Config.Get()
  if not s.learn then
    return
  end
  local Sec = S()
  local n = tonumber(Sec.Get(GetNumLootItems)) or 0
  if n <= 0 then
    return
  end
  local perNpc, order = {}, {}
  for slot = 1, n do
    local money = IsMoneySlot(slot)
    local itemID = (not money) and SlotItemID(slot) or nil
    for _, src in ipairs(SlotSources(slot)) do
      if not seen[src.guid] then
        local npcID = Sec.NpcIDFromGUID(src.guid)
        if npcID then
          local e = perNpc[npcID]
          if not e then
            e = { guids = {}, kills = 0, items = {} }
            perNpc[npcID] = e
            order[#order + 1] = npcID
          end
          if not e.guids[src.guid] then
            e.guids[src.guid] = true
            e.kills = e.kills + 1
          end
          if itemID then
            e.items[itemID] = (e.items[itemID] or 0) + math.max(1, math.floor(src.qty))
          end
        end
      end
    end
  end
  if #order == 0 then
    return
  end
  local mapID = MapID()
  local now = (time and time()) or 0
  local summary = { npcs = 0, kills = 0, items = 0 }
  for _, npcID in ipairs(order) do
    local e = perNpc[npcID]
    for guid in pairs(e.guids) do
      if seenCount >= SEEN_MAX then
        seen, seenCount = {}, 0
      end
      seen[guid] = true
      seenCount = seenCount + 1
    end
    Seekwell.Learned.Record(npcID, nameCache[npcID], e.kills, e.items, mapID, now)
    summary.npcs = summary.npcs + 1
    summary.kills = summary.kills + e.kills
    for _ in pairs(e.items) do
      summary.items = summary.items + 1
    end
  end
  lastWindow = summary
  if Seekwell.Debug then
    Seekwell.Debug(string.format("learned: %d npc, %d kill, %d item", summary.npcs, summary.kills, summary.items))
  end
end

function Loot.LastWindow()
  return lastWindow
end

function Loot.Start()
  if frame then
    return
  end
  frame = CreateFrame("Frame")
  frame:RegisterEvent("LOOT_OPENED")
  frame:RegisterEvent("PLAYER_TARGET_CHANGED")
  frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
  local handler = Seekwell.Safe("loot", function(_, event)
    if event == "LOOT_OPENED" then
      Loot.OnLootOpened()
    elseif event == "PLAYER_TARGET_CHANGED" then
      Loot.RememberUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
      Loot.RememberUnit("mouseover")
    end
  end)
  frame:SetScript("OnEvent", handler)
end
