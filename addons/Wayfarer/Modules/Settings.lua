--[[
  Wayfarer.Settings — the one settings window (/wf, minimap button left-click).
  Sections: General, Party marks; later Procs and Fishing. Plain widgets only, everything pcall-guarded.
]]

Wayfarer = Wayfarer or {}
Wayfarer.Modules = Wayfarer.Modules or {}

local Mod = {}
Wayfarer.Modules.Settings = Mod
Wayfarer.Settings = Mod

local frame
local widgets = {} -- refreshers
local PANEL_W, PANEL_H = 580, 460 -- same layout as the BetterBackpack settings
local NAV_W, PAD, TOP = 132, 10, 36
local WIDTH = PANEL_W - NAV_W - PAD * 3 - 26
local sections, navBtns, current = {}, {}, "general"
local SECTIONS = {
  { id = "general", label = "General" },
  { id = "marks", label = "Party marks" },
  { id = "procs", label = "Procs" },
  { id = "fishing", label = "Fishing" },
}

local function Profile()
  return Wayfarer.Config.GetProfile()
end

--- A template child is only used when it really is a widget object (not nil, not a method).
local function Obj(v)
  local t = type(v)
  return (t == "table" or t == "userdata") and v or nil
end

local function ApplyMarks()
  if Wayfarer.Modules.PartyMarks then
    Wayfarer.Modules.PartyMarks.Apply()
  end
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
  cb:SetScript("OnClick", function(self)
    local raw = self:GetChecked()
    set(raw == true or raw == 1)
  end)
  widgets[#widgets + 1] = function()
    cb:SetChecked(get() and true or false)
  end
  return cb
end

local function PickColor(c, onChange)
  local function apply()
    local r, g, b = ColorPickerFrame:GetColorRGB()
    onChange(r, g, b)
  end
  local prev = { r = c.r, g = c.g, b = c.b }
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({
      r = c.r, g = c.g, b = c.b, hasOpacity = false,
      swatchFunc = apply,
      cancelFunc = function()
        onChange(prev.r, prev.g, prev.b)
      end,
    })
  else
    ColorPickerFrame.func = apply
    ColorPickerFrame.cancelFunc = function()
      onChange(prev.r, prev.g, prev.b)
    end
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
    ColorPickerFrame:Show()
  end
end

local function Swatch(parent, label, y, getColor, setColor, isEnabled)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(22, 22)
  btn:SetPoint("TOPLEFT", 42, y)
  local border = btn:CreateTexture(nil, "BACKGROUND")
  border:SetAllPoints()
  border:SetColorTexture(1, 1, 1, 1)
  local fill = btn:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT", 2, -2)
  fill:SetPoint("BOTTOMRIGHT", -2, 2)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", btn, "RIGHT", 8, 0)
  text:SetText(label)
  btn:SetScript("OnClick", function()
    if isEnabled and not isEnabled() then
      return
    end
    PickColor(getColor(), function(r, g, b)
      setColor(r, g, b)
      fill:SetColorTexture(r, g, b, 1)
    end)
  end)
  widgets[#widgets + 1] = function()
    local c = getColor()
    local on = not isEnabled or isEnabled()
    fill:SetColorTexture(c.r, c.g, c.b, 1)
    btn:SetEnabled(on)
    btn:SetAlpha(on and 1 or 0.35)
    text:SetAlpha(on and 1 or 0.45)
    if not on and ColorPickerFrame and ColorPickerFrame:IsShown() then
      ColorPickerFrame:Hide()
    end
  end
  return btn
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
  s:SetScript("OnValueChanged", function(self, value)
    value = math.floor((value or min) + 0.5)
    if tx then
      tx:SetText(label .. ": " .. value)
    end
    if get() ~= value then
      set(value)
    end
  end)
  widgets[#widgets + 1] = function()
    s:SetValue(get())
    if tx then
      tx:SetText(label .. ": " .. get())
    end
  end
  return s
end

local function ShowSection(id)
  current = id
  for i = 1, #SECTIONS do
    local sid = SECTIONS[i].id
    local on = sid == id
    if sections[sid] then
      sections[sid]:SetShown(on)
    end
    local b = navBtns[i]
    if b then
      b.sel:SetShown(on)
      b.text:SetTextColor(on and 1 or 0.75, on and 0.82 or 0.75, on and 0 or 0.75)
    end
  end
  if frame and frame.scroll then
    frame.scroll:SetVerticalScroll(0)
    local sec = sections[id]
    frame.content:SetHeight(math.max(120, (sec and sec.height or 120) + 8))
    local sb = Obj(frame.scroll.ScrollBar)
    if sb then
      sb:SetShown(frame.content:GetHeight() - (frame.scroll:GetHeight() or 0) > 1)
    end
  end
end

local function NavButton(f, i)
  local btn = CreateFrame("Button", nil, f.nav)
  btn:SetSize(NAV_W - 8, 24)
  btn:SetPoint("TOPLEFT", f.nav, "TOPLEFT", 4, -(4 + (i - 1) * 26))
  local hl = btn:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.82, 0, 0.15)
  hl:Hide()
  local sel = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
  sel:SetAllPoints()
  sel:SetColorTexture(1, 0.82, 0, 0.28)
  sel:Hide()
  btn.sel = sel
  btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  btn.text:SetPoint("LEFT", 10, 0)
  btn.text:SetText(SECTIONS[i].label)
  btn:SetScript("OnClick", function()
    ShowSection(SECTIONS[i].id)
  end)
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

local function Build()
  local ok, f = pcall(CreateFrame, "Frame", "WayfarerSettings", UIParent, "BasicFrameTemplateWithInset")
  if not ok or not f then
    f = CreateFrame("Frame", "WayfarerSettings", UIParent, "BackdropTemplate")
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
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  local title = "Wayfarer \226\128\148 Settings"
  if f.SetTitle then
    pcall(f.SetTitle, f, title)
  elseif Obj(f.TitleText) then
    f.TitleText:SetText(title)
  else
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOP", 0, -14)
    t:SetText(title)
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

  for i = 1, #SECTIONS do
    NavButton(f, i)
    local sec = CreateFrame("Frame", nil, f.content)
    sec:SetPoint("TOPLEFT")
    sec:SetSize(WIDTH, 600)
    sec:Hide()
    sections[SECTIONS[i].id] = sec
  end

  -- General
  local g = sections.general
  local y = 0
  Heading(g, "General", y)
  y = y - 30
  Check(g, "Show the minimap button", y, function()
    return Profile().minimap.show ~= false
  end, function(on)
    if Wayfarer.Modules.Minimap then
      Wayfarer.Modules.Minimap.SetShown(on)
    end
  end)
  y = y - 34
  Note(g, "Left-click the minimap button for this window, right-click to switch the marks on or off, drag it to move it. Chat commands: /wf help.", y)
  g.height = -y + 40

  -- Party marks
  local m = sections.marks
  y = 0
  Heading(m, "Party and raid marks", y)
  y = y - 30
  Check(m, "Mark party and raid members on nameplates", y, function()
    return Profile().partyMarks.enabled
  end, function(on)
    Profile().partyMarks.enabled = on
    ApplyMarks()
  end)
  y = y - 28
  Check(m, "Coloured outline around the health bar", y, function()
    return Profile().partyMarks.outline
  end, function(on)
    Profile().partyMarks.outline = on
    ApplyMarks()
  end)
  y = y - 28
  Check(m, "Small tag (P / R) left of the bar", y, function()
    return Profile().partyMarks.badge
  end, function(on)
    Profile().partyMarks.badge = on
    ApplyMarks()
  end)
  y = y - 34
  Check(m, "Use the class colour", y, function()
    return Profile().partyMarks.colorMode == "class"
  end, function(on)
    Profile().partyMarks.colorMode = on and "class" or "custom"
    ApplyMarks()
    Mod.Refresh()
  end)
  y = y - 30
  local notClass = function()
    return Profile().partyMarks.colorMode ~= "class"
  end
  Swatch(m, "Party colour (when not using class colour)", y, function()
    return Profile().partyMarks.partyColor
  end, function(r, g2, b)
    Profile().partyMarks.partyColor = { r = r, g = g2, b = b }
    ApplyMarks()
  end, notClass)
  y = y - 30
  Swatch(m, "Raid colour (when not using class colour)", y, function()
    return Profile().partyMarks.raidColor
  end, function(r, g2, b)
    Profile().partyMarks.raidColor = { r = r, g = g2, b = b }
    ApplyMarks()
  end, notClass)
  y = y - 46
  Slider(m, "Outline thickness", y, 1, 4, function()
    return Profile().partyMarks.thickness
  end, function(v)
    Profile().partyMarks.thickness = v
    ApplyMarks()
  end)
  y = y - 44
  Note(m, "Friendly player nameplates must be enabled in the game options for marks to show on players in cities. Marks are created out of combat; a nameplate seen for the first time in combat gets its mark afterwards.", y)
  y = y - 54
  m.friendsNote = Note(m, "Party marks need friendly nameplates: enable them in Options > Nameplates", y)
  m.friendsNote:SetTextColor(1, 0.55, 0.2)
  m.height = -y + 70
  widgets[#widgets + 1] = function()
    local on = GetCVar and GetCVar("nameplateShowFriends") == "0"
    m.friendsNote:SetShown(on and true or false)
  end

  -- Module sections: a module exports BuildSettings(sec, H) and returns the content height.
  -- H = { Heading, Note, Check, Swatch, Slider, Obj, Profile, width }; widgets register refreshers via H.Register(fn).
  local H = {
    Heading = Heading, Note = Note, Check = Check, Swatch = Swatch, Slider = Slider, Obj = Obj,
    Profile = Profile, width = WIDTH,
    Register = function(fn)
      widgets[#widgets + 1] = fn
    end,
  }
  local function ModuleSection(id, modName, title, soon)
    local sec = sections[id]
    local mod = Wayfarer.Modules[modName]
    if mod and mod.BuildSettings then
      local ok2, h = pcall(mod.BuildSettings, sec, H)
      if ok2 and type(h) == "number" then
        sec.height = h
        return
      end
      if not ok2 and Wayfarer.RecordError then
        Wayfarer.RecordError("Settings." .. modName, h)
      end
    end
    Heading(sec, title, 0)
    Note(sec, soon, -30)
    sec.height = 80
  end
  ModuleSection("procs", "ProcHUD", "Procs and timers", "Not available.")
  ModuleSection("fishing", "EasyFish", "Fishing", "Not available.")

  if UISpecialFrames then
    table.insert(UISpecialFrames, "WayfarerSettings")
  end
  frame = f
  f:Hide()
  ShowSection(current)
  return f
end

function Mod.Refresh()
  for i = 1, #widgets do
    pcall(widgets[i])
  end
end

function Mod.Ensure()
  if not frame then
    frame = Build()
  end
  return frame
end

function Mod.Show()
  Mod.Ensure()
  Mod.Refresh()
  frame:Show()
end

function Mod.Hide()
  if frame then
    frame:Hide()
  end
end

function Mod.Toggle()
  Mod.Ensure()
  if frame:IsShown() then
    frame:Hide()
  else
    Mod.Show()
  end
end
