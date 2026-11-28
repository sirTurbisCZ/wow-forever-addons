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
-- A debuff on a friendly unit is shown only when its total duration is at most this long: Weakened Soul (15 s),
-- poisons, diseases, curses fit; Resurrection Sickness (600 s) and hour-long bonuses filed as debuffs (Boosted Rest) do not.
-- Unknown duration is shown.
local FRIENDLY_DEBUFF_MAX_SEC = 300
-- Hostile debuff with an unknown (secret / nil) caster: true = show it. In combat the client hides other casters' aura fields
-- (secret), so a strict rule would drop every debuff but your own. Only a debuff KNOWN to come from an NPC is hidden.
local UNKNOWN_SOURCE_KEEP = true

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
  if row._pbDirect then
    return row._pbDirect -- row built from this very AuraData (CollectDirectAuras)
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
  local prof = D.Profile and D.Profile()
  if type(prof) == "table" and prof.enemyBuffs == false then
    return false -- "Enemy buffs row" off in the settings window
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
      if row._pbSynthetic and not (InCombatLockdown and InCombatLockdown()) then
        -- own-cast placeholder (combat only): out of combat the real aura data takes over
        keep = false
        why = "source"
        return
      end
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
          -- debuffs on friendly plates: any caster, but not hour-long "debuffs" (Boosted Rest)
          local dur = pub(data.duration)
          keep = not (type(dur) == "number" and dur > FRIENDLY_DEBUFF_MAX_SEC)
          if not keep then
            why = "buff"
          end
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
        if pub(data.isFromPlayerOrPlayerPet) == false then
          keep = member == true -- the client says: not cast by a player (NPC/mob)
        else
          keep = member == true or (member == nil and UNKNOWN_SOURCE_KEEP)
        end
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

-- ---------------------------------------------------------------------------------------------------
-- Friendly plates in combat. The client does not let addons read the auras of friendly units in combat
-- ("Auras cannot be accessed when secret while tainted"), and re-anchoring frames that hang on nameplate
-- frames is blocked in lockdown. So:
--  A) icons painted out of combat stay and expire from their stored times (RefreshGapCooldownsOnly);
--  B) your own Power Word: Shield is known from the cast event -> Weakened Soul (15 s) on that unit's row.
-- Both need the row frame to be anchored BEFORE combat (PreAnchorFriend); only our own frames are touched
-- in combat (Show / icons / size / child anchors), never the plate's.
-- ---------------------------------------------------------------------------------------------------

local WEAKENED_SOUL = 6788
local WEAKENED_SOUL_SEC = 15
local PWS_IDS = {
  [17] = true, [592] = true, [600] = true, [3747] = true, [6065] = true,
  [6066] = true, [10898] = true, [10899] = true, [10900] = true, [10901] = true,
}
local sentTarget = {}

local function SpellNameOf(spellID)
  local name
  pcall(function()
    if C_Spell and C_Spell.GetSpellName then
      name = C_Spell.GetSpellName(spellID)
    end
    if not name and GetSpellInfo then
      name = GetSpellInfo(spellID)
    end
  end)
  if name ~= nil and IsSecret(name) then
    return nil
  end
  return name
end

local function IsPowerWordShield(spellID)
  if type(spellID) ~= "number" or IsSecret(spellID) then
    return false
  end
  if PWS_IDS[spellID] then
    return true
  end
  return SpellNameOf(spellID) == "Power Word: Shield"
end

local function NumPoints(f)
  local n = 0
  pcall(function()
    n = f:GetNumPoints() or 0
  end)
  return n
end

--- Out of combat: anchor (hidden) the row of a party/raid plate so it can be shown in combat.
function D.PreAnchorFriend(unit, plate)
  if (InCombatLockdown and InCombatLockdown()) or not plate or not unit then
    return
  end
  if not (D.IsPartyRaidMergePlate and D.IsPartyRaidMergePlate(unit, plate)) then
    return
  end
  local fb = D.fallbacks[unit]
  -- ClearFallback drops the points (and the flag): re-anchor whenever the row has no points.
  if fb and fb._pbAnchored and NumPoints(fb) > 0 and fb._pbPlate == plate then
    return
  end
  fb = D.EnsureFallback(unit, plate)
  if not fb then
    return
  end
  local painted = tonumber(fb._painted) or 0
  pcall(D.LayoutMergeBesideNative, unit, plate, fb, math.max(1, painted))
  if painted <= 0 then
    pcall(fb.Hide, fb)
    fb._painted = 0
  end
end

--- The row frame for `unit` on `plate`; when the key differs (target/plate key), any row on that plate.
local function RowFor(unit, plate)
  local fb = unit and D.fallbacks[unit]
  if fb then
    return fb, unit
  end
  for k, f in pairs(D.fallbacks) do
    if f and f._pbPlate == plate then
      return f, k
    end
  end
  return nil, unit
end

