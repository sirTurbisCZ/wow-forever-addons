--[[
  Seekwell.Tooltip — "Seekwell: Mob name 12.5 %" lines on item tooltips (max 1-5 sources, Forever / learned first).
  Shown also when TnnysMobLoot is installed (owner decision). Hook: TooltipDataProcessor post-call for items,
  fallback OnTooltipSetItem. Secret values are skipped; a line is never added twice.
]]

Seekwell = Seekwell or {}
local Tip = {}
Seekwell.Tooltip = Tip

local PREFIX = "Seekwell:"
local installed = false
local busy = false
local mode = nil -- "processor" or "hook"

local function Sec()
  return Seekwell.Secret
end

local function ItemIDFrom(tooltip, data)
  local S = Sec()
  if type(data) == "table" then
    local id = S.Plain(data.id)
    if type(id) == "number" and id > 0 then
      return id
    end
  end
  if tooltip and tooltip.GetItem then
    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    if ok then
      return S.ItemIDFromLink(link)
    end
  end
  return nil
end

local function HasOurLine(tooltip)
  local S = Sec()
  local name = S.Str(tooltip.GetName and tooltip:GetName())
  if not name then
    return false
  end
  local n = tonumber(S.Plain(tooltip:NumLines())) or 0
  for i = 1, n do
    local fs = _G[name .. "TextLeft" .. i]
    local t = fs and fs.GetText and S.Str(fs:GetText())
    if t and t:find(PREFIX, 1, true) then
      return true
    end
  end
  return false
end

--- Another addon (Tinny) already added its own "Drops from" list to this tooltip.
local function HasForeignDrops(tooltip)
  local S = Sec()
  local name = S.Str(tooltip.GetName and tooltip:GetName())
  if not name then
    return false
  end
  local n = tonumber(S.Plain(tooltip:NumLines())) or 0
  for i = 1, n do
    local fs = _G[name .. "TextLeft" .. i]
    local t = fs and fs.GetText and S.Str(fs:GetText())
    if t and t:find("Drops from", 1, true) and not t:find(PREFIX, 1, true) then
      return true
    end
  end
  return false
end

--- Lines for an item: { {text, r, g, b} } (also used by the tests).
function Tip.Lines(itemID)
  local s = Seekwell.Config.Get()
  local max = math.max(1, math.min(5, tonumber(s.tooltip.max) or 3))
  local R = Seekwell.Registry
  local out = {}
  local dj = false
  for _, row in ipairs(R.ItemSources(itemID, max)) do
    local name = R.NpcName(row.npc) or ("npc " .. tostring(row.npc))
    local text = PREFIX .. " " .. name .. " " .. R.FormatPct(row.p)
    if row.origin == "dj" then
      dj = true
      text = PREFIX .. " " .. tostring(row.dungeon) .. " \226\128\148 " .. tostring(row.boss)
    end
    if row.origin == "dj" then
      out[#out + 1] = { text, 0.95, 0.75, 0.35 }
    elseif row.origin == "classic" then
      out[#out + 1] = { text, 0.62, 0.62, 0.62 }
    else
      out[#out + 1] = { text, 0.45, 0.80, 1.0 }
    end
  end
  -- one compact Dungeon Journal line (boss without npc id, or a dungeon quest reward)
  local DJ = Seekwell.DJ
  if not dj and #out < max and DJ and DJ.ItemSources then
    local ok, rows = pcall(DJ.ItemSources, itemID)
    local r = ok and rows and rows[1]
    if r then
      out[#out + 1] = { PREFIX .. " " .. r.label, 0.95, 0.75, 0.35 }
    end
  end
  return out
end

local function OnItem(tooltip, data)
  if busy or not tooltip then
    return
  end
  local s = Seekwell.Config.Get()
  if not s.tooltip.enabled then
    return
  end
  if tooltip.IsForbidden and tooltip:IsForbidden() then
    return
  end
  local itemID = ItemIDFrom(tooltip, data)
  if not itemID then
    return
  end
  if HasOurLine(tooltip) then
    return
  end
  if s.tooltip.skipIfDropsShown ~= false and HasForeignDrops(tooltip) then
    return
  end
  local lines = Tip.Lines(itemID)
  if #lines == 0 then
    return
  end
  busy = true
  for _, l in ipairs(lines) do
    tooltip:AddLine(l[1], l[2], l[3], l[4])
  end
  if mode == "hook" and tooltip.Show then
    pcall(tooltip.Show, tooltip) -- resize after the lines were added
  end
  busy = false
end

local SafeOnItem

--- "processor" | "hook" | nil (not installed yet) — for /sw selftest.
function Tip.Mode()
  return installed and mode or nil
end

function Tip.Install()
  if installed then
    return mode
  end
  installed = true
  SafeOnItem = Seekwell.Safe("tooltip", function(tooltip, data)
    local ok, err = pcall(OnItem, tooltip, data)
    busy = false
    if not ok then
      error(err, 0)
    end
  end)
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
    and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, SafeOnItem)
    mode = "processor"
  else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
      if tt and tt.HookScript then
        tt:HookScript("OnTooltipSetItem", function(self)
          SafeOnItem(self, nil)
        end)
      end
    end
    mode = "hook"
  end
  return mode
end

function Tip.Mode()
  return mode
end
