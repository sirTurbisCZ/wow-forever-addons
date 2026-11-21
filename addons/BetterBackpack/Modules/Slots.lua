--[[
  BetterBackpack.Slots — 1:1 bag:slot SecureActionButtons (path B CS-RMB).
  Never shared pool. Create/SetAttribute OOC only. Never harvest CombinedBags.Items.
  All visible slots forced to SLOT×SLOT (37) — one grid for every category.
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

function Slots.KeyringBagIndex()
  if Enum and Enum.BagIndex and Enum.BagIndex.Keyring ~= nil then
    return Enum.BagIndex.Keyring
  end
  if KEYRING_CONTAINER ~= nil then
    return KEYRING_CONTAINER
  end
  return -2
end

function Slots.IsKeyringBag(bag)
  if bag == nil then
    return false
  end
  local key = Slots.KeyringBagIndex()
  local match = false
  pcall(function()
    if bag == key then
      match = true
    end
  end)
  if match then
    return true
  end
  local plain = SafeNum(key, nil)
  if plain ~= nil then
    return SafeNum(bag, nil) == plain
  end
  return SafeNum(bag, nil) == -2
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
  if Slots.IsKeyringBag(bag) then
    b = "K"
  elseif Slots.IsReagentBag(bag) then
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
  if Slots.IsKeyringBag(bag) then
    local b = SafeNum(Slots.KeyringBagIndex(), nil) or SafeNum(bag, nil) or -2
    return b, s
  end
  if Slots.IsReagentBag(bag) then
    local b = SafeNum(Slots.ReagentBagIndex(), nil) or SafeNum(bag, nil) or 5
    return b, s
  end
  return SafeNum(bag, nil), s
end

function Slots.NumSlotsForBag(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    local ok, res = pcall(C_Container.GetContainerNumSlots, bag)
    if ok and type(res) == "number" and not IsSecret(res) and res > 0 and res <= 96 then
      return res
    end
  end
  -- Reagent bag on Forever may secret GetContainerNumSlots — recover via free+occupied.
  if Slots.IsReagentBag(bag) then
    local free
    if C_Container and C_Container.GetContainerNumFreeSlots then
      local ok, f = pcall(C_Container.GetContainerNumFreeSlots, bag)
      if ok and type(f) == "number" and not IsSecret(f) and f >= 0 then
        free = f
      end
    end
    local occ = 0
    local maxOcc = 0
    for slot = 1, 36 do
      if Slots.SlotOccupied(bag, slot) then
        occ = occ + 1
        maxOcc = slot
      end
    end
    if free ~= nil then
      local total = occ + free
      if total > 0 and total <= 98 then
        return total
      end
    end
    if maxOcc > 0 then
      return maxOcc
    end
  end
  return 0
end

-- Backpack + worn bags: 0 .. NUM_BAG_SLOTS. No bank/keyring.
function Slots.PlayerBagLastIndex()
  local last = NUM_BAG_SLOTS
  if type(last) ~= "number" or last < 0 or last > 12 then
    last = 4
  end
  return last
end

function Slots.IsPlayerBagIndex(bag)
  local b = SafeNum(bag, nil)
  if b == nil then
    return false
  end
  if Slots.IsKeyringBag(b) then
    return false
  end
  return b >= 0 and b <= Slots.PlayerBagLastIndex()
end

function Slots.PlayerBagRanges()
  local ranges = {}
  local last = Slots.PlayerBagLastIndex()
  for bag = 0, last do
    local n = Slots.NumSlotsForBag(bag)
    if n > 0 then
      ranges[#ranges + 1] = {
        bag = bag,
        slots = n,
        reagent = false,
        keyring = false,
      }
    end
  end
  return ranges
end

-- Footer + Materials: player bags 0..NUM_BAG_SLOTS + reagent. Never keyring invent.
function Slots.InventoryBagRanges()
  local ranges = Slots.PlayerBagRanges()
  local seen = {}
  for i = 1, #ranges do
    seen[ranges[i].bag] = true
  end
  local reb = Slots.ReagentBagIndex()
  local already = false
  for i = 1, #ranges do
    if ranges[i].reagent or (reb ~= nil and ranges[i].bag == reb) or Slots.IsReagentBag(ranges[i].bag) then
      already = true
      break
    end
  end
  if not already and reb ~= nil then
    local n = Slots.NumSlotsForBag(reb)
    if n > 0 then
      ranges[#ranges + 1] = {
        bag = reb,
        slots = n,
        reagent = true,
        keyring = false,
      }
    end
  end
  return ranges
end

-- Footer used/total (player + reagent). Chat parts include R=n.
function Slots.CountPlayerSlots()
  local parts = {}
  local total, free = 0, 0
  local ranges = Slots.InventoryBagRanges()
  for i = 1, #ranges do
    local bag, n = ranges[i].bag, ranges[i].slots
    if ranges[i].reagent then
      parts[#parts + 1] = string.format("R=%d", n)
    else
      parts[#parts + 1] = string.format("%d=%d", bag, n)
    end
    total = total + n
    for slot = 1, n do
      if not Slots.SlotOccupied(bag, slot) then
        free = free + 1
      end
    end
  end
  local used = total - free
  if used < 0 then
    used = 0
  end
  return used, total, free, table.concat(parts, " ")
end

-- Layout lanes: inventory (player+reagent) + keyring when real API reports slots.
function Slots.BagRanges()
  local ranges = Slots.InventoryBagRanges()
  local seen = {}
  for i = 1, #ranges do
    seen[ranges[i].bag] = true
  end
  local key = Slots.KeyringBagIndex()
  if key ~= nil and not seen[key] then
    -- only add keyring if GetContainerNumSlots returns real (no probe invent)
    local n = 0
    if C_Container and C_Container.GetContainerNumSlots then
      local ok, res = pcall(C_Container.GetContainerNumSlots, key)
      if ok and type(res) == "number" and not IsSecret(res) and res > 0 and res <= 96 then
        n = res
      end
    end
    if n > 0 then
      ranges[#ranges + 1] = {
        bag = key,
        slots = n,
        reagent = false,
        keyring = true,
      }
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
    -- Never keep park host Hidden — SecureActionButtons created under a
    -- Hidden parent can refuse to paint after SetParent to a shown frame.
    host:Show()
    host:SetAlpha(0)
    host:EnableMouse(false)
    return host
  end
  host = CreateFrame("Frame", "BetterBackpackSlotHost", UIParent)
  host:SetSize(SLOT, SLOT)
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -9000, 0)
  host:SetAlpha(0)
  host:EnableMouse(false)
  host:Show()
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

local function EnsureCountFs(btn)
  if not btn then
    return nil
  end
  local fs = btn.Count
  if not fs then
    pcall(function()
      fs = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    end)
    if not fs then
      fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    end
    btn.Count = fs
  end
  pcall(function()
    fs:ClearAllPoints()
    fs:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    fs:SetJustifyH("RIGHT")
    -- Always white — never green/quality-tinted count.
    fs:SetTextColor(1, 1, 1, 1)
    if fs.SetDrawLayer then
      fs:SetDrawLayer("OVERLAY", 7)
    end
    if fs.SetShadowOffset then
      fs:SetShadowOffset(1, -1)
    end
    if NumberFontNormal then
      fs:SetFontObject(NumberFontNormal)
    elseif GameFontHighlightSmall then
      fs:SetFontObject(GameFontHighlightSmall)
    end
  end)
  return fs
end

local function ResolveStackCount(info, bag, slot)
  if type(info) == "table" then
    for _, key in ipairs({ "stackCount", "Count", "quantity", "stack", "num" }) do
      local c = SafeNum(info[key], nil)
      if c and c >= 1 then
        return c
      end
    end
  end
  -- Legacy GetContainerItemInfo(bag,slot) → texture, count, ...
  if GetContainerItemInfo then
    local ok, a, b, c = pcall(GetContainerItemInfo, bag, slot)
    if ok then
      -- Retail-style table return
      if type(a) == "table" then
        local n = SafeNum(a.stackCount or a.Count, nil)
        if n and n >= 1 then
          return n
        end
      end
      -- Classic unpack: texture, itemCount, locked, quality, ...
      local n = SafeNum(b, nil) or SafeNum(c, nil)
      if n and n >= 1 then
        return n
      end
    end
  end
  if C_Container and C_Container.GetContainerItemInfo then
    local ok, info2 = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and type(info2) == "table" then
      local n = SafeNum(info2.stackCount or info2.Count, nil)
      if n and n >= 1 then
        return n
      end
    end
  end
  return 1
end

local function ResolveIconTexture(info, bag, slot)
  if type(info) == "table" then
    local file = info.iconFileID
    if file ~= nil and not IsSecret(file) then
      return file
    end
    local id = info.itemID
    if type(id) == "number" and not IsSecret(id) then
      if C_Item and C_Item.GetItemIconByID then
        local ok, tex = pcall(C_Item.GetItemIconByID, id)
        if ok and tex ~= nil and not IsSecret(tex) then
          return tex
        end
      end
      if GetItemIcon then
        local ok, tex = pcall(GetItemIcon, id)
        if ok and tex ~= nil and not IsSecret(tex) then
          return tex
        end
      end
    end
  end
  -- Legacy GetContainerItemInfo texture (non-secret string/number).
  if GetContainerItemInfo then
    local ok, a = pcall(GetContainerItemInfo, bag, slot)
    if ok then
      if type(a) == "string" and a ~= "" and not IsSecret(a) then
        return a
      end
      if type(a) == "number" and not IsSecret(a) then
        return a
      end
      if type(a) == "table" and a.iconFileID ~= nil and not IsSecret(a.iconFileID) then
        return a.iconFileID
      end
    end
  end
  return nil
end

-- Baganator Blizzard skin: empty SlotBackground under icon (CombinedBags-like).
-- Must stay above SyncVisual / Acquire / MakeVisualOnly (Lua 5.1 local scope).
local function EnsureSlotBackground(btn)
  if not btn or btn.SlotBackground then
    return btn and btn.SlotBackground
  end
  local sb
  pcall(function()
    sb = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    sb:SetAllPoints(btn)
    local ok = pcall(sb.SetAtlas, sb, "bags-item-slot64")
    if not ok then
      sb:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
      sb:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    end
    sb:SetAlpha(0.9)
    btn.SlotBackground = sb
  end)
  return btn.SlotBackground
end

function Slots.SyncVisual(btn, bag, slot)
  if not btn then
    return
  end
  pcall(function()
    local info
    if C_Container and C_Container.GetContainerItemInfo then
      local ok, res = pcall(C_Container.GetContainerItemInfo, bag, slot)
      if ok and type(res) == "table" then
        info = res
      end
    end
    local icon = btn.icon or btn.Icon
    local tex = ResolveIconTexture(info, bag, slot)
    EnsureSlotBackground(btn)
    if not info and not tex then
      if icon then
        icon:SetTexture(nil)
        icon:Hide()
      end
      if btn.SlotBackground then
        btn.SlotBackground:Show()
      end
      if btn.IconBorder then
        btn.IconBorder:Hide()
      end
      local fs = EnsureCountFs(btn)
      if fs then
        fs:SetText("")
        fs:Hide()
      end
      Slots.SyncCooldown(btn, bag, slot)
      if Slots.Normalize then
        Slots.Normalize(btn)
      end
      return
    end
    if icon then
      if tex ~= nil then
        icon:SetTexture(tex)
        icon:SetAlpha(1)
        icon:Show()
      elseif not info or not info.iconFileID then
        icon:SetTexture(nil)
        icon:Hide()
      end
      -- secret iconFileID with no itemID fallback: leave prior tex; never SetTexture(secret)
    end
    if btn.SlotBackground then
      btn.SlotBackground:Show()
    end
    local count = ResolveStackCount(info, bag, slot)
    local fs = EnsureCountFs(btn)
    -- count==1 (quest uniques etc.) → blank; count>1 → always white number.
    if fs then
      fs:SetTextColor(1, 1, 1, 1)
      if type(count) == "number" and count > 1 then
        fs:SetText(tostring(count))
        fs:Show()
      else
        fs:SetText("")
        fs:Hide()
      end
    end
    if SetItemButtonQuality and type(info.quality) == "number" and not IsSecret(info.quality) then
      SetItemButtonQuality(btn, info.quality, info.itemID)
    end
    -- Re-force white after quality (some builds tint Count).
    if fs and type(count) == "number" and count > 1 then
      fs:SetTextColor(1, 1, 1, 1)
      fs:Show()
    end
    Slots.SyncCooldown(btn, bag, slot)
    if Slots.Normalize then
      Slots.Normalize(btn)
    end
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
  if btn then
    btn:SetSize(SLOT, SLOT)
    btn:SetScale(1)
    EnsureSlotBackground(btn)
  end
  if not btn then
    btn = CreateFrame("Button", name, parent)
    btn:SetSize(SLOT, SLOT)
    EnsureSlotBackground(btn)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon
    btn.Icon = icon
    local count
    pcall(function()
      count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    end)
    if not count then
      count = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    end
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
    EnsureSlotBackground(btn)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon
    btn.Icon = icon
    local count
    pcall(function()
      count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    end)
    if not count then
      count = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    end
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
  local ranges = Slots.BagRanges()
  for i = 1, #ranges do
    local bag, n = ranges[i].bag, ranges[i].slots
    for slot = 1, n do
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

-- One grid size for every category (ItemButtonTemplate / quality border drift).
local function NormalizeSlotVisual(btn)
  if not btn then
    return
  end
  EnsureSlotBackground(btn)
  pcall(function()
    btn:SetScale(1)
    if btn.SetIgnoreParentScale then
      btn:SetIgnoreParentScale(false)
    end
    btn:SetSize(SLOT, SLOT)
    btn:SetWidth(SLOT)
    btn:SetHeight(SLOT)
    if btn.SetHitRectInsets then
      btn:SetHitRectInsets(0, 0, 0, 0)
    end
  end)
  if btn.SlotBackground then
    pcall(function()
      btn.SlotBackground:ClearAllPoints()
      btn.SlotBackground:SetAllPoints(btn)
      btn.SlotBackground:Show()
    end)
  end
  local ic = btn.icon or btn.Icon or btn.IconTexture
  if ic then
    pcall(function()
      ic:ClearAllPoints()
      ic:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
      ic:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
      ic:SetSize(SLOT, SLOT)
      ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      if ic.SetDrawLayer then
        ic:SetDrawLayer("ARTWORK", 0)
      end
      ic:SetAlpha(1)
      ic:Show()
    end)
  end
  pcall(function()
    local nt = btn.GetNormalTexture and btn:GetNormalTexture()
    if nt then
      nt:ClearAllPoints()
      nt:SetAllPoints(btn)
      nt:SetSize(SLOT, SLOT)
    end
    local pt = btn.GetPushedTexture and btn:GetPushedTexture()
    if pt then
      pt:ClearAllPoints()
      pt:SetAllPoints(btn)
    end
    local ht = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if ht then
      ht:ClearAllPoints()
      ht:SetAllPoints(btn)
    end
  end)
  -- Quality / overlay chrome must not inflate past SLOT.
  for _, key in ipairs({ "IconBorder", "IconOverlay", "IconOverlay2", "IconQuestTexture", "flash" }) do
    local r = btn[key]
    if r and r.ClearAllPoints then
      pcall(function()
        r:ClearAllPoints()
        r:SetAllPoints(btn)
        if r.SetSize then
          r:SetSize(SLOT, SLOT)
        end
      end)
    end
  end
  if btn.Count then
    pcall(function()
      btn.Count:ClearAllPoints()
      btn.Count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    end)
  end
  if btn.cooldown or btn.Cooldown then
    pcall(function()
      local cd = btn.cooldown or btn.Cooldown
      cd:ClearAllPoints()
      cd:SetAllPoints(btn)
    end)
  end
end

function Slots.Normalize(btn)
  NormalizeSlotVisual(btn)
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
    parent = parent or EnsureHost()
    parent:Show()
    btn:Show()
    btn:SetParent(parent)
    btn:ClearAllPoints()
    -- TOPLEFT + explicit 37×37 (dual-anchor stretched some ItemButtons unevenly).
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    NormalizeSlotVisual(btn)
    -- No SetFrameStrata on slot buttons (Forever BLOCKED noise).
    local base = (parent.GetFrameLevel and parent:GetFrameLevel()) or 1
    btn:SetFrameLevel(base + 80)
    local mouseOn = shown and (btn._bbSecure or not inCombat)
    btn:EnableMouse(mouseOn and true or false)
    if shown then
      btn:SetAlpha(1)
      btn:Show()
      NormalizeSlotVisual(btn)
      Slots.SyncVisual(btn, btn._bbBag, btn._bbSlot)
      -- SetItemButtonQuality can resize IconBorder — normalize again after.
      NormalizeSlotVisual(btn)
      btn:SetAlpha(1)
      btn:Show()
      if btn._bbSecure and not inCombat then
        Slots.SyncAttrs(btn, btn._bbBag, btn._bbSlot)
      end
      NormalizeSlotVisual(btn)
    else
      btn:SetAlpha(0)
      btn:EnableMouse(false)
      btn:Show()
      NormalizeSlotVisual(btn)
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
