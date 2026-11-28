--[[
  Wayfarer.ProcContainer — proc icons drawn by a Blizzard-managed AuraContainer (#47).
  In combat the player's auras are secret on this client, so the addon cannot read them. A container draws icon,
  duration swipe and stack count in C code, so the addon never reads the aura. Pattern: Plateband (verified in
  combat for nameplates) and SKTools party frames. One container, one HELPFUL group, candidate filter
  includeSpellIDs (a set of spell ids); unit "player".
  UNVERIFIED in the game: SetUnit("player") and includeSpellIDs in combat on Forever. Every call is pcall'd; when
  anything is refused the container stays off (IsActive() = false) and ProcHUD keeps its own icons.
  Rules kept from Plateband: no SetTexCoord on the icon, no formatter for the stack count, no SetScript on the
  buttons, no ClearAllPoints and no frame creation in combat, text on a child frame above the cooldown, every
  button initialised once. Only Show / Hide / SetUnit / SetEnabled / UpdateAllAuras are used in combat.
]]

Wayfarer = Wayfarer or {}

local PC = {}
Wayfarer.ProcContainer = PC

local GROUP = "wfProcs"
local UNIT = "player"
local MAX_FRAMES = 8
local SPACING = 4
local TEMPLATES = { "CustomAuraContainerTemplate", "ManagedAuraContainerTemplate" }

local ids, nIds = {}, 0 -- spell id -> true
local api, apiWhy, template = nil, "not probed yet", nil
local c, built, failed -- the container, built ok, reason of a failure (nil = none)
local pending = false -- ids changed in combat: filters re-applied when combat ends
local shown = false
local bound = false -- SetUnit("player") accepted
local lastErr
local buttons, inited, made = {}, {}, 0
local layoutNote = "-"

local function InCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

local function Err(where, err)
  lastErr = tostring(where) .. ": " .. tostring(err):sub(1, 140)
end

--- Does this client have the container type? One hidden probe container, out of combat only.
function PC.Available()
  if api ~= nil then
    return api
  end
  if InCombat() then
    apiWhy = "not probed yet (in combat)"
    return false
  end
  local lastE = "?"
  for i = 1, #TEMPLATES do
    local ok, f = pcall(CreateFrame, "AuraContainer", nil, UIParent, TEMPLATES[i])
    if ok and f and f.AddAuraGroup and f.SetUnit then
      pcall(f.Hide, f)
      api, template, apiWhy = true, TEMPLATES[i], "ok (" .. TEMPLATES[i] .. ")"
      return true
    end
    lastE = ok and (f and "frame has no AddAuraGroup/SetUnit" or "CreateFrame returned nil") or tostring(f)
  end
  api = false
  apiWhy = "no AuraContainer: " .. lastE:sub(1, 120)
  return false
end

-- ---------------------------------------------------------------------------
-- Spell ids
-- ---------------------------------------------------------------------------

local function copyIds()
  local t = {}
  for id in pairs(ids) do
    t[id] = true
  end
  return t
end

--- Push the ids to the container group: out of combat only, otherwise remembered for PC.Flush().
--- Returns "stored" (no container yet: Build uses them), "deferred", "applied" or "failed".
local function applyIds()
  if not (built and c) then
    return "stored"
  end
  if InCombat() then
    pending = true
    return "deferred"
  end
  local ok, err = pcall(c.SetAuraGroupCandidateFilters, c, GROUP, { includeSpellIDs = copyIds() })
  if not ok then
    Err("SetAuraGroupCandidateFilters", err)
    return "failed"
  end
  pending = false
  if c.UpdateAllAuras then
    pcall(c.UpdateAllAuras, c)
  end
  return "applied"
end

function PC.HasId(id)
  return ids[id] == true
end

--- Add one spell id. Returns isNew, state (see applyIds).
function PC.AddId(id)
  if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) then
    return false, "invalid"
  end
  if ids[id] then
    return false, "known"
  end
  ids[id] = true
  nIds = nIds + 1
  return true, applyIds()
end

--- Add many ids (list); applies once. Returns the number of new ids.
function PC.AddIds(list)
  local n = 0
  if type(list) ~= "table" then
    return 0
  end
  for _, id in ipairs(list) do
    if type(id) == "number" and id > 0 and id == math.floor(id) and not ids[id] then
      ids[id] = true
      nIds = nIds + 1
      n = n + 1
    end
  end
  if n > 0 then
    applyIds()
  end
  return n
