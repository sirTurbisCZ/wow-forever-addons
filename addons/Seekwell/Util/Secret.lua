--[[
  Seekwell.Secret — every value read from the client goes through Plain().
  The Forever client can hand out "secret values" (GUIDs, names, positions in instances);
  comparing, formatting or using one as a table key throws. A secret value is treated as unknown (nil).
]]

Seekwell = Seekwell or {}
local S = {}
Seekwell.Secret = S

local function IsSecret(v)
  if v == nil or not issecretvalue then
    return false
  end
  local ok, r = pcall(issecretvalue, v)
  if not ok then
    return true -- cannot tell: be careful
  end
  return r == true
end
S.IsSecret = IsSecret

--- v, or nil when v is nil or secret.
local function Plain(v)
  if v == nil or IsSecret(v) then
    return nil
  end
  return v
end
S.Plain = Plain

--- First return value of fn(...) as a plain value; nil on error or secret.
function S.Get(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, v = pcall(fn, ...)
  if not ok then
    return nil
  end
  return Plain(v)
end

--- A plain string, or nil.
function S.Str(v)
  v = Plain(v)
  if type(v) == "string" then
    return v
  end
  return nil
end

local function Split(guid)
  -- "Creature-0-1234-0-5678-299-0000ABCDEF": type, 0, server, instance, zone uid, npcID, spawn uid
  local parts, n = {}, 0
  for part in string.gmatch(guid, "[^%-]+") do
    n = n + 1
    parts[n] = part
    if n >= 6 then
      break
    end
  end
  return parts
end

--- "creature", "player", "pet", "object", "other", "secret" or "none".
function S.GUIDKind(guid)
  if guid == nil then
    return "none"
  end
  if IsSecret(guid) then
    return "secret"
  end
  if type(guid) ~= "string" or guid == "" then
    return "none"
  end
  local unitType = guid:match("^(%a+)%-")
  if unitType == "Creature" or unitType == "Vehicle" then
    return "creature"
  elseif unitType == "Player" then
    return "player"
  elseif unitType == "Pet" then
    return "pet"
  elseif unitType == "GameObject" then
    return "object"
  end
  return "other"
end

--- npcID of a creature / vehicle GUID, else nil (also for secret GUIDs).
function S.NpcIDFromGUID(guid)
  guid = Plain(guid)
  if type(guid) ~= "string" then
    return nil
  end
  local ok, parts = pcall(Split, guid)
  if not ok or not parts then
    return nil
  end
  local unitType = parts[1]
  if unitType == "Creature" or unitType == "Vehicle" then
    local id = tonumber(parts[6])
    if id and id > 0 then
      return id
    end
  end
  return nil
end

--- itemID from an item link or "item:123" string.
function S.ItemIDFromLink(link)
  link = S.Str(link)
  if not link then
    return nil
  end
  return tonumber(link:match("item:(%d+)"))
end
