--[[ Plateband — defaults, schemaVersion, migration ]]

Plateband = Plateband or {}

local CURRENT_SCHEMA = 20
local MAX_ERRORS = 40
local MAX_MSG = 2000

Plateband.Config = Plateband.Config or {}
local Config = Plateband.Config

Config.CURRENT_SCHEMA = CURRENT_SCHEMA
Config.MAX_ERRORS = MAX_ERRORS
Config.MAX_MSG = MAX_MSG
Config.VERSION = "0.8.2"

local function ProfileDefaults()
  return {
    enabled = true,
    safeMode = false,
    iconSize = 18,
    maxIcons = 12,
    showBand = true,
    -- 0.1.15: safe beside-native merge default on (schema 6 had opt-in off).
    mergeMissing = true,
    -- 0.2.23: party/friend/player nameplates — same harmful merge as enemies.
    mergeFriendPlates = true,
    -- Repaint non-target plates when their auras change (new HoTs / party DoTs). Off-switch for CPU.
    auraWatchPlates = true,
    -- Hover tooltip on added icons (step 3).
    gapTooltip = true,
    watchOn = false,
    watchInterval = 2,
    chatOnChange = false,
    -- Dev telemetry (PAINT/PLATE trace, CARD export, FELog mirror). OFF for players: `/pb dev on`.
    silentTrace = false,
    paintTraceInCombat = false,
    -- Auto-saved diagnose cards (dev): off by default.
    autoDiag = false,
    -- 0.7.0 EXPERIMENTAL: Blizzard-managed AuraContainer row instead of the collector row (`/pb ac on|off`).
    -- Blizzard AuraContainer row (works for friendly units in combat); falls back to the legacy row when the client lacks it.
    useAuraContainer = true,
    -- 0.8.0: settings window. enemyBuffs off skips the dispellable-buff group.
    enemyBuffs = true,
    minimap = { show = true, angle = 230 },
  }
end

local function Defaults()
  return {
    schemaVersion = CURRENT_SCHEMA,
    profile = ProfileDefaults(),
    errors = {},
    lastDiagnose = nil,
    lastDiag = nil, -- alias
    sessionLog = {
      startedAt = 0,
      lines = {},
      export = "",
    },
    paintTrace = {
      startedAt = 0,
      entries = {},
      export = "",
    },
    lastPaintTrace = nil,
    runtimeVer = { ver = "", at = 0, src = "" },
    -- AuraContainer mode: buff spell ids the container must not show on friendly plates (food/drink, permanent),
    -- learned from readable aura data out of combat. [spellId] = "food" | "permanent".
    acExclude = {},
  }
end

Config.Defaults = Defaults
Config.ProfileDefaults = ProfileDefaults

local function EnsureProfile(db)
  if type(db.profile) ~= "table" then
    db.profile = ProfileDefaults()
    return
  end
  local p = db.profile
  local d = ProfileDefaults()
  for k, v in pairs(d) do
    if p[k] == nil then
      p[k] = v
    end
  end
end

local function EnsureSessionLog(db)
  if type(db.sessionLog) ~= "table" then
    db.sessionLog = {
      startedAt = 0,
      lines = {},
      fileOk = false,
      export = "",
    }
  end
  if type(db.sessionLog.lines) ~= "table" then
    db.sessionLog.lines = {}
  end
end