end

--- Replace the whole id set (set = { [id] = true }).
function PC.SetIds(set)
  ids, nIds = {}, 0
  for id, v in pairs(type(set) == "table" and set or {}) do
    if v and type(id) == "number" and id > 0 then
      ids[id] = true
      nIds = nIds + 1
    end
  end
  return applyIds()
end

function PC.GetIds()
  local list = {}
  for id in pairs(ids) do
    list[#list + 1] = id
  end
  table.sort(list)
  return list
end

--- Call when combat ends: applies ids that changed during combat.
function PC.Flush()
  if pending and built and not InCombat() then
    return applyIds()
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

--- One AuraButton, called by the container (initializeFrame): icon, duration swipe, stack count.
local function initButton(button, size)
  if inited[button] then
    return -- already set up (the container may call initializeFrame again for a reused button)
  end
  inited[button] = true
  made = made + 1
  buttons[#buttons + 1] = button
  local ok, err = pcall(function()
    pcall(button.SetSize, button, size, size)
    if button.SetMouseMotionEnabled then
      pcall(button.SetMouseMotionEnabled, button, false)
    end
    if button.SetMouseClickEnabled then
      pcall(button.SetMouseClickEnabled, button, false)
    end
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button) -- never SetTexCoord (masked icons throw and leave the container empty)
    if button.SetIcon then
      pcall(button.SetIcon, button, icon)
    end
    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button)
    pcall(cd.EnableMouse, cd, false)
    pcall(cd.SetDrawBling, cd, false)
    pcall(cd.SetReverse, cd, true)
    pcall(cd.SetDrawSwipe, cd, true)
    pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0.5)
    pcall(cd.SetHideCountdownNumbers, cd, true)
    cd.noCooldownCount = true
    if button.SetDurationCooldown then
      pcall(button.SetDurationCooldown, button, cd)
      pcall(cd.SetHideCountdownNumbers, cd, true)
    end
    -- Stack count: a font string on a child frame ABOVE the cooldown (a region of the button would sit under it).
    -- Never pass a formatter: the engine would format a secret count in Lua and the container would freeze.
    local over = CreateFrame("Frame", nil, button)
    over:SetAllPoints(button)
    pcall(over.EnableMouse, over, false)
    pcall(function()
      over:SetFrameLevel((cd:GetFrameLevel() or 1) + 5)
    end)
    local count = over:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    if button.SetApplicationCount then
      if not pcall(button.SetApplicationCount, button, count) then
        pcall(button.SetApplicationCount, button, count, {})
      end
    end
  end)
  if not ok then
    Err("initializeFrame", err)
  end
end

