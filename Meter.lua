-- ThreatMeter: what the player sees. The window with one bar per player, a
-- "Pull aggro" line, the threat badge, and the warning (screen glow and sound).
-- Everything is drawn from ns (Core.lua) when an answer arrives or the player
-- changes a setting; nothing runs per frame. The bars ease themselves: ClassicAPI's
-- StatusBar:SetValue takes an interpolation.
local addonName, ns = ...
if not ns.ready then return end

local UI = ns.UI
local floor, min = math.floor, math.min
local Meter = {}
ns.Meter = Meter

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local FONT = "Interface\\AddOns\\" .. addonName .. "\\fonts\\Roboto.ttf"
local SOUND = "Interface\\AddOns\\" .. addonName .. "\\sounds\\warn.ogg"
local EASE, NOW = Enum.StatusBarInterpolation.ExponentialEaseOut, Enum.StatusBarInterpolation.Immediate
local MAX_ROWS = 14          -- the most players the server's answer can hold
local HEADER, LABELS, PAD, GAP = 26, 14, 6, 2
local NAME_MIN = 60
local TOP = HEADER + LABELS   -- where the first bar starts
local PANEL = { 0.06, 0.06, 0.07, 0.85 }
local GREY = { 0.5, 0.5, 0.5 }

local db, win, title, labels, foot, badge, badgeText, badgeShape, glow, pulse
local rows = {}
local cols = { tps = true, threat = true }   -- columns that fit the width
local titleName, titlePerc, titleNoData, heightKey, badgeKey

-- Your own bar and badge are always red, so you can find yourself at a glance.
local RED = { 1, 0.15, 0.1 }

local function SavePosition(frame, key)
    local point, _, relative, x, y = frame:GetPoint()
    db[key] = { point, relative, x, y }
end

local function RestorePosition(frame, key, point, x, y)
    frame:ClearAllPoints()
    local saved = db[key]
    if saved then
        frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        frame:SetPoint(point, UIParent, point, x, y)
    end
end

local function Draggable(frame, key)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function() if not db.locked then this:StartMoving() end end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing(); SavePosition(this, key) end)
end

-- A bar with its texts: name on the left, then per second, threat and percent.
local function NewRow(index)
    local bar = CreateFrame("StatusBar", nil, win)
    bar:SetStatusBarTexture(MEDIA .. "Smooth")
    bar:SetMinMaxValues(0, 100)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(bar)
    back:SetColorTexture(0, 0, 0, 0.35)
    local row = { bar = bar }
    for _, key in ipairs({ "name", "tps", "threat", "perc" }) do
        row[key] = bar:CreateFontString(nil, "OVERLAY")
        row[key]:SetJustifyH(key == "name" and "LEFT" or "RIGHT")
    end
    rows[index] = row
    return row
end

local function Toggle(region, on) if on then region:Show() else region:Hide() end end

-- The "Pull aggro" line sits on top; the players follow it, one slot lower while
-- it is shown. Runs when that changes or the size does, never per answer.
local function Place(withFoot)
    local height = db.rowHeight
    foot.bar:ClearAllPoints()
    foot.bar:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -TOP)
    local first = TOP + (withFoot and height or 0)
    for i = 1, MAX_ROWS do
        rows[i].bar:ClearAllPoints()
        rows[i].bar:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -(first + (i - 1) * height))
    end
end

