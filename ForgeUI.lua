-- ForgeUI: the settings widgets (switches, sliders, buttons, tabs, window) as
-- rounded shapes. They are nine-slices of one white disc, tinted per use, so any
-- size keeps crisp corners.
local addonName, ns = ...

-- The settings colours: warm grey with orange text and controls.
local PALETTE = {
    edge = { 1.00, 0.60, 0.25, 0.45 },
    surface = { 0.24, 0.23, 0.22, 0.97 },
    track = { 0.17, 0.16, 0.155, 1 },
    control = { 0.32, 0.305, 0.29, 1 },
    selected = { 0.66, 0.31, 0.07, 1 },
    accent = { 1.00, 0.58, 0.18, 1 },
    knob = { 0.62, 0.60, 0.58, 1 },
    heading = { 1.00, 0.62, 0.22 }, text = { 1.00, 0.84, 0.66 }, hint = { 0.72, 0.69, 0.66 },
}

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

local UI = {
    disc = MEDIA .. "Disc", shadow = MEDIA .. "Shadow", close = MEDIA .. "Close",
    shadowColor = { 0, 0, 0, 0.55 },
    hover = { 1, 1, 1, 0.08 },
    halo = { 1, 1, 1, 0.10 },
    white = { 1, 1, 1, 1 },
    clear = { 0, 0, 0, 0 },
}
for role, color in pairs(PALETTE) do UI[role] = color end
ns.UI = UI

-- Shapes ----------------------------------------------------------------

-- Per axis: first half, a thin middle strip to stretch, last half.
local SPANS = { { 0, 0.5 }, { 0.49, 0.51 }, { 0.5, 1 } }

function UI.Paint(shape, color)
    if shape.color == color then return end
    shape.color = color
    for i = 1, 9 do shape[i]:SetVertexColor(color[1], color[2], color[3], color[4]) end
end

-- outset grows the shape past the frame (negative insets it); dy shifts it.
function UI.Rounded(frame, layer, radius, color, outset, file, dy)
    outset, dy = outset or 0, dy or 0
    local shape = {}
    for row = 1, 3 do
        for col = 1, 3 do
            local piece = frame:CreateTexture(nil, layer)
            piece:SetTexture(file or UI.disc)
            piece:SetTexCoord(SPANS[col][1], SPANS[col][2], SPANS[row][1], SPANS[row][2])
            shape[(row - 1) * 3 + col] = piece
        end
    end
    local tl, tr, bl, br = shape[1], shape[3], shape[7], shape[9]
    for _, corner in ipairs({ tl, tr, bl, br }) do
        corner:SetWidth(radius); corner:SetHeight(radius)
    end
    tl:SetPoint("TOPLEFT", frame, "TOPLEFT", -outset, outset + dy)
    tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", outset, outset + dy)
    bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -outset, -outset + dy)
    br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", outset, -outset + dy)
    local function Span(piece, first, firstPoint, last, lastPoint)
        piece:SetPoint("TOPLEFT", first, firstPoint)
        piece:SetPoint("BOTTOMRIGHT", last, lastPoint)
    end
    Span(shape[2], tl, "TOPRIGHT", tr, "BOTTOMLEFT")
    Span(shape[4], tl, "BOTTOMLEFT", bl, "TOPRIGHT")
    Span(shape[5], tl, "BOTTOMRIGHT", br, "TOPLEFT")
    Span(shape[6], tr, "BOTTOMLEFT", br, "TOPRIGHT")
    Span(shape[8], bl, "TOPRIGHT", br, "BOTTOMLEFT")
    UI.Paint(shape, color)
    return shape
end

-- A floating card: soft shadow, a faint accent rim and the surface.
-- Uses the frame's BACKGROUND, BORDER and ARTWORK layers; text goes on OVERLAY.
function UI.Surface(frame, radius)
    UI.Rounded(frame, "BACKGROUND", radius + 10, UI.shadowColor, 12, UI.shadow, -3)
    UI.Rounded(frame, "BORDER", radius, UI.edge)
    return UI.Rounded(frame, "ARTWORK", radius - 1, UI.surface, -1)
