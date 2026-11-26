--[[ PlatesPaint — PaintMergeMissing in own chunk (WoW 60 upvalue cap). ]]
Plateband = Plateband or {}
local D = Plateband.PlatesPaintDeps
if not D then
  return
end

D.PaintMergeMissing = function(unit, plate)
if not plate then
    D.ClearFallback(unit)
    return 0
  end
  local friendRow = (D.MergeFriendPlatesEnabled and D.MergeFriendPlatesEnabled())
    and (D.IsPlayerOrFriendPlate and D.IsPlayerOrFriendPlate(unit, plate)
      or D.PlateUsesFriendlyHarmfulFilter and D.PlateUsesFriendlyHarmfulFilter(plate))
  local parent = (friendRow and D.FriendFallbackPaintParent and D.FriendFallbackPaintParent(plate))
    or (D.FallbackPaintParent and D.FallbackPaintParent(plate))
    or D.FallbackParent(plate)
  if not parent then
    D.ClearFallback(unit)
    return 0
  end
  local nativeList = D.NativeDebuffAnchorList(plate) or parent

  D.EnsureNativeVisible(plate)
  D.RestoreNameShift(unit, plate)

  local partyAuraTok = D.ResolvePartyTokenForPlate(plate)
  if not partyAuraTok and type(unit) == "string" and plate then
    for pi = 1, 4 do
      local pt = "party" .. pi
      if D.SafeUnitExists(pt) and (D.SameUnit(unit, pt) or D.PlateUnitBindingMatches(plate, pt)) then
        partyAuraTok = pt
        break
      end
    end
  end
  local partyMerge = D.IsPartyRaidMergePlate(unit, plate)
  local friendPlate = partyMerge
  if partyMerge or D.MergeFriendPlatesEnabled() then
    friendPlate = D.IsPlayerOrFriendPlate(unit, plate) or partyMerge
  end
  if partyMerge then
    friendPlate = true
  end
  if D.PlateUsesFriendlyHarmfulFilter and D.PlateUsesFriendlyHarmfulFilter(plate) then
    friendPlate = true
    if not partyAuraTok and D.ResolvePartyTokenForPlate then
      partyAuraTok = D.ResolvePartyTokenForPlate(plate)
    end
    if partyAuraTok then
      partyMerge = true
    end
  end
  if friendPlate and not partyAuraTok and plate then
    partyAuraTok = D.ResolvePartyTokenForPlate(plate)
    if partyAuraTok then
      partyMerge = true
    end
  end
  D.lastPaintDebug.partyTok = partyAuraTok or "-"

  D.lastPaintDebug.harv = 0
  D.lastPaintDebug.tgtSrc = 0
  D.lastPaintDebug.miss = 0
  local carryPaint = 0
  if unit and D.fallbacks[unit] then
    carryPaint = tonumber(D.fallbacks[unit]._painted) or 0
  end
  D.lastPaintDebug.painted = carryPaint
  D.lastPaintDebug.personal = 0
  D.lastPaintDebug.foreign = 0
  D.lastPaintDebug.cdN = 0
  D.lastPaintDebug.tfRows = 0
  D.lastPaintDebug.gapSz = nil
  D.lastPaintDebug.lockSz = nil

  local plateUnit = D.CanonicalPlateUnit(plate, unit)
  if plateUnit then
    if type(unit) == "string" and unit:match("^nameplate%d+") and unit ~= plateUnit then
      if not D.PlateUnitBindingMatches(plate, unit) then
        if D.fallbacks[unit] then
          D.ClearFallback(unit)
        end
      end
    end
    unit = plateUnit
  end

  local paintKeys = D.NativeShownKeySet(plate)
  local maxN = D.MaxIcons()
  local missing = {}
  local stats = { personal = 0, foreign = 0 }
  local isTarget = D.PlateMatchesTarget(plate)
  -- ShouldUseTargetAuraSource includes IsTargetPlate (GUID/nameplate bind); do not require PlateMatchesTarget alone (0.3.22).
  local useTargetSrc = D.ShouldUseTargetAuraSource(unit, plate)

  if partyAuraTok then
    friendPlate = true
    partyMerge = true
    local partyPlate = D.PlateFor(partyAuraTok)
    local plateParty = D.ResolvePartyTokenForPlate and D.ResolvePartyTokenForPlate(plate)
    if partyPlate and partyPlate ~= plate and not isTarget and plateParty ~= partyAuraTok then
      if not D.PlateUnitBindingMatches(plate, partyAuraTok) then
        local bound = D.UnitTokenFromPlate(plate)
        if not (bound and D.SameUnit(bound, partyAuraTok)) and not D.SameUnit(unit, partyAuraTok) then
          D.ClearFallback(unit)
          return 0
        end
      end
    end
  end

  if friendPlate then
    useTargetSrc = false
    if not partyAuraTok and plate and D.ResolvePartyTokenForPlate then
      partyAuraTok = D.ResolvePartyTokenForPlate(plate)
    end
    if partyAuraTok then
      partyMerge = true
    elseif D.IsPartyRaidMergePlate and D.IsPartyRaidMergePlate(unit, plate) then
      partyMerge = true
    end
  end

  if not friendPlate and useTargetSrc then
    pcall(function()
      if UnitIsFriend and UnitIsFriend("player", "target") then
        friendPlate = true
      end
    end)
  end
  D.lastPaintDebug.friendPlate = friendPlate and 1 or 0
  if (friendPlate or partyMerge) and D.FriendNativeShownKeySet then
    paintKeys = D.FriendNativeShownKeySet(plate)
  end

  local nativeN = D.CountPlateHarmfulShown(plate)
  local visBtns = {}
  D.CollectPlateDebuffButtons(plate, visBtns, maxN)
  local visN = 0
  for vi = 1, #visBtns do
    if D.NativeAuraButtonLive(visBtns[vi]) then
      visN = visN + 1
    end
  end
  if visN > nativeN then
    nativeN = visN
  end
  D.lastPaintDebug.nativeN = nativeN
  D.lastPaintDebug.nativeVis = visN
  local allowSecret = useTargetSrc or nativeN == 0
  local queueSkip = D.CopyKeySet(paintKeys)
  local harvN = 0
  -- Hostile target plate: always TF harvest (0.2.54 — lean path left harv=0 / miss=0 live).
  local heavyTarget = useTargetSrc and (not friendPlate or D.NeedsHeavyTargetHarvest(unit, plate, nativeN))
  if useTargetSrc and friendPlate then
    local tfH = D.CountTargetHarmfulApi("target")
    if (tfH or 0) > (visN or 0) then
      heavyTarget = true
    end
  end

  if useTargetSrc then
    if heavyTarget or not friendPlate then
    local harv = {}
    pcall(function()
      harv = D.CollectTargetHarmfulRows(maxN) or {}
    end)
    harvN = #harv
    D.lastPaintDebug.harv = harvN
    D.lastPaintDebug.tgtSrc = 1
    for i = 1, #harv do
      D.AppendGapRow(queueSkip, missing, maxN, stats, harv[i], false)
    end
    D.CollectPersonalAuraGaps("target", queueSkip, missing, maxN, stats)
    if type(unit) == "string" and unit ~= "target" then
      D.CollectPersonalAuraGaps(unit, queueSkip, missing, maxN, stats)
    end
    D.CollectTargetFramePersonalGaps(queueSkip, missing, maxN, stats)
    local foreignSkip = D.CopyKeySet(queueSkip)
    D.CollectForeignAuraGaps("target", foreignSkip, missing, maxN, allowSecret, stats)
    D.CollectAuraSlotsGaps("target", foreignSkip, missing, maxN, stats)
    if type(unit) == "string" and unit ~= "target" then
      D.CollectForeignAuraGaps(unit, foreignSkip, missing, maxN, allowSecret, stats)
    end
    D.CollectTargetFrameMissing(queueSkip, missing, maxN, stats)
    D.CollectUnitHarmfulMirror("target", queueSkip, missing, maxN, stats)
    if type(unit) == "string" and unit ~= "target" then
      D.CollectUnitHarmfulMirror(unit, queueSkip, missing, maxN, stats)
    end
    D.EnsureTargetHarmfulParity(plate, missing, queueSkip, maxN, stats)
    D.DedupeGapIcons(missing, maxN)
    D.ReconcileTfHarmfulCoverage(plate, missing, queueSkip, maxN, stats, "target")
    D.DedupeGapIcons(missing, maxN)
    local tfUiN = D.CountTargetFrameAuras()
    if not (tfUiN > 0 and #missing > 0) then
      D.PruneInactiveGapRows(missing, "target", maxN)
    end
    D.ReconcileTargetFrameUiButtons(plate, missing, queueSkip, maxN, stats)
    D.DedupeGapIcons(missing, maxN)
    if #missing == 0 then
      pcall(D.ForceFillTargetFrameGaps, missing, queueSkip, maxN, stats)
      D.DedupeGapIcons(missing, maxN)
    end
  else
    D.lastPaintDebug.tgtSrc = 1
    D.lastPaintDebug.harv = 0
    D.CollectPersonalAuraGaps("target", queueSkip, missing, maxN, stats)
    local foreignSkip = D.CopyKeySet(queueSkip)
    if friendPlate then
      D.CollectPlayerOwnedKeys("target", foreignSkip)
    end
    D.CollectForeignAuraGaps("target", foreignSkip, missing, maxN, allowSecret, stats)
    D.CollectAuraSlotsGaps("target", foreignSkip, missing, maxN, stats)
    if type(unit) == "string" and unit ~= "target" then
      D.CollectPlayerOwnedKeys(unit, foreignSkip)
      D.CollectForeignAuraGaps(unit, foreignSkip, missing, maxN, allowSecret, stats)
    end
    D.CollectTargetFrameMissing(queueSkip, missing, maxN, stats)
    if friendPlate then
      D.EnsureTargetHarmfulParity(plate, missing, queueSkip, maxN, stats)
      D.ReconcileTargetFrameUiButtons(plate, missing, queueSkip, maxN, stats)
      local harmTok = partyAuraTok or unit or "target"
      D.EnsureUnitHarmfulParity(harmTok, plate, missing, queueSkip, maxN, stats)
      if D.CollectFriendHelpfulAuraGaps then
        local helpSkip = D.CopyKeySet(queueSkip)
        pcall(D.CollectFriendHelpfulAuraGaps, harmTok, helpSkip, missing, maxN, stats)
      end
      D.DedupeGapIcons(missing, maxN)
      if #missing == 0 then
        pcall(D.ForceFillTargetFrameGaps, missing, queueSkip, maxN, stats)
        D.EnsureUnitHarmfulParity(harmTok, plate, missing, queueSkip, maxN, stats)
        D.DedupeGapIcons(missing, maxN)
      end
    else
      D.DedupeGapIcons(missing, maxN)
      local tfHarm = D.CountTargetHarmfulApi("target")
      if not (tfHarm > 0 and #missing > 0) then
        D.PruneInactiveGapRows(missing, "target", maxN)
      end
      if #missing == 0 and tfHarm > 0 then
        pcall(D.ForceFillTargetFrameGaps, missing, queueSkip, maxN, stats)
        D.DedupeGapIcons(missing, maxN)
      end
    end
    end
  elseif partyMerge and type(unit) == "string" then
    D.lastPaintDebug.tgtSrc = 0
    D.lastPaintDebug.harv = 0
    local auraTok = partyAuraTok or unit
    local foreignSkip = D.CopyKeySet(paintKeys)
    D.CollectPersonalAuraGaps(auraTok, foreignSkip, missing, maxN, stats)
    D.CollectPlayerOwnedKeys(auraTok, foreignSkip)
    D.CollectForeignAuraGaps(auraTok, foreignSkip, missing, maxN, true, stats)
    D.CollectAuraSlotsGaps(auraTok, foreignSkip, missing, maxN, stats)
    D.CollectUnitHarmfulMirror(auraTok, foreignSkip, missing, maxN, stats)
    D.EnsureUnitHarmfulParity(auraTok, plate, missing, foreignSkip, maxN, stats)
    if D.CollectFriendHelpfulAuraGaps then
      local helpSkip = D.CopyKeySet(foreignSkip)
      pcall(D.CollectFriendHelpfulAuraGaps, auraTok, helpSkip, missing, maxN, stats)
    end
    D.DedupeGapIcons(missing, maxN)
    if friendPlate and #missing > 0 then
      D.lastPaintDebug.harv = #missing
    else
      D.PruneInactiveGapRows(missing, auraTok, maxN)
    end
  elseif type(unit) == "string" then
    D.lastPaintDebug.tgtSrc = 0
    D.lastPaintDebug.harv = 0
    local auraTok = partyAuraTok or unit
    if friendPlate and partyAuraTok then
      auraTok = partyAuraTok
    end
    D.CollectPersonalAuraGaps(auraTok, paintKeys, missing, maxN, stats)
    local foreignSkip = D.CopyKeySet(paintKeys)
    D.CollectPlayerOwnedKeys(auraTok, foreignSkip)
    D.CollectForeignAuraGaps(auraTok, foreignSkip, missing, maxN, allowSecret or friendPlate, stats)
    if auraTok ~= unit then
      D.CollectForeignAuraGaps(unit, foreignSkip, missing, maxN, allowSecret or friendPlate, stats)
      D.CollectAuraSlotsGaps(unit, foreignSkip, missing, maxN, stats)
    end
    D.CollectAuraSlotsGaps(auraTok, foreignSkip, missing, maxN, stats)
    D.CollectUnitHarmfulMirror(auraTok, foreignSkip, missing, maxN, stats)
    D.EnsureUnitHarmfulParity(auraTok, plate, missing, foreignSkip, maxN, stats)
    if D.CollectFriendHelpfulAuraGaps then
      local helpSkip = D.CopyKeySet(foreignSkip)
      pcall(D.CollectFriendHelpfulAuraGaps, auraTok, helpSkip, missing, maxN, stats)
    end
    D.DedupeGapIcons(missing, maxN)
    D.PruneInactiveGapRows(missing, auraTok, maxN)
    D.lastPaintDebug.harv = #missing
  end

  local paintAuraTok = D.AuraUnitForPlate(unit, plate, useTargetSrc, partyAuraTok)
  if friendPlate or partyMerge then
    local pt = partyAuraTok
    if not pt and D.ResolvePartyTokenForPlate then
      pt = D.ResolvePartyTokenForPlate(plate)
    end
    if type(pt) == "string" and pt ~= "" then
      paintAuraTok = pt
    end
  end
  if (friendPlate or partyMerge) and type(paintAuraTok) == "string" and #missing == 0 then
    local skip = D.CopyKeySet(D.NativeShownKeySet(plate))
    pcall(D.EnsureUnitHarmfulParity, paintAuraTok, plate, missing, skip, maxN, stats)
    pcall(D.CollectUnitHarmfulMirror, paintAuraTok, skip, missing, maxN, stats)
    if #missing == 0 then
      pcall(D.CollectForeignAuraGaps, paintAuraTok, skip, missing, maxN, true, stats)
      pcall(D.EnsureUnitHarmfulParity, paintAuraTok, plate, missing, skip, maxN, stats)
    end
    if D.CollectFriendHelpfulAuraGaps then
      local helpSkip = D.CopyKeySet(skip)
      pcall(D.CollectFriendHelpfulAuraGaps, paintAuraTok, helpSkip, missing, maxN, stats)
    end
    D.DedupeGapIcons(missing, maxN)
    D.lastPaintDebug.miss = #missing
    if #missing > 0 then
      D.lastPaintDebug.harv = #missing
    end
  end
  local friendAuraN = friendPlate and D.CountFriendAuraSlots and D.CountFriendAuraSlots(paintAuraTok)
    or (friendPlate and D.CountHarmfulAuraSlots(paintAuraTok)) or 0
  local friendHarmN = friendAuraN
  D.lastPaintDebug.helpfulN = stats.helpful or 0
  if friendPlate and friendAuraN > 0 and #missing == 0 and type(paintAuraTok) == "string" then
    local skip = D.CopyKeySet(D.NativeShownKeySet(plate))
    pcall(D.EnsureUnitHarmfulParity, paintAuraTok, plate, missing, skip, maxN, stats)
    pcall(D.CollectUnitHarmfulMirror, paintAuraTok, skip, missing, maxN, stats)
    if #missing == 0 then
      pcall(D.CollectForeignAuraGaps, paintAuraTok, skip, missing, maxN, true, stats)
    end
    if D.CollectFriendHelpfulAuraGaps then
      local helpSkip = D.CopyKeySet(skip)
      pcall(D.CollectFriendHelpfulAuraGaps, paintAuraTok, helpSkip, missing, maxN, stats)
    end
    D.DedupeGapIcons(missing, maxN)
    D.lastPaintDebug.miss = #missing
  end
  if not (friendPlate and (friendAuraN > 0 or (D.lastPaintDebug.tfRows or 0) > 0 or #missing > 0)) then
    D.PruneInactiveGapRows(missing, paintAuraTok, maxN)
  end
  D.ApplyGapSticky(unit, missing, useTargetSrc or friendPlate, paintAuraTok, friendPlate)
  if useTargetSrc and heavyTarget then
    local tfUiLate = D.CountTargetFrameAuras()
    if not (tfUiLate > 0 and #missing > 0) then
      D.PruneInactiveGapRows(missing, paintAuraTok, maxN)
    end
    if #missing == 0 and tfUiLate > 0 then
      pcall(D.ForceFillTargetFrameGaps, missing, queueSkip, maxN, stats)
      D.DedupeGapIcons(missing, maxN)
    end
  end

  D.lastPaintDebug.miss = #missing
  local countTf = D.CountTargetFrameAuras
  D.lastPaintDebug.tfBtn = (useTargetSrc and heavyTarget) and type(countTf) == "function" and countTf() or 0
  D.lastPaintDebug.unit = tostring(unit)
  D.lastPaintDebug.nativeN = nativeN
  D.lastPaintDebug.partyTok = partyAuraTok or "-"
  if useTargetSrc and D.HasTarget() then
    D.lastPaintDebug.tfRows = D.CountTargetHarmfulExpected("target", D.lastPaintDebug.harv)
  elseif friendPlate and type(partyAuraTok or unit) == "string" then
    local auraTok = partyAuraTok or unit
    local apiN = D.CountHarmfulAuraSlots(auraTok)
    D.lastPaintDebug.tfRows = math.max(apiN, D.CountTargetHarmfulExpected(auraTok, math.max(D.lastPaintDebug.harv or 0, #missing, apiN)))
  elseif type(unit) == "string" then
    D.lastPaintDebug.tfRows = D.CountTargetHarmfulExpected(partyAuraTok or unit, math.max(D.lastPaintDebug.harv or 0, #missing))
  else
    D.lastPaintDebug.tfRows = 0
  end

  if #missing == 0 and (friendPlate or partyMerge) and type(paintAuraTok) == "string" then
    local retry = {}
    local skip = D.CopyKeySet(D.NativeShownKeySet(plate))
    pcall(D.EnsureUnitHarmfulParity, paintAuraTok, plate, retry, skip, maxN, stats)
    pcall(D.CollectUnitHarmfulMirror, paintAuraTok, skip, retry, maxN, stats)
    if #retry == 0 and (D.lastPaintDebug.tfRows or 0) > 0 then
      pcall(D.CollectForeignAuraGaps, paintAuraTok, skip, retry, maxN, true, stats)
      pcall(D.EnsureUnitHarmfulParity, paintAuraTok, plate, retry, skip, maxN, stats)
    end
    if #retry > 0 then
      D.DedupeGapIcons(retry, maxN)
      for i = 1, #retry do
        missing[i] = retry[i]
      end
      D.lastPaintDebug.miss = #missing
      D.lastPaintDebug.tfRows = D.CountTargetHarmfulExpected(paintAuraTok, #missing)
    end
  end

  if #missing == 0 then
    local held = D.fallbacks[unit]
    local sticky = D.gapSticky[unit]
    local now = GetTime and GetTime() or 0
    local heldN = held and tonumber(held._painted) or 0
    if heldN > 0 and (not sticky or type(sticky.icons) ~= "table" or #sticky.icons == 0) then
      D.gapSticky[unit] = nil
      D.ClearFallback(unit, false)
      D.lastPaintDebug.painted = 0
      D.lastPaintDebug.miss = 0
      D.SilentTracePaint("paint_stale_cleared", unit, plate)
      return 0
    end
    if heldN > 0 and sticky and type(sticky.icons) == "table" and #sticky.icons > 0 then
      local auraUnit = D.AuraUnitForPlate(unit, plate, useTargetSrc, partyAuraTok)
      local stickyLive = {}
      for si = 1, #sticky.icons do
        if D.GapAuraLive(sticky.icons[si], auraUnit) then
          stickyLive[#stickyLive + 1] = sticky.icons[si]
        end
      end
      if #stickyLive == 0 then
        D.gapSticky[unit] = nil
        local retry = {}
        local skip = D.CopyKeySet(D.NativeShownKeySet(plate))
        if type(auraUnit) == "string" then
          if friendPlate or partyMerge then
            pcall(D.EnsureUnitHarmfulParity, auraUnit, plate, retry, skip, maxN, stats)
            pcall(D.CollectUnitHarmfulMirror, auraUnit, skip, retry, maxN, stats)
          end
          if #retry == 0 then
            pcall(D.CollectForeignAuraGaps, auraUnit, skip, retry, maxN, allowSecret, stats)
            pcall(D.CollectPersonalAuraGaps, auraUnit, skip, retry, maxN, stats)
            D.PruneInactiveGapRows(retry, auraUnit, maxN)
          end
        end
        if #retry > 0 then
          D.DedupeGapIcons(retry, maxN)
          for i = 1, #retry do
            missing[i] = retry[i]
          end
          D.lastPaintDebug.miss = #missing
          D.lastPaintDebug.tfRows = D.CountTargetHarmfulExpected(auraUnit, #missing)
        elseif (friendPlate or partyMerge) and type(auraUnit) == "string"
            and ((D.CountFriendAuraSlots and D.CountFriendAuraSlots(auraUnit))
              or (D.CountHarmfulAuraSlots(auraUnit) or 0)) > 0 then
          local skip = D.CopyKeySet(D.NativeShownKeySet(plate))
          pcall(D.EnsureUnitHarmfulParity, auraUnit, plate, missing, skip, maxN, stats)
          pcall(D.CollectUnitHarmfulMirror, auraUnit, skip, missing, maxN, stats)
          if #missing == 0 then
            pcall(D.CollectForeignAuraGaps, auraUnit, skip, missing, maxN, allowSecret, stats)
          end
          D.DedupeGapIcons(missing, maxN)
          D.lastPaintDebug.miss = #missing
        else
          D.ClearFallback(unit, false)
          D.lastPaintDebug.painted = 0
          D.lastPaintDebug.miss = 0
          D.SilentTracePaint("paint_stale_cleared", unit, plate)
          return 0
        end
      elseif #stickyLive > 0 then
        sticky.icons = stickyLive
        local stillLive, liveN = D.StickyRowsLiveOnUnit(sticky.icons, auraUnit)
        if type(auraUnit) == "string" then
          local slots = (D.CountFriendAuraSlots and D.CountFriendAuraSlots(auraUnit))
            or (D.CountHarmfulAuraSlots(auraUnit) or 0)
          local keepFriend = (friendPlate or partyMerge) and slots > 0
          if (not stillLive or liveN == 0) and not keepFriend then
            D.gapSticky[unit] = nil
            D.ClearFallback(unit, false)
            D.lastPaintDebug.painted = 0
            D.lastPaintDebug.miss = 0
            D.SilentTracePaint("paint_stale_cleared", unit, plate)
            return 0
          end
        end
        local budget = D.GapStickyBudget(friendPlate or partyMerge)
        if type(sticky.at) == "number" and (now - sticky.at) <= budget then
          local heldCd = 0
          pcall(function()
            local n, cdn = D.RefreshHeldGapFallback(unit, plate, held, sticky.icons, auraUnit)
            heldN = n or 0
            heldCd = cdn or 0
          end)
          stillLive, liveN = D.StickyRowsLiveOnUnit(sticky.icons, auraUnit)
          local holdSlots = type(auraUnit) == "string"
            and ((D.CountFriendAuraSlots and D.CountFriendAuraSlots(auraUnit))
              or (D.CountHarmfulAuraSlots(auraUnit) or 0)) or 0
          local friendHold = (friendPlate or partyMerge) and holdSlots > 0
          if heldN <= 0 or (not stillLive and not friendHold) then
            D.gapSticky[unit] = nil
            D.lastPaintDebug.painted = 0
            D.ClearFallback(unit, false)
            if heldN <= 0 then
              D.SilentTracePaint("paint_hold_expired", unit, plate)
            else
              D.SilentTracePaint("paint_stale_cleared", unit, plate)
            end
            return 0
          end
          sticky.at = now
          D.lastPaintDebug.painted = heldN
          D.lastPaintDebug.miss = 0
          D.lastPaintDebug.cdN = heldCd
          D.SilentTracePaint("paint_hold", unit, plate)
          return heldN
        else
          D.gapSticky[unit] = nil
          D.ClearFallback(unit, false)
          D.lastPaintDebug.painted = 0
          D.SilentTracePaint("paint_stale_cleared", unit, plate)
          return 0
        end
      end
    end
    if #missing == 0 then
      if (friendPlate or partyMerge) and type(auraUnit) == "string" then
        local retry = {}
        local skip = D.CopyKeySet(D.NativeShownKeySet(plate))
        pcall(D.EnsureUnitHarmfulParity, auraUnit, plate, retry, skip, maxN, stats)
        if #retry == 0 and D.HasTarget() and D.PlateMatchesTarget(plate) then
          pcall(D.EnsureTargetHarmfulParity, plate, retry, skip, maxN, stats)
        end
        if #retry > 0 then
          D.DedupeGapIcons(retry, maxN)
          for i = 1, #retry do
            missing[i] = retry[i]
          end
          D.lastPaintDebug.miss = #missing
        elseif friendPlate and type(auraUnit) == "string" then
          pcall(D.CollectUnitHarmfulMirror, auraUnit, skip, retry, maxN, stats)
          pcall(D.CollectForeignAuraGaps, auraUnit, skip, retry, maxN, true, stats)
          pcall(D.EnsureUnitHarmfulParity, auraUnit, plate, retry, skip, maxN, stats)
          if #retry > 0 then
            D.DedupeGapIcons(retry, maxN)
            for i = 1, #retry do
              missing[i] = retry[i]
            end
            D.lastPaintDebug.miss = #missing
          else
            D.lastPaintDebug.painted = 0
            D.ClearFallback(unit, false)
            return 0
          end
        else
          D.lastPaintDebug.painted = 0
          D.ClearFallback(unit, false)
          return 0
        end
      else
        D.lastPaintDebug.painted = 0
        D.ClearFallback(unit, false)
        return 0
      end
    end
  end

  local fb = D.EnsureFallback(unit, plate)
  if not fb then
    D.lastPaintDebug.painted = 0
    D.lastPaintDebug.parent = "nil"
    return 0
  end
  D.lastPaintDebug.parent = (parent == plate) and "plate" or ((parent == (plate and plate.UnitFrame)) and "UnitFrame" or "AurasFrame")
  local sz, pad = D.MergeRowIconSize(plate, fb)
  fb._pbPlate = plate
  local auraUnit = paintAuraTok or D.AuraUnitForPlate(unit, plate, useTargetSrc, partyAuraTok)
  local painted = 0
  local cdN = 0
  for i = 1, #missing do
    if painted >= maxN then
      break
    end
    painted = painted + 1
    local slot = fb.icons[painted]
    if not slot or not slot.SetSize then
      slot = D.CreateGapAuraButton(fb, sz)
      slot._pbPlate = plate
      fb.icons[painted] = slot
    end
    local okLay = pcall(function()
      if slot._pbSz ~= sz then
        pcall(D.InitAuraButton, slot, sz)
        slot._pbSz = sz
      end
      slot:ClearAllPoints()
      slot:SetSize(sz, sz)
      slot:SetPoint("LEFT", fb, "LEFT", (painted - 1) * (sz + pad), 0)
    end)
    if not okLay then
      painted = painted - 1
    else
      D.EnrichGapAuraEntry(missing[i], auraUnit)
      local okVis, cdSet = D.ApplyGapAuraVisual(slot, missing[i], auraUnit)
      if not okVis and friendPlate then
        local alts = { partyAuraTok, useTargetSrc and D.HasTarget() and "target" or nil, unit, paintAuraTok }
        for ai = 1, #alts do
          local alt = alts[ai]
          if type(alt) == "string" and alt ~= "" and alt ~= auraUnit then
            D.EnrichGapAuraEntry(missing[i], alt)
            okVis, cdSet = D.ApplyGapAuraVisual(slot, missing[i], alt)
            if okVis then
              auraUnit = alt
              break
            end
          end
        end
      end
      if cdSet then
        cdN = cdN + 1
      end
      if okVis then
        pcall(function()
          slot:SetAlpha(1)
          slot:Show()
          local ic = slot.icon or slot.Icon
          if ic and ic.SetAlpha then
            ic:SetAlpha(1)
          end
        end)
      else
        pcall(slot.Hide, slot)
        painted = painted - 1
      end
    end
  end
  for i = painted + 1, #fb.icons do
    local slot = fb.icons[i]
    if slot then
      pcall(slot.Hide, slot)
    end
  end

  if painted == 0 then
    if friendPlate and #missing > 0 and type(auraUnit) == "string" then
      pcall(function()
        local n, _cdn = D.RefreshHeldGapFallback(unit, plate, fb, missing, auraUnit)
        if (n or 0) > 0 then
          painted = n
        end
      end)
    end
    if painted == 0 and friendPlate and type(auraUnit) == "string" then
      local sticky = D.gapSticky[unit]
      if sticky and type(sticky.icons) == "table" and #sticky.icons > 0 then
        local liveSticky = {}
        for si = 1, #sticky.icons do
          if D.GapAuraLive(sticky.icons[si], auraUnit) then
            liveSticky[#liveSticky + 1] = sticky.icons[si]
          end
        end
        if #liveSticky > 0 then
          local n, _cdn = D.RefreshHeldGapFallback(unit, plate, fb, liveSticky, auraUnit)
          if (n or 0) > 0 then
            painted = n
            D.SilentTracePaint("paint_hold", unit, plate)
            return painted
          end
        end
      end
    end
    pcall(fb.Hide, fb)
    fb._painted = 0
    D.lastPaintDebug.painted = 0
    return 0
  end

  pcall(function()
    fb:SetSize(math.max(1, painted * (sz + pad)), sz)
    local strata = "MEDIUM"
    pcall(function()
      if nativeList.GetFrameStrata then
        strata = nativeList:GetFrameStrata() or strata
      end
    end)
    fb:SetFrameStrata(strata)
    local lvl = 50
    pcall(function()
      if nativeList.GetFrameLevel then
        lvl = (nativeList:GetFrameLevel() or 1) + 3
      elseif parent then
        lvl = (parent:GetFrameLevel() or 1) + 15
      end
    end)
    fb:SetFrameLevel(lvl)
    pcall(function()
      if fb.SetClipsChildren then
        fb:SetClipsChildren(false)
      end
    end)
    fb:Show()
  end)
  fb._painted = painted
  fb._gapPersonal = stats.personal or 0
  fb._gapForeign = stats.foreign or 0

  pcall(D.LayoutMergeBesideNative, unit, plate, fb, painted)
  if (friendPlate or partyMerge) and painted > 0 and D.BoostFriendGapChrome then
    pcall(D.BoostFriendGapChrome, fb, plate, painted)
  end
  if painted > 0 then
    local kept = {}
    for i = 1, painted do
      kept[i] = missing[i]
    end
    D.RememberGapSticky(unit, kept, auraUnit)
  end
  D.lastPaintDebug.painted = painted
  D.lastPaintDebug.personal = stats.personal
  D.lastPaintDebug.foreign = stats.foreign
  D.lastPaintDebug.gapSz = sz
  D.lastPaintDebug.lockSz = fb._pbLockedSz
  D.lastPaintDebug.cdN = cdN
  local harmApi = 0
  if friendPlate and type(auraUnit) == "string" then
    harmApi = D.CountHarmfulAuraSlots(auraUnit) or 0
    if harmApi > (D.lastPaintDebug.tfRows or 0) then
      D.lastPaintDebug.tfRows = harmApi
    end
  end
  if painted > 0 then
    D.SilentTracePaint("paint", unit, plate)
  elseif friendPlate and (harmApi > 0 or (D.lastPaintDebug.miss or 0) > 0) then
    D.SilentTracePaint("paint_gap", unit, plate)
  elseif (D.lastPaintDebug.miss or 0) > 0 then
    local harmLive = friendPlate and type(auraUnit) == "string" and harmApi > 0
    if not harmLive then
      D.SilentTracePaint("paint", unit, plate)
    end
  elseif friendPlate then
    D.SilentTracePaint("paint_sample", unit, plate)
  end
  return painted
end
