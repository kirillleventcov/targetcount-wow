--[[
  TargetCount Core — Data model, event handling, and recording logic.
  Supports profiles, session tracking, zone/class info, target-of-target,
  party/raid awareness, and hourly timeline bucketing.
]]

local addonName = "targetcount"
TargetCountDB = TargetCountDB or {}

local db
local sessionStart = time()
local sessionCounts = {}
local partyThrottle = {}
local partyThrottleCount = 0
local THROTTLE_PRUNE_THRESHOLD = 200
local THROTTLE_WINDOW = 2

local function isThisAddon(name)
    return type(name) == "string" and name:lower() == addonName:lower()
end

local function hourKey(t)
    return tostring(math.floor((t or time()) / 3600))
end

local function ensureDB()
    db = TargetCountDB
    if not db.version or db.version < 2 then
        if db.targets and not db.profiles then
            db.profiles = { Default = { targets = db.targets, partyTargets = {} } }
            db.targets = nil
        end
        db.version = 2
    end
    db.activeProfile = db.activeProfile or "Default"
    db.profiles = db.profiles or {}
    local pn = db.activeProfile
    if not db.profiles[pn] then
        db.profiles[pn] = { targets = {}, partyTargets = {} }
    end
    local p = db.profiles[pn]
    p.targets = p.targets or {}
    p.partyTargets = p.partyTargets or {}
    db.ui = db.ui or {}
end

local function activeProfile()
    ensureDB()
    return db.profiles[db.activeProfile]
end

local lastGUID, suppressGUID

local function reactionLabel(unit)
    if not UnitExists(unit) then return "unknown" end
    local atk = UnitCanAttack("player", unit)
    local ast = UnitCanAssist("player", unit)
    if atk and not ast then return "hostile" end
    if ast and not atk then return "friendly" end
    if not atk and not ast then return "neutral" end
    return "mixed"
end

local function recordTarget(unit)
    if not UnitExists(unit) then return end
    local guid = UnitGUID(unit)
    if not guid then return end

    local name, realm = UnitName(unit)
    name = name or "???"
    if realm and realm ~= "" then name = name .. "-" .. realm end

    local kind = reactionLabel(unit)
    local now  = time()
    local zone = GetZoneText() or "Unknown"
    local isP  = UnitIsPlayer(unit)
    local cLoc, cEn, cType
    if isP then
        cLoc, cEn = UnitClass(unit)
    else
        cType = UnitCreatureType(unit)
    end

    local tbl = activeProfile().targets
    local e = tbl[guid]
    if not e then
        e = {
            name = name, count = 0,
            byKind = { friendly = 0, hostile = 0, neutral = 0, mixed = 0, unknown = 0 },
            firstSeen = now, zones = {}, totHistory = {}, timeline = {},
        }
        tbl[guid] = e
    end

    e.name     = name
    e.count    = e.count + 1
    e.lastSeen = now
    e.lastKind = kind
    e.isPlayer = isP
    if isP then
        e.class = cEn
        e.classLocalized = cLoc
    else
        e.creatureType = cType
    end

    e.byKind = e.byKind or { friendly = 0, hostile = 0, neutral = 0, mixed = 0, unknown = 0 }
    local bk = e.byKind[kind] and kind or "unknown"
    e.byKind[bk] = (e.byKind[bk] or 0) + 1

    e.zones = e.zones or {}
    e.zones[zone] = (e.zones[zone] or 0) + 1

    e.timeline = e.timeline or {}
    local hk = hourKey(now)
    e.timeline[hk] = (e.timeline[hk] or 0) + 1

    sessionCounts[guid] = (sessionCounts[guid] or 0) + 1

    if UnitExists("targettarget") then
        local tGuid = UnitGUID("targettarget")
        local tName = UnitName("targettarget")
        if tGuid and tName then
            e.totHistory = e.totHistory or {}
            local th = e.totHistory[tGuid]
            if not th then
                th = { name = tName, count = 0 }
                e.totHistory[tGuid] = th
            end
            th.count = th.count + 1
            th.name  = tName
        end
    end

    if TargetCount_OnStatsChanged then TargetCount_OnStatsChanged() end
