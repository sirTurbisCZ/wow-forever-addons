--[[
  BetterBackpack.Slots — 1:1 bag:slot SecureActionButtons (path B CS-RMB).
  Never shared pool. Create/SetAttribute OOC only. Never harvest CombinedBags.Items.
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local Slots = {}
BetterBackpack.Modules.Slots = Slots

local SLOT = 37
local buttons = {} -- BagSlotKey → button
local preCreated = false
local host -- invisible parent for parking unused / pre-create

local function IsSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v)
end

Slots.IsSecret = IsSecret

local function SafeNum(v, fallback)
  if type(v) ~= "number" then
    return fallback
  end
  if IsSecret(v) then
    return fallback
  end
  return v
end

Slots.SafeNum = SafeNum

function Slots.ReagentBagIndex()
  if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag ~= nil then
    return Enum.BagIndex.ReagentBag
  end
  return 5
end

function Slots.IsReagentBag(bag)
  if bag == nil then
    return false
  end
  local reb = Slots.ReagentBagIndex()
  local match = false
  pcall(function()
    if bag == reb then
      match = true
    end
  end)
  if match then
    return true
  end
  if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag ~= nil then
    local plain = SafeNum(Enum.BagIndex.ReagentBag, nil)
    if plain ~= nil then
      return SafeNum(bag, nil) == plain
    end
    return false
  end
  return SafeNum(bag, nil) == 5
end

function Slots.BagSlotKey(bag, slot)
  local b
  if Slots.IsReagentBag(bag) then
    b = "R"
  else
    b = SafeNum(bag, nil)
    if b == nil then
      b = "?"
    end
  end
  local s = SafeNum(slot, nil)
  if s == nil and slot ~= nil then
    for i = 1, 36 do
      local match = false
      pcall(function()
        if slot == i then
          match = true
        end
      end)
      if match then
        s = i
        break
      end
    end
  end
  if s == nil then
    s = "?"
  end
  return tostring(b) .. ":" .. tostring(s)
end

function Slots.AttrBagSlot(bag, slot)
  local s = SafeNum(slot, nil)
  if s == nil then
    return nil, nil
  end
  if Slots.IsReagentBag(bag) then
    local b = SafeNum(Slots.ReagentBagIndex(), nil) or SafeNum(bag, nil) or 5
    return b, s
  end
  return SafeNum(bag, nil), s
end

function Slots.NumSlotsForBag(bag)
  if not (C_Container and C_Container.GetContainerNumSlots) then
    return 0
  end
  local ok, res = pcall(C_Container.GetContainerNumSlots, bag)
  if not ok or type(res) ~= "number" then
    if Slots.IsReagentBag(bag) then
      return 36
    end
    return 0
  end
  if IsSecret(res) then
    return 36
  end
  return res > 0 and res or 0
end

function Slots.BagRanges()
  local ranges = {}
  local reb = Slots.ReagentBagIndex()
  local bags = { 0, 1, 2, 3, 4, reb }
  if not Slots.IsReagentBag(5) then
    bags[#bags + 1] = 5
  end
  for i = 1, #bags do
    local bag = bags[i]
    local already = false
    for j = 1, #ranges do
      local match = false
      pcall(function()
        if ranges[j].bag == bag then
          match = true
        end
      end)
      if match or (Slots.IsReagentBag(ranges[j].bag) and Slots.IsReagentBag(bag)) then
        already = true
        break
      end
    end
    if not already then
      local n = Slots.NumSlotsForBag(bag)
      if n > 0 then
        ranges[#ranges + 1] = {
          bag = bag,
          slots = n,
          reagent = Slots.IsReagentBag(bag),
        }
      end
    end
  end
  return ranges
end

function Slots.SlotOccupied(bag, slot)
  if C_Container and C_Container.GetContainerItemID then
    local ok, res = pcall(C_Container.GetContainerItemID, bag, slot)
    if ok and res ~= nil then
      return true
    end
  end
  if C_Container and C_Container.GetContainerItemInfo then
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and type(info) == "table" then
      if info.itemID ~= nil or info.iconFileID ~= nil or info.hyperlink ~= nil then
        return true
      end
    end
  end
  return false
end

local function EnsureHost()
  if host then
    return host
  end
  host = CreateFrame("Frame", "BetterBackpackSlotHost", UIParent)
  host:SetSize(1, 1)
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -9000, 0)
  host:Hide()
  return host
end

local function EnsureCooldown(btn)
  if not btn then
    return nil
  end
  local cd = btn.cooldown or btn.Cooldown
  if cd then
    btn.cooldown = cd
    return cd
  end
  pcall(function()
    cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints(btn)
    cd:SetDrawEdge(false)
    if cd.SetHideCountdownNumbers then
      cd:SetHideCountdownNumbers(false)
    end
    btn.cooldown = cd
    btn.Cooldown = cd
  end)
  return btn.cooldown
end

function Slots.SyncCooldown(btn, bag, slot)
  local cd = EnsureCooldown(btn)
  if not cd then
    return
  end
  local start, duration, enable
  if C_Container and C_Container.GetContainerItemCooldown then
    local ok, s, d, e = pcall(C_Container.GetContainerItemCooldown, bag, slot)
    if ok then
      start, duration, enable = s, d, e
    end
  elseif GetContainerItemCooldown then
    local ok, s, d, e = pcall(GetContainerItemCooldown, bag, slot)
    if ok then
      start, duration, enable = s, d, e
    end
  end
  if IsSecret(start) or IsSecret(duration) or IsSecret(enable) then
    return
  end
  if type(start) == "number" and type(duration) == "number" and duration > 0 and enable ~= 0 then
    cd:SetCooldown(start, duration)
  else
    cd:Clear()
  end
end

function Slots.SyncVisual(btn, bag, slot)
  if not btn or not C_Container or not C_Container.GetContainerItemInfo then
    return
  end
  pcall(function()
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if not ok or type(info) ~= "table" then
      local icon = btn.icon or btn.Icon
      if icon then
        icon:SetTexture(nil)
      end
      if btn.Count and btn.Count.SetText then
        btn.Count:SetText("")
      end
      Slots.SyncCooldown(btn, bag, slot)
      return
    end
    local icon = btn.icon or btn.Icon
    if icon and info.iconFileID and not IsSecret(info.iconFileID) then
      icon:SetTexture(info.iconFileID)
    elseif icon and not info.iconFileID then
      icon:SetTexture(nil)
    end
    local count = SafeNum(info.stackCount or info.Count, 1) or 1
    if SetItemButtonCount then
      SetItemButtonCount(btn, count)
    elseif btn.Count and btn.Count.SetText then
      btn.Count:SetText(count > 1 and tostring(count) or "")
    end
    if SetItemButtonQuality and type(info.quality) == "number" and not IsSecret(info.quality) then
      SetItemButtonQuality(btn, info.quality, info.itemID)
    end
    Slots.SyncCooldown(btn, bag, slot)
  end)
end

function Slots.SyncAttrs(btn, bag, slot)
  if not btn or not btn._bbSecure then
    return
  end
  if InCombatLockdown and InCombatLockdown() then
    return
  end
  local Context = BetterBackpack.Modules.Context
  local b, s = Slots.AttrBagSlot(bag, slot)
  if not b or not s then
    return
  end
  local itemStr = b .. " " .. s
  local special = Context and Context.SpecialRmbContext and Context.SpecialRmbContext()
  pcall(function()
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("useOnKeyDown", false)
    btn:SetAttribute("bag2", b)
    btn:SetAttribute("slot2", s)
    btn:SetAttribute("bag", b)
    btn:SetAttribute("slot", s)
    btn:SetAttribute("item", itemStr)
    btn:SetAttribute("macrotext2", nil)
    btn:SetAttribute("*macrotext2", nil)
    btn:SetAttribute("type1", nil)
    btn:SetAttribute("macrotext1", nil)
    btn:SetAttribute("*type1", nil)
    btn:SetAttribute("*macrotext1", nil)
    if special then
      btn:SetAttribute("type2", nil)
      btn:SetAttribute("*type2", nil)
      btn:SetAttribute("item2", nil)
    else
      btn:SetAttribute("type2", "item")
      btn:SetAttribute("*type2", "item")
      btn:SetAttribute("item2", itemStr)
    end
  end)
end

function Slots.ClearRmbUse(btn)
  if not btn or not btn.SetAttribute or (InCombatLockdown and InCombatLockdown()) then
    return
  end
  pcall(function()
    btn:SetAttribute("type2", nil)
    btn:SetAttribute("*type2", nil)
    btn:SetAttribute("macrotext2", nil)
    btn:SetAttribute("*macrotext2", nil)
    btn:SetAttribute("item2", nil)
  end)
end

function Slots.SyncAllAttrs()
  if InCombatLockdown and InCombatLockdown() then
    return
  end
  for _, btn in pairs(buttons) do
    if btn and btn._bbSecure and btn._bbBag ~= nil and btn._bbSlot ~= nil then
      Slots.SyncAttrs(btn, btn._bbBag, btn._bbSlot)
    end
  end
end

function Slots.ForceRestoreItemUse()
  if InCombatLockdown and InCombatLockdown() then
    return
  end
  for _, btn in pairs(buttons) do
    if btn and btn._bbSecure and btn._bbBag ~= nil and btn._bbSlot ~= nil then
      btn._bbSpecialRmb = nil
      Slots.SyncAttrs(btn, btn._bbBag, btn._bbSlot)
    end
  end
end

local function IsSpellTargetingItem()
  if SpellIsTargeting then
    local ok, v = pcall(SpellIsTargeting)
    if ok and v then
      return true
    end
  end
  if SpellCanTargetItem then
    local ok, v = pcall(SpellCanTargetItem)
    if ok and v then
      return true
    end
  end
  if GetCursorInfo then
    local ok, kind = pcall(GetCursorInfo)
    if ok and kind == "spell" then
      return true
    end
  end
  return false
end

local function ArmLmbUse(self)
  if not self or (InCombatLockdown and InCombatLockdown()) then
    return
  end
  local b, s = Slots.AttrBagSlot(self._bbBag, self._bbSlot)
  if not b or not s then
    return
  end
  local useMacro = string.format("/use %d %d", b, s)
  pcall(function()
    self:SetAttribute("type1", "macro")
    self:SetAttribute("macrotext1", useMacro)
    self:SetAttribute("*type1", "macro")
    self:SetAttribute("*macrotext1", useMacro)
  end)
end

local function ClearLmbUse(self)
  if not self or (InCombatLockdown and InCombatLockdown()) then
    return
  end
  pcall(function()
    self:SetAttribute("type1", nil)
    self:SetAttribute("macrotext1", nil)
    self:SetAttribute("*type1", nil)
    self:SetAttribute("*macrotext1", nil)
  end)
end

local function WireScripts(btn)
  if btn._bbWired then
    if not (InCombatLockdown and InCombatLockdown()) then
      btn:RegisterForClicks("AnyUp", "AnyDown")
    end
    return
  end
  btn._bbWired = true
  local function pickup(self)
    if InCombatLockdown and InCombatLockdown() then
      return
    end
    if IsSpellTargetingItem() then
      return
    end
    local b, s = self._bbBag, self._bbSlot
    if not b or not s then
      return
    end
    if C_Container and C_Container.PickupContainerItem then
      pcall(C_Container.PickupContainerItem, b, s)
    elseif PickupContainerItem then
      pcall(PickupContainerItem, b, s)
    end
  end
  btn:RegisterForClicks("AnyUp", "AnyDown")
  btn:RegisterForDrag("LeftButton")
  btn:SetScript("OnDragStart", pickup)
  btn:SetScript("OnReceiveDrag", pickup)
  if btn.HookScript then
    btn:HookScript("OnMouseDown", function(self, button)
      local Context = BetterBackpack.Modules.Context
      if button == "RightButton" and Context and Context.SpecialRmbContext and Context.SpecialRmbContext() then
        Slots.ClearRmbUse(self)
        self._bbSpecialRmb = true
        return
      end
      if button ~= "LeftButton" then
        return
      end
      self._bbLmbDown = true
      if IsSpellTargetingItem() then
        self._bbSpellTarget = true
        ArmLmbUse(self)
      end
    end)
    btn:HookScript("OnMouseUp", function(self, button)
      local Context = BetterBackpack.Modules.Context
      if button == "RightButton" then
        if self._bbSpecialRmb or (Context and Context.SpecialRmbContext and Context.SpecialRmbContext()) then
          if Context and Context.TrySpecialRmb then
            Context.TrySpecialRmb(self)
          end
        end
        self._bbSpecialRmb = nil
        return
      end
      if button == "LeftButton" and self._bbLmbDown and not self._bbDragging then
        if self._bbSpellTarget then
          if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
              ClearLmbUse(self)
              self._bbSpellTarget = nil
            end)
          else
            ClearLmbUse(self)
            self._bbSpellTarget = nil
          end
        else
          pickup(self)
        end
      end
      self._bbLmbDown = nil
      self._bbDragging = nil
    end)
    btn:HookScript("OnDragStart", function(self)
      self._bbDragging = true
    end)
  end
  btn:SetScript("OnEnter", function(self)
    if not self._bbBag or not self._bbSlot then
      return
    end
    if self._bbSecure and not (InCombatLockdown and InCombatLockdown()) then
      Slots.SyncAttrs(self, self._bbBag, self._bbSlot)
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetBagItem, GameTooltip, self._bbBag, self._bbSlot)
    local Context = BetterBackpack.Modules.Context
    local ctx = Context and Context.SpecialRmbContext and Context.SpecialRmbContext()
    if ctx == "merchant" then
      GameTooltip:AddLine("RMB = sell to vendor", 0.2, 1, 0.4, true)
    elseif ctx == "mail" then
      GameTooltip:AddLine("RMB = attach to mail", 0.2, 1, 0.4, true)
    elseif ctx == "bank" then
      GameTooltip:AddLine("RMB = deposit to bank", 0.2, 1, 0.4, true)
    else
      GameTooltip:AddLine("RMB = use / learn", 0.6, 0.8, 1, true)
    end
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
end

