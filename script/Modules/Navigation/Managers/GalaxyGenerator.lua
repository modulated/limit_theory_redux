local Words = require("Core.ECS.Words")
local PositionCalculator = require("Modules.CelestialObjects.Managers.UniverseManager.PositionCalculator")

--- The galaxy around the played star system: its star systems as nodes and
--- the jump-gate links between them.
---
--- Only the played system (node 1) is generated in full, by UniverseManager.
--- The other nodes are a name, a seed and a position in the universe: enough
--- to link gates to them now, and to generate them in full when something
--- travels there.
---
--- The links are an undirected graph built in two passes:
---   1. a minimum spanning tree (Prim, on straight-line distance), so every
---      system can be reached from every other;
---   2. extra links from each system to its nearest neighbours, while both
---      ends have fewer than `maxLinksPerSystem` links and the neighbour is no
---      farther than `maxLinkStretch` times the system's nearest one. These
---      give alternative routes without long links across the galaxy.
---
--- Everything is a function of the seed, so a seed always gives the same
--- galaxy.
---@class GalaxyGenerator
local GalaxyGenerator = {}

---@class GalaxySystem
---@field id integer index in `Galaxy.systems`; 1 is the played system
---@field name string
---@field seed integer the seed its star system is generated from
---@field position Position in universe coordinates (the same as StarSystem transforms before rebasing)
---@field links integer[] ids of the links that touch it

---@class GalaxyLink
---@field id integer index in `Galaxy.links`
---@field a integer system id
---@field b integer system id
---@field distance number
---@field inTree boolean part of the spanning tree (removing it would split the galaxy)

---@class Galaxy
---@field systems GalaxySystem[]
---@field links GalaxyLink[]
---@field radius number the universe radius the systems were placed in

local function distance(p, q)
    local dx, dy, dz = p.x - q.x, p.y - q.y, p.z - q.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Place `count - 1` systems around the played one, re-rolling positions that
--- fall too close to a system already placed.
---@param rng RNG
---@param systems GalaxySystem[]
---@param count integer
---@param universe table UniverseScaleConfig.universe
---@param cfg table Config.game.galaxy
local function placeSystems(rng, systems, count, universe, cfg)
    local minDist = universe.radius * (cfg.minSeparation or 0)
    local tries = math.max(1, cfg.placementTries or 1)

    for id = #systems + 1, count do
        local best, bestGap = nil, -1
        for _ = 1, tries do
            local candidate = PositionCalculator.universePosition(
                rng, universe.distributionType, universe.radius,
                universe.gridSpacing, universe.gridJitter, id)
            local gap = math.huge
            for _, other in ipairs(systems) do
                gap = math.min(gap, distance(candidate, other.position))
            end
            -- Keep the roomiest candidate, in case none clears minDist
            if gap > bestGap then
                best, bestGap = candidate, gap
            end
            if gap >= minDist then break end
        end

        systems[id] = {
            id = id,
            name = Words.getCoolName(rng),
            seed = rng:get64(),
            position = best,
            links = {},
        }
    end
end

---@param galaxy Galaxy
---@param a integer
---@param b integer
---@param inTree boolean
local function addLink(galaxy, a, b, inTree)
    local link = {
        id = #galaxy.links + 1,
        a = a,
        b = b,
        distance = distance(galaxy.systems[a].position, galaxy.systems[b].position),
        inTree = inTree,
    }
    galaxy.links[link.id] = link
    table.insert(galaxy.systems[a].links, link.id)
    table.insert(galaxy.systems[b].links, link.id)
end

