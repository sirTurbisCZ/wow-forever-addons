--[[
  Wayfarer.ProcHUD — procs and time-based triggers of the player's own class (mage: meter + procs; shaman, druid, priest, warlock: proc icons).
  - Arcane Blast meter: pips + timer. In combat the player's own aura stacks may be secret, so the count is
    predicted from UNIT_SPELLCAST_SUCCEEDED and re-synced from the real aura whenever it is readable.
  - At max stacks: pulse + "dump" hint (Arcane Wrath / Arcane Missiles icons, optional action button glow).
  - Proc icons (Clearcasting, Missile Barrage, Presence of Mind) from a per-class whitelist; every spell id is
    verified at runtime and unknown ids are skipped.
  Own frames only, parented and anchored to UIParent. Blizzard frames are only read (action button geometry,
  out of combat), never anchored to or changed. The ticker runs only while the HUD is shown.
  /wf proc help|on|off|test|unlock|lock|reset|status
]]

Wayfarer = Wayfarer or {}
Wayfarer.Modules = Wayfarer.Modules or {}

local Mod = {}
Wayfarer.Modules.ProcHUD = Mod

-- Arcane Blast constants. NOT verified in the Forever client (taken from the old Retinue DecisionAuras):
-- the real duration and refresh rule are learned from the aura whenever it is readable (saved in the profile).
local AB_MAX_STACKS = 4
local AB_WINDOW_DEFAULT = 18 -- seconds; Retinue used 18 s, SoD tooltips say 6 s. The aura duration wins once read.
local AB_REFRESH_ON_CAST_DEFAULT = false -- Retinue: "window from first application, not refreshed"
local TICK = 0.1
local UNLOCK_MAX_SEC = 90 -- unlocked HUD locks itself again
local ABSENT_SEC = 3 -- aura missing this long (in combat) = stacks are gone
local TEST_MAX_SEC = 30 -- test mode switches itself off
local TEST_STEP = 1.2 -- seconds per fake stack in test mode
local ICON_SIZE, PIP_W, PIP_H, PIP_GAP = 28, 18, 10, 3

local COLOR_PIP_EMPTY = { 0.22, 0.22, 0.26 }
local COLOR_PIP_ON = { 0.45, 0.75, 1.00 }
local COLOR_PIP_MAX = { 1.00, 0.82, 0.20 }
local COLOR_PIP_INCOMING = { 0.45, 0.75, 1.00, 0.35 } -- the next stack while its cast is running

--[[
  Per-class whitelist. kind:
    "stacks" — stacking aura built by casts (meter); ids = cast spell ids (ranks), auras = aura ids
    "proc"   — aura shown as an icon while present; glow = key of a "dump" entry to highlight
    "dump"   — spender shown / highlighted at max stacks of the "stacks" entry (ids = ranks)
  Ids come from the old Retinue (Forever ranks). Each id is checked with C_Spell.GetSpellInfo at runtime.
]]
local TRIGGERS = {
  MAGE = {
    {
      key = "arcaneBlast", kind = "stacks", name = "Arcane Blast", spellID = 400574,
      ids = { 30451, 1239700, 1239699, 1239697, 1239696, 400574 },
      auras = { 36032, 400573, 400586 },
      maxStacks = AB_MAX_STACKS, dump = { "arcaneWrath", "arcaneMissiles" },
    },
    {
      key = "arcaneMissiles", kind = "dump", name = "Arcane Missiles", spellID = 5143,
      ids = { 25345, 10212, 10211, 8417, 8416, 5145, 5144, 5143 },
    },
    -- Arcane Wrath (talent, 3.5 s cast, 6 s cooldown): the spender to use at max stacks on WoW Forever (id seen in game).
    { key = "arcaneWrath", kind = "dump", name = "Arcane Wrath", spellID = 1326079, ids = { 1326079 } },
    {
      -- the free-cast buff of the Arcane Concentration talent (Forever shows it as Clearcasting / Arcane Concentration)
      key = "clearcasting", kind = "proc", name = "Clearcasting", spellID = 12536, auras = { 12536 },
      names = { "Clearcasting", "Arcane Concentration", "Jasn\195\161 mysl", "Ark\195\161nn\195\173 koncentrace" },
    },
    {
      -- names: the aura is also found by name (ids differ between client builds; English and Czech client text)
      key = "missileBarrage", kind = "proc", name = "Missile Barrage", spellID = 400589, auras = { 400589 },
      names = { "Missile Barrage", "Palba st\197\153el" }, glow = "arcaneMissiles",
    },
    { key = "presenceOfMind", kind = "proc", name = "Presence of Mind", spellID = 12043, auras = { 12043 } },
  },
  -- Presence-only proc icons (#34). Aura ids are UNVERIFIED (from memory); the name list (English + Czech client
  -- text) is the fallback, so a wrong id is harmless. Names confirmed on Forever (ForeverDB talents/coach data).
  SHAMAN = {
    {
      key = "elementalFocus", kind = "proc", name = "Clearcasting", spellID = 16246, auras = { 16246 },
      names = { "Elemental Focus", "Jasn\195\161 mysl", "\197\189iveln\195\169 soust\197\153ed\196\155n\195\173" },
    },
    {
      key = "flurry", kind = "proc", name = "Flurry", spellID = 16257, auras = { 16257, 16277, 16278, 16279, 16280 },
      names = { "P\197\153\195\173val" },
    },
    {
      key = "naturesSwiftness", kind = "proc", name = "Nature's Swiftness", spellID = 16188, auras = { 16188 },
      names = { "Rychlost p\197\153\195\173rody" },
    },
  },
  DRUID = {
    {
      key = "clearcasting", kind = "proc", name = "Clearcasting", spellID = 16870, auras = { 16870 },
      names = { "Omen of Clarity", "Jasn\195\161 mysl", "Znamen\195\173 jasnosti" },
    },
    {
      key = "naturesGrace", kind = "proc", name = "Nature's Grace", spellID = 16886, auras = { 16886 },
      names = { "Milost p\197\153\195\173rody" },
    },
    {
      key = "naturesSwiftness", kind = "proc", name = "Nature's Swiftness", spellID = 17116, auras = { 17116 },
      names = { "Rychlost p\197\153\195\173rody" },
    },
  },
  PRIEST = {
    {
      key = "innerFocus", kind = "proc", name = "Inner Focus", spellID = 14751, auras = { 14751 },
      names = { "Vnit\197\153n\195\173 soust\197\153ed\196\155n\195\173" },
    },
    {
      key = "spiritTap", kind = "proc", name = "Spirit Tap", spellID = 15271, auras = { 15271 },
      names = { "\196\140erp\195\161n\195\173 ducha" },
    },
    {
      key = "powerInfusion", kind = "proc", name = "Power Infusion", spellID = 10060, auras = { 10060 },
      names = { "P\197\153\195\173liv moci" },
    },
  },
  WARLOCK = {
    {
      key = "shadowTrance", kind = "proc", name = "Shadow Trance", spellID = 17941, auras = { 17941 },
      names = { "Nightfall", "St\195\173nov\195\189 trans" },
    },
  },
}
Mod.TRIGGERS = TRIGGERS

