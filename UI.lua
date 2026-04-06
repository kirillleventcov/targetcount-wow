------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local ROW_HEIGHT   = 20
local COL_RANK     = 28
local COL_NAME     = 140
local COL_COUNT    = 50
local COL_KIND     = 68
local COL_ZONE     = 80
local COL_SEEN     = 46
local WIN_W, WIN_H = 520, 400
local GRAPH_HOURS  = 24
local MAX_ROWS     = 400

local ACCENT       = { 0.40, 0.72, 1.0 }
local GOLD         = { 1, 0.82, 0 }
local DIM          = { 0.50, 0.50, 0.50 }

------------------------------------------------------------------------
-- Forward declarations
------------------------------------------------------------------------
local refreshUI, refreshGraph, buildList, onRowEnter, onRowLeave

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local activeTab   = "targets"
local sessionMode = false
local searchText  = ""
local zoneFilter  = nil
local sortField   = "count"
local sortAsc     = false

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function relTime(ts)
    if not ts then return "\226\128\148" end
    local d = time() - ts
    if d < 60    then return d .. "s" end
    if d < 3600  then return math.floor(d / 60) .. "m" end
    if d < 86400 then return math.floor(d / 3600) .. "h" end
    return math.floor(d / 86400) .. "d"
end

local function classColor(en)
    if not en or not RAID_CLASS_COLORS then return nil end
    return RAID_CLASS_COLORS[en]
end

local function kindSummary(e)
    local b = e.byKind
    if not b then return e.lastKind or "\226\128\148" end
    local p = {}
    for _, k in ipairs({ "hostile", "friendly", "neutral", "mixed" }) do
        if (b[k] or 0) > 0 then p[#p + 1] = k:sub(1, 1) .. ":" .. b[k] end
    end
    return #p > 0 and table.concat(p, " ") or (e.lastKind or "\226\128\148")
end

local function topZone(e)
    if not e.zones then return "\226\128\148" end
    local best, bestN = "\226\128\148", 0
    for z, n in pairs(e.zones) do
        if n > bestN then best, bestN = z, n end
    end
    return best
end

local function topTracker(e)
    if not e.trackedBy then return "\226\128\148" end
    local best, bestN, cnt = "?", 0, 0
    for nm, n in pairs(e.trackedBy) do
        cnt = cnt + 1
        if n > bestN then best, bestN = nm, n end
    end
    if cnt <= 1 then return best end
    return best .. " +" .. (cnt - 1)
end

local function collectZones()
    local p = TargetCount_GetProfile()
    local set = {}
    for _, e in pairs(p.targets) do
        if e.zones then for z in pairs(e.zones) do set[z] = true end end
    end
    local list = {}
    for z in pairs(set) do list[#list + 1] = z end
    table.sort(list)
    return list
end

------------------------------------------------------------------------
-- Shared menu frame for EasyMenu calls
------------------------------------------------------------------------
local menuFrame = CreateFrame("Frame", "TargetCountMenuFrame", UIParent, "UIDropDownMenuTemplate")

------------------------------------------------------------------------
-- Main frame
------------------------------------------------------------------------
local main = CreateFrame("Frame", "TargetCountFrame", UIParent, "BackdropTemplate")
main:SetSize(WIN_W, WIN_H)
main:SetPoint("CENTER")
main:SetClampedToScreen(true)
main:SetMovable(true)
main:EnableMouse(true)
main:RegisterForDrag("LeftButton")
main:SetScript("OnDragStart", main.StartMoving)
main:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local d = TargetCount_GetDB()
    d.ui = d.ui or {}
    local pt, _, rp, x, y = self:GetPoint(1)
    d.ui.point = pt; d.ui.relPoint = rp; d.ui.x = x; d.ui.y = y
end)
main:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
main:SetBackdropColor(0.06, 0.06, 0.10, 0.96)
main:SetBackdropBorderColor(0.35, 0.38, 0.50, 0.8)
main:SetFrameStrata("MEDIUM")
main:Hide()
tinsert(UISpecialFrames, "TargetCountFrame")

------------------------------------------------------------------------
-- Title bar
------------------------------------------------------------------------
local titleBar = CreateFrame("Frame", nil, main, "BackdropTemplate")
titleBar:SetPoint("TOPLEFT", 4, -4)
titleBar:SetPoint("TOPRIGHT", -4, -4)
titleBar:SetHeight(26)
titleBar:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
})
titleBar:SetBackdropColor(0.10, 0.10, 0.16, 0.7)
titleBar:SetBackdropBorderColor(0, 0, 0, 0)

local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("LEFT", 10, 0)
title:SetText("|cff66b8ffTarget|r|cffffffffCount|r")

