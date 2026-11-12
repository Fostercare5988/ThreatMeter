-- ThreatMeter: the settings window (ForgeUI), the same pages in AddOn Options, and
-- the slash commands.
local addonName, ns = ...
if not ns.ready then return end

local UI = ns.UI
local L, R = UI.L, UI.R
local layout = UI.NewLayout()
local TABS = { { label = "Window" }, { label = "Alerts" } }
local panel, pages, ShowTab, book
local tab = 1
local refresh = {}

-- Syncs the open page, then places it for the width it has (window or AddOn Options).
local function Refresh()
    if refresh[tab] then refresh[tab]() end
    if book then book:Place(tab) end
end

-- What each setting needs done when it changes.
local APPLY = {
    locked = "Apply", hideOut = "Apply", alphaCombat = "Apply", alphaOut = "Apply",
    scale = "Relayout", width = "Relayout", rows = "Relayout", rowHeight = "Relayout",
    badge = "Update", allEnemies = "Reevaluate",
}

local function Set(key, value)
    ns.db[key] = value
    local how = APPLY[key]
    if key == "enabled" then ns.SetEnabled(value)
    elseif how == "Reevaluate" then ns.Reevaluate() elseif how then ns.Meter[how]() end
end

local function PercentFormat(value) return math.floor(value * 100 + 0.5) .. "%" end

local widgets = {}

local function Switch(page, column, key, text, tip, after)
    local widget = UI.Switch("ThreatMeter_" .. key, page, text, tip, 0, 0, function(on)
        Set(key, on)
        if after then after(on) end
        Refresh()
    end)
    widgets[key] = widget
    layout:Switch(page, column, widget)
    return widget
end

local function Slider(page, column, key, text, low, high, step, format)
    local slider = UI.Slider("ThreatMeter_" .. key, page, text, 0, 0, 208, low, high, step, function(value)
        Set(key, value)
    end, format)
    widgets[key] = slider
    layout:Slider(page, column, slider)
    return slider
end

local function PreviewButton(page, name, x)
    local button = UI.Button(name, page, "Preview", 0, 0, 172, function()
        ns.SetPreview(not ns.previewing)
        Refresh()
    end)
    UI.Tooltip(button, "Shows sample players so you can place and try the window. Starting a fight ends it.")
    layout:Footer(page, button, x)
    return button
end

local previews = {}

local function Create()
    panel = UI.Window("ThreatMeter_Options", "ThreatMeter", 500, 400, GetAddOnMetadata(addonName, "Version"))
    pages, ShowTab = UI.Tabs(panel, "ThreatMeter_", TABS, function(index)
        tab = index
        Refresh()
    end)

    -- Window ------------------------------------------------------------------
    local page = pages[1]
    layout:Heading(page, L, "Window")
    Switch(page, L, "enabled", "Enable ThreatMeter",
        "Off turns the whole addon off: no window, no warnings, nothing asked of the server. /tm on and /tm off do the same.")
    Switch(page, L, "locked", "Lock position", "Stops the window and the badge from being dragged.")
    Switch(page, L, "hideOut", "Hide out of combat", "Shows the window only while you fight.")
    Switch(page, L, "allEnemies", "Normal enemies too",
        "Show threat against every enemy. Off: only bosses, elites and rares, which live long enough for it to matter.")
    layout:Heading(page, L, "Opacity")
    Slider(page, L, "alphaCombat", "In combat", 0.2, 1, 0.05, PercentFormat)
    Slider(page, L, "alphaOut", "Out of combat", 0.2, 1, 0.05, PercentFormat)

    layout:Heading(page, R, "Size")
    Slider(page, R, "scale", "Scale", 0.6, 1.5, 0.05, PercentFormat)
    Slider(page, R, "width", "Width", 150, 300, 10)
    Slider(page, R, "rows", "Players shown", 3, 14, 1)
    Slider(page, R, "rowHeight", "Bar height", 14, 32, 1)
    layout:Hint(page, R, "Drag the window by its title to move it.")
    previews[1] = PreviewButton(page, "ThreatMeter_Preview1", 28)
    layout:Footer(page, UI.Button("ThreatMeter_Reset", page, "Reset positions", 0, 0, 172, function()
        ns.Meter.ResetPositions()
    end), 216)

    refresh[1] = function()
        UI.Sync(widgets.enabled, ns.db.enabled)
        UI.Sync(widgets.locked, ns.db.locked)
        UI.Sync(widgets.hideOut, ns.db.hideOut)
        UI.Sync(widgets.allEnemies, ns.db.allEnemies)
        for _, key in ipairs({ "alphaCombat", "alphaOut", "scale", "width", "rows", "rowHeight" }) do
            UI.SetSlider(widgets[key], ns.db[key])
        end
        UI.Select(previews[1], ns.previewing)
    end

    -- Alerts ------------------------------------------------------------------
    page = pages[2]
    layout:Heading(page, L, "Threat badge")
    Switch(page, L, "badge", "Show my threat", "A small number with your threat on the target. Drag it where you want it.")
    layout:Hint(page, L, "Your own bar and badge are always red.")
    layout:Heading(page, R, "Warning")
    Switch(page, R, "screenGlow", "Screen glow", "A red glow around the screen when your threat is high.",
        function(on) if on and not UnitAffectingCombat("player") then ns.Meter.Alert("glow") end end)
    Switch(page, R, "sound", "Sound", "A warning sound when your threat is high.",
        function(on) if on and not UnitAffectingCombat("player") then ns.Meter.Alert("sound") end end)
    Slider(page, R, "threshold", "Warn at", 50, 100, 5, function(value) return value .. "%" end)
    layout:Hint(page, R, "The warning repeats every 5 seconds while your threat stays above this. It stays quiet when you hold aggro.")
    previews[2] = PreviewButton(page, "ThreatMeter_Preview2", 28)

    refresh[2] = function()
        UI.Sync(widgets.badge, ns.db.badge)
        UI.Sync(widgets.screenGlow, ns.db.screenGlow)
        UI.Sync(widgets.sound, ns.db.sound)
        UI.SetSlider(widgets.threshold, ns.db.threshold)
        UI.Select(previews[2], ns.previewing)
    end

    -- A page back from AddOn Options is hidden even when its tab is the active one.
    panel:SetScript("OnShow", function() ShowTab(tab); pages[tab]:Show() end)
    panel:SetScript("OnHide", function() ns.SetPreview(false) end)

    -- Game Menu > AddOn Options > ThreatMeter (ClassicAPI): the same pages, one column.
    book = UI.Book({
        name = addonName, text = "Open a page under " .. addonName .. ", or type /tm for the settings window.",
        open = function() ns.OpenSettings(true) end,
        panel = panel, pages = pages, tabs = TABS, layout = layout, refresh = Refresh,
        select = function(index) tab = index end,
        hide = function() ns.SetPreview(false) end,
    })
end

-- Opens the settings window (or closes it when it is open and `open` is not set).
function ns.OpenSettings(open)
    if InterfaceOptionsFrame:IsShown() then InterfaceOptionsFrame:Hide() end
    if panel:IsShown() and not open then panel:Hide() else panel:Show() end
end

-- The pages exist from the start: AddOn Options lists them.
Create()

SLASH_THREATMETER1, SLASH_THREATMETER2 = "/tm", "/threatmeter"
SlashCmdList["THREATMETER"] = function(text)
    text = string.lower(text or "")
    if text == "on" or text == "show" then
        Set("enabled", true)
        Refresh()
    elseif text == "off" or text == "hide" then
        Set("enabled", false)
        Refresh()
    else
        ns.OpenSettings()
    end
end
