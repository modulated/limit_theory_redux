local Patrolling = require("Modules.NPC.Jobs.Patrolling")
local Marauding = require("Modules.NPC.Jobs.Marauding")
local Transport = require("Modules.NPC.Jobs.Transport")
local Escort = require("Modules.NPC.Jobs.Escort")

--- Give an idle pilot its next job (Legacy Actions/Think and CriminalThink,
--- without the economy: they weighed job payouts; here each role has its
--- trade). Security patrols the stations and gates; pirates maraud near the
--- gates and belts; traders haul between stations, pirate merchants between
--- hideouts; a guard escorts its charge, and one whose charge is gone takes
--- on an unguarded hauler of its faction, or patrols.
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

local function patrolNodes(places)
    local nodes = {}
    for _, p in ipairs(places.stations) do nodes[#nodes + 1] = p end
    for _, gate in ipairs(places.gates) do nodes[#nodes + 1] = gate.position end
    if #nodes == 0 then
        for _, p in ipairs(places.pointsOfInterest) do nodes[#nodes + 1] = p end
    end
    return nodes
end

--- A hauler's run: two stops of its kind, and maybe out through a gate.
local function transportJob(npc, ctx)
    local places, rng, stats = ctx.places, ctx.rng, npc.pilot.stats
    local pool = {}
    if stats.stops == "hideouts" then
        for _, gate in ipairs(places.gates) do pool[#pool + 1] = gate.position end
        for _, p in ipairs(places.pointsOfInterest) do pool[#pool + 1] = p end
    else
        for _, p in ipairs(places.stations) do pool[#pool + 1] = p end
        if #pool == 0 then
            for _, p in ipairs(places.pointsOfInterest) do pool[#pool + 1] = p end
        end
    end
    local stops = shuffled(rng, pool)
    while #stops > 2 do table.remove(stops) end
    local exitGate = #places.gates > 0 and rng:getUniform() < 0.5
        and places.gates[rng:getInt(1, #places.gates)] or nil
    if #stops == 0 and not exitGate then return nil end
    return Transport(stops, exitGate, stats.stops == "hideouts" and "Smuggling" or "Hauling cargo")
end

---@param npc table NpcSystem's record
---@param ctx table NpcSystem
---@return table|nil job an NPC action, nil to stay idle
function Think.chooseJob(npc, ctx)
    local places, rng = ctx.places, ctx.rng

    -- A guard: its charge, or a new one
    if npc.isGuard then
        if not ctx:isGuarding(npc.charge) then
            npc.charge = ctx:findUnguarded(npc)
            if npc.charge then ctx:assignGuard(npc, npc.charge) end
        end
        if npc.charge then
            return Escort(npc.charge, npc.slot)
        end
        if npc.role == "mercenary" then
            local nodes = patrolNodes(places)
            return #nodes > 0 and Patrolling(shuffled(rng, nodes)) or nil
        end
        npc.isGuard = false -- a pirate with nothing to guard goes marauding
    end

    local stats = npc.pilot.stats
    if npc.role == "security" then
        local nodes = patrolNodes(places)
        return #nodes > 0 and Patrolling(shuffled(rng, nodes)) or nil
    elseif not stats.gunship then
        return transportJob(npc, ctx)
    else
        local grounds = {}
        for _, gate in ipairs(places.gates) do grounds[#grounds + 1] = gate.position end
        for _, p in ipairs(places.pointsOfInterest) do grounds[#grounds + 1] = p end
        if #grounds == 0 then return nil end
        return Marauding(grounds[rng:getInt(1, #grounds)], 2.5)
    end
end

return Think
