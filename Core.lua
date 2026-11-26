-- ThreatMeter: who holds how much threat on your target in a group fight, how
-- much more you need to pull aggro, and a warning before you do. Core: the saved
-- table and the page in ClassicAPI's Settings window (AddOn Options, or /tm).
-- Doc headings are ClassicAPI's docs/API.md; "stock" is the client's own API.
if not CLASSIC_API_VERSION then error("ThreatMeter needs ClassicAPI.", 0) end

local _, T = ...
ThreatMeterDB = ThreatMeterDB or {} -- restored first: LoadSavedVariablesFirst
local db = ThreatMeterDB
T.db = db

-- The defaults are Claude's sizes (his saved file, 2026-11-22).
T.DEFAULTS = { enabled = true, rows = 14, width = 220, rowHeight = 25 }
-- The most players one answer of the server holds (asking for more broke the old meter, 2026-11-12).
T.MOST = 14

-- One sweep clears every key nothing owns (KNOWN_PATTERNS KP-64); the meter
-- starts before the window registers the page, so the defaults are filled now.
for key in pairs(db) do
    if T.DEFAULTS[key] == nil then db[key] = nil end
end
for key, value in pairs(T.DEFAULTS) do
    if type(db[key]) ~= type(value) then db[key] = value end
end

function T.Print(text) DEFAULT_CHAT_FRAME:AddMessage("|cffff9e38ThreatMeter|r " .. text) end

local category
function T.OpenPage()
    if category then Settings.OpenToCategory(category:GetID()) end
end

-- On or off through the page's setting, so the page shows it too: /tm on, /tm off, the X.
function T.Switch(on)
    Settings.SetValue("ThreatMeter_enabled", on)
    T.Print(on and "is on." or "is off. Type /tm on to turn it on again.")
end

-- The page, in play order: the switch, then what it shows, then the preview.
SettingsRegistrar:AddRegistrant(function()
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("ThreatMeter")
    local function Setting(key, label)
        return Settings.RegisterAddOnSetting(category, "ThreatMeter_" .. key, key, db, type(T.DEFAULTS[key]), label, T.DEFAULTS[key])
    end
    local function On() return db.enabled end
    local enabled = Setting("enabled", "Show ThreatMeter")
    enabled:SetValueChangedCallback(function(_, value) T.SetEnabled(value) end)
    local switch = Settings.CreateCheckbox(category, enabled,
        "In a party or raid, the threat on your target while you fight a boss, an elite or a rare. Off: nothing is asked or shown. /tm on and /tm off do the same.")
    local function Slider(key, label, lo, hi, step, tip)
        local setting = Setting(key, label)
        setting:SetValueChangedCallback(T.Relayout)
        local options = Settings.CreateSliderOptions(lo, hi, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        Settings.CreateSlider(category, setting, options, tip):SetParentInitializer(switch, On)
    end
    Slider("rows", "Players shown", 3, T.MOST, 1, "How many players the window lists, most threat first. You are always on it.")
    Slider("width", "Width", 150, 300, 10, "A narrow window leaves out threat per second, then threat, so names fit.")
    Slider("rowHeight", "Bar height", 14, 32, 1, "The height of each bar; the text grows with it.")
    local preview = CreateSettingsButtonInitializer("Preview", "Preview", T.TogglePreview,
        "Sample players in the window, to drag it and the badge into place and to see the warning. A second click or a fight ends it.", true)
    preview:SetParentInitializer(switch, On)
    layout:AddInitializer(preview)
    Settings.RegisterAddOnCategory(category)
end)

-- /tm on and /tm off switch it (the player's order, 2026-11-26); /tm alone opens the page.
SLASH_THREATMETER1 = "/tm"
SlashCmdList.THREATMETER = function(msg)
    local word = string.lower((string.gsub(msg or "", "%s+", "")))
    if word == "on" or word == "off" then T.Switch(word == "on") else T.OpenPage() end
end
