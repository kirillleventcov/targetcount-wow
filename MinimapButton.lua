local ICON_TEXTURE    = "Interface\\Icons\\INV_Misc_Target_01"
local DEFAULT_ANGLE   = 225
local EDGE_PAD        = 6

local btn = CreateFrame("Button", "TargetCountMinimapButton", Minimap)
btn:SetSize(32, 32)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
btn:SetMovable(true)
btn:SetClampedToScreen(true)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")

local overlay = btn:CreateTexture(nil, "OVERLAY")
overlay:SetSize(54, 54)
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
overlay:SetPoint("TOPLEFT", 0, 0)

local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetSize(20, 20)
icon:SetTexture(ICON_TEXTURE)
icon:SetPoint("CENTER", 0, 1)

local bg = btn:CreateTexture(nil, "BACKGROUND")
bg:SetSize(24, 24)
bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
bg:SetPoint("CENTER", 0, 1)

local function isSquareMinimap()
    -- ElvUI, SexyMap, etc. define this global when they reshape the minimap
    return type(GetMinimapShape) == "function" and GetMinimapShape() == "SQUARE"
end

local function positionButton(angle)
    local rad = math.rad(angle)
    local cos_a = math.cos(rad)
    local sin_a = math.sin(rad)

    local hw = Minimap:GetWidth()  / 2 + EDGE_PAD
    local hh = Minimap:GetHeight() / 2 + EDGE_PAD
    local x, y

    if isSquareMinimap() then
        -- Project the unit-circle direction onto the rectangle perimeter
        local abs_c = math.abs(cos_a)
        local abs_s = math.abs(sin_a)
        if abs_c < 0.001 then
            x, y = 0, (sin_a > 0 and hh or -hh)
        elseif abs_s < 0.001 then
            x, y = (cos_a > 0 and hw or -hw), 0
        else
            local s = math.min(hw / abs_c, hh / abs_s)
            x, y = cos_a * s, sin_a * s
        end
    else
        local radius = math.min(hw, hh)
        x = cos_a * radius
        y = sin_a * radius
    end

    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function getAngle()
    local d = TargetCount_GetDB()
    return d.ui and d.ui.minimapAngle or DEFAULT_ANGLE
end

local function saveAngle(angle)
    local d = TargetCount_GetDB()
    d.ui = d.ui or {}
    d.ui.minimapAngle = angle
end

local function angleFromCursor()
    local cx, cy = Minimap:GetCenter()
    local mx, my = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    return math.deg(math.atan2(my / s - cy, mx / s - cx))
end

positionButton(DEFAULT_ANGLE)

btn:SetScript("OnDragStart", function(self)
    self.dragging = true
    self:SetScript("OnUpdate", function()
        local a = angleFromCursor()
        positionButton(a)
        saveAngle(a)
    end)
end)

btn:SetScript("OnDragStop", function(self)
    self.dragging = false
    self:SetScript("OnUpdate", nil)
end)

btn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
        local d = TargetCount_GetDB()
        d.ui = d.ui or {}
        d.ui.minimapHidden = true
        btn:Hide()
        print("|cff00ccffTargetCount:|r Minimap button hidden. Type /tc minimap to show it again.")
        return
    end
    if TargetCountFrame:IsShown() then
        TargetCountFrame:Hide()
    else
        TargetCountFrame:Show()
    end
end)

btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("TargetCount", 1, 1, 1)
    local p = TargetCount_GetProfile()
    local count = 0
    for _ in pairs(p.targets) do count = count + 1 end
    GameTooltip:AddLine(count .. " unique targets", 0.8, 0.8, 0.8)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: toggle window", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click: hide button", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Drag to reposition", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)

btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

------------------------------------------------------------------------
-- Slash command extension: /tc minimap
-- Wraps whatever slash handler is registered at ADDON_LOADED time,
-- guaranteeing both UI.lua and this file have finished loading.
------------------------------------------------------------------------
local function hookMinimapSlash()
    local prev = SlashCmdList["TARGETCOUNT"]
    SlashCmdList["TARGETCOUNT"] = function(msg)
        local cmd = (msg or ""):trim():lower()
        if cmd == "minimap" then
            local d = TargetCount_GetDB()
            d.ui = d.ui or {}
            if d.ui.minimapHidden then
                d.ui.minimapHidden = false
                btn:Show()
                print("|cff00ccffTargetCount:|r Minimap button shown.")
            else
                d.ui.minimapHidden = true
                btn:Hide()
                print("|cff00ccffTargetCount:|r Minimap button hidden.")
            end
            return
        end
        if prev then prev(msg) end
    end
end

------------------------------------------------------------------------
-- ADDON_LOADED: restore angle and visibility
------------------------------------------------------------------------
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:SetScript("OnEvent", function(_, _, loaded)
    if type(loaded) ~= "string" or loaded:lower() ~= "targetcount" then return end
    positionButton(getAngle())
    local d = TargetCount_GetDB()
    if d.ui and d.ui.minimapHidden then btn:Hide() end
    hookMinimapSlash()
end)

------------------------------------------------------------------------
-- LDB / Data Broker (optional — works if LibDataBroker-1.1 is loaded)
------------------------------------------------------------------------
if LibStub then
    local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
    if ldb then
        ldb:NewDataObject("TargetCount", {
            type  = "launcher",
            icon  = ICON_TEXTURE,
            label = "TargetCount",
            OnClick = function(_, button)
                if button == "LeftButton" then
                    if TargetCountFrame:IsShown() then TargetCountFrame:Hide()
                    else TargetCountFrame:Show() end
                end
            end,
            OnTooltipShow = function(tt)
                tt:AddLine("TargetCount", 1, 1, 1)
                local p = TargetCount_GetProfile()
                local c = 0
                for _ in pairs(p.targets) do c = c + 1 end
                tt:AddLine(c .. " unique targets", 0.8, 0.8, 0.8)
                tt:AddLine("Click to toggle window", 0.6, 0.6, 0.6)
            end,
        })
    end
end
