-- ThreatMeter: what the player sees. The window (the pull aggro line, one bar per
-- player, the title), the badge with your percent, and the warning. Drawn from T
-- (Threat.lua) after an answer or a setting change. Nothing runs per frame: the bars
-- ease themselves (API.md "statusBar:SetValue") and the pulse is an animation group.
local _, T = ...
local db = T.db
local floor, min, max = math.floor, math.min, math.max

local FLAT, BAR = "Interface\\Buttons\\WHITE8X8", "Interface\\TargetingFrame\\UI-StatusBar"
local FONT = STANDARD_TEXT_FONT
local SOUND = "Interface\\AddOns\\ThreatMeter\\sounds\\warn.ogg"
local GLOW = "Interface\\FullScreenTextures\\LowHealth" -- the client's red screen edge (FrameXML UIParent.xml:35)
local EASE, JUMP = Enum.StatusBarInterpolation.ExponentialEaseOut, Enum.StatusBarInterpolation.Immediate
local MAX, HEAD, PAD, NAME_ROOM = T.MOST, 22, 4, 60 -- the most players an answer holds; title; edge; least name width
local RED = { 1, 0.15, 0.1 }                     -- your bar, the pull line and the badge
local RIGHTS = { "pct", "threat", "tps" }         -- the columns from the right edge

local function Flat(f, r, g, b, a)
    f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    f:SetBackdropColor(r, g, b, a)
    f:SetBackdropBorderColor(0, 0, 0)
end

-- Named and made at load: the client keeps them where the player drags them
-- (layout-cache.txt); the points below hold only until then (KNOWN_PATTERNS KP-66).
local function Movable(f, grip)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    grip:EnableMouse(true)
    grip:SetScript("OnMouseDown", function() if arg1 == "RightButton" and grip ~= f then T.OpenPage() else f:StartMoving() end end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
end

local win = CreateFrame("Frame", "ThreatMeter_Window", UIParent)
win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -200)
Flat(win, 0.06, 0.06, 0.06, 0.85)
local head = CreateFrame("Frame", nil, win) -- drag the window by its title; a right-click opens the page
head:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
head:SetPoint("TOPRIGHT", win, "TOPRIGHT", -20, 0)
head:SetHeight(HEAD)
Movable(win, head)
local title = head:CreateFontString(nil, "OVERLAY") -- the target's name: it gives way to the value
local value = head:CreateFontString(nil, "OVERLAY") -- your percent, or that the server is silent
value:SetPoint("RIGHT", head, "RIGHT", -2, 0)
title:SetPoint("LEFT", head, "LEFT", PAD + 2, 0)
title:SetPoint("RIGHT", value, "LEFT", -6, 0)
title:SetJustifyH("LEFT")
title:SetWordWrap(false) -- one line, ending in "..." when it is too long (API.md "SetWordWrap")

local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
close:SetSize(22, 22)
close:SetPoint("TOPRIGHT", win, "TOPRIGHT", 1, 1)
close:SetScript("OnClick", function() T.Switch(false) end)
close:SetScript("OnEnter", function() GameTooltip:SetOwner(close, "ANCHOR_TOPLEFT"); GameTooltip:SetText("Turn ThreatMeter off"); GameTooltip:Show() end)
close:SetScript("OnLeave", function() GameTooltip:Hide() end)

local labels = {}
for key, text in pairs({ pct = "%", threat = "Threat", tps = "TPS" }) do
    labels[key] = win:CreateFontString(nil, "OVERLAY")
    labels[key]:SetFont(FONT, 10)
    labels[key]:SetJustifyH("RIGHT")
    labels[key]:SetTextColor(0.6, 0.6, 0.6)
    labels[key]:SetText(text)
end

-- A bar with its texts: the name on the left, then per second, threat and percent.
local function NewBar()
    local bar = CreateFrame("StatusBar", nil, win)
    bar:SetStatusBarTexture(BAR)
    bar:SetMinMaxValues(0, 100)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(bar)
    back:SetTexture(FLAT)
    back:SetVertexColor(0, 0, 0, 0.35)
    local row = { bar = bar, name = bar:CreateFontString(nil, "OVERLAY") }
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    for _, key in ipairs(RIGHTS) do
        row[key] = bar:CreateFontString(nil, "OVERLAY")
        row[key]:SetJustifyH("RIGHT")
    end
    bar:Hide()
    return row