end

function UI.Tint(texture, c)
    texture:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
end

function UI.Disc(parent, layer, size, color)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetTexture(UI.disc)
    texture:SetWidth(size); texture:SetHeight(size)
    UI.Tint(texture, color)
    return texture
end

-- Text ------------------------------------------------------------------

function UI.Color(font, role)
    local c = UI[role]
    font:SetTextColor(c[1], c[2], c[3])
end

-- Without a font: a heading-colored GameFontNormal. With one: hint text.
function UI.Label(parent, text, x, y, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    UI.Color(label, font and "hint" or "heading")
    return label
end

-- Section headings: small accent capitals.
function UI.Heading(parent, text, x, y)
    local label = UI.Label(parent, string.upper(text), x, y, "GameFontNormalSmall")
    UI.Color(label, "heading")
    return label
end

local function HideTooltip() GameTooltip:Hide() end

function UI.Tooltip(widget, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self or this or widget, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", HideTooltip)
end

-- Buttons ---------------------------------------------------------------

-- Selected buttons (active tab, chosen list entry) become a filled accent pill.
-- Ghost buttons sit on a track and show no fill until selected.
function UI.Select(button, selected)
    if button.selected == selected then return end
    button.selected = selected
    UI.Paint(button.fill, selected and UI.selected or (button.ghost and UI.clear or UI.control))
    UI.Color(button:GetFontString(), (selected or not button.ghost) and "text" or "hint")
end

-- A rounded pill. options: ghost, height, font.
function UI.Button(name, parent, text, x, y, width, onClick, options)
    options = options or {}
    local height = options.height or 22
    local button = CreateFrame("Button", name, parent)
    button:SetWidth(width); button:SetHeight(height)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:RegisterForClicks("LeftButtonUp")
    button.fill = UI.Rounded(button, "BACKGROUND", height / 2, UI.clear)
    UI.Rounded(button, "HIGHLIGHT", height / 2, UI.hover)
    local label = button:CreateFontString(nil, "OVERLAY", options.font or "GameFontHighlightSmall")
    label:SetAllPoints(button)
    button:SetFontString(label)
    button:SetText(text)
    button.ghost = options.ghost
    UI.Select(button, false)
    button:SetScript("OnClick", onClick)
    return button
end

-- Switches and radios ---------------------------------------------------

function UI.Checked(widget)
    local value = widget:GetChecked()
    return value == true or value == 1
end

-- Switches and radio dots draw their own state, so a disabled or
-- unchecked control never shows the native check art.
local function PaintCheck(widget)
    local on, dim = UI.Checked(widget), widget.disabled and true or false
    if widget.shownOn == on and widget.shownDim == dim then return end
    widget.shownOn, widget.shownDim = on, dim
    if widget.dot then
        UI.Tint(widget.ring, on and UI.accent or UI.hint)
        if on then widget.dot:Show() else widget.dot:Hide() end
    else
        UI.Paint(widget.track, on and UI.selected or UI.control)
        widget.knob:ClearAllPoints()
        widget.knob:SetPoint("LEFT", widget, "LEFT", on and 14 or 2, 0)
        UI.Tint(widget.knob, on and UI.white or UI.knob)
    end
    widget:SetAlpha(dim and 0.4 or 1)
end

function UI.SetCheck(widget, value)
    if UI.Checked(widget) ~= value then widget:SetChecked(value) end
    PaintCheck(widget)
end

-- Sets value and enabled state from settings; call it from the page refresh.
function UI.Sync(widget, value, enabled)
    local disabled = enabled == false
    if widget.disabled ~= disabled then
        widget.disabled = disabled
        if disabled then widget:Disable() else widget:Enable() end
    end
    UI.SetCheck(widget, value and true or false)
end

-- A sliding switch with a label. onClick(value) runs after the switch repaints;
-- refresh dependent controls there. hitWidth bounds the clickable label.
function UI.Switch(name, parent, text, tip, x, y, onClick, hitWidth)
    local widget = CreateFrame("CheckButton", name, parent)
    widget:SetWidth(28); widget:SetHeight(16)
    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 2)
    -- Make the label clickable without overlapping the neighboring column.
    widget:SetHitRectInsets(0, -(hitWidth or 190), 0, 0)
    widget.track = UI.Rounded(widget, "BACKGROUND", 8, UI.control)
    widget.knob = UI.Disc(widget, "ARTWORK", 12, UI.knob)
    local halo = UI.Disc(widget, "HIGHLIGHT", 22, UI.halo)
    halo:SetPoint("CENTER", widget.knob, "CENTER", 0, 0)
    widget.label = widget:CreateFontString(name .. "Text", "OVERLAY", "GameFontHighlightSmall")
    widget.label:SetPoint("LEFT", widget, "RIGHT", 8, 0)
    widget.label:SetJustifyH("LEFT")
    widget.label:SetText(text)
    UI.Color(widget.label, "text")
    if tip then UI.Tooltip(widget, tip) end
    if onClick then
        widget:SetScript("OnClick", function(self)
            local clicked = self or this or widget
            PaintCheck(clicked)
            onClick(UI.Checked(clicked))
        end)
    end
    PaintCheck(widget)
    return widget
end

-- Sliders ---------------------------------------------------------------

local function ShowSliderValue(slider, value)
    slider.valueText:SetText(slider.format and slider.format(value) or tostring(value))
end

-- A labelled slider: label and value on one line, a rounded track below.
-- The block is 32 high; stack blocks 42 apart. onChange(value) runs only
-- for player changes; format(value) returns the value text.
function UI.Slider(name, parent, text, x, y, width, minValue, maxValue, step, onChange, format)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    UI.Color(label, "text")
    local slider = CreateFrame("Slider", name, parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetWidth(width); slider:SetHeight(16)
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
    slider:SetHitRectInsets(0, 0, -4, -4)
    slider:EnableMouse(true)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    -- A 6-high track inset from the 16-high hit area.
    UI.Rounded(slider, "BACKGROUND", 3, UI.control, -5)
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetTexture(UI.disc)
    thumb:SetWidth(14); thumb:SetHeight(14)
    UI.Tint(thumb, UI.accent)
    slider:SetThumbTexture(thumb)
    slider.label = label
    slider.valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slider.valueText:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    slider.valueText:SetJustifyH("RIGHT")
    UI.Color(slider.valueText, "heading")
    slider.step, slider.format = step, format
    slider:SetScript("OnValueChanged", function(self)
        local widget = self or this or slider
        local value = math.floor(widget:GetValue() / step + 0.5) * step
        ShowSliderValue(widget, value)
        -- SetValue from a refresh also fires this; only the player changes settings.
        if onChange and not widget.refreshing then onChange(value) end
    end)
    return slider
end

-- Shows a saved value without calling onChange.
function UI.SetSlider(slider, value)
    slider.refreshing = true
    slider:SetValue(value)
    slider.refreshing = nil
    ShowSliderValue(slider, value)
end

-- Segmented choice ------------------------------------------------------

-- One pill track with ghost buttons, the chosen one a filled pill.
-- onClick(index) runs on a click; call the returned Select(index) to show
-- the choice. options: height (default 30), font.
function UI.Segmented(prefix, parent, labels, x, y, width, onClick, options)
    options = options or {}
    local count, height = table.getn(labels), options.height or 30
    local track = CreateFrame("Frame", nil, parent)
    track:SetWidth(width); track:SetHeight(height)
    track:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    UI.Rounded(track, "BACKGROUND", height / 2, UI.track)
    local buttonWidth = math.floor((width - 6 - (count - 1)) / count)
    local style = { ghost = true, height = height - 6, font = options.font }
    local buttons = {}
    for i = 1, count do
        local index = i
        buttons[i] = UI.Button(prefix .. i, track, labels[i],
            3 + (i - 1) * (buttonWidth + 1), -3, buttonWidth, function() onClick(index) end, style)
    end
    local function Select(index)
        for i = 1, count do UI.Select(buttons[i], i == index) end
    end
    return buttons, Select, track
end

-- Window ----------------------------------------------------------------

-- A movable card in DIALOG strata with title, version, close glyph and
-- Escape-to-close. It starts hidden. Content starts at y = -98 with tabs,
-- or y = -56 without them; side margins are 28.
function UI.Window(name, title, width, height, version)
    local panel = CreateFrame("Frame", name, UIParent)
    panel:SetWidth(width); panel:SetHeight(height)
    panel:SetPoint("TOP", UIParent, "CENTER", 0, 190)
    panel:SetFrameStrata("DIALOG"); panel:SetToplevel(true)
    panel:EnableMouse(true); panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function() panel:StartMoving() end)
    panel:SetScript("OnDragStop", function() panel:StopMovingOrSizing(); UI.PinTop(panel) end)
    panel:SetClampedToScreen(true)
    UI.Surface(panel, 14)
    panel:Hide()
    panel.width = width
    table.insert(UISpecialFrames, name)

    local heading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", panel, "TOPLEFT", 26, -18)
    heading:SetText(title)
    UI.Color(heading, "heading")
    panel.title = heading
    if version then
        local text = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        text:SetPoint("BOTTOMLEFT", heading, "BOTTOMRIGHT", 6, 1)
        text:SetText("v" .. version)
        UI.Color(text, "hint")
    end
    local close = CreateFrame("Button", name .. "Close", panel)
    close:SetWidth(22); close:SetHeight(22)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -14)
    close:RegisterForClicks("LeftButtonUp")
    UI.Disc(close, "HIGHLIGHT", 22, UI.halo):SetAllPoints(close)
    local glyph = close:CreateTexture(nil, "ARTWORK")
    glyph:SetTexture(UI.close)
    glyph:SetWidth(12); glyph:SetHeight(12)
    glyph:SetPoint("CENTER", close, "CENTER", 0, 0)
    UI.Tint(glyph, UI.hint)
    close:SetScript("OnClick", function() panel:Hide() end)
    return panel
