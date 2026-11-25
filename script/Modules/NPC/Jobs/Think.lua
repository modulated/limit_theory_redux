local Factions = require("Modules.NPC.Factions")
local Patrolling = require("Modules.NPC.Jobs.Patrolling")
local Marauding = require("Modules.NPC.Jobs.Marauding")
local Transport = require("Modules.NPC.Jobs.Transport")

--- Give an idle pilot its next job (Legacy Actions/Think and CriminalThink,
--- without the economy: they weighed job payouts; here each faction has its
--- trade). Security patrols the stations and gates, pirates maraud near the
--- gates and belts, traders haul between stations.
local Think = {}

--- A random reordering of a list (a copy).
local function shuffled(rng, list)
    local copy = {}
    for i, v in ipairs(list) do copy[i] = v end
    for i = #copy, 2, -1 do
        local j = rng:getInt(1, i)
        copy[i], copy[j] = copy[j], copy[i]
    end
    return copy
end

---@param npc table NpcSystem's record
---@param ctx table NpcSystem
---@return table|nil job an NPC action, nil to stay idle
function Think.chooseJob(npc, ctx)
    local places = ctx.places
    local faction = npc.pilot:getFaction()
    local rng = ctx.rng

    if faction == Factions.Security then
        local nodes = {}
        for _, p in ipairs(places.stations) do nodes[#nodes + 1] = p end
        for _, gate in ipairs(places.gates) do nodes[#nodes + 1] = gate.position end
        if #nodes == 0 then nodes = places.pointsOfInterest end
        if #nodes == 0 then return nil end
        return Patrolling(shuffled(rng, nodes))
    elseif faction == Factions.Pirate then
        local grounds = {}
        for _, gate in ipairs(places.gates) do grounds[#grounds + 1] = gate.position end
        for _, p in ipairs(places.pointsOfInterest) do grounds[#grounds + 1] = p end
        if #grounds == 0 then return nil end
        return Marauding(grounds[rng:getInt(1, #grounds)], 2.5)
    elseif faction == Factions.Trader then
        local stops = shuffled(rng, places.stations)
        if #stops == 0 then stops = shuffled(rng, places.pointsOfInterest) end
        while #stops > 2 do table.remove(stops) end
        local exitGate = #places.gates > 0 and rng:getUniform() < 0.5
            and places.gates[rng:getInt(1, #places.gates)] or nil
        if #stops == 0 and not exitGate then return nil end
        return Transport(stops, exitGate)
    end
    return nil
end

return Think
