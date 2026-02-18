local f = CreateFrame("Frame", "RaidListMana", UIParent)
f:SetPoint("CENTER") 

-- HIDE ON LOAD: Starts in "Sleep Mode"
f:Hide()

f:EnableMouse(true)
f:SetMovable(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)

--Text Area
f.text = f:CreateFontString(nil, "ARTWORK")
f.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
f.text:SetPoint("TOPLEFT", 0, 0) 
f.text:SetJustifyH("LEFT")
f.text:SetJustifyV("TOP")
f.text:SetText("Waiting for raid...")

-- Configuration
local updateInterval = 0.5 
local timeSinceLastUpdate = 0
local LINE_HEIGHT = 14 
local TITLE_HEIGHT = 20 
local FRAME_WIDTH = 200 

-- Get Hex Color for Class
local function GetClassColorString(className)
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[className] then
        local color = RAID_CLASS_COLORS[className]
        return string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
    end
    return "|cffffffff" -- Default to White if class not found
end

-- HELPER: Scan Raid to find Earth Shield Casters
-- Returns a table: { ["raid1"] = true } for any unit that CAST an Earth Shield
local function GetActiveRestoShamans()
    local confirmedHealers = {}
    local count = GetNumRaidMembers()
    
    for i = 1, count do
        local targetUnit = "raid" .. i
        local bIndex = 1
        while true do
            local name, _, _, _, _, _, _, unitCaster = UnitBuff(targetUnit, bIndex)
            if not name then break end
            
            -- If we find Earth Shield, the CASTER is a Resto Shaman
            if name == "Earth Shield" and unitCaster then
                confirmedHealers[unitCaster] = true
            end
            bIndex = bIndex + 1
        end
    end
    return confirmedHealers
end

-- The Precise Healer Detector
local function IsActiveHealer(unitID, classFileName, confirmedShamans)
    local maxMana = UnitPowerMax(unitID)

    -- BASELINE FILTER: 
    -- Filter out Ret Paladins, Enh Shamans, Ferals (<12k Mana)
    if maxMana < 12000 then return false end

    -- PRIEST: Healer if NOT in Shadowform
    if classFileName == "PRIEST" then
        local i = 1
        while true do
            local name = UnitBuff(unitID, i)
            if not name then break end
            if name == "Shadowform" then return false end -- Found Shadowform = DPS
            i = i + 1
        end
        return true
    end

    -- DRUID: Healer if NOT in DPS/Tank Forms
    if classFileName == "DRUID" then
        local i = 1
        while true do
            local name = UnitBuff(unitID, i)
            if not name then break end
            -- If we see Moonkin, Cat, or Bear, they are NOT a healer
            if name == "Moonkin Form" or name == "Cat Form" or name == "Bear Form" or name == "Dire Bear Form" then 
                return false 
            end
            i = i + 1
        end
        return true
    end

    -- SHAMAN: The "Precise" Check
    if classFileName == "SHAMAN" then
        -- CHECK A: Are they the source of an active Earth Shield? (100% Guaranteed Healer)
        if confirmedShamans[unitID] then return true end

        -- CHECK B: Do they have massive mana? (>24k)
        -- Elemental usually hovers around 18k-22k. Resto pushes 30k+.
        if maxMana > 24000 then return true end

        -- If they have low mana and NO Earth Shield out, assume Elemental/Enh
        return false
    end

    -- PALADIN: Healer based on Mana Pool
    -- Holy Paladins stack Intellect (30k+ Mana). Prot/Ret do not.
    if classFileName == "PALADIN" then
        if maxMana > 20000 then 
            return true 
        end
        return false
    end

    return false
end

-- The Main Update Logic
local function UpdateRoster()
    local count = GetNumRaidMembers()
    
    local rosterString = "Healers Mana:\n"
    local healerCount = 0 
    
    -- Step 1: Pre-scan for Earth Shield owners
    local confirmedShamans = GetActiveRestoShamans()

    for i = 1, count do
        local unitID = "raid" .. i
        local name, _, _, _, _, classFileName, _, online, isDead = GetRaidRosterInfo(i)

        if name then
            -- FILTER: Must be a potential healer class
            if classFileName == "PRIEST" or classFileName == "PALADIN" or classFileName == "DRUID" or classFileName == "SHAMAN" then
                
                -- CHECK: Are they actually healing? (Pass the Shaman table)
                if IsActiveHealer(unitID, classFileName, confirmedShamans) then
                    
                    healerCount = healerCount + 1
                    
                    local current = UnitPower(unitID)
                    local max = UnitPowerMax(unitID)
                    local percent = 0
                    if max > 0 then
                        percent = math.floor((current / max) * 100)
                    end

                    -- 1. Get the color code
                    local colorCode = GetClassColorString(classFileName)

                    -- 2. Wrap the name in color
                    local coloredName = colorCode .. name .. "|r"

                    -- 3. Format the line
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
        healerCount = 1 
    end

    f.text:SetText(rosterString)

    -- Dynamic Scaling: Resize the invisible drag area to fit the text
    local newHeight = TITLE_HEIGHT + (healerCount * LINE_HEIGHT) + 10
    f:SetSize(FRAME_WIDTH, newHeight)
end

-- The Frame Engine
f:SetScript("OnUpdate", function(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate > updateInterval then
        UpdateRoster()
        timeSinceLastUpdate = 0
    end
end)

-- The Wake Up Switch
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

-- Slash Command to Scale the Addon
SLASH_HEALERMANA1 = "/rlm"
SlashCmdList["HEALERMANA"] = function(msg)
    local scale = tonumber(msg)
    
    if scale and scale >= 0.5 and scale <= 4 then
        f:SetScale(scale)
        print("|cff00ff00RaidListMana:|r Scale set to " .. scale)
    else
        print("|cff00ff00RaidListMana:|r Usage: /rlm <number>")
        print("Example: /rlm 1.2")
    end
end