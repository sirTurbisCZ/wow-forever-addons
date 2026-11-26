--[[
  PlatesPolicy — WHAT Plateband adds to a plate (rules only; layout lives in Plates.lua).

  Friendly plates : every debuff (any source) + helpful buffs whose total duration is <= HELPFUL_MAX_SEC
                    (HoTs, shields, short effects). Food/drink and long buffs are never added.
  Hostile plates  : the player's own DoTs that native omitted + debuffs cast by PARTY/RAID members
                    + dispellable / stealable enemy buffs. Neutral mobs are hostile (see IsPlayerOrFriendPlate).

  One choke point: D.ApplyGapPolicy(rows, unitToken, friendPlate) filters whatever the collectors produced.
  Loaded after Plates.lua (builds Plateband.PlatesPaintDeps) and before PlatesPaint.lua.
]]

Plateband = Plateband or {}
local D = Plateband.PlatesPaintDeps
if not D then
  return
end

-- A helpful aura is shown on friendly plates only when its TOTAL duration is at most this many seconds.
-- (Total, not remaining: a 30-min buff must not pop in during its last minute.)
local HELPFUL_MAX_SEC = 60
-- Hostile debuff with an unknown (secret / nil) caster: false = hide it (strict reading of "party only").
local UNKNOWN_SOURCE_KEEP = false

local IsSecret = D.IsSecret

--- Public (non-secret) value or nil.
local function pub(v)
  if v ~= nil and not IsSecret(v) then
    return v
  end
  return nil
end

--- Resolve a gap row to its live AuraData (source, dispel info, duration). Cached per row (rows live one paint).
function D.GapRowAuraData(row, tok)
  if type(row) ~= "table" or type(tok) ~= "string" or not C_UnitAuras then
    return nil
  end
  if row._pbData ~= nil then
    return row._pbData or nil
  end
  local aid, sid, icon = pub(row.auraInstanceID), pub(row.spellId), pub(row.icon)
  local data
  if aid and C_UnitAuras.GetAuraDataByAuraInstanceID then
    local ok, d = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, tok, aid)
    if ok and type(d) == "table" then
      data = d
    end
  end
  if not data and (aid or sid or icon) and C_UnitAuras.GetAuraDataByIndex then
    local first = row.isHelpful and "HELPFUL" or "HARMFUL"
    local second = row.isHelpful and "HARMFUL" or "HELPFUL"
    for _, filter in ipairs({ first, second }) do
      for i = 1, 40 do
        local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, tok, i, filter)
        if not ok or type(d) ~= "table" then
          break
        end
        local hit = false
        if aid then
          hit = pub(d.auraInstanceID) == aid
        elseif sid then
          hit = pub(d.spellId) == sid
        elseif icon then
          hit = pub(d.icon) == icon
        end
        if hit then
          data = d
          break
        end
      end
      if data then
        break
      end
    end
  end
  row._pbData = data or false
  return data
end

--- true = caster is the player's group (party/raid, pets included), false = someone else / the player,
--- nil = unknown (secret or no caster).
function D.AuraSourceIsGroupMember(data)
  if type(data) ~= "table" then
    return nil
  end
  local src = pub(data.sourceUnit)
  if type(src) ~= "string" or src == "" then
    return nil
  end
  if D.SameUnit(src, "player") or D.SameUnit(src, "pet") then
    return false
  end
  if src:match("^party%d+$") or src:match("^raid%d+$") or src:match("^partypet%d+$") or src:match("^raidpet%d+$") then
    return true
  end
  local hit = false
  pcall(function()
    local inParty = UnitInParty and UnitInParty(src)
    local inRaid = UnitInRaid and UnitInRaid(src)
    if (inParty and not IsSecret(inParty)) or (inRaid and not IsSecret(inRaid)) then
      hit = true
    end
  end)
  if hit then
    return true
  end
  for i = 1, 4 do
    if D.SameUnit(src, "party" .. i) or D.SameUnit(src, "partypet" .. i) then
      return true
    end
  end
  return false
end

--- Friendly plate: is this helpful aura worth showing?
function D.FriendlyHelpfulAllowed(data)
  if type(data) ~= "table" then
    return false
  end
  if D.IsFriendlyConsumableAura and D.IsFriendlyConsumableAura(data) then
    return false
  end
  local dur = pub(data.duration)
  if type(dur) ~= "number" or dur <= 0 then
    return false -- no duration (or secret): permanent / unknown buffs stay hidden
  end
  return dur <= HELPFUL_MAX_SEC
end