--- Prim's algorithm on the complete graph; O(n²), fine for tens of systems.
---@param galaxy Galaxy
local function linkSpanningTree(galaxy)
    local systems = galaxy.systems
    local n = #systems
    if n < 2 then return end

    local inTree = { [1] = true }
    local bestDist, bestFrom = {}, {}
    for i = 2, n do
        bestDist[i] = distance(systems[1].position, systems[i].position)
        bestFrom[i] = 1
    end

    for _ = 2, n do
        local next, nextDist = nil, math.huge
        for i = 2, n do
            if not inTree[i] and bestDist[i] < nextDist then
                next, nextDist = i, bestDist[i]
            end
        end
        inTree[next] = true
        addLink(galaxy, bestFrom[next], next, true)

        for i = 2, n do
            if not inTree[i] then
                local d = distance(systems[next].position, systems[i].position)
                if d < bestDist[i] then
                    bestDist[i], bestFrom[i] = d, next
                end
            end
        end
    end
end

---@param galaxy Galaxy
---@param cfg table Config.game.galaxy
local function linkNearestNeighbours(galaxy, cfg)
    local systems = galaxy.systems
    local n = #systems
    local maxLinks = cfg.maxLinksPerSystem or math.huge
    local stretch = cfg.maxLinkStretch or math.huge

    local linked = {}
    local function key(a, b) return a < b and (a * 65536 + b) or (b * 65536 + a) end
    for _, link in ipairs(galaxy.links) do
        linked[key(link.a, link.b)] = true
    end

    for i = 1, n do
        local neighbours = {}
        for j = 1, n do
            if j ~= i then
                table.insert(neighbours, { id = j, d = distance(systems[i].position, systems[j].position) })
            end
        end
        -- Ties broken by id, so the order never depends on the sort's stability
        table.sort(neighbours, function(p, q)
            if p.d ~= q.d then return p.d < q.d end
            return p.id < q.id
        end)

        local nearest = neighbours[1] and neighbours[1].d or 0
        for k = 1, math.min(cfg.nearestLinks or 0, #neighbours) do
            local j = neighbours[k].id
            if neighbours[k].d > nearest * stretch then break end
            if not linked[key(i, j)]
                and #systems[i].links < maxLinks
                and #systems[j].links < maxLinks then
                linked[key(i, j)] = true
                addLink(galaxy, i, j, false)
            end
        end
    end
end

--- Build the galaxy for a seed.
---@param seed integer
---@param home { position: Position, name: string|nil } the played star system
---@param universe table UniverseScaleConfig.universe (where systems are placed)
---@param cfg table Config.game.galaxy
---@return Galaxy
function GalaxyGenerator:generate(seed, home, universe, cfg)
    local rng = RNG.Create(seed)
    assert(rng, "GalaxyGenerator: could not create an RNG")

    local count = rng:getInt(cfg.systemCount.min, cfg.systemCount.max)

    ---@type Galaxy
    local galaxy = { systems = {}, links = {}, radius = universe.radius }
    galaxy.systems[1] = {
        id = 1,
        name = home.name or Words.getCoolName(rng),
        seed = 0, -- the played system already exists; it has its own seed
        position = home.position,
        links = {},
    }

    placeSystems(rng, galaxy.systems, count, universe, cfg)
    linkSpanningTree(galaxy)
    linkNearestNeighbours(galaxy, cfg)
    return galaxy
end

--- The system at the other end of a link.
---@param galaxy Galaxy
---@param link GalaxyLink
---@param from integer system id
---@return GalaxySystem
function GalaxyGenerator:otherEnd(galaxy, link, from)
    return galaxy.systems[link.a == from and link.b or link.a]
end

--- One line per system and its links, for the log.
---@param galaxy Galaxy
---@return string[]
function GalaxyGenerator:describe(galaxy)
    local lines = {}
    for _, system in ipairs(galaxy.systems) do
        local names = {}
        for _, linkId in ipairs(system.links) do
            table.insert(names, self:otherEnd(galaxy, galaxy.links[linkId], system.id).name)
        end
        table.insert(lines, string.format("%2d %-20s -> %s", system.id, system.name, table.concat(names, ", ")))
    end
    return lines
end

return GalaxyGenerator