-- Sizes and anchors; runs when a setting changes, never per answer.
local function Layout()
    local width, height = db.width, db.rowHeight
    local size = min(18, floor(height * 0.64 + 0.5))
    local inner = width - 2 * PAD
    local perc, threat, tps = floor(size * 2.9), floor(size * 3.8), floor(size * 3)
    -- A narrow window drops threat per second, then threat, to keep room for names.
    cols.tps, cols.threat = true, true
    if inner - perc - threat - tps - 16 < NAME_MIN then cols.tps = false end
    if not cols.tps and inner - perc - threat - 12 < NAME_MIN then cols.threat = false end
    local right = perc + 2 + (cols.threat and threat + 2 or 0) + (cols.tps and tps + 2 or 0)
    win:SetWidth(width)
    win:SetScale(db.scale)
    for i = 0, MAX_ROWS do
        local row = i == 0 and foot or rows[i] or NewRow(i)
        row.bar:SetWidth(inner)
        row.bar:SetHeight(height - GAP)
        for _, key in ipairs({ "name", "tps", "threat", "perc" }) do row[key]:SetFont(FONT, size, "OUTLINE") end
        row.perc:ClearAllPoints(); row.perc:SetPoint("RIGHT", row.bar, "RIGHT", -4, 0)
        row.perc:SetWidth(perc); row.perc:SetHeight(size + 2)
        row.threat:ClearAllPoints(); row.threat:SetPoint("RIGHT", row.perc, "LEFT", -2, 0)
        row.threat:SetWidth(threat); row.threat:SetHeight(size + 2)
        row.tps:ClearAllPoints(); row.tps:SetPoint("RIGHT", row.threat, "LEFT", -2, 0)
        row.tps:SetWidth(tps); row.tps:SetHeight(size + 2)
        Toggle(row.threat, cols.threat); Toggle(row.tps, cols.tps)
        row.name:ClearAllPoints(); row.name:SetPoint("LEFT", row.bar, "LEFT", 5, 0)
        row.name:SetWidth(inner - right - 8); row.name:SetHeight(size + 2)
        row.owner, row.pk, row.tk, row.sk = nil, nil, nil, nil
    end
    -- Each label ends where its column ends.
    local x = width - PAD - 4
    for _, c in ipairs({ { "perc", 0 }, { "threat", perc + 2 }, { "tps", perc + threat + 4 } }) do
        local label = labels[c[1]]
        label:SetFont(FONT, size - 3, "")
        label:ClearAllPoints()
        label:SetPoint("TOPRIGHT", win, "TOPLEFT", x - c[2], -(HEADER - 3))
    end
    title:SetFont(FONT, size - 1, "OUTLINE")
    title:SetWidth(width - 60)
    Place(false)
    heightKey, titleName = nil, false
end

local function ShowRow(row, e, mine)
    local bar = row.bar
    local ease = row.owner == e.name
    if not ease then
        row.owner = e.name
        row.name:SetText(e.name)
        row.pk, row.tk, row.sk, row.colorKey = nil, nil, nil, nil
        bar:SetValue(e.perc, NOW)
    else
        bar:SetValue(e.perc, EASE)
    end
    local pk = floor(e.perc + 0.5)
    if pk ~= row.pk then
        row.pk = pk
        row.perc:SetText(pk .. "%")
    end
    local colorKey = mine and "me" or ns.classes[e.name] or "none"
    if colorKey ~= row.colorKey then
        row.colorKey = colorKey
        if mine then
            bar:SetStatusBarColor(RED[1], RED[2], RED[3], 0.95)
        else
            local c = ns.classColor[ns.classes[e.name]] or GREY
            bar:SetStatusBarColor(c[1], c[2], c[3], 0.9)
        end
    end
    if e.threat ~= row.tk then row.tk = e.threat; row.threat:SetText(AbbreviateNumbers(floor(e.threat))) end
    local sk = floor(e.tps + 0.5)
    if sk ~= row.sk then row.sk = sk; row.tps:SetText(sk) end
    bar:Show()
end

local function ShowFoot(me)
    local bar = foot.bar
    if me.tank then
        foot.name:SetText("You hold aggro")
        foot.threat:SetText("")
        bar:SetValue(100, EASE)
        bar:SetStatusBarColor(1, 0.15, 0.1, 0.95)
        foot.owner = nil
    else
        local gap = floor(ns.pullAt - me.threat)
        if gap < 0 then gap = 0 end
        if foot.owner ~= "pull" then foot.owner = "pull"; foot.name:SetText("Pull aggro"); foot.tk = nil end
        if gap ~= foot.tk then foot.tk = gap; foot.threat:SetText("+" .. AbbreviateNumbers(gap)) end
        local share = ns.pullAt > 0 and me.threat * 100 / ns.pullAt or 0
        bar:SetValue(share, EASE)
        bar:SetStatusBarColor(RED[1], RED[2], RED[3], 0.95)
    end
    foot.tps:SetText(""); foot.perc:SetText("")
    bar:Show()
