--[[
  Forever Error Log — copyable error window + minimap button (0.3.1).
  Built lazily on first open. Plain frames, no libraries, no OnUpdate except while dragging the button.
]]

ForeverErrorLog = ForeverErrorLog or {}
local FE = ForeverErrorLog
local Config = FE.Config

local W = {}
FE.Window = W

local PAGE_SIZE = 20
local MAX_TEXT = 60000
local MONOREPO = { "ForeverErrorLog", "BetterBackpack", "Plateband", "Wayfarer", "Seekwell", "Seekwell_Locations" }

local ISSUES_URL = "https://github.com/sirTurbisCZ/wow-forever-addons/issues"
local CLEAR_CONFIRM_SECS = 3

local frame, edit, scroll, pageLabel, titleLabel, clearBtn
local clearArmedUntil = 0
local view, page = "session", 1
local minimapBtn

local function DB()
  return Config.EnsureDB()
end

local function Meta(name, field)
  local fn = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if not fn then
    return nil
  end
  local ok, v = pcall(fn, name, field)
  return ok and v or nil
end

local function IsLoaded(name)
  local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if not fn then
    return false
  end
  local ok, v = pcall(fn, name)
  return ok and v and true or false
end

local function Header()
  local lines = { "Report issues: " .. ISSUES_URL, "Forever Error Log v" .. tostring(Config.VERSION or "?") .. " - error report" }
  local ver, build, _, toc
  if GetBuildInfo then
    ver, build, _, toc = GetBuildInfo()
  end
  lines[#lines + 1] = string.format("Client: %s (build %s, interface %s)", tostring(ver), tostring(build), tostring(toc))
  lines[#lines + 1] = "Locale: " .. tostring(GetLocale and GetLocale() or "?")
  local mods = {}
  for i = 1, #MONOREPO do
    local n = MONOREPO[i]
    if n == "ForeverErrorLog" or IsLoaded(n) then
      mods[#mods + 1] = n .. " " .. tostring(Meta(n, "Version") or "?")
    end
  end
  lines[#lines + 1] = "Addons: " .. table.concat(mods, ", ")
  return table.concat(lines, "\n")
end

--- Returns the list shown for the current view and a label.
local function CurrentList()
  local db = DB()
  if view == "previous" then
    local arch = db.errorArchive and db.errorArchive.sessions or {}
    local s = arch[#arch]
    return (s and s.errors) or {}, "previous session" .. (s and s.at and (" (saved " .. tostring(s.at) .. ")") or "")
  end
  return db.errors or {}, "this session"
end

--- Escape '|' for display, then cut to `max` bytes on a UTF-8 character boundary without splitting a '||' pair.
local function FitText(text, max)
  text = text:gsub("|", "||")
  if #text <= max then
    return text, false
  end
  local cut = max
  -- never end before a continuation byte (0x80-0xBF): that would cut a multi-byte character
  while cut > 0 do
    local b = text:byte(cut + 1)
    if b and b >= 0x80 and b < 0xC0 then
      cut = cut - 1
    else
      break
    end
  end
  local head = text:sub(1, cut)
  local bars = #head:match("|*$")
  if bars % 2 == 1 then
    head = head:sub(1, -2)
  end
  return head, true
end
W.FitText = FitText

local function PageCount(n)
  return math.max(1, math.ceil(n / PAGE_SIZE))
end

--- Builds the report text for the current view/page (newest entries first).
function W.BuildText()
  local list, label = CurrentList()
  local n = #list
  local pages = PageCount(n)
  if page > pages then
    page = pages
  end
  if page < 1 then
    page = 1
  end
  local out = { Header(), string.format("View: %s - %d error(s) - page %d/%d", label, n, page, pages), "" }
  if n == 0 then
    out[#out + 1] = "No errors stored."
  end
  local first = n - (page - 1) * PAGE_SIZE
  local last = math.max(1, first - PAGE_SIZE + 1)
  local fmt = FE.FormatEntry
  for i = first, last, -1 do
    local e = list[i]
    if e then
      out[#out + 1] = fmt and fmt(e, i) or tostring(e.msg)
      if e.stack and e.stack ~= "" then
        out[#out + 1] = e.stack
      end
      out[#out + 1] = ""
    end
  end
  local text, cut = FitText(table.concat(out, "\n"), MAX_TEXT)
  if cut then
    text = text .. "\n... (page truncated, use Next)"
  end
  return text, page, pages
end

local function DisarmClear()
  clearArmedUntil = 0
  if clearBtn then
    clearBtn:SetText("Clear")
  end
end

function W.Refresh()
  if not frame then
    return
  end
  DisarmClear()
  local text, p, pages = W.BuildText()
  edit.fullText = text
  edit:SetText(text)
  if edit.SetCursorPosition then
    edit:SetCursorPosition(0)
  end
  if scroll.SetVerticalScroll then
    scroll:SetVerticalScroll(0)
  end
  pageLabel:SetText(string.format("%d / %d", p, pages))
  titleLabel:SetText("Forever Error Log - " .. (view == "previous" and "Previous" or "This session"))
end

local function SavePosition()
  local point, _, relPoint, x, y = frame:GetPoint()
  local w = DB().window
  w.point, w.relPoint, w.x, w.y = point, relPoint, x, y
end

local function Button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

--- Place the window from the saved position (centered when none is saved). No-op before it is built.
function W.ApplyPosition()
  if not frame then
    return
  end
  local w = DB().window
  frame:ClearAllPoints()
  if w.point then
    frame:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
  else
    frame:SetPoint("CENTER")
  end
end

local function Build()
  frame = CreateFrame("Frame", "ForeverErrorLogWindow", UIParent, "BackdropTemplate")
  frame:SetSize(640, 440)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
  end
  W.ApplyPosition()
  frame:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
  end)

  titleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleLabel:SetPoint("TOP", 0, -16)

  scroll = CreateFrame("ScrollFrame", "ForeverErrorLogScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 20, -40)
  scroll:SetPoint("BOTTOMRIGHT", -40, 48)

  edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
  edit:SetWidth(560)
  edit:SetMaxLetters(MAX_TEXT + 100)
  edit.fullText = ""
  -- Read-only feeling: selection and copy work, typing is undone.
  edit:SetScript("OnTextChanged", function(self, userInput)
    if userInput and self:GetText() ~= (self.fullText or "") then
      self:SetText(self.fullText or "")
    end
  end)
  edit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  scroll:SetScrollChild(edit)

  local bSession = Button(frame, "This session", 90, function()
    view, page = "session", 1
    W.Refresh()
  end)
  bSession:SetPoint("BOTTOMLEFT", 20, 16)
  local bPrev = Button(frame, "Previous", 80, function()
    view, page = "previous", 1
    W.Refresh()
  end)
  bPrev:SetPoint("LEFT", bSession, "RIGHT", 4, 0)

  local bPgPrev = Button(frame, "<", 28, function()
    page = page - 1
    W.Refresh()
  end)
  bPgPrev:SetPoint("LEFT", bPrev, "RIGHT", 16, 0)
  pageLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  pageLabel:SetPoint("LEFT", bPgPrev, "RIGHT", 6, 0)
  pageLabel:SetWidth(50)
  local bPgNext = Button(frame, ">", 28, function()
    page = page + 1
    W.Refresh()
  end)
  bPgNext:SetPoint("LEFT", pageLabel, "RIGHT", 2, 0)

  local bClose = Button(frame, "Close", 70, function()
    frame:Hide()
  end)
  bClose:SetPoint("BOTTOMRIGHT", -20, 16)
  clearBtn = Button(frame, "Clear", 70, function()
    W.ClearClicked()
  end)
  clearBtn:SetPoint("RIGHT", bClose, "LEFT", -4, 0)

  if UISpecialFrames then
    table.insert(UISpecialFrames, "ForeverErrorLogWindow")
  end
  frame:SetScript("OnShow", function()
    W.Refresh()
  end)
  frame:Hide()
end

--- Button handler: this session clears at once (it is archived); previous needs a second click within 3 s.
function W.ClearClicked()
  if view ~= "previous" then
    return W.Clear()
  end
  local t = GetTime and GetTime() or 0
  if clearArmedUntil > 0 and t <= clearArmedUntil then
    DisarmClear()
    return W.Clear()
  end
  clearArmedUntil = t + CLEAR_CONFIRM_SECS
  clearBtn:SetText("Really clear?")
  if C_Timer and C_Timer.After then
    local armed = clearArmedUntil
    C_Timer.After(CLEAR_CONFIRM_SECS, function()
      if clearArmedUntil == armed then
        DisarmClear()
      end
    end)
  end
end

--- Clear the viewed list: this session -> archived then wiped; previous -> archive dropped.
function W.Clear()
  if view == "previous" then
    local arch = DB().errorArchive
    if arch and arch.sessions then
      wipe(arch.sessions)
    end
  else
    FE.ClearErrors()
  end
  page = 1
  W.Refresh()
end

function W.Open()
  if not frame then
    Build()
  end
  frame:Show()
end

function W.Toggle()
  if frame and frame:IsShown() then
    frame:Hide()
  else
    W.Open()
  end
end

function W.IsBuilt()
  return frame ~= nil
end

-- ---------------------------------------------------------------- minimap button

local function PlaceButton()
  if not minimapBtn or not Minimap then
    return
  end
  local a = math.rad(tonumber(DB().minimap.angle) or 245)
  local radius = ((Minimap:GetWidth() or 140) / 2) + 4 -- the Forever minimap is larger than the classic 140 px
  minimapBtn:ClearAllPoints()
  minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
end

local function ShowTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("ForeverErrorLog")
  local list = DB().errors or {}
  GameTooltip:AddLine(string.format("%d error(s) this session", #list), 1, 1, 1)
  for i = #list, math.max(1, #list - 4), -1 do
    local e = list[i]
    local m = tostring(e.msg or "?"):gsub("%s+", " ")
    GameTooltip:AddLine(string.format("[%s] %s", tostring(e.addon or "?"), m:sub(1, 70)), 1, 0.4, 0.4)
  end
  GameTooltip:AddLine("Left-click: error window", 0.7, 0.7, 0.7)
  GameTooltip:AddLine("Right-click: settings hint /felog help", 0.7, 0.7, 0.7)
  GameTooltip:AddLine("Drag: move", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end

local function BuildButton()
  if minimapBtn or not Minimap then
    return
  end
  local b = CreateFrame("Button", "ForeverErrorLogMinimapButton", Minimap)
  minimapBtn = b
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b:SetScript("OnClick", function(self, btn)
    if btn == "RightButton" then
      print((FE.L and FE.L.PREFIX or "[ForeverErrorLog]") .. " /felog help")
    else
      W.Toggle()
    end
  end)
  b:SetScript("OnEnter", function(self)
    ShowTooltip(self)
  end)
  b:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  b:SetScript("OnDragStart", function(self)
    GameTooltip:Hide()
    -- OnUpdate exists only while the button is being dragged.
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      DB().minimap.angle = math.deg(math.atan2(cy / s - my, cx / s - mx)) % 360
      PlaceButton()
    end)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  PlaceButton()
  -- The minimap size can change after login (Forever minimap resize): keep the button on the ring.
  if Minimap.HookScript then
    pcall(Minimap.HookScript, Minimap, "OnSizeChanged", PlaceButton)
  end
end

function W.UpdateMinimap()
  if DB().minimapHide then
    if minimapBtn then
      minimapBtn:Hide()
    end
    return
  end
  BuildButton()
  if minimapBtn then
    minimapBtn:Show()
    PlaceButton()
  end
end

function W.ToggleMinimap()
  local db = DB()
  db.minimapHide = not db.minimapHide
  W.UpdateMinimap()
  print((FE.L and FE.L.PREFIX or "[ForeverErrorLog]") .. " minimap button " .. (db.minimapHide and "hidden" or "shown"))
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    pcall(W.UpdateMinimap)
  else
    pcall(PlaceButton)
  end
end)