local function MakeVisualOnly(name, parent)
  local btn
  pcall(function()
    btn = CreateFrame("ItemButton", name, parent, "ItemButtonTemplate")
  end)
  if not btn then
    btn = CreateFrame("Button", name, parent)
    btn:SetSize(SLOT, SLOT)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon
    btn.Icon = icon
    local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.Count = count
  end
  EnsureCooldown(btn)
  btn._bbSecure = false
  return btn
end

function Slots.Acquire(bag, slot)
  local key = Slots.BagSlotKey(bag, slot)
  local btn = buttons[key]
  local inCombat = InCombatLockdown and InCombatLockdown()
  if btn and not btn._bbSecure and not inCombat then
    pcall(function()
      btn:SetAlpha(0)
      btn:EnableMouse(false)
      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 0)
      btn:SetParent(EnsureHost())
    end)
    buttons[key] = nil
    btn = nil
  end
  if btn then
    if not inCombat and btn._bbSecure then
      Slots.SyncAttrs(btn, bag, slot)
    end
    btn._bbBag = bag
    btn._bbSlot = slot
    return btn
  end
  local parent = EnsureHost()
  local name = "BetterBackpackSlot_" .. tostring(key):gsub("[^%w]", "_")
  if inCombat then
    btn = MakeVisualOnly(name .. "V", parent)
    btn._bbProxy = true
    btn._bbBag = bag
    btn._bbSlot = slot
    WireScripts(btn)
    buttons[key] = btn
    return btn
  end
  local isSecure = false
  pcall(function()
    btn = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    isSecure = btn ~= nil
  end)
  if not btn then
    btn = MakeVisualOnly(name, parent)
    isSecure = false
  else
    btn:SetSize(SLOT, SLOT)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon
    btn.Icon = icon
    local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.Count = count
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture([[Interface\Common\WhiteIconFrame]])
    border:SetAllPoints()
    border:Hide()
    btn.IconBorder = border
    EnsureCooldown(btn)
  end
  btn._bbSecure = isSecure and true or false
  btn._bbProxy = true
  btn._bbBag = bag
  btn._bbSlot = slot
  btn._bbWired = nil
  WireScripts(btn)
  if isSecure then
    Slots.SyncAttrs(btn, bag, slot)
  end
  buttons[key] = btn
  return btn