end

local function UpdateBadge(me)
    if not (db.badge and me) then
        if badgeKey then badge:Hide(); badgeKey = nil end
        return
    end
    local pk = floor(me.perc + 0.5)
    if pk == badgeKey then return end
    badgeKey = pk
    badgeText:SetText(pk .. "%")
    for i = 1, 9 do badgeShape[i]:SetVertexColor(RED[1] * 0.8, RED[2] * 0.8, RED[3] * 0.8, 0.9) end
    badge:Show()
end

local function UpdateTitle(me)
    local name = ns.targetName
    local pk = me and floor(me.perc + 0.5) or -1
    local noData = ns.noData
    if name == titleName and pk == titlePerc and noData == titleNoData then return end
    titleName, titlePerc, titleNoData = name, pk, noData
    if not name then
        title:SetText("ThreatMeter")
    elseif ns.noData then
        title:SetText(name .. "  |cff888888no threat data from the server")
    elseif pk >= 0 then
        title:SetText(name .. "  " .. pk .. "%")
    else
        title:SetText(name)
    end
end

-- Redraws everything from ns: after an answer, a clear or a setting change.
function Meter.Update()
    if not win then return end
    local n = min(ns.count, db.rows)
    local me = ns.me
    for i = 1, n do
        local e = ns.order[i]
        ShowRow(rows[i], e, e == me)
    end
    for i = n + 1, MAX_ROWS do
        if rows[i].bar:IsShown() then rows[i].bar:Hide(); rows[i].owner = nil end
    end
    local showFoot = me and ns.tank
    if showFoot then ShowFoot(me) elseif foot.bar:IsShown() then foot.bar:Hide(); foot.owner = nil end
    UpdateTitle(me)
    UpdateBadge(me)
    -- The window is as tall as what it shows; labels only over rows.
    local key = n * 2 + (showFoot and 1 or 0)
    if key ~= heightKey then
        heightKey = key
        win:SetHeight((n > 0 and TOP or HEADER) + n * db.rowHeight + (showFoot and db.rowHeight or 0) + PAD)
        for key, label in pairs(labels) do Toggle(label, n > 0 and cols[key] ~= false) end
        Place(showFoot)
    end
end

local function Alpha(combat)
    win:SetAlpha(combat and db.alphaCombat or db.alphaOut)
end

-- Window visibility: shown by the player, and hidden out of combat when asked.
local inCombat
function Meter.Apply()
    if not win then return end
    local show = db.enabled and (inCombat or ns.previewing or not db.hideOut)
    if show then win:Show() else win:Hide() end
    Alpha(inCombat)
    win:EnableMouse(not db.locked)
    badge:EnableMouse(not db.locked)
end

function Meter.Combat(on)
    inCombat = on and true or false
    Meter.Apply()
end

-- which: "glow" or "sound" plays just that one (the settings use it to try them).
function Meter.Alert(which)
    if db.screenGlow and which ~= "sound" then
        pulse:Stop()
        glow:Show()
        pulse:Play()
    end
    if db.sound and which ~= "glow" then
        PlaySoundFile(SOUND, "Master")
        FlashClientIcon()
    end
end

-- A setting that changes the window's size or fonts.
function Meter.Relayout()
    if not win then return end
    Layout()
    ns.SetLimit(db.rows)
    Meter.Update()
    Meter.Apply()
end

function Meter.ResetPositions()
    db.window, db.badgePos = nil, nil
    RestorePosition(win, "window", "TOPLEFT", 40, -200)
    RestorePosition(badge, "badgePos", "CENTER", 0, -140)
end

