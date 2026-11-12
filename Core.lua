-- ThreatMeter: the threat data. It asks the server who holds how much threat on
-- the target, keeps the answers per player and says when the meter has news.
-- Meter.lua draws it, Settings.lua configures it; both read ns, nothing else.
--
-- The server's protocol: we send the addon message "TWT_UDTSv4" ("limit=N") to the
-- group, and the answer comes back as CHAT_MSG_ADDON text
--   TWTv4=name:tank:threat:percent:melee;name:...   (an optional "#..." tail follows)
-- tank is 1 for whoever holds aggro, melee is 1 for a player in melee range, and
-- percent is the share of the tank's threat. Seen working on OctoWoW 2026-11-08
-- (Azuregos, raid). No DLL has threat data, so this stays the only source.
local addonName, ns = ...

if type(CLASSIC_API_VERSION) ~= "number" then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff2020ThreatMeter|r needs ClassicAPI. It is turned off.")
    return
end
ns.ready = true

local find, sub, gmatch, lower = string.find, string.sub, string.gmatch, string.lower
local max, sort, wipe = math.max, table.sort, table.wipe
local GetTime = GetTime

local ASK = "TWT_UDTSv4"
local ANSWER = "TWTv4="
local GAP = 0.1          -- the least time between two questions
local TIMEOUT = 1        -- ask again when an answer is this late
local NO_ANSWER = 3      -- after this long without any answer the title says so
local WATCH = 0.5        -- how often to look again while the target is not yet fighting
local TPS_WINDOW = 3     -- threat per second is measured over 3 to 6 seconds
local ALERT_EVERY = 5    -- seconds between two warnings
local FIELDS = "([^:;#]*):([^:;#]*):([^:;#]*):([^:;#]*):([^:;#]*)"

ns.DEFAULTS = {
    enabled = true, locked = false, hideOut = false, allEnemies = false,
    scale = 1, alphaCombat = 1, alphaOut = 1, rows = 8, rowHeight = 22, width = 280,
    badge = true, screenGlow = true, sound = true, threshold = 80,
}

-- Data the meter reads ----------------------------------------------------------
ns.order = {}        -- the players of the last answer, most threat first
ns.count = 0
ns.me, ns.tank = nil, nil   -- our entry and the aggro holder's, when in the answer
ns.pullAt = 0        -- the threat at which we take aggro from the tank
ns.targetName = nil  -- set while threat is being asked for
ns.noData = false    -- no answer to the first questions
ns.previewing = false
ns.classes = {}      -- player name -> class token, from the group roster
ns.classColor = {}   -- class token -> { r, g, b }
ns.limitText = "limit=" .. ns.DEFAULTS.rows

local entries, order = {}, ns.order
local answerNo = 0
local active, inflight, stale = false, false, false
local sentAt, firstAsk, lastAlert = 0, 0, -ALERT_EVERY
local nextPending, timeoutPending, watchPending = false, false, false
local myName = UnitName("player")
local db

local RAID, PARTY = {}, {}
for i = 1, 40 do RAID[i] = "raid" .. i end
for i = 1, 4 do PARTY[i] = "party" .. i end

local function Channel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

-- Guarded timer callbacks: ClassicAPI swallows errors in C_Timer callbacks, so
-- they go to the error handler from here (KP-63).
local function Guard(f)
    local handler = geterrorhandler()
    return function() xpcall(f, handler) end
end

-- Roster ------------------------------------------------------------------------

local function NoteClass(unit)
    local name = UnitName(unit)
    local _, token = UnitClass(unit)
    if not name or not token then return end
    ns.classes[name] = token
    if not ns.classColor[token] then
        local color = C_ClassColor.GetClassColor(token)
        if color then
            local r, g, b = color:GetRGBA()
            ns.classColor[token] = { r, g, b }
        end
    end
end

local function ScanRoster()
    if ns.previewing then return end
    wipe(ns.classes)
    NoteClass("player")
    local units, n = RAID, GetNumRaidMembers()
    if n == 0 then units, n = PARTY, GetNumPartyMembers() end
    for i = 1, n do NoteClass(units[i]) end
end

-- Answers -----------------------------------------------------------------------

local function ByThreat(a, b)
    if a.threat ~= b.threat then return a.threat > b.threat end
    return a.name < b.name
end

local function Sample(e, now, threat)
    if not e.t1 then
        e.t0, e.v0, e.t1, e.v1 = now, threat, now, threat
    elseif now - e.t1 >= TPS_WINDOW then
        e.t0, e.v0, e.t1, e.v1 = e.t1, e.v1, now, threat
    end
    local span = now - e.t0
    if span >= 1 then e.tps = max(0, (threat - e.v0) / span) end