local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", main, "TOPRIGHT", -2, -2)
closeBtn:SetSize(22, 22)

------------------------------------------------------------------------
-- Tab system
------------------------------------------------------------------------
local tabs = {}
local function updateTabHighlight()
    for _, t in pairs(tabs) do
        if t.tabName == activeTab then
            t.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)
            t.fs:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
            t.underline:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
            t.underline:Show()
        else
            t.bg:SetColorTexture(1, 1, 1, 0.03)
            t.fs:SetTextColor(0.60, 0.60, 0.60)
            t.underline:Hide()
        end
    end
end

local function makeTab(name, label, prev)
    local t = CreateFrame("Button", nil, main)
    t:SetSize(68, 22)
    t.tabName = name
    if prev then t:SetPoint("LEFT", prev, "RIGHT", 2, 0)
    else t:SetPoint("TOPLEFT", main, "TOPLEFT", 10, -32) end
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    t.bg:SetColorTexture(1, 1, 1, 0.03)
    t.fs = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.fs:SetPoint("CENTER", 0, 1)
    t.fs:SetText(label)
    t.underline = t:CreateTexture(nil, "ARTWORK")
    t.underline:SetHeight(2)
    t.underline:SetPoint("BOTTOMLEFT", 2, 0)
    t.underline:SetPoint("BOTTOMRIGHT", -2, 0)
    t.underline:Hide()
    tabs[name] = t
    return t
end

local tabTargets  = makeTab("targets",  "Targets")
local tabParty    = makeTab("party",    "Party",    tabTargets)
local tabTimeline = makeTab("timeline", "Timeline", tabParty)

------------------------------------------------------------------------
-- Profile button
------------------------------------------------------------------------
local profileBtn = CreateFrame("Button", nil, main)
profileBtn:SetSize(120, 20)
profileBtn:SetPoint("TOPRIGHT", main, "TOPRIGHT", -10, -33)
profileBtn.bg = profileBtn:CreateTexture(nil, "BACKGROUND")
profileBtn.bg:SetAllPoints()
profileBtn.bg:SetColorTexture(1, 1, 1, 0.06)
profileBtn.fs = profileBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
profileBtn.fs:SetPoint("CENTER")
profileBtn.fs:SetText("Default \226\150\188")
profileBtn:SetScript("OnClick", function(self)
    local menu = {}
    for _, nm in ipairs(TargetCount_ProfileNames()) do
        menu[#menu + 1] = {
            text = nm,
            checked = (nm == TargetCount_GetDB().activeProfile),
            func = function()
                TargetCount_SetProfile(nm)
                profileBtn.fs:SetText(nm .. " \226\150\188")
                refreshUI()
            end,
        }
    end
    menu[#menu + 1] = {
        text = "|cff00ff00+ New Profile|r", notCheckable = true,
        func = function() StaticPopup_Show("TARGETCOUNT_NEW_PROFILE") end,
    }
    local active = TargetCount_GetDB().activeProfile
    local count = 0
    for _ in pairs(TargetCount_GetDB().profiles) do count = count + 1 end
    if count > 1 then
        menu[#menu + 1] = {
            text = " ", isTitle = true, notCheckable = true,
        }
        for _, nm in ipairs(TargetCount_ProfileNames()) do
            if nm ~= active then
                menu[#menu + 1] = {
                    text = "|cffff6666Delete: " .. nm .. "|r", notCheckable = true,
                    func = function()
                        TargetCount_DeleteProfile(nm)
                        if main:IsShown() then refreshUI() end
                    end,
                }
            end
        end
    end
    EasyMenu(menu, menuFrame, self, 0, 0, "MENU")
end)

------------------------------------------------------------------------
-- Separator after tabs
------------------------------------------------------------------------
local tabSep = main:CreateTexture(nil, "ARTWORK")
tabSep:SetHeight(1)
tabSep:SetPoint("TOPLEFT", main, "TOPLEFT", 6, -55)
tabSep:SetPoint("TOPRIGHT", main, "TOPRIGHT", -6, -55)
tabSep:SetColorTexture(0.3, 0.3, 0.4, 0.4)

------------------------------------------------------------------------
-- Filter frame (session toggle, search, zone)
------------------------------------------------------------------------
local filterFrame = CreateFrame("Frame", nil, main)
filterFrame:SetPoint("TOPLEFT", main, "TOPLEFT", 10, -60)
filterFrame:SetPoint("TOPRIGHT", main, "TOPRIGHT", -10, -60)
filterFrame:SetHeight(22)

local function makeToggleBtn(parent, width, text, anchor, anchorFrame)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 20)
    if anchorFrame then
        b:SetPoint("LEFT", anchorFrame, "RIGHT", 2, 0)
    else
        b:SetPoint("LEFT", anchor or 0, 0)
    end
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.fs:SetPoint("CENTER")
    b.fs:SetText(text)
    return b
