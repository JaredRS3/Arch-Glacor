---@module 'AG.config'
---@author Jared
---@description Hardmode AG configuration - consistent to 2500-3000% enrage
local Config = {}

local API = require("api")

local RotationManager = require("Arch-Glacor.core.rotation_manager")
local PrayerFlicker = require("Arch-Glacor.core.prayer_flicker")
local Timer = require("Arch-Glacor.core.timer")

local Utils = require("Arch-Glacor.AG.utils")

-- Add debug logging for status changes
local lastStatus = ""
local function logStatusChange(newStatus)
    if newStatus ~= lastStatus then
        Utils.debugLog(string.format("Status Change: %s -> %s", lastStatus, newStatus))
        lastStatus = newStatus
    end
end

-- Animation IDs for mechanic detection (placeholders - you'll fill these in)
local MECHANIC_ANIMATIONS = {
    ArmsAnim = 34282,           -- Exposed Core (Arms) animation
    MinionsAnim = 34281,        -- Glacyte Minions animation
    PillarsAnim = 34279,        -- Pillars of Ice animation
    FlurryAnims = {34274, 34275, 34276, 34277}, -- Flurry animations
    FrostCannonAnim = 34278     -- Frost Cannon animation
}
local ArchGlacorId = 28241
-- Object IDs for mechanic end detection (placeholders - you'll fill these in)
local MECHANIC_OBJECTS = {
    ArmId = 28242,              -- Arm object ID
    MinionIds = {28248, 28246}, -- Multiple minion IDs
    BolsterMinionId = 28247,
    UnstableIceId = 28249,      -- Unstable ice object ID
    IceIds = {121360, 121361, 121362, 121363, 121364},
    CoreId = 28249,             -- Core object ID
    BeamId = 28245              -- Beam object ID for pillars mechanic
}

-- At top of file after other object IDs
local GEAR_IDS = {
    TFN = {
        HEAD = 55488,
        BODY = 55498,
        LEGS = 55499,
        BOOTS = 55496
    },
    TANK = {
        HEAD = 52262,
        BODY = 55434,
        LEGS = 52282,
        BOOTS = 52270
    }
}

-- Helper function to perform improvise using any rotation manager instance
local function performImprovise(rotationInstance, spend, iterations)
    iterations = iterations or 1
    spend = spend or false
    
    for i = 1, iterations do
        -- Get the best ability to use from improvise system
        local bestAbility = rotationInstance:_improvise(spend)
        
        -- Use the ability
        if bestAbility then
            if rotationInstance:_useAbility(bestAbility) then
                Utils.debugLog("Used improvised ability: " .. bestAbility)
                return true
            else
                Utils.debugLog("Failed to use improvised ability: " .. bestAbility)
                return false
            end
        end
    end
    return false
end

--[[
    A friendly message:
        Hello! It's worth taking some time understanding how things work before playing around with some of the values.
        
        This script could have been much simpler and even consolidated into one file, but the main intention behind making this
        was to showcase the libraries being used and their potential when making more complex PVM'ing scripts.

    That being said, please feel free to bring all your questions and comments to the  thread.
    ---------

    Here's a quick breakdown of the configurations:

    - User Inputs
        - This is for the values that need to be defined by the user; includes values like:
            - Whether or not to use a bank pin
            - The value of said bank pin
            - The key pressed to target cycle (very important for clean rotations)
            - The health and prayer thresholds
                - Used by the player manager to know when to eat or use excalibur/elven ritual shard
            - The items in your loadout to check formatted before every kill

    - Rotation Manager Configuration
        You are invited to change and mess around without things here until you're happy with the result.
        - Will execute a rotation listed, one step at a time. (More details in rotation_manager.lua)
            - step = {
                label: string,                  The name of the ability or inventory item. Needs to be 100% accurate
                type: string,                   [OPTIONAL] Type of step used. Can be: "Ability" (default), "Inventory", "Improvise", or "Custom" (default: "Ability")
                action: function(): boolean,    [OPTIONAL] The function to execute with type = "Custom"
                wait: number,                   [OPTIONAL] The amount of time to wait before executing the next step (default 3 ticks)
                useTicks: boolean,              [OPTIONAL] Whether or not to use game ticks or real-time for waiting (default: true)
                style: string,                  [OPTIONAL] Used for improvising: Only "Necromancy" is currently supported
                useAdren: boolean,              [OPTIONAL] If true, will attempt to spend adrenaline as it sees fit
                condition: function(): boolean, [OPTIONAL] If true, will execute the step, otherwise it will attempt to either use replacementAction or skip 
                replacementLabel: string,       [OPTIONAL] Replacement ability for when step condition is not met
                replacementAction: function     [OPTIONAL] Replacement action for when step condition is not met 
                replacementWait: number         [OPTIONAL] Replacement wait time for when step condition is not met 
            }
        - You can have different rotations for different stages.

    - Buff Configuration
        - The values in this list are the ones that will be managed while inside the boss room
        - Feel free to add to the list or change existing values according to your preferences
        - buff = {
            buffName: string,                   The name of the buff
            buffId: number,                     The Bbar ID for checking if the buff is accurate
            execute: function()                 The function to execute in order to apply the buff
            canApply: function(any): boolean,   [OPTIONAL] Function to check if the buff should be applied
            toggle: boolean                     [OPTIONAL] Whether or not to toggle the buff off (re-execute) while not managed
            refreshAt: number                   [OPTIONAL] Number of seconds to refresh the buff at
        }

             MECHANIC DETECTION SYSTEM:
             
             The script now automatically detects which of the 5 mechanics is active based on Arch-Glacor's animation ID.
             When a mechanic is detected, it automatically switches to the appropriate rotation:
             
             - Arms (Exposed Core): Uses ArmsRotation
             - Minions (Glacyte Minions): Uses MinionsRotation 
             - Pillars (Pillars of Ice): Uses PillarsRotation with beam avoidance strategy:
               * Move to beamspot[1] and wait
               * When beam within 4 tiles, Bladed Dive to beamspot[2]
               * When beam within 4 tiles again, Surge to beamspot[3]
               * Use Soul Sap, then final Surge when beam approaches
             - Flurry: Uses FlurryRotation (includes Living Death usage)
             - Frost Cannon: Uses FrostCannonRotation
             
             The system tracks:
             - Current active mechanic
             - Mechanic history (last 5 mechanics)
             - Mechanic count for the fight
             - Automatic rotation state transfer between mechanics
             - Beam positions for pillars mechanic (beamspots[1-3])
             
             TODO: Fill in the actual IDs in MECHANIC_ANIMATIONS and MECHANIC_OBJECTS tables above
]]

Config.Instances, Config.TrackedKills = {}, {}

Config.UserInput = {
    -- essential
    useBankPin = false,
    bankPin = 1234,                 -- use ur own [0000 will spam your console]
    targetCycleKey = 0x09,          -- 0x09 is tab
    -- health and prayer thresholds (settings for player manager)
    healthThreshold = {
        normal = {type = "percent", value = 65},
        critical = {type = "percent", value = 60},
        special = {type = "percent", value = 75}  -- excal threshold
    },
    prayerThreshold = {
        normal = {type = "current", value = 200},
        critical = {type = "percent", value = 10},
        special = {type = "current", value = 600}  -- elven shard threshold
    },
    -- things to check in your inventory before fight
    presetChecks = {
        {id = 48951, amount = 68}, -- 69 x vuln bombs
        {id = 28227, amount = 4},  -- 4  x super sara brews
        {id = 42267, amount = 4},  -- 4  x blue blubbers
        {id = 57164, amount = 1},  -- 1  x ode to deceit
    },
    aura = {
        id = 22294,
        name = "Equilibrium aura",
        buffId = 26098, 
        interfaceSlot = 23
    },
    -- (private method)
    Notifications = true,
    webhookUrl = "",
    mention = true,
    userId = ""
}

Config.Variables = {
    -- flags 
    initialCheck = false,
    conjuresSummoned = false,
    bossDead = false,
    initialRotationComplete = false,  -- Track if initial rotation is complete
    hasUniqueInChest = false,  -- New flag to track if unique is in chest
    chestChecked = false,  -- Track if chest has been checked this kill
    clickedAqueductPortal = false,  -- New flag to track if we've clicked the aqueduct portal
    -- mechanic tracking
    currentMechanic = "none",
    lastMechanic = "none",
    pendingMechanic = "none",
    mechanicStartTick = 0,
    lastMechanicDetectionTick = 0,  -- Track when last mechanic was detected for cooldown
    armsEndTick = 0,  -- Track when arms mechanic ended for cooldown
    mechanicCount = 0,
    mechanicHistory = {},  -- Track the 5 mechanics in order
    -- minion targeting
    targetMinionsActive = false,  -- Flag to control when minion targeting timer is active
    -- attempts
    bankAttempts = 0,
    conjureAttempts = 0,
    killCount = 0,
    -- tiles
    adreCrystalTile = {x = 0, y = 0, z = 0},
    adreCrystalBDTile = {x = 0, y = 0, z = 0},
    poratlTile = {x = 0, y = 0, z = 0},
    lootTile = {x = 0, y = 0, z = 0},
    startspot = {x = 0, y = 0, range = 0},  -- Initialize startspot
    safeSpot = {x = 0, y = 0, range = 0},
    -- misc
    adrenCrystalSide = "East",
    gateTile = nil,
    beamspots = nil,
    armspot = nil,  -- Add armspot alongside beamspots
    inTFNGear = false,
    needTFNForConjures = false,
    minionEndTick = nil,  -- Track when minions are first detected as gone
    minionsDetected = false,  -- Track if minions have actually spawned
    pillarsDetected = false,  -- Track if pillars have actually spawned
    armsDetected = false,  -- Track if arms have actually spawned
    mechanicEndTicks = {
        arms = 0,
        minions = 0,
        pillars = 0,
        flurry = 0,
        frostcannon = 0
    },
    iceDetectedForDive = false,
    chestLooted = false,  -- Track if we've looted/continued from chest
    lastIcePositions = {left = nil, right = nil},
    chestContainerOpenTime = 0,  -- Track when chest container first opened
    deathStep = nil,
    deathStepTick = nil,
    threeBeamsDetectedTime = nil, -- Track when we first detected 3+ beams for emergency timing
    deathLootStep = nil,
    deathLootStepTick = nil,
    -- Death loot tracking variables
    diedInBossRoom = false,  -- Track if we died in the boss room
    hadContinuedChallenge = false,  -- Track if we had continued challenge before death
    deathLootAvailable = false,  -- Track if there's loot to collect from death
    everUsedContinueChallenge = false,  -- Track if continue challenge has ever been used this session
    totalSeenInChest = 0,
    totalClaimed = 0,
    killLogged = false,
    enrageDetected = false,
}

Config.Data = {
    loot = {
        51808, -- Resonant anima of Wen (tradeable)
        995, -- Coins
        44813, -- Banite stone spirit
        6693, -- Crushed nest
        989, -- Crystal key
        52018, -- Glacor remnants
        31867, -- Hydrix bolt tips
        52121, -- Medium blunt orikalkum salvage
        12176, -- Spirit weed seed
        32821, -- Summoning focus
        1631, -- Uncut dragonstone
        1395, -- Water battlestaff
        1444, -- Water talisman
        42954, -- Onyx dust
        29863, -- Sirenic scale
        28550, -- Crystal triskelion
        6571, -- Uncut onyx
        52021, -- Leng artefact
        52019, -- Dark nilas
        51817, -- Manuscript of Wen
        52115, -- Scripture of Wen
        
    },

    -- rare drops
    uniques = {
        52020, -- Frozen core of Leng
        52120, -- Glacor core
    },

    uniqueDropData = {
        [52020] = {
            name = "Frozen core of Leng",
            thumbnail = "https://runescape.wiki/images/Frozen_core_of_Leng_detail.png"
        },
        --[52115] = {
        --    name = "Scripture of Wen",
        --    thumbnail = "https://runescape.wiki/images/Scripture_of_Wen_detail.png"
        --},
        [52120] = {
            name = "Glacor core",
            thumbnail = "https://runescape.wiki/images/Glacor_core_detail.png"
        },
    },
    lootedUniques = {}
}

--#region rotation manager init
Config.RotationManager = {
    -- this rotation references and tries to match the equilibrium rotation listed on the PVME
    -- assumes t100 weapons and t99 prayers, amongst other best-in-slot items
    InitialRotation = {
        name = "Initial Rotation",
        rotation = {
            --prefight steps
            {label = "Delay", type = "Custom", action = function() return true end, wait = 2},
            {label = "Invoke Death"},
            {label = "Conjure Undead Army"},
            {label = "Life Transfer"},
            {label = "Command Skeleton Warrior"},
            {
                label = "Target cycle",
                type = "Custom",
                action = function()
                    print("[TARGET CYCLE]: Tick = "..API.Get_tick() - Config.Timer.handleInstance.lastTriggered)
                    API.KeyboardPress2(Config.UserInput.targetCycleKey, 60, 0)
                    return true
                end,
                wait = 0
            },
            {label = "Vulnerability bomb", type = "Inventory", wait = 0},
            --fight
            {label = "Touch of Death", action = function () Config.Variables.initialRotationComplete = true end},
            -- Set flag to end initial rotation after Bloat and Debilitate
            {
                label = "End Initial Rotation",
                type = "Custom",
                action = function()
                    Config.Variables.initialRotationComplete = true
                    return true
                end,
                wait = 0
            },
           
        }
    },
    fightRotation = {
        name = "Fight Rotation",
        rotation = {
            {
                label = "Equip Soulbound Lantern",
                type = "Custom",
                action = function()
                    if Inventory:InvItemFound(55485) then
                        return API.DoAction_Inventory1(55485, 0, 2, API.OFF_ACT_GeneralInterface_route)
                    end
                    return true -- Skip if not found
                end,
                wait = 0
            },
            {label = "Improvise", type = "Improvise", style = "Necromancy", spend = false}
        }
    },
    PillarsRotation = {
        name = "Pillars Rotation",
        rotation = {
            
            {
                label = "Move to beamspot 1",
                type = "Custom",
                action = function()
                    if Config.Variables.beamspots and Config.Variables.beamspots[1] then
                        local spot1 = Config.Variables.beamspots[1]
                        local playerCoords = API.PlayerCoord()
                        local distance = math.sqrt((playerCoords.x - spot1.x)^2 + (playerCoords.y - spot1.y)^2)
                        
                        if distance <= 1 then
                            Utils.debugLog("Already at beamspot 1")
                            return true -- Already there, advance
                        end
                        
                        Utils.debugLog("Moving to beamspot 1: (" .. spot1.x .. ", " .. spot1.y .. ") Distance: " .. string.format("%.1f", distance))
                        ---@diagnostic disable-next-line
                        API.DoAction_WalkerW(WPOINT.new(spot1.x, spot1.y, 0))
                        
                        -- If far away, wait for orientation 270° then surge
                        if distance > 3 then
                            local playerOrientation = math.floor(API.calculatePlayerOrientation()) % 360
                            if math.abs(playerOrientation - 270) <= 10 then
                                Utils.debugLog("Orientation 270 reached, surging to spot 1")
                                if Utils.useAbility("Surge") then
                                    API.RandomSleep2(50, 30, 30)
                                    ---@diagnostic disable-next-line
                                    API.DoAction_WalkerW(WPOINT.new(spot1.x, spot1.y, 0))
                                end
                            end
                        end
                        return false -- Still moving, don't advance
                    end
                    return true
                end,
                wait = 0,
                useTicks = true
            },
            {
                label = "Wait for beam within 4 distance and anim -1",
                type = "Custom",
                action = function()
                    -- Check for ice objects first
                    local iceExists = false
                    for _, iceId in ipairs(MECHANIC_OBJECTS.IceIds) do
                        local iceObjects = Utils.findAll(iceId, 0, 20)
                        if #iceObjects > 0 then
                            iceExists = true
                            break
                        end
                    end
                    
                    -- Track ice detection state
                    if not Config.Variables.iceDetectedForDive then
                        Config.Variables.iceDetectedForDive = false
                    end
                    
                    -- If ice exists, mark it as detected
                    if iceExists then
                        if not Config.Variables.iceDetectedForDive then
                            Utils.debugLog("Ice detected - waiting for ice to disappear before diving")
                            Config.Variables.iceDetectedForDive = true
                        end
                    else
                        -- If ice was detected but now disappeared, dive
                        if Config.Variables.iceDetectedForDive then
                            Utils.debugLog("Ice disappeared - diving to beamspot 3")
                            Config.Variables.iceDetectedForDive = false -- Reset for next time
                            return true
                        end
                    end
                    
                    local beams = Utils.findAll(MECHANIC_OBJECTS.BeamId, 1, 20)
                    
                    if #beams == 0 then
                        Utils.debugLog("No beams yet, waiting...")
                        return false -- Keep waiting
                    end
                    
                    local closestDistance = math.huge
                    local closestBeam = nil
                    for _, beam in ipairs(beams) do
                        if beam.Distance < closestDistance then
                            closestDistance = beam.Distance
                            closestBeam = beam
                        end
                    end
                    
                    Utils.debugLog(string.format("Closest beam: distance=%.1f, anim=%d", closestDistance, closestBeam.Anim))
                    
                    if closestDistance <= 4 and closestBeam.Anim == -1 then
                        Utils.debugLog("Beam conditions met (<=4 tiles, anim=-1), proceeding to dive")
                        return true -- Conditions met, advance
                    else
                        Utils.debugLog(string.format("Waiting for beam conditions: need <=4 distance AND anim=-1, current: %.1f distance, anim=%d", closestDistance, closestBeam.Anim))
                        return false -- Keep waiting
                    end
                end,
                wait = 0,
                useTicks = true
            },
            {
                label = "Dive to beamspot 3",
                type = "Custom",
                action = function()
                    if Config.Variables.beamspots and Config.Variables.beamspots[3] then
                        local spot3 = Config.Variables.beamspots[3]
                        Utils.debugLog("Diving to beamspot 3: (" .. spot3.x .. ", " .. spot3.y .. ")")
                        ---@diagnostic disable-next-line
                        API.DoAction_Dive_Tile(WPOINT.new(spot3.x, spot3.y, 0))
                    end
                    return true
                end,
                wait =1,
                useTicks = true
            },
            {
                label = "Wait for ice to disappear",
                type = "Custom",
                action = function()
                    -- Check if any ice objects still exist
                    for _, iceId in ipairs(MECHANIC_OBJECTS.IceIds) do
                        local iceObjects = Utils.findAll(iceId, 0, 30)
                        if #iceObjects > 0 then
                            Utils.debugLog("Waiting for ice to disappear...")
                            return false -- Ice still exists, keep waiting
                        end
                    end
                    Utils.debugLog("All ice objects have disappeared, proceeding")
                    return true -- No ice found, proceed
                end,
                wait = 0,
                useTicks = true
            },
            {
                label = "Click beamspot 4",
                type = "Custom",
                action = function()
                    if Config.Variables.beamspots and Config.Variables.beamspots[4] then
                        local spot4 = Config.Variables.beamspots[4]
                        Utils.debugLog("Clicking beamspot 4: (" .. spot4.x .. ", " .. spot4.y .. ")")
                        ---@diagnostic disable-next-line
                        API.DoAction_WalkerW(WPOINT.new(spot4.x, spot4.y, 0))
                    end
                    return true
                end,
                wait = 1,
                useTicks = true
            },
            {
                label = "Wait for beam conditions to surge to spot 5",
                type = "Custom",
                action = function()
                    local beams = Utils.findAll(MECHANIC_OBJECTS.BeamId, 1, 30)
                    
                    -- Track if beams have been detected (use a persistent variable)
                    if #beams > 0 then
                        Config.Variables.beamsDetectedForSpot5 = true
                    end
                    
                    -- Track when we first detected 3+ beams for emergency timing
                    if #beams >= 3 and not Config.Variables.threeBeamsDetectedTime then
                        Config.Variables.threeBeamsDetectedTime = API.Get_tick()
                        Utils.debugLog("Detected 3+ beams, starting emergency timer")
                    end
                    
                    -- If beams were detected but now disappeared, proceed
                    if Config.Variables.beamsDetectedForSpot5 and #beams == 0 then
                        Utils.debugLog("Beams were detected but now disappeared - proceeding to spot 5")
                        Config.Variables.beamsDetectedForSpot5 = false -- Reset for next time
                        Config.Variables.threeBeamsDetectedTime = nil -- Reset emergency timer
                        return true
                    end
                    
                    if #beams == 0 then
                        Utils.debugLog("No beams yet, waiting...")
                        return false -- Keep waiting
                    end
                    
                    local playerCoords = API.PlayerCoord()
                    local playerX = playerCoords.x
                    
                    -- Find beams behind and in front
                    local beamBehind = nil
                    local beamFront = nil
                    local beamBehindDistance = math.huge
                    local beamFrontDistance = math.huge
                    
                    -- Collect all beam distances and animations for debugging
                    local allBeamDistances = {}
                    local allBeamAnimations = {}
                    
                    for _, beam in ipairs(beams) do
                        local beamX = beam.Tile_XYZ.x
                        table.insert(allBeamDistances, string.format("%.1f", beam.Distance))
                        table.insert(allBeamAnimations, tostring(beam.Anim))
                        
                        if beamX <= playerX and beam.Distance < beamBehindDistance then
                            beamBehind = beam
                            beamBehindDistance = beam.Distance
                        elseif beamX > playerX and beam.Distance < beamFrontDistance then
                            beamFront = beam
                            beamFrontDistance = beam.Distance
                        end
                    end
                    
                    -- Print all beam distances and animations
                    Utils.debugLog(string.format("All beam distances: [%s] | Behind: %.1f | Front: %.1f", 
                        table.concat(allBeamDistances, ", "), 
                        beamBehindDistance == math.huge and -1 or beamBehindDistance,
                        beamFrontDistance == math.huge and -1 or beamFrontDistance))
                    
                    Utils.debugLog(string.format("All beam animations: [%s] | Behind anim: %s | Front anim: %s",
                        table.concat(allBeamAnimations, ", "),
                        beamBehind and tostring(beamBehind.Anim) or "N/A",
                        beamFront and tostring(beamFront.Anim) or "N/A"))
                    
                    -- Check if player is moving
                    local playerMoving = API.ReadPlayerMovin2()
                    Utils.debugLog(string.format("Player moving: %s", tostring(playerMoving)))
                    
                    -- Check conditions
                    local beamBehindClose = beamBehind and beamBehindDistance <= 4 and beamBehind.Anim == -1
                    local beamFrontClose = beamFront and beamFrontDistance <= 7 and beamFront.Anim == -1
                    local beamFrontFar = beamFront and beamFrontDistance >= 7 and beamFront.Anim == -1
                    local beamFrontVeryClose = beamFront and beamFrontDistance <= 4.5 and beamFront.Anim == -1
                    local beamBackVeryClose = beamBehind and beamBehindDistance <= 2 and beamBehind.Anim == -1
                    local beamwalkingFrontVeryClose = beamFront and beamFrontDistance <= 4 and beamFront.Anim == -1
                    -- EMERGENCY WALK LOGIC: Check if we should walk forward 2 tiles
                    -- EMERGENCY WALK FOR INACTIVE BEAMS: Walk forward if inactive beam is <=2 tiles in front
                    -- This should run BEFORE the emergency timer logic, as a standalone check
                    local inactiveFrontBeam = nil
                    local inactiveFrontDistance = math.huge

                    -- Find closest inactive beam in front of player
                    for _, beam in ipairs(beams) do
                        local beamX = beam.Tile_XYZ.x
                        if beamX > playerX and beam.Anim ~= -1 then -- Beam in front and not active yet
                            local distance = math.abs(playerX - beamX)
                            if distance < inactiveFrontDistance then
                                inactiveFrontBeam = beam
                                inactiveFrontDistance = distance
                            end
                        end
                    end

                    -- If we found an inactive beam in front, check if we should walk forward
                    if inactiveFrontBeam then
                        local beamX = inactiveFrontBeam.Tile_XYZ.x
                        local distanceToBeam = beamX - playerX
                        
                        Utils.debugLog(string.format("Inactive beam detected in front: X=%.1f, Distance=%.1f, Anim=%d", 
                            beamX, distanceToBeam, inactiveFrontBeam.Anim))
                        
                        -- If beam is <=2 tiles in front, start walking forward
                        if distanceToBeam <= 2 and distanceToBeam > -2 then -- Walk until beam is 2 tiles behind us
                            Utils.debugLog(string.format("EMERGENCY WALK INACTIVE: Beam %.1f tiles ahead (<=2) - walking forward +2 tiles", distanceToBeam))
                            local newX = playerCoords.x + 3
                            ---@diagnostic disable-next-line
                            API.DoAction_WalkerW(WPOINT.new(newX, playerCoords.y, 0))
                            return false -- Keep checking
                        elseif distanceToBeam <= -2 then
                            Utils.debugLog(string.format("EMERGENCY WALK INACTIVE: Beam now %.1f tiles behind - stopping emergency walk", math.abs(distanceToBeam)))
                        end
                    end

                    -- THEN your existing emergency timer logic starts here:
                    local currentTick = API.Get_tick()
                    local emergencyWalkCondition = false
                    if Config.Variables.threeBeamsDetectedTime then
                        -- Remove the inactive beam logic from inside here and keep only the existing emergency conditions
                        local ticksSince = currentTick - Config.Variables.threeBeamsDetectedTime
                        Utils.debugLog(string.format("EMERGENCY DEBUG: %d ticks since 3+ beams detected (need 2+ for emergency)", ticksSince))
                        
                        if ticksSince >= 0 then
                            Utils.debugLog("EMERGENCY DEBUG: Emergency timer threshold reached!")
                            
                            -- PRIORITY 1: If front beam <=2, surge immediately +4 tiles if further front beam >=8
                            local frontVeryClose = beamFront and beamFrontDistance <= 2
                            local furtherFrontFar = false
                            
                            -- Look for beams further ahead (beyond the close front beam)
                            if frontVeryClose then
                                local furtherBeams = Utils.findAll(MECHANIC_OBJECTS.BeamId, 1, 30)
                                for _, beam in ipairs(furtherBeams) do
                                    local beamDistance = math.abs(playerCoords.x - beam.Tile_XYZ.x)
                                    if beamDistance >= 6.5 and beam.Tile_XYZ.x > playerCoords.x then
                                        furtherFrontFar = true
                                        Utils.debugLog(string.format("EMERGENCY DEBUG: Found further front beam at distance %.1f", beamDistance))
                                        break
                                    end
                                end
                            end
                            
                            Utils.debugLog(string.format("EMERGENCY DEBUG: Front very close (<=2): %s, Further front far (>=6.5): %s", 
                                tostring(frontVeryClose), tostring(furtherFrontFar)))
                            
                            if frontVeryClose and furtherFrontFar then
                                emergencyWalkCondition = true
                                Utils.debugLog("EMERGENCY WALK +2: Front beam <= tiles and further front beam >=8 tiles - walking forward 4 tiles")
                                local newX = playerCoords.x + 2
                                ---@diagnostic disable-next-line
                                API.DoAction_WalkerW(WPOINT.new(newX, playerCoords.y, 0))
                                return false
                            end
                            
                            -- PRIORITY 2: Original emergency walk logic (behind close + front far)
                            local emergencyBehindClose = beamBehind and beamBehindDistance <= 3
                            local emergencyFrontFar = beamFront and beamFrontDistance >= 6
                            Utils.debugLog(string.format("EMERGENCY DEBUG: Behind close (<=3): %s, Front far (>=6): %s", 
                                tostring(emergencyBehindClose), tostring(emergencyFrontFar)))
                            if emergencyBehindClose and emergencyFrontFar then
                                emergencyWalkCondition = true
                                Utils.debugLog("EMERGENCY WALK +2: Behind beam <=3 tiles and front beam >=6 tiles - walking forward 2 tiles")
                                local newX = playerCoords.x + 2
                                ---@diagnostic disable-next-line
                                API.DoAction_WalkerW(WPOINT.new(newX, playerCoords.y, 0))
                                return false
                            else
                                Utils.debugLog("EMERGENCY WALK NOT TRIGGERED: Conditions not met")
                            end
                        else
                            Utils.debugLog("EMERGENCY DEBUG: Still waiting for 2-tick delay")
                        end
                    end
                    local currentTick = API.Get_tick()
                    local emergencyWalkCondition = false
                    if Config.Variables.threeBeamsDetectedTime then
                        local ticksSince = currentTick - Config.Variables.threeBeamsDetectedTime
                        Utils.debugLog(string.format("EMERGENCY DEBUG: %d ticks since 3+ beams detected (need 2+ for emergency)", ticksSince))
                        
                        if ticksSince >= 0 then
                            Utils.debugLog("EMERGENCY DEBUG: Emergency timer threshold reached!")
                            
                            -- PRIORITY 1: If front beam <=2, surge immediately +4 tiles if further front beam >=8
                            local frontVeryClose = beamFront and beamFrontDistance <= 2
                            local furtherFrontFar = false
                            
                            -- Look for beams further ahead (beyond the close front beam)
                            if frontVeryClose then
                                local furtherBeams = Utils.findAll(MECHANIC_OBJECTS.BeamId, 1, 30)
                                for _, beam in ipairs(furtherBeams) do
                                    local beamDistance = math.abs(playerCoords.x - beam.Tile_XYZ.x)
                                    if beamDistance >= 6.5 and beam.Tile_XYZ.x > playerCoords.x then
                                        furtherFrontFar = true
                                        Utils.debugLog(string.format("EMERGENCY DEBUG: Found further front beam at distance %.1f", beamDistance))
                                        break
                                    end
                                end
                            end
                            
                            Utils.debugLog(string.format("EMERGENCY DEBUG: Front very close (<=2): %s, Further front far (>=6.5): %s", 
                                tostring(frontVeryClose), tostring(furtherFrontFar)))
                            
                            if frontVeryClose and furtherFrontFar then
                                emergencyWalkCondition = true
                                Utils.debugLog("EMERGENCY WALK +2: Front beam <= tiles and further front beam >=8 tiles - walking forward 4 tiles")
                                local newX = playerCoords.x + 2
                                ---@diagnostic disable-next-line
                                API.DoAction_WalkerW(WPOINT.new(newX, playerCoords.y, 0))
                                return false
                            end
                            
                            -- PRIORITY 2: Original emergency walk logic (behind close + front far)
                            local emergencyBehindClose = beamBehind and beamBehindDistance <= 3
                            local emergencyFrontFar = beamFront and beamFrontDistance >= 6
                            Utils.debugLog(string.format("EMERGENCY DEBUG: Behind close (<=3): %s, Front far (>=6): %s", 
                                tostring(emergencyBehindClose), tostring(emergencyFrontFar)))
                            if emergencyBehindClose and emergencyFrontFar then
                                emergencyWalkCondition = true
                                Utils.debugLog("EMERGENCY WALK +2: Behind beam <=3 tiles and front beam >=6 tiles - walking forward 2 tiles")
                                local newX = playerCoords.x + 2
                                ---@diagnostic disable-next-line
                                API.DoAction_WalkerW(WPOINT.new(newX, playerCoords.y, 0))
                                return false
                            else
                                Utils.debugLog("EMERGENCY WALK NOT TRIGGERED: Conditions not met")
                            end
                        else
                            Utils.debugLog("EMERGENCY DEBUG: Still waiting for 2-tick delay")
                        end
                    end
                    
                    -- PRIORITY 1: If front beam <=5, surge immediately (or back beam <=2 when not moving)
                    if beamFrontVeryClose or (beamBackVeryClose and not playerMoving) then
                        Utils.debugLog("Front beam <=5 tiles or Back Beam <=2.8 - EMERGENCY surge to spot 5 (ignoring behind beam)")
                        Utils.useAbility("Surge")
                        API.RandomSleep2(30, 50, 50)
                        
                        if Config.Variables.beamspots and Config.Variables.beamspots[5] then
                            local spot5 = Config.Variables.beamspots[5]
                            ---@diagnostic disable-next-line
                            API.DoAction_WalkerW(WPOINT.new(spot5.x, spot5.y, 0))
                        end
                        Config.Variables.beamsDetectedForSpot5 = false -- Reset
                        Config.Variables.threeBeamsDetectedTime = nil -- Reset emergency timer
                        return true
                        
                    -- If player is moving, ignore behind beam conditions and only check front beam
                    elseif playerMoving then
                        if beamFrontVeryClose then
                            Utils.debugLog("Player moving and front beam <=5 - surging to spot 5 (ignoring behind beam)")
                            Utils.useAbility("Surge")
                            API.RandomSleep2(30, 50, 50)
                            
                            if Config.Variables.beamspots and Config.Variables.beamspots[5] then
                                local spot5 = Config.Variables.beamspots[5]
                                ---@diagnostic disable-next-line
                                API.DoAction_WalkerW(WPOINT.new(spot5.x, spot5.y, 0))
                            end
                            Config.Variables.beamsDetectedForSpot5 = false -- Reset
                            Config.Variables.threeBeamsDetectedTime = nil -- Reset emergency timer
                            return true
                        else
                            Utils.debugLog("Player moving but front beam conditions not met, waiting...")
                            return false
                        end
                        
                    -- PRIORITY 2: If beam behind <=4 and beam front >=7, walk +2
                    elseif beamBehindClose and beamFrontFar then
                        Utils.debugLog("Beam behind <=4 and front >=7, walking +2 tiles and continuing")
                        local newX = playerCoords.x + 2
                        ---@diagnostic disable-next-line
                        API.DoAction_WalkerW(WPOINT.new(newX, playerCoords.y, 0))
                        -- Don't return true, keep waiting
                        return false
                        
                    -- PRIORITY 3: If beam behind <=4 and beam front <=7, surge
                    elseif beamBehindClose and beamFrontClose then
                        Utils.debugLog("Beam behind <=4 and front <=7, surging and clicking spot 5")
                        Utils.useAbility("Surge")
                        API.RandomSleep2(30, 50, 50)
                        
                        if Config.Variables.beamspots and Config.Variables.beamspots[5] then
                            local spot5 = Config.Variables.beamspots[5]
                            ---@diagnostic disable-next-line
                            API.DoAction_WalkerW(WPOINT.new(spot5.x, spot5.y, 0))
                        end
                        Config.Variables.beamsDetectedForSpot5 = false -- Reset
                        Config.Variables.threeBeamsDetectedTime = nil -- Reset emergency timer
                        return true
                    else
                        Utils.debugLog("Waiting for beam conditions...")
                        return false -- Keep waiting
                    end
                end,
                wait = 0,
                useTicks = true
            },
            {
                label = "Wait until at spot 5",
                type = "Custom",
                action = function()
                    if Config.Variables.beamspots and Config.Variables.beamspots[5] then
                        local spot5 = Config.Variables.beamspots[5]
                        local playerCoords = API.PlayerCoord()
                        local distanceToSpot5 = math.sqrt((playerCoords.x - spot5.x)^2 + (playerCoords.y - spot5.y)^2)
                        
                        if distanceToSpot5 > 1 then
                            local isMoving = API.ReadPlayerMovin2()
                            Utils.debugLog(string.format("Still moving to spot 5... [moving: %s]", tostring(isMoving)))
                            
                            -- If not moving and haven't reached destination, click again
                            if not isMoving then
                                Utils.debugLog("Movement stopped, re-clicking spot 5")
                                ---@diagnostic disable-next-line
                                API.DoAction_WalkerW(WPOINT.new(spot5.x, spot5.y, 0))
                            end
                            
                            return false -- Still moving, keep waiting
                        else
                            Utils.debugLog("Reached beamspot 5")
                            return true -- At position, proceed
                        end
                    end
                    return true -- No beamspot, skip waiting
                end,
                wait = 0,
                useTicks = true
            },
            {
                label = "Wait for beam proximity then move to spot 6",
                type = "Custom",
                action = function()
                    -- Check for ice within 10 distance (immediate movement)
                    for _, iceId in ipairs(MECHANIC_OBJECTS.IceIds) do
                        local iceObjects = Utils.findAll(iceId, 0, 10)
                        if #iceObjects > 0 then
                            Utils.debugLog("Ice detected within 10 tiles, moving to spot 6 immediately")
                            if Config.Variables.beamspots and Config.Variables.beamspots[6] then
                                local spot6 = Config.Variables.beamspots[6]
                                --if API.GetABs_name1("Dive").cooldown_timer <= 1 then
                                 --   ---@diagnostic disable-next-line
                                --    API.DoAction_Dive_Tile(WPOINT.new(spot6.x, spot6.y, 0))
                               -- else
                                ---@diagnostic disable-next-line
                                API.DoAction_WalkerW(WPOINT.new(spot6.x, spot6.y, 0))
                                --end
                            end
                            return true
                        end
                    end
                    
                    local beams = Utils.findAll(MECHANIC_OBJECTS.BeamId, 1, 30)
                    
                    if #beams == 0 then
                        Utils.debugLog("No beams, proceeding to spot 6")
                        return true -- No beams, proceed
                    end
                    
                    local closestDistance = math.huge
                    local closestBeam = nil
                    for _, beam in ipairs(beams) do
                        if beam.Distance < closestDistance then
                            closestDistance = beam.Distance
                            closestBeam = beam
                        end
                    end
                    
                    if closestDistance <= 4 and closestBeam.Anim == -1 then
                        Utils.debugLog("Moving to beamspot 6")
                        if Config.Variables.beamspots and Config.Variables.beamspots[6] then
                            local spot6 = Config.Variables.beamspots[6]
                            --if API.GetABs_name1("Dive").cooldown_timer <= 1 then
                             --   ---@diagnostic disable-next-line
                            --    API.DoAction_Dive_Tile(WPOINT.new(spot6.x, spot6.y, 0))
                            --else
                            ---@diagnostic disable-next-line
                            API.DoAction_WalkerW(WPOINT.new(spot6.x, spot6.y, 0))
                            --end
                        end
                        return true
                    else
                        Utils.debugLog("Waiting for beam proximity to move to spot 6...")
                        return false -- Keep waiting
                    end
                end,
                wait = 0,
                useTicks = true
            },
            {
                label = "Wait until at spot 6",
                type = "Custom",
                action = function()
                    if Config.Variables.beamspots and Config.Variables.beamspots[6] then
                        local spot6 = Config.Variables.beamspots[6]
                        local playerCoords = API.PlayerCoord()
                        local distanceToSpot6 = math.sqrt((playerCoords.x - spot6.x)^2 + (playerCoords.y - spot6.y)^2)
                        
                        if distanceToSpot6 > 1.5 then
                            local isMoving = API.ReadPlayerMovin2()
                            Utils.debugLog(string.format("Still moving to spot 6... [moving: %s]", tostring(isMoving)))
                            
                            -- If not moving and haven't reached destination, click again
                            if not isMoving then
                                Utils.debugLog("Movement stopped, re-clicking spot 6")
                                ---@diagnostic disable-next-line
                                API.DoAction_WalkerW(WPOINT.new(spot6.x, spot6.y, 0))
                            end
                            
                            return false -- Still moving, keep waiting
                        else
                            Utils.debugLog("Reached beamspot 6")
                            return true -- At position, proceed
                        end
                    end
                    return true -- No beamspot, skip waiting
                end,
                wait = 0,
                useTicks = true
            },
            {
                label = "Wait for beam proximity then move to spot 7",
                type = "Custom",
                action = function()
                    -- Check for ice within 10 distance (immediate movement)
                    for _, iceId in ipairs(MECHANIC_OBJECTS.IceIds) do
                        local iceObjects = Utils.findAll(iceId, 0, 10)
                        if #iceObjects > 0 then
                            Utils.debugLog("Ice detected within 10 tiles, moving to spot 7 immediately")
                            if Config.Variables.beamspots and Config.Variables.beamspots[7] then
                                local spot7 = Config.Variables.beamspots[7]
                                ---@diagnostic disable-next-line
                                API.DoAction_WalkerW(WPOINT.new(spot7.x, spot7.y, 0))
                            end
                            return true
                        end
                    end
                    
                    local beams = Utils.findAll(MECHANIC_OBJECTS.BeamId, 1, 30)
                    
                    if #beams == 0 then
                        Utils.debugLog("No beams, proceeding to spot 7")
                        return true -- No beams, proceed
                    end
                    
                    local closestDistance = math.huge
                    local closestBeam = nil
                    for _, beam in ipairs(beams) do
                        if beam.Distance < closestDistance then
                            closestDistance = beam.Distance
                            closestBeam = beam
                        end
                    end
                    
                    if closestDistance <= 4 and closestBeam.Anim == -1 then
                        Utils.debugLog("Walking to beamspot 7")
                        if Config.Variables.beamspots and Config.Variables.beamspots[7] then
                            local spot7 = Config.Variables.beamspots[7]
                            ---@diagnostic disable-next-line
                            API.DoAction_WalkerW(WPOINT.new(spot7.x, spot7.y, 0))
                        end
                        return true
                    else
                        Utils.debugLog("Waiting for beam proximity to move to spot 7...")
                        return false -- Keep waiting
                    end
                end,
                wait = 0,
                useTicks = true
            },
            {
                label = "Check if pillars mechanic complete",
                type = "Custom",
                action = function()
                    -- Check if beams are gone, indicating mechanic should end
                    local beams = Utils.findAll(MECHANIC_OBJECTS.BeamId, 1, 30)
                    
                    if #beams == 0 then
                        Utils.debugLog("Pillars rotation: All beams gone, mechanic should end")
                        -- Force the rotation to be trailing so it ends and transfers back
                        Config.Instances.PillarsRotation.trailing = true
                        return true
                    end
                    
                    -- Also check for timeout
                    local currentTick = API.Get_tick()
                    local mechanicDuration = currentTick - Config.Variables.mechanicStartTick
                    if mechanicDuration > 80 then -- 48 seconds timeout
                        Utils.debugLog("Pillars rotation: Timeout reached, forcing mechanic to end")
                        Config.Instances.PillarsRotation.trailing = true
                        return true
                    end
                    
                    Utils.debugLog(string.format("Pillars rotation: Beams still present (%d), continuing mechanic", #beams))
                    return false -- Continue pillars mechanic
                end,
                wait = 1,
                useTicks = true
            }
        }
    },

    ArmsRotation = {
        name = "Arms Rotation",
        rotation = {
            {
                label = "Walk to armspot",
                type = "Custom",
                action = function()
                    if Config.Variables.armspot and
                       Config.Variables.armspot.x and Config.Variables.armspot.y and
                       type(Config.Variables.armspot.x) == "number" and type(Config.Variables.armspot.y) == "number" and
                       Config.Variables.armspot.x == Config.Variables.armspot.x and
                       Config.Variables.armspot.y == Config.Variables.armspot.y then

                        Utils.debugLog(string.format("Walking to armspot: (%.0f, %.0f)", Config.Variables.armspot.x, Config.Variables.armspot.y))
                        ---@diagnostic disable-next-line
                        return API.DoAction_WalkerW(WPOINT.new(Config.Variables.armspot.x, Config.Variables.armspot.y, 0))
                    else
                        Utils.debugLog("Armspot coordinates invalid, cannot walk to position")
                        return false
                    end
                end,
                wait = 1,
                useTicks = true
            },
            {label = "Invoke Death"},
            {
                label = "Wait for arm to spawn then attack",
                type = "Custom",
                action = function()
                    local arms = Utils.findAll(MECHANIC_OBJECTS.ArmId, 1, 30)
                    if #arms == 0 then
                        Utils.debugLog("No arms found, waiting for arm to spawn...")
                        return false -- Keep waiting for arms
                    end

                    Utils.debugLog("Arm detected, attacking")
                    API.RandomSleep2(150, 50, 50)

                    -- Try to attack arm
                    API.DoAction_NPC(0x2a,API.OFF_ACT_AttackNPC_route,{ MECHANIC_OBJECTS.ArmId },50)

                    -- Check if we're targeting it
                    local targetInfo = API.ReadTargetInfo(true)
                    if targetInfo and targetInfo.Target_Name == "Icy Arm (left)" then
                        Utils.debugLog("Successfully targeting Icy Arm (left)")
                        return true
                    else
                        Utils.debugLog("Not targeting arm yet, will try again next cycle")
                        return false -- Will retry on next execution
                    end
                end,
                wait = 0,
                useTicks = true
            },
            {label = "Vulnerability bomb", type = "Inventory", wait = 0},
            {label = "Equip T90 Skull Lantern", type = "Custom", action = function()
                Inventory:Equip(55545)  -- T90 skull lantern
                return true
            end, wait = 0},
            {
                label = "Soul Sap",
                condition = function()
                    local souls = RotationManager:getBuff(30123).remaining
                    return souls <= 1
                end
            },
            {label = "Soul Strike"},
            {
                label = "Basic<nbsp>Attack",
                condition = function()
                    return not (API.GetABs_name1("Soul Sap").cooldown_timer <= 2) and RotationManager:getBuff(30123).remaining == 0
                end
            },
            {
                label = "Soul Sap",
                condition = function()
                    local souls = RotationManager:getBuff(30123).remaining
                    return souls == 0 and API.GetABs_name1("Soul Sap").cooldown_timer <= 2
                end
            },
            {label = "Soul Strike"},
            {
                label = "Re-equip Soulbound Lantern",
                type = "Custom",
                action = function()
                    if Inventory:InvItemFound(55485) then
                        Inventory:Equip(55485)  -- Soulbound lantern
                        return true
                    end
                    return false
                end,
                wait = 0
            },
            {label = "Improvise", type = "Improvise", style = "Necromancy", spend = false},
            {
                label = "Move to post-arms position",
                type = "Custom",
                action = function()
                    if Config.Variables.startspot and
                       Config.Variables.startspot.x and Config.Variables.startspot.y and
                       type(Config.Variables.startspot.x) == "number" and type(Config.Variables.startspot.y) == "number" and
                       Config.Variables.startspot.x == Config.Variables.startspot.x and
                       Config.Variables.startspot.y == Config.Variables.startspot.y then

                        local targetX = math.floor(Config.Variables.startspot.x - 7)
                        local targetY = math.floor(Config.Variables.startspot.y - 1)
                        Utils.debugLog(string.format("Moving to post-arms position: (%d, %d)", targetX, targetY))
                        ---@diagnostic disable-next-line
                        return API.DoAction_WalkerW(WPOINT.new(targetX, targetY, 0))
                    else
                        Utils.debugLog("Startspot coordinates invalid, cannot move to post-arms position")
                        return false
                    end
                end,
                wait = 1,
                useTicks = true
            }
        }
    },
    
    FlurryRotation = {
        name = "Flurry Rotation",
        rotation = {
            {label = "Debilitate", condition = function() return API.GetHPrecent() < 50 end},
            {label = "Basic<nbsp>Attack"},
            {
                label = "0 ticking 1/2", type = "Custom", 
                condition = function() return API.GetAdrenalineFromInterface() >= 35 end,
                action = function()
                    Inventory:Equip(57164)  -- roar of awakening + ode to deceit
                    Inventory:Equip(57160)
                    Utils.useAbility("Ingenuity of the Humans")
                    Utils.useAbility("Weapon Special Attack")  -- magic spec
                    Inventory:Equip(55545) -- tier 90 skull lantern
                    return true
                end, 
                wait = 1
            },
            {
                label = "Equip Omni Guard", type = "Custom", 
                
                action = function()
                    Inventory:Equip(55484) -- t95 necro
                    return true
                end, 
                wait = 2
            },
            {
                label = "Re-equip Soulbound Lantern", 
                type = "Custom", 
                action = function()
                    if Inventory:InvItemFound(55485) then
                        Inventory:Equip(55485)  -- Soulbound lantern
                        return true
                    end
                    return true
                end, 
                wait = 0
            },
            {label = "Improvise", type = "Improvise", style = "Necromancy", spend = true}
        }
    },

    FrostCannonRotation = {
        name = "Frost Cannon Rotation",
        rotation = {
            {label = "Adrenaline renewal potion", type = "Inventory", wait = 0, condition = function() return API.GetAdrenalineFromInterface() < 7 and not API.DeBuffbar_GetIDstatus(26094, false).found end},
            {label = "Anticipation", wait = 3},
            {label = "Limitless", wait = 0, condition = function() return API.GetAdrenalineFromInterface() <50 end},
            {label = "Reflect", condition = function() return API.GetABs_name1("Reflect").cooldown_timer <= 2 end, replacementLabel = "Devotion", wait = 2},
            --{label = "Reprisal", wait = 3},
            {label = "Powerburst of vitality", wait = 0,type = "Inventory", condition = function() return (not API.Buffbar_GetIDstatus(14225, false).found) and (not API.Buffbar_GetIDstatus(21665, false).found) end}, -- no Devotion or No Reflect
            {
                label = "Vengeance",
                type = "Custom", 
                action = function()
                    if Utils.useAbility("Spellbook Swap (Lunar)") then
                        Utils.debugLog("Swapped to Lunar spellbook for Vengeance")
                        API.RandomSleep2(100, 50, 50)
                        
                        if Utils.useAbility("Vengeance") then
                            Utils.debugLog("Used Vengeance")
                            return true
                        else
                            Utils.debugLog("Failed to use Vengeance")
                            return false
                        end
                    else
                        Utils.debugLog("Failed to swap to Lunar spellbook")
                        return false
                    end
                end,
                wait = 1
            },
            {label = "Divert", wait=2, condition = function() return API.GetABs_name1("Divert").cooldown_timer <= 2 end},
            {
                label = "Disruption Shield",
                type = "Custom",
                condition = function() return (API.GetABs_name1("Divert").cooldown_timer <= 28) or (not API.Buffbar_GetIDstatus(14225, false).found) end, -- No Divert or Reflect
                action = function()
                    if Utils.useAbility("Spellbook Swap (Lunar)") then
                        Utils.debugLog("Swapped to Lunar spellbook for Disruption Shield")
                        API.RandomSleep2(100, 50, 50)
                        
                        if Utils.useAbility("Disruption Shield") then
                            Utils.debugLog("Used Disruption Shield")
                            return true
                        else
                            Utils.debugLog("Failed to use Disruption Shield")
                            return false
                        end
                    else
                        Utils.debugLog("Failed to swap to Lunar spellbook")
                        return false
                    end
                end,
                wait = 1
            },
            {label = "Freedom", condition = function() return API.ReadPlayerAnim == 424 end},
            {label = "Improvise", type = "Improvise", style = "Necromancy", spend = false}
        }
    },

    MinionsRotation = {
        name = "Minions Rotation",
        rotation = {
            {
                label = "Activate Minion Targeting",
                type = "Custom",
                action = function()
                    Utils.debugLog("Activating automatic minion targeting immediately")
                    Config.Variables.targetMinionsActive = true
                    return true
                end,
                wait = 0,
                useTicks = true
            },
            {label = "Invoke Death"},
            {
                label = "Wait for minions to spawn",
                type = "Custom",
                action = function()
                    local bolstered = API.GetAllObjArray1({MECHANIC_OBJECTS.BolsterMinionId}, 60, {1})[1]
                    local minions1 = Utils.findAll(MECHANIC_OBJECTS.MinionIds[1], 1, 30)
                    local minions2 = Utils.findAll(MECHANIC_OBJECTS.MinionIds[2], 1, 30)

                    if not (bolstered or #minions1 > 0 or #minions2 > 0) then
                        Utils.debugLog("Waiting for minions to spawn...")
                        return false -- Stay on this step until minions spawn
                    end

                    Utils.debugLog("Minions detected, proceeding to positioning")
                    return true -- Advance to next step
                end,
                wait = 0,
                useTicks = true
            },
            {
                label = "Move to optimal minion position",
                type = "Custom",
                action = function()
                    local allMinions = {}
                    local normalMinions = {}  -- Only normal minions (no bolstered)

                    local bolstered = API.GetAllObjArray1({MECHANIC_OBJECTS.BolsterMinionId}, 60, {1})[1]
                    if bolstered then table.insert(allMinions, bolstered) end

                    local minions1 = Utils.findAll(MECHANIC_OBJECTS.MinionIds[1], 1, 30)
                    local minions2 = Utils.findAll(MECHANIC_OBJECTS.MinionIds[2], 1, 30)

                    -- Add to both lists
                    for _, minion in ipairs(minions1) do
                        table.insert(allMinions, minion)
                        table.insert(normalMinions, minion)
                    end
                    for _, minion in ipairs(minions2) do
                        table.insert(allMinions, minion)
                        table.insert(normalMinions, minion)
                    end

                    if #allMinions == 0 then
                        Utils.debugLog("No minions found, waiting...")
                        return false -- Wait for minions
                    end

                    local function findOptimalPosition(minionList, listName)
                        -- Calculate center position
                    local centerX, centerY = 0, 0
                        for _, minion in ipairs(minionList) do
                        centerX = centerX + minion.Tile_XYZ.x
                        centerY = centerY + minion.Tile_XYZ.y
                    end
                        centerX = math.floor(centerX / #minionList)
                        centerY = math.floor(centerY / #minionList)

                        -- Check if this position is within 4 tiles of all minions in the list
                        local validPosition = true
                        for _, minion in ipairs(minionList) do
                            local dx = math.abs(centerX - minion.Tile_XYZ.x)
                            local dy = math.abs(centerY - minion.Tile_XYZ.y)
                            if dx > 3.5 or dy > 3.5 then
                                validPosition = false
                                break
                            end
                        end

                        if validPosition then
                            Utils.debugLog(string.format("Found valid position for %s: (%d, %d)", listName, centerX, centerY))
                            return {x = centerX, y = centerY, valid = true}
                        end

                        -- Try to find a better position within a small search area
                        local bestTile = {x = centerX, y = centerY}
                        local bestDistance = math.huge

                        for offsetX = -2, 2 do
                            for offsetY = -2, 2 do
                                local testX = centerX + offsetX
                                local testY = centerY + offsetY
                                local totalDistance = 0
                                local validTile = true

                                for _, minion in ipairs(minionList) do
                                    local distance = math.sqrt((testX - minion.Tile_XYZ.x)^2 + (testY - minion.Tile_XYZ.y)^2)
                                    if distance > 3.5 then
                                        validTile = false
                                        break
                                    end
                                    totalDistance = totalDistance + distance
                                end

                                if validTile and totalDistance < bestDistance then
                                    bestDistance = totalDistance
                                    bestTile = {x = testX, y = testY}
                                end
                            end
                        end

                        -- Check if the best tile is actually valid
                        local finalValid = true
                        for _, minion in ipairs(minionList) do
                            local distance = math.sqrt((bestTile.x - minion.Tile_XYZ.x)^2 + (bestTile.y - minion.Tile_XYZ.y)^2)
                            if distance > 3.5 then
                                finalValid = false
                                break
                            end
                        end

                        Utils.debugLog(string.format("Best position for %s: (%d, %d) - Valid: %s",
                            listName, bestTile.x, bestTile.y, tostring(finalValid)))
                        return {x = bestTile.x, y = bestTile.y, valid = finalValid}
                    end

                    local targetPosition = nil
                    local targetMinions = nil

                    -- Priority 1: Try to position for ALL minions (including bolstered)
                    if bolstered and #normalMinions > 0 then
                        local allResult = findOptimalPosition(allMinions, "ALL minions (including bolstered)")
                        if allResult.valid then
                            targetPosition = allResult
                            targetMinions = allMinions
                            Utils.debugLog(string.format("Using position for ALL minions: (%d, %d) for %d total minions",
                                targetPosition.x, targetPosition.y, #allMinions))
                        end
                    end

                    -- Priority 2: Handle normal minions while staying closest to bolstered
                    if not targetPosition and #normalMinions > 0 and bolstered then
                        -- Find the position closest to bolstered that can hit ALL normal minions within 2.5 tiles
                        local function findPositionNearBolstered(minions, bolsteredPos)
                            local bestPosition = nil
                            local bestDistanceToBolstered = math.huge
                            local bolsteredX, bolsteredY = bolsteredPos.Tile_XYZ.x, bolsteredPos.Tile_XYZ.y

                            -- Search in a 7x7 grid around the bolstered minion to find valid positions
                            for dx = -3, 3 do
                                for dy = -3, 3 do
                                    local testX = math.floor(bolsteredX + dx)
                                    local testY = math.floor(bolsteredY + dy)

                                    -- Check if ALL normal minions are within 2.5 tiles from this position
                                    local allMinionsInRange = true
                                    for _, minion in ipairs(minions) do
                                        local mx, my = minion.Tile_XYZ.x, minion.Tile_XYZ.y
                                        local distance = math.sqrt((testX - mx)^2 + (testY - my)^2)
                                        if distance > 2.5 then -- Must be within 2.5 tiles of ALL normal minions
                                            allMinionsInRange = false
                                            break
                                        end
                                    end

                                    -- If this position can hit all normal minions, check if it's closer to bolstered
                                    if allMinionsInRange then
                                        local distanceToBolstered = math.sqrt((testX - bolsteredX)^2 + (testY - bolsteredY)^2)
                                        if distanceToBolstered < bestDistanceToBolstered then
                                            bestDistanceToBolstered = distanceToBolstered
                                            bestPosition = {x = testX, y = testY, valid = true}
                                        end
                                    end
                                end
                            end
                            return bestPosition, bestDistanceToBolstered
                        end

                        local nearBolsteredResult, distToBolstered = findPositionNearBolstered(normalMinions, bolstered)
                        if nearBolsteredResult and nearBolsteredResult.valid then
                            targetPosition = nearBolsteredResult
                            targetMinions = normalMinions
                            Utils.debugLog(string.format("Priority 2: Optimal positioning for normal minions while closest to bolstered: (%d, %d) for %d normal minions (%.1f tiles from bolstered)",
                                targetPosition.x, targetPosition.y, #normalMinions, distToBolstered))

                            -- Debug: Show distances to each minion
                            Utils.debugLog("=== POSITIONING DISTANCES ===")
                            for i, minion in ipairs(normalMinions) do
                                local distance = math.sqrt((targetPosition.x - minion.Tile_XYZ.x)^2 + (targetPosition.y - minion.Tile_XYZ.y)^2)
                                Utils.debugLog(string.format("Normal minion %d: %.1f tiles (within 2.5: %s)", i, distance, tostring(distance <= 2.5)))
                            end
                            Utils.debugLog(string.format("Bolstered minion: %.1f tiles", distToBolstered))
                            Utils.debugLog("=== END POSITIONING DEBUG ===")
                        else
                            Utils.debugLog("Priority 2 FAILED: Could not find position within 2.5 tiles of all normal minions near bolstered")
                        end
                    end

                    -- Priority 3: Fallback to normal minion positioning (regardless of bolstered presence)
                    if not targetPosition and #normalMinions > 0 then
                        Utils.debugLog("Priority 3: Falling back to optimal positioning for normal minions only")

                        local normalResult = findOptimalPosition(normalMinions, "normal minions fallback")
                        if normalResult.valid then
                            targetPosition = normalResult
                            targetMinions = normalMinions
                            Utils.debugLog(string.format("Priority 3: Using fallback positioning for normal minions: (%d, %d) for %d normal minions",
                                targetPosition.x, targetPosition.y, #normalMinions))
                        else
                            -- Even if not perfectly valid, use it as last resort
                            targetPosition = normalResult
                            targetMinions = normalMinions
                            Utils.debugLog(string.format("Priority 3: Using imperfect fallback positioning: (%d, %d) for %d normal minions (may be >3.5 tiles from some)",
                                targetPosition.x, targetPosition.y, #normalMinions))
                        end
                    end

                    if not targetPosition then
                        Utils.debugLog("Could not find valid positioning for any minion configuration")
                        return false
                    end

                    -- Target appropriate minion (prioritize bolstered if using all minions)
                    if bolstered then
                    ---@diagnostic disable-next-line
                        API.DoAction_NPC(0x2a, API.OFF_ACT_AttackNPC_route, {MECHANIC_OBJECTS.BolsterMinionId}, 50)
                    elseif #minions1 > 0 then
                        API.DoAction_NPC(0x2a, API.OFF_ACT_AttackNPC_route, {MECHANIC_OBJECTS.MinionIds[1]}, 50)
                    elseif #minions2 > 0 then
                        API.DoAction_NPC(0x2a, API.OFF_ACT_AttackNPC_route, {MECHANIC_OBJECTS.MinionIds[2]}, 50)
                    end

                    API.RandomSleep2(50, 30, 30)

                    -- Use dive if available, otherwise walk
                    ---@diagnostic disable-next-line
                    local targetTile = WPOINT.new(targetPosition.x, targetPosition.y, 0)

                    -- DEBUG: Show all minions and their distances to the target position
                    Utils.debugLog(string.format("=== MINION POSITIONING DEBUG ==="))
                    Utils.debugLog(string.format("Target position: (%d, %d)", targetPosition.x, targetPosition.y))
                    if bolstered then
                        local dist = math.sqrt((targetPosition.x - bolstered.Tile_XYZ.x)^2 + (targetPosition.y - bolstered.Tile_XYZ.y)^2)
                        Utils.debugLog(string.format("Bolstered minion at (%d, %d) - Distance: %.1f",
                            math.floor(bolstered.Tile_XYZ.x), math.floor(bolstered.Tile_XYZ.y), dist))
                    end
                    for i, minion in ipairs(minions1) do
                        local dist = math.sqrt((targetPosition.x - minion.Tile_XYZ.x)^2 + (targetPosition.y - minion.Tile_XYZ.y)^2)
                        Utils.debugLog(string.format("Minion1[%d] at (%d, %d) - Distance: %.1f",
                            i, math.floor(minion.Tile_XYZ.x), math.floor(minion.Tile_XYZ.y), dist))
                    end
                    for i, minion in ipairs(minions2) do
                        local dist = math.sqrt((targetPosition.x - minion.Tile_XYZ.x)^2 + (targetPosition.y - minion.Tile_XYZ.y)^2)
                        Utils.debugLog(string.format("Minion2[%d] at (%d, %d) - Distance: %.1f",
                            i, math.floor(minion.Tile_XYZ.x), math.floor(minion.Tile_XYZ.y), dist))
                    end
                    Utils.debugLog(string.format("=== END POSITIONING DEBUG ==="))

                    if API.GetABs_name1("Bladed Dive").cooldown_timer <= 1 then
                        Utils.debugLog("Using Bladed Dive to position")
                        API.DoAction_Dive_Tile(targetTile)
                        API.RandomSleep2(200, 30, 30)
                        API.DoAction_WalkerW(targetTile)
                    else
                        Utils.debugLog("Dive not available, walking to position")
                        API.DoAction_WalkerW(targetTile)
                    end

                    return true
                end,
                wait = 0,
                useTicks = true
            },

            {label = "Threads of Fate"},
            {label = "Threads of Fate", condition = function() return API.GetABs_name1("Threads of Fate").cooldown_timer <= 2 end},
            {
                label = "Wait until positioned correctly",
                type = "Custom",
                action = function()
                    -- Check if we're close to optimal minion position (same logic as 2500+)
                    local allMinions = {}

                    local bolstered = API.GetAllObjArray1({MECHANIC_OBJECTS.BolsterMinionId}, 60, {1})[1]

                    local minions1 = Utils.findAll(MECHANIC_OBJECTS.MinionIds[1], 1, 30)
                    local minions2 = Utils.findAll(MECHANIC_OBJECTS.MinionIds[2], 1, 30)

                    for _, minion in ipairs(minions1) do table.insert(allMinions, minion) end
                    for _, minion in ipairs(minions2) do table.insert(allMinions, minion) end

                    if #allMinions == 0 then
                        Utils.debugLog("Minions gone, proceeding")
                        return true -- Minions gone, proceed
                    end

                    -- Check if we're within 5 tiles of all minions
                    local playerCoords = API.PlayerCoord()
                    local withinRange = true

                    for _, minion in ipairs(allMinions) do
                        local inRange
                        if bolstered then
                            -- Check if minion is within +/- 5 tiles of bolstered minion
                            local bx, by = bolstered.Tile_XYZ.x, bolstered.Tile_XYZ.y
                                        local mx, my = minion.Tile_XYZ.x, minion.Tile_XYZ.y
                            inRange = (mx >= bx - 5 and mx <= bx + 5 and my >= by - 4 and my <= by + 5)
                        else
                            -- Check if minion is within +/- 5 tiles of player
                            local px, py = playerCoords.x, playerCoords.y
                            local mx, my = minion.Tile_XYZ.x, minion.Tile_XYZ.y
                            inRange = (mx >= px - 5 and mx <= px + 5 and my >= py - 5 and my <= py + 5)
                        end
                        if not inRange then
                            withinRange = false
                            break
                                        end
                                    end

                    -- Override withinRange if buff 30129 has 4 seconds or less remaining
                    if API.Bbar_ConvToSeconds(API.Buffbar_GetIDstatus(30129, false)) <= 4 then
                        withinRange = true
                        Utils.debugLog("[2500%%] Buff 30129 expiring soon - overriding position check to proceed")
                    end

                    if withinRange then
                        Utils.debugLog("[2500%%] Positioned correctly within range of all minions")
                        return true -- Good position, proceed
                    else
                        Utils.debugLog("[2500%%] Still positioning, not within range of all minions")

                        -- Debug print details about what's out of range
                        local playerCoords = API.PlayerCoord()
                        Utils.debugLog(string.format("[2500%%] Player position: (%.1f, %.1f)", playerCoords.x, playerCoords.y))

                        -- Check each minion's distance from bolstered position
                        if bolstered then
                            Utils.debugLog(string.format("[2500%%] Bolstered position: (%.1f, %.1f)", bolstered.Tile_XYZ.x, bolstered.Tile_XYZ.y))
                        end

                        for i, minion in ipairs(allMinions) do
                            local inRange
                            local rangeFrom
                            if bolstered then
                                local bx, by = bolstered.Tile_XYZ.x, bolstered.Tile_XYZ.y
                                local mx, my = minion.Tile_XYZ.x, minion.Tile_XYZ.y
                                inRange = (mx >= bx - 5.5 and mx <= bx + 5.5 and my >= by - 5.5 and my <= by + 5.5)
                                rangeFrom = string.format("bolstered at (%.1f, %.1f)", bx, by)
                            else
                                local px, py = playerCoords.x, playerCoords.y
                                local mx, my = minion.Tile_XYZ.x, minion.Tile_XYZ.y
                                inRange = (mx >= px - 5.5 and mx <= px + 5.5 and my >= py - 5.5 and my <= py + 5.5)
                                rangeFrom = string.format("player at (%.1f, %.1f)", px, py)
                            end
                            Utils.debugLog(string.format("[2500%%] Minion %d at (%.1f, %.1f) - %s within 5 tiles of %s",
                                i, minion.Tile_XYZ.x, minion.Tile_XYZ.y, inRange and "IN RANGE" or "OUT OF RANGE", rangeFrom))
                        end

                        return false -- Keep waiting
                    end
                end,
                wait = 0,
                useTicks = true
            },
            {label = "Volley of Souls", replacementLabel = "Soul Sap", condition = function() return RotationManager:getBuff(30123).remaining >= 3 end},
            {label = "Volley of Souls", replacementLabel = "Soul Sap", condition = function() return RotationManager:getBuff(30123).remaining >= 3 end},
            {label = "Volley of Souls", replacementLabel = "Basic<nbsp>Attack", condition = function() return RotationManager:getBuff(30123).remaining >= 3 end},
            {label = "Improvise", type = "Improvise", style = "Necromancy", spend = false}
        }
    },
}

-- Helper function to transfer rotation state with REMAINING cooldown
-- Simple same-tick protection fix:
-- Corrected transfer function that handles idle rotations properly:

-- Simple fix for massive delta values:

local function transferRotationState(fromRotation, toRotation)
    if fromRotation and toRotation and fromRotation.timer then
        Utils.debugLog("Transferring rotation state from " .. fromRotation.name .. " to " .. toRotation.name)
        
        -- Calculate time since last execution
        local currentTick = API.Get_tick()
        local currentTime = os.clock() * 1000
        local oldDelta = fromRotation.timer.useTicks and (currentTick - fromRotation.timer.lastTriggered) or (currentTime - fromRotation.timer.lastTime)
        
        Utils.debugLog(string.format("OLD rotation: lastTriggered=%d, cooldown=%d, delta=%d", 
            fromRotation.timer.lastTriggered, fromRotation.timer.cooldown, oldDelta))
        
        -- Simple fix: if delta is massive, assume default 3 tick wait
        local newCooldown
        if oldDelta > 10 then  -- Anything over 10 ticks is unrealistic for normal rotations
            newCooldown = 3  -- Default wait time
            Utils.debugLog("Massive delta detected - using default 3 tick wait")
        else
            -- Normal remaining time calculation
            newCooldown = math.max(1, fromRotation.timer.cooldown - oldDelta)
            Utils.debugLog(string.format("Normal delta - using remaining cooldown: %d", newCooldown))
        end
        
        -- Transfer timer state
        toRotation.timer.lastTriggered = currentTick
        toRotation.timer.lastTime = currentTime
        toRotation.timer.cooldown = newCooldown
        toRotation.timer.useTicks = fromRotation.timer.useTicks
        
        -- Transfer rotation state
        toRotation.trailing = fromRotation.trailing or false
        toRotation.improvising = fromRotation.improvising or false
        
        Utils.debugLog(string.format("NEW rotation: lastTriggered=%d, cooldown=%d, canTrigger=%s", 
            toRotation.timer.lastTriggered, toRotation.timer.cooldown, tostring(toRotation.timer:canTrigger())))
        
        Utils.debugLog("State transfer completed successfully")
    end
end
-- Helper function to detect current mechanic based on AG animation (trigger-based)
local function detectMechanic()
    local AG = Utils.find(28241, 1, 20)
    if not AG then 
        Utils.debugLog("[DETECT] No AG found")
        return "none" 
    end
    
    local currentTick = API.Get_tick()
    local currentAnim = AG.Anim
    
    -- ALWAYS log what animation we're seeing
    --Utils.debugLog(string.format("[DETECT] Tick %d: AG Anim=%d, CurrentMech=%s, LastMech=%s", 
    --    currentTick, currentAnim, Config.Variables.currentMechanic, Config.Variables.lastMechanic))
    
    -- Check if we're still in the cooldown period since last mechanic detection
    if Config.Variables.lastMechanicDetectionTick > 0 and 
        (currentTick - Config.Variables.lastMechanicDetectionTick) < 12 then
        --Utils.debugLog(string.format("[DETECT] In cooldown: %d ticks since last detection", 
            --currentTick - Config.Variables.lastMechanicDetectionTick))
        return Config.Variables.currentMechanic
    end
    
    -- Log what animation matches what mechanic
    local detectedMechanic = "none"
    
    if currentAnim == MECHANIC_ANIMATIONS.ArmsAnim then
        --Utils.debugLog(string.format("[DETECT] Animation %d matches ARMS", currentAnim))
        if Config.Variables.armsEndTick > 0 and (currentTick - Config.Variables.armsEndTick) < 12   then
            --Utils.debugLog(string.format("[DETECT] Arms still in cooldown: %d ticks since end", 
             --   currentTick - Config.Variables.armsEndTick))
            return Config.Variables.currentMechanic
        end
        detectedMechanic = "arms"
    elseif currentAnim == MECHANIC_ANIMATIONS.MinionsAnim then
        Utils.debugLog(string.format("[DETECT] Animation %d matches MINIONS", currentAnim))
        detectedMechanic = "minions"
    elseif currentAnim == MECHANIC_ANIMATIONS.PillarsAnim then
       -- Utils.debugLog(string.format("[DETECT] Animation %d matches PILLARS", currentAnim))
        detectedMechanic = "pillars"
    elseif currentAnim == MECHANIC_ANIMATIONS.FlurryAnims[1] or 
            currentAnim == MECHANIC_ANIMATIONS.FlurryAnims[2] or 
            currentAnim == MECHANIC_ANIMATIONS.FlurryAnims[3] or 
            currentAnim == MECHANIC_ANIMATIONS.FlurryAnims[4] then
       -- Utils.debugLog(string.format("[DETECT] Animation %d matches FLURRY", currentAnim))
        -- Prevent consecutive flurry mechanics (flurry -> minions -> flurry)
        if Config.Variables.lastMechanic == "flurry" then
            Utils.debugLog("[DETECT] Preventing consecutive flurry - last mechanic was already flurry")
            detectedMechanic = "none"  -- Ignore this flurry detection
        else
            detectedMechanic = "flurry"
        end
    elseif currentAnim == MECHANIC_ANIMATIONS.FrostCannonAnim then
       -- Utils.debugLog(string.format("[DETECT] Animation %d matches FROST CANNON", currentAnim))
        detectedMechanic = "frostcannon"
    else
      --  Utils.debugLog(string.format("[DETECT] Animation %d DOES NOT MATCH any mechanic", currentAnim))
    end
    
   -- Utils.debugLog(string.format("[DETECT] Result: detected=%s, returning=%s", 
   --     detectedMechanic, detectedMechanic ~= "none" and detectedMechanic or Config.Variables.currentMechanic))
    
    if detectedMechanic ~= "none" then
        return detectedMechanic
    end
    
    return Config.Variables.currentMechanic
end

-- Helper function to detect if current mechanic has ended
local function isMechanicEnded(mechanic)
    if mechanic == "none" then return true end
    
    if mechanic == "arms" then
        -- Only check for arm end if we're actually in arms phase
        if Config.Variables.currentMechanic == "arms" then
            -- Check for arm objects with wider search range
            local arms = Utils.findAll(MECHANIC_OBJECTS.ArmId, 1, 30)
            
            -- If arms haven't been detected yet, we can't end
            if not Config.Variables.armsDetected then
                if #arms > 0 then
                    Config.Variables.armsDetected = true
                    Utils.debugLog("Arms detected and flagged")
                end
                        return false
                    end
                    
            -- Only check for end condition if arms were previously detected
            if Config.Variables.armsDetected then
                local armsGone = #arms == 0
                if armsGone then
                    Utils.debugLog("Arms mechanic ending - no arms found")
                end
                return armsGone
            end
        end
        return false
    elseif mechanic == "minions" then
        -- Only check for minion end if we're actually in minions phase
        if Config.Variables.currentMechanic == "minions" then
            -- Check for all minion types using multiple methods
            local minions1 = Utils.findAll(MECHANIC_OBJECTS.MinionIds[1], 1, 30) -- First minion type
            local minions2 = Utils.findAll(MECHANIC_OBJECTS.MinionIds[2], 1, 30) -- Second minion type
            local bolster = Utils.findAll(MECHANIC_OBJECTS.BolsterMinionId, 1, 30)
            
            -- Also try with API.GetAllObjArray1 as backup
            local bolsterBackup = API.GetAllObjArray1({MECHANIC_OBJECTS.BolsterMinionId}, 60, {1})
            local minions1Backup = API.GetAllObjArray1({MECHANIC_OBJECTS.MinionIds[1]}, 60, {1})
            local minions2Backup = API.GetAllObjArray1({MECHANIC_OBJECTS.MinionIds[2]}, 60, {1})
            
            -- RESTORED PRINTS
            --Utils.debugLog(string.format("Minions check: minions1=%d(%d), minions2=%d(%d), bolster=%d(%d), detected=%s", 
                --#minions1, #minions1Backup, #minions2, #minions2Backup, #bolster, #bolsterBackup, tostring(Config.Variables.minionsDetected)))
            
            -- If minions haven't been detected yet, we can't end
            if not Config.Variables.minionsDetected then
                if #minions1 > 0 or #minions2 > 0 or #bolster > 0 or #bolsterBackup > 0 or #minions1Backup > 0 or #minions2Backup > 0 then
                    Config.Variables.minionsDetected = true
                    Utils.debugLog("Minions detected and flagged")
                end
                return false
            end
            
            -- FIXED: Check for end condition immediately when no minions found
            local allGone = (#minions1 == 0 and #minions2 == 0 and #bolster == 0) and 
                           (#bolsterBackup == 0 and #minions1Backup == 0 and #minions2Backup == 0)
            
            if allGone then
                Utils.debugLog("All minions gone - mechanic should end")
                -- Set the end tick for minions mechanic
                if not Config.Variables.mechanicEndTicks then
                    Config.Variables.mechanicEndTicks = {
                        arms = 0,
                        minions = 0,
                        pillars = 0,
                        flurry = 0,
                        frostcannon = 0
                    }
                end
                Config.Variables.mechanicEndTicks.minions = API.Get_tick()
                Utils.debugLog(string.format("Set minions end tick: %d", Config.Variables.mechanicEndTicks.minions))
                return true
            end
            
            -- Also add a timeout mechanism (60 seconds = 100 ticks) in case minions get stuck
            local currentTick = API.Get_tick()
            local mechanicDuration = currentTick - Config.Variables.mechanicStartTick
            local timeout = mechanicDuration > 100 -- 60 seconds timeout
            
            if timeout then
                Utils.debugLog("Minions mechanic timed out after 60 seconds - forcing end")
                return true
            end
            
            --Utils.debugLog("Some minions still alive - mechanic continues")
            return false
        end
        return false
    elseif mechanic == "pillars" then
        -- Only check for pillar end if we're actually in pillars phase
        if Config.Variables.currentMechanic == "pillars" then
            -- Check for all pillar objects
            local pillars = Utils.findAll(MECHANIC_OBJECTS.BeamId, 1, 30)
            
            -- If pillars haven't been detected yet, we can't end
            if not Config.Variables.pillarsDetected then
                if #pillars > 0 then
                    Config.Variables.pillarsDetected = true
                    Utils.debugLog("Pillars detected and flagged")
                end
                return false
            end
            
            -- Only check for end condition if pillars were previously detected
            if Config.Variables.pillarsDetected then
                local pillarsGone = #pillars == 0
                -- Also add timeout (45 seconds for pillars)
                local currentTick = API.Get_tick()
                local mechanicDuration = currentTick - Config.Variables.mechanicStartTick
                local timeout = mechanicDuration > 100 -- 60 seconds timeout (reduced from 2700)
                
                -- Add some debugging every 10 ticks to see what's happening
                if currentTick % 10 == 0 then
                    Utils.debugLog(string.format("Pillars check: beams=%d, duration=%d ticks, timeout=%s", 
                        #pillars, mechanicDuration, tostring(timeout)))
                end
                
                if pillarsGone then
                    Utils.debugLog("Pillars mechanic ending - no beams found")
                    return true
                elseif timeout then
                    Utils.debugLog("Pillars mechanic timed out after 60 seconds - forcing end")
                    return true
                else
                    return false
                end
            end
        end
        return false
    elseif mechanic == "flurry" then
        -- Flurry should only end when another mechanic starts, not on a timer
        -- The mechanic detection system will handle switching when AG starts a new mechanic
        return false  -- Never auto-end flurry, only end when new mechanic detected
    elseif mechanic == "frostcannon" then
        -- Frost cannon ends after a certain duration
        local currentTick = API.Get_tick()
        local mechanicDuration = currentTick - Config.Variables.mechanicStartTick
        return mechanicDuration > 15 -- Adjust duration as needed
    end
    
    return false
end

-- Helper function to get appropriate rotation for mechanic
local function getRotationForMechanic(mechanic)
    if mechanic == "arms" then
        return Config.Instances.ArmsRotation
    elseif mechanic == "minions" then
        return Config.Instances.MinionsRotation
    elseif mechanic == "pillars" then
        return Config.Instances.PillarsRotation
    elseif mechanic == "flurry" then
        return Config.Instances.FlurryRotation
    elseif mechanic == "frostcannon" then
        return Config.Instances.FrostCannonRotation
    else
        return Config.Instances.fightRotation
    end
end

Config.Instances.fightRotation = RotationManager.new(Config.RotationManager.fightRotation)
Config.Instances.InitialRotation = RotationManager.new(Config.RotationManager.InitialRotation)

-- Create rotation instances for hardmode
Config.Instances.ArmsRotation = RotationManager.new(Config.RotationManager.ArmsRotation)
Config.Instances.MinionsRotation = RotationManager.new(Config.RotationManager.MinionsRotation)

Config.Instances.PillarsRotation = RotationManager.new(Config.RotationManager.PillarsRotation)
Config.Instances.FlurryRotation = RotationManager.new(Config.RotationManager.FlurryRotation)
Config.Instances.FrostCannonRotation = RotationManager.new(Config.RotationManager.FrostCannonRotation)
--#endregion

Config.Buffs = {
    {
        buffName = "Ruination",
        buffId = 30769,
        canApply = function(self) return (self.state.prayer.current > 100) end,
        execute = function() return Utils.useAbility("Ruination") end,
        toggle = true
    },
    {
        buffName = "Animate Dead",
        buffId = 14764,
        canApply = function(self) return (API.GetABs_name1("Animate Dead").enabled) and not Inventory:InvItemFound(49417) end,
        execute = function() return Utils.useAbility("Animate Dead") end,
    },
    {
        buffName = "Protect Item",
        buffId = 26046,
        canApply = function(self) return (self.state.prayer.current > 100) end,
        execute = function() return Utils.useAbility("Protect Item") end,
        toggle = true
    },
    {
        buffName  = "Scripture of Jas",
        buffId = 51814,
        canApply = function(self) return Equipment:GetPocket() and Equipment:GetPocket().id == 51814 end,
        execute = function()
            return Utils.useAbility("Scripture of Jas")
        end,
        toggle = true
    },
    {
        buffName = "Kwuarm incense sticks",
        buffId = 47709,
        execute = function()
            local name = "Kwuarm incense sticks"
            local buff = API.Buffbar_GetIDstatus(47709, false)

            if buff.found and (Inventory:GetItemAmount(name) > 0) then
                -- Extract potency level from buff text (e.g., "5m (4)" -> potency = 4)
                local potency = tonumber(string.match(buff.text or "", "%((%d+)%)")) or 0

                if potency < 4 and (Inventory:GetItemAmount(name) >= 6) then
                    -- Potency less than 4 and have 6+ sticks: increase potency
                    return API.DoAction_Inventory3(name, 0, 2, API.OFF_ACT_GeneralInterface_route)
                else
                    -- Potency maxed or not enough sticks: extend duration
                    return API.DoAction_Inventory3(name, 0, 1, API.OFF_ACT_GeneralInterface_route)
                end
            else
                -- No buff active: light new incense
                return API.DoAction_Inventory3(name, 0, 2, API.OFF_ACT_GeneralInterface_route)
            end
        end,
        refreshAt = 660
    },
    {
        buffName = "Powder of penance",
        buffId = 52806,
        canApply = function(state) return (Inventory:GetItemAmount("Powder of penance") > 0) and not state:getBuff(52806).found end,
        execute = function() return API.DoAction_Inventory3("Powder of penance", 0, 1, API.OFF_ACT_GeneralInterface_route) end,
        refreshAt = 660
    },
    {
        buffName = "Elder overload",
        buffId = 49039,
        canApply = function(state) return (Inventory:GetItemAmount("Elder overload") > 0) and (API.Get_tick() - state.timestamp.buff > 1) end,
        execute = function()
            return API.DoAction_Inventory3("Elder overload", 0, 1, API.OFF_ACT_GeneralInterface_route)
        end,
        refreshAt = math.random(5, 20)
    },
    {
        buffName = "Weapon poison+++",
        buffId = 30095,
        canApply = function(state) return (Inventory:GetItemAmount("Weapon poison+++") > 0) and (API.Get_tick() - state.timestamp.buff > 1) end,
        execute = function()
            return API.DoAction_Inventory3("Weapon poison+++", 0, 1, API.OFF_ACT_GeneralInterface_route)
        end,
        refreshAt = math.random(5, 20)
    },
    -- placeholder for summoning manager
    {
        buffName = "Binding contract (ripper demon)",
        buffId = 26095, -- summoning buff lol
        canApply = function(state) return not state:getBuff(26095).found end,
        execute = function() return API.DoAction_Inventory3("Binding contract (ripper demon)", 0, 1, API.OFF_ACT_GeneralInterface_route) end,
        refreshAt = math.random(5, 20)
    },
   -- {
   --     buffName = "Binding contract (ripper demon)",
    --    buffId = 26095, -- summoning buff lol
    --    canApply = function(state) return not state:getBuff(26095).found end,
    --    execute = function() return API.DoAction_Inventory3("Binding contract (ripper demon)", 0, 1, API.OFF_ACT_GeneralInterface_route) end,
    --    refreshAt = math.random(5, 20)
  -- }
}

--#region prayer flicker init
Config.prayerFlicker = {
    prayers = {
        PrayerFlicker.PRAYERS.SOUL_SPLIT,
        PrayerFlicker.PRAYERS.DEFLECT_MELEE,
        PrayerFlicker.PRAYERS.DEFLECT_RANGED,
        PrayerFlicker.PRAYERS.DEFLECT_MAGIC
    },
    defaultPrayer = PrayerFlicker.PRAYERS.SOUL_SPLIT,
    npcs = {
        {
            id = 28241, -- AG
            animations = {
                {
                    animId = 34272,                                    -- Mage Auto
                    prayer = PrayerFlicker.PRAYERS.DEFLECT_MAGIC, -- deflect magic
                    overrideAnim = 34279,
                    priority = 5,
                    activationDelay = 2,
                    duration = 3
                },
                {
                    animId = 34273,                                    -- Mage Auto
                    prayer = PrayerFlicker.PRAYERS.DEFLECT_MAGIC, -- deflect magic
                    overrideAnim = 34279,
                    priority = 7,
                    activationDelay = 2,
                    duration = 3
                },
                {
                    animId = 34274,                                    -- Ranged Auto
                    prayer = PrayerFlicker.PRAYERS.DEFLECT_RANGED, -- deflect ranged
                    overrideAnim = 34279,
                    priority = 4,
                    activationDelay = 2,
                    duration = 3
                },
                {
                    animId = 34275,                                    -- Ranged Auto
                    prayer = PrayerFlicker.PRAYERS.DEFLECT_RANGED, -- deflect ranged
                    overrideAnim = 34279,
                    priority = 6,
                    activationDelay = 2,
                    duration = 3
                },
                {
                    animId = 34276,                                    -- Melee Auto
                    prayer = PrayerFlicker.PRAYERS.DEFLECT_MELEE, -- deflect melee
                    overrideAnim = 34279,
                    priority = 3,
                    activationDelay = 2,
                    duration = 4
                },
                {
                    animId = 34277,                                    -- Melee Auto
                    prayer = PrayerFlicker.PRAYERS.DEFLECT_MELEE, -- deflect melee
                    overrideAnim = 34279,
                    priority = 2,
                    activationDelay = 2,
                    duration = 4
                },
                {
                    animId = 34278,                                    -- Frost Cannon
                    prayer = PrayerFlicker.PRAYERS.DEFLECT_MAGIC, -- deflect magic
                    --bypassCondition = function() return Utils.isMitigaterActive() end,
                    priority = 88,
                    activationDelay = 4,
                    duration = 10
                },
                {
                    -- Arms mechanic - check for arm objects instead of animation
                    condition = function() 
                        -- Conditional arms mechanic checks
                        Utils.debugLog("Checking conditional arms mechanic", "debug")
                        
                        -- Check if ID 28244 exists
                        local armMechanicExists = Utils.find(28244, 1, 30) ~= nil
                        
                        return armMechanicExists
                    end,
                    prayer = PrayerFlicker.PRAYERS.DEFLECT_MAGIC, -- deflect magic
                    priority = 9999,
                    activationDelay = 14,  -- 16 tick delay as requested
                    duration = 5
                },
                --{
                --    condition = function() return Utils.isMitigaterActive() end,
               --     prayer = PrayerFlicker.PRAYERS.SOUL_SPLIT,
                --    priority = 999, -- Highest priority
               --     duration = 100 -- High duration - will last until mitigater not active due to condition
                --}
            }
        }
    }
}

Config.Instances.prayerFlicker = PrayerFlicker.new(Config.prayerFlicker)

-- Enable prayer flicker debug
--#endregion

--#region timers init
Config.Timer = {
    flexTimer = Timer.new(
        {
            name = "Flex timer",
            cooldown = 600,
            useTicks = false,
            condition = function() return true end,
            action = function() return true end
        }
    ),
    autoPrism = Timer.new(
        {
        name = "Auto Prism of Restoration",
        cooldown = 1,
        useTicks = true,
        condition = function() return Utils.getSpellbook() == "Ancient" end,
        action = function() return Utils.useAbility("Prism of Restoration") end
        }
    ),
    loadLastPreset = Timer.new(
        {
            name = "Load last preset",
            cooldown = 3,
            condition = function(state) return Utils.playerIsIdle(state) end,
            action = function(state)
                print(Utils.hasAllItems(Config.UserInput.presetChecks))
                if not Utils.hasAllItems(Config.UserInput.presetChecks) then
                    
                    if Config.Variables.bankAttempts <= 3 then
                        if API.DoAction_Object1(0x33,API.OFF_ACT_GeneralObject_route3,{ 114750 },50) then
                            Config.Variables.bankAttempts = Config.Variables.bankAttempts + 1
                            return true
                        end
                    else
                        Utils.terminate(
                            "Attempts at loading appropriate preset failed.",
                            "Make sure your last loaded preset has all items."
                        )
                    end
                end
                return false
            end
        }
    ),
    standByBankChest = Timer.new(
        {
            name = "Bankstand",
            cooldown = 3,
            condition = function(state) return Utils.playerIsIdle(state) end,
            action = function(state)
                local bankChest = Utils.find(114750, 12, 20)
                if bankChest and not Utils.atLocation(bankChest.Tile_XYZ.x, bankChest.Tile_XYZ.y -1, 1) then
                    ---@diagnostic disable-next-line
                    return API.DoAction_WalkerW(WPOINT.new(bankChest.Tile_XYZ.x, bankChest.Tile_XYZ.y - 1, 0))
                end
                return false
            end
        }
    ),
    prayAtAltar = Timer.new(
        {
            name = "Pray at Altar of War",
            cooldown = 6,
            condition = function(state) return Utils.playerIsIdle(state) end,
            action = function(state) return API.DoAction_Object1(0x3d,API.OFF_ACT_GeneralObject_route0, { 114748 }, 50) end
        }
    ),
    bonfireBoost = Timer.new(
        {
            name = "Bonfire Boost",
            cooldown = 6,
            condition = function(state) return Utils.playerIsIdle(state) end,
            action = function(state) return API.DoAction_Object1(0x29,API.OFF_ACT_GeneralObject_route0, { 131888 }, 50) end
        }
    ),
    summonConjures = Timer.new(
        {
            name = "Summon conjures",
            cooldown = 300,         -- 300 ms
            useTicks = false,       -- uses real time instead of game ticks
            condition = function() return true end,
            action = function()
                --checks if conjures are summoned or animation matches summoning animation
                local zombieGhostSkellyCheck = API.Buffbar_GetIDstatus(34177).found and 
                                             API.Buffbar_GetIDstatus(34178).found and 
                                             API.Buffbar_GetIDstatus(34179).found
                
                local conjuresExpiring = (API.Bbar_ConvToSeconds(API.Buffbar_GetIDstatus(34177)) < 59) or 
                                       (API.Bbar_ConvToSeconds(API.Buffbar_GetIDstatus(34178)) < 59) or 
                                       (API.Bbar_ConvToSeconds(API.Buffbar_GetIDstatus(34179)) < 59)
                
                if (API.ReadPlayerAnim() == 35502) or (zombieGhostSkellyCheck and not conjuresExpiring) then
                    Config.Variables.conjuresSummoned = true
                end

                -- reset flexTimer in case it was used elsewhere
                -- override flexTimer configuration
                if not ((Config.Timer.flexTimer.name == "Summoning conjures") or 
                       (Config.Timer.flexTimer.name == "Equipping lantern") or 
                       (Config.Timer.flexTimer.name == "Unequipping lantern")) then
                    Config.Timer.flexTimer.cooldown = 1
                    Config.Timer.flexTimer.useTicks = true
                    Config.Timer.flexTimer:reset()
                end

                -- summons are not healthy
                if conjuresExpiring and (API.Buffbar_GetIDstatus(34178).found or API.Buffbar_GetIDstatus(34179).found) then
                    ---@diagnostic disable-next-line
                    Config.Timer.flexTimer.action = function() 
                        return Inventory:Equip(36619) -- Equip excalibur instead of unequipping lantern
                    end
                    Config.Timer.flexTimer.name = "Unequipping lantern"
                    Config.Timer.flexTimer.cooldown = 1
                    Config.Timer.flexTimer.useTicks = true
                    Config.Timer.flexTimer:execute()
                end

                local soulboundLanternInInventory = Inventory:InvItemFound(55485) -- Check specifically for Soulbound lantern

                --equip lantern
                if soulboundLanternInInventory then
                    Config.Timer.flexTimer.action = function() 
                        return Inventory:Equip(55485) -- Equip soulbound lantern specifically
                    end
                    Config.Timer.flexTimer.name = "Equipping lantern"
                    Config.Timer.flexTimer:execute()
                    return true -- exits out of sequence and activates summonConjure's timer
                end

                if Config.Timer.flexTimer:canTrigger() then
                    if Config.Variables.conjureAttempts <= 5 then
                        --overrides flexTimer's name, cooldowns and actions
                        Config.Timer.flexTimer.action = function() return Utils.useAbility("Conjure Undead Army") end
                        Config.Timer.flexTimer.name = "Summoning conjures"
                        if Config.Timer.flexTimer:execute() then
                            Config.Timer.flexTimer.cooldown = 600
                            Config.Variables.conjureAttempts = Config.Variables.conjureAttempts + 1
                            return true
                        end
                    else
                        Utils.terminate(
                            "Too many summoning conjures attempts failed.",
                            "Make sure you have enough runes in your nexus."
                        )
                    end
                end
                return false
            end
        }
    ),
    -- TODO: fix implementation to be cleaner when NOT going to bank -> altar
    navigate = Timer.new(
        {
            name = "Navigate",
            cooldown = 1,
            useTicks = true,
            condition = function(state) return true end,
            action = function(state)
                --[[
                    navigation cases:
                    1. at altar: best case scenario
                        - click on tile in front of bank chest
                        - flexTimer: reset
                    2. at bank chest
                        - check direction facing
                        - if surge direction
                            - yes: has dive/bd?
                                - yes: need adren?
                                    - yes: bd surge to appropriate adren crystal tile
                                    - no: bd surge to appropriate portal tile
                                - no: surge & flexTimer:reset()
                            - no: goto continue
                        - yes: surge & flexTimer:reset()
                        - no: goto continue
                    3. at stairs:
                        - facing portals?
                            - yes:    1. surge
                                    2. flexTimer:reset()
                                    3. return
                            - no: goto continue
                    ::continue::
                    4. else
                        - need adren?
                            - yes: click on adren crystal
                            - no: click on portal
                ]]

                ---@diagnostic disable-next-line
                local coords = (Config.Variables.adrenCrystalSide == "West" and WPOINT.new(3290, 10148,0)) or WPOINT.new(3298,10148, 0)
                --flexTimer.useTicks = true

                if Utils.atLocation(3304, 10127, 3) then -- at altar
                    Config.Timer.flexTimer.name = "Moving next to bank"
                    Config.Timer.flexTimer.cooldown = 300
                    Config.Timer.flexTimer.useTicks = false
                    -- click on tile infornt of bank chest
                    ---@diagnostic disable-next-line
                    Config.Timer.flexTimer.action = function(state) return API.DoAction_WalkerW(WPOINT.new(3299, 10131, 0)) end
                elseif Utils.atLocation(3299, 10132, 3) and not Utils.atLocation(3294, 10134, 2) and state.state.orientation >= 300 then -- at bank chest and not at stairs and facing nw
                    Config.Timer.flexTimer.cooldown = 1
                    Config.Timer.flexTimer.name = "Dive & Surge to adrenaline crystals"
                    Config.Timer.flexTimer.action = function(state)
                        -- surge bd to appropriate adren crystal
                        if Utils.useAbility("Surge") then
                            API.RandomSleep2(50, 30, 30)
                            if API.DoAction_Dive_Tile(coords) then
                                return true
                            end
                        end
                        return false
                    end
                    Config.Timer.flexTimer:reset()
                elseif Utils.atLocation(3294, 10134, 2) and state.state.orientation == 0 then -- at stairs facing north
                    Config.Timer.flexTimer.name = "Dive & Surge at stairs"
                    -- uses surge when at stairs
                    Config.Timer.flexTimer.action = function(state)
                        if Utils.useAbility("Surge") then
                            API.RandomSleep2(50, 30, 30)
                            if API.DoAction_Dive_Tile(coords) then
                                return true
                            end
                        end
                        return false
                    end
                elseif Utils.playerIsIdle(state) then
                    Config.Timer.flexTimer.name = "Walking around portals and crystals"
                    ---@diagnostic disable-next-line
                    Config.Timer.flexTimer.action = function(state) return API.DoAction_WalkerW(WPOINT.new(3293 + math.random(-2, 2), 10148 + math.random(-2, 2), 0)) end
                end

                local success = Config.Timer.flexTimer:execute(state)
                Config.Timer.flexTimer.cooldown = 1
                Config.Timer.flexTimer.action = function() end
                if Config.Timer.flexTimer.name == "Surging at stairs" then Config.Timer.flexTimer:reset() end
                if Config.Timer.flexTimer.name == "Moving next to bank" then Config.Timer.flexTimer:reset() end

                return success
            end
        }
    ),
    channelAdren = Timer.new(
        {
            name = "Channel Adrenaline",
            cooldown = 3,
            condition = function(state) return Utils.playerIsIdle(state) end,
            action = function(state)
                ---@diagnostic disable-next-line
                local coords = (Config.Variables.adrenCrystalSide == "West" and WPOINT.new(3290, 10148,0)) or WPOINT.new(3298,10148, 0)
                return API.DoAction_Object_r(0x29, API.OFF_ACT_GeneralObject_route0, {114749}, 40, coords, 3)
            end
        }
    ),
    useDarkness = Timer.new(
        {
            name = "Use Darkness",
            cooldown = 4,
            condition = function() return true end,
            action = function(state)
                if Utils.useAbility("Darkness") then
                    return true
                end
                return false
            end
        }
    ),
    goThroughPortal = Timer.new(
        {
            name = "Go through AG portal",
            cooldown = 4,
            condition = function() return true end,
            action = function()
                if API.DoAction_Object1(0x39,API.OFF_ACT_GeneralObject_route0,{ 121370 },50) then
                    Config.Variables.bankAttempts = 0
                    return true
                end
                return false
            end
        }
    ),
    handleInstance = Timer.new(
        {
            name = "Handle AG instance",
            cooldown = 1,
            condition = function() return true end,
            action = function(state)
                Config.Timer.flexTimer.useTicks = true
                Config.Timer.flexTimer.cooldown = 1
                if API.VB_FindPSettinOrder(2874).state == 425992 or API.VB_FindPSettinOrder(2874).state == 13 then -- enrage select is open
                    Config.Timer.flexTimer.name = "Selecting enrage"
                    ---@diagnostic disable-next-line
                    --Config.Timer.flexTimer.action = function() return API.DoAction_Interface(0xffffffff, 0xffffffff, 0, 720, 38, -1, API.OFF_ACT_GeneralInterface_Choose_option) end
                    Config.Timer.flexTimer.action = function() return API.DoAction_Interface(0xffffffff, 0xffffffff, 0, 720, 20, -1, API.OFF_ACT_GeneralInterface_Choose_option) end
                elseif API.VB_FindPSettinOrder(2874).state == 589832 or API.VB_FindPSettinOrder(2874).state == 18 then -- boss interface is open
                    Config.Timer.flexTimer.name = "Starting private instance"
                    Config.Timer.flexTimer.action = function()
                        ---@diagnostic disable-next-line
                        if API.DoAction_Interface(0x2e, 0xffffffff, 1, 1591, 60, -1, API.OFF_ACT_GeneralInterface_route) or API.DoAction_Interface(0x2e, 0xffffffff, 1, 1673, 60, -1, API.OFF_ACT_GeneralInterface_route) then
                            return true
                        end
                    end
                else
                    Config.Timer.flexTimer.name = "Entering through aqueduct portal"
                    Config.Timer.flexTimer.action = function() 
                        if not Config.Variables.clickedAqueductPortal then
                            local clicked = API.DoAction_Object1(0x39,API.OFF_ACT_GeneralObject_route0,{ 121338 },50)
                            if clicked then
                                Config.Variables.clickedAqueductPortal = true
                            end
                            return clicked
                        end
                        return false
                    end
                end

                local success = Config.Timer.flexTimer:execute(state)
                return success
            end
        }
    ),
    getInPosition = Timer.new(
        {
            name = "Get in position (start spot)",
            cooldown = 2,
            condition = function(state) return not state.state.moving end,
            action = function(state)
                ---@diagnostic disable-next-line
                return API.DoAction_WalkerW(WPOINT.new(Config.Variables.startspot.x, Config.Variables.startspot.y, 0))
            end
        }
    ),
    collectDeath = Timer.new(
        {
            name = "Log kill details",
            cooldown = 10000,   -- Reduced to 1 second
            useTicks = false,
            condition = function() return true end,
            action = function()
                local chatEvents = API.GatherEvents_chat_check()
                
                local killTime = "UNKNOWN"
                for i, chat in ipairs(chatEvents) do
                    
                    -- Try multiple patterns
                    if string.find(chat.text, "Completion Time") then
                        killTime = chat.text:gsub("<col=2DBA14>Completion Time:</col> ", "")
                        break
                    elseif string.find(chat.text, "completion time") then -- lowercase
                        Utils.debugLog("FOUND completion time (lowercase)!")
                        killTime = chat.text
                        break
                    elseif string.find(chat.text, "time") then -- any time mention
                        Utils.debugLog("FOUND message with 'time': " .. chat.text)
                    end
                end
                
                Config.Variables.killCount = Config.Variables.killCount + 1
                Config.TrackedKills[Config.Variables.killCount] = {
                    runtime = API.ScriptRuntimeString(),
                    fightDuration = killTime
                }
                
                Utils.debugLog("Logged kill #" .. Config.Variables.killCount .. " with time: " .. killTime)
                Utils.debugLog("=== END COLLECT DEATH DEBUG ===")
                return true
            end
        }
    ),
    checkChestForUnique = Timer.new(
        {
            name = "Check chest for unique items",
            cooldown = 1,
            condition = function() 
                -- Check if container 906 is actually available
                local containerExists = pcall(function() 
                    return API.Container_Get_s(906, Config.Data.uniques[1]) ~= nil 
                end)
                if not containerExists then
                    Utils.debugLog("Container 906 not available yet")
                    return false
                end
                return true
            end,
            action = function()
                Utils.debugLog("Checking chest container 906 for unique items...")
                local container = API.Container_Get_all(906)
                for _, uniqueId in ipairs(Config.Data.uniques) do
                    if API.Container_Get_s(906, uniqueId) then
                        for _, item in pairs(container) do
                            print(item.item_id)
                            if item.item_id ~= -1 and item.item_id == uniqueId then
                        Utils.debugLog("Found unique item " .. uniqueId .. " in chest!")
                        Config.Variables.hasUniqueInChest = true
                        return true
                            end
                        end
                        
                    end
                end
                Utils.debugLog("No unique items found in chest")
                Config.Variables.hasUniqueInChest = false
                return true
            end
        }
    ),
    claimLoot = Timer.new(
        {
            name = "Claim loot from chest",
            cooldown = 1,
            condition = function() return Config.Variables.hasUniqueInChest end,
            action = function()
                -- Get chest value before claiming
                local chestValue = Utils.getLootValue()
                if chestValue and chestValue > 0 then
                    Config.Variables.totalSeenInChest = chestValue
                    Config.Variables.totalClaimed = Config.Variables.totalClaimed + chestValue
                    Utils.debugLog("Claiming chest value: " .. tostring(chestValue))
                end
                local success = API.DoAction_Interface(0x24,0xffffffff,1,863,114,-1,API.OFF_ACT_GeneralInterface_route)
                if success and API.VB_FindPSettinOrder(2874).state == 12 then
                    Config.Variables.chestLooted = true
                end
                return success
            end
        }
    ),
    continueChallenge = Timer.new(
        {
            name = "Continue challenge", 
            cooldown = 1,
            condition = function() return not Config.Variables.hasUniqueInChest end,
            action = function()
                -- Get chest value before continuing
                local chestValue = Utils.getLootValue()
                if chestValue and chestValue > 0 then
                    Config.Variables.totalSeenInChest = chestValue + Config.Variables.totalClaimed
                    Utils.debugLog("Continuing with chest value: " .. tostring(chestValue))
                end
                API.RandomSleep2(1200, 600, 600)
                local success = API.DoAction_Interface(0x24,0xffffffff,1,863,105,-1,API.OFF_ACT_GeneralInterface_route)
                API.RandomSleep2(800, 200, 200)
                if API.VB_FindPSettinOrder(2874).state == 12 then
                   
                    Config.Variables.everUsedContinueChallenge = true
                    Config.Variables.chestLooted = true
                    Utils.debugLog("Continue challenge used - setting everUsedContinueChallenge flag")
                end
                return success
            end
        }
    ),
    waitForLoot = Timer.new(
        {
            name = "Waiting for loot...",
            cooldown = 7,
            condition = function() return true end,
            action = function() 
                Config.Variables.bossDead = true 
                API.RandomSleep2(3200, 600, 600)
                return true 
            end
        }
    ),
    uniqueDropped = Timer.new(
        {
            name = "Unique dropped: sending discord message",
            cooldown = 20,
            condition = function() return #API.GetAllObjArray1(Config.Data.uniques, 30, {3}) > 0 end,
            action = function()
                ---@type AllObject[]
                local uniqueDrops, success = API.GetAllObjArray1(Config.Data.uniques, 30, {3}), false

                if uniqueDrops and Config.UserInput.discordNotifications then
                    Config.Timer.collectDeath:execute()
                    -- double drops are 1/40k-ish
                    for _, drop in pairs(uniqueDrops) do
                        local killData = Config.TrackedKills[Config.Variables.killCount]
                        local dropData = Config.Data.uniqueDropData[drop.Id]
                        table.insert(Config.Data.lootedUniques, ({"["..Config.Variables.killCount.."] "..dropData.name, killData.runtime}))
                        Utils.sendDiscordWebhook((Config.UserInput.mention and "^<@"..Config.UserInput.userId.."^>") or "", Config.UserInput.webhookUrl, {
                            embeds = {
                                {
                                    title = string.format("Congratulations! You found %s%s", dropData.prefix or (dropData.name ~= "Miso's collar") and "a " or "", dropData.name),
                                    description = dropData.message or ("You've managed to strip Ice Telos of a Cold **"..dropData.name.."**!"),
                                    color = 10181046,
                                    author = {
                                        name = "Jared's Arch-Glacor",
                                        icon_url = "https://runescape.wiki/images/Arch-Glacor.png?ac3e5"
                                    },
                                    thumbnail = {url = dropData.thumbnail},
                                    fields = {
                                        {name = "Kill Number", value = tostring(Config.Variables.killCount), inline = true},
                                        {name = "Fight Duration", value = killData.fightDuration, inline = true},
                                        {name = "Runtime", value = killData.runtime, inline = true},
                                    }
                                }
                            }
                        })
                        API.RandomSleep2(50, 40, 40)
                    end
                end

            return success
        end
        }
    ),
    teleportToWars = Timer.new(
        {
            name = "War's Retreat Teleport",
            cooldown = 10,
            condition = function(state) return Utils.playerIsIdle(state) end,
            action = function(state) return Utils.useAbility("War's Retreat Teleport") end
        }
    ),
    equipTFN = Timer.new(
        {
            name = "Equip TFN gear",
            cooldown = 600, -- 600ms between pieces
            useTicks = false,
            condition = function(state)
                -- Check if we need TFN gear based on conditions
                local needTFN = (
                    Config.Variables.currentMechanic == "pillars" or
                    Config.Variables.currentMechanic == "arms" or
                    state:getBuff(21665).found or  -- Devotion
                    state:getBuff(14228).found or  -- Barricad
                    Config.Variables.needTFNForConjures -- Flag for when about to summon conjures
                )
                return needTFN and not Config.Variables.inTFNGear
            end,
            action = function()
                -- Equip each piece of TFN gear
                for _, id in pairs(GEAR_IDS.TFN) do
                    API.DoAction_Inventory1(id, 0, 2, API.OFF_ACT_GeneralInterface_route)
                    API.RandomSleep2(30, 30, 30)
                end
                Config.Variables.inTFNGear = true
                return true
            end
        }
    ),
    equipTank = Timer.new(
        {
            name = "Equip Tank gear",
            cooldown = 600, -- 600ms between pieces
            useTicks = false,
            condition = function(state)
                -- Check if we should go back to tank gear
                local needTank = not (
                    Config.Variables.currentMechanic == "pillars" or
                    Config.Variables.currentMechanic == "arms" or
                    state:getBuff(21665).found or  -- Devotion
                    state:getBuff(14228).found or  -- Barricade
                    Config.Variables.needTFNForConjures -- Flag for when about to summon conjures
                )
                return needTank and Config.Variables.inTFNGear
            end,
            action = function()
                -- Equip each piece of tank gear
                for _, id in pairs(GEAR_IDS.TANK) do
                    API.DoAction_Inventory1(id, 0, 2, API.OFF_ACT_GeneralInterface_route)
                    API.RandomSleep2(30, 30, 30)
                end
                Config.Variables.inTFNGear = false
                return true
            end
        }
    ),
    destroyCore = Timer.new(
        {
            name = "Destroy Core",
            cooldown = 1,
            useTicks = true,
            condition = function() return true end,
            action = function()
                -- Check if core exists and try to destroy it
                local core = Utils.find(MECHANIC_OBJECTS.CoreId, 1, 30)
                if core then
                    return API.DoAction_NPC(0x29, API.OFF_ACT_InteractNPC_route, {MECHANIC_OBJECTS.CoreId}, 50)
                end
                return false
            end
        }
    ),
    attackAG = Timer.new(
        {
            name = "Attack Arch-Glacor",
            cooldown = 1,
            useTicks = true,
            condition = function() 
                -- Only attack AG when not targeting and not in minion targeting mode
                if API.IsTargeting() then return false end
                if Config.Variables.targetMinionsActive then return false end
                
                -- Only avoid attacking during pillars mechanic
                if Config.Variables.currentMechanic == "pillars" then return false end
                
                return true
            end,
            action = function()
                return API.DoAction_NPC(0x2a,API.OFF_ACT_AttackNPC_route,{ ArchGlacorId },50)
            end
        }
    ),
    attackMinions = Timer.new(
        {
            name = "Attack Minions",
            cooldown = 1,
            useTicks = true,
            condition = function() 
                -- Only run when flag is active
                if not Config.Variables.targetMinionsActive then return false end
                
                -- Only run during minions mechanic
                if Config.Variables.currentMechanic ~= "minions" then return false end
                
                -- Check if any minions exist (still needed for targeting)
                local bolstered = API.GetAllObjArray1({MECHANIC_OBJECTS.BolsterMinionId}, 60, {1})[1]
                local minions1 = Utils.findAll(MECHANIC_OBJECTS.MinionIds[1], 1, 30)
                local minions2 = Utils.findAll(MECHANIC_OBJECTS.MinionIds[2], 1, 30)
                
                local anyMinionsExist = bolstered or #minions1 > 0 or #minions2 > 0
                
                -- If we're not targeting anything, definitely try to target
                if not API.IsTargeting() or API.GetTargetHealth() ~= 0 then
                    return anyMinionsExist
                end
                
                -- If we are targeting, check if we should retarget
                -- This handles the case where one minion dies but there are multiple of the same type
                if anyMinionsExist then
                    -- Get current target ID if available
                    local currentTarget = API.ReadTargetInfo(true)
                    if currentTarget and currentTarget.Id then
                        local targetId = currentTarget.Id
                        
                        -- Check Type1 minions
                        if targetId == MECHANIC_OBJECTS.MinionIds[1] then
                            if #minions1 > 1 then
                                Utils.debugLog(string.format("RETARGET: Multiple Type1 minions (%d) exist - retargeting to ensure hitting live minion", #minions1))
                                return true  -- Retarget to ensure we're hitting a live minion
                            end
                            
                        -- Check Type2 minions
                        elseif targetId == MECHANIC_OBJECTS.MinionIds[2] then
                            if #minions2 > 1 then
                                Utils.debugLog(string.format("RETARGET: Multiple Type2 minions (%d) exist - retargeting to ensure hitting live minion", #minions2))
                                return true  -- Retarget to ensure we're hitting a live minion
                            end
                            
                        -- Check Bolstered minion
                        elseif targetId == MECHANIC_OBJECTS.BolsterMinionId then
                            if bolstered then
                                return false  -- Already targeting bolstered, no need to retarget
                            else
                                Utils.debugLog("RETARGET: Bolstered minion died - need to retarget")
                                return true  -- Bolstered died, need to retarget
                            end
                            
                        -- Unknown target
                        else
                            Utils.debugLog(string.format("RETARGET: Unknown minion target ID %d - retargeting to get proper minion", targetId))
                            return true  -- Unknown target, retarget to get a proper minion
                        end
                        
                    else
                        Utils.debugLog("RETARGET: No target info available - attempting to target")
                        return true  -- No target info, should try to target
                    end
                end
                
                return false
            end,
            action = function()
                -- Priority: bolstered > minions1 > minions2
                local bolstered = API.GetAllObjArray1({MECHANIC_OBJECTS.BolsterMinionId}, 60, {1})[1]
                local minions1 = Utils.findAll(MECHANIC_OBJECTS.MinionIds[1], 1, 30)
                local minions2 = Utils.findAll(MECHANIC_OBJECTS.MinionIds[2], 1, 30)
                
                -- Get current target info for debugging
                local currentTarget = API.ReadTargetInfo(true)
                local currentTargetId = currentTarget and currentTarget.Id or "none"
                local currentTargetName = currentTarget and currentTarget.Name or "none"
                local isTargeting = API.IsTargeting()
                
                -- Get player position for distance calculations
                local playerCoords = API.PlayerCoord()
                
                Utils.debugLog("=== MINIONS TARGETING DEBUG ===")
                Utils.debugLog(string.format("Current mechanic: %s", Config.Variables.currentMechanic or "none"))
                Utils.debugLog(string.format("Targeting active: %s", tostring(Config.Variables.targetMinionsActive)))
                Utils.debugLog(string.format("Is targeting: %s", tostring(isTargeting)))
                Utils.debugLog(string.format("Current target: ID=%s, Name=%s", tostring(currentTargetId), tostring(currentTargetName)))
                Utils.debugLog(string.format("Player position: (%.1f, %.1f)", playerCoords.x, playerCoords.y))
                
                -- Debug minion counts and positions
                Utils.debugLog(string.format("Minion counts: Bolstered=%d, Type1=%d, Type2=%d", 
                    bolstered and 1 or 0, #minions1, #minions2))
                
                    if bolstered then
                    local dist = math.sqrt((playerCoords.x - bolstered.Tile_XYZ.x)^2 + (playerCoords.y - bolstered.Tile_XYZ.y)^2)
                    Utils.debugLog(string.format("Bolstered minion: ID=%d, Position=(%.1f, %.1f), Distance=%.1f", 
                        bolstered.Id, bolstered.Tile_XYZ.x, bolstered.Tile_XYZ.y, dist))
                end
                
                for i, minion in ipairs(minions1) do
                    local dist = math.sqrt((playerCoords.x - minion.Tile_XYZ.x)^2 + (playerCoords.y - minion.Tile_XYZ.y)^2)
                    Utils.debugLog(string.format("Minion1[%d]: ID=%d, Position=(%.1f, %.1f), Distance=%.1f", 
                        i, minion.Id, minion.Tile_XYZ.x, minion.Tile_XYZ.y, dist))
                end
                
                for i, minion in ipairs(minions2) do
                    local dist = math.sqrt((playerCoords.x - minion.Tile_XYZ.x)^2 + (playerCoords.y - minion.Tile_XYZ.y)^2)
                    Utils.debugLog(string.format("Minion2[%d]: ID=%d, Position=(%.1f, %.1f), Distance=%.1f", 
                        i, minion.Id, minion.Tile_XYZ.x, minion.Tile_XYZ.y, dist))
                end
                
                -- Targeting logic with debug
                if bolstered then
                    Utils.debugLog("TARGETING: Attacking bolstered minion (highest priority)")
                    local success = API.DoAction_NPC(0x2a, API.OFF_ACT_AttackNPC_route, {MECHANIC_OBJECTS.BolsterMinionId}, 50)
                    Utils.debugLog(string.format("Bolstered targeting result: %s", tostring(success)))
                    Utils.debugLog("=== END MINIONS TARGETING DEBUG ===")
                    return success
                elseif #minions1 > 0 then
                    Utils.debugLog(string.format("TARGETING: Attacking minion type 1 (%d remaining)", #minions1))
                    local success = API.DoAction_NPC(0x2a, API.OFF_ACT_AttackNPC_route, {MECHANIC_OBJECTS.MinionIds[1]}, 50)
                    Utils.debugLog(string.format("Minion1 targeting result: %s", tostring(success)))
                    Utils.debugLog("=== END MINIONS TARGETING DEBUG ===")
                    return success
                elseif #minions2 > 0 then
                    Utils.debugLog(string.format("TARGETING: Attacking minion type 2 (%d remaining)", #minions2))
                    local success = API.DoAction_NPC(0x2a, API.OFF_ACT_AttackNPC_route, {MECHANIC_OBJECTS.MinionIds[2]}, 50)
                    Utils.debugLog(string.format("Minion2 targeting result: %s", tostring(success)))
                    Utils.debugLog("=== END MINIONS TARGETING DEBUG ===")
                    return success
                end
                
                -- Don't reset the flag here - let the mechanic ending system handle it
                Utils.debugLog("TARGETING: No minions found, waiting for mechanic to end properly")
                Utils.debugLog("=== END MINIONS TARGETING DEBUG ===")
                return false
            end
        }
    ),
    dodgeIce = Timer.new(
        {
            name = "Dodge Ice",
            cooldown = 1,
            useTicks = true,
            condition = function() 
                -- Don't dodge ice while executing pillars rotation beam mechanic
                if Config.Variables.currentMechanic == "pillars" and 
                   Config.Instances.PillarsRotation and 
                   not Config.Instances.PillarsRotation.trailing then
                    return false
                end
                
                -- Don't dodge ice during arms mechanic
                if Config.Variables.currentMechanic == "arms" then
                    return false
                end
                
                -- Check if ice is approaching and we need to move
                local playerCoords = API.PlayerCoord()
                local playerX = playerCoords.x
                local leftIceX = nil
                local rightIceX = nil
                
                -- Validate player coordinates
                if not playerX or type(playerX) ~= "number" or playerX ~= playerX then -- NaN check
                    Utils.debugLog("Invalid player coordinates, skipping ice dodge")
                    return false
                end
                
                -- Track previous ice positions to detect phantom teleporting ice
                if not Config.Variables.lastIcePositions then
                    Config.Variables.lastIcePositions = {left = nil, right = nil}
                end
                
                -- Use pre-calculated arena boundaries for phantom detection
                local leftEdge = Config.Variables.iceEdges and Config.Variables.iceEdges.left or nil
                local rightEdge = Config.Variables.iceEdges and Config.Variables.iceEdges.right or nil
                
                for _, iceId in ipairs(MECHANIC_OBJECTS.IceIds) do
                    local iceObjects = Utils.findAll(iceId, 0, 30)
                    for _, ice in ipairs(iceObjects) do
                        local iceX = ice.Tile_XYZ.x
                        
                        -- Validate ice coordinates
                        if not iceX or type(iceX) ~= "number" or iceX ~= iceX then
                            Utils.debugLog("Invalid ice coordinates, skipping")
                            goto continue
                        end
                        
                        -- Ice to the west (lower X values)
                        if iceX < playerX then
                            -- Check for phantom teleporting ice (moved more than 2 tiles since last tick)
                            if Config.Variables.lastIcePositions.left and 
                               math.abs(iceX - Config.Variables.lastIcePositions.left) > 2 then
                                --Utils.debugLog(string.format("Phantom left ice detected: moved from %.1f to %.1f (%.1f tiles) - ignoring", 
                                    --Config.Variables.lastIcePositions.left, iceX, math.abs(iceX - Config.Variables.lastIcePositions.left)))
                                goto continue
                            end
                            
                            -- Check for ice appearing after none (only valid near left edge)
                            if not Config.Variables.lastIcePositions.left and leftEdge and iceX > (leftEdge + 1) then
                                Utils.debugLog(string.format("Invalid left ice spawn: X=%.1f not near left edge (%.1f) - ignoring", iceX, leftEdge))
                                goto continue
                            end
                            
                            -- Debug: Show when left ice passes all phantom checks  
                            if not Config.Variables.lastIcePositions.left then
                                Utils.debugLog(string.format("Left ice appearing after none: X=%.1f, Player=%.1f, LeftEdge=%s, Valid=%s", 
                                    iceX, playerX, leftEdge and string.format("%.1f", leftEdge) or "nil", 
                                    tostring(not leftEdge or iceX <= (leftEdge + 1))))
                            end
                            
                            if not leftIceX or iceX > leftIceX then
                                leftIceX = iceX  -- Track the closest ice on the left
                            end
                        -- Ice to the east (higher X values)
                        elseif iceX > playerX then
                            -- Check for phantom teleporting ice
                            if Config.Variables.lastIcePositions.right and 
                               math.abs(iceX - Config.Variables.lastIcePositions.right) > 2 then
                                --Utils.debugLog(string.format("Phantom right ice detected: moved from %.1f to %.1f (%.1f tiles) - ignoring", 
                                    --Config.Variables.lastIcePositions.right, iceX, math.abs(iceX - Config.Variables.lastIcePositions.right)))
                                goto continue
                            end
                            
                            -- Check for ice appearing after none (only valid near right edge)
                            if not Config.Variables.lastIcePositions.right and rightEdge and iceX < (rightEdge - 1) then
                                Utils.debugLog(string.format("Invalid right ice spawn: X=%.1f not near right edge (%.1f) - ignoring", iceX, rightEdge))
                                goto continue
                            end
                            
                            -- Debug: Show when right ice passes all phantom checks
                            if not Config.Variables.lastIcePositions.right then
                                Utils.debugLog(string.format("Right ice appearing after none: X=%.1f, Player=%.1f, RightEdge=%s, Valid=%s", 
                                    iceX, playerX, rightEdge and string.format("%.1f", rightEdge) or "nil", 
                                    tostring(not rightEdge or iceX >= (rightEdge - 1))))
                            end
                            
                            if not rightIceX or iceX < rightIceX then
                                rightIceX = iceX  -- Track the closest ice on the right
                    end
                end
                
                        ::continue::
                    end
                end
                
                -- Update tracked positions for next tick
                Config.Variables.lastIcePositions.left = leftIceX
                Config.Variables.lastIcePositions.right = rightIceX
                
                -- Calculate distances
                local leftDistance = leftIceX and math.abs(playerX - leftIceX) or math.huge
                local rightDistance = rightIceX and math.abs(playerX - rightIceX) or math.huge
                
                -- Only dodge if ice is within 6 tiles
                local needToDodge = (leftDistance <= 6) or (rightDistance <= 6)
                
                if needToDodge then
                   -- Utils.debugLog(string.format("Ice detected - Left: %s (dist: %.1f), Right: %s (dist: %.1f)", 
                    --    leftIceX and string.format("%.1f", leftIceX) or "none", 
                    --    leftDistance == math.huge and -1 or leftDistance,
                    --    rightIceX and string.format("%.1f", rightIceX) or "none",
                     --   rightDistance == math.huge and -1 or rightDistance))
                end
                
                return needToDodge
            end,
            action = function()
                local playerCoords = API.PlayerCoord()
                local playerX = playerCoords.x
                local playerY = playerCoords.y
                local leftIceX = nil
                local rightIceX = nil
                
                -- Validate player coordinates
                if not playerX or type(playerX) ~= "number" or playerX ~= playerX or
                   not playerY or type(playerY) ~= "number" or playerY ~= playerY then
                    Utils.debugLog("Invalid player coordinates in ice dodge action")
                    return false
                end
                
                -- Find ice positions again with phantom detection
                -- Calculate arena boundaries for phantom detection
                local leftEdge = Config.Variables.iceEdges and Config.Variables.iceEdges.left or nil
                local rightEdge = Config.Variables.iceEdges and Config.Variables.iceEdges.right or nil
                
                for _, iceId in ipairs(MECHANIC_OBJECTS.IceIds) do
                    local iceObjects = Utils.findAll(iceId, 0, 30)
                    for _, ice in ipairs(iceObjects) do
                        local iceX = ice.Tile_XYZ.x
                        
                        -- Validate ice coordinates
                        if not iceX or type(iceX) ~= "number" or iceX ~= iceX then
                            goto continue
                        end
                        
                        -- Apply same phantom detection as in condition
                        if iceX < playerX then
                            if Config.Variables.lastIcePositions and Config.Variables.lastIcePositions.left and 
                               math.abs(iceX - Config.Variables.lastIcePositions.left) > 2 then
                                goto continue
                            end
                            -- Check for ice appearing after none (only valid near left edge)
                            if Config.Variables.lastIcePositions and not Config.Variables.lastIcePositions.left and leftEdge and iceX > (leftEdge + 1) then
                                goto continue
                            end
                            if not leftIceX or iceX > leftIceX then
                                leftIceX = iceX
                            end
                        elseif iceX > playerX then
                            if Config.Variables.lastIcePositions and Config.Variables.lastIcePositions.right and 
                               math.abs(iceX - Config.Variables.lastIcePositions.right) > 2 then
                                goto continue
                            end
                            if not rightIceX or iceX < rightIceX then
                                rightIceX = iceX
                    end
                end
                
                        ::continue::
                    end
                end
                
                local leftDistance = leftIceX and math.abs(playerX - leftIceX) or math.huge
                local rightDistance = rightIceX and math.abs(playerX - rightIceX) or math.huge
                local moveX = playerX
                
                -- If we have ice on both sides
                if leftIceX and rightIceX then
                    local gap = rightIceX - leftIceX
                    
                    --Utils.debugLog(string.format("Ice on both sides - Gap: %.1f tiles", gap))
                    
                    if gap >= 18 then
                        -- Large gap, move to center
                        moveX = math.floor(leftIceX + gap / 2)
                        Utils.debugLog("Large gap - moving to center")
                    elseif gap >= 9 then
                        -- Medium gap, check if safe
                        local center = leftIceX + gap / 2
                        local safeRadius = (gap - 2) / 2
                        local distFromCenter = math.abs(playerX - center)
                        
                        -- NEW: Also check if we're too close to either ice wall
                        if leftDistance <= 4 or rightDistance <= 4 then
                            -- Too close to ice, must move to center regardless
                            moveX = math.floor(center)
                            --Utils.debugLog(string.format("Medium gap - TOO CLOSE TO ICE (left: %.1f, right: %.1f) - moving to center", 
                            --    leftDistance, rightDistance))
                        elseif distFromCenter > safeRadius then
                            moveX = math.floor(center)
                            --Utils.debugLog("Medium gap - moving to safe center")
                        else
                            --Utils.debugLog("Already safe in medium gap")
                            return false
                        end
                    else
                        -- Small gap, dodge away from closest
                        if leftDistance < rightDistance then
                            moveX = playerX + 4
                            Utils.debugLog("Small gap - dodging right")
                        else
                            moveX = playerX - 4
                            Utils.debugLog("Small gap - dodging left")
                        end
                    end
                -- Ice only on one side
                elseif leftIceX and not rightIceX then
                    if leftDistance <= 5 then
                        moveX = playerX + 6  -- Move east (higher X)
                        Utils.debugLog(string.format("Ice only on west side (X=%.1f) - moving east", leftIceX))
                    end
                elseif rightIceX and not leftIceX then
                    if rightDistance <= 5 then
                        moveX = playerX - 6  -- Move west (lower X)
                        Utils.debugLog(string.format("Ice only on east side (X=%.1f) - moving west", rightIceX))
                    end
                else
                    Utils.debugLog("No ice detected")
                    return false
                end
                
                -- CRITICAL FIX: Don't move beyond the right ice boundary
                if rightIceX and moveX >= rightIceX then
                    moveX = rightIceX - 2  -- Stay 2 tiles away from right ice
                    Utils.debugLog(string.format("Capped movement to avoid going past right ice: %.1f -> %.1f", moveX + 2, moveX))
                end
                
                -- Also don't move beyond the left ice boundary
                if leftIceX and moveX <= leftIceX then
                    moveX = leftIceX + 2  -- Stay 2 tiles away from left ice
                    Utils.debugLog(string.format("Capped movement to avoid going past left ice: %.1f -> %.1f", moveX - 2, moveX))
                end
                
                if moveX ~= playerX then
                    Utils.debugLog(string.format("Moving from X=%d to X=%d", math.floor(playerX), math.floor(moveX)))
                    ---@diagnostic disable-next-line
                    return API.DoAction_WalkerW(WPOINT.new(moveX, playerY, 0))
                end
                
                return false
            end
        }
    ),
    vulnBomb = Timer.new(
        {
            name = "Vulnerability Bomb",
            cooldown = 5,  -- 10 ticks
            useTicks = true,
            condition = function()
                local target = API.IsTargeting()
                if not target then return false end
                
                -- Don't use vuln bomb during pillars mechanic
                if Config.Variables.currentMechanic == "pillars" then return false end
                
                local hasVuln = false
                local value = API.VB_FindPSettinOrder(896).state 
                if value == 536870912 then
                    hasVuln = true
                end
                return not hasVuln  -- Fixed: trigger when target DOESN'T have vuln
            end,
            action = function()
                return API.DoAction_Inventory1(48951, 0, 1, API.OFF_ACT_GeneralInterface_route)
            end
        }
    ),
    healFamiliar = Timer.new(
        {
            name = "Heal Familiar",
            cooldown = 1, -- 10 ticks cooldown to avoid spam
            useTicks = true,
            condition = function()
                -- Check if familiar health is below 3000
                local familiarHp = Familiars:GetHealth()
                    if familiarHp and familiarHp < 3000 then
                        Utils.debugLog("Familiar HP: " .. familiarHp .. " - needs healing")
                        return true
                else
                return false
                end
            end,
            action = function()
                -- Use Prism of Restoration (no spellbook swap needed since already on Ancient)
                if Utils.useAbility("Prism of Restoration") then
                    Utils.debugLog("Used Prism of Restoration to heal familiar")
                    return true
                else
                    Utils.debugLog("Failed to use Prism of Restoration")
                    return false
                end
            end
        }
    ),
    handleDeath = Timer.new(
        {
            name = "Handle Death",
            cooldown = 1,
            useTicks = true,
            condition = function() return true end,
            action = function()
                -- Initialize death step if not set
                if not Config.Variables.deathStep then
                    Config.Variables.deathStep = 1
                    Config.Variables.deathStepTick = API.Get_tick()
                end
                
                local currentTick = API.Get_tick()
                
                if Config.Variables.deathStep == 1 then
                    -- Step 1: Interact with Death NPC
                    local ticksWaited = currentTick - Config.Variables.deathStepTick
                    Utils.debugLog("Death Step 1: Waiting 6 ticks, waited: " .. ticksWaited)
                    if ticksWaited >= 6 then
                        if API.DoAction_NPC(0x29,API.OFF_ACT_InteractNPC_route3,{ 27299},50) then
                            Config.Variables.deathStep = 2
                            Config.Variables.deathStepTick = currentTick
                            return true
                        end
                    end
                    return false
                    
                elseif Config.Variables.deathStep == 2 then
                    -- Step 2: Wait till VB 2874 is 18
                    local vbState = API.VB_FindPSettinOrder(2874).state
                    Utils.debugLog("Death Step 2: Waiting for VB 2874 to be 18, current: " .. tostring(vbState))
                    if vbState == 18 then
                        Config.Variables.deathStep = 3
                        Config.Variables.deathStepTick = currentTick
                        return true
                    end
                    return false
                    
                elseif Config.Variables.deathStep == 3 then
                    -- Step 3: Click interface 1626:47
                    Utils.debugLog("Death Step 3: Clicking interface 1626:47")
                    if API.DoAction_Interface(0xffffffff,0xffffffff,1,1626,47,-1,API.OFF_ACT_GeneralInterface_route) then
                        Config.Variables.deathStep = 4
                        Config.Variables.deathStepTick = currentTick
                        return true
                    end
                    return false
                    
                elseif Config.Variables.deathStep == 4 then
                    -- Step 4: Wait 3 ticks
                    local ticksWaited = currentTick - Config.Variables.deathStepTick
                    Utils.debugLog("Death Step 4: Waiting 3 ticks, waited: " .. ticksWaited)
                    if ticksWaited >= 3 then
                        Config.Variables.deathStep = 5
                        Config.Variables.deathStepTick = currentTick
                        return true
                    end
                    return false
                    
                elseif Config.Variables.deathStep == 5 then
                    -- Step 5: Click interface 1626:72
                    Utils.debugLog("Death Step 5: Clicking interface 1626:72")
                    if API.DoAction_Interface(0xffffffff,0xffffffff,0,1626,72,-1,API.OFF_ACT_GeneralInterface_Choose_option) then
                        Config.Variables.deathStep = 6
                        Config.Variables.deathStepTick = currentTick
                        return true
                    end
                    return false
                    
                elseif Config.Variables.deathStep == 6 then
                    -- Step 6: Wait 2 ticks
                    local ticksWaited = currentTick - Config.Variables.deathStepTick
                    Utils.debugLog("Death Step 6: Waiting 2 ticks, waited: " .. ticksWaited)
                    if ticksWaited >= 2 then
                        Config.Variables.deathStep = 7
                        Config.Variables.deathStepTick = currentTick
                        return true
                    end
                    return false
                    
                elseif Config.Variables.deathStep == 7 then
                    -- Step 7: Click interface 1673:14 (final step)
                    Utils.debugLog("Death Step 7: Clicking interface 1673:14 (final step)")
                    if API.DoAction_Interface(0x2e,0xffffffff,1,1673,14,-1,API.OFF_ACT_GeneralInterface_route) then
                        -- Reset death step for next time
                        Config.Variables.deathStep = nil
                        Config.Variables.deathStepTick = nil
                        Utils.debugLog("Death handling complete - resetting death steps")
                        return true
                    end
                    return false
                end
                
                return false
            end
        }
    ),
    collectDeathLoot = Timer.new(
        {
            name = "Collect Death Loot",
            cooldown = 1,
            useTicks = true,
            condition = function() return true end,
            action = function()
                -- Initialize death loot step if not set
                if not Config.Variables.deathLootStep then
                    Config.Variables.deathLootStep = 1
                    Config.Variables.deathLootStepTick = API.Get_tick()
                end
                
                local currentTick = API.Get_tick()
                
                if Config.Variables.deathLootStep == 1 then
                    -- Step 1: First action to claim loot - try 121367 first, then 121368
                    Utils.debugLog("Death Loot Step 1: Claiming death loot")
                    if API.DoAction_Object1(0x29,API.OFF_ACT_GeneralObject_route0,{ 121367 },50) then
                        Config.Variables.deathLootStep = 2
                        Config.Variables.deathLootStepTick = currentTick
                        return true
                    elseif API.DoAction_Object1(0x29,API.OFF_ACT_GeneralObject_route0,{ 121368 },50) then
                        Config.Variables.deathLootStep = 2
                        Config.Variables.deathLootStepTick = currentTick
                        return true
                    end
                    return false
                    
                elseif Config.Variables.deathLootStep == 2 then
                    -- Step 2: Wait for VB 18
                    local vbState = API.VB_FindPSettinOrder(2874).state
                    Utils.debugLog("Death Loot Step 2: Waiting for VB 2874 to be 18, current: " .. tostring(vbState))
                    if vbState == 18 then
                        Config.Variables.deathLootStep = 3
                        Config.Variables.deathLootStepTick = currentTick
                        return true
                    end
                    return false
                    
                elseif Config.Variables.deathLootStep == 3 then
                    -- Step 3: Second action to complete loot collection (pseudo for now)
                    Utils.debugLog("Death Loot Step 3: Completing death loot collection")
                    -- TODO: Replace with actual API function
                    if API.DoAction_Interface(0x24,0xffffffff,1,863,114,-1,API.OFF_ACT_GeneralInterface_route) then
                        -- Reset all death loot variables after successful collection
                        Config.Variables.deathLootStep = nil
                        Config.Variables.deathLootStepTick = nil
                        Config.Variables.diedInBossRoom = false
                        Config.Variables.hadContinuedChallenge = false
                        Config.Variables.deathLootAvailable = false
                        Config.Variables.everUsedContinueChallenge = false
                        Utils.debugLog("Death loot collection complete - resetting all death loot variables")
                        return true
                    end
                    return false
                end
                
                return false
            end
        }
    ),
}

---@type PlayerManagerConfig
Config.playerManager = {
    locations = {
        {
            name   = "War's Retreat",
            coords = { x = 3295, y = 10137, range = 30 }
        },
        {
            name = "Arch-Glacor (Lobby)",
            coords = { x = 1754, y = 1112, range = 12 }
        },
        {
            name = "Arch-Glacor (Boss Room)",
            detector = function() -- checks to see if instance timer exists
                local timer = {
                    { 861, 0, -1, -1, 0 }, { 861, 2, -1, 0, 0 },
                    { 861, 4, -1, 2,  0 }, { 861, 8, -1, 4, 0 }
                }
                local result = API.ScanForInterfaceTest2Get(false, timer)
                return result and #result > 0 and #result[1].textids > 0
            end
        },
        {
            name = "Death's Office",
            detector = function() return #Utils.findAll(27299, 1, 30) > 0 end
        },
    },
    -- status = {name: string, priority: number, condition: fun(self):boolean, execute: fun(self)}
    statuses = {
        -- general statuses
        {
            name = "Initializing",
            condition = function(self) return Config.Variables.initialCheck == false end,
            execute =  function(self)
                if not Config.Variables.initialCheck then
                    if self.state.location ~= "War's Retreat" then
                        Utils.terminate(
                            "Unfamiliar starting location.",
                            "Please start the script at War's Retreat."
                        )
                        return
                    end
                    if #Utils.findAll(121370, 0, 60) == 0 then -- AG portal
                        Utils.terminate("Portal to Arch-Glacor not found.")
                        return
                    end
                    Config.Variables.adrenCrystalSide = (math.floor(Utils.find(121370, 0, 60).Tile_XYZ.x) == 3298) and "East" or "West"
                    Utils.debugLog("Portal & Adrenaline crystal side: "..Config.Variables.adrenCrystalSide)
                    Config.Variables.initialCheck = true
                end
            end,
            priority = 100
        },
        {
            name = "Resetting tracked Config.Variables",
            condition = function(self) return Config.Variables.gateTile ~= nil and self.state.location == "War's Retreat" end,
            execute = function(self)
                Utils.debugLog("Resetting everything")
                    -- reset everything
                    Config.Variables.conjuresSummoned = false
                    Config.Variables.bankAttempts = 0
                    Config.Variables.conjureAttempts = 0
                    Config.Variables.initialRotationComplete = false  -- Reset initial rotation flag
                    Config.Variables.startspot = {x = 0, y =  0, range = 0}
                    Config.Variables.gateTile = nil
                    Config.Variables.beamspots = nil
                    Config.Variables.iceEdges = nil
                    Config.Variables.bossDead = false
                    Config.Variables.hasUniqueInChest = false  -- Reset unique chest flag
                    Config.Variables.chestChecked = false  -- Reset chest checked flag
                    Config.Variables.clickedAqueductPortal = false
                    Config.Variables.chestInterfaceLoggedOnce = false  -- Reset chest interface logged flag
                    Config.Variables.deathStep = nil  -- Reset death step tracking
                    Config.Variables.deathStepTick = nil  -- Reset death step tick tracking
                    -- reset mechanic tracking
                    Config.Variables.currentMechanic = "none"
                    Config.Variables.lastMechanic = "none"
                    Config.Variables.mechanicStartTick = 0
                    Config.Variables.lastMechanicDetectionTick = 0  -- Reset mechanic detection cooldown
                    Config.Variables.armsEndTick = 0
                    Config.Variables.mechanicCount = 0
                    Config.Variables.mechanicHistory = {}
                    Config.Variables.minionsDetected = false
                    Config.Variables.pillarsDetected = false
                    Config.Variables.armsDetected = false
                    Config.Variables.targetMinionsActive = false  -- Reset minion targeting flag
                    Config.Variables.chestLooted = false
                    Config.Variables.chestContainerOpenTime = 0  -- Reset chest timer
                    Config.Variables.pendingMechanic = "none"
                    -- reset all rotation instances
                    Config.Instances.fightRotation:reset()
                    Config.Instances.InitialRotation:reset()
                    Config.Instances.ArmsRotation:reset()
                    Config.Instances.PillarsRotation:reset()
                    Config.Instances.FlurryRotation:reset()
                    Config.Instances.FrostCannonRotation:reset()
                    Config.Instances.MinionsRotation:reset()
                    Config.Variables.mechanicEndTicks = {
                        arms = 0,
                        minions = 0,
                        pillars = 0,
                        flurry = 0,
                        frostcannon = 0
                    }
                    Config.Variables.threeBeamsDetectedTime = nil  -- Reset emergency timer
                    -- Reset death loot variables
                    Config.Variables.chestLooted = false
                    Config.Variables.chestContainerOpenTime = 0  -- Reset chest timer
                    Config.Variables.enrageDetected = false  -- Reset enrage detection flag
                    
                    -- reset all rotation instances
            end,
            priority = 90,
        },
        -- statuses at war's retreat
        {
            name = "Handling Death Recovery",
            condition = function(self) return self.state.location == "Death's Office" end,
            execute = function(self)
                logStatusChange("Handling Death Recovery")
                Config.Timer.handleDeath:execute()
            end,
            priority = 95  -- High priority to handle death immediately
        },
        {
            name = "Collecting Death Loot",
            condition = function(self) 
                return self.state.location == "Arch-Glacor (Lobby)" and 
                       Config.Variables.diedInBossRoom and 
                       Config.Variables.deathLootAvailable
            end,
            execute = function(self)
                logStatusChange("Collecting Death Loot")
                Config.Timer.collectDeathLoot:execute()
            end,
            priority = 94  -- High priority after death recovery
        },
        {
            name = "Detecting Death in Boss Room",
            condition = function(self) 
                -- Check if we're at Death's office but were previously in boss room
                return self.state.location == "Death's Office" and 
                       not Config.Variables.diedInBossRoom
            end,
            execute = function(self)
                logStatusChange("Detecting Death in Boss Room")
                print("Detecting Death in Boss Room")
                print(Config.Variables.everUsedContinueChallenge)
                Config.Variables.diedInBossRoom = true
                
                -- Send death notification webhook
                if Config.UserInput.discordNotifications then
                    Utils.sendDiscordWebhook((Config.UserInput.mention and "^<@"..Config.UserInput.userId.."^>") or "", Config.UserInput.webhookUrl, {
                        embeds = {
                            {
                                title = "You have Died at Arch-Glacor",
                                description = "Better luck next time!",
                                color = 16711680, -- Red color
                                author = {
                                    name = "Jared's Arch-Glacor",
                                    icon_url = "https://runescape.wiki/images/Arch-Glacor.png?ac3e5"
                                },
                                thumbnail = {url = "https://runescape.wiki/images/Death_%282020_Halloween_event%29_chathead.png?11fd3"},
                                fields = {
                                    {name = "Kill Number", value = tostring(Config.Variables.killCount + 1), inline = true},
                                    {name = "Runtime", value = API.ScriptRuntimeString(), inline = true},
                                }
                            }
                        }
                    })
                end
                
                -- Check if we had continued challenge before death
                -- If we've used continue challenge at least once this script run, we have death loot
                if Config.Variables.everUsedContinueChallenge then
                    Config.Variables.hadContinuedChallenge = true
                    Config.Variables.deathLootAvailable = true
                    Utils.debugLog("Death detected - had continued challenge, death loot available")
                else
                    Config.Variables.hadContinuedChallenge = false
                    Config.Variables.deathLootAvailable = false
                    Utils.debugLog("Death detected - no previous continue challenge, no death loot")
                end
            end,
            priority = 96  -- Higher than death recovery to set flags first
        },
        {
            name = "Doing Bank PIN",
            condition = function(self) 
                if self.state.location == "War's Retreat" then
                    if API.DoBankPin(Config.UserInput.bankPin) then
                        if not Config.UserInput.useBankPin then
                            Utils.terminate(
                                "No bankpin provided while being bankpin required.",
                                "Make sure your bankpin is initialized under Config.userInput.bankPin."
                            )
                        else
                            return true
                        end
                    end
                end
                return false
            end,
            execute = function(self) end,
            priority = 12
        },
        {
            name = "Loading last preset",
            condition = function(self) return (self.state.location == "War's Retreat") and not Utils.hasAllItems(Config.UserInput.presetChecks) end,
            execute = function(self)
                Config.Timer.loadLastPreset:execute(self)
                
            end,
            priority = 11
        },
        {
            name = "Waiting for health to regenerate",
            condition = function(self) return self.state.location == "War's Retreat" and self.state.health.percent < 90 end,
            execute = function(self) Config.Timer.standByBankChest:execute(self) end,
            priority = 10
        },
        {
            name = "Interacting with Bonfire",
            condition = function(self) return self.state.location == "War's Retreat" and (API.Bbar_ConvToSeconds(API.Buffbar_GetIDstatus(10931, false)) < 240) end,
            execute = function(self)
                Config.Timer.bonfireBoost:execute(self) 
            end,
            priority = 9
        },
        {
            name = "Interacting with Altar of War",
            condition = function(self) return self.state.location == "War's Retreat" and self.state.prayer.percent < 95 end,
            execute = function(self)
                -- Only deactivate prayer when we're actually going to use the altar
                if Config.Timer.prayAtAltar:canTrigger() then
                Config.Instances.prayerFlicker:deactivatePrayer()
                end
                Config.Timer.prayAtAltar:execute(self) 
            end,
            priority = 8
        },
        {
            name = "Navigate to Adrenaline crytals",
            condition = function(self)
                if self.state.adrenaline >= 100 and not self:getDebuff(26094).found then return false end
                if Utils.find(114749, 12, 60) then
                    local crystal = Utils.find(114749, 12, 60).Tile_XYZ
                    return self.state.location == "War's Retreat" and not Utils.atLocation(crystal.x, crystal.y, 6)
                end
                return false
            end,
            execute = function(self) Config.Timer.navigate:execute(self) end,
            priority = 7
        },
        {
            name = "Channeling adrenaline",
            condition = function(self)
                return self.state.location == "War's Retreat" and
                    (self.state.adrenaline < 100 or self:getDebuff(26094).found)
            end,
            execute = function(self) Config.Timer.channelAdren:execute(self) end,
            priority = 6
        },
        {
            name = "Approaching portal",
            condition = function(self) return self.state.location == "War's Retreat" and not Utils.atLocation(3293, 10148, 12) end,
            execute = function(self) Config.Timer.navigate:execute(self) end,
            priority = 5
        },
        
        {
            name = "Going through portal",
            condition = function(self) return self.state.location == "War's Retreat" end,
            execute = function(self) Config.Timer.goThroughPortal:execute(self) end,
            priority = 3
        },
        -- statuses at AG
        {
            name = "Using Darkness",
            condition = function(self) 
                return self.state.location == "Arch-Glacor (Lobby)" and 
                       (not API.Buffbar_GetIDstatus(30122).found or (API.Bbar_ConvToSeconds(API.Buffbar_GetIDstatus(30122, false)) <= 360))
            end,
            execute = function(self) Config.Timer.useDarkness:execute(self) end,
            priority = 10
        },
        {
            name = "Starting new instance",
            condition = function(self) return self.state.location == "Arch-Glacor (Lobby)" end,
            execute = function(self) Config.Timer.handleInstance:execute(self) end,
            priority = 9
        },
        -- statuses at AG room
        -- initializing everything
        {
            name = "Locking in!",
            condition = function(self) return self.state.location == "Arch-Glacor (Boss Room)" and not Config.Variables.gateTile end,
            execute = function(self)
                local gate = Utils.findAll(121341, 0, 50)
                if #gate > 0 then
                    local gateTile = gate[1].Tile_XYZ
                    if gateTile.x == 1751.5 and gateTile.y == 1102.5 then
                        Utils.debugLog("Registered the wrong gate.")
                        return
                    end
                    Config.Variables.startspot = {x = math.floor(gateTile.x + 10), y = math.floor(gateTile.y - 4), range = 0}
                    Utils.debugLog(string.format("Start spot tile: (%s, %s, 0)", Config.Variables.startspot.x, Config.Variables.startspot.y))
                    Config.Variables.beamspots = {
                        {x = math.floor(gateTile.x - 1), y = math.floor(gateTile.y - 5)},
                        {x = math.floor(gateTile.x - 1), y = math.floor(gateTile.y + 1)},
                        {x = math.floor(gateTile.x + 9), y = math.floor(gateTile.y + 1)},
                        {x = math.floor(gateTile.x + 11), y = math.floor(gateTile.y + 1)},
                        {x = math.floor(gateTile.x + 24), y = math.floor(gateTile.y + 1)},
                        {x = math.floor(gateTile.x + 24), y = math.floor(gateTile.y - 5)},
                        {x = math.floor(gateTile.x + 20), y = math.floor(gateTile.y - 5)}
                    }
                    Config.Variables.armspot = {x = math.floor(gateTile.x + 11), y = math.floor(gateTile.y - 5)}
                    Config.Variables.iceEdges = {
                        left = gateTile.x + 1, -- +1 maybe
                        right = gateTile.x + 29
                    }
                    Config.Variables.gateTile = gateTile
                    Config.Instances.ArmsRotation = Config.Instances.ArmsRotation
                    Config.Instances.MinionsRotation = Config.Instances.MinionsRotation
                    Config.Variables.enrageDetected = true
                end
            end,
            priority = 40
        },
        -- pre-fight
        {
            name = "Executing Initial Rotation",
            condition = function(self)
                local atLocation = self.state.location == "Arch-Glacor (Boss Room)"
                local AG = Utils.find(28241, 1, 20)
                local fightHasStarted = AG and AG.Life and AG.Hitpoints and (AG.Life < AG.Hitpoints or Config.Variables.mechanicCount > 0)
                
                return atLocation
                    and not Config.Variables.bossDead
                    and not Config.Instances.InitialRotation.trailing
                    and not Config.Variables.initialRotationComplete
                    and not fightHasStarted  -- NEW: Prevent activation if fight has already started
            end,
            execute = function(self)
                Config.Instances.InitialRotation:execute()
                
                -- Check if initial rotation is complete and transfer state to fight rotation
                if Config.Instances.InitialRotation.trailing then
                    Utils.debugLog("Initial rotation complete, transferring state to fight rotation...")
                    transferRotationState(Config.Instances.InitialRotation, Config.Instances.fightRotation)
                    Utils.debugLog("State transfer complete")
                end
                
                -- Also get in position at the same time
                if not Utils.atLocation(Config.Variables.startspot.x, Config.Variables.startspot.y, 1) then
                    Config.Timer.getInPosition:execute(self)
                end
                Config.Timer.healFamiliar:execute()
                self:manageHealth()
                self:managePrayer()
                self:manageBuffs(Config.Buffs)
                Config.Instances.prayerFlicker:update()
            end,
            priority = 5
        },
        {
            name = "Getting in position",
            condition = function(self)
                local atLocation = self.state.location == "Arch-Glacor (Boss Room)"
                local AG = Utils.find(28241, 1, 20)
                local AGLife = AG and AG.Life or - 1
        
                return atLocation
                    and not Config.Variables.bossDead
                    and AGLife ~= 0
                    and not Utils.atLocation(Config.Variables.startspot.x, Config.Variables.startspot.y, 1)
                    and Config.Instances.InitialRotation.trailing  -- Only run after initial rotation is complete
            end,
            execute = function(self)
                Config.Timer.getInPosition:execute(self)
                Config.Instances.fightRotation:execute()
                Config.Timer.healFamiliar:execute()
                self:manageHealth()
                self:managePrayer()
                self:manageBuffs(Config.Buffs)
                Config.Instances.prayerFlicker:update()
            end,
            priority = 4
        },
        {
            name = "Waiting for Boss...",
            condition = function(self)
                return not Config.Variables.bossDead and (self.state.location == "Arch-Glacor (Boss Room)") and (#Utils.findAll(28241, 1, 20) == 0)
            end,
            execute = function(self)
                Config.Instances.fightRotation:execute()    -- rotation_manager
                Config.Timer.healFamiliar:execute()
                self:manageHealth()
                self:managePrayer()
                self:manageBuffs(Config.Buffs)
                Config.Instances.prayerFlicker:update()
            end,
            priority = 1
        },
        -- fight stuff
        {
            name = "Fighting Boss (Mechanic Detected)",
            condition = function(self)
                local AG = self.state.location == "Arch-Glacor (Boss Room)" and Utils.find(28241, 1, 20)
                if not AG or not AG.Life or AG.Life <= 0 or Config.Variables.bossDead then return false end
                
                -- Check if we have an active mechanic OR if a new one is detected
                local detectedMechanic = detectMechanic()
                local hasActiveMechanic = Config.Variables.currentMechanic ~= "none"
                
                return detectedMechanic ~= "none" or hasActiveMechanic
            end,
            execute = function(self)
                logStatusChange("Fighting Boss (Mechanic: " .. Config.Variables.currentMechanic .. ")")
                
                local detectedMechanic = detectMechanic()
                local currentTick = API.Get_tick()

                -- Execute all fight timers
                Config.Timer.destroyCore:execute()
                Config.Timer.attackAG:execute()
                Config.Timer.attackMinions:execute()
                Config.Timer.vulnBomb:execute()
                Config.Timer.dodgeIce:execute()
                Config.Timer.healFamiliar:execute()

                -- Check if current mechanic has ended
                if Config.Variables.currentMechanic ~= "none" and isMechanicEnded(Config.Variables.currentMechanic) then
                    -- Set end tick for the mechanic that just ended
                    if not Config.Variables.mechanicEndTicks then
                        Config.Variables.mechanicEndTicks = {
                            arms = 0,
                            minions = 0,
                            pillars = 0,
                            flurry = 0,
                            frostcannon = 0
                        }
                    end
                    Config.Variables.mechanicEndTicks[Config.Variables.currentMechanic] = currentTick
                    Utils.debugLog(string.format("[EXECUTE] Mechanic %s ENDED - set end tick: %d", 
                        Config.Variables.currentMechanic, currentTick))
                    
                    -- Reset specific flags when mechanic ends
                    if Config.Variables.currentMechanic == "minions" then
                        Config.Variables.targetMinionsActive = false
                        Config.Variables.minionsDetected = false
                    elseif Config.Variables.currentMechanic == "arms" then
                        Config.Variables.armsEndTick = currentTick
                        Config.Variables.armsDetected = false
                    elseif Config.Variables.currentMechanic == "pillars" then
                        Config.Variables.pillarsDetected = false
                    end
                    
                    -- Get the rotations before resetting
                    local mechanicRotation = getRotationForMechanic(Config.Variables.currentMechanic)
                    local fightRotation = Config.Instances.fightRotation
                    
                    -- Transfer state from mechanic rotation to fight rotation
                    if mechanicRotation and mechanicRotation ~= fightRotation then
                        transferRotationState(mechanicRotation, fightRotation)
                        mechanicRotation:reset()
                    end
                    
                    -- AFTER rotation reset: Re-equip soulbound lantern if arms mechanic ended
                    if Config.Variables.lastMechanic == "arms" then
                        if Inventory:InvItemFound(55485) then
                            Utils.debugLog("Arms mechanic ended - re-equipping soulbound lantern (after rotation reset)")
                            Inventory:Equip(55485)
                        else
                            Utils.debugLog("Arms mechanic ended but no soulbound lantern found in inventory")
                        end
                    end
                    
                    -- Update mechanic tracking
                    Config.Variables.lastMechanic = Config.Variables.currentMechanic
                    Config.Variables.currentMechanic = "none"
                    
                    -- Check for pending mechanic (important for pillars->minions transition)
                    if Config.Variables.pendingMechanic and Config.Variables.pendingMechanic ~= "none" then
                        Utils.debugLog("Processing pending mechanic: " .. Config.Variables.pendingMechanic .. " after " .. Config.Variables.lastMechanic .. " ended")
                        
                        -- Set the pending mechanic as current
                        Config.Variables.currentMechanic = Config.Variables.pendingMechanic
                        Config.Variables.mechanicStartTick = currentTick
                        Config.Variables.lastMechanicDetectionTick = currentTick
                        Config.Variables.mechanicCount = Config.Variables.mechanicCount + 1
                        
                        -- Add to history
                        table.insert(Config.Variables.mechanicHistory, Config.Variables.pendingMechanic)
                        if #Config.Variables.mechanicHistory > 5 then
                            table.remove(Config.Variables.mechanicHistory, 1)
                        end
                        
                        -- Clear the pending mechanic
                        Config.Variables.pendingMechanic = "none"
                        
                        -- Reset detection flags for the new mechanic
                        if Config.Variables.currentMechanic == "minions" then
                            Config.Variables.minionsDetected = false
                        elseif Config.Variables.currentMechanic == "pillars" then
                            Config.Variables.pillarsDetected = false
                        elseif Config.Variables.currentMechanic == "arms" then
                            Config.Variables.armsDetected = false
                        end
                        
                        Utils.debugLog("Activated pending mechanic: " .. Config.Variables.currentMechanic)
                    end
                    
                    -- Execute one cycle of fight rotation immediately
                    Config.Instances.fightRotation:execute()
                    
                    -- Handle other mechanics before returning
                    self:manageHealth()
                    self:managePrayer()
                    self:manageBuffs(Config.Buffs)
                    Config.Instances.prayerFlicker:update()
                    
                    return -- CRITICAL FIX: Exit here to prevent re-detection in same cycle!
                end

                -- Check if this is a new mechanic being triggered
                if detectedMechanic ~= "none" and detectedMechanic ~= Config.Variables.currentMechanic then
                    local AG = Utils.find(28241, 1, 20)
                    Utils.debugLog(string.format("[EXECUTE] NEW MECHANIC TRIGGERED: %s -> %s (AG Anim: %d)", 
                        Config.Variables.currentMechanic, detectedMechanic, AG and AG.Anim or -1))
                
                -- Force-end the current mechanic if a new one is detected
                if Config.Variables.currentMechanic ~= "none" then
                    if Config.Variables.currentMechanic == "pillars" then
                        -- Store the new mechanic as pending instead of force-ending pillars
                        Config.Variables.pendingMechanic = detectedMechanic
                        Utils.debugLog("Pillars active - storing " .. detectedMechanic .. " as pending mechanic")
                        
                        -- Don't update current mechanic variables, let pillars complete
                        -- Execute pillars rotation and other mechanics
                        if Config.Variables.currentMechanic ~= "none" then
                            local currentRotation = getRotationForMechanic(Config.Variables.currentMechanic)
                            if currentRotation then
                                currentRotation:execute()
                            end
                        end
                        
                        self:manageHealth()
                        self:managePrayer()
                        self:manageBuffs(Config.Buffs)
                        Config.Instances.prayerFlicker:update()
                        return -- Exit early, don't process the new mechanic yet
                    else
                        -- Force-end other mechanics normally
                        Utils.debugLog("Force-ending current mechanic: " .. Config.Variables.currentMechanic .. " due to new mechanic: " .. detectedMechanic)
                        
                        -- Track when the force-ended mechanic ended
                        if not Config.Variables.mechanicEndTicks then
                            Config.Variables.mechanicEndTicks = {
                                arms = 0,
                                minions = 0,
                                pillars = 0,
                                flurry = 0,
                                frostcannon = 0
                            }
                        end
                        Config.Variables.mechanicEndTicks[Config.Variables.currentMechanic] = currentTick
                        
                        -- Reset specific flags when mechanic is force-ended
                        if Config.Variables.currentMechanic == "minions" then
                            Config.Variables.targetMinionsActive = false
                            Config.Variables.minionsDetected = false
                            Utils.debugLog("Force-deactivated minion targeting and reset detection - new mechanic detected")
                        elseif Config.Variables.currentMechanic == "arms" then
                            Config.Variables.armsDetected = false
                                
                                -- ALWAYS re-equip soulbound lantern when arms mechanic is force-ended
                                if Inventory:InvItemFound(55485) then
                                    Utils.debugLog("Arms mechanic force-ended - re-equipping soulbound lantern")
                                    Inventory:Equip(55485)
                                else
                                    Utils.debugLog("Arms mechanic force-ended but no soulbound lantern found in inventory")
                                end
                        end
                        
                        -- Get the rotation for the mechanic being ended
                        local endingRotation = getRotationForMechanic(Config.Variables.currentMechanic)
                        if endingRotation then
                                endingRotation:reset()
                        end
                        
                        -- AFTER rotation reset: Re-equip soulbound lantern if arms mechanic was force-ended
                        if Config.Variables.currentMechanic == "arms" then
                            if Inventory:InvItemFound(55485) then
                                Utils.debugLog("Arms mechanic force-ended - re-equipping soulbound lantern (after rotation reset)")
                                Inventory:Equip(55485)
                            else
                                Utils.debugLog("Arms mechanic force-ended but no soulbound lantern found in inventory")
                            end
                        end
                    end
                end
                -- SAFETY: Pillars to Minions transition - move to spot 6 to avoid beam death
                -- Update mechanic tracking FIRST
                Config.Variables.lastMechanic = Config.Variables.currentMechanic
                Config.Variables.currentMechanic = detectedMechanic
                Config.Variables.mechanicStartTick = currentTick
                Config.Variables.lastMechanicDetectionTick = currentTick
                Config.Variables.mechanicCount = Config.Variables.mechanicCount + 1
                
                -- Emergency walk logic AFTER mechanic variables are updated
                if Config.Variables.lastMechanic == "pillars" and detectedMechanic == "minions" then
                    if Config.Variables.beamspots and Config.Variables.beamspots[6] then
                        local spot6 = Config.Variables.beamspots[6]
                        local playerCoords = API.PlayerCoord()
                        local distanceToSpot6 = math.sqrt((playerCoords.x - spot6.x)^2 + (playerCoords.y - spot6.y)^2)
                        
                        -- If we're not already at spot 6, move there immediately
                        if distanceToSpot6 > 1.5 then
                            Utils.debugLog("SAFETY: Transitioning from pillars to minions - moving to beamspot 6 to avoid beam death")
                            ---@diagnostic disable-next-line
                            API.DoAction_WalkerW(WPOINT.new(spot6.x, spot6.y, 0))
                        else
                            Utils.debugLog("SAFETY: Already at beamspot 6 during pillars->minions transition")
                        end
                    else
                        Utils.debugLog("WARNING: Pillars to minions transition but no beamspot 6 available")
                    end
                end
                
                    -- Add to history
                table.insert(Config.Variables.mechanicHistory, detectedMechanic)
                if #Config.Variables.mechanicHistory > 5 then
                    table.remove(Config.Variables.mechanicHistory, 1)
                end
                
                -- Get the appropriate rotation for this mechanic
                local newRotation = getRotationForMechanic(detectedMechanic)
                local oldRotation = getRotationForMechanic(Config.Variables.lastMechanic)
                
                -- Transfer state from previous rotation if it exists
                if oldRotation and newRotation and oldRotation ~= newRotation then
                    transferRotationState(oldRotation, newRotation)
                        oldRotation:reset()
                end
                
                -- Reset detection flags based on mechanic type
                if detectedMechanic == "minions" then
                    Config.Variables.minionsDetected = false
                elseif detectedMechanic == "pillars" then
                    Config.Variables.pillarsDetected = false
                elseif detectedMechanic == "arms" then
                    Config.Variables.armsDetected = false
                    Utils.debugLog("Reset arms detection flag for new cycle")
                end
            end

                -- Execute the appropriate rotation for current mechanic
            if Config.Variables.currentMechanic ~= "none" then
                local currentRotation = getRotationForMechanic(Config.Variables.currentMechanic)
                if currentRotation then
                    currentRotation:execute()
                end
                
                -- Execute essential timers during mechanic phases
                Config.Timer.attackMinions:execute()  -- Critical for minions mechanic
                Config.Timer.attackAG:execute()       -- Maintain AG targeting
                Config.Timer.healFamiliar:execute()   -- Keep familiar alive
            end

            -- Handle other mechanics
            self:manageHealth()
            self:managePrayer()
            self:manageBuffs(Config.Buffs)
            Config.Instances.prayerFlicker:update()
            end,
            priority = 6
        },
        {
            name = "Fighting Boss",
            condition = function(self)
                local AG = self.state.location == "Arch-Glacor (Boss Room)" and Utils.find(28241, 1, 20)
                return AG and AG.Life > 0 and not Config.Variables.bossDead and Config.Variables.currentMechanic == "none"
            end,
            execute = function(self)
                logStatusChange("Fighting Boss (Normal)")
                
                -- Execute all fight timers
                Config.Timer.destroyCore:execute()
                Config.Timer.attackAG:execute()
                Config.Timer.attackMinions:execute()
                Config.Timer.vulnBomb:execute()
                Config.Timer.dodgeIce:execute()
                Config.Timer.healFamiliar:execute()
                
                Config.Instances.fightRotation:execute()      -- rotation_manager
                self:manageHealth()
                self:managePrayer()
                self:manageBuffs(Config.Buffs)
                Config.Instances.prayerFlicker:update()
            end,
            priority = 3
        },
        {
            name = "Boss Room Fallback (Maintaining Buffs)",
            condition = function(self)
                local AG = Utils.find(28241, 1, 20)
                local inRoom = self.state.location == "Arch-Glacor (Boss Room)"
                return inRoom and not Config.Variables.bossDead and AG
            end,
            execute = function(self)
                logStatusChange("Boss Room Fallback (Maintaining Buffs)")
                
                -- Essential buff management during transitions
                self:manageHealth()
                self:managePrayer()
                self:manageBuffs(Config.Buffs)
                Config.Instances.prayerFlicker:update()
                
                -- Also run basic timers
                Config.Timer.healFamiliar:execute()
                Config.Timer.attackAG:execute()
            end,
            priority = 1  -- Lowest priority fallback
        },
        -- post fight
        {
            name = "Confirming boss death",
            condition = function(self)
                local AG = Utils.find(28241, 1, 20)
                local AGHealth = AG and AG.Life or 0
                local inRoom = self.state.location == "Arch-Glacor (Boss Room)"
                return inRoom and not Config.Variables.bossDead and AG and (AGHealth == 0)
            end,
            execute = function(self) 
                logStatusChange("Confirming Boss Death")
                self:managePrayer()
                self:manageBuffs(Config.Buffs)
                Config.Instances.prayerFlicker:update()
                Config.Timer.waitForLoot:execute()
            end,
            priority = 25
        },
        {
            name = "Opening chest interface",
            condition = function(self) 
                return Config.Variables.bossDead and self.state.location == "Arch-Glacor (Boss Room)" and not API.Container_Get_Check(906) and not Config.Variables.chestLooted
            end,
            execute = function(self) 
                logStatusChange("Opening Chest Interface")
                Config.Timer.teleportToWars:execute(self)  -- This opens the chest interface
            end,
            priority = 20  -- Higher than chest check so it opens first
        },
        {
            name = "Checking chest for unique items",
            condition = function(self) 
                return Config.Variables.bossDead and self.state.location == "Arch-Glacor (Boss Room)" and not Config.Variables.chestChecked
            end,
            execute = function(self) 
                logStatusChange("Checking Chest for Uniques")
                if Config.Timer.checkChestForUnique:execute() then
                    Config.Variables.chestChecked = true  -- Mark as checked
                end
            end,
            priority = 15  -- After chest is opened
        },
        {
            name = "Claiming loot",
            condition = function(self) 
                return Config.Variables.bossDead and Config.Variables.hasUniqueInChest and self.state.location == "Arch-Glacor (Boss Room)" and not Config.Variables.chestLooted
            end,
            execute = function(self) 
                logStatusChange("Claiming Unique Loot")
                
                Config.Timer.uniqueDropped:execute()
                Config.Timer.claimLoot:execute()
            end,
            priority = 10
        },
        {
            name = "Continuing challenge",
            condition = function(self) 
                return Config.Variables.bossDead and not Config.Variables.hasUniqueInChest and self.state.location == "Arch-Glacor (Boss Room)" and not Config.Variables.chestLooted
            end,
            execute = function(self) 
                logStatusChange("Continuing Challenge")
                Config.Timer.continueChallenge:execute()
            end,
            priority = 10
        },
        {
            name = "Teleport to War's Retreat",
            condition = function(self) 
                return Config.Variables.bossDead and self.state.location ~= "War's Retreat"
            end,
            execute = function(self) 
                logStatusChange("Teleporting to War's Retreat")
                Config.Timer.collectDeath:execute()
                Config.Timer.teleportToWars:execute(self)
                -- Don't reset rotation instances here - wait until actually at War's Retreat
                -- The "Resetting tracked Config.Variables" status will handle the reset properly
            end,
            priority = 5  -- After claim/continue actions
        },
    },
    health = Config.UserInput.healthThreshold,
    prayer = Config.UserInput.prayerThreshold
}

return Config


