---@version 1.0.1
---@author Jared
---@description Hardmode Arch-Glacor combat script - consistent to 2500-3000% enrage
local version = "1.0.1"
local API = require("api")

--[[
    Hardmode AG Script - Works consistently up to 2500-3000% enrage
    Author: Jared

    Features:
    - Auto-loot detection for Frozen core of Leng and Glacor core
    - Optimized rotations for consistent kills up to 3000% enrage
    - Intelligent buff management with incense potency checking
    - Requires 50% hard mode completion

    Changelog:
    - Fixed inventory API calls for latest client
    - Updated buff management conditions
    - Added intelligent incense stick potency detection
]]

local PlayerManager     = require("Arch-Glacor.core.player_manager")        -- file saved in Lua_Scripts\Arch-Glacor\core

local Config            = require("Arch-Glacor.AG.config")              -- file saved in Lua_Scripts\Arch-Glacor\AG
local Utils             = require("Arch-Glacor.AG.utils")               -- file saved in Lua_Scripts\Arch-Glacor\AG

API.Write_fake_mouse_do(false)
local scriptStartTime = os.time()
local playerManager, prayerFlicker = PlayerManager.new(Config.playerManager), Config.Instances.prayerFlicker
---@param number number
local function formatNumber(number)
    -- Handle nil input
    if not number then
        return "0.00"
    end
    -- convert to string and split into whole and decimal parts
    local str = string.format("%.2f", number)
    local whole, decimal = str:match("^(%d+)%.(%d+)$")
    if not whole then
        -- if no decimal, just format the whole number
        return string.format("%d", number):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    end
    -- format the whole number part with commas
    local formatted = string.format("%d", tonumber(whole)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return formatted .. "." .. decimal
end
--#region tracking table generation
local function tracking()
    local currentGp = formatNumber(Config.Variables.totalClaimed)
    local perHour = Utils.valuePerHour(Config.Variables.totalClaimed, scriptStartTime)
    local perHourNumber = tonumber(perHour) or 0
    local gpPerHour = formatNumber(perHourNumber)
    local metrics = {
        { "Jared's Arch-Glacor", "Version: " .. version },
        { "",                "" },
        { "Metrics:",        API.ScriptRuntimeString() },
        { "- Status: ", playerManager.state.status } or {},
        { "- Location: ", playerManager.state.location } or {},
        { "- Total Kills (/hr)",  Config.Variables.killCount .. string.format(" (%s)", Utils.valuePerHour(Config.Variables.killCount, scriptStartTime)) },
        { "- Total Rares (/hr)",  #Config.Data.lootedUniques .. string.format(" (%s)", Utils.valuePerHour(#Config.Data.lootedUniques, scriptStartTime)) },
        { "- Total Claimed (/hr)",     string.format("%s (%s)", currentGp, gpPerHour) },
        { "- Total Seen in Chest",    Utils.formatNumber(Config.Variables.totalSeenInChest) },
        { "",                     "" },
        { "Kill Times:",          "" },
        { "- Fastest Kill:",      Utils.getKillStats(Config.TrackedKills).fastestKillDuration },
        { "- Slowest Kill:",      Utils.getKillStats(Config.TrackedKills).slowestKillDuration },
        { "- Average Kill Time:", Utils.getKillStats(Config.TrackedKills).averageKillDuration }
    }
    -- change this depending on what you want to track whilst debugging
    local trackedDebuggingTables = {
        playerManager:stateTracking(),
        playerManager:managementTracking(),
        playerManager:foodItemsTracking(),
        playerManager:prayerItemsTracking(),
        playerManager:managedBuffsTracking()
    }

    if #Config.Data.lootedUniques > 0 then
        Utils.tableConcat(metrics, { { "", "" } })
        Utils.tableConcat(metrics, { { "Drops:", "" } })
        Utils.tableConcat(metrics, { { "- Name", "Runtime" } })
        Utils.tableConcat(metrics, Config.Data.lootedUniques)
    end

    --view kill details
    if Utils.debug and #Config.TrackedKills > 0 then
        Utils.tableConcat(metrics, { { "", "" } })
        Utils.tableConcat(metrics, { { "Kill Details:", "" } })
        for i, killData in pairs(Config.TrackedKills) do
            Utils.tableConcat(metrics, { { string.format("- [%s] %s", i, killData.runtime), killData.fightDuration } })
        end
    end

    if Utils.debug then 
        for _, table in pairs(trackedDebuggingTables) do
            Utils.tableConcat(metrics, { { "", "" } })
            Utils.tableConcat(metrics, table)
        end
    end

    API.DrawTable(metrics) -- draw table pls
end
--#endregion

--#region main loop
while API.Read_LoopyLoop() do
    playerManager:update()
    if playerManager.state.location ~= "Arch-Glacor (Boss Room)" then prayerFlicker:deactivatePrayer() end
    -- completely optional stats & metrics
    tracking()
    -- very short zzz
    API.RandomSleep2(10, 10, 10)
end
--#endregion