local BAR_PREFIXES = {
  "ActionButton", "BonusActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
  "MultiBarRightButton", "MultiBarLeftButton",
}

local started = false
local active = false
local whyInactive = "not started"
local classFile
local eventFrame, root, meter, ticker
local procIcons, dumpIcons, glows = {}, {}, {}
local entries = {} -- verified entries of the player's class
local byKey = {}
local stacksEntry -- the verified "stacks" entry or nil
local castIds, castNames = {}, {} -- for the stacks entry
local buttonCache = {} -- { { cx, cy, size, ids = {[spellID]=true}, name = spellName } } (UIParent coords)
local buttonsDirty = true
local test = { on = false, start = 0 }
local ab = { stacks = 0, expires = 0, source = "none", auraExp = nil, auraStacks = nil, pendingCheck = nil }
local seenAuraInCombat = false
local debugOn = false
local dbg = { casts = 0, matched = 0, lastId = nil, lastName = nil, auraSeen = false, starts = 0, startMatched = 0,
  startUnreadable = 0, lastStartName = nil }
local unlockedAt
local lastTrace

local function Cfg()
  return Wayfarer.Config.GetProfile().procHUD
end

local function IsSecret(v)
  return issecretvalue and issecretvalue(v) or false
end

local function Num(v)
  if type(v) ~= "number" or IsSecret(v) then
    return nil
  end
  return v
end

local function Str(v)
  if type(v) ~= "string" or IsSecret(v) then
    return nil
  end
  return v
end

local function InCombat()
  if InCombatLockdown and InCombatLockdown() then
    return true
  end
  local ok, v = pcall(UnitAffectingCombat, "player")
  return ok and not IsSecret(v) and v and true or false
end

local function Now()
  return GetTime and GetTime() or 0
end

local function Report(context, err)
  if Wayfarer.RecordError then
    Wayfarer.RecordError("prochud:" .. tostring(context), err)
  end
end

local function Guard(context, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    Report(context, err)
  end
end

--- name, icon of a spell id, or nil when the client does not know it.
local function SpellInfo(id)
  local name, icon
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, id)
    if ok and type(info) == "table" then
      name, icon = Str(info.name), info.iconID or info.originalIconID
    end
  end
  if not name and GetSpellInfo then
    local ok, n, _, ic = pcall(GetSpellInfo, id)
    if ok then
      name, icon = Str(n), ic
    end
  end
  if name and not icon and C_Spell and C_Spell.GetSpellTexture then
    local ok, tex = pcall(C_Spell.GetSpellTexture, id)
    if ok then
      icon = tex
    end
  end
  if IsSecret(icon) then
    icon = nil
  end
  return name, icon
end

local AURA_FILTERS = { "HELPFUL", "HARMFUL" }

--- Aura data of the first present aura id (table, id) or nil. Presence is trusted; fields may be secret.
local function ReadAura(ids, auraName)
  local names = type(auraName) == "table" and auraName or (auraName and { auraName }) or nil
  auraName = nil
  if not ids then
    return nil
  end
  for i = 1, #ids do
    local id = ids[i]
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
      local ok, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
      if ok and type(data) == "table" then
        return data, id
      end
    elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      for _, filter in ipairs(AURA_FILTERS) do
        for n = 1, 40 do
          local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", n, filter)
          if not ok or type(data) ~= "table" then
            break
          end
          if Num(data.spellId) == id then
            return data, id
          end
        end
      end
    end
  end
  if names and #names > 0 and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    -- ids differ between client builds: fall back to the aura name
    for _, filter in ipairs(AURA_FILTERS) do
      for n = 1, 40 do
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", n, filter)
        if not ok or type(data) ~= "table" then
          break
        end
        local nm = Str(data.name)
        if nm then
          for k = 1, #names do
            if nm == names[k] then
              return data, Num(data.spellId)
            end
          end
        end
      end
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Trigger verification
-- ---------------------------------------------------------------------------