--- Combat-safe: put one synthetic row into the next free slot of an already anchored row.
--- Returns ok, reason (reason is shown by /pb tree).
function D.CombatAppendRow(unit, plate, row, tok)
  local fb, key = RowFor(unit, plate)
  if not fb then
    return false, "no row frame (plate not painted out of combat)"
  end
  if not fb._pbAnchored or NumPoints(fb) == 0 then
    return false, "row not anchored (key " .. tostring(key) .. ")"
  end
  if type(fb.icons) ~= "table" then
    return false, "row has no slots"
  end
  unit = key
  local sticky = D.gapSticky[unit]
  if not sticky or type(sticky.icons) ~= "table" then
    sticky = { icons = {}, at = GetTime and GetTime() or 0 }
    D.gapSticky[unit] = sticky
  end
  local painted = tonumber(fb._painted) or 0
  -- Same spell already on the row: refresh its timer instead of adding a second icon.
  local n
  for i = 1, #sticky.icons do
    if sticky.icons[i].spellId == row.spellId then
      sticky.icons[i] = row
      n = i
      break
    end
  end
  if not n then
    -- sticky index == slot index (RefreshGapCooldownsOnly maps them 1:1)
    n = math.max(painted, #sticky.icons) + 1
    if n > D.MaxIcons() then
      return false, "row full"
    end
    sticky.icons[n] = row
  end
  local slot = fb.icons[n]
  if not slot or not slot.SetSize then
    return false, "no slot " .. tostring(n)
  end
  local sz, pad = D.MergeRowIconSize(plate, fb)
  local okLay = pcall(function()
    for i = painted + 1, n do
      local s = fb.icons[i]
      if s then
        s:ClearAllPoints() -- OUR slot, anchored to OUR row frame only
        s:SetSize(sz, sz)
        s:SetPoint("LEFT", fb, "LEFT", (i - 1) * (sz + pad), 0)
      end
    end
  end)
  local okVis = pcall(D.ApplyGapAuraVisual, slot, row, tok)
  pcall(slot.Show, slot)
  fb._painted = math.max(painted, n)
  local okShow = pcall(function()
    fb:SetSize(math.max(1, fb._painted * (sz + pad)), sz)
    fb:Show()
  end)
  sticky.at = GetTime and GetTime() or 0
  return true, string.format("slot=%d lay=%s vis=%s show=%s shown=%s", n, tostring(okLay), tostring(okVis),
    tostring(okShow), tostring(fb:IsShown()))
end

local function BareName(name)
  if type(name) ~= "string" or IsSecret(name) then
    return nil
  end
  return (name:match("^([^%-]+)") or name)
end

local function TokenForName(name)
  local want = BareName(name)
  local list = { "target", "mouseover", "focus", "player", "party1", "party2", "party3", "party4" }
  if want and want ~= "" then
    for i = 1, #list do
      local tok = list[i]
      local hit = false
      pcall(function()
        hit = UnitExists(tok) and BareName(UnitName(tok)) == want
      end)
      if hit then
        return tok, "name"
      end
    end
  end
  -- No usable target name (secret / empty / not found): the friendly target, then mouseover.
  for _, tok in ipairs({ "target", "mouseover" }) do
    local hit = false
    pcall(function()
      hit = UnitExists(tok) and UnitIsFriend("player", tok) and not UnitIsUnit(tok, "player")
    end)
    if hit then
      return tok, "guess"
    end
  end
  return nil, "none"
end

--- UNIT_SPELLCAST_SENT (unit, targetName, castGUID, spellID) / UNIT_SPELLCAST_SUCCEEDED (unit, castGUID, spellID)
function D.ClearSentTargets()
  wipe(sentTarget)
end

function D.OnOwnCast(event, unit, a, b, c)
  if unit ~= "player" then
    return
  end
  local combat = InCombatLockdown and InCombatLockdown() and true or false
  if event == "UNIT_SPELLCAST_SENT" then
    -- a = target name, b = castGUID, c = spellID. Keep the name even when the id is unreadable here.
    if b ~= nil and not IsSecret(b) and (IsPowerWordShield(c) or c == nil or IsSecret(c)) then
      sentTarget[b] = (a ~= nil and not IsSecret(a)) and a or false
    end
    return
  end
  if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
    return
  end
  -- a = castGUID, b = spellID
  local guidOk = a ~= nil and not IsSecret(a)
  local targetName = guidOk and sentTarget[a] or nil
  if guidOk then
    sentTarget[a] = nil
  end
  if not IsPowerWordShield(b) then
    return
  end
  local tok, how = TokenForName(targetName or nil)
  D.lastOwnCast = string.format("%s PW:S id=%s sentTarget=%s token=%s(%s)", combat and "COMBAT" or "ooc",
    tostring(b), tostring(targetName), tostring(tok), how)
  if not combat then
    D.lastOwnCast = D.lastOwnCast .. " (out of combat: real aura data is used)"
    return
  end
  if not tok then
    return
  end
  local plate = D.PlateFor(tok)
  if not plate then
    D.lastOwnCast = D.lastOwnCast .. " no plate for token"
    return
  end
  if D.AcOwnsPlate and D.AcOwnsPlate(plate) then
    -- Experimental AuraContainer row: the container shows the real Weakened Soul; no placeholder on the legacy row.
    D.lastOwnCast = D.lastOwnCast .. " (AuraContainer row owns this plate: placeholder skipped)"
    return
  end
  local plateUnit = D.NameplateUnitFor and D.NameplateUnitFor(tok)
  local key = D.OverlayUnitKey and D.OverlayUnitKey(plateUnit, plate)
  local icon
  pcall(function()
    if C_Spell and C_Spell.GetSpellTexture then
      icon = C_Spell.GetSpellTexture(WEAKENED_SOUL)
    end
    if not icon and GetSpellTexture then
      icon = GetSpellTexture(WEAKENED_SOUL)
    end
    if not icon and GetSpellInfo then
      icon = select(3, GetSpellInfo(WEAKENED_SOUL))
    end
  end)
  local now = GetTime and GetTime() or 0
  local row = {
    icon = icon,
    spellId = WEAKENED_SOUL,
    duration = WEAKENED_SOUL_SEC,
    expirationTime = now + WEAKENED_SOUL_SEC,
    isHelpful = false,
    _pbSynthetic = "own cast",
  }
  local okCall, okAppend, why = pcall(D.CombatAppendRow, key, plate, row, tok)
  D.lastOwnCast = D.lastOwnCast .. string.format(" plateUnit=%s key=%s icon=%s appended=%s %s", tostring(plateUnit),
    tostring(key), tostring(icon ~= nil), tostring(okCall and okAppend), tostring(okCall and why or okAppend))
end

--- Native debuffs that appear after our row was anchored (own DoT in combat) grow into it: widen our spacer
--- frame so the row starts right of the last visible native icon. Only our own frame is resized.
function D.AvoidNativeOverlap(fb, plate)
  local sp = fb and fb._pbSpacer
  if not sp or not plate then
    return
  end
  local function num(v)
    return type(v) == "number" and not IsSecret(v)
  end
  local buttons = {}
  pcall(D.CollectPlateDebuffButtons, plate, buttons, 40)
  local _, pad = D.MergeRowIconSize(plate, fb)
  pad = tonumber(pad) or 2
  local need = 0
  pcall(function()
    local s = sp:GetEffectiveScale()
    local base, fT, fB = sp:GetLeft(), fb:GetTop(), fb:GetBottom()
    if not (num(s) and num(base) and num(fT) and num(fB)) then
      return
    end
    base, fT, fB = base * s, fT * fb:GetEffectiveScale(), fB * fb:GetEffectiveScale()
    for i = 1, #buttons do
      local btn = buttons[i]
      local vis, a = false, 0
      pcall(function()
        vis = btn:IsVisible()
        a = btn:GetAlpha()
      end)
      if vis == true and num(a) and a > 0.05 then
        local bs = btn:GetEffectiveScale()
        local r, t, b = btn:GetRight(), btn:GetTop(), btn:GetBottom()
        if num(bs) and num(r) and num(t) and num(b) then
          r, t, b = r * bs, t * bs, b * bs
          -- same line as our row, and reaching past where the row starts
          if t > fB + 1 and b < fT - 1 and r > base then
            need = math.max(need, (r - base) / s + pad)
          end
        end
      end
    end
  end)
  local w = math.max(0.01, need)
  if fb._pbShift ~= w then
    pcall(sp.SetWidth, sp, w)
    fb._pbShift = w
  end
end

--- All harmful auras of a unit, one row per aura INSTANCE (so the same spell from two casters = two icons).
--- Returns nil when the client will not give the data (friendly units in combat): the caller keeps what the
--- older collectors produced. Native-visible icons are skipped so they are not drawn twice.
function D.CollectDirectAuras(tok, plate, maxN)
  if type(tok) ~= "string" or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
    return nil
  end
  local nativeKeys = D.NativeShownKeySet and D.NativeShownKeySet(plate) or {}
  local rows, seen = {}, {}
  for i = 1, 40 do
    local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, tok, i, "HARMFUL")
    if not ok then
      return nil
    end
    if type(d) ~= "table" then
      break
    end
    local row = {
      icon = d.icon,
      spellId = d.spellId,
      auraInstanceID = d.auraInstanceID,
      applications = d.applications,
      expirationTime = d.expirationTime,
      duration = d.duration,
      isHelpful = false,
      _pbDirect = d,
    }
    local key = D.AuraDedupeKey(d, d.icon)
    local ck = D.CanonicalGapKey(row)
    if not ((ck and nativeKeys[ck]) or (key and nativeKeys[key]) or (ck and seen[ck])) then
      if ck then
        seen[ck] = true
      end
      rows[#rows + 1] = row
      if #rows >= (maxN or 12) then
        break
      end
    end
  end
  return rows
end