--- Hostile plate: enemy buff the player could dispel or steal.
function D.EnemyBuffDispellable(data)
  if type(data) ~= "table" then
    return false
  end
  if pub(data.isStealable) == true then
    return true
  end
  local dn = pub(data.dispelName)
  return type(dn) == "string" and dn ~= ""
end

--- Is this aura a buff? true / false / nil (cannot tell). Does not trust AuraData flags alone: the client may
--- not provide isHelpful, so the aura is also looked up in the HELPFUL / HARMFUL lists by id / spell / icon.
function D.GapRowIsHelpful(row, data, tok)
  if row._pbHelpful ~= nil then
    if row._pbHelpful == "?" then
      return nil
    end
    return row._pbHelpful
  end
  local result
  if row.isHelpful ~= nil then
    result = row.isHelpful and true or false
  elseif data then
    local h = pub(data.isHelpful)
    local hm = pub(data.isHarmful)
    if h ~= nil then
      result = h and true or false
    elseif hm ~= nil then
      result = not hm
    end
  end
  if result == nil and type(tok) == "string" and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    local aid = pub(row.auraInstanceID) or (data and pub(data.auraInstanceID))
    local sid = pub(row.spellId) or (data and pub(data.spellId))
    local icon = pub(row.icon) or (data and pub(data.icon))
    local function found(filter)
      for i = 1, 40 do
        local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, tok, i, filter)
        if not ok or type(d) ~= "table" then
          return false
        end
        if aid then
          if pub(d.auraInstanceID) == aid then
            return true
          end
        elseif sid then
          if pub(d.spellId) == sid then
            return true
          end
        elseif icon and pub(d.icon) == icon then
          return true
        end
      end
      return false
    end
    if aid or sid or icon then
      if found("HARMFUL") then
        result = false
      elseif found("HELPFUL") then
        result = true
      end
    end
  end
  row._pbHelpful = result == nil and "?" or result
  return result
end

--- Filter `rows` in place by the rules above. Returns how many rows were dropped.
function D.ApplyGapPolicy(rows, tok, friendPlate, quiet)
  if type(rows) ~= "table" or type(tok) ~= "string" then
    return 0
  end
  -- Per-call cache only: a row kept from an earlier paint (sticky) must be judged on today's aura data.
  for i = 1, #rows do
    if type(rows[i]) == "table" then
      rows[i]._pbData = nil
      rows[i]._pbHelpful = nil
    end
  end
  local j, dropped = 1, 0
  -- Counters for /pb diagnose (pol=kept/noData/unknownType/buffRule/source/err).
  local st = { kept = 0, noData = 0, unknown = 0, buff = 0, source = 0, err = 0 }
  for i = 1, #rows do
    local row = rows[i]
    local keep = false
    local why = "source"
    local ok = pcall(function()
      local data = D.GapRowAuraData(row, tok)
      local helpful = D.GapRowIsHelpful(row, data, tok)
      if helpful == nil and friendPlate then
        keep = false -- cannot tell buff from debuff on a friendly plate: never guess
        why = "unknown"
      elseif friendPlate then
        if data == nil then
          -- Unverifiable row (e.g. scraped from the target frame, whose aura pools also hold BUFFS):
          -- cannot prove it is a debuff or a short buff, so it is not added.
          keep = false
          why = "noData"
        elseif helpful then
          keep = D.FriendlyHelpfulAllowed(data)
          why = "buff"
        else
          keep = true -- all debuffs on friendly plates, any caster
        end
      elseif helpful then
        keep = data ~= nil and D.EnemyBuffDispellable(data)
        why = "buff"
      elseif data == nil then
        keep = false -- cannot tell who cast it
        why = "noData"
      elseif D.AuraIsOurPersonalOnly(data) then
        keep = true
      elseif pub(data.isFromPlayerOrPlayerPet) == true then
        -- Cast by ANY player or player pet (the client flag does not mean "mine"): strangers fighting
        -- next to you count too. NPC / mob debuffs are the ones that stay hidden.
        keep = true
      else
        local member = D.AuraSourceIsGroupMember(data)
        keep = member == true or (member == nil and UNKNOWN_SOURCE_KEEP)
      end
    end)
    if not ok then
      keep = false
      why = "err"
    end
    if keep then
      rows[j] = row
      j = j + 1
      st.kept = st.kept + 1
    else
      dropped = dropped + 1
      local key = (why == "noData" and "noData") or (why == "unknown" and "unknown") or (why == "buff" and "buff")
        or (why == "err" and "err") or "source"
      st[key] = st[key] + 1
    end
  end
  for k = j, #rows do
    rows[k] = nil
  end
  if D.lastPaintDebug and not quiet then
    D.lastPaintDebug.pol = string.format("%d/%d/%d/%d/%d/%d", st.kept, st.noData, st.unknown, st.buff, st.source, st.err)
  end
  return dropped