--- Ensure PlatebandDB exists, migrate schema, return db.
function Config.EnsureDB()
  if type(PlatebandDB) ~= "table" then
    PlatebandDB = Defaults()
    return PlatebandDB
  end

  local db = PlatebandDB
  local from = tonumber(db.schemaVersion) or 0

  if from < 1 then
    EnsureProfile(db)
    if type(db.errors) ~= "table" then
      db.errors = {}
    end
    db.schemaVersion = 1
    from = 1
  end

  if from < 2 then
    EnsureSessionLog(db)
    EnsureProfile(db)
    if db.lastDiagnose == nil and db.lastDiag ~= nil then
      db.lastDiagnose = db.lastDiag
    end
    db.schemaVersion = 2
    from = 2
  end

  if from < 3 then
    EnsureProfile(db)
    -- Kill chat flood from v0.1.1 chatOnChange=true default.
    db.profile.chatOnChange = false
    db.schemaVersion = 3
    from = 3
  end

  if from < 4 then
    EnsureProfile(db)
    -- Solo native-first: never cover name/health with overlay paint.
    db.profile.paintOverlay = false
    db.schemaVersion = 4
    from = 4
  end

  if from < 5 then
    EnsureProfile(db)
    db.profile.paintOverlay = false
    db.profile.mergeMissing = true
    db.schemaVersion = 5
    from = 5
  end

  if from < 6 then
    EnsureProfile(db)
    -- Name mutation broke Forever plates — force native-only until merge is opt-in safe.
    db.profile.paintOverlay = false
    db.profile.mergeMissing = false
    db.schemaVersion = 6
    from = 6
  end

  if from < 7 then
    EnsureProfile(db)
    db.profile.paintOverlay = false
    db.profile.mergeMissing = true
    db.schemaVersion = 7
    from = 7
  end

  if from < 8 then
    EnsureProfile(db)
    if db.profile.silentTrace == nil then
      db.profile.silentTrace = true
    end
    if db.profile.paintTraceOn == nil then
      db.profile.paintTraceOn = true
    end
    db.profile.chatOnChange = false
    if type(db.paintTrace) ~= "table" then
      db.paintTrace = { startedAt = 0, entries = {}, export = "" }
    end
    db.schemaVersion = 8
    from = 8
  end

  if from < 9 then
    EnsureProfile(db)
    if db.profile.mergeFriendPlates == nil then
      db.profile.mergeFriendPlates = true
    end
    db.schemaVersion = 9
    from = 9
  end

  if from < 10 then
    EnsureProfile(db)
    if db.profile.paintTraceInCombat == nil then
      db.profile.paintTraceInCombat = false
    end
    db.schemaVersion = 10
    from = 10
  end

  if from < 11 then
    EnsureProfile(db)
    db.profile.paintTraceOn = false
    if db.profile.autoDiag == nil then
      db.profile.autoDiag = false
    end
    db.schemaVersion = 11
    from = 11
  end

  if from < 12 then
    if type(db.agentLive) ~= "table" then
      db.agentLive = { seq = 0, ver = "", at = 0, io = "sv_only", lines = 0 }
    end
    db.schemaVersion = 12
    from = 12
  end

  if from < 13 then
    EnsureProfile(db)
    if db.profile.hideFriendlyFoodBuffs == nil then
      db.profile.hideFriendlyFoodBuffs = true
    end
    db.schemaVersion = 13
    from = 13
  end

  if from < 14 then
    EnsureProfile(db)
    if db.profile.mergeFriendHelpful == nil then
      db.profile.mergeFriendHelpful = true
    end
    db.schemaVersion = 14
    from = 14
  end

  if from < 15 then
    EnsureProfile(db)
    db.profile.mergeFriendHelpful = false
    db.schemaVersion = 15
    from = 15
  end

  -- 0.4.0: dev telemetry is opt-in; drop dead keys and the undeclared host-script SV keys.
  if from < 16 then
    EnsureProfile(db)
    db.profile.silentTrace = false
    db.profile.autoDiag = false
    db.profile.paintOverlay = nil
    db.profile.paintTraceOn = nil
    for _, k in ipairs({
      "chatTruthLine", "chatTruthAt", "configChatVer", "exportPulseSeq", "exportPulseAt", "exportPulseN",
      "exportUnixEpoch", "exportLoadGt", "ioAllowName", "ioExportDiskLine", "ioExportDiskTried",
      "ioExportDiskVer", "exportIoDiag", "interfacePbVer", "interfaceFeVer", "reloadPending",
      "reloadPendingVer", "telemetryMode", "exportLoginDiskVer", "continuousDiskPulse", "agentLive",
      "liveHead",
    }) do
      db[k] = nil
    end
    if type(db.sessionLog) == "table" then
      db.sessionLog.fileOk = nil
      db.sessionLog.export = ""
    end
    db.schemaVersion = 16
    from = 16
  end

  -- 0.4.1: helpful-gap rules moved to PlatesPolicy.lua; the old switches are gone.
  if from < 17 then
    EnsureProfile(db)
    db.profile.mergeFriendHelpful = nil
    db.profile.hideFriendlyFoodBuffs = nil
    if db.profile.auraWatchPlates == nil then
      db.profile.auraWatchPlates = true
    end
    if db.profile.gapTooltip == nil then
      db.profile.gapTooltip = true
    end
    db.schemaVersion = 17
    from = 17
  end

  -- 0.7.0: experimental AuraContainer row, off by default; learned exclude list for its friendly buff group.
  if from < 18 then
    EnsureProfile(db)
    db.profile.useAuraContainer = false
    if type(db.acExclude) ~= "table" then
      db.acExclude = {}
    end
    db.schemaVersion = 18
    from = 18
  end

  -- 0.7.2: the AuraContainer row becomes the default (verified in game: enemy and friendly plates, in combat).
  if from < 19 then
    EnsureProfile(db)
    db.profile.useAuraContainer = true
    db.schemaVersion = 19
    from = 19
  end

  -- 0.8.0: settings window keys (defaults keep the behaviour unchanged).
  if from < 20 then
    EnsureProfile(db)
    local p = db.profile
    p.enemyDebuffs = nil -- (dropped before release: the client already shows own debuffs by default)
    if type(p.enemyBuffs) ~= "boolean" then
      p.enemyBuffs = true
    end
    if type(p.minimap) ~= "table" then
      p.minimap = { show = true, angle = 230 }
    end
    db.schemaVersion = 20
    from = 20
  end

  EnsureProfile(db)
  EnsureSessionLog(db)
  if type(db.paintTrace) ~= "table" then
    db.paintTrace = { startedAt = 0, entries = {}, export = "" }
  end
  if type(db.errors) ~= "table" then
    db.errors = {}
  end
  if type(db.acExclude) ~= "table" then
    db.acExclude = {}
  end

  return db
end

function Config.Reset()
  PlatebandDB = Defaults()
  return PlatebandDB
end

function Config.GetProfile()
  -- Hot path (dozens of calls per nameplate update): EnsureDB builds the default tables and merges them every time, so
  -- a database that was already ensured (current schema, profile table) is returned directly.
  local db = PlatebandDB
  if type(db) == "table" and type(db.schemaVersion) == "number" and db.schemaVersion >= CURRENT_SCHEMA and type(db.profile) == "table" then
    return db.profile
  end
  return Config.EnsureDB().profile
end
