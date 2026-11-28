local Items = require("Shared.Registries.Items")
local Productions = require("Shared.Registries.Productions")

--- The player's own stations: outposts deployed from a kit at an orbital
--- slot or on an asteroid belt.
---
--- Each is a record here, not an entity: the entities go with their system
--- on a jump and are built again from these records when the player comes
--- back (LimitTheoryRedux:spawnPlayerStations), as the generated stations are
--- built again from their system's seed. A record keeps where the station
--- stands (its position, saved, so nothing about it depends on the slot
--- arithmetic staying the same), what kind it is, and what it has earned.
---
--- Everything else of the player's at an outpost is filed under its key,
--- `p:<id>`, like a generated station's: the hangar and the lines
--- (PlayerFactories), the orders (MarketSystem). What an outpost changes is
--- who the market and the lines belong to:
---
---   * the lines are the owner's own -- as many as the kind has, any recipe of
---     its specialisation, and no fee (PlayerFactories asks here);
---   * the market is the owner's orders and nothing else. NPCs that are not
---     hostile to the player come and trade on it: miners sell into the
---     owner's bids, traders buy the owner's listings. The owner pays no
---     broker fee or sales tax there, and the tax an NPC pays on a sale is the
---     owner's (MarketSystem).
---@class PlayerStations
local PlayerStations = {
    ---@type table<integer, PlayerStation>
    stations = {},
    nextId = 1,
}

---@class PlayerStation
---@field id integer
---@field kind string a key of Config.game.outposts.kinds
---@field name string
---@field systemId integer
---@field anchorId string the slot it was deployed at ("o:2:3", "b:1:5")
---@field position table { x, y, z }
---@field income table { taxes, sales, purchases } credits, all told

--- The key everything of the player's at an outpost is filed under.
---@param id integer
---@return string
function PlayerStations.keyOf(id)
    return "p:" .. tostring(id)
end

--- Whether a station key is an outpost's.
---@param key string|nil
---@return boolean
function PlayerStations.isOwnedKey(key)
    return type(key) == "string" and key:sub(1, 2) == "p:"
end

--- A new game: none.
function PlayerStations:reset()
    self.stations = {}
    self.nextId = 1
end

---@param key string|nil
---@return PlayerStation|nil
function PlayerStations:byKey(key)
    if not PlayerStations.isOwnedKey(key) then return nil end
    return self.stations[tonumber(key:sub(3))]
end