end

-- Reads the part of an answer after "TWTv4=" into the entries.
local function Ingest(text, now)
    answerNo = answerNo + 1
    local hash = find(text, "#", 1, true)
    if hash then text = sub(text, 1, hash - 1) end
    local had, n = ns.count, 0
    local me, tank
    for name, isTank, threat, perc, melee in gmatch(text, FIELDS) do
        local e = entries[name]
        if not e then
            e = { name = name, threat = 0, perc = 0, tps = 0 }
            entries[name] = e
        end
        threat = tonumber(threat) or 0
        if e.seen ~= answerNo - 1 then e.t1 = nil end   -- it missed an answer: measure again
        Sample(e, now, threat)
        e.seen, e.threat, e.perc = answerNo, threat, tonumber(perc) or 0
        e.tank, e.melee = isTank == "1", melee == "1"
        n = n + 1
        order[n] = e
        if e.tank then tank = e end
        if name == myName then me = e end
    end
    for i = had, n + 1, -1 do order[i] = nil end
    ns.count = n
    sort(order, ByThreat)
    ns.me, ns.tank = me, tank
    if me and tank and me ~= tank then
        ns.pullAt = tank.threat * (me.melee and 1.1 or 1.3)
    else
        ns.pullAt = 0
    end
end

local function Alert(now)
    local me = ns.me
    if not me or me.tank or me.perc < db.threshold or now - lastAlert < ALERT_EVERY then return end
    if not (db.screenGlow or db.sound) then return end
    lastAlert = now
    ns.Meter.Alert()
end

-- Forget the data: a new target, the end of a fight.
local function Clear()
    wipe(entries)
    for i = ns.count, 1, -1 do order[i] = nil end
    ns.count, ns.me, ns.tank, ns.pullAt = 0, nil, nil, 0
    ns.noData = false
    stale = inflight        -- an answer still due is about the old target
end

-- Asking ------------------------------------------------------------------------

local ELIGIBLE = { worldboss = true, elite = true, rareelite = true, rare = true }

-- Threat matters for bosses, elites and rares; normal enemies die too fast
-- unless the player asked for them all.
local function TargetOK()
    if not UnitExists("target") or UnitIsDead("target") or UnitIsPlayer("target")
            or not UnitCanAttack("player", "target") then return false end
    return db.allEnemies or ELIGIBLE[UnitClassification("target")] == true
end

local function Wanted()
    return Channel() and UnitAffectingCombat("player") and TargetOK() and UnitAffectingCombat("target")
end

local Ask, Evaluate

local function Stop()
    if not active then return end
    active = false
    ns.targetName = nil
    Clear()
    ns.Meter.Update()
end

Ask = function()
    if not Wanted() then return Stop() end
    local now = GetTime()
    SendAddonMessage(ASK, ns.limitText, Channel())
    inflight, sentAt = true, now
    if not timeoutPending then
        timeoutPending = true
        C_Timer.After(TIMEOUT, ns.Timeout)
    end
end

local function Later(delay)
    if nextPending then return end
    nextPending = true
    C_Timer.After(delay, ns.Next)
end

ns.Next = Guard(function()
    nextPending = false
    if active and not inflight then Ask() end
end)

-- The answer is late: ask again, and say so after a few seconds.
ns.Timeout = Guard(function()
    timeoutPending = false
    if not inflight then return end
    local now = GetTime()
    local late = now - sentAt
    if late < TIMEOUT - 0.01 then
        timeoutPending = true
        return C_Timer.After(TIMEOUT - late, ns.Timeout)
    end
    inflight, stale = false, false
    if not active then return end
    if not ns.noData and now - firstAsk >= NO_ANSWER and ns.count == 0 then
        ns.noData = true
        ns.Meter.Update()
    end
    Ask()
end)

-- The player is fighting and the target qualifies, but it is not in combat yet:
-- look again shortly.
ns.Watch = Guard(function()
    watchPending = false
    Evaluate()
end)

Evaluate = function()
    if ns.previewing or not db.enabled then return end
    if Wanted() then
        if not active then
            active, firstAsk = true, GetTime()
            ns.targetName = UnitName("target")
            ns.Meter.Update()
        end
        if not inflight then Ask() end
    else
        Stop()
        if not watchPending and Channel() and UnitAffectingCombat("player") and TargetOK() then
            watchPending = true
            C_Timer.After(WATCH, ns.Watch)
        end
    end