end

local function onTargetChanged()
    local guid = UnitExists("target") and UnitGUID("target") or nil
    if not guid then
        if lastGUID then suppressGUID = lastGUID end
        lastGUID = nil
        return
    end
    if suppressGUID and guid == suppressGUID then
        suppressGUID = nil
        lastGUID = guid
        return
    end
    suppressGUID = nil
    lastGUID = guid
    recordTarget("target")
end

local function recordPartyTarget(pu)
    if not UnitExists(pu) then return end
    local tu = pu .. "target"
    if not UnitExists(tu) then return end
    local tg = UnitGUID(tu)
    local mg = UnitGUID(pu)
    if not tg or not mg then return end

    local now = time()
    local key = mg .. tg
    if partyThrottle[key] and (now - partyThrottle[key]) < THROTTLE_WINDOW then return end
    if not partyThrottle[key] then
        partyThrottleCount = partyThrottleCount + 1
    end
    partyThrottle[key] = now

    if partyThrottleCount > THROTTLE_PRUNE_THRESHOLD then
        local stale = now - 30
        for k, v in pairs(partyThrottle) do
            if v < stale then
                partyThrottle[k] = nil
                partyThrottleCount = partyThrottleCount - 1
            end
        end
    end

    local mn = UnitName(pu) or "?"
    local tn, tr = UnitName(tu)
    tn = tn or "?"
    if tr and tr ~= "" then tn = tn .. "-" .. tr end

    local pt = activeProfile().partyTargets
    if not pt[tg] then
        pt[tg] = { name = tn, count = 0, trackedBy = {}, lastSeen = now }
        if UnitIsPlayer(tu) then
            local _, ce = UnitClass(tu)
            pt[tg].class = ce
            pt[tg].isPlayer = true
        end
    end
    local e = pt[tg]
    e.name = tn
    e.count = e.count + 1
    e.lastSeen = now
    e.trackedBy = e.trackedBy or {}
    e.trackedBy[mn] = (e.trackedBy[mn] or 0) + 1

    if TargetCount_OnStatsChanged then TargetCount_OnStatsChanged() end
end

local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
evFrame:RegisterEvent("ADDON_LOADED")
evFrame:RegisterEvent("UNIT_TARGET")
evFrame:SetScript("OnEvent", function(_, ev, a1)
    if ev == "ADDON_LOADED" and isThisAddon(a1) then
        ensureDB()
        sessionStart = time()
    elseif ev == "PLAYER_TARGET_CHANGED" then
        onTargetChanged()
    elseif ev == "UNIT_TARGET" then
        if a1 and (a1:match("^party%d+$") or a1:match("^raid%d+$")) then
            recordPartyTarget(a1)
        end
    end
end)

function TargetCount_GetDB()        ensureDB(); return db end
function TargetCount_GetProfile()    return activeProfile() end
function TargetCount_SessionStart()  return sessionStart end
function TargetCount_SessionCount(g) return sessionCounts[g] or 0 end
function TargetCount_HourKey(t)      return hourKey(t) end

function TargetCount_ResetStats()
    local p = activeProfile()
    wipe(p.targets)
    wipe(p.partyTargets)
    wipe(sessionCounts)
    if TargetCount_OnStatsChanged then TargetCount_OnStatsChanged() end
end

function TargetCount_SetProfile(name)
    ensureDB()
    db.activeProfile = name
    if not db.profiles[name] then
        db.profiles[name] = { targets = {}, partyTargets = {} }
    end
    wipe(sessionCounts)
    if TargetCount_OnStatsChanged then TargetCount_OnStatsChanged() end
end

function TargetCount_ProfileNames()
    ensureDB()
    local r = {}
    for k in pairs(db.profiles) do r[#r + 1] = k end
    table.sort(r)
    return r
end

function TargetCount_DeleteProfile(name)
    ensureDB()
    if name == db.activeProfile or not db.profiles[name] then return false end
    db.profiles[name] = nil
    return true
end
