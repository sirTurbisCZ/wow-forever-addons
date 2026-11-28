--[[
  Seekwell.Window — the one window (/sw, minimap button left-click), BetterBackpack / Wayfarer layout:
  section list on the left, scrollable content on the right (scrollbar only when needed).
  Sections: Target, Wishlist, Learned, Settings. Plain widgets only, everything pcall-guarded.
]]

Seekwell = Seekwell or {}
local Win = {}
Seekwell.Window = Win

local frame
local widgets = {} -- refreshers
local PANEL_W, PANEL_H = 580, 460 -- settings mode
local BIG_W, BIG_H = 1060, 680 -- browser mode (clamped to 92 % of UIParent)
local NAV_W, NAV_B, PAD, TOP = 132, 96, 10, 36
local WIDTH = PANEL_W - NAV_W - PAD * 3 - 26
local notes = {} -- { fs, sec, pad }: note widths follow the content width of their section's mode
local secMode = {} -- section frame -> mode
local layoutMode -- mode the frame is currently sized for
local MAX_WISH_SHOWN = 30
local sections, navBtns, current = {}, {}, "search"
-- Two modes of the same window: "browser" (Search, Wishlist, Zone + hidden detail pages) and "settings".
local mode, lastOf = "browser", { browser = "search", settings = "target" }
local SECTIONS = {
  { id = "target", label = "Target", mode = "settings" },
  { id = "wishlist", label = "Wishlist", mode = "browser" },
  { id = "learned", label = "Learned", mode = "settings" },
  { id = "settings", label = "Settings", mode = "settings" },
}
local registered = {} -- sections of feature modules: { id, label, build(sec, H) -> height }
local wishItems, wishLines = {}, {} -- pools
local wishInput, wishMsg
local learnedText, wishEmpty, bindingText
local refreshQueued = false

local function Settings()
  return Seekwell.Config.Get()
end

--- A template child is only used when it really is a widget object (not nil, not a method).
local function Obj(v)
  local t = type(v)
  return (t == "table" or t == "userdata") and v or nil
end