local function VerifyTriggers()
  entries, byKey, stacksEntry, castIds, castNames = {}, {}, nil, {}, {}
  local list = classFile and TRIGGERS[classFile]
  if not list then
    return 0, 0
  end
  local total = #list
  for i = 1, total do
    local t = list[i]
    local e = { key = t.key, kind = t.kind, name = t.name, ids = {}, auras = {}, maxStacks = t.maxStacks,
      dump = t.dump, glow = t.glow, names = {} }
    if t.kind == "proc" then
      e.names[1] = t.name
      for _, nm in ipairs(t.names or {}) do
        e.names[#e.names + 1] = nm
      end
    end
    for _, id in ipairs(t.ids or {}) do
      local n, ic = SpellInfo(id)
      if n then
        e.ids[#e.ids + 1] = id
        e.localName = e.localName or n
        e.icon = e.icon or ic
      end
    end
    for _, id in ipairs(t.auras or {}) do
      local n, ic = SpellInfo(id)
      if n then
        e.auras[#e.auras + 1] = id
        e.localName = e.localName or n
        e.icon = e.icon or ic
      end
    end
    if not e.icon and t.spellID then
      local _, ic = SpellInfo(t.spellID)
      e.icon = ic
    end
    if (e.kind == "stacks" or e.kind == "proc") and #e.auras == 0 and t.auras then
      -- aura spells are often hidden from spell lookups; the cast ids decide, the aura is read by id or name
      for _, id in ipairs(t.auras) do
        e.auras[#e.auras + 1] = id
      end
    end
    if e.kind == "proc" and e.localName then
      e.names[#e.names + 1] = e.localName
    end
    local usable = (e.kind == "dump" and #e.ids > 0) or (e.kind == "proc" and (#e.auras > 0 or #e.names > 0))
      or (e.kind == "stacks" and #e.ids > 0 and #e.auras > 0)
    if usable then
      e.icon = e.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
      entries[#entries + 1] = e
      byKey[e.key] = e
      if e.kind == "stacks" and not stacksEntry then
        stacksEntry = e
        for _, id in ipairs(e.ids) do
          castIds[id] = true
        end
        if e.localName then
          castNames[e.localName] = true
        end
      end
    end
  end
  return #entries, total
end

-- ---------------------------------------------------------------------------
-- Arcane Blast state (prediction + re-sync)
-- ---------------------------------------------------------------------------

local function Window()
  return Num(Cfg().abWindow) or AB_WINDOW_DEFAULT
end

local function RefreshOnCast()
  local v = Cfg().abRefresh
  if v == nil then
    return AB_REFRESH_ON_CAST_DEFAULT
  end
  return v and true or false
end

local function MaxStacks()
  return (stacksEntry and stacksEntry.maxStacks) or AB_MAX_STACKS
end

-- The stack aura is applied when the cast finishes: while the next Arcane Blast is being cast its pip is shown dimmed.
-- incoming = time the cast started (cleared on success / stop / failure; a stuck value ends after INCOMING_MAX seconds).
local incoming
local INCOMING_MAX = 6

local function ClearAB()
  ab.stacks, ab.expires, ab.source, ab.auraExp, ab.auraStacks, ab.pendingCheck, ab.absentSince = 0, 0, "none", nil, nil, nil, nil
end

local function NoteCast()
  local now = Now()
  if ab.stacks <= 0 or now >= ab.expires then
    ab.stacks = 1
    ab.expires = now + Window()
  else
    ab.stacks = math.min(MaxStacks(), ab.stacks + 1)
    if RefreshOnCast() then
      ab.expires = now + Window()
    end
  end
  ab.source = "predict"
  ab.lastCast = now
  -- remember the last readable aura so the next readable sync can learn whether casts refresh the timer
  if ab.auraExp and ab.auraStacks and ab.auraStacks < MaxStacks() then
    ab.pendingCheck = { exp = ab.auraExp, stacks = ab.auraStacks, at = now }
  end
end

local function Trace(msg)
  if debugOn and msg ~= lastTrace then
    lastTrace = msg
    Wayfarer.Print("procs debug: " .. msg)
  end
end

local function SyncAB()
  if not stacksEntry then
    ClearAB()
    return
  end
  local now = Now()
  if ab.stacks > 0 and ab.expires > 0 and now >= ab.expires then
    ClearAB()
  end
  local data = ReadAura(stacksEntry.auras, stacksEntry.localName)
  if ab.stacks > 0 and (now - (ab.lastCast or 0)) < 1.5 and not data then
    return -- just cast: give the aura time to appear before trusting its absence
  end
  if data then
    -- the aura can linger in the list for a moment after it ran out: an expiry in the past means "gone",
    -- never "start a new window"
    local rawExp = Num(data.expirationTime)
    if rawExp and rawExp > 0 and rawExp <= now + 0.05 then
      data = nil
      if ab.stacks > 0 then
        ClearAB()
      end
    end
  end
  local combat = InCombat()
  Trace(string.format("sync aura=%s apps=%s dur=%s combat=%s predicted=%d",
    tostring(data ~= nil), tostring(data and Num(data.applications)), tostring(data and Num(data.duration)),
    tostring(combat), ab.stacks))
  if data then
    ab.absentSince = nil
    dbg.auraSeen = true
    if combat then
      seenAuraInCombat = true
    end
    local apps = Num(data.applications)
    local exp = Num(data.expirationTime)
    local dur = Num(data.duration)
    if exp and exp <= now + 0.05 then
      exp = nil -- stale or "no expiry" value: ignore it, keep the predicted window
    end
    if dur and dur > 0 then
      Cfg().abWindow = dur -- learned real window
    end
    if apps then
      local stacks = math.min(MaxStacks(), math.max(1, apps))
      local pc = ab.pendingCheck
      if pc and exp and stacks > pc.stacks then
        Cfg().abRefresh = exp > pc.exp + 0.25
        ab.pendingCheck = nil
      end
      ab.stacks = stacks
      if exp and exp > 0 then
        ab.expires = exp
      elseif ab.expires <= now then
        ab.expires = now + Window()
      end
      ab.auraExp, ab.auraStacks = exp, stacks
      ab.source = "aura"
    else
      -- present but secret: keep the prediction, at least one stack
      if ab.stacks <= 0 then
        ab.stacks = 1
        ab.expires = now + Window()
      end
      if exp and exp > 0 then
        ab.expires = exp
      end
      ab.source = "predict"
    end
    return
  end
  -- no aura: gone for sure out of combat, or in combat once lookups proved to work in this fight
  -- A missing aura never clears the meter: on this client the aura read is unreliable (also out of combat, e.g.
  -- right after the target died) while the buff is still there. The stacks end with the 18 s window instead
  -- (counted from the first cast, see above); whenever the aura is readable the real values win.
end

-- ---------------------------------------------------------------------------
-- Action button overlay (own frames on UIParent at the button's screen position)
-- ---------------------------------------------------------------------------

local function ScanButtons()
  if InCombatLockdown and InCombatLockdown() then
    buttonsDirty = true
    return
  end
  buttonsDirty = false
  buttonCache = {}
  if not (UIParent and GetActionInfo) then
    return
  end
  local us = Num(UIParent:GetEffectiveScale())
  if not us or us <= 0 then
    return
  end
  for p = 1, #BAR_PREFIXES do
    for i = 1, 12 do
      local btn = _G[BAR_PREFIXES[p] .. i]
      if btn then
        pcall(function()
          if not btn:IsVisible() then
            return
          end
          local action = Num(btn.action)
          if not action then
            return
          end
          local kind, id = GetActionInfo(action)
          id = Num(id)
          if kind ~= "spell" or not id then
            return
          end
          local cx, cy = btn:GetCenter()
          local w, bs = Num(btn:GetWidth()), Num(btn:GetEffectiveScale())
          cx, cy = Num(cx), Num(cy)
          if not (cx and cy and w and bs) then
            return
          end
          local name = SpellInfo(id)
          buttonCache[#buttonCache + 1] = { cx = cx * bs / us, cy = cy * bs / us, size = w * bs / us, id = id, name = name }
        end)
      end
    end
  end
end

local function GlowFrame(i)
  local g = glows[i]
  if g then
    return g
  end
  g = CreateFrame("Frame", nil, UIParent)
  g:SetFrameStrata("HIGH")
  g:EnableMouse(false)
  g.tex = g:CreateTexture(nil, "OVERLAY")
  g.tex:SetPoint("TOPLEFT", -8, 8)
  g.tex:SetPoint("BOTTOMRIGHT", 8, -8)
  g.tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  g.tex:SetBlendMode("ADD")
  g:Hide()
  glows[i] = g
  return g
end

--- Rebuild the button cache now when it is stale, glow is on and we are not in lockdown.
local function MaybeScan()
  if buttonsDirty and active and Cfg().actionGlow then
    ScanButtons()
  end
end

local function HideGlows()
  for i = 1, #glows do
    glows[i]:Hide()
  end
end

--- Glow every cached button whose spell belongs to one of the given entries.
local function ShowGlows(list)
  local n = 0
  if buttonsDirty then
    ScanButtons()
  end
  for _, b in ipairs(buttonCache) do
    for _, e in ipairs(list) do
      local hit = (b.name and b.name == e.localName)
      if not hit then
        for _, id in ipairs(e.ids) do
          if id == b.id then
            hit = true
          end
        end
      end
      if hit then
        n = n + 1
        local g = GlowFrame(n)
        g:ClearAllPoints()
        g:SetPoint("CENTER", UIParent, "BOTTOMLEFT", b.cx, b.cy)
        g:SetSize(b.size, b.size)
        local c = e.glowColor or COLOR_PIP_MAX
        g.tex:SetVertexColor(c[1], c[2], c[3], 1)
        g:Show()
        break
      end
    end
  end
  for i = n + 1, #glows do
    glows[i]:Hide()
  end
end

-- ---------------------------------------------------------------------------
-- HUD frames
-- ---------------------------------------------------------------------------

local function SavePosition()
  if not root then
    return
  end
  local cx, cy = root:GetCenter()
  local ux, uy = UIParent:GetCenter()
  local rs, us = Num(root:GetEffectiveScale()), Num(UIParent:GetEffectiveScale())
  cx, cy, ux, uy = Num(cx), Num(cy), Num(ux), Num(uy)
  if not (cx and cy and ux and uy and rs and us and us > 0) then
    return
  end
  local cfg = Cfg()
  cfg.x = math.floor((cx * rs - ux * us) / us + 0.5)
  cfg.y = math.floor((cy * rs - uy * us) / us + 0.5)
end

local function Place()
  if not root then
    return
  end
  local cfg = Cfg()
  local scale = math.max(50, math.min(200, tonumber(cfg.scale) or 100)) / 100
  root:SetScale(scale)
  root:ClearAllPoints()
  root:SetPoint("CENTER", UIParent, "CENTER", (tonumber(cfg.x) or 0) / scale, (tonumber(cfg.y) or 0) / scale)
end

local function MakeIcon(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f:EnableMouse(false)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(0, 0, 0, 0.8)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetPoint("TOPLEFT", 1, -1)
  f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local ok, cd = pcall(CreateFrame, "Cooldown", nil, f, "CooldownFrameTemplate")
  if ok and cd then
    cd:SetAllPoints(f.icon)
    pcall(cd.SetDrawEdge, cd, false)
    pcall(cd.SetHideCountdownNumbers, cd, true)
    f.cd = cd
  end
  f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  f.count:SetPoint("BOTTOMRIGHT", -1, 1)
  f:Hide()
  return f
end

local function BuildHUD()
  if root then
    return root
  end
  root = CreateFrame("Frame", "WayfarerProcHUD", UIParent)
  root:SetSize(PIP_W * AB_MAX_STACKS + PIP_GAP * 3 + 40, PIP_H + 8)
  root:SetFrameStrata("MEDIUM")
  root:SetClampedToScreen(true)
  root:SetMovable(true)
  root:EnableMouse(false)
  root:RegisterForDrag("LeftButton")
  root:SetScript("OnDragStart", function(self)
    Guard("drag", function()
      if not Cfg().locked then
        self:StartMoving()
      end
    end)
  end)
  root:SetScript("OnDragStop", function(self)
    Guard("drag", function()
      self:StopMovingOrSizing()
      SavePosition()
      Place()
    end)
  end)
  root.bg = root:CreateTexture(nil, "BACKGROUND")
  root.bg:SetAllPoints()
  root.bg:SetColorTexture(0.1, 0.4, 0.9, 0.25)
  root.label = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  root.label:SetPoint("BOTTOM", root, "TOP", 0, 2)
  root.label:SetText("")

  meter = CreateFrame("Frame", nil, root)
  meter:SetPoint("TOPLEFT", 0, 0)
  meter:SetSize(PIP_W * AB_MAX_STACKS + PIP_GAP * (AB_MAX_STACKS - 1) + 40, PIP_H + 8)
  meter.bg = meter:CreateTexture(nil, "BACKGROUND")
  meter.bg:SetAllPoints()
  meter.bg:SetColorTexture(0, 0, 0, 0.55)
  meter.pips = {}
  for i = 1, AB_MAX_STACKS do
    local pip = meter:CreateTexture(nil, "ARTWORK")
    pip:SetSize(PIP_W, PIP_H)
    pip:SetPoint("LEFT", meter, "LEFT", 4 + (i - 1) * (PIP_W + PIP_GAP), 0)
    pip:SetColorTexture(COLOR_PIP_EMPTY[1], COLOR_PIP_EMPTY[2], COLOR_PIP_EMPTY[3], 1)
    meter.pips[i] = pip
  end
  meter.timer = meter:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  meter.timer:SetPoint("RIGHT", meter, "RIGHT", -4, 0)
  meter.glow = meter:CreateTexture(nil, "OVERLAY")
  meter.glow:SetPoint("TOPLEFT", -4, 4)
  meter.glow:SetPoint("BOTTOMRIGHT", 4, -4)
  meter.glow:SetColorTexture(COLOR_PIP_MAX[1], COLOR_PIP_MAX[2], COLOR_PIP_MAX[3], 0.35)
  meter.glow:SetBlendMode("ADD")
  meter.glow:Hide()
  if meter.glow.CreateAnimationGroup then
    local ok = pcall(function()
      local ag = meter.glow:CreateAnimationGroup()
      ag:SetLooping("BOUNCE")
      local a = ag:CreateAnimation("Alpha")
      a:SetFromAlpha(1)
      a:SetToAlpha(0.25)
      a:SetDuration(0.45)
      meter.pulse = ag
    end)
    if not ok then
      meter.pulse = nil
    end
  end
  meter.dumpLabel = meter:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  meter.dumpLabel:SetPoint("LEFT", meter, "RIGHT", 6 + 2 * 24, 0)
  meter.dumpLabel:SetTextColor(COLOR_PIP_MAX[1], COLOR_PIP_MAX[2], COLOR_PIP_MAX[3])
  meter.dumpLabel:SetText("dump")
  meter.dumpLabel:Hide()
  for i = 1, 2 do
    local d = MakeIcon(meter, 22)
    d:SetPoint("LEFT", meter, "RIGHT", 4 + (i - 1) * 24, 0)
    dumpIcons[i] = d
  end
  root:Hide()
  Place()
  return root
end

local function SetPip(i, c)
  meter.pips[i]:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

--- Is the dump spell worth showing right now? Wrath: off cooldown (secret = assume ready). Missiles: only with a
--- Missile Barrage proc up (the proc icon itself is shown separately).
local function DumpUsable(e, procs)
  if e.key == "arcaneMissiles" then
    for _, p in ipairs(procs or {}) do
      if p.e.key == "missileBarrage" then
        return true
      end
    end
    return false
  end
  local id = e.ids[1]
  if id and C_Spell and C_Spell.GetSpellCooldown then
    local ok, cd = pcall(C_Spell.GetSpellCooldown, id)
    if ok and type(cd) == "table" then
      local dur, start = Num(cd.duration), Num(cd.startTime)
      if dur and start and dur > 1.6 and start + dur > Now() then
        return false
      end
    end
  end
  return true
end

local function RenderMeter(stacks, remain, show, procs, upcoming)
  if not show then
    meter:Hide()
    return false
  end
  local maxS = MaxStacks()
  for i = 1, AB_MAX_STACKS do
    if i > maxS then
      meter.pips[i]:Hide()
    else
      meter.pips[i]:Show()
      if i <= stacks then
        SetPip(i, stacks >= maxS and COLOR_PIP_MAX or COLOR_PIP_ON)
      elseif upcoming and i == stacks + 1 then
        SetPip(i, COLOR_PIP_INCOMING)
      else
        SetPip(i, COLOR_PIP_EMPTY)
      end
    end
  end
  meter.timer:SetText(remain and remain > 0 and string.format("%.1f", remain) or "")
  local maxed = stacks >= maxS
  meter.glow:SetShown(maxed)
  if meter.pulse then
    if maxed and not meter.pulse:IsPlaying() then
      meter.pulse:Play()
    elseif not maxed and meter.pulse:IsPlaying() then
      meter.pulse:Stop()
    end
  end
  local cfg = Cfg()
  local n = 0
  local dumps = {}
  if maxed and cfg.dumpHint ~= false and stacksEntry and stacksEntry.dump then
    for _, k in ipairs(stacksEntry.dump) do
      local e = byKey[k]
      if e and n < #dumpIcons and DumpUsable(e, procs) then
        n = n + 1
        dumpIcons[n].icon:SetTexture(e.icon)
        dumpIcons[n]:Show()
        dumps[#dumps + 1] = e
      end
    end
  end
  for i = n + 1, #dumpIcons do
    dumpIcons[i]:Hide()
  end
  meter.dumpLabel:SetShown(n > 0)
  meter:Show()
  return true, dumps
end

local function ProcIcon(i)
  if not procIcons[i] then
    procIcons[i] = MakeIcon(root, ICON_SIZE)
  end
  return procIcons[i]
end

--- Show the given proc list ({ e = entry, data = aura data or nil }) below the meter.
local function RenderProcs(list, below)
  local y = below and -(PIP_H + 8 + 4) or 0
  for i = 1, #list do
    local f = ProcIcon(i)
    local e, data = list[i].e, list[i].data
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", root, "TOPLEFT", (i - 1) * (ICON_SIZE + 4), y)
    local tex = e.icon
    if (not tex or tex == "Interface\\Icons\\INV_Misc_QuestionMark") and data then
      local ic = data.icon
      if ic and not IsSecret(ic) then
        tex = ic
      end
    end
    f.icon:SetTexture(tex)
    local apps = data and Num(data.applications)
    f.count:SetText(apps and apps > 1 and tostring(apps) or "")
    if f.cd then
      local exp, dur = data and Num(data.expirationTime), data and Num(data.duration)
      if exp and dur and dur > 0 and exp > 0 then
        pcall(f.cd.SetCooldown, f.cd, exp - dur, dur)
      else
        pcall(f.cd.Clear, f.cd)
      end
    end
    f:Show()
  end
  for i = #list + 1, #procIcons do
    procIcons[i]:Hide()
  end
  return #list
end

-- ---------------------------------------------------------------------------
-- Update loop
-- ---------------------------------------------------------------------------

local Update, RefreshSettings -- forward

local function StopTicker()
  if ticker then
    ticker:Cancel()
    ticker = nil
  end
end

local function StartTicker()
  if ticker or not (C_Timer and C_Timer.NewTicker) then
    return
  end
  ticker = C_Timer.NewTicker(TICK, function()
    Guard("tick", Update)
  end)
end

local function HideAll()
  StopTicker()
  HideGlows()
  if root then
    if meter and meter.pulse and meter.pulse:IsPlaying() then
      meter.pulse:Stop()
    end
    root:Hide()
  end
end

Update = function()
  local cfg = Cfg()
  if not active then
    HideAll()
    return
  end
  BuildHUD()
  if cfg.locked == false and unlockedAt and Now() - unlockedAt > UNLOCK_MAX_SEC then
    cfg.locked = true
    Wayfarer.Print("procs: HUD locked again")
    RefreshSettings()
  end
  local unlocked = cfg.locked == false
  local stacks, remain = 0, nil
  local procs = {}
  if test.on and Now() - test.start > TEST_MAX_SEC then
    test.on = false
    Wayfarer.Print("procs: test mode ended")
    RefreshSettings()
  end
  if test.on then
    local nProcEntries = 0
    for _, e in ipairs(entries) do
      if e.kind == "proc" then
        nProcEntries = nProcEntries + 1
      end
    end
    local cycle = math.max(MaxStacks(), nProcEntries) + 1
    local step = math.floor((Now() - test.start) / TEST_STEP) % cycle
    stacks = math.min(step, MaxStacks())
    remain = Window() - ((Now() - test.start) % (TEST_STEP * cycle))
    local n = 0
    for _, e in ipairs(entries) do
      if e.kind == "proc" then
        n = n + 1
        if step >= n then -- icons light up one by one with the fake stacks
          procs[#procs + 1] = { e = e }
        end
      end
    end
  else
    SyncAB()
    stacks = ab.stacks
    remain = ab.expires > 0 and (ab.expires - Now()) or nil
    if cfg.procs ~= false then
      for _, e in ipairs(entries) do
        if e.kind == "proc" then
          local data = ReadAura(e.auras, e.names)
          if data then
            procs[#procs + 1] = { e = e, data = data }
          end
        end
      end
    end
  end
  if incoming and Now() - incoming > INCOMING_MAX then
    incoming = nil
  end
  local upcoming = incoming and cfg.upcoming ~= false and not test.on and stacks < MaxStacks()
  local meterOn = cfg.meter ~= false and stacksEntry ~= nil and (stacks > 0 or upcoming or test.on or unlocked)
  local shown, dumps = RenderMeter(stacks, remain, meterOn, procs, upcoming)
  local nProcs = RenderProcs(cfg.procs ~= false and procs or {}, shown)
  -- glow targets: dump spenders at max stacks + spenders named by present procs
  local glowList = {}
  if cfg.actionGlow and not test.on then
    for _, e in ipairs(dumps or {}) do
      glowList[#glowList + 1] = e
    end
    for _, p in ipairs(procs) do
      local g = p.e.glow and byKey[p.e.glow]
      if g then
        glowList[#glowList + 1] = g
      end
    end
  end
  if #glowList > 0 then
    ShowGlows(glowList)
  else
    HideGlows()
  end
  local any = shown or nProcs > 0 or unlocked or test.on
  root.bg:SetShown(unlocked)
  root.label:SetShown(unlocked)
  root:EnableMouse(unlocked)
  if any then
    local w = math.max(shown and (meter:GetWidth() or 0) or 0, nProcs * (ICON_SIZE + 4))
    local h = (shown and (PIP_H + 8) or 0) + (nProcs > 0 and (ICON_SIZE + (shown and 4 or 0)) or 0)
    root:SetSize(math.max(w, 40), math.max(h, PIP_H + 8))
    root:Show()
    StartTicker()
  else
    HideAll()
  end
end

local function SafeUpdate()
  Guard("update", Update)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local EVENTS = {
  "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_INTERRUPTED", "UNIT_AURA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
  "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
  "SPELLS_CHANGED",
}

local function IsStacksCast(spellID)
  spellID = Num(spellID)
  if not spellID then
    return false
  end
  if castIds[spellID] then
    return true
  end
  local name = SpellInfo(spellID)
  return name and castNames[name] or false
end

local function OnEvent(_, event, a1, a2, a3)
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    if a1 ~= "player" then
      return
    end
    -- (unit, castGUID, spellID); legacy clients: (unit, spellName, rank)
    local sid = Num(a3) or Num(a2)
    dbg.casts = dbg.casts + 1
    dbg.lastId = sid
    dbg.lastName = sid and SpellInfo(sid) or nil
    if stacksEntry and IsStacksCast(sid) then
      dbg.matched = dbg.matched + 1
    end
    if debugOn then
      Wayfarer.Print(string.format("procs debug: cast id=%s name=%s match=%s", tostring(sid), tostring(sid and SpellInfo(sid)), tostring(IsStacksCast(sid))))
    end
    if stacksEntry and IsStacksCast(sid) then
      incoming = nil
      NoteCast()
      SafeUpdate()
    end
  elseif event == "UNIT_SPELLCAST_START" then
    if a1 ~= "player" or not stacksEntry then
      return
    end
    dbg.starts = dbg.starts + 1
    local sid = Num(a3) or Num(a2)
    local match = sid and IsStacksCast(sid) or false
    if not sid and UnitCastingInfo then
      -- the spell id of the event is unreadable (secret in combat): ask the cast itself (name or spell id)
      local ok, name, _, _, _, _, _, _, _, castSpell = pcall(UnitCastingInfo, "player")
      if ok then
        local nm = Str(name)
        dbg.lastStartName = nm
        if nm and castNames[nm] then
          match = true
        elseif Num(castSpell) then
          match = IsStacksCast(Num(castSpell))
        end
        if not nm and not Num(castSpell) then
          dbg.startUnreadable = dbg.startUnreadable + 1
        end
      end
    end
    if match then
      dbg.startMatched = dbg.startMatched + 1
      incoming = Now()
      SafeUpdate()
    end
  elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
    if a1 == "player" and incoming then
      -- STOP also arrives right after a successful cast: the stack was already counted then
      incoming = nil
      SafeUpdate()
    end
  elseif event == "UNIT_AURA" then
    if a1 == "player" and not ticker then -- the 0.1 s ticker already refreshes while the HUD is shown
      SafeUpdate()
    end
  elseif event == "PLAYER_REGEN_DISABLED" then
    seenAuraInCombat = false
    MaybeScan()
    if test.on then
      test.on = false
      Wayfarer.Print("procs: test mode off (combat)")
    end
    SafeUpdate()
  elseif event == "PLAYER_REGEN_ENABLED" then
    seenAuraInCombat = false
    MaybeScan()
    SafeUpdate()
  elseif event == "SPELLS_CHANGED" then
    Mod.Apply()
  elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR" then
    buttonsDirty = true
    MaybeScan()
  else
    buttonsDirty = true
    MaybeScan()
    SafeUpdate()
  end
end

local function SetEvents(on)
  if not eventFrame then
    return
  end
  if on then
    for _, e in ipairs(EVENTS) do
      if e:find("^UNIT_SPELLCAST_") or e == "UNIT_AURA" then
        if not (eventFrame.RegisterUnitEvent and pcall(eventFrame.RegisterUnitEvent, eventFrame, e, "player")) then
          pcall(eventFrame.RegisterEvent, eventFrame, e)
        end
      else
        pcall(eventFrame.RegisterEvent, eventFrame, e)
      end
    end
  else
    pcall(eventFrame.UnregisterAllEvents, eventFrame)
  end
  -- Always listen: an inactive module ("none of N spells known" while spell data loads) must re-check.
  pcall(eventFrame.RegisterEvent, eventFrame, "SPELLS_CHANGED")
end

-- ---------------------------------------------------------------------------
-- Module API
-- ---------------------------------------------------------------------------

local function ResolveClass()
  local ok, _, f = pcall(UnitClass, "player")
  if ok and Str(f) then
    classFile = f
  end
  return classFile
end

--- Apply the current settings: (de)activate, register events, place and redraw.
function Mod.Apply()
  if not started then
    return
  end
  ResolveClass()
  local cfg = Cfg()
  local n, total = VerifyTriggers()
  if not cfg.enabled then
    active, whyInactive = false, "disabled"
  elseif not classFile then
    active, whyInactive = false, "class unknown"
  elseif not TRIGGERS[classFile] or #TRIGGERS[classFile] == 0 then
    active, whyInactive = false, "no triggers for " .. classFile
  elseif n == 0 then
    active, whyInactive = false, string.format("none of %d %s spells known to this client", total, classFile)
  else
    active, whyInactive = true, nil
  end
  if not active then
    test.on = false
    ClearAB()
  end
  SetEvents(active)
  if root then
    Place()
  end
  if active then
    buttonsDirty = true
    MaybeScan()
  end
  SafeUpdate()
end

function Mod.Start()
  if started then
    return
  end
  started = true
  Cfg().locked = true -- always start locked: the empty bar is only for placing the HUD
  eventFrame = CreateFrame("Frame")
  eventFrame:SetScript("OnEvent", function(self, event, ...)
    local ok, err = pcall(OnEvent, self, event, ...)
    if not ok then
      Report(event, err)
    end
  end)
  Mod.Apply()
end

function Mod.SetTest(on)
  if on and not active then
    Wayfarer.Print("procs: test mode unavailable — " .. tostring(whyInactive))
    test.on = false
    return false
  end
  if on and InCombat() then
    Wayfarer.Print("procs: test mode only out of combat")
    return false
  end
  test.on = on and true or false
  test.start = Now()
  SafeUpdate()
  return test.on
end

function Mod.IsTesting()
  return test.on
end

function Mod.SetLocked(locked)
  Cfg().locked = locked and true or false
  unlockedAt = (not locked) and Now() or nil
  SafeUpdate()
end

function Mod.ResetPosition()
  local d = Wayfarer.Config.ProfileDefaults().procHUD
  local cfg = Cfg()
  cfg.x, cfg.y, cfg.scale = d.x, d.y, d.scale
  Place()
  SafeUpdate()
end

function Mod.Status()
  local cfg = Cfg()
  if not active then
    return string.format("off (%s)", tostring(whyInactive))
  end
  local learned = Num(cfg.abWindow)
  local refresh = cfg.abRefresh
  return string.format(
    "on class=%s triggers=%d meter=%s stacks=%d (%s) window=%.1fs (%s) refresh=%s locked=%s test=%s scale=%d%% | casts seen %d, matched %d, last id=%s name=%s, aura ever read=%s | casts starting %d, matched %d, unreadable %d, last name=%s",
    tostring(classFile), #entries, stacksEntry and (cfg.meter ~= false and "on" or "off") or "n/a", ab.stacks,
    ab.source, Window(), learned and "learned" or "default", refresh == nil and "default-" .. tostring(AB_REFRESH_ON_CAST_DEFAULT) or tostring(refresh),
    tostring(cfg.locked ~= false), tostring(test.on), tonumber(cfg.scale) or 100,
    dbg.casts, dbg.matched, tostring(dbg.lastId), tostring(dbg.lastName), tostring(dbg.auraSeen),
    dbg.starts, dbg.startMatched, dbg.startUnreadable, tostring(dbg.lastStartName))
end

RefreshSettings = function()
  if Wayfarer.Settings and Wayfarer.Settings.Refresh then
    Wayfarer.Settings.Refresh()
  end
end

local HELP = {
  "/wf proc on|off — procs and timers module",
  "/wf proc test — fake 0-4 stacks to place the HUD (again to stop)",
  "/wf proc unlock|lock — drag the HUD / fix it",
  "/wf proc reset — default position and scale",
  "/wf proc status — what is running and why",
  "/wf proc debug — print id and name of each cast (to find the right spell ids)",
  "/wf proc auras — list your current auras with ids",
}

function Mod.Slash(rest)
  rest = (rest or ""):match("^%s*(.-)%s*$") or ""
  local cfg = Cfg()
  local P = Wayfarer.Print
  if rest == "" or rest == "help" then
    for _, l in ipairs(HELP) do
      P(l)
    end
  elseif rest == "on" or rest == "off" then
    cfg.enabled = rest == "on"
    Mod.Apply()
    P("procs: " .. (cfg.enabled and "on" or "off") .. (active and "" or (cfg.enabled and (" — " .. tostring(whyInactive)) or "")))
  elseif rest == "test" then
    local on = Mod.SetTest(not test.on)
    if on then
      P("procs: test mode on (/wf proc test to stop)")
    elseif active then
      P("procs: test mode off")
    end
  elseif rest == "unlock" or rest == "lock" then
    Mod.SetLocked(rest == "lock")
    P(rest == "lock" and "procs: HUD locked" or "procs: HUD unlocked — drag it, then /wf proc lock")
  elseif rest == "reset" then
    Mod.ResetPosition()
    P("procs: position reset")
  elseif rest == "status" then
    P("procs: " .. Mod.Status())
  elseif rest == "debug" then
    debugOn = not debugOn
    P("procs: debug " .. (debugOn and "on — every cast of yours prints id and name (/wf proc debug to stop)" or "off"))
  elseif rest == "auras" then
    local n = 0
    for _, filter in ipairs(AURA_FILTERS) do
      for i = 1, 40 do
        local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
        if not ok or type(d) ~= "table" then
          break
        end
        n = n + 1
        P(string.format("aura %s id=%s name=%s stacks=%s", filter, tostring(Num(d.spellId)), tostring(Str(d.name)), tostring(Num(d.applications))))
      end
    end
    P(string.format("procs: %d auras listed; stacks entry: %s", n, stacksEntry and (stacksEntry.localName or "?") or "none"))
  else
    P("usage: /wf proc on|off|test|unlock|lock|reset|status")
  end
  RefreshSettings()
end

--- Settings section (Settings.lua calls this once with H = helpers); returns the content height.
function Mod.BuildSettings(sec, H)
  local y = 0
  H.Heading(sec, "Procs and timers", y)
  y = y - 30
  H.Check(sec, "Enable procs and timers", y, function()
    return H.Profile().procHUD.enabled
  end, function(on)
    H.Profile().procHUD.enabled = on
    Mod.Apply()
    RefreshSettings()
  end)
  y = y - 28
  H.Check(sec, "Arcane Blast stack meter (mage only)", y, function()
    return H.Profile().procHUD.meter ~= false
  end, function(on)
    H.Profile().procHUD.meter = on
    SafeUpdate()
  end)
  y = y - 28
  H.Check(sec, "Show the next stack dimmed while the cast runs", y, function()
    return H.Profile().procHUD.upcoming ~= false
  end, function(on)
    H.Profile().procHUD.upcoming = on
    SafeUpdate()
  end)
  y = y - 28
  H.Check(sec, "Proc icons (Clearcasting, Missile Barrage, Flurry, ...)", y, function()
    return H.Profile().procHUD.procs ~= false
  end, function(on)
    H.Profile().procHUD.procs = on
    SafeUpdate()
  end)
  y = y - 28
  H.Check(sec, "Dump hint at max stacks (Arcane Wrath, Missiles)", y, function()
    return H.Profile().procHUD.dumpHint ~= false
  end, function(on)
    H.Profile().procHUD.dumpHint = on
    SafeUpdate()
  end)
  y = y - 28
  H.Check(sec, "Glow on action bar buttons (own overlay)", y, function()
    return H.Profile().procHUD.actionGlow and true or false
  end, function(on)
    H.Profile().procHUD.actionGlow = on
    buttonsDirty = true
    MaybeScan()
    SafeUpdate()
  end)
  y = y - 46
  H.Slider(sec, "Scale %", y, 50, 200, function()
    return tonumber(H.Profile().procHUD.scale) or 100
  end, function(v)
    H.Profile().procHUD.scale = v
    Place()
    SafeUpdate()
  end)
  y = y - 40
  H.Check(sec, "Unlock position (drag the HUD)", y, function()
    return not H.Profile().procHUD.locked
  end, function(on)
    Mod.SetLocked(not on)
  end)
  y = y - 28
  H.Check(sec, "Test mode (fake 0-4 stacks, out of combat)", y, function()
    return test.on
  end, function(on)
    Mod.SetTest(on)
    RefreshSettings()
  end)
  y = y - 32
  local btn = CreateFrame("Button", nil, sec, "UIPanelButtonTemplate")
  btn:SetSize(140, 22)
  btn:SetPoint("TOPLEFT", 18, y)
  btn:SetText("Reset position")
  btn:SetScript("OnClick", function()
    Guard("settings reset", function()
      Mod.ResetPosition()
      RefreshSettings()
    end)
  end)
  y = y - 32
  local status = H.Note(sec, "", y)
  H.Register(function()
    status:SetText("Status: " .. Mod.Status())
  end)
  y = y - 30
  H.Note(sec, "Only your own class is tracked. Mage: stack meter, dump hint and proc icons. Shaman, druid, priest and warlock: proc icons only (Clearcasting, Flurry, Nature's Swiftness, Nature's Grace, Inner Focus, Spirit Tap, Power Infusion, Shadow Trance), shown while the buff is up; other classes have nothing and the module stays off. In combat the stack count is predicted from your casts and corrected from the real aura whenever the game lets addons read it. Chat: /wf proc help.", y)
  return -y + 60
end