local function newContainer(parent)
  local order = { template }
  for i = 1, #TEMPLATES do
    if TEMPLATES[i] ~= template then
      order[#order + 1] = TEMPLATES[i]
    end
  end
  local lastE
  for i = 1, #order do
    local ok, f = pcall(CreateFrame, "AuraContainer", nil, parent, order[i])
    if ok and f and f.AddAuraGroup then
      return f
    end
    lastE = ok and "no container" or f
  end
  return nil, lastE
end

local function fail(why)
  failed = why
  shown = false
  if c then
    pcall(c.Hide, c)
  end
  built = false
  return false, why
end

--- Build the container under `parent`. Out of combat only. opts: size (icon), x, y (TOPLEFT offsets in parent).
--- Returns ok, why.
function PC.Build(parent, opts)
  if built then
    return true
  end
  if failed then
    return false, failed
  end
  if InCombat() then
    return false, "in combat"
  end
  if nIds == 0 then
    return false, "no spell ids"
  end
  if not PC.Available() then
    return fail(apiWhy)
  end
  opts = opts or {}
  local size = tonumber(opts.size) or 28
  local f, e = newContainer(parent)
  if not f then
    return fail("container create failed: " .. tostring(e):sub(1, 100))
  end
  c = f
  -- The template starts enabled; hide it until a unit is bound (visibility gates its events).
  pcall(c.Hide, c)
  pcall(c.SetSize, c, 1, 1)
  pcall(c.EnableMouse, c, false)
  pcall(c.SetPoint, c, "TOPLEFT", parent, "TOPLEFT", tonumber(opts.x) or 0, tonumber(opts.y) or 0)
  pcall(function()
    c:SetFrameLevel((parent:GetFrameLevel() or 1) + 3)
  end)
  if c.SetFlowLayoutAxis and AnchorUtil and AnchorUtil.FlowLayoutAxis then
    pcall(c.SetFlowLayoutAxis, c, AnchorUtil.FlowLayoutAxis.Horizontal)
    pcall(c.SetFlowLayoutAnchorPoint, c, "TOPLEFT")
    if AnchorUtil.FlowDirection then
      pcall(c.SetFlowLayoutGrowthDirection, c, AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    end
  end
  pcall(c.SetFlowLayoutPadding, c, 0, 0, 0, 0)
  -- do NOT add isFromPlayerOrPlayerPet: procs can come from talents or other sources
  local lastE, added
  for li = 1, 2 do
    local layout = { elementWidth = size, elementHeight = size }
    if li == 1 then
      layout.elementSpacing = SPACING
    end
    local ok, err = pcall(c.AddAuraGroup, c, GROUP, "HELPFUL", {
      maxFrameCount = MAX_FRAMES,
      candidateFilters = { includeSpellIDs = copyIds() },
      sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Expiration or nil,
      sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal or nil,
      initializeFrame = function(button)
        initButton(button, size)
      end,
      layout = layout,
    })
    if ok then
      added = true
      layoutNote = li == 1 and "spaced" or "no spacing"
      break
    end
    lastE = err
  end
  if not added then
    return fail("AddAuraGroup refused: " .. tostring(lastE):sub(1, 100))
  end
  if c.SetEnabled then
    pcall(c.SetEnabled, c, true)
  end
  local okU, errU = pcall(c.SetUnit, c, UNIT)
  if not okU then
    return fail("SetUnit(" .. UNIT .. ") refused: " .. tostring(errU):sub(1, 100))
  end
  bound = true
  if c.UpdateAllAuras then
    pcall(c.UpdateAllAuras, c)
  end
  built, pending = true, false
  pcall(c.Show, c)
  shown = true
  return true
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

function PC.IsBuilt()
  return built and true or false
end

--- The container exists and drew nothing wrong so far: ProcHUD lets it draw the proc icons.
function PC.IsActive()
  return built and not failed and true or false
end

function PC.Failed()
  return failed
end

--- Show or hide our own container (allowed in combat). No-op until built.
function PC.SetShown(on)
  if not (built and c) then
    return
  end
  on = on and true or false
  if shown == on then
    return
  end
  shown = on
  pcall(on and c.Show or c.Hide, c)
end

function PC.Hide()
  PC.SetShown(false)
end

--- Bind the player again and ask for a full refresh. Only the calls Plateband also makes in combat.
function PC.Refresh()
  if not (built and c) then
    return false
  end
  if c.SetEnabled then
    pcall(c.SetEnabled, c, true)
  end
  local ok, err = pcall(c.SetUnit, c, UNIT)
  if not ok then
    Err("SetUnit", err)
    return false
  end
  bound = true
  if c.UpdateAllAuras then
    pcall(c.UpdateAllAuras, c)
  end
  return true
end

--- Forget a failure (and the cached "no API") so the next out-of-combat Update builds again.
function PC.Reset()
  failed, lastErr = nil, nil
  if not built then
    api = nil
    c = nil
    bound = false
  end
end

function PC.State()
  if failed or api == false then
    return "unavailable"
  end
  return built and "active" or "not built"
end

--- 'container=<active|unavailable|not built> ids=N unit=player'
function PC.Status()
  return string.format("container=%s ids=%d unit=%s", PC.State(), nIds, bound and UNIT or "-")
end

local function countShown()
  local n = 0
  for i = 1, #buttons do
    local b = buttons[i]
    local ok, v = pcall(function()
      return b:IsShown() == true
    end)
    if ok and v then
      n = n + 1
    end
  end
  return n
end

--- Extra lines for /wf proc diag (the reason when unavailable, buttons made / shown, pending ids, last error).
function PC.Details()
  local lines = {}
  lines[1] = string.format("api=%s group=%s buttons made=%d shown=%d pending=%s%s", apiWhy,
    built and layoutNote or "-", made, countShown(), tostring(pending), failed and (" FAILED: " .. failed) or "")
  if lastErr then
    lines[2] = "last error: " .. lastErr
  end
  return lines
end
