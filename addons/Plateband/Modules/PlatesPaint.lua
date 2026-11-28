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
    D.DedupeGapIcons(missing, maxN)
    D.lastPaintDebug.miss = #missing
  end
  if not (friendPlate and (friendAuraN > 0 or (D.lastPaintDebug.tfRows or 0) > 0 or #missing > 0)) then
    D.PruneInactiveGapRows(missing, paintAuraTok, maxN)
  end
  -- When the client returns the unit's auras, they are the authoritative source: one icon per aura instance
  -- (several casters of one spell stay separate). The collectors above are only the fallback.
  if type(paintAuraTok) == "string" then
    local direct = D.CollectDirectAuras(paintAuraTok, plate, maxN)
    if direct then
      for i = #missing, 1, -1 do
        missing[i] = nil
      end
      for i = 1, #direct do
        missing[i] = direct[i]
      end
    end
  end
  D.ApplyGapSticky(unit, missing, useTargetSrc or friendPlate, paintAuraTok, friendPlate)
  -- Rules (PlatesPolicy.lua): add short helpful / dispellable buffs, then drop everything the rules exclude.
  if type(paintAuraTok) == "string" then
    D.CollectPolicyHelpfulGaps(paintAuraTok, D.CopyKeySet(D.NativeShownKeySet(plate)), missing, maxN, friendPlate and true or false, stats)
    D.DedupeGapIcons(missing, maxN)
    D.ApplyGapPolicy(missing, paintAuraTok, friendPlate and true or false)
    D.lastPaintDebug.miss = #missing
  end
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
    -- Remembered (sticky) icons were judged when they were stored: run them through today's rules too,
    -- otherwise an emptied list re-paints icons the rules would reject (long buffs, foreign debuffs).
    do
      local st = D.gapSticky[unit]
      if st and type(st.icons) == "table" and type(paintAuraTok) == "string" then
        D.ApplyGapPolicy(st.icons, paintAuraTok, friendPlate and true or false, true)
        if #st.icons == 0 then
          D.gapSticky[unit] = nil
        end
      end
    end
    local held = D.fallbacks[unit]
    local sticky = D.gapSticky[unit]
    local auraUnit -- also used by the friend retry below (was a nil global there)
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
      auraUnit = D.AuraUnitForPlate(unit, plate, useTargetSrc, partyAuraTok)
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
      if auraUnit == nil and (friendPlate or partyMerge) then
        auraUnit = D.AuraUnitForPlate(unit, plate, useTargetSrc, partyAuraTok)
      end
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

  -- Rows re-added by the retry paths above go through the same rules.
  do
    local ruleTok = paintAuraTok or auraUnit
    if type(ruleTok) == "string" then
      local dropped = D.ApplyGapPolicy(missing, ruleTok, friendPlate and true or false) or 0
      if dropped > 0 then
        D.lastPaintDebug.policyDrop = dropped
        D.lastPaintDebug.miss = #missing
      end
    end
  end

  -- One row per plate: a row left under another key (target key, recycled nameplateN) would be drawn at the
  -- same spot as this one (icon on top of icon).
  for k, other in pairs(D.fallbacks) do
    if k ~= unit and other and other._pbPlate == plate and (tonumber(other._painted) or 0) > 0 then
      D.ClearFallback(k)
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

-- =====================================================================================================
-- EXPERIMENTAL (0.7.0): Blizzard-managed AuraContainer row. Profile `useAuraContainer` (default false),
-- `/pb ac on|off|status`. Pattern from SKTools PartyFrames.lua (HoT reminders) and the 12.1 AuraContainer API.
--
-- The container tracks its unit's auras C-side: no aura reads, no timers, no math on possibly-secret values,
-- so it can work on friendly units in combat, where C_UnitAuras is locked for addons. Per plate: one host
-- frame of OUR OWN (child of the plate's UnitFrame), anchored out of combat directly above the name and
-- left-aligned with the health bar (same offset as the legacy row); inside it two containers built out of
-- combat: "friend" (debuffs <= 300 s, helpful <= 60 s minus food/drink/permanent spell ids) and "enemy"
-- (debuffs from players/pets, dispellable/stealable buffs). Only one is shown. In combat only our own frames
-- are shown/hidden and the unit is (re)bound. Everything is pcall'd; when the API or a group is refused the
-- plate silently keeps the legacy row and `/pb ac status` says why.
-- =====================================================================================================
do
  local AC = { hosts = {}, api = nil, apiWhy = "not probed yet", template = nil, buildFailed = nil,
    lastErr = nil, errN = 0, learnedNew = 0, inCombatSkips = 0 }
  D.AC = AC

  local TEMPLATES = { "CustomAuraContainerTemplate", "ManagedAuraContainerTemplate" }
  local FRIEND_DEBUFF_MAX_SEC = 300 -- same as PlatesPolicy FRIENDLY_DEBUFF_MAX_SEC
  local FRIEND_HELPFUL_MAX_SEC = 60 -- same as PlatesPolicy HELPFUL_MAX_SEC
  local LEARN_CAP = 400
  local LEARN_EVERY_SEC = 3
  -- Food / Drink aura ids (classic-era ids, best effort). The container cannot match names, so food is excluded
  -- by spell id; the list grows from readable aura data out of combat (PlatebandDB.acExclude).
  local FOOD_SEED = { 430, 431, 432, 433, 434, 435, 1127, 1129, 1131, 1133, 1135, 1137, 22734, 24355 }
  local seedSet = {}
  for i = 1, #FOOD_SEED do
    seedSet[FOOD_SEED[i]] = true
  end
  local learnAt = {}

  local function inCombat()
    return InCombatLockdown and InCombatLockdown() and true or false
  end

  local function pub(v)
    if v ~= nil and not D.IsSecret(v) then
      return v
    end
    return nil
  end

  local function profile()
    local ok, p = pcall(D.Profile)
    return ok and type(p) == "table" and p or {}
  end

  local function acErr(where, err)
    AC.errN = AC.errN + 1
    AC.lastErr = tostring(where) .. ": " .. tostring(err):sub(1, 140)
    if Plateband.RecordError then
      pcall(Plateband.RecordError, "ac:" .. tostring(where), err)
    end
  end

  local function wanted()
    local p = profile()
    if p.useAuraContainer ~= true or p.mergeMissing ~= true then
      return false
    end
    local ok, active = pcall(D.ModuleActive)
    return ok and active and true or false
  end

  local function learnedDB()
    if type(PlatebandDB) ~= "table" then
      return nil
    end
    if type(PlatebandDB.acExclude) ~= "table" then
      PlatebandDB.acExclude = {}
    end
    return PlatebandDB.acExclude
  end

  local function excludeMap()
    local m, n = {}, 0
    for id in pairs(seedSet) do
      m[id] = true
      n = n + 1
    end
    local l = learnedDB()
    if l then
      for id in pairs(l) do
        if type(id) == "number" and not m[id] then
          m[id] = true
          n = n + 1
        end
      end
    end
    return m, n
  end

  --- Does this client have the container type? Creates one hidden probe container (out of combat only).
  local function probe()
    if AC.api ~= nil then
      return AC.api
    end
    if inCombat() then
      AC.apiWhy = "not probed yet (in combat; probed after combat)"
      return nil
    end
    local lastErr = "?"
    for i = 1, #TEMPLATES do
      local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, TEMPLATES[i])
      if ok and c and c.AddAuraGroup and c.SetUnit then
        pcall(c.Hide, c)
        AC.probeFrame = c
        AC.api = true
        AC.template = TEMPLATES[i]
        AC.apiWhy = "ok (" .. TEMPLATES[i] .. ")"
        return true
      end
      lastErr = ok and (c and "frame has no AddAuraGroup/SetUnit" or "CreateFrame returned nil") or tostring(c)
    end
    AC.api = false
    AC.apiWhy = "CreateFrame('AuraContainer', ..., '" .. TEMPLATES[1] .. "') failed: " .. lastErr:sub(1, 120)
    return false
  end

  local function newContainer(parent)
    local order = { AC.template }
    for i = 1, #TEMPLATES do
      if TEMPLATES[i] ~= AC.template then
        order[#order + 1] = TEMPLATES[i]
      end
    end
    local lastErr
    for i = 1, #order do
      local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, order[i])
      if ok and c and c.AddAuraGroup then
        return c
      end
      lastErr = ok and "no container" or c
    end
    return nil, lastErr
  end

  --- One AuraButton, called by the container (initializeFrame). Icon + duration swipe + countdown + stack
  --- count + our 1px border; the container's own tooltip (mouse motion only, clicks pass to the plate).
  --- Never SetTexCoord (Forever icons are masked), never a formatter for the stack count (SKTools: the engine
  --- formats a secret count in Lua and the throw freezes the container), no SetScript (buttons may be forbidden).
  local function initButton(c, button, size, kind)
    c._pbButtons = c._pbButtons or {}
    c._pbInited = c._pbInited or {}
    if c._pbInited[button] then
      return -- already set up (the container may call initializeFrame again for a reused button)
    end
    c._pbInited[button] = true
    c._pbButtons[#c._pbButtons + 1] = button
    local ok, err = pcall(function()
      pcall(button.SetSize, button, size, size)
      if button.SetMouseMotionEnabled then
        pcall(button.SetMouseMotionEnabled, button, profile().gapTooltip ~= false)
      end
      if button.SetMouseClickEnabled then
        pcall(button.SetMouseClickEnabled, button, false)
      end
      local icon = button:CreateTexture(nil, "ARTWORK")
      icon:SetAllPoints(button)
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
      cd.noCooldownCount = true
      if button.SetDurationCooldown then
        pcall(button.SetDurationCooldown, button, cd)
      end
      -- Text above the swipe: font strings on the button itself would sit under the cooldown child frame.
      local over = CreateFrame("Frame", nil, button)
      over:SetAllPoints(button)
      pcall(over.EnableMouse, over, false)
      pcall(function()
        over:SetFrameLevel((cd:GetFrameLevel() or 1) + 5)
      end)
      local dur = over:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      dur:SetPoint("CENTER", button, "CENTER", 0, 0)
      if D.ApplyNativeAuraDurationFont then
        pcall(D.ApplyNativeAuraDurationFont, dur, size)
      end
      local durOk = button.SetDurationText and pcall(button.SetDurationText, button, dur) or false
      if durOk then
        pcall(cd.SetHideCountdownNumbers, cd, true)
      else
        pcall(dur.Hide, dur)
        pcall(cd.SetHideCountdownNumbers, cd, false)
        if D.ApplyNativeAuraCooldown then
          pcall(D.ApplyNativeAuraCooldown, cd, size)
        end
      end
      local count = over:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
      if D.StyleAuraStackFont then
        pcall(D.StyleAuraStackFont, count, size)
      end
      local countOk = false
      if button.SetApplicationCount then
        countOk = pcall(button.SetApplicationCount, button, count)
        if not countOk then
          countOk = pcall(button.SetApplicationCount, button, count, {})
        end
      end
      if D.ApplyGapBorder then
        pcall(D.ApplyGapBorder, over, { isHelpful = kind == "helpful", _pbKind = kind == "purge" and "purge" or nil })
      end
      c._pbInit = string.format("icon=%s cd=%s durText=%s count=%s", tostring(button.SetIcon ~= nil),
        tostring(button.SetDurationCooldown ~= nil), tostring(durOk), tostring(countOk))
    end)
    if not ok then
      acErr("initializeFrame", err)
    end
  end

  --- Rules -> container groups. Each group lists attempts, best filter first; the first one the client
  --- accepts is used (an unknown filter token or candidate key may be refused).
  local function groupSpecs(side)
    if side == "friend" then
      local ex = excludeMap()
      return {
        { key = "pbFD", kind = "debuff", tries = {
          { filter = "HARMFUL", cf = { maxDuration = FRIEND_DEBUFF_MAX_SEC }, label = "HARMFUL maxDuration=300" },
          { filter = "HARMFUL", label = "HARMFUL (no duration filter)" },
        } },
        { key = "pbFB", kind = "helpful", tries = {
          { filter = "HELPFUL", cf = { maxDuration = FRIEND_HELPFUL_MAX_SEC, excludeSpellIDs = ex },
            label = "HELPFUL maxDuration=60 excludeSpellIDs", usesExclude = true },
          { filter = "HELPFUL", cf = { maxDuration = FRIEND_HELPFUL_MAX_SEC }, label = "HELPFUL maxDuration=60" },
          { filter = "HELPFUL|RAID_IN_COMBAT", label = "HELPFUL|RAID_IN_COMBAT" },
        } },
      }
    end
    local pr = profile()
    local specs = {}
    specs[1] = { key = "pbED", kind = "debuff", tries = {
      { filter = "HARMFUL", cf = { isFromPlayerOrPlayerPet = true }, label = "HARMFUL isFromPlayerOrPlayerPet" },
      { filter = "HARMFUL|PLAYER", label = "HARMFUL|PLAYER (own only)" },
    } }
    if pr.enemyBuffs ~= false then
      specs[#specs + 1] = { key = "pbEB", kind = "purge", tries = {
        { filter = "HELPFUL|DISPELLABLE", label = "HELPFUL|DISPELLABLE" },
        { filter = "HELPFUL|RAID_PLAYER_DISPELLABLE", label = "HELPFUL|RAID_PLAYER_DISPELLABLE" },
        { filter = "HELPFUL", cf = { isStealable = true }, label = "HELPFUL isStealable" },
      } }
    end
    return specs
  end
  D.AcGroupSpecs = groupSpecs

  local function addGroup(c, spec, size, pad, maxN)
    local lastErr
    for ti = 1, #spec.tries do
      local t = spec.tries[ti]
      for li = 1, 2 do
        local layout = { elementWidth = size, elementHeight = size }
        if li == 1 then
          layout.elementSpacing = pad
        end
        local gk = spec.key .. ti .. (li == 1 and "s" or "")
        local opts = {
          maxFrameCount = maxN,
          candidateFilters = t.cf,
          sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Expiration or nil,
          sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal or nil,
          initializeFrame = function(button)
            initButton(c, button, size, spec.kind)
          end,
          layout = layout,
        }
        local ok, err = pcall(c.AddAuraGroup, c, gk, t.filter, opts)
        if ok then
          return { key = gk, label = t.label .. (li == 1 and "" or " (no spacing)"), usesExclude = t.usesExclude }
        end
        lastErr = err
      end
    end
    return nil, lastErr
  end

  local function hideHost(h)
    if not h then
      return
    end
    pcall(h.Hide, h)
    for _, side in ipairs({ "friend", "enemy" }) do
      local c = h._pbC[side]
      if c then
        pcall(c.Hide, c)
        c._pbBound = nil
      end
    end
    local was = h._pbActive
    h._pbActive = false
    if was and h._pbPlate then
      local dl = D.NativeDebuffList and D.NativeDebuffList(h._pbPlate)
      if dl and dl.SetAlpha then
        pcall(dl.SetAlpha, dl, 1) -- give the native debuffs back
      end
    end
  end

  local function ensureHost(plate)
    local h = AC.hosts[plate]
    if h then
      return h
    end
    if inCombat() then
      return nil, "in combat"
    end
    local parent = D.FriendFallbackPaintParent and D.FriendFallbackPaintParent(plate)
    if not parent then
      return nil, "no plate parent"
    end
    local ok, f = pcall(CreateFrame, "Frame", nil, parent)
    if not ok or not f then
      return nil, f
    end
    pcall(f.EnableMouse, f, false)
    pcall(f.SetSize, f, 1, 1)
    pcall(f.Hide, f)
    f._pbPlate = plate
    f._pbAcHost = true
    f._pbC = {} -- [side] = container ("friend" / "enemy")
    AC.hosts[plate] = f
    return f
  end

  --- Out of combat only: directly above the name, left-aligned with the health bar (legacy row offset).
  local function anchorHost(h, plate)
    local bar = D.HealthBar and D.HealthBar(plate)
    if not bar or (D.FrameIsGlobalChrome and D.FrameIsGlobalChrome(bar)) then
      return false, "no health bar"
    end
    local y = D.AboveNameRowY and D.AboveNameRowY(plate, bar) or 16
    if h._pbAnchored and h._pbBar == bar and h._pbY == y then
      return true
    end
    local ok, err = pcall(function()
      h:ClearAllPoints() -- our own frame
      h:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, y)
      local uf = plate.UnitFrame
      local strata, lvl = "MEDIUM", 50
      pcall(function()
        strata = uf:GetFrameStrata() or strata
        lvl = (uf:GetFrameLevel() or 0) + 25
      end)
      if strata == "BACKGROUND" or strata == "LOW" then
        strata = "MEDIUM"
      end
      h:SetFrameStrata(strata)
      h:SetFrameLevel(lvl)
      -- The row sits above the name, outside the UnitFrame box: same unclipping as the legacy friendly row.
      if uf and uf.SetClipsChildren then
        pcall(uf.SetClipsChildren, uf, false)
      end
      if plate.SetClipsChildren then
        pcall(plate.SetClipsChildren, plate, false)
      end
    end)
    h._pbAnchored = ok and true or false
    h._pbBar, h._pbY = bar, y
    return ok, err
  end

  --- Out of combat only: both containers of a host (friend + enemy rules), hidden until a unit is bound.
  local function ensureContainers(h, plate)
    if h._pbBuilt then
      return true
    end
    if AC.buildFailed then
      return false, AC.buildFailed
    end
    if inCombat() then
      return false, "in combat"
    end
    if not probe() then
      return false, AC.apiWhy
    end
    local size, pad = 18, 2
    pcall(function()
      size, pad = D.MergeRowIconSize(plate)
    end)
    size, pad = tonumber(size) or 18, tonumber(pad) or 2
    local maxN = D.MaxIcons and D.MaxIcons() or 12
    for _, side in ipairs({ "friend", "enemy" }) do
      if not h._pbC[side] then
        local c, err = newContainer(h)
        if not c then
          AC.buildFailed = "container create failed: " .. tostring(err):sub(1, 100)
          return false, AC.buildFailed
        end
        -- The template starts enabled; visibility gates its events and OnShow asks for a full refresh.
        pcall(c.Hide, c)
        pcall(c.SetSize, c, 1, 1)
        pcall(c.EnableMouse, c, false)
        pcall(c.SetPoint, c, "BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
        if c.SetFlowLayoutAxis and AnchorUtil and AnchorUtil.FlowLayoutAxis then
          pcall(c.SetFlowLayoutAxis, c, AnchorUtil.FlowLayoutAxis.Horizontal)
          pcall(c.SetFlowLayoutAnchorPoint, c, "BOTTOMLEFT")
          if AnchorUtil.FlowDirection then
            pcall(c.SetFlowLayoutGrowthDirection, c, AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)
          end
          c._pbFlow = true
        end
        pcall(c.SetFlowLayoutPadding, c, 0, 0, 0, 0)
        c._pbGroups = {}
        c._pbSide = side
        local errs = {}
        local specs = groupSpecs(side)
        for si = 1, #specs do
          local g, gerr = addGroup(c, specs[si], size, pad, maxN)
          if g then
            c._pbGroups[#c._pbGroups + 1] = g
          else
            errs[#errs + 1] = specs[si].key .. ": " .. tostring(gerr):sub(1, 80)
          end
        end
        c._pbGroupErr = #errs > 0 and table.concat(errs, "; ") or nil
        if #c._pbGroups == 0 then
          AC.buildFailed = "no aura group accepted (" .. side .. "): " .. tostring(c._pbGroupErr)
          return false, AC.buildFailed
        end
        h._pbC[side] = c
      end
    end
    h._pbBuilt = true
    return true
  end

  --- Unit token the container follows. Friendly units: their party/raid token (aura data of friends is only
  --- returned for those on this client); otherwise the nameplate token. Never "target" (it would follow the
  --- next target on this plate).
  local function bindToken(unit, plate, friend)
    if friend and D.ResolvePartyTokenForPlate then
      local pt = D.ResolvePartyTokenForPlate(plate)
      if type(pt) == "string" and pt ~= "target" then
        return pt
      end
    end
    if type(unit) == "string" and unit:match("^nameplate%d+$") then
      return unit
    end
    local t = D.UnitTokenFromPlate and D.UnitTokenFromPlate(plate)
    if type(t) == "string" and t:match("^nameplate%d+$") then
      return t
    end
    return nil
  end

  --- Re-applies the learned food/drink/permanent spell ids to every friendly buff group (out of combat).
  local function applyExcludes()
    if inCombat() then
      return
    end
    local ex = excludeMap()
    for _, h in pairs(AC.hosts) do
      local c = h._pbC.friend
      if c and c.SetAuraGroupCandidateFilters and type(c._pbGroups) == "table" then
        for i = 1, #c._pbGroups do
          local g = c._pbGroups[i]
          if g.usesExclude then
            local ok, err = pcall(c.SetAuraGroupCandidateFilters, c, g.key,
              { maxDuration = FRIEND_HELPFUL_MAX_SEC, excludeSpellIDs = ex })
            if not ok then
              acErr("SetAuraGroupCandidateFilters", err)
            end
          end
        end
      end
    end
  end

  --- Out of combat, readable friendly auras: remember spell ids of food/drink and of permanent buffs, which
  --- the container cannot recognise by itself (it filters by id and duration, not by name).
  local function learn(tok)
    if inCombat() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
      return
    end
    local now = GetTime and GetTime() or 0
    if (now - (learnAt[tok] or -100)) < LEARN_EVERY_SEC then
      return
    end
    learnAt[tok] = now
    local l = learnedDB()
    if not l then
      return
    end
    local n = 0
    for _ in pairs(l) do
      n = n + 1
    end
    local added = 0
    for i = 1, 40 do
      local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, tok, i, "HELPFUL")
      if not ok or type(d) ~= "table" then
        break
      end
      local sid = pub(d.spellId)
      if type(sid) == "number" and l[sid] == nil and not seedSet[sid] and n + added < LEARN_CAP then
        local why
        if D.IsFriendlyConsumableAura and D.IsFriendlyConsumableAura(d) then
          why = "food"
        elseif pub(d.duration) == 0 then
          why = "permanent"
        end
        if why then
          l[sid] = why
          added = added + 1
        end
      end
    end
    if added > 0 then
      AC.learnedNew = AC.learnedNew + added
      applyExcludes()
    end
  end

  local function muteNativeDebuffs(plate)
    local dl = D.NativeDebuffList and D.NativeDebuffList(plate)
    if dl and dl.SetAlpha then
      pcall(dl.SetAlpha, dl, 0)
    end
  end

  --- Called from UpdateOverlay for every plate. true = the container row owns this plate (legacy row bypassed).
  function D.AcUpdate(unit, plate)
    local h = plate and AC.hosts[plate]
    if not wanted() then
      if h and h._pbActive then
        hideHost(h)
      end
      return false
    end
    if not plate or AC.api == false or AC.buildFailed then
      return false
    end
    local combat = inCombat()
    if not h then
      if combat then
        AC.inCombatSkips = AC.inCombatSkips + 1 -- built after combat (REGEN repaint)
        return false
      end
      if not probe() then
        return false -- no container API on this client: legacy row, `/pb ac status` says why
      end
      local err
      h, err = ensureHost(plate)
      if not h then
        acErr("host", err)
        return false
      end
    end
    if not combat then
      local okA, whyA = anchorHost(h, plate)
      if not okA then
        h._pbWhy = "anchor: " .. tostring(whyA)
        hideHost(h)
        return false
      end
      local okB, whyB = ensureContainers(h, plate)
      if not okB then
        h._pbWhy = "build: " .. tostring(whyB)
        hideHost(h)
        return false
      end
    end
    if not (h._pbAnchored and h._pbBuilt) then
      return false
    end
    -- Side (friend / enemy rules): decided out of combat; in combat only for a new unit on this plate
    -- (reaction checks may be secret in combat).
    local side = h._pbSide
    if not combat or h._pbUnitKey ~= unit or not side then
      local friend = (D.IsPlayerOrFriendPlate and D.IsPlayerOrFriendPlate(unit, plate))
        or (D.PlateUsesFriendlyHarmfulFilter and D.PlateUsesFriendlyHarmfulFilter(plate))
      side = friend and "friend" or "enemy"
    end
    if side == "friend" and D.MergeFriendPlatesEnabled and not D.MergeFriendPlatesEnabled() then
      h._pbUnitKey, h._pbSide = unit, side -- remembered so combat-time secret reaction checks keep the side
      hideHost(h) -- "Friendly plates" off in the settings window
      return false
    end
    local c = h._pbC[side]
    local tok = bindToken(unit, plate, side == "friend")
    if not c or not tok then
      h._pbWhy = c and "no unit token" or ("no " .. side .. " container")
      hideHost(h)
      return false
    end
    local other = h._pbC[side == "friend" and "enemy" or "friend"]
    if other then
      pcall(other.Hide, other)
      other._pbBound = nil
    end
    if c._pbBound ~= tok or h._pbUnitKey ~= unit then
      pcall(c.SetEnabled, c, true)
      local ok, err = pcall(c.SetUnit, c, tok)
      if not ok then
        acErr("SetUnit", err)
        h._pbWhy = "SetUnit(" .. tostring(tok) .. ") failed"
        hideHost(h)
        return false
      end
      c._pbBound = tok
      if c.UpdateAllAuras then
        pcall(c.UpdateAllAuras, c)
      end
    end
    pcall(c.Show, c)
    pcall(h.Show, h)
    h._pbUnitKey, h._pbSide, h._pbActive, h._pbWhy = unit, side, true, nil
    -- Native lists: buffs / crowd control muted exactly as in the legacy mode, plus the native debuffs
    -- (this row shows them; alpha only, never moved).
    if D.MuteNativeBuffList then
      pcall(D.MuteNativeBuffList, plate)
    end
    muteNativeDebuffs(plate)
    if not combat and side == "friend" then
      learn(tok)
    end
    return true
  end

  --- Settings window: hover tooltips on the buttons that already exist (out of combat; later buttons read the
  --- setting when they are created).
  function D.AcApplyTooltips()
    if inCombat() then
      AC.tipsPending = true -- re-applied by D.AcOnRegen when combat ends
      return false
    end
    AC.tipsPending = nil
    local on = profile().gapTooltip ~= false
    for _, h in pairs(AC.hosts) do
      for _, side in ipairs({ "friend", "enemy" }) do
        local c = h._pbC[side]
        local list = c and c._pbButtons
        if list then
          for i = 1, #list do
            if list[i].SetMouseMotionEnabled then
              pcall(list[i].SetMouseMotionEnabled, list[i], on)
            end
          end
        end
      end
    end
    return true
  end

  --- PLAYER_REGEN_ENABLED: apply what the settings window could not change in combat.
  function D.AcOnRegen()
    if AC.tipsPending then
      D.AcApplyTooltips()
    end
  end

  --- Nameplate UNIT_AURA: true = the container row already follows this unit, so the caller skips the repaint.
  --- Only cheap work stays: the rate-limited learn() out of combat and, on friendly plates (native buff buttons
  --- are muted one by one and new pooled ones appear with new auras), a mute re-apply at most once a second.
  function D.AcAuraEvent(unit, plate)
    local h = plate and AC.hosts[plate]
    if not (h and h._pbActive and h._pbBuilt and h._pbUnitKey == unit and wanted()) then
      return false
    end
    if h._pbSide == "friend" then
      local c = h._pbC.friend
      local tok = c and c._pbBound
      if tok and not inCombat() then
        learn(tok)
      end
      local now = GetTime and GetTime() or 0
      if D.MuteNativeBuffList and (now - (h._pbMuteAt or 0)) >= 1 then
        h._pbMuteAt = now
        pcall(D.MuteNativeBuffList, plate)
      end
    end
    return true
  end

  function D.AcOwnsPlate(plate)
    local h = plate and AC.hosts[plate]
    return (h and h._pbActive and wanted()) and true or false
  end

  --- NAME_PLATE_UNIT_REMOVED: hide the row of the recycled plate (combat-safe: our frames only).
  function D.AcDetach(unit)
    for _, h in pairs(AC.hosts) do
      if h._pbUnitKey == unit then
        hideHost(h)
        h._pbUnitKey = nil
      end
    end
  end

  function D.AcHideAll()
    for _, h in pairs(AC.hosts) do
      hideHost(h)
      h._pbUnitKey = nil
    end
  end

  local function countButtons(c)
    local made, shown, forbidden = 0, 0, 0
    local list = c and c._pbButtons or {}
    for i = 1, #list do
      local b = list[i]
      made = made + 1
      local forb = false
      pcall(function()
        forb = b.IsForbidden and b:IsForbidden() and true or false
      end)
      if forb then
        forbidden = forbidden + 1
      else
        pcall(function()
          if b:IsShown() then
            shown = shown + 1
          end
        end)
      end
    end
    return made, shown, forbidden
  end

  local function showStr(f)
    local s, v = "?", "?"
    pcall(function()
      s = tostring(f:IsShown())
      v = tostring(f:IsVisible())
    end)
    return s .. "/" .. v
  end

  local function groupLabels(c)
    local parts = {}
    for i = 1, #(c and c._pbGroups or {}) do
      parts[#parts + 1] = c._pbGroups[i].key .. "=" .. c._pbGroups[i].label
    end
    return table.concat(parts, "; ")
  end

  function D.AcStatusLines()
    local p = profile()
    local lines = {}
    if not inCombat() then
      probe()
    end
    lines[#lines + 1] = string.format("ac: setting useAuraContainer=%s (merge=%s) -> mode %s",
      tostring(p.useAuraContainer == true), tostring(p.mergeMissing == true), wanted() and "ON" or "off (legacy row)")
    lines[#lines + 1] = string.format("ac: API AuraContainer: %s | flow layout=%s sort enums=%s",
      tostring(AC.apiWhy), tostring(AnchorUtil ~= nil and AnchorUtil.FlowLayoutAxis ~= nil),
      tostring(AuraContainerSortMethod ~= nil))
    local nHost, nBuilt, nActive = 0, 0, 0
    local sample
    for _, h in pairs(AC.hosts) do
      nHost = nHost + 1
      if h._pbBuilt then
        nBuilt = nBuilt + 1
        sample = sample or h
      end
      if h._pbActive then
        nActive = nActive + 1
      end
    end
    lines[#lines + 1] = string.format("ac: plates with a row=%d built=%d active=%d combatSkips=%d", nHost, nBuilt,
      nActive, AC.inCombatSkips)
    if AC.buildFailed then
      lines[#lines + 1] = "ac: build failed -> legacy row everywhere: " .. tostring(AC.buildFailed)
    end
    if sample then
      lines[#lines + 1] = "ac: friend groups: " .. groupLabels(sample._pbC.friend)
        .. (sample._pbC.friend and sample._pbC.friend._pbGroupErr and (" | refused: " .. sample._pbC.friend._pbGroupErr) or "")
      lines[#lines + 1] = "ac: enemy groups: " .. groupLabels(sample._pbC.enemy)
        .. (sample._pbC.enemy and sample._pbC.enemy._pbGroupErr and (" | refused: " .. sample._pbC.enemy._pbGroupErr) or "")
    end
    local _, nEx = excludeMap()
    lines[#lines + 1] = string.format("ac: excluded buff ids=%d (seed %d, learned this session +%d)", nEx, #FOOD_SEED,
      AC.learnedNew)
    lines[#lines + 1] = string.format("ac: errors=%d last=%s", AC.errN, tostring(AC.lastErr or "-"))
    return lines
  end

  --- /pb tree lines for one plate.
  function D.AcTreeLines(plate)
    local lines = {}
    local p = profile()
    local h = plate and AC.hosts[plate]
    lines[#lines + 1] = string.format("  AC: mode=%s api=%s host=%s anchored=%s y=%s built=%s active=%s side=%s unitKey=%s why=%s",
      wanted() and "on" or "off", tostring(AC.apiWhy), tostring(h ~= nil), tostring(h and h._pbAnchored),
      h and h._pbY and string.format("%.1f", h._pbY) or "-", tostring(h and h._pbBuilt), tostring(h and h._pbActive),
      tostring(h and h._pbSide), tostring(h and h._pbUnitKey), tostring(h and h._pbWhy or AC.buildFailed or "-"))
    if p.useAuraContainer ~= true then
      return lines
    end
    if h then
      for _, side in ipairs({ "friend", "enemy" }) do
        local c = h._pbC[side]
        if c then
          local made, shown, forbidden = countButtons(c)
          local back, w, hh = "?", "?", "?"
          pcall(function()
            local u = c:GetUnit()
            back = (u ~= nil and D.IsSecret(u)) and "SECRET" or tostring(u)
          end)
          pcall(function()
            local cw, ch = c:GetWidth(), c:GetHeight()
            w = D.IsSecret(cw) and "S" or string.format("%.0f", cw)
            hh = D.IsSecret(ch) and "S" or string.format("%.0f", ch)
          end)
          lines[#lines + 1] = string.format("  AC %s: bound=%s GetUnit=%s shown/visible=%s size=%sx%s buttons made=%d shown=%d forbidden=%d flow=%s",
            side, tostring(c._pbBound), back, showStr(c), w, hh, made, shown, forbidden, tostring(c._pbFlow))
          if c._pbInit then
            lines[#lines + 1] = "  AC " .. side .. " button init: " .. c._pbInit
          end
        end
      end
      lines[#lines + 1] = "  AC host shown/visible=" .. showStr(h)
    end
    local dl = D.NativeDebuffList and D.NativeDebuffList(plate)
    local a = "?"
    pcall(function()
      a = string.format("%.1f", dl:GetAlpha())
    end)
    lines[#lines + 1] = string.format("  AC native DebuffList alpha=%s | errors=%d last=%s", a, AC.errN,
      tostring(AC.lastErr or "-"))
    return lines
  end
end
