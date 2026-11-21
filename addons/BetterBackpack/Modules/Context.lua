--[[
  BetterBackpack.Context — vendor / mail / bank RMB meaning.
  Never UseContainerItem from OnClick. Mail detect = MailFrame:IsVisible().
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local Context = {}
BetterBackpack.Modules.Context = Context

local Slots = BetterBackpack.Modules.Slots

local function MerchantIsOpen()
  return MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown()
end

local function MailSendIsOpen()
  if not (MailFrame and MailFrame.IsVisible) then
    return false
  end
  local okMail, mailVis = pcall(MailFrame.IsVisible, MailFrame)
  if not (okMail and mailVis) then
    return false
  end
  if SendMailFrame and SendMailFrame.IsVisible then
    local ok, vis = pcall(SendMailFrame.IsVisible, SendMailFrame)
    if ok and vis then
      return true
    end
  end
  local tab = MailFrame.selectedTab
  if type(tab) == "number" and tab == 2 then
    return true
  end
  return false
end

local function BankIsOpen()
  return BankFrame and BankFrame.IsShown and BankFrame:IsShown()
end

function Context.SpecialRmbContext()
  if MerchantIsOpen() then
    return "merchant"
  end
  if MailSendIsOpen() then
    return "mail"
  end
  if BankIsOpen() then
    return "bank"
  end
  return nil
end

local function PickupSlotToCursor(b, s)
  if ClearCursor then
    pcall(ClearCursor)
  end
  local picked = false
  if C_Container and C_Container.PickupContainerItem then
    picked = select(1, pcall(C_Container.PickupContainerItem, b, s))
  elseif PickupContainerItem then
    picked = select(1, pcall(PickupContainerItem, b, s))
  end
  if not picked then
    return false
  end
  if CursorHasItem then
    local ok, v = pcall(CursorHasItem)
    return ok and v and true or false
  end
  return true
end

function Context.TrySpecialRmb(self)
  if not self or (InCombatLockdown and InCombatLockdown()) then
    return false
  end
  local ctx = Context.SpecialRmbContext()
  if not ctx then
    return false
  end
  local b, s = self._bbBag, self._bbSlot
  if not b or not s then
    return false
  end
  if not PickupSlotToCursor(b, s) then
    return false
  end
  if ctx == "merchant" and SellCursorItem then
    pcall(SellCursorItem)
    return true
  end
  if ctx == "mail" and ClickSendMailItemButton then
    pcall(ClickSendMailItemButton)
    return true
  end
  if ctx == "bank" then
    if PutItemInBag then
      pcall(PutItemInBag, BANK_CONTAINER or -1)
      return true
    end
    if C_Container and C_Container.PutItemInBag then
      pcall(C_Container.PutItemInBag, BANK_CONTAINER or -1)
      return true
    end
  end
  if ClearCursor then
    pcall(ClearCursor)
  end
  return false
end

function Context.SyncSpecialMode()
  if Slots and Slots.SyncAllAttrs then
    Slots.SyncAllAttrs()
  end
end

function Context.ForceRestoreItemUse()
  if Slots and Slots.ForceRestoreItemUse then
    Slots.ForceRestoreItemUse()
  end
end

function Context.ForceRestoreDeferred()
  Context.ForceRestoreItemUse()
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      Context.ForceRestoreItemUse()
    end)
    C_Timer.After(0.15, function()
      Context.ForceRestoreItemUse()
    end)
  end
end