end

--- Helpful gaps through the same pipeline as harmful ones:
--- friendly plate -> short helpful buffs, hostile plate -> dispellable/stealable buffs.
function D.CollectPolicyHelpfulGaps(unitToken, skipKeys, out, maxN, friendPlate, stats)
  if type(unitToken) ~= "string" or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
    return
  end
  for i = 1, 40 do
    if #out >= maxN then
      return
    end
    local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unitToken, i, "HELPFUL")
    if not ok or type(data) ~= "table" then
      break
    end
    local wanted = false
    pcall(function()
      if friendPlate then
        wanted = D.FriendlyHelpfulAllowed(data)
      else
        wanted = D.EnemyBuffDispellable(data)
      end
    end)
    if wanted then
      local icon = data.icon
      local key = D.AuraDedupeKey(data, icon)
      local ck = D.CanonicalGapKey({ icon = icon, spellId = data.spellId, auraInstanceID = data.auraInstanceID })
      if not ((ck and skipKeys[ck]) or (key and skipKeys[key])) then
        key = key or ("help:" .. tostring(i) .. ":" .. tostring(unitToken))
        out[#out + 1] = {
          icon = icon,
          spellId = data.spellId,
          auraInstanceID = data.auraInstanceID,
          applications = data.applications,
          expirationTime = data.expirationTime,
          duration = data.duration,
          isHelpful = true,
          _pbKind = friendPlate and "help" or "purge",
        }
        skipKeys[key] = true
        if ck then
          skipKeys[ck] = true
        end
        if stats then
          stats.helpful = (stats.helpful or 0) + 1
        end
      end
    end
  end
end

--- Hover tooltip for an added icon (what the effect does). Only GameTooltip is touched - no secure or native
--- frames; every call is pcall'd (aura ids may be secret). Scripts are set in Plates.lua InitAuraButton.
function D.GapButtonOnEnter(self)
  local ok0, p = pcall(function()
    return Plateband.Config.GetProfile()
  end)
  if ok0 and type(p) == "table" and p.gapTooltip == false then
    return
  end
  local row, tok = self._pbRow, self._pbUnit
  if type(row) ~= "table" or type(tok) ~= "string" or not GameTooltip then
    return
  end
  pcall(GameTooltip.SetOwner, GameTooltip, self, "ANCHOR_TOP")
  local shown = false
  local aid = row.auraInstanceID
  if aid ~= nil then
    local fn = GameTooltip.SetUnitAuraByAuraInstanceID
    if fn then
      shown = pcall(fn, GameTooltip, tok, aid)
    end
    if not shown and row.isHelpful and GameTooltip.SetUnitBuffByAuraInstanceID then
      shown = pcall(GameTooltip.SetUnitBuffByAuraInstanceID, GameTooltip, tok, aid)
    end
  end
  local sid = pub(row.spellId)
  if not shown and sid and GameTooltip.SetSpellByID then
    shown = pcall(GameTooltip.SetSpellByID, GameTooltip, sid)
  end
  if shown then
    pcall(GameTooltip.Show, GameTooltip)
  else
    pcall(GameTooltip.Hide, GameTooltip)
  end
end

function D.GapButtonOnLeave(self)
  if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then
    pcall(GameTooltip.Hide, GameTooltip)
  end
end

--- Thin coloured border so buffs and debuffs in the one row can be told apart:
--- green = helpful (HoT, shield, short buff), red = debuff, gold = enemy buff you can dispel / steal.
function D.ApplyGapBorder(button, row)
  if not button or type(row) ~= "table" then
    return
  end
  local helpful = row.isHelpful == true or row._pbHelpful == true
  local r, g, b = 0.85, 0.15, 0.15
  if row._pbKind == "purge" then
    r, g, b = 0.95, 0.75, 0.10
  elseif helpful then
    r, g, b = 0.20, 0.80, 0.25
  end
  local edges = button._pbEdges
  if not edges then
    edges = {}
    for i = 1, 4 do
      local t = button:CreateTexture(nil, "OVERLAY", nil, 7)
      edges[i] = t
    end
    local th = 1
    edges[1]:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    edges[1]:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    edges[1]:SetHeight(th)
    edges[2]:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    edges[2]:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    edges[2]:SetHeight(th)
    edges[3]:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    edges[3]:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    edges[3]:SetWidth(th)
    edges[4]:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    edges[4]:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    edges[4]:SetWidth(th)
    button._pbEdges = edges
  end
  for i = 1, 4 do
    edges[i]:SetColorTexture(r, g, b, 1)
    edges[i]:Show()
  end
end