end

local btnAll  = makeToggleBtn(filterFrame, 56, "All Time")
local btnSess = makeToggleBtn(filterFrame, 56, "Session", nil, btnAll)

local function updateSessionButtons()
    if sessionMode then
        btnAll.bg:SetColorTexture(1, 1, 1, 0.04)
        btnAll.fs:SetTextColor(DIM[1], DIM[2], DIM[3])
        btnSess.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.15)
        btnSess.fs:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    else
        btnAll.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.15)
        btnAll.fs:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        btnSess.bg:SetColorTexture(1, 1, 1, 0.04)
        btnSess.fs:SetTextColor(DIM[1], DIM[2], DIM[3])
    end
end
updateSessionButtons()

btnAll:SetScript("OnClick", function()
    sessionMode = false; updateSessionButtons(); refreshUI()
end)
btnSess:SetScript("OnClick", function()
    sessionMode = true; updateSessionButtons(); refreshUI()
end)

local searchLabel = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
searchLabel:SetPoint("LEFT", btnSess, "RIGHT", 12, 0)
searchLabel:SetText("Search:")
searchLabel:SetTextColor(DIM[1], DIM[2], DIM[3])

local searchBox = CreateFrame("EditBox", "TargetCountSearch", filterFrame, "InputBoxTemplate")
searchBox:SetSize(100, 18)
searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 4, 0)
searchBox:SetAutoFocus(false)
searchBox:SetScript("OnTextChanged", function(self)
    searchText = self:GetText():lower()
    refreshUI()
end)
searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

local zoneBtn = CreateFrame("Button", nil, filterFrame)
zoneBtn:SetSize(100, 20)
zoneBtn:SetPoint("RIGHT", filterFrame, "RIGHT", 0, 0)
zoneBtn.bg = zoneBtn:CreateTexture(nil, "BACKGROUND")
zoneBtn.bg:SetAllPoints()
zoneBtn.bg:SetColorTexture(1, 1, 1, 0.06)
zoneBtn.fs = zoneBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
zoneBtn.fs:SetPoint("CENTER")
zoneBtn.fs:SetText("All Zones \226\150\188")
zoneBtn:SetScript("OnClick", function(self)
    local menu = {
        { text = "All Zones", checked = (zoneFilter == nil), func = function()
            zoneFilter = nil; zoneBtn.fs:SetText("All Zones \226\150\188"); refreshUI()
        end },
    }
    for _, z in ipairs(collectZones()) do
        menu[#menu + 1] = {
            text = z, checked = (zoneFilter == z),
            func = function()
                zoneFilter = z; zoneBtn.fs:SetText(z .. " \226\150\188"); refreshUI()
            end,
        }
    end
    EasyMenu(menu, menuFrame, self, 0, 0, "MENU")
end)

------------------------------------------------------------------------
-- Column headers (sortable buttons)
------------------------------------------------------------------------
local headerFrame = CreateFrame("Frame", nil, main, "BackdropTemplate")
headerFrame:SetPoint("TOPLEFT", main, "TOPLEFT", 10, -84)
headerFrame:SetPoint("TOPRIGHT", main, "TOPRIGHT", -10, -84)
headerFrame:SetHeight(18)
headerFrame.bg = headerFrame:CreateTexture(nil, "BACKGROUND")
headerFrame.bg:SetAllPoints()
headerFrame.bg:SetColorTexture(0.12, 0.12, 0.18, 0.6)

local headerSep = headerFrame:CreateTexture(nil, "ARTWORK")
headerSep:SetHeight(1)
headerSep:SetPoint("BOTTOMLEFT")
headerSep:SetPoint("BOTTOMRIGHT")
headerSep:SetColorTexture(0.3, 0.3, 0.4, 0.5)

local function makeHeader(label, width, field, anchor, justifyH)
    local btn = CreateFrame("Button", nil, headerFrame)
    btn:SetSize(width, 18)
    if anchor then btn:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    else btn:SetPoint("LEFT", 4, 0) end
    btn.label = label
    btn.field = field
    btn.fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.fs:SetPoint("LEFT")
    btn.fs:SetWidth(width)
    btn.fs:SetJustifyH(justifyH or "LEFT")
    btn.fs:SetText(label)
    btn.fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    if field then
        btn:SetScript("OnClick", function()
            if sortField == field then sortAsc = not sortAsc
            else sortField = field; sortAsc = (field == "name") end
            refreshUI()
        end)
    end
    return btn
end