end

function Slots.Get(bag, slot)
  return buttons[Slots.BagSlotKey(bag, slot)]
end

function Slots.ForEach(fn)
  for key, btn in pairs(buttons) do
    fn(btn, key)
  end
end

function Slots.CountSecure()
  local n, attrs = 0, 0
  for _, btn in pairs(buttons) do
    if btn and btn._bbSecure then
      n = n + 1
      local t2 = btn.GetAttribute and btn:GetAttribute("type2")
      local i2 = btn.GetAttribute and btn:GetAttribute("item2")
      if t2 == "item" and type(i2) == "string" and i2:find("%d") then
        attrs = attrs + 1
      end
    end
  end
  return n, attrs
end

function Slots.PreCreate()
  if preCreated then
    return true
  end
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  EnsureHost()
  local bags = { 0, 1, 2, 3, 4, Slots.ReagentBagIndex() }
  if not Slots.IsReagentBag(5) then
    bags[#bags + 1] = 5
  end
  for i = 1, #bags do
    local bag = bags[i]
    for slot = 1, 36 do
      local btn = Slots.Acquire(bag, slot)
      Slots.SyncAttrs(btn, bag, slot)
    end
  end
  preCreated = true
  return true
end

function Slots.IsPreCreated()
  return preCreated
end

function Slots.Place(btn, parent, x, y, shown)
  if not btn then
    return
  end
  local inCombat = InCombatLockdown and InCombatLockdown()
  if shown == nil then
    shown = true
  end
  pcall(function()
    btn:SetParent(parent or EnsureHost())
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    btn:SetSize(SLOT, SLOT)
    btn:SetFrameLevel((parent:GetFrameLevel() or 1) + 10)
    local mouseOn = shown and (btn._bbSecure or not inCombat)
    btn:EnableMouse(mouseOn and true or false)
    if shown then
      btn:SetAlpha(1)
      btn:Show()
      Slots.SyncVisual(btn, btn._bbBag, btn._bbSlot)
      if btn._bbSecure and not inCombat then
        Slots.SyncAttrs(btn, btn._bbBag, btn._bbSlot)
      end
    else
      btn:SetAlpha(0)
      btn:EnableMouse(false)
      btn:Show()
    end
  end)
end

function Slots.ParkUnused(used)
  local inCombat = InCombatLockdown and InCombatLockdown()
  for _, btn in pairs(buttons) do
    if not used[btn] then
      pcall(function()
        btn:SetAlpha(0)
        btn:EnableMouse(false)
        if not inCombat or not btn._bbSecure then
          btn:ClearAllPoints()
          btn:SetPoint("TOPLEFT", EnsureHost(), "TOPLEFT", 0, 0)
          btn:SetParent(EnsureHost())
        end
      end)
    end
  end
end

Slots.SLOT = SLOT