local function Heading(parent, text, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", 16, y)
  fs:SetText(text)
  return fs
end

local function Note(parent, text, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", 18, y)
  fs:SetWidth(WIDTH - 40)
  fs:SetJustifyH("LEFT")
  fs:SetTextColor(0.65, 0.65, 0.65)
  fs:SetText(text)
  notes[#notes + 1] = { fs = fs, sec = parent }
  return fs
end

local function Check(parent, label, y, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", 14, y)
  cb:SetSize(24, 24)
  local text = Obj(cb.text) or Obj(cb.Text)
  if not text then
    text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  end
  text:SetText(label)
  cb:SetScript("OnClick", Seekwell.Safe("window.check", function(self)
    local raw = self:GetChecked()
    set(raw == true or raw == 1)
  end))
  widgets[#widgets + 1] = function()
    cb:SetChecked(get() and true or false)
  end
  return cb
end

local function Slider(parent, label, y, min, max, get, set)
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", 48, y)
  s:SetWidth(170)
  s:SetMinMaxValues(min, max)
  s:SetValueStep(1)
  if s.SetObeyStepOnDrag then
    s:SetObeyStepOnDrag(true)
  end
  local name = s.GetName and s:GetName()
  if type(name) ~= "string" then
    name = nil
  end
  local lo = Obj(s.Low) or (name and Obj(_G[name .. "Low"]))
  local hi = Obj(s.High) or (name and Obj(_G[name .. "High"]))
  local tx = Obj(s.Text) or (name and Obj(_G[name .. "Text"]))
  if lo then
    lo:SetText(tostring(min))
  end
  if hi then
    hi:SetText(tostring(max))
  end
  s:SetScript("OnValueChanged", Seekwell.Safe("window.slider", function(_, value)
    value = math.floor((tonumber(value) or min) + 0.5)
    if tx then
      tx:SetText(label .. ": " .. value)
    end
    if get() ~= value then
      set(value)
    end
  end))
  widgets[#widgets + 1] = function()
    s:SetValue(get())
    if tx then
      tx:SetText(label .. ": " .. get())
    end
  end
  return s
end

local function Button(parent, label, x, y, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 160, 22)
  b:SetPoint("TOPLEFT", x, y)
  b:SetText(label)
  b:SetScript("OnClick", Seekwell.Safe("window.button", onClick))
  return b
end

--- Window size of a mode: w, h, nav width, content width.
local function ModeSize(m)
  if m ~= "browser" then
    return PANEL_W, PANEL_H, NAV_W, WIDTH
  end
  local pw = UIParent and UIParent.GetWidth and tonumber(UIParent:GetWidth()) or nil
  local ph = UIParent and UIParent.GetHeight and tonumber(UIParent:GetHeight()) or nil
  local w, h = BIG_W, BIG_H
  if pw and pw > 0 then
    w = math.min(w, math.floor(pw * 0.92))
  end
  if ph and ph > 0 then
    h = math.min(h, math.floor(ph * 0.92))
  end
  w, h = math.max(PANEL_W, w), math.max(PANEL_H, h)
  return w, h, NAV_B, w - NAV_B - PAD * 3 - 26
end
Win.ModeSize = ModeSize

--- Content width of the current mode (sections reflow to it).
function Win.ContentWidth(m)
  local _, _, _, cw = ModeSize(m or mode)
  return cw
end

--- Size of the area of a fixed (non-scrolling) section: w, h.
function Win.FixedArea(m)
  local _, h, _, cw = ModeSize(m or mode)
  return cw + 26, h - TOP - PAD
end

function Win.Size()
  if not frame then
    return nil
  end
  return frame.swW, frame.swH
end

local function PosStore()
  local ok, s = pcall(Settings)
  if not ok or type(s) ~= "table" or type(s.browser) ~= "table" then
    return nil
  end
  if type(s.browser.pos) ~= "table" then
    s.browser.pos = {}
  end
  return s.browser.pos
end

local function SavePos()
  if not frame then
    return
  end
  local point, _, rel, x, y = frame:GetPoint()
  local st = PosStore()
  if st and type(point) == "string" and tonumber(x) and tonumber(y) then
    st[layoutMode or mode] = { point, type(rel) == "string" and rel or point, tonumber(x), tonumber(y) }
  end
end

--- Resize the window and reflow the sections for mode m (only when the mode changes).
local function Relayout(m, force)
  if not frame or (layoutMode == m and not force) then
    return
  end
  if layoutMode and layoutMode ~= m then
    SavePos()
  end
  layoutMode = m
  local w, h, nw, cw = ModeSize(m)
  frame.swW, frame.swH = w, h
  frame:SetSize(w, h)
  frame:ClearAllPoints()
  local st = PosStore()
  local p = st and type(st[m]) == "table" and st[m] or nil
  if p and type(p[1]) == "string" and tonumber(p[3]) and tonumber(p[4]) then
    frame:SetPoint(p[1], UIParent, p[2] or p[1], p[3], p[4])
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, m == "browser" and 0 or 40)
  end
  frame.nav:SetSize(nw, h - TOP - PAD)
  frame.scroll:SetSize(cw, h - TOP - PAD)
  frame.content:SetWidth(cw)
  if frame.modeBtn then
    frame.modeBtn:SetWidth(nw - 16)
  end
  for i = 1, #navBtns do
    navBtns[i]:SetWidth(nw - 8)
  end
  for i = 1, #SECTIONS do
    local def = SECTIONS[i]
    local sec = sections[def.id]
    if sec and (def.mode or "settings") == m then
      if def.fixed then
        sec:SetSize(Win.FixedArea(m))
      else
        sec:SetWidth(cw)
      end
      sec.width = cw
    end
  end
  for _, n in ipairs(notes) do
    local sm = secMode[n.sec]
    if sm == m then
      pcall(n.fs.SetWidth, n.fs, cw - 40)
    end
  end
  for _, def in ipairs(registered) do
    if (def.mode or "settings") == m and type(def.layout) == "function" and sections[def.id] then
      local fw, fh = Win.FixedArea(m)
      local ok, err = pcall(def.layout, sections[def.id], def.fixed and fw or cw, fh)
      if not ok then
        Seekwell.RecordError("window.layout." .. def.id, err)
      end
    end
  end
end

local function UpdateScrollHeight()
  if not frame or not frame.scroll then
    return
  end
  local sec = sections[current]
  frame.content:SetHeight(math.max(120, (sec and sec.height or 120) + 8))
  local sb = Obj(frame.scroll.ScrollBar)
  if sb then
    sb:SetShown(frame.content:GetHeight() - (frame.scroll:GetHeight() or 0) > 1)
  end
end

local function SecDef(id)
  for i = 1, #SECTIONS do
    if SECTIONS[i].id == id then
      return SECTIONS[i]
    end
  end
  return nil
end

local function SetTitle(text)
  if not frame then
    return
  end
  if frame.SetTitle then
    pcall(frame.SetTitle, frame, text)
  elseif Obj(frame.TitleText) then
    frame.TitleText:SetText(text)
  elseif frame.titleFS then
    frame.titleFS:SetText(text)
  end
end

local function ShowSection(id)
  current = id
  local def = SecDef(id)
  mode = (def and def.mode) or "settings"
  lastOf[mode] = id
  Relayout(mode)
  if frame and frame.scroll then
    frame.scroll:SetShown(not (def and def.fixed))
  end
  local navId = (def and def.navAs) or id -- a hidden page highlights its parent nav entry
  local slot = 0
  for i = 1, #SECTIONS do
    local sid = SECTIONS[i].id
    local on = sid == id
    if sections[sid] then
      sections[sid]:SetShown(on)
    end
    local b = navBtns[i]
    if b then
      local inMode = (SECTIONS[i].mode or "settings") == mode
      b:SetShown(inMode)
      if inMode then
        slot = slot + 1
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame.nav, "TOPLEFT", 4, -(4 + (slot - 1) * 30))
      end
      local sel = sid == navId
      b.sel:SetShown(sel)
      b.bar:SetShown(sel)
      b.text:SetTextColor(sel and 1 or 0.75, sel and 0.82 or 0.75, sel and 0 or 0.75)
    end
  end
  if frame and frame.modeBtn then
    frame.modeBtn:SetText(mode == "browser" and "Settings >" or "< Browser")
  end
  SetTitle(mode == "browser" and "Seekwell" or "Seekwell - Settings")
  if frame and frame.scroll then
    frame.scroll:SetVerticalScroll(0)
  end
  Win.Refresh()
end
Win.ShowSection = ShowSection

local function NavButton(f, i, slot)
  local btn = CreateFrame("Button", nil, f.nav)
  btn:SetSize(NAV_W - 8, 26)
  btn:SetPoint("TOPLEFT", f.nav, "TOPLEFT", 4, -(4 + ((slot or i) - 1) * 26))
  local hl = btn:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.82, 0, 0.15)
  hl:Hide()
  local sel = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
  sel:SetAllPoints()
  sel:SetColorTexture(1, 0.82, 0, 0.28)
  sel:Hide()
  btn.sel = sel
  local bar = btn:CreateTexture(nil, "ARTWORK")
  bar:SetPoint("TOPLEFT", 0, 0)
  bar:SetPoint("BOTTOMLEFT", 0, 0)
  bar:SetWidth(3)
  bar:SetColorTexture(1, 0.82, 0, 1)
  bar:Hide()
  btn.bar = bar
  btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  btn.text:SetPoint("LEFT", 10, 0)
  btn.text:SetText(SECTIONS[i].label)
  btn:SetScript("OnClick", Seekwell.Safe("window.nav", function()
    ShowSection(SECTIONS[i].id)
  end))
  btn:SetScript("OnEnter", function()
    if current ~= SECTIONS[i].id then
      hl:Show()
    end
  end)
  btn:SetScript("OnLeave", function()
    hl:Hide()
  end)
  navBtns[i] = btn
end

local function BindingKeyText()
  local key = GetBindingKey and Seekwell.Secret.Get(GetBindingKey, "SEEKWELL_TARGET")
  if type(key) == "string" and key ~= "" then
    return "Current key: |cffffd100" .. key .. "|r"
  end
  return "No key set yet: Game Menu > Options > Key Bindings > AddOns > Seekwell > \"Show my target's drops\"."
end

local function BuildTarget(sec)
  local y = 0
  Heading(sec, "My target's drops", y)
  y = y - 30
  Note(sec, "A compact panel lists what drops from the mob in your target (or under the mouse): drop chance, where the value comes from (Forever n = measured kills, Classic estimate, learned = your own loot), a tick when you own the item and a star for your wishlist. It works in combat.", y)
  y = y - 58
  Button(sec, "Open the target panel", 16, y, 190, function()
    Seekwell.TargetPanel.Toggle()
  end)
  Button(sec, "Browse items and mobs", 214, y, 170, function()
    if Seekwell.Browser and Seekwell.Browser.Open then
      Seekwell.Browser.Open()
    end
  end)
  y = y - 34
  bindingText = Note(sec, "", y)
  y = y - 34
  Note(sec, "Also /sw target, or right-click the minimap button. In the panel: click a row = wishlist star, Shift+click = link the item in chat.", y)
  sec.height = -y + 50
end

local function WishItemLine(sec, i)
  local b = wishItems[i]
  if b then
    return b
  end
  b = CreateFrame("Button", nil, sec)
  b:SetSize(WIDTH - 110, 18)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(18, 18)
  b.icon:SetPoint("LEFT", 0, 0)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.text:SetPoint("LEFT", 24, 0)
  b.text:SetJustifyH("LEFT")
  b.text:SetWidth(WIDTH - 110 - 24 - 116)
  b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.count:SetPoint("RIGHT", b, "RIGHT", -62, 0)
  b.count:SetWidth(56)
  b.count:SetJustifyH("RIGHT")
  local okq, qty = pcall(CreateFrame, "EditBox", nil, b, "InputBoxTemplate")
  if not okq or not qty then
    qty = CreateFrame("EditBox", nil, b)
  end
  qty:SetSize(44, 20)
  qty:SetPoint("RIGHT", b, "RIGHT", -8, 0)
  qty:SetTextInsets(6, 6, 0, 0)
  qty:SetJustifyH("CENTER")
  qty:SetAutoFocus(false)
  qty:SetNumeric(true)
  qty:SetMaxLetters(4)
  qty:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
  local function CommitQty(self)
    if b.itemID then
      local v = tonumber(self:GetText())
      if v and v >= 1 then
        Seekwell.Wish.SetQty(b.itemID, v)
        Seekwell.Wish.RefreshOwned()
        Win.Refresh()
      end
    end
  end
  qty:SetScript("OnEnterPressed", function(self)
    CommitQty(self)
    self:ClearFocus()
  end)
  qty:SetScript("OnEditFocusLost", CommitQty)
  qty:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  b.qty = qty
  b:SetScript("OnEnter", Seekwell.Safe("window.wish.enter", function(self)
    if self.itemID and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if not pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID) then
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.itemID)
      end
      GameTooltip:Show()
    end
  end))
  b:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  b:SetScript("OnClick", Seekwell.Safe("window.wish.click", function(self)
    if self.itemID and Seekwell.ItemView and Seekwell.ItemView.Show then
      Seekwell.ItemView.Show(self.itemID)
    end
  end))
  b.remove = CreateFrame("Button", nil, sec, "UIPanelButtonTemplate")
  b.remove:SetSize(70, 18)
  b.remove:SetText("Remove")
  b.remove:SetPoint("LEFT", b, "RIGHT", 6, 0)
  b.remove:SetScript("OnClick", Seekwell.Safe("window.wish.remove", function()
    if b.itemID then
      Seekwell.Wish.Remove(b.itemID)
      Win.Refresh()
      if Seekwell.TargetPanel then
        Seekwell.TargetPanel.Render()
      end
    end
  end))
  wishItems[i] = b
  return b
end

local function WishSourceLine(sec, i)
  local fs = wishLines[i]
  if not fs then
    fs = sec:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    wishLines[i] = fs
  end
  fs:SetWidth(Win.ContentWidth("browser") - 60)
  return fs
end

local function RenderWishlist()
  local sec = sections.wishlist
  if not sec then
    return
  end
  local R, TP = Seekwell.Registry, Seekwell.TargetPanel
  local items = Seekwell.Wish.Items()
  -- owned items go last (they are ticked and ignored by alerts and hunts)
  table.sort(items, function(a, b)
    local oa, ob = Seekwell.Wish.IsOwned(a.id), Seekwell.Wish.IsOwned(b.id)
    if oa ~= ob then
      return not oa
    end
    if a.t ~= b.t then
      return a.t > b.t
    end
    return a.id < b.id
  end)
  local y = -122
  local ni, nl = 0, 0
  local cw = Win.ContentWidth("browser")
  if wishMsg then
    wishMsg:SetWidth(cw - 40)
  end
  for idx, w in ipairs(items) do
    if idx > MAX_WISH_SHOWN then
      break
    end
    ni = ni + 1
    local line = WishItemLine(sec, ni)
    local name, _, quality = TP.ItemInfo(w.id)
    line.itemID = w.id
    line:SetSize(cw - 110, 18)
    line.text:SetWidth(cw - 110 - 24 - 116)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", 16, y)
    local owned = Seekwell.Wish.IsOwned(w.id)
    local wq, have = Seekwell.Wish.Qty(w.id), Seekwell.Wish.Have(w.id)
    line.text:SetText((owned and "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t " or "") .. (name or ("item " .. w.id)))
    local _, _, _, icon = TP.ItemInfo(w.id)
    if icon then
      line.icon:SetTexture(icon)
    else
      line.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    if line.icon.SetDesaturated then
      line.icon:SetDesaturated(owned and true or false)
    end
    line.icon:Show()
    line.count:SetText(string.format("%s%d/%d|r", owned and "|cff55dd55" or "|cffffffff", have, wq))
    if not line.qty:HasFocus() then
      line.qty:SetText(tostring(wq))
    end
    line.qty:Show()
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if owned then
      line.text:SetTextColor(0.55, 0.55, 0.55)
    elseif type(c) == "table" and c.r then
      line.text:SetTextColor(c.r, c.g, c.b)
    else
      line.text:SetTextColor(1, 1, 1)
    end
    line:Show()
    line.remove:Show()
    y = y - 20
    local srcs = owned and Seekwell.Config.Get().wishIgnoreOwned ~= false and {} or R.ItemSources(w.id, 5)
    local djx = {} -- Dungeon Journal sources not already shown as a boss drop row (quest rewards, bosses without npc id)
    if not (owned and Seekwell.Config.Get().wishIgnoreOwned ~= false) and Seekwell.DJ then
      local shown = {}
      for _, src in ipairs(srcs) do
        if src.origin == "dj" then
          shown[tostring(src.dungeon) .. "|" .. tostring(src.boss)] = true
        end
      end
      local ok, rows = pcall(Seekwell.DJ.ItemSources, w.id)
      for _, r in ipairs(ok and rows or {}) do
        if #djx < 2 and not (r.source == "dungeon" and shown[tostring(r.dungeon) .. "|" .. tostring(r.boss)]) then
          djx[#djx + 1] = r
        end
      end
    end
    if owned and Seekwell.Config.Get().wishIgnoreOwned ~= false then
      nl = nl + 1
      local fs = WishSourceLine(sec, nl)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", 30, y)
      fs:SetText("you have it \194\183 left out of alerts and hunts")
      fs:SetTextColor(0.4, 0.75, 0.4)
      fs:Show()
      y = y - 16
    elseif #srcs == 0 and #djx == 0 then
      nl = nl + 1
      local fs = WishSourceLine(sec, nl)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", 30, y)
      fs:SetText("no known source (" .. (Seekwell.L.UNKNOWN or "-") .. ")")
      fs:SetTextColor(0.55, 0.55, 0.55)
      fs:Show()
      y = y - 16
    end
    for _, src in ipairs(srcs) do
      nl = nl + 1
      local fs = WishSourceLine(sec, nl)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", 30, y)
      fs:SetText((R.NpcName(src.npc) or ("npc " .. src.npc)) .. "  " .. R.FormatPct(src.p) .. "  \194\183 " .. R.OriginLabel(src))
      if src.origin == "classic" then
        fs:SetTextColor(0.62, 0.62, 0.62)
      else
        fs:SetTextColor(0.75, 0.88, 1)
      end
      fs:Show()
      y = y - 16
    end
    for _, r in ipairs(djx) do
      nl = nl + 1
      local fs = WishSourceLine(sec, nl)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", 30, y)
      fs:SetText(r.label .. "  \194\183 Dungeon Journal")
      fs:SetTextColor(0.95, 0.75, 0.35)
      fs:Show()
      y = y - 16
    end
    y = y - 6
  end
  for i = ni + 1, #wishItems do
    wishItems[i]:Hide()
    wishItems[i].remove:Hide()
    wishItems[i].qty:Hide()
  end
  for i = nl + 1, #wishLines do
    wishLines[i]:Hide()
  end
  if #items == 0 then
    wishEmpty:SetText("Your wishlist is empty. Type an item name above, or click a row in the target panel.")
  elseif #items > MAX_WISH_SHOWN then
    wishEmpty:SetText(string.format("%d items, the newest %d are shown.", #items, MAX_WISH_SHOWN))
  else
    wishEmpty:SetText(string.format("%d item(s). Row box = wanted amount; tick = you have that many.", #items))
  end
  sec.height = -y + 30
end

local function WishAdd()
  if not wishInput then
    return
  end
  local text = wishInput:GetText() or ""
  if text:match("^%s*$") then
    return
  end
  local st, info = Seekwell.Wish.AddByText(text)
  if st == "added" then
    wishMsg:SetText("Added " .. info.name .. (Seekwell.Wish.Qty(info.id) > 1 and (" x" .. Seekwell.Wish.Qty(info.id)) or "") .. ".")
    wishInput:SetText("")
  elseif st == "qty" then
    wishMsg:SetText(info.name .. ": wanted amount is now " .. Seekwell.Wish.Qty(info.id) .. ".")
    wishInput:SetText("")
  elseif st == "exists" then
    wishMsg:SetText(info.name .. " is already on the list.")
  elseif st == "many" then
    local names = {}
    for i, f in ipairs(info) do
      if i > 6 then
        break
      end
      names[#names + 1] = f.name
    end
    wishMsg:SetText("Several match: " .. table.concat(names, ", ") .. " \226\128\148 type more of the name.")
  else
    wishMsg:SetText("Nothing found. Items you have not met may need a second try; links and ids always work.")
  end
  RenderWishlist()
end

local function BuildWishlist(sec)
  Heading(sec, "Wishlist (this character)", 0)
  local label = sec:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("TOPLEFT", 18, -24)
  label:SetText("Add an item (name, link or id; e.g. linen cloth x20):")
  local ok, eb = pcall(CreateFrame, "EditBox", nil, sec, "InputBoxTemplate")
  if not ok or not eb then
    eb = CreateFrame("EditBox", nil, sec)
  end
  eb:SetSize(230, 20)
  eb:SetPoint("TOPLEFT", 24, -40)
  eb:SetAutoFocus(false)
  eb:SetFontObject(ChatFontNormal or GameFontHighlight)
  eb:SetScript("OnEnterPressed", function(self)
    WishAdd()
    self:ClearFocus()
  end)
  eb:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  wishInput = eb
  Button(sec, "Add", 262, -38, 60, WishAdd)
  wishMsg = sec:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  wishMsg:SetPoint("TOPLEFT", 18, -62)
  wishMsg:SetWidth(WIDTH - 40)
  wishMsg:SetJustifyH("LEFT")
  wishMsg:SetTextColor(0.8, 0.8, 0.5)
  wishEmpty = Note(sec, "", -100)
  sec.height = 160
end

local function RenderLearned()
  if not learnedText then
    return
  end
  local st = Seekwell.Learned.Stats()
  local T = Seekwell.Tinny
  local tinny
  if T.Available() then
    local c = T.Counts()
    tinny = string.format("Tinny data: Forever %d mobs (as of %s), Classic estimates %d mobs.", c.forever, tostring(T.AsOf() or "-"), c.starter)
  else
    tinny = Seekwell.L.TINNY_MISSING or "Tinny data not available"
  end
  learnedText:SetText(string.format("Learned from your loot: %d mobs, %d kills, %d drops.\nSaved data about %d KB (limit about %d mobs, the oldest are dropped).\n%s",
    st.npcs, st.kills, st.items, math.floor(st.bytes / 1024 + 0.5), Seekwell.Learned.CAP, tinny))
end

local function BuildLearned(sec)
  local y = 0
  Heading(sec, "Learned data", y)
  y = y - 30
  learnedText = sec:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  learnedText:SetPoint("TOPLEFT", 18, y)
  learnedText:SetWidth(WIDTH - 40)
  learnedText:SetJustifyH("LEFT")
  y = y - 70
  Check(sec, "Learn drops from my loot windows", y, function()
    return Settings().learn
  end, function(on)
    Settings().learn = on
  end)
  y = y - 36
  Button(sec, "Clear learned data", 16, y, 170, function()
    if StaticPopup_Show and StaticPopupDialogs then
      StaticPopup_Show("SEEKWELL_CLEAR_LEARNED")
    end
  end)
  y = y - 32
  Note(sec, "Only item ids, kill counts and the zone are stored, no positions. Tinny's data is read while you play and is never copied into Seekwell's saved data.", y)
  sec.height = -y + 50
end

local function ApplyTooltipChange()
  Seekwell.Registry.ClearCache()
  if Seekwell.TargetPanel then
    Seekwell.TargetPanel.Refresh(true)
  end
end

local function BuildSettings(sec)
  local y = 0
  Heading(sec, "Settings", y)
  y = y - 30
  Check(sec, "Show the minimap button", y, function()
    return Settings().minimap.show ~= false
  end, function(on)
    if Seekwell.Modules.Minimap then
      Seekwell.Modules.Minimap.SetShown(on)
    end
  end)
  y = y - 28
  Check(sec, "\"Drops from\" lines on item tooltips", y, function()
    return Settings().tooltip.enabled
  end, function(on)
    Settings().tooltip.enabled = on
  end)
  y = y - 28
  Check(sec, "Skip ours when the tooltip already has a \"Drops from\" list", y, function()
    return Settings().tooltip.skipIfDropsShown ~= false
  end, function(on)
    Settings().tooltip.skipIfDropsShown = on
  end)
  y = y - 28
  Check(sec, "Show \"Seekwell: wishlist 3/20\" on tooltips of wishlist items", y, function()
    return Settings().tooltip.wish ~= false
  end, function(on)
    Settings().tooltip.wish = on
  end)
  y = y - 46
  Slider(sec, "Tooltip sources", y, 1, 5, function()
    return tonumber(Settings().tooltip.max) or 3
  end, function(v)
    Settings().tooltip.max = v
  end)
  y = y - 40
  Check(sec, "Include Classic estimates (Tinny's Classic data)", y, function()
    return Settings().classic
  end, function(on)
    Settings().classic = on
    ApplyTooltipChange()
  end)
  y = y - 28
  Check(sec, "Wishlist: leave items I already own out of alerts and hunts", y, function()
    return Settings().wishIgnoreOwned ~= false
  end, function(on)
    Settings().wishIgnoreOwned = on
    Seekwell.Wish.RefreshOwned()
    Seekwell.Wish.generation = Seekwell.Wish.generation + 1
  end)
  y = y - 28
  Check(sec, "Hide quest items in drop lists", y, function()
    return Settings().hideQuest
  end, function(on)
    Settings().hideQuest = on
    ApplyTooltipChange()
  end)
  y = y - 28
  Check(sec, "Share learned data with group / guild", y, function()
    return Settings().share
  end, function(on)
    if Seekwell.Share and Seekwell.Share.Apply then
      Seekwell.Share.Apply(on)
    else
      Settings().share = on
    end
  end)
  y = y - 26
  Note(sec, "Off by default. Details, channels and counters: the Sharing section.", y)
  y = y - 34
  Note(sec, "Hotkey for the target panel: Game Menu > Options > Key Bindings > AddOns > Seekwell. Chat commands: /sw help.", y)
  sec.height = -y + 50
end

local function OnEvent(_, event)
  if event == "GET_ITEM_INFO_RECEIVED" and current == "wishlist" and not refreshQueued then
    refreshQueued = true
    local run = Seekwell.Safe("window.refresh", function()
      refreshQueued = false
      Win.Refresh()
    end)
    if C_Timer and C_Timer.After then
      C_Timer.After(0.3, run)
    else
      run()
    end
  end
end

local function Build()
  local ok, f = pcall(CreateFrame, "Frame", "SeekwellWindow", UIParent, "BasicFrameTemplateWithInset")
  if not ok or not f then
    f = CreateFrame("Frame", "SeekwellWindow", UIParent, "BackdropTemplate")
    if f.SetBackdrop then
      f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
      })
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
  end
  f:SetSize(PANEL_W, PANEL_H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    pcall(SavePos)
  end)
  local title = "Seekwell"
  if f.SetTitle then
    pcall(f.SetTitle, f, title)
  elseif Obj(f.TitleText) then
    f.TitleText:SetText(title)
  else
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOP", 0, -14)
    t:SetText(title)
    f.titleFS = t
  end

  f.nav = CreateFrame("Frame", nil, f)
  f.nav:SetPoint("TOPLEFT", PAD, -TOP)
  f.nav:SetSize(NAV_W, PANEL_H - TOP - PAD)
  local div = f:CreateTexture(nil, "ARTWORK")
  div:SetColorTexture(1, 1, 1, 0.12)
  div:SetWidth(1)
  div:SetPoint("TOP", f.nav, "TOPRIGHT", 4, 0)
  div:SetPoint("BOTTOM", f.nav, "BOTTOMRIGHT", 4, 0)

  local okS, scroll = pcall(CreateFrame, "ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  if not okS or not scroll then
    scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local max = self:GetVerticalScrollRange() or 0
      self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * 48)))
    end)
  end
  scroll:SetPoint("TOPLEFT", div, "TOPRIGHT", PAD, 0)
  scroll:SetSize(WIDTH, PANEL_H - TOP - PAD)
  local sb = Obj(scroll.ScrollBar)
  if sb then
    sb:ClearAllPoints()
    sb:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -16)
    sb:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 16)
    sb:Hide()
    scroll:HookScript("OnScrollRangeChanged", function(_, _, yRange)
      sb:SetShown((yRange or 0) > 1)
    end)
  end
  f.scroll = scroll
  f.content = CreateFrame("Frame", nil, scroll)
  f.content:SetSize(WIDTH, PANEL_H - TOP - PAD)
  scroll:SetScrollChild(f.content)

  local slot = 0
  for i = 1, #SECTIONS do
    if not SECTIONS[i].hidden then
      slot = slot + 1
      NavButton(f, i, slot)
    end
    local def = SECTIONS[i]
    local sm = def.mode or "settings"
    local sec
    if def.fixed then
      -- a fixed section fills the content area and scrolls its own lists
      sec = CreateFrame("Frame", nil, f)
      sec:SetPoint("TOPLEFT", div, "TOPRIGHT", PAD, 0)
      sec:SetSize(Win.FixedArea(sm))
    else
      sec = CreateFrame("Frame", nil, f.content)
      sec:SetPoint("TOPLEFT")
      sec:SetSize(Win.ContentWidth(sm), 600)
    end
    sec.width = Win.ContentWidth(sm)
    secMode[sec] = sm
    sec:Hide()
    sections[def.id] = sec
  end

  local builders = { target = BuildTarget, wishlist = BuildWishlist, learned = BuildLearned, settings = BuildSettings }
  for id, fn in pairs(builders) do
    local okB, err = pcall(fn, sections[id])
    if not okB then
      Seekwell.RecordError("window." .. id, err)
      sections[id].height = 80
    end
  end

  for _, def in ipairs(registered) do
    local sm = def.mode or "settings"
    local fw, fh = Win.FixedArea(sm)
    local H = { Heading = Heading, Note = Note, Check = Check, Slider = Slider, Button = Button, Obj = Obj,
      Settings = Settings, width = def.fixed and fw or Win.ContentWidth(sm), height = fh, ContentWidth = Win.ContentWidth }
    local okR, h = pcall(def.build, sections[def.id], H)
    if okR and type(h) == "number" then
      sections[def.id].height = h
    else
      if not okR then
        Seekwell.RecordError("window." .. def.id, h)
      end
      sections[def.id].height = 80
    end
  end

  f:SetScript("OnEvent", Seekwell.Safe("window.event", OnEvent))
  f:SetScript("OnShow", function(self)
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  end)
  f:SetScript("OnHide", function(self)
    self:UnregisterAllEvents()
  end)

  if StaticPopupDialogs and not StaticPopupDialogs.SEEKWELL_CLEAR_LEARNED then
    StaticPopupDialogs.SEEKWELL_CLEAR_LEARNED = {
      text = "Seekwell: forget all learned loot data? This cannot be undone.",
      button1 = YES or "Yes",
      button2 = NO or "No",
      OnAccept = Seekwell.Safe("window.clear", function()
        Seekwell.Learned.Clear()
        Seekwell.Registry.ClearCache()
        Seekwell.Print(Seekwell.L.LEARNED_RESET or "learned data cleared")
        Win.Refresh()
      end),
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
  end

  if UISpecialFrames then
    table.insert(UISpecialFrames, "SeekwellWindow")
  end
  local mb = CreateFrame("Button", nil, f.nav, "UIPanelButtonTemplate")
  mb:SetSize(NAV_W - 16, 22)
  mb:SetPoint("BOTTOMLEFT", f.nav, "BOTTOMLEFT", 6, 4)
  mb:SetText("Settings >")
  mb:SetScript("OnClick", Seekwell.Safe("window.mode", function()
    if mode == "browser" then
      Win.ShowSettings()
    else
      Win.ShowBrowser()
    end
  end))
  f.modeBtn = mb
  frame = f
  f:Hide()
  layoutMode = nil
  Relayout(mode, true)
  if not sections[current] then
    current = sections.search and "search" or "wishlist"
  end
  ShowSection(current)
  return f
end

--- Refresh widgets and the dynamic content of the visible section.
--- Feature modules add their own window section (call at file load, before the window is built).
--- build(sec, H): H = { Heading, Note, Check, Slider, Button, Obj, Settings, width }; returns the content height.
--- Optional: mode = "browser"|"settings" (default "settings"), hidden = true (no nav entry), navAs = id (nav entry highlighted while shown), before = id,
--- fixed = true (the section fills the content area instead of the scroll frame; it scrolls its own lists),
--- layout(sec, w, h) called when the window is resized for the section's mode.
function Win.RegisterSection(def)
  local pos = #SECTIONS
  for i = 1, #SECTIONS do
    if def.before and SECTIONS[i].id == def.before then
      pos = i
      break
    end
  end
  table.insert(SECTIONS, pos, { id = def.id, label = def.label, hidden = def.hidden, navAs = def.navAs,
    mode = def.mode or "settings", fixed = def.fixed })
  registered[#registered + 1] = def
end

function Win.Refresh()
  if not frame or not (frame.IsShown and frame:IsShown()) then
    return -- hidden: the sections render again when the window is shown
  end
  for i = 1, #widgets do
    pcall(widgets[i])
  end
  if current == "wishlist" then
    local ok, err = pcall(RenderWishlist)
    if not ok then
      Seekwell.RecordError("window.wishlist", err)
    end
  elseif current == "learned" then
    local ok, err = pcall(RenderLearned)
    if not ok then
      Seekwell.RecordError("window.learned", err)
    end
  elseif current == "target" and bindingText then
    bindingText:SetText(BindingKeyText())
  end
  UpdateScrollHeight()
end

function Win.Ensure()
  if not frame then
    frame = Build()
  end
  return frame
end

function Win.Show(section)
  Win.Ensure()
  if (section == "item" or section == "mob") and not sections[section] then
    section = "search" -- the item / mob pages are the right pane of the Search page since 0.3.1
  end
  frame:Show()
  if section and sections[section] then
    ShowSection(section)
  else
    Win.Refresh()
  end
end

function Win.Hide()
  if frame then
    frame:Hide()
  end
end

local function ShowMode(m, section)
  Win.Ensure()
  local def = section and SecDef(section)
  if not (def and sections[section] and (def.mode or "settings") == m) then
    section = lastOf[m]
    if not sections[section] then
      section = (m == "browser") and (sections.search and "search" or "wishlist") or "target"
    end
  end
  Win.Show(section)
end

--- The browser mode (default page: the last browser page, else "search").
function Win.ShowBrowser(section)
  ShowMode("browser", section)
end

--- The settings mode (default page: the last settings page, else "target").
function Win.ShowSettings(section)
  ShowMode("settings", section)
end

--- Toggle the window in browser mode; open in settings mode it switches to the browser instead of closing.
function Win.Toggle()
  Win.Ensure()
  if frame:IsShown() and mode == "browser" then
    frame:Hide()
  else
    Win.ShowBrowser()
  end
end

function Win.Current()
  return current
end

function Win.CurrentMode()
  return mode
end