local hRank  = makeHeader("#",     COL_RANK,  nil)
local hName  = makeHeader("Name",  COL_NAME,  "name",    hRank)
local hCount = makeHeader("Count", COL_COUNT, "count",   hName, "RIGHT")
local hKind  = makeHeader("Kind",  COL_KIND,  nil,       hCount)
local hZone  = makeHeader("Zone",  COL_ZONE,  "zone",    hKind)
local hSeen  = makeHeader("Seen",  COL_SEEN,  "lastSeen", hZone, "RIGHT")

local function updateHeaders()
    local arrow = sortAsc and " \226\150\178" or " \226\150\188"
    local function hl(btn, field, text)
        if sortField == field then
            btn.fs:SetText(text .. arrow)
            btn.fs:SetTextColor(1, 1, 1)
        else
            btn.fs:SetText(text)
            btn.fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        end
    end
    hl(hName,  "name",     "Name")
    hl(hCount, "count",    "Count")
    hl(hZone,  "zone",     "Zone")
    hl(hSeen,  "lastSeen", "Seen")
    hRank.fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    if activeTab == "party" then
        hKind.fs:SetText("Tracked By")
    else
        hKind.fs:SetText("Kind")
    end
    hKind.fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
end

------------------------------------------------------------------------
-- Scroll frame & row pool
------------------------------------------------------------------------
local scroll = CreateFrame("ScrollFrame", nil, main, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", -2, -2)
scroll:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -26, 40)

local scrollChild = CreateFrame("Frame", nil, scroll)
scrollChild:SetSize(WIN_W - 44, 1)
scroll:SetScrollChild(scrollChild)

local rows = {}

local function acquireRow(i)
    local row = rows[i]
    if row then return row end

    row = CreateFrame("Frame", nil, scrollChild)
    row:SetSize(WIN_W - 44, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:EnableMouse(true)

    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.rank:SetPoint("LEFT", 6, 0)
    row.rank:SetWidth(COL_RANK)
    row.rank:SetJustifyH("LEFT")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.rank, "RIGHT", 4, 0)
    row.name:SetWidth(COL_NAME - 8)
    row.name:SetJustifyH("LEFT")

    row.bar = row:CreateTexture(nil, "ARTWORK", nil, -1)
    row.bar:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
    row.bar:SetHeight(ROW_HEIGHT - 6)

    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
    row.count:SetWidth(COL_COUNT)
    row.count:SetJustifyH("RIGHT")

    row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.kind:SetPoint("LEFT", row.count, "RIGHT", 4, 0)
    row.kind:SetWidth(COL_KIND)
    row.kind:SetJustifyH("LEFT")

    row.zone = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.zone:SetPoint("LEFT", row.kind, "RIGHT", 4, 0)
    row.zone:SetWidth(COL_ZONE)
    row.zone:SetJustifyH("LEFT")

    row.seen = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.seen:SetPoint("LEFT", row.zone, "RIGHT", 4, 0)
    row.seen:SetWidth(COL_SEEN)
    row.seen:SetJustifyH("RIGHT")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row:SetScript("OnEnter", onRowEnter)
    row:SetScript("OnLeave", onRowLeave)

    rows[i] = row
    return row
end

local function stripeRow(row, i)
    if i % 2 == 0 then
        row.bg:SetColorTexture(1, 1, 1, 0.035)
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end
end

------------------------------------------------------------------------
-- Graph frame (Timeline tab)
------------------------------------------------------------------------
local graphFrame = CreateFrame("Frame", nil, main)
graphFrame:SetPoint("TOPLEFT", scroll)
graphFrame:SetPoint("BOTTOMRIGHT", scroll)
graphFrame:Hide()

local graphBars   = {}
local graphLabels = {}

local graphTitle = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
graphTitle:SetPoint("TOP", graphFrame, "TOP", 0, -4)

------------------------------------------------------------------------
-- Footer
------------------------------------------------------------------------
local footer = main:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
footer:SetPoint("BOTTOM", main, "BOTTOM", 0, 26)
footer:SetWidth(WIN_W - 40)
footer:SetJustifyH("CENTER")

------------------------------------------------------------------------
-- Data building
------------------------------------------------------------------------
local function shouldInclude(guid, entry)
    local count = entry.count
    if sessionMode and activeTab == "targets" then
        count = TargetCount_SessionCount(guid)
        if count == 0 then return false, 0 end
    end
    if searchText ~= "" then
        local nm = (entry.name or ""):lower()
        if not nm:find(searchText, 1, true) then return false, 0 end
    end
    if zoneFilter and activeTab == "targets" then
        if not entry.zones or not entry.zones[zoneFilter] then return false, 0 end
    end
    return true, count
end