end
local pull, rows = NewBar(), {}
pull.bar:SetStatusBarColor(RED[1], RED[2], RED[3])
for i = 1, MAX do rows[i] = NewBar() end

-- The badge: your percent, where you put it.
local badge = CreateFrame("Frame", "ThreatMeter_Badge", UIParent)
badge:SetSize(58, 26)
badge:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
Flat(badge, RED[1] * 0.7, RED[2] * 0.7, RED[3] * 0.7, 0.9)
Movable(badge, badge)
local badgeText = badge:CreateFontString(nil, "OVERLAY")
badgeText:SetFont(FONT, 15, "OUTLINE")
badgeText:SetPoint("CENTER", badge, "CENTER", 0, 0)
badge:Hide()

-- The warning: one red pulse at the screen's edge, the warning sound and a taskbar flash.
local glow = CreateFrame("Frame", nil, UIParent)
glow:SetAllPoints(UIParent)
glow:SetFrameStrata("LOW")
glow:SetAlpha(0)
glow:Hide()
local edge = glow:CreateTexture(nil, "BACKGROUND")
edge:SetAllPoints(glow)
edge:SetTexture(GLOW)
edge:SetBlendMode("ADD")
local pulse = glow:CreateAnimationGroup()
for order, to in ipairs({ 0.6, 0 }) do -- 0 to 0.6, then back to 0, 0.4 s each
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.6 - to)
    fade:SetToAlpha(to)
    fade:SetDuration(0.4)
    fade:SetOrder(order)
end
pulse:SetScript("OnFinished", function() glow:Hide() end)

function T.Warn()
    glow:Show()
    pulse:Stop()
    pulse:Play()
    PlaySoundFile(SOUND, "Master")
    FlashClientIcon()
end

local cols = {}                                -- each column's width; 0 when it is left out
local shown, labelHeight, heightKey = 14, 12, nil
local titleName, titleP, titleSilent, badgeP = false, nil, nil, nil

local function Fit(text, size, width, point, x)
    text:SetFont(FONT, size, "OUTLINE")
    text:SetSize(width, size + 2)
    text:ClearAllPoints()
    text:SetPoint(point, text:GetParent(), point, x, 0)
    if width > 0 then text:Show() else text:Hide() end
end

-- Sizes and anchors; after a setting change, never per answer.
local function Layout()
    local width, height = db.width, db.rowHeight
    shown = floor(db.rows + 0.5)
    local size = min(18, floor(height * 0.64 + 0.5))
    local inner = width - 2 * PAD
    cols.pct, cols.threat, cols.tps = floor(size * 2.9), floor(size * 3.8), floor(size * 3)
    -- A narrow window leaves out threat per second, then threat, so names keep room.
    if inner - cols.pct - cols.threat - cols.tps - 16 < NAME_ROOM then cols.tps = 0 end
    if inner - cols.pct - cols.threat - cols.tps - 12 < NAME_ROOM then cols.threat = 0 end
    win:SetWidth(width)
    for i = 0, MAX do
        local row = rows[i] or pull
        row.bar:SetSize(inner, height - 2)
        local x = -3
        for _, key in ipairs(RIGHTS) do
            Fit(row[key], size, cols[key], "RIGHT", x)
            if cols[key] > 0 then x = x - cols[key] - 2 end
        end
        if row == pull then x = -3 end -- the pull line writes no column: its text has the whole bar
        Fit(row.name, size, inner + x - 6, "LEFT", 4)
        row.owner = nil -- every text is written again
        row.bar:Hide()
    end
    labelHeight = max(10, size - 4)
    local x = -PAD - 3
    for _, key in ipairs(RIGHTS) do
        labels[key]:SetFont(FONT, labelHeight - 1)
        labels[key]:SetWidth(cols[key])
        labels[key]:ClearAllPoints()
        labels[key]:SetPoint("TOPRIGHT", win, "TOPRIGHT", x, -HEAD + 2)
        if cols[key] > 0 then x = x - cols[key] - 2 end
    end
    title:SetFont(FONT, size - 1, "OUTLINE")
    title:SetHeight(size + 2)
    value:SetFont(FONT, size - 1, "OUTLINE")
    heightKey, titleName, titleP = nil, false, false
end