end

-- StartMoving can leave a CENTER anchor. Pin the top so height changes
-- (tabs of different length) grow downward.
function UI.PinTop(panel)
    local left, top = panel:GetLeft(), panel:GetTop()
    if left and top then
        local ratio = panel:GetEffectiveScale() / UIParent:GetEffectiveScale()
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * ratio, top * ratio)
    end
end

-- Segmented tabs: one pill track under the title, the active tab a filled pill.
-- tabs = { { label = "Loot", height = 380 }, ... }; each gets a page frame
-- covering the window. onSelect(index) runs after the switch, to refresh.
-- Returns the pages and a Show(index) function.
-- width defaults to the width UI.Window was given.
function UI.Tabs(panel, prefix, tabs, onSelect, width)
    width = width or panel.width
    local count = table.getn(tabs)
    local labels, pages, active, Select, Show = {}, {}, nil, nil, nil
    for i = 1, count do
        labels[i] = tabs[i].label
        pages[i] = CreateFrame("Frame", prefix .. "Page" .. i, panel)
        pages[i]:SetAllPoints(panel); pages[i]:Hide()
    end
    Show = function(index)
        if not tabs[index] then index = 1 end
        if index ~= active then
            if active then pages[active]:Hide() end
            active = index
            Select(index)
            if tabs[index].height then panel:SetHeight(tabs[index].height) end
            pages[index]:Show()
        end
        if onSelect then onSelect(index) end
    end
    local _
    _, Select = UI.Segmented(prefix .. "Tab", panel, labels, 24, -48, width - 48,
        function(index) Show(index) end, { font = "GameFontHighlight" })
    return pages, Show
end