function Meter.Init()
    db = ns.db
    win = CreateFrame("Frame", "ThreatMeter_Window", UIParent)
    win:SetFrameStrata("MEDIUM")
    UI.Rounded(win, "BACKGROUND", 10, PANEL)
    Draggable(win, "window")
    RestorePosition(win, "window", "TOPLEFT", 40, -200)

    title = win:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 2, -7)
    title:SetJustifyH("LEFT"); title:SetHeight(14)
    labels = {}
    for _, key in ipairs({ "tps", "threat", "perc" }) do
        labels[key] = win:CreateFontString(nil, "OVERLAY")
        labels[key]:SetFont(FONT, 10, "")
        labels[key]:SetJustifyH("RIGHT")
        UI.Color(labels[key], "hint")
    end
    labels.tps:SetText("TPS"); labels.threat:SetText("Threat"); labels.perc:SetText("%")

    -- Settings and close.
    local cog = CreateFrame("Button", "ThreatMeter_Cog", win)
    cog:SetWidth(14); cog:SetHeight(14)
    cog:SetPoint("TOPRIGHT", win, "TOPRIGHT", -26, -5)
    cog:SetNormalTexture(MEDIA .. "icon_cog")
    cog:SetScript("OnClick", function() ns.OpenSettings() end)
    UI.Tooltip(cog, "Settings")
    local close = CreateFrame("Button", "ThreatMeter_Close", win)
    close:SetWidth(14); close:SetHeight(14)
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -5)
    local glyph = close:CreateTexture(nil, "ARTWORK")
    glyph:SetTexture(UI.close); glyph:SetWidth(9); glyph:SetHeight(9)
    glyph:SetPoint("CENTER", close, "CENTER", 0, 0)
    UI.Tint(glyph, UI.hint)
    close:SetScript("OnClick", function()
        ns.SetEnabled(false)
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9e38ThreatMeter|r is off. Type /tm on to turn it back on.")
    end)
    UI.Tooltip(close, "Turn ThreatMeter off")

    foot = NewRow(0)
    rows[0] = nil
    for i = 1, MAX_ROWS do NewRow(i) end

    -- The threat badge: your threat as a number, where you put it.
    badge = CreateFrame("Frame", "ThreatMeter_Badge", UIParent)
    badge:SetWidth(58); badge:SetHeight(26)
    badge:SetFrameStrata("MEDIUM")
    badgeShape = UI.Rounded(badge, "BACKGROUND", 8, { 0, 0, 0, 0.8 })
    badgeText = badge:CreateFontString(nil, "OVERLAY")
    badgeText:SetFont(FONT, 15, "OUTLINE")
    badgeText:SetPoint("CENTER", badge, "CENTER", 0, 0)
    Draggable(badge, "badgePos")
    RestorePosition(badge, "badgePos", "CENTER", 0, -140)
    badge:Hide()

    -- The warning glow: one pulse over the whole screen.
    glow = CreateFrame("Frame", "ThreatMeter_Glow", UIParent)
    glow:SetFrameStrata("LOW")
    glow:SetAllPoints(UIParent)
    glow:SetAlpha(0)
    glow:Hide()
    local texture = glow:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(glow)
    texture:SetTexture(MEDIA .. "fs_glow")
    texture:SetBlendMode("ADD")
    pulse = glow:CreateAnimationGroup()
    local rise = pulse:CreateAnimation("Alpha")
    rise:SetFromAlpha(0); rise:SetToAlpha(0.6); rise:SetDuration(0.4); rise:SetSmoothing("OUT"); rise:SetOrder(1)
    local fall = pulse:CreateAnimation("Alpha")
    fall:SetFromAlpha(0.6); fall:SetToAlpha(0); fall:SetDuration(0.4); fall:SetSmoothing("IN"); fall:SetOrder(2)
    pulse:SetScript("OnFinished", function() glow:Hide() end)

    inCombat = UnitAffectingCombat("player") and true or false
    Layout()
    Meter.Update()
    Meter.Apply()
end
