local ffi = require("ffi")
local SaveFile = require("Shared.Save.SaveFile")
local Reputation = require("Modules.NPC.Reputation")
local PlayerWallet = require("Modules.Economy.Managers.PlayerWallet")
local PlayerCargo = require("Modules.Economy.Managers.PlayerCargo")
local PlayerFactories = require("Modules.Economy.Managers.PlayerFactories")
local MarketIntel = require("Modules.Economy.Managers.MarketIntel")
local MarketSystem = require("Modules.Economy.Systems.MarketSystem")
local PlayerFleet = require("Modules.Constructs.Managers.PlayerFleet")
local StockComponent = require("Modules.Economy.Components.StockComponent")
local PlayerStations = require("Modules.Economy.Managers.PlayerStations")

--- What a saved game holds, and putting it back.
---
--- A game is mostly made again rather than read back: the galaxy and every
--- star system in it are generated from the game's seed, the NPC ships from
--- each system's hostility. So a save keeps what cannot be generated -- what
--- the player has done and owns -- and the seed that makes the rest:
---
---   game        the scenario, the seed, the system, the clock, the course,
---               the factions the player chose to turn against
---   player      where the ship is (and the station it is docked at)
---   wallet, cargo, fleet, reputation
---   factories   every hangar and leased line, by station key
---   orders      the player's market orders, by station key, escrow and all
---   intel       what is known of the markets within reach
---   stations    the stock of the stations in the system the player is in
---   structures  the player's own stations (PlayerStations, when present)
---
--- Loading runs the game's own paths rather than a third way of building a
--- world: a new game from the saved seed and scenario, with the persistent
--- state put back between its reset and its first build (so the ship is
--- built in the saved hull), and then, for a save in another system, the
--- rebuild a jump does, into that system.
---
--- `schema` is the version of this layout; MIGRATIONS[n] brings a save at
--- schema n up to n + 1, so an old save is upgraded rather than refused.
---@class SaveGame
local SaveGame = {}

SaveGame.SCHEMA = 1

--- schema n -> n + 1, applied in order to an older save's state.
---@type table<integer, fun(state: table)>
SaveGame.MIGRATIONS = {}

--- The slots, in the order the screens list them.
SaveGame.SLOTS = { "quicksave", "autosave", "slot1", "slot2", "slot3", "slot4", "slot5" }
SaveGame.SLOT_NAMES = {
    quicksave = "Quicksave", autosave = "Autosave",
    slot1 = "Slot 1", slot2 = "Slot 2", slot3 = "Slot 3", slot4 = "Slot 4", slot5 = "Slot 5",
}
--- The slots a player saves into by choice (not the automatic two).
SaveGame.MANUAL_SLOTS = { "slot1", "slot2", "slot3", "slot4", "slot5" }

------------------------------------------------------------------------------
-- Plain copies
------------------------------------------------------------------------------

--- A deep copy of plain data. Anything that is not data is left out with a
--- warning rather than poisoning the save (the codec would refuse it).
---@param value any
---@param path string|nil
---@return any
local function copy(value, path)
    local kind = type(value)
    if kind ~= "table" then
        if kind == "function" or kind == "userdata" or kind == "cdata" or kind == "thread" then
            Log.Warn("SaveGame: %s is a %s; not saved", path or "value", kind)
            return nil
        end
        return value
    end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v, (path or "value") .. "." .. tostring(k)) end
    return out
end
SaveGame.copy = copy

---@param stock StockComponent|nil
---@return table|nil
local function stockOut(stock)
    if not stock then return nil end
    local units = {}
    for itemId, n in pairs(stock.units or {}) do
        if n and n > 0 then units[itemId] = n end
    end
    return { units = units, capacity = stock.capacity }
end

---@param saved table|nil
---@param capacity number|nil the capacity it should have if the save has none
---@return StockComponent
local function stockIn(saved, capacity)
    local stock = StockComponent(saved and saved.capacity or capacity)
    for itemId, n in pairs(saved and saved.units or {}) do stock.units[itemId] = n end
    return stock
end

------------------------------------------------------------------------------
-- Seeds: 64-bit integers, kept exactly
------------------------------------------------------------------------------

--- A game's seed is a uint64 from the engine's RNG. A double would round
--- anything past 2^53 and generate a different galaxy, so it is kept as its
--- two 32-bit halves. (A seed that is a plain number -- a fixed test seed --
--- is kept as one.)
---@param seed any
---@return table
function SaveGame.packSeed(seed)
    if type(seed) == "number" then return { n = seed } end
    local hi = tonumber(seed / 4294967296ULL)
    local lo = tonumber(seed % 4294967296ULL)
    return { hi = hi, lo = lo }
end

---@param packed table
---@return any seed
function SaveGame.unpackSeed(packed)
    if packed.n then return packed.n end
    return ffi.cast("uint64_t", packed.hi) * 4294967296ULL + ffi.cast("uint64_t", packed.lo)
end

------------------------------------------------------------------------------
-- Taking a save
------------------------------------------------------------------------------

