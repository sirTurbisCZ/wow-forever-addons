-- SellValue — vendor sell price of what a bulk/auto sell sold, and of the Junk lane (tooltip).
-- Price = item info field 11 (sellPrice), cached per item id. Unknown (not cached yet) items are never counted.
-- No events, no combat work.

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local SellValue = {}
BetterBackpack.Modules.SellValue = SellValue

local priceCache = {} -- itemID -> copper (only known prices are cached)

local function InCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

local function Num(v)
  if type(v) ~= "number" then
    return nil
  end
  if type(issecretvalue) == "function" and issecretvalue(v) then
    return nil
  end
  return v
end

--- Copper per single item, or nil when the item info is not cached yet.
function SellValue.Price(itemID)
  itemID = Num(itemID)
  if not itemID then
    return nil
  end
  local hit = priceCache[itemID]
  if hit ~= nil then
    return hit
  end
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not fn then
    return nil
  end
  local ok, name, _, _, _, _, _, _, _, _, _, sellPrice = pcall(fn, itemID)
  if not ok or name == nil then
    return nil
  end
  sellPrice = Num(sellPrice)
  if sellPrice == nil then
    return nil
  end
  priceCache[itemID] = sellPrice
  return sellPrice
end

--- Read id and stack count of a bag slot (call BEFORE the sale). Returns { id, count } or nil.
function SellValue.Measure(bag, slot)
  if bag == nil or slot == nil or not (C_Container and C_Container.GetContainerItemInfo) then
    return nil
  end
  local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
  if not ok or type(info) ~= "table" then
    return nil
  end
  local id = Num(info.itemID)
  if not id then
    return nil
  end
  local count = Num(info.stackCount) or 1
  if count < 1 then
    count = 1
  end
  return { id = id, count = count }
end

function SellValue.NewTally()
  return { items = 0, copper = 0, unknownItems = 0 }
end

--- Add a measured slot (m from Measure, or nil when the slot could not be read) to a tally.
function SellValue.Add(tally, m)
  if not tally then
    return
  end
  local price = m and SellValue.Price(m.id)
  if price == nil then
    tally.unknownItems = tally.unknownItems + (m and m.count or 1)
    return
  end
  tally.items = tally.items + m.count
  tally.copper = tally.copper + price * m.count
end

function SellValue.Format(copper, omitCopper)
  copper = math.floor(tonumber(copper) or 0)
  if copper < 0 then
    copper = 0
  end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then
    parts[#parts + 1] = g .. "g"
  end
  if s > 0 then
    parts[#parts + 1] = s .. "s"
  end
  if c > 0 and not (omitCopper and #parts > 0) then
    parts[#parts + 1] = c .. "c"
  end
  if #parts == 0 then
    return omitCopper and "0s" or "0c"
  end
  return table.concat(parts, " ")
end

--- Chat text for a finished sell, or nil when nothing was sold.
function SellValue.Summary(tally)
  if not tally then
    return nil
  end
  local unknown = tally.unknownItems or 0
  if (tally.items or 0) == 0 and unknown == 0 then
    return nil
  end
  if tally.items == 0 then
    return string.format("Sold %d items (value unknown)", unknown)
  end
  local text = string.format("Sold %d items for %s", tally.items, SellValue.Format(tally.copper))
  if unknown > 0 then
    text = text .. string.format(" (%d unknown)", unknown)
  end
  return text
end

function SellValue.Announce(tally)
  local text = SellValue.Summary(tally)
  if text and BetterBackpack.Print then
    BetterBackpack.Print(text)
  end
end

--- Tooltip line for a lane's slot list ({bag,slot}...), or nil (not Junk, in combat, nothing known).
function SellValue.LaneTooltipLine(laneKey, list)
  if laneKey ~= "junk" or InCombat() or type(list) ~= "table" or #list == 0 then
    return nil
  end
  local tally = SellValue.NewTally()
  for i = 1, #list do
    SellValue.Add(tally, SellValue.Measure(list[i].bag, list[i].slot))
  end
  if tally.items == 0 then
    return nil
  end
  local text = "Sell value: " .. SellValue.Format(tally.copper, true)
  if tally.unknownItems > 0 then
    text = text .. string.format(" (%d unknown)", tally.unknownItems)
  end
  return text
end