buildList = function()
    local p = TargetCount_GetProfile()
    local src = (activeTab == "party") and p.partyTargets or p.targets
    local list = {}
    for guid, entry in pairs(src) do
        local ok, cnt = shouldInclude(guid, entry)
        if ok then
            list[#list + 1] = { guid = guid, entry = entry, sortCount = cnt }
        end
    end
    table.sort(list, function(a, b)
        local va, vb
        if sortField == "count" then
            va, vb = a.sortCount, b.sortCount
        elseif sortField == "name" then
            va, vb = (a.entry.name or ""), (b.entry.name or "")
        elseif sortField == "lastSeen" then
            va, vb = a.entry.lastSeen or 0, b.entry.lastSeen or 0
        elseif sortField == "zone" then
            va, vb = topZone(a.entry), topZone(b.entry)
        else
            va, vb = a.sortCount, b.sortCount
        end
        if va ~= vb then
            if sortAsc then return va < vb else return va > vb end
        end
        return (a.entry.name or "") < (b.entry.name or "")
    end)
    return list
end

------------------------------------------------------------------------
-- Row tooltips
------------------------------------------------------------------------
onRowEnter = function(self)
    if not self.data then return end
    self.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.12)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local e = self.data.entry

    if activeTab == "party" then
        GameTooltip:AddLine(e.name or "?", 1, 1, 1)
        if e.trackedBy then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Tracked by:", GOLD[1], GOLD[2], GOLD[3])
            for nm, n in pairs(e.trackedBy) do
                GameTooltip:AddDoubleLine("  " .. nm, n, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
            end
        end
        if e.lastSeen then
            GameTooltip:AddLine("Last: " .. date("%m/%d %H:%M", e.lastSeen), DIM[1], DIM[2], DIM[3])
        end
    else
        local cc = e.isPlayer and classColor(e.class)
        if cc then GameTooltip:AddLine(e.name or "?", cc.r, cc.g, cc.b)
        else GameTooltip:AddLine(e.name or "?", 1, 1, 1) end

        if e.isPlayer and e.classLocalized then
            GameTooltip:AddLine(e.classLocalized, 0.7, 0.7, 0.7)
        elseif e.creatureType then
            GameTooltip:AddLine(e.creatureType, 0.7, 0.7, 0.7)
        end

        GameTooltip:AddLine(" ")
        if e.firstSeen then
            GameTooltip:AddDoubleLine("First seen", date("%m/%d %H:%M", e.firstSeen),
                DIM[1], DIM[2], DIM[3], DIM[1], DIM[2], DIM[3])
        end
        if e.lastSeen then
            GameTooltip:AddDoubleLine("Last seen", date("%m/%d %H:%M", e.lastSeen),
                DIM[1], DIM[2], DIM[3], DIM[1], DIM[2], DIM[3])
        end

        local sc = TargetCount_SessionCount(self.data.guid)
        if sc > 0 then
            GameTooltip:AddDoubleLine("This session", sc,
                ACCENT[1], ACCENT[2], ACCENT[3], ACCENT[1], ACCENT[2], ACCENT[3])
        end

        if e.zones then
            local zl = {}
            for z, n in pairs(e.zones) do zl[#zl + 1] = { z = z, n = n } end
            if #zl > 0 then
                table.sort(zl, function(a, b) return a.n > b.n end)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Zones:", GOLD[1], GOLD[2], GOLD[3])
                for i = 1, math.min(5, #zl) do
                    GameTooltip:AddDoubleLine("  " .. zl[i].z, zl[i].n,
                        0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
                end
                if #zl > 5 then
                    GameTooltip:AddLine("  +" .. (#zl - 5) .. " more", DIM[1], DIM[2], DIM[3])
                end
            end
        end

        if e.totHistory then
            local tl = {}
            for _, th in pairs(e.totHistory) do tl[#tl + 1] = th end
            if #tl > 0 then
                table.sort(tl, function(a, b) return a.count > b.count end)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Target-of-target:", GOLD[1], GOLD[2], GOLD[3])
                for i = 1, math.min(5, #tl) do
                    GameTooltip:AddDoubleLine("  " .. tl[i].name, tl[i].count,
                        0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
                end
                if #tl > 5 then
                    GameTooltip:AddLine("  +" .. (#tl - 5) .. " more", DIM[1], DIM[2], DIM[3])
                end
            end
        end
    end

    GameTooltip:Show()
end

onRowLeave = function(self)
    stripeRow(self, self.rowIdx or 1)
    GameTooltip:Hide()
end

------------------------------------------------------------------------
-- Refresh — table view
------------------------------------------------------------------------
refreshUI = function()
    if activeTab == "timeline" then return end
    updateHeaders()

    local list = buildList()
    local total = #list

    if total == 0 then
        footer:SetText(activeTab == "party"
            and "No party targets recorded yet."
            or "No targets recorded yet.")
        scrollChild:SetHeight(ROW_HEIGHT)
        local row = acquireRow(1)
        row.data = nil; row.rowIdx = 1
        row.rank:SetText("\226\128\148")
        row.name:SetText("(no data)"); row.name:SetTextColor(DIM[1], DIM[2], DIM[3])
        row.count:SetText(""); row.kind:SetText(""); row.zone:SetText(""); row.seen:SetText("")
        row.bar:Hide()
        stripeRow(row, 1); row:Show()
        for j = 2, #rows do rows[j]:Hide() end
        scroll:SetVerticalScroll(0)
        return
    end

    local cap = math.min(total, MAX_ROWS)
    scrollChild:SetHeight(math.max(ROW_HEIGHT, cap * ROW_HEIGHT))

    local maxCount = 1
    for i = 1, cap do
        if list[i].sortCount > maxCount then maxCount = list[i].sortCount end
    end

    for i = 1, cap do
        local it  = list[i]
        local e   = it.entry
        local row = acquireRow(i)
        row.data   = it
        row.rowIdx = i

        row.rank:SetText(tostring(i))
        row.rank:SetTextColor(DIM[1], DIM[2], DIM[3])

        row.name:SetText(e.name or "?")
        if e.isPlayer and e.class then
            local cc = classColor(e.class)
            if cc then row.name:SetTextColor(cc.r, cc.g, cc.b)
            else row.name:SetTextColor(0.9, 0.9, 0.9) end
        else
            row.name:SetTextColor(0.9, 0.9, 0.9)
        end

        row.count:SetText(tostring(it.sortCount))
        row.count:SetTextColor(1, 1, 1)

        local barW = math.max(1, (it.sortCount / maxCount) * COL_COUNT)
        row.bar:SetWidth(barW)
        local pct = it.sortCount / maxCount
        row.bar:SetColorTexture(
            ACCENT[1] * 0.6 + 0.1 * pct,
            ACCENT[2] * 0.4 + 0.1 * pct,
            ACCENT[3] * 0.5 + 0.2 * pct,
            0.15 + 0.20 * pct
        )
        row.bar:Show()

        if activeTab == "party" then
            row.kind:SetText(topTracker(e))
            row.zone:SetText("")
        else
            row.kind:SetText(kindSummary(e))
            row.zone:SetText(topZone(e))
        end
        row.kind:SetTextColor(0.7, 0.7, 0.7)
        row.zone:SetTextColor(0.7, 0.7, 0.7)
        row.seen:SetText(relTime(e.lastSeen))
        row.seen:SetTextColor(DIM[1], DIM[2], DIM[3])
        stripeRow(row, i); row:Show()
    end

    for j = cap + 1, #rows do rows[j]:Hide() end

    local mode = sessionMode and "session" or "all time"
    if total > cap then
        footer:SetText(string.format("Top %d of %d (%s)  |  sorted by %s", cap, total, mode, sortField))
    else
        footer:SetText(string.format("%d unique target(s) (%s)  |  sorted by %s", total, mode, sortField))
    end
    scroll:SetVerticalScroll(0)
end

------------------------------------------------------------------------
-- Refresh — graph view
------------------------------------------------------------------------
refreshGraph = function()
    local curHour = math.floor(time() / 3600)
    local totals  = {}
    local maxVal  = 1

    local p = TargetCount_GetProfile()
    for _, entry in pairs(p.targets) do
        if entry.timeline then
            for hk, cnt in pairs(entry.timeline) do
                local h = tonumber(hk)
                if h and h > curHour - GRAPH_HOURS and h <= curHour then
                    local idx = h - (curHour - GRAPH_HOURS)
                    totals[idx] = (totals[idx] or 0) + cnt
                end
            end
        end
    end

    for i = 1, GRAPH_HOURS do
        if (totals[i] or 0) > maxVal then maxVal = totals[i] end
    end

    local gw = graphFrame:GetWidth() - 20
    local gh = graphFrame:GetHeight() - 44
    local bw = gw / GRAPH_HOURS

    local totalEvents = 0
    for i = 1, GRAPH_HOURS do
        local cnt = totals[i] or 0
        totalEvents = totalEvents + cnt

        if not graphBars[i] then
            local bar = CreateFrame("Button", nil, graphFrame)
            bar:EnableMouse(true)
            bar.tex = bar:CreateTexture(nil, "ARTWORK")
            bar.tex:SetAllPoints()
            bar:SetScript("OnEnter", function(self)
                self.tex:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(self.hourLabel or "", 1, 1, 1)
                GameTooltip:AddLine(string.format("%d event(s)", self.cnt or 0), 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end)
            bar:SetScript("OnLeave", function(self)
                if (self.cnt or 0) > 0 then
                    self.tex:SetColorTexture(ACCENT[1] * 0.7, ACCENT[2] * 0.7, ACCENT[3] * 0.9, 0.65)
                else
                    self.tex:SetColorTexture(0.25, 0.25, 0.30, 0.2)
                end
                GameTooltip:Hide()
            end)
            graphBars[i] = bar

            graphLabels[i] = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        end

        local bar   = graphBars[i]
        local label = graphLabels[i]
        local barH  = math.max(2, (cnt / maxVal) * gh)

        bar:SetSize(math.max(1, bw - 2), barH)
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", graphFrame, "BOTTOMLEFT", 10 + (i - 1) * bw, 28)
        bar.cnt = cnt

        local hour = (curHour - GRAPH_HOURS + i) % 24
        bar.hourLabel = string.format("%02d:00", hour)

        if cnt > 0 then
            bar.tex:SetColorTexture(ACCENT[1] * 0.7, ACCENT[2] * 0.7, ACCENT[3] * 0.9, 0.65)
        else
            bar.tex:SetColorTexture(0.25, 0.25, 0.30, 0.2)
        end
        bar:Show()

        if i % 4 == 0 or i == 1 then
            label:SetText(string.format("%02d:00", hour))
            label:ClearAllPoints()
            label:SetPoint("TOP", bar, "BOTTOM", 0, -2)
            label:Show()
        else
            label:Hide()
        end
    end

    graphTitle:SetText(string.format("Last %d hours \226\128\148 %d events (peak %d/hr)", GRAPH_HOURS, totalEvents, maxVal))
    footer:SetText(string.format("Timeline: %d events across %d hours", totalEvents, GRAPH_HOURS))
end

------------------------------------------------------------------------
-- Tab switching
------------------------------------------------------------------------
local function setActiveTab(name)
    activeTab = name
    updateTabHighlight()
    if name == "timeline" then
        filterFrame:Hide(); headerFrame:Hide(); scroll:Hide()
        graphFrame:Show()
        refreshGraph()
    else
        graphFrame:Hide()
        filterFrame:Show(); headerFrame:Show(); scroll:Show()
        refreshUI()
    end
end

tabTargets:SetScript("OnClick",  function() setActiveTab("targets") end)
tabParty:SetScript("OnClick",    function() setActiveTab("party") end)
tabTimeline:SetScript("OnClick", function() setActiveTab("timeline") end)
updateTabHighlight()

------------------------------------------------------------------------
-- Export frame
------------------------------------------------------------------------
local exportFrame = CreateFrame("Frame", "TargetCountExportFrame", UIParent, "BackdropTemplate")
exportFrame:SetSize(440, 300)
exportFrame:SetPoint("CENTER")
exportFrame:SetFrameStrata("DIALOG")
exportFrame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
exportFrame:SetBackdropColor(0.06, 0.06, 0.10, 0.97)
exportFrame:SetBackdropBorderColor(0.35, 0.38, 0.50, 0.8)
exportFrame:EnableMouse(true)
exportFrame:Hide()
tinsert(UISpecialFrames, "TargetCountExportFrame")

local exportClose = CreateFrame("Button", nil, exportFrame, "UIPanelCloseButton")
exportClose:SetPoint("TOPRIGHT", -2, -2)
exportClose:SetSize(22, 22)

local exportTitle = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
exportTitle:SetPoint("TOP", 0, -10)
exportTitle:SetText("Export \226\128\148 Ctrl+A, Ctrl+C to copy")

local exportScroll = CreateFrame("ScrollFrame", "TargetCountExportScroll", exportFrame, "UIPanelScrollFrameTemplate")
exportScroll:SetPoint("TOPLEFT", 12, -30)
exportScroll:SetPoint("BOTTOMRIGHT", -30, 10)

local exportBox = CreateFrame("EditBox", "TargetCountExportBox", exportScroll)
exportBox:SetMultiLine(true)
exportBox:SetFontObject(GameFontHighlightSmall)
exportBox:SetWidth(390)
exportBox:SetAutoFocus(true)
exportBox:SetScript("OnEscapePressed", function() exportFrame:Hide() end)
exportScroll:SetScrollChild(exportBox)

local function showExport()
    local list = buildList()
    local lines = {}
    local mode = sessionMode and "Session" or "All Time"
    local prof = TargetCount_GetDB().activeProfile
    local header = activeTab == "party" and "Party Targets" or "Targets"
    lines[1] = string.format("TargetCount - %s (%s, Profile: %s)", header, mode, prof)
    lines[2] = string.rep("-", 60)
    local cap = math.min(#list, 50)
    for i = 1, cap do
        local e = list[i].entry
        local z = activeTab == "party" and topTracker(e) or topZone(e)
        lines[#lines + 1] = string.format("#%-3d  %-22s %5d  %-10s  %s",
            i, (e.name or "?"):sub(1, 22), list[i].sortCount, e.lastKind or "\226\128\148", z)
    end
    lines[#lines + 1] = string.rep("-", 60)
    lines[#lines + 1] = string.format("Total: %d unique entries", #list)

    exportBox:SetText(table.concat(lines, "\n"))
    exportBox:HighlightText()
    exportFrame:Show()
    exportBox:SetFocus()
end

------------------------------------------------------------------------
-- Bottom buttons
------------------------------------------------------------------------
local resetBtn = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
resetBtn:SetSize(72, 22)
resetBtn:SetPoint("BOTTOMLEFT", 10, 8)
resetBtn:SetText("Reset")
resetBtn:SetScript("OnClick", function() StaticPopup_Show("TARGETCOUNT_RESET") end)

local exportBtn = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
exportBtn:SetSize(72, 22)
exportBtn:SetPoint("BOTTOMRIGHT", -10, 8)
exportBtn:SetText("Export")
exportBtn:SetScript("OnClick", showExport)

------------------------------------------------------------------------
-- Popups
------------------------------------------------------------------------
StaticPopupDialogs["TARGETCOUNT_RESET"] = {
    text            = "Clear ALL TargetCount data for the active profile?",
    button1         = "Yes",
    button2         = "No",
    OnAccept        = function() TargetCount_ResetStats(); refreshUI() end,
    timeout         = 0,
    whileDead       = true,
    hideOnEscape    = true,
}

StaticPopupDialogs["TARGETCOUNT_NEW_PROFILE"] = {
    text            = "Enter new profile name:",
    button1         = "Create",
    button2         = "Cancel",
    hasEditBox      = true,
    OnAccept        = function(self)
        local nm = self.editBox:GetText()
        if nm and nm:trim() ~= "" then
            TargetCount_SetProfile(nm:trim())
            profileBtn.fs:SetText(nm:trim() .. " \226\150\188")
            refreshUI()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local nm = self:GetText()
        if nm and nm:trim() ~= "" then
            TargetCount_SetProfile(nm:trim())
            profileBtn.fs:SetText(nm:trim() .. " \226\150\188")
            refreshUI()
        end
        parent:Hide()
    end,
    timeout         = 0,
    whileDead       = true,
    hideOnEscape    = true,
}

------------------------------------------------------------------------
-- Global callback from Core.lua
------------------------------------------------------------------------
function TargetCount_OnStatsChanged()
    if main:IsShown() then
        if activeTab == "timeline" then refreshGraph()
        else refreshUI() end
    end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SlashCmdList["TARGETCOUNT"] = function(msg)
    msg = (msg or ""):trim():lower()
    if msg == "reset" then
        TargetCount_ResetStats()
        print("|cff00ccffTargetCount:|r Stats reset.")
    elseif msg == "export" then
        if not main:IsShown() then refreshUI(); main:Show() end
        showExport()
    elseif msg:find("^profile ") then
        local name = msg:sub(9):trim()
        if name ~= "" then
            TargetCount_SetProfile(name)
            profileBtn.fs:SetText(name .. " \226\150\188")
            print("|cff00ccffTargetCount:|r Switched to profile: " .. name)
            if main:IsShown() then refreshUI() end
        end
    else
        if main:IsShown() then main:Hide()
        else setActiveTab(activeTab); main:Show() end
    end
end
SLASH_TARGETCOUNT1 = "/targetcount"
SLASH_TARGETCOUNT2 = "/tc"

------------------------------------------------------------------------
-- OnShow & ADDON_LOADED (restore saved position)
------------------------------------------------------------------------
main:SetScript("OnShow", function()
    if activeTab == "timeline" then refreshGraph()
    else refreshUI() end
end)

local uiLoadFrame = CreateFrame("Frame")
uiLoadFrame:RegisterEvent("ADDON_LOADED")
uiLoadFrame:SetScript("OnEvent", function(_, _, loaded)
    if type(loaded) ~= "string" or loaded:lower() ~= "targetcount" then return end
    local d = TargetCount_GetDB()
    local ui = d.ui
    if ui and ui.point and ui.relPoint and ui.x and ui.y then
        main:ClearAllPoints()
        main:SetPoint(ui.point, UIParent, ui.relPoint, ui.x, ui.y)
    end
    profileBtn.fs:SetText((d.activeProfile or "Default") .. " \226\150\188")
end)