--- The player's orders: those waiting at stations out of the scene, and
--- copies of those in the books of the stations in it (filed as if waiting,
--- which is how a loaded game finds them).
---@param game table
---@return table<string, table[]>
local function ordersOut(game)
    local orders = copy(MarketSystem.parked) or {}
    local places = game.npcs and game.npcs.places
    for _, dock in ipairs(places and places.docks or {}) do
        if dock.entity and dock.entity:isValid() and dock.key then
            local list = orders[dock.key] or {}
            for _, order in ipairs(MarketSystem:playerOrders(dock.entity)) do
                local saved = copy(order)
                saved.id = nil
                list[#list + 1] = saved
            end
            if #list > 0 then orders[dock.key] = list end
        end
    end
    -- Ids are per book: a loaded book gives fresh ones
    for _, list in pairs(orders) do
        for _, order in ipairs(list) do order.id = nil end
    end
    return orders
end

--- The stock of the stations in the scene, by key.
---@param game table
---@return table<string, table>
local function stationsOut(game)
    local EconomyComponents = require("Modules.Economy.Components")
    local out = {}
    local places = game.npcs and game.npcs.places
    for _, dock in ipairs(places and places.docks or {}) do
        local stock = dock.entity and dock.entity:isValid() and dock.entity:get(EconomyComponents.Stock)
        if stock and dock.key then out[dock.key] = stockOut(stock) end
    end
    return out
end

--- Where the player's ship is, and which way it faces.
---@param game table
---@return table
local function playerOut(game)
    local out = { docked = game.docked and game.docked.key or nil }
    local ship = game.playerShip
    local PhysicsComponents = require("Modules.Physics.Components")
    local rbCmp = ship and ship:isValid() and ship:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    if body then
        local p = body:getPos()
        local f = body:getRot():getForward()
        out.position = { x = p.x, y = p.y, z = p.z }
        out.forward = { x = f.x, y = f.y, z = f.z }
    end
    return out
end

--- Everything a save keeps of a game.
---@param game table LimitTheoryRedux
---@return table state
function SaveGame.capture(game)
    -- The ship's fit as it is now, not as it was last refitted
    if game.playerShip then PlayerFleet:record(game.playerShip) end

    local factories = {}
    for key, record in pairs(PlayerFactories.stations or {}) do
        factories[key] = {
            hangar = stockOut(record.hangar),
            leases = copy(record.leases, "leases"),
            lastTick = record.lastTick,
        }
    end

    return {
        schema = SaveGame.SCHEMA,
        game = {
            scenario = game.startScenarioId,
            seed = SaveGame.packSeed(game.seed),
            system = game.currentSystemId or 1,
            time = game.simTime or 0,
            course = copy(game.course),
            hostilityAccepted = copy(game.hostilityAccepted) or {},
        },
        player = playerOut(game),
        wallet = { balance = PlayerWallet.balance },
        cargo = stockOut(PlayerCargo:get()),
        fleet = {
            ships = copy(PlayerFleet.ships, "fleet"),
            nextId = PlayerFleet.nextId,
            activeId = PlayerFleet.activeId,
        },
        reputation = copy(Reputation.standing),
        factories = factories,
        orders = ordersOut(game),
        intel = copy(MarketIntel.stations, "intel"),
        stations = stationsOut(game),
        structures = PlayerStations:snapshot(),
    }
end

--- What the list of saves shows of one.
---@param game table
---@param slot string
---@return table meta
function SaveGame.summary(game, slot)
    local system = game.galaxy and game.galaxy.systems[game.currentSystemId]
    local ship = PlayerFleet:active()
    return {
        slot = slot,
        savedAt = os.time(),
        playTime = math.floor(game.simTime or 0),
        system = system and system.name or "Start system",
        docked = game.docked and game.docked.label or nil,
        credits = PlayerWallet.balance,
        ship = ship and ship.name or nil,
        gameVersion = Config.gameVersion,
        schema = SaveGame.SCHEMA,
    }
end

------------------------------------------------------------------------------
-- Putting one back
------------------------------------------------------------------------------

--- Bring an older save's state up to this version.
---@param state table
---@return boolean ok
---@return string|nil problem
function SaveGame.migrate(state)
    local schema = state.schema or 0
    if schema > SaveGame.SCHEMA then
        return false, string.format("made by a newer version (schema %d; this reads up to %d)",
            schema, SaveGame.SCHEMA)
    end
    while schema < SaveGame.SCHEMA do
        local step = SaveGame.MIGRATIONS[schema]
        if not step then return false, "no way to upgrade a save of schema " .. schema end
        step(state)
        schema = schema + 1
        state.schema = schema
    end
    return true
end

--- Put back what the player owns and has done. Runs between a new game's
--- reset (resetGalaxy) and its first build, so everything built after --
--- the ship above all -- is built from it.
---@param game table
---@param state table
function SaveGame.restoreManagers(game, state)
    local g = state.game or {}
    game.simTime = g.time or 0
    game.course = copy(g.course)
    game.hostilityAccepted = copy(g.hostilityAccepted) or {}

    if state.reputation then
        for faction, value in pairs(state.reputation) do Reputation.standing[faction] = value end
    end
    if state.wallet then PlayerWallet.balance = state.wallet.balance or PlayerWallet.balance end
    if state.cargo then
        PlayerCargo.stock = stockIn(state.cargo, Config.game.cargo.holdCapacity)
    end
    if state.fleet and state.fleet.ships then
        PlayerFleet.ships = {}
        for id, ship in pairs(state.fleet.ships) do PlayerFleet.ships[tonumber(id) or id] = copy(ship) end
        PlayerFleet.nextId = state.fleet.nextId or PlayerFleet.nextId
        PlayerFleet.activeId = state.fleet.activeId
    end
    PlayerFactories.stations = {}
    for key, record in pairs(state.factories or {}) do
        PlayerFactories.stations[key] = {
            hangar = stockIn(record.hangar, Config.game.factory.hangarCapacity),
            leases = copy(record.leases) or {},
            lastTick = record.lastTick,
        }
    end
    MarketSystem.parked = copy(state.orders) or {}
    MarketIntel.stations = copy(state.intel) or {}
    -- The stations of the saved system get their stock back as they are
    -- built (LimitTheoryRedux:applySavedStationStock)
    game.savedStationStock = copy(state.stations) or {}

    PlayerStations:restore(state.structures)
end

------------------------------------------------------------------------------
-- Slots on disk
------------------------------------------------------------------------------

---@return string
function SaveGame.directory()
    local dir = (Config.paths and Config.paths.files or "./") .. "saves/"
    if Directory and Directory.Create then Directory.Create(dir) end
    return dir
end

---@param slot string
---@return string
function SaveGame.path(slot)
    return SaveGame.directory() .. slot .. ".ltrsave"
end

--- Save the game into a slot.
---@param game table
---@param slot string
---@return boolean ok
---@return string|nil problem
function SaveGame.save(game, slot)
    local okCapture, state = pcall(SaveGame.capture, game)
    if not okCapture then return false, "could not gather the game: " .. tostring(state) end
    SaveGame.invalidate()
    return SaveFile.write(SaveGame.path(slot), SaveGame.summary(game, slot), state)
end

--- Read a slot.
---@param slot string
---@return table|nil meta
---@return table|string state or the problem
---@return boolean|nil fromBackup
function SaveGame.read(slot)
    local meta, state, fromBackup = SaveFile.read(SaveGame.path(slot))
    if not meta then return nil, state end
    local ok, problem = SaveGame.migrate(state)
    if not ok then return nil, problem end
    return meta, state, fromBackup
end

--- Every slot's summary (nil where it is empty), for the screens.
---@return table[] { slot, name, meta|nil, problem|nil }
function SaveGame.list()
    local rows = {}
    for _, slot in ipairs(SaveGame.SLOTS) do
        local meta, problem = SaveFile.readMeta(SaveGame.path(slot))
        rows[#rows + 1] = {
            slot = slot,
            name = SaveGame.SLOT_NAMES[slot],
            meta = meta,
            problem = meta == nil and problem ~= "no file" and problem or nil,
        }
    end
    return rows
end

--- The slot list as the screens show it: read once and kept until a save is
--- written (the screens draw every frame; the disk is read when it changed).
---@type table[]|nil
SaveGame.cached = nil

---@return table[]
function SaveGame.listCached()
    if not SaveGame.cached then SaveGame.cached = SaveGame.list() end
    return SaveGame.cached
end

--- Forget the cached list (a save was written, or a screen opened).
function SaveGame.invalidate()
    SaveGame.cached = nil
end

--- The most recent save in any slot, for Continue.
---@return string|nil slot
function SaveGame.latest()
    local best, bestAt = nil, -1
    for _, row in ipairs(SaveGame.listCached()) do
        if row.meta and (row.meta.savedAt or 0) > bestAt then
            best, bestAt = row.slot, row.meta.savedAt or 0
        end
    end
    return best
end

--- A save's summary in two lines, for the screens: where it was, then
--- what the player had and when.
---@param meta table|nil
---@return string where
---@return string what
function SaveGame.describeLines(meta)
    if not meta then return "Empty", "" end
    local where = meta.system or "?"
    if meta.docked then where = where .. "  ·  docked at " .. meta.docked end
    local parts = {}
    if meta.credits then
        local digits = tostring(math.floor(meta.credits)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
        parts[#parts + 1] = (digits:gsub("^,", "")) .. " cr"
    end
    if meta.ship then parts[#parts + 1] = meta.ship end
    local t = meta.playTime or 0
    parts[#parts + 1] = string.format("%dh %02dm played", math.floor(t / 3600), math.floor(t / 60) % 60)
    if meta.savedAt then parts[#parts + 1] = os.date("%Y-%m-%d %H:%M", meta.savedAt) end
    return where, table.concat(parts, "  ·  ")
end

--- A save's summary in one line.
---@param meta table|nil
---@return string
function SaveGame.describe(meta)
    if not meta then return "Empty" end
    local where, what = SaveGame.describeLines(meta)
    return where .. "  ·  " .. what
end

return SaveGame
