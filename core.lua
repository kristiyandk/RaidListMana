-- 1. Create the Main Window
local f = CreateFrame("Frame", "RaidListMana", UIParent)
f:SetPoint("CENTER") 
-- Note: SetBackdrop is removed so the frame is transparent/invisible

-- HIDE ON LOAD: Starts in "Sleep Mode"
f:Hide()

-- 2. Make it Draggable
-- Since the frame is invisible, we rely on the text/size to catch mouse clicks.
f:EnableMouse(true)
f:SetMovable(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)

-- 3. Create the Text Area
f.text = f:CreateFontString(nil, "ARTWORK")
f.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
f.text:SetPoint("TOPLEFT", 0, 0) 
f.text:SetJustifyH("LEFT")
f.text:SetJustifyV("TOP")
f.text:SetText("Waiting for raid...")

-- 4. Configuration
local updateInterval = 0.5 
local timeSinceLastUpdate = 0
local PALADIN_MANA_CUTOFF = 20000 
local LINE_HEIGHT = 14 
local TITLE_HEIGHT = 20 
local FRAME_WIDTH = 200 

-- Helper: Get Hex Color for Class
local function GetClassColorString(className)
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[className] then
        local color = RAID_CLASS_COLORS[className]
        -- Convert standard WoW colors (0-1) to Hex code (e.g. ff00a1)
        return string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
    end
    return "|cffffffff" -- Default to White if class not found
end

-- 5. The Healer Detector
local function IsActiveHealer(unitID, classFileName)
    -- PRIEST: Healer if NOT in Shadowform
    if classFileName == "PRIEST" then
        local i = 1
        while true do
            local name = UnitBuff(unitID, i)
            if not name then break end
            if name == "Shadowform" then return false end
            i = i + 1
        end
        return true 
    end

    -- DRUID: Healer if in "Tree of Life" form
    if classFileName == "DRUID" then
        local i = 1
        while true do
            local name = UnitBuff(unitID, i)
            if not name then break end
            if name == "Tree of Life" then return true end
            i = i + 1
        end
        return false
    end

    -- SHAMAN: Healer if "Water Shield" or "Earth Shield"
    if classFileName == "SHAMAN" then
        local i = 1
        while true do
            local name = UnitBuff(unitID, i)
            if not name then break end
            if name == "Water Shield" or name == "Earth Shield" then return true end
            i = i + 1
        end
        return false
    end

    -- PALADIN: Healer if Max Mana > Threshold (High Intellect)
    if classFileName == "PALADIN" then
        if UnitPowerMax(unitID) > PALADIN_MANA_CUTOFF then
            return true
        else
            return false
        end
    end

    return false
end

-- 6. The Main Update Logic
local function UpdateRoster()
    local count = GetNumRaidMembers()
    
    local rosterString = "Healer's Mana:\n"
    local healerCount = 0 -- We use this to resize the frame later

    for i = 1, count do
        local unitID = "raid" .. i
        local name, _, _, _, _, classFileName, _, online, isDead = GetRaidRosterInfo(i)

        if name then
            -- FILTER: Must be a potential healer class
            if classFileName == "PRIEST" or classFileName == "PALADIN" or classFileName == "DRUID" or classFileName == "SHAMAN" then
                
                -- CHECK: Are they actually healing?
                if IsActiveHealer(unitID, classFileName) then
                    
                    -- IMPORTANT: Count them so we can resize the frame!
                    healerCount = healerCount + 1
                    
                    local current = UnitPower(unitID)
                    local max = UnitPowerMax(unitID)
                    local percent = 0
                    if max > 0 then
                        percent = math.floor((current / max) * 100)
                    end

                    -- 1. Get the color code (e.g., "|cffF58CBA" for Paladin)
                    local colorCode = GetClassColorString(classFileName)

                    -- 2. Wrap the name in color: Color + Name + Reset (|r)
                    local coloredName = colorCode .. name .. "|r"

                    -- 3. Use the COLORED name in the string format
                    local lineText = string.format("%s: %d%%", coloredName, percent)

                    if not online then lineText = lineText .. " (Off)"
                    elseif isDead then lineText = lineText .. " (Dead)" end

                    rosterString = rosterString .. lineText .. "\n"
                end
            end
        end
    end

    -- Handle empty list
    if healerCount == 0 then
        rosterString = "No active healers."
        healerCount = 1 -- Keep frame slightly open to show the message
    end

    f.text:SetText(rosterString)

    -- Dynamic Scaling: Resize the invisible drag area to fit the text
    local newHeight = TITLE_HEIGHT + (healerCount * LINE_HEIGHT) + 10
    f:SetSize(FRAME_WIDTH, newHeight)
end

-- 7. The Frame Engine
f:SetScript("OnUpdate", function(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate > updateInterval then
        UpdateRoster()
        timeSinceLastUpdate = 0
    end
end)

-- 8. The Wake Up Switch
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

f:SetScript("OnEvent", function()
    if GetNumRaidMembers() > 0 then
        if not f:IsShown() then
            f:Show() 
            f.text:SetText("Initializing...")
        end
    else
        if f:IsShown() then
            f:Hide()
        end
    end
end)

-- 9. Slash Command to Scale the Addon
-- Type "/hmt 1.2" to scale it to 120%
SLASH_HEALERMANA1 = "/rlm"
SlashCmdList["HEALERMANA"] = function(msg)
    local scale = tonumber(msg)
    
    if scale and scale >= 0.3 and scale <= 5 then
        f:SetScale(scale)
        print("|cff00ff00RaidListMana:|r Scale set to " .. scale)
    else
        print("|cff00ff00RaidListMana:|r Usage: /rlm <number>")
        print("Example: /rlm 1.2")
    end
end