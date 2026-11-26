-- ThreatMeter: threat from the server. No DLL can read threat on a mob: the 1.12
-- server sends none and has no threat opcode (ClassicAPI TODO #98, "NOT FEASIBLE
-- in a client DLL"), so this is no -- GAP: and no release replaces it.
-- SERVER: the question is SendAddonMessage("TWT_UDTSv4", "limit=N", "RAID" or "PARTY");
-- the answer, a CHAT_MSG_ADDON whose text holds "TWTv4=" and then
-- name:tank:threat:percent:melee per player, ";" between them, an optional "#..." tail;
-- tank is 1 for the aggro holder, melee 1 for a player in melee range. The server
-- answers about the asker's target, 14 players at most. Seen working on OctoWoW
-- 2026-11-08 (Azuregos, raid) with the old addon. UNVERIFIED: the answer's prefix and
-- sender (so any message holding "TWTv4=" is read while a question is out) and what
-- percent means (so it is not read: the percents come from the threats).
local _, T = ...
local db = T.db
local find, max, sort, wipe = string.find, math.max, table.sort, table.wipe

local PREFIX, ANSWER = "TWT_UDTSv4", "TWTv4="
local ASK = "limit=" .. T.MOST -- always the most: you and the tank are in the answer, whatever the window shows
local RECORD = "^([^:;#]*):([^:;#]*):([^:;#]*):[^:;#]*:([^:;#]*);?" -- name, tank, threat, melee
local GAP, TIMEOUT, SILENT = 0.1, 1, 3  -- least time between questions; ask again; say "no data"
local SPAN = 3                          -- threat per second is measured over 3 to 6 seconds
local PULL_MELEE, PULL_RANGED = 1.1, 1.3 -- UNVERIFIED: test in game (vanilla's, the old addon's)
local WARN_AT, WARN_EVERY = 80, 5       -- percent of the tank's threat; seconds between warnings
local KINDS = { worldboss = true, elite = true, rareelite = true, rare = true }

T.order, T.count, T.pullAt, T.previewing = {}, 0, 0, false -- the last answer, most threat first
T.classes = {}                                         -- player name -> class token
local entries, order, classes = {}, T.order, T.classes -- entries by name, kept through a fight

local frame = CreateFrame("Frame")
local active, inflight, sentAt, heardAt, warnedAt = false, false, 0, 0, -100
local gen, askedGen, answers = 0, 0, 0 -- gen grows at each clear: an older question's answer is dropped
local rosterStale = true
local Evaluate

-- C_Timer drops a callback's error (API.md "C_Timer.After"); these reach the handler (KP-63).
local function Guard(f) return function() xpcall(f, geterrorhandler()) end end

local function Channel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

-- Threat matters on bosses, elites and rares; normal enemies die too fast.
local function TargetOK()
    return UnitExists("target") and not UnitIsDead("target") and not UnitIsPlayer("target")
        and UnitCanAttack("player", "target") and KINDS[UnitClassification("target")]
end

-- The class map, read again only when an answer comes after a roster change.
local function Note(unit)
    local name = UnitName(unit)
    local _, token = UnitClass(unit)
    if name and token then classes[name] = token end
end
local function ReadRoster()
    rosterStale = false
    wipe(classes)
    Note("player")
    local unit, n = "raid", GetNumRaidMembers()
    if n == 0 then unit, n = "party", GetNumPartyMembers() end
    for i = 1, n do Note(unit .. i) end
end

local function ByThreat(a, b)
    if a.threat ~= b.threat then return a.threat > b.threat end
    return a.name < b.name
end

-- Threat per second over the last 3 to 6 seconds; a player who missed an answer starts again.
local function Sample(e, now)
    if e.seen ~= answers - 1 or not e.t1 then
        e.t0, e.v0, e.t1, e.v1 = now, e.threat, now, e.threat
    elseif now - e.t1 >= SPAN then
        e.t0, e.v0, e.t1, e.v1 = e.t1, e.v1, now, e.threat
    end
    if now - e.t0 >= 1 then e.tps = max(0, (e.threat - e.v0) / (now - e.t0)) end
    e.seen = answers
end

-- Reads one answer, from `at` in `msg`, into the entries: no table and no closure per answer.
local function Read(msg, at, now)
    if rosterStale and not T.previewing then ReadRoster() end
    answers = answers + 1
    local myName, n, me, tank = UnitName("player"), 0, nil, nil
    while true do
        local _, last, name, isTank, threat, melee = find(msg, RECORD, at)
        if not last then break end
        at = last + 1
        local e = entries[name]
        if not e then e = { name = name, tps = 0 }; entries[name] = e end
        e.threat, e.tank, e.melee = tonumber(threat) or 0, isTank == "1", melee == "1"
        Sample(e, now)
        n = n + 1
        order[n] = e
        if e.tank then tank = e end
        if name == myName then me = e end
    end
    for i = n + 1, T.count do order[i] = nil end
    T.count, T.me, T.tank = n, me, tank
    sort(order, ByThreat)
    -- Percent of the tank's threat (of the most, when nobody holds aggro).
    local top = tank or order[1]
    local base = top and top.threat or 0
    for i = 1, n do order[i].pct = base > 0 and order[i].threat * 100 / base or 0 end
    T.pullAt = 0
    if me and tank and me ~= tank then T.pullAt = tank.threat * (me.melee and PULL_MELEE or PULL_RANGED) end
end

-- The warning: past 80% of the tank's threat, again every 5 s while it stays; never as the tank.
local function Warn(now)
    local me = T.me
    if me and T.tank and me ~= T.tank and me.pct >= WARN_AT and now - warnedAt >= WARN_EVERY then
        warnedAt = now
        T.Warn()
    end
end

-- Forget the data: a new target, the end of a fight or of a preview.
local function Clear()
    gen = gen + 1
    wipe(entries)
    for i = 1, T.count do order[i] = nil end
    T.count, T.me, T.tank, T.pullAt, T.silent = 0, nil, nil, 0, false
end

local function Stop()
    if not active then return end
    active, T.target = false, nil
    Clear()
    T.Redraw()
end

local function Answered()
    inflight = false
    frame:UnregisterEvent("CHAT_MSG_ADDON") -- every addon's messages: heard only while asking
end

-- A question's own timeout; one for an earlier, answered question finds a later one out.
local Timeout = Guard(function()
    local now = GetTime()
    if not inflight or now - sentAt < TIMEOUT - 0.01 then return end
    Answered()
    if active and not T.silent and now - heardAt >= SILENT - 0.01 then
        T.silent = true
        T.Redraw()
    end
    Evaluate()
end)
local Next = Guard(function() if not inflight then Evaluate() end end)

-- Asks when it should, stops when it should not: after every event, answer and timeout.
Evaluate = function()
    if T.previewing or not db.enabled then return end
    local channel = Channel()
    local fight = channel and UnitAffectingCombat("player") and TargetOK()
    local wanted = fight and UnitAffectingCombat("target")
    -- The target qualifies but does not fight yet: its combat flag wakes the meter.
    if fight and not wanted then frame:RegisterUnitEvent("UNIT_FLAGS", "target") else frame:UnregisterEvent("UNIT_FLAGS") end
    if not wanted then return Stop() end
    if not active then
        active, heardAt, T.target = true, GetTime(), UnitName("target")
        T.Redraw()
    end
    -- One question out at a time, ten a second at most: an early call waits for Next.
    if inflight or GetTime() - sentAt < GAP - 0.001 then return end
    inflight, askedGen, sentAt = true, gen, GetTime()
    C_Timer.After(TIMEOUT, Timeout) -- first: a question that fails to go out still runs into it
    frame:RegisterEvent("CHAT_MSG_ADDON")
    SendAddonMessage(PREFIX, ASK, channel)
end

local function OnAnswer(msg)
    local _, last = find(msg, ANSWER, 1, true)
    if not last then return end
    local now = GetTime()
    Answered()
    if askedGen == gen and active then
        heardAt, T.silent = now, false
        Read(msg, last + 1, now)
        T.Redraw()
        Warn(now)
    end
    local wait = GAP - (now - sentAt)
    if wait > 0 then C_Timer.After(wait, Next) else Evaluate() end
end

-- Sample players through the same path as an answer: name (false: you), class, tank, threat, melee.
local SAMPLE = {
    { "Tenk", "WARRIOR", 1, 12000, 1 }, { "Chad", "PALADIN", 0, 11400, 1 }, { false, nil, 0, 10200, 1 },
    { "Olaf", "DRUID", 0, 8400, 1 }, { "Jimmy", "ROGUE", 0, 6000, 1 }, { "Miranda", "PRIEST", 0, 5400, 0 },
    { "Felix", "MAGE", 0, 4200, 0 }, { "Tom", "WARLOCK", 0, 3000, 0 }, { "Bill", "HUNTER", 0, 1200, 0 },
}
function T.Preview(on)
    if on == T.previewing or (on and (UnitAffectingCombat("player") or not db.enabled)) then return end
    Stop()
    T.previewing = on
    Clear()
    if on then
        local me, parts = UnitName("player"), {}
        for i, s in ipairs(SAMPLE) do
            classes[s[1] or me] = s[2] or select(2, UnitClass("player"))
            parts[i] = (s[1] or me) .. ":" .. s[3] .. ":" .. s[4] .. ":0:" .. s[5]
        end
        T.target, warnedAt = "Preview", -100
        Read(table.concat(parts, ";"), 1, GetTime())
        Warn(GetTime())
    else
        T.target, rosterStale, warnedAt = nil, true, -100 -- the preview's warning silences no real one
    end
    T.Redraw()
end
function T.TogglePreview() T.Preview(not T.previewing) end

local EVENTS = { "PLAYER_IN_COMBAT_CHANGED", "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }

frame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" then
        if inflight and arg2 then OnAnswer(arg2) end
        return
    elseif event == "PLAYER_TARGET_CHANGED" then
        if T.previewing then return end
        Stop()
    elseif event == "PLAYER_IN_COMBAT_CHANGED" then
        if arg1 then T.Preview(false) end
    elseif event == "GROUP_ROSTER_UPDATE" then
        rosterStale = true
    end
    Evaluate() -- and UNIT_FLAGS, PLAYER_ENTERING_WORLD
end)

-- Off means off: no events, no questions, no window (Meter.lua). A question still out
-- runs into its timeout.
function T.SetEnabled(on)
    if on then
        for _, e in ipairs(EVENTS) do frame:RegisterEvent(e) end
        Evaluate()
    else
        T.Preview(false)
        frame:UnregisterAllEvents()
        Stop()
    end
    T.Show(on)
end