-- The pull line on top, the players below; the window as tall as what it shows.
local function Place(n, withPull)
    local h = db.rowHeight
    local top = HEAD + (n > 0 and labelHeight or 0)
    pull.bar:ClearAllPoints()
    pull.bar:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -top)
    if withPull then top = top + h end
    for i = 1, MAX do
        rows[i].bar:ClearAllPoints()
        rows[i].bar:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -(top + (i - 1) * h))
    end
    win:SetHeight(top + n * h + PAD)
    for key, label in pairs(labels) do
        if n > 0 and cols[key] > 0 then label:Show() else label:Hide() end
    end
end

-- A text is written only when what it shows changed; a new owner jumps, the same one eases.
local function ShowRow(row, e, mine)
    local bar = row.bar
    if row.owner ~= e.name then
        row.owner, row.p, row.t, row.s, row.c = e.name, nil, nil, nil, nil
        row.name:SetText(e.name)
        bar:SetValue(e.pct, JUMP)
    else
        bar:SetValue(e.pct, EASE)
    end
    local class = mine and "you" or T.classes[e.name] or "none"
    if class ~= row.c then
        row.c = class
        local color = C_ClassColor.GetClassColor(class) -- nil for "you" and "none"
        if mine then
            bar:SetStatusBarColor(RED[1], RED[2], RED[3])
        elseif color then
            bar:SetStatusBarColor(color:GetRGB())
        else
            bar:SetStatusBarColor(0.5, 0.5, 0.5)
        end
    end
    local p, s = floor(e.pct + 0.5), floor(e.tps + 0.5)
    if p ~= row.p then row.p = p; row.pct:SetText(p .. "%") end
    if cols.threat > 0 and e.threat ~= row.t then row.t = e.threat; row.threat:SetText(AbbreviateNumbers(floor(e.threat))) end
    if cols.tps > 0 and s ~= row.s then row.s = s; row.tps:SetText(s) end
    bar:Show()
end

-- "Pull aggro +N": the threat you still need; the bar is your share of that point.
local function ShowPull(me, tank)
    if me == tank then
        if pull.owner ~= "hold" then
            pull.owner = "hold"
            pull.name:SetText("You hold aggro")
            pull.bar:SetValue(100, JUMP)
        end
    else
        local need = max(0, floor(T.pullAt - me.threat))
        if pull.owner ~= "pull" or need ~= pull.t then
            pull.owner, pull.t = "pull", need
            pull.name:SetText("Pull aggro +" .. AbbreviateNumbers(need))
        end
        pull.bar:SetValue(T.pullAt > 0 and me.threat * 100 / T.pullAt or 0, EASE)
    end
    pull.bar:Show()
end

local function ShowTitle(me)
    local name, p, silent = T.target, me and floor(me.pct + 0.5), T.silent
    if name ~= titleName then titleName = name; title:SetText(name or "ThreatMeter") end
    if p == titleP and silent == titleSilent then return end
    titleP, titleSilent = p, silent
    value:SetText(silent and "|cff888888no threat data|r" or p and p .. "%" or "")
end

local function ShowBadge(me)
    local p = me and floor(me.pct + 0.5)
    if p == badgeP then return end
    badgeP = p
    if p then badgeText:SetText(p .. "%") end
    badge:SetShown(p ~= nil)
end

-- Redraws from T: after an answer, a clear or a setting change.
function T.Redraw()
    local order, me, tank = T.order, T.me, T.tank
    local n, listed = min(T.count, shown), false
    for i = 1, n do
        local e = order[i]
        if i == n and me and not listed then e = me end -- you are always on the list
        listed = listed or e == me
        ShowRow(rows[i], e, e == me)
    end
    for i = n + 1, MAX do
        if rows[i].owner then rows[i].owner = nil; rows[i].bar:Hide() end
    end
    local withPull = me and tank and true or false
    if withPull then ShowPull(me, tank) elseif pull.owner then pull.owner = nil; pull.bar:Hide() end
    ShowTitle(me)
    ShowBadge(me)
    local key = n * 2 + (withPull and 1 or 0)
    if key ~= heightKey then heightKey = key; Place(n, withPull) end
end

function T.Relayout()
    Layout()
    T.Redraw()
end

function T.Show(on) win:SetShown(on) end

Layout()
T.Redraw()
T.SetEnabled(db.enabled) -- the events (Threat.lua) and the window