end

local function OnAnswer(text)
    local now = GetTime()
    inflight = false
    if stale then
        stale = false
    elseif active then
        ns.noData = false
        Ingest(text, now)
        ns.Meter.Update()
        Alert(now)
    end
    if active then
        local wait = GAP - (now - sentAt)
        if wait <= 0 then Ask() else Later(wait) end
    end
end

-- Sets how many rows the meter shows; the server is asked for that many players.
function ns.SetLimit(rows)
    ns.limitText = "limit=" .. rows
end

-- Preview: sample players through the same path as a real answer, to place and
-- try the window out of combat.
local SAMPLE = {
    { "Tenk", "WARRIOR", 1, 12000, 100, 1 }, { "Chad", "PALADIN", 0, 11800, 98, 1 },
    { 0, "ROGUE", 0, 9000, 75, 1 }, { "Olaf", "DRUID", 0, 8400, 70, 1 },
    { "Jimmy", "ROGUE", 0, 6000, 50, 1 }, { "Miranda", "PRIEST", 0, 5400, 45, 0 },
    { "Felix", "MAGE", 0, 4200, 35, 0 }, { "Tom", "WARLOCK", 0, 3000, 25, 0 },
    { "Bill", "HUNTER", 0, 1200, 10, 0 },
}

function ns.SetPreview(on)
    if on == ns.previewing or (on and (UnitAffectingCombat("player") or not db.enabled)) then return end
    ns.previewing = on
    if on then
        local text = {}
        for i, s in ipairs(SAMPLE) do
            local name = s[1] == 0 and myName or s[1]
            local class = s[1] == 0 and select(2, UnitClass("player")) or s[2]
            ns.classes[name] = class
            if not ns.classColor[class] then
                local r, g, b = C_ClassColor.GetClassColor(class):GetRGBA()
                ns.classColor[class] = { r, g, b }
            end
            text[i] = name .. ":" .. s[3] .. ":" .. s[4] .. ":" .. s[5] .. ":" .. s[6]
        end
        ns.targetName = "Preview"
        Ingest(table.concat(text, ";"), GetTime())
    else
        ns.targetName = nil
        Clear()
        stale = false
        ScanRoster()
    end
    ns.Meter.Update()
    ns.Meter.Apply()
end

-- Events ------------------------------------------------------------------------

local function LoadSettings()
    ThreatMeterDB = ThreatMeterDB or {}
    db = ThreatMeterDB
    -- "shown" (a hidden window that kept working) became "enabled".
    if db.shown == false and db.enabled == nil then db.enabled = false end
    db.shown = nil
    for key, value in pairs(ns.DEFAULTS) do
        if db[key] == nil then db[key] = value end
    end
    if db.rows > 14 then db.rows = 14 end   -- the server's answer holds 14 players at most
    ns.db = db
    ns.SetLimit(db.rows)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

local EVENTS = { "CHAT_MSG_ADDON", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }

-- Off means off: no events, no questions to the server, no window.
function ns.SetEnabled(on)
    db.enabled = on and true or false
    if on then
        for _, name in ipairs(EVENTS) do frame:RegisterEvent(name) end
        ScanRoster()
        ns.Meter.Combat(UnitAffectingCombat("player"))
        Evaluate()
    else
        ns.SetPreview(false)
        for _, name in ipairs(EVENTS) do frame:UnregisterEvent(name) end
        Stop()
        inflight, stale = false, false
    end
    ns.Meter.Apply()
end

frame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" then
        if inflight and arg2 then
            local _, last = find(arg2, ANSWER, 1, true)
            if last then OnAnswer(sub(arg2, last + 1)) end
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if ns.previewing then return end
        Stop()
        Clear()
        Evaluate()
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.SetPreview(false)
        ScanRoster()
        ns.Meter.Combat(true)
        Evaluate()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Stop()
        ns.Meter.Combat(false)
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        ScanRoster()
        if active and not Channel() then Stop() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        ScanRoster()
        ns.Meter.Combat(UnitAffectingCombat("player"))
        Evaluate()
    elseif event == "ADDON_LOADED" and arg1 == addonName then
        frame:UnregisterEvent("ADDON_LOADED")
        myName = UnitName("player")
        LoadSettings()
        ns.Meter.Init()
        if db.enabled then ns.SetEnabled(true) end
    end
end)

-- A setting that changes who qualifies: look at the target again.
function ns.Reevaluate()
    if active then Stop() end
    Evaluate()
end