--- The outposts in one star system, by id.
---@param systemId integer
---@return PlayerStation[]
function PlayerStations:inSystem(systemId)
    local list = {}
    for _, station in pairs(self.stations) do
        if station.systemId == systemId then list[#list + 1] = station end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

--- All of them, by id.
---@return PlayerStation[]
function PlayerStations:all()
    local list = {}
    for _, station in pairs(self.stations) do list[#list + 1] = station end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

------------------------------------------------------------------------------
-- Kinds
------------------------------------------------------------------------------

--- A kind's configuration.
---@param kind string
---@return table|nil
function PlayerStations.kindOf(kind)
    return Config.game.outposts.kinds[kind]
end

--- The kit item a kind is deployed from.
---@param kind string
---@return ItemDefinition|nil
function PlayerStations.kitOf(kind)
    local cfg = PlayerStations.kindOf(kind)
    return cfg and Items:getByName(cfg.kit) or nil
end

--- How many production lines the outpost at `key` has (0: not an outpost).
---@param key string
---@return integer
function PlayerStations:lines(key)
    local station = self:byKey(key)
    local cfg = station and PlayerStations.kindOf(station.kind)
    return cfg and cfg.lines or 0
end

--- What the outpost at `key` can make: every recipe of its specialisation
--- that has inputs (a solar array's free energy needs no outpost), by id.
---@param key string
---@return ProductionDefinition[]
function PlayerStations:recipes(key)
    local station = self:byKey(key)
    local cfg = station and PlayerStations.kindOf(station.kind)
    if not cfg then return {} end
    local classes = {}
    for _, class in ipairs(cfg.classes or {}) do classes[class] = true end
    local list = {}
    for _, recipe in ipairs(Productions:getAll()) do
        if classes[recipe.class] and #recipe.inputs > 0 then list[#list + 1] = recipe end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

------------------------------------------------------------------------------
-- Deploying
------------------------------------------------------------------------------

--- Record a new outpost. The caller has spent the kit and builds the entity.
---@param kind string
---@param systemId integer
---@param anchor table { id, position, label }
---@param systemName string|nil for its name
---@return PlayerStation|nil
function PlayerStations:deploy(kind, systemId, anchor, systemName)
    local cfg = PlayerStations.kindOf(kind)
    if not cfg then return nil end
    local id = self.nextId
    self.nextId = id + 1
    local p = anchor.position
    local station = {
        id = id,
        kind = kind,
        name = string.format("%s %s", systemName or "System", cfg.name),
        systemId = systemId,
        anchorId = anchor.id,
        position = { x = p.x, y = p.y, z = p.z },
        income = { taxes = 0, sales = 0, purchases = 0 },
    }
    -- Two of a kind in one system are told apart by number
    local same = 0
    for _, other in pairs(self.stations) do
        if other.systemId == systemId and other.kind == kind then same = same + 1 end
    end
    if same > 0 then station.name = string.format("%s %d", station.name, same + 1) end
    self.stations[id] = station
    return station
end

--- Note what the owner earned or spent at an outpost's market.
---@param key string
---@param kind string "taxes", "sales" or "purchases"
---@param amount number
function PlayerStations:recordIncome(key, kind, amount)
    local station = self:byKey(key)
    if not station or not amount or amount == 0 then return end
    station.income[kind] = (station.income[kind] or 0) + amount
end

------------------------------------------------------------------------------
-- Where they may stand
------------------------------------------------------------------------------

---@param entity Entity
---@return table|nil pos, number radius
local function placeOf(entity)
    if not entity or not entity:isValid() then return nil, 0 end
    local PhysicsComponents = require("Modules.Physics.Components")
    local rbCmp = entity:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    if body then return body:getPos(), body:getBoundingRadius() end
    local transform = entity:get(PhysicsComponents.Transform)
    if transform then return transform:getPos(), transform:getScale() end
    return nil, 0
end

---@param a table
---@param b table
---@return number
local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- The slots an outpost may be deployed at in the system the game is in:
--- `orbitSlots` around each planet on the ring the generated stations use,
--- and `beltSlots` along each asteroid belt. A slot within `minSpacing` of a
--- station, an outpost or a gate is taken. Each has a stable id (the planet's
--- or the belt's place and the slot's number): a system is generated the
--- same every time.
---@param game table LimitTheoryRedux
---@return table[] { id, kind ("orbit"|"belt"), parent (Entity), parentName, position, free }
function PlayerStations:anchors(game)
    local cfg = Config.game.outposts
    local sceneCfg = game.cfg or {}
    local anchors = {}

    -- What a slot must keep clear of
    local occupied = {}
    for _, station in ipairs(game.stations or {}) do
        local pos = placeOf(station)
        if pos then occupied[#occupied + 1] = pos end
    end
    for _, record in pairs(self.stations) do
        if record.systemId == game.currentSystemId then occupied[#occupied + 1] = record.position end
    end
    for _, gate in ipairs(game.jumpGates or {}) do
        if gate.position then occupied[#occupied + 1] = gate.position end
    end
    local function free(pos)
        for _, other in ipairs(occupied) do
            if distance(pos, other) < cfg.minSpacing then return false end
        end
        return true
    end

    -- Around each planet, on the generated stations' ring
    local orbitMult = sceneCfg.stationOrbitMult or 2.5
    for planetIndex, planet in ipairs(game.planets or {}) do
        local center, radius = placeOf(planet)
        if center then
            local ring = radius * orbitMult
            for slot = 1, cfg.orbitSlots do
                -- Offset half a step from the generated stations' angles
                local angle = (slot - 0.5) * 2 * math.pi / cfg.orbitSlots
                local pos = { x = center.x + math.cos(angle) * ring, y = center.y,
                              z = center.z + math.sin(angle) * ring }
                anchors[#anchors + 1] = {
                    id = string.format("o:%d:%d", planetIndex, slot),
                    kind = "orbit", parent = planet, parentIndex = planetIndex,
                    position = pos, free = free(pos),
                }
            end
        end
    end

    -- Along each belt, around the star
    local starPos = placeOf(game.starEntity) or { x = 0, y = 0, z = 0 }
    local CelestialComponents = require("Modules.CelestialObjects.Components")
    for beltIndex, belt in ipairs(game.beltEntities or {}) do
        local beltCmp = belt:isValid() and belt:get(CelestialComponents.AsteroidBelt)
        local ring = beltCmp and beltCmp:getOrbitRadius()
        if ring and ring > 0 then
            for slot = 1, cfg.beltSlots do
                local angle = (slot - 1) * 2 * math.pi / cfg.beltSlots
                local pos = { x = starPos.x + math.cos(angle) * ring, y = starPos.y,
                              z = starPos.z + math.sin(angle) * ring }
                anchors[#anchors + 1] = {
                    id = string.format("b:%d:%d", beltIndex, slot),
                    kind = "belt", parent = belt, parentIndex = beltIndex,
                    position = pos, free = free(pos),
                }
            end
        end
    end
    return anchors
end

--- The nearest free slot of one planet or belt to a position.
---@param game table
---@param parent Entity the planet or belt
---@param from table position
---@return table|nil anchor
function PlayerStations:nearestFreeAnchor(game, parent, from)
    local best, bestDistance = nil, math.huge
    for _, anchor in ipairs(self:anchors(game)) do
        if anchor.free and anchor.parent and parent and anchor.parent.id == parent.id then
            local d = distance(anchor.position, from)
            if d < bestDistance then best, bestDistance = anchor, d end
        end
    end
    return best
end

------------------------------------------------------------------------------
-- Saving
------------------------------------------------------------------------------

---@return table
function PlayerStations:snapshot()
    local stations = {}
    for id, station in pairs(self.stations) do
        stations[#stations + 1] = {
            id = id, kind = station.kind, name = station.name, systemId = station.systemId,
            anchorId = station.anchorId,
            position = { x = station.position.x, y = station.position.y, z = station.position.z },
            income = { taxes = station.income.taxes or 0, sales = station.income.sales or 0,
                       purchases = station.income.purchases or 0 },
            defense = station.defense and {
                hull = station.defense.hull, shield = station.defense.shield,
                destroyed = station.defense.destroyed,
            } or nil,
        }
    end
    table.sort(stations, function(a, b) return a.id < b.id end)
    return { stations = stations, nextId = self.nextId }
end

---@param saved table|nil
function PlayerStations:restore(saved)
    self:reset()
    if not saved then return end
    for _, station in ipairs(saved.stations or {}) do
        if PlayerStations.kindOf(station.kind) then
            station.income = station.income or { taxes = 0, sales = 0, purchases = 0 }
            self.stations[station.id] = station
        else
            Log.Warn("PlayerStations: a saved outpost of an unknown kind (%s) was left out", tostring(station.kind))
        end
    end
    self.nextId = math.max(saved.nextId or 1, 1)
end

return PlayerStations
