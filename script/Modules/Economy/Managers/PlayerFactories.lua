local StockComponent = require("Modules.Economy.Components.StockComponent")
local Economy = require("Modules.Economy.Components")
local CoreComponents = require("Modules.Core.Components")
local Items = require("Shared.Registries.Items")
local Productions = require("Shared.Registries.Productions")
local PlayerWallet = require("Modules.Economy.Managers.PlayerWallet")
local StationTradeSystem = require("Modules.Economy.Systems.StationTradeSystem")
local PlayerStations = require("Modules.Economy.Managers.PlayerStations")

--- The player's own industry: a hangar at every station they have used, and
--- the production lines they have rented there.
---
--- A station rents out `Config.game.factory.rentableLines` of its lines. A
--- rented line runs the recipe the player chose, taking its inputs from the
--- player's hangar at that station and putting the outputs back in it, and
--- the station takes a cut of each finished run (`rentShare` of what the run
--- is worth, at least `rentMinFee`). Holding a lease costs nothing: an unfed
--- line just sits there.
---
--- A rented line needs hands like any other, out of the station's
--- `Workforce`, and the station's own lines claim first
--- (`ProductionSystem:update` runs before this). So a lawless system with no
--- workers has nothing running, the player's line included.
---
--- This lives beside `PlayerWallet` and `PlayerCargo` rather than on the
--- station entities: stations are destroyed and rebuilt when a system is
--- generated again, and a hangar has to outlive that. Everything is keyed by
--- a station key (`system id:station index`), which is stable because a
--- system's stations are built from the system's own seed.
---@class PlayerFactories
local PlayerFactories = {
    ---@type table<string, table>
    stations = {},
}

--- A new game: no hangars, no leases.
function PlayerFactories:reset()
    self.stations = {}
end

--- The player's things at one station, made on demand.
---@param key string
---@return table { hangar = StockComponent, leases = table[], lastTick = number|nil }
function PlayerFactories:at(key)
    local record = self.stations[key]
    if not record then
        record = {
            hangar = StockComponent(Config.game.factory.hangarCapacity),
            leases = {},
        }
        self.stations[key] = record
    end
    return record
end

--- The player's hangar at a station.
---@param key string
---@return StockComponent
function PlayerFactories:hangar(key)
    return self:at(key).hangar
end

--- The lines the player is renting there: `{ id, progress, running, crewed }`.
---@param key string
---@return table[]
function PlayerFactories:leases(key)
    return self:at(key).leases
end

--- How many more lines this station will rent out.
---@param key string
---@return integer
function PlayerFactories:freeLines(key)
    -- At the player's own outpost: the lines its kind has, all theirs
    local lines = PlayerStations.isOwnedKey(key) and PlayerStations:lines(key)
        or Config.game.factory.rentableLines
    return math.max(0, lines - #self:leases(key))
end

--- What a station rents out.
---
--- Not what its own lines are running: a renter fighting the station's floor
--- for the same ore buys dear and sells cheap, which is no business at all.
--- It is the other recipes of the same trades (a refinery rents out
--- refining, a factory manufacturing), the ones a station could tool a spare
--- line for, minus anything too expensive to feed
--- (`production.maxLineInputValue`) and anything that needs no inputs -- a
--- solar array's free energy is the station's own business.
---
--- The list is a few of them (`factory.rentChoices`), chosen by the
--- station's seed, so each station is worth visiting for what it will rent.
---@param station Entity
---@return ProductionDefinition[]
---@param key string|nil the station key (an outpost offers its whole specialisation)
function PlayerFactories:offered(station, key)
    if PlayerStations.isOwnedKey(key) then return PlayerStations:recipes(key) end
    local cached = station.rentOffers
    if cached then return cached end
    local productionCmp = station:get(Economy.Production)
    local own, classes = {}, {}
    for _, recipe in ipairs(productionCmp and productionCmp:getRecipes() or {}) do
        own[recipe.id] = true
        classes[recipe.class] = true
    end

    local limit = Config.game.production.maxLineInputValue
    local candidates = {}
    for _, recipe in ipairs(Productions:getAll()) do
        if classes[recipe.class] and not own[recipe.id] and #recipe.inputs > 0 then
            local value = 0
            for _, entry in ipairs(recipe.inputs) do
                value = value + (entry.item.startEquilibriumPrice
                    or Config.game.trade.defaultPrice) * entry.count
            end
            if value <= limit then candidates[#candidates + 1] = recipe end
        end
    end
    table.sort(candidates, function(a, b) return a.id < b.id end)

    -- A stable few: the station's seed decides where the list starts
    local offers = {}
    local wanted = math.min(Config.game.factory.rentChoices, #candidates)
    if wanted > 0 then
        local seedCmp = station:get(CoreComponents.Seed)
        local seed = seedCmp and seedCmp:getSeed() or 0
        local start = math.floor(math.abs(tonumber(seed) or 0) % #candidates)
        for index = 1, wanted do
            offers[index] = candidates[(start + index - 1) % #candidates + 1]
        end
    end
    station.rentOffers = offers
    return offers
end

--- Rent a line to run `recipeId`: `runs` times (a job, which ends when they
--- are done), or over and over until it is given back (nil).
---@param key string
---@param recipeId integer
---@param runs integer|nil
---@return boolean leased, string|nil reason
function PlayerFactories:lease(key, recipeId, runs)
    if not Productions:getDefinition(recipeId) then return false, "no such recipe" end
    if self:freeLines(key) <= 0 then return false, "this station has no line free" end
    if runs ~= nil and runs < 1 then return false, "no runs" end
    table.insert(self:leases(key), { id = recipeId, progress = 0, running = false, runs = runs })
    return true
end

--- How many runs of a recipe the hangar holds the inputs for.
---@param key string
---@param recipe ProductionDefinition
---@return integer
function PlayerFactories:runsPossible(key, recipe)
    local hangar = self:hangar(key)
    local runs = math.huge
    for _, entry in ipairs(recipe.inputs) do
        runs = math.min(runs, math.floor(hangar:count(entry.item.id) / entry.count))
    end
    if runs == math.huge then return 0 end
    return runs
end

--- Give a line back. Whatever a run in progress had taken is lost, as it
--- would be.
---@param key string
---@param index integer which lease
---@return boolean released
function PlayerFactories:release(key, index)
    local leases = self:leases(key)
    if not leases[index] then return false end
    table.remove(leases, index)
    return true
end

--- What a finished run is worth, at equilibrium prices: what the station's
--- cut is taken from.
---@param recipe ProductionDefinition
---@return number
local function outputValue(recipe)
    local value = 0
    for _, entry in ipairs(recipe.outputs) do
        local price = entry.item.startEquilibriumPrice or Config.game.trade.defaultPrice
        value = value + price * entry.count
    end
    return value
end

--- The station's cut of one run.
---@param recipe ProductionDefinition
---@return integer
---@param key string|nil the station key: the player's own outpost charges nothing
function PlayerFactories:feeFor(recipe, key)
    if PlayerStations.isOwnedKey(key) then return 0 end
    local cfg = Config.game.factory
    return math.max(cfg.rentMinFee, math.ceil(outputValue(recipe) * cfg.rentShare))
end

---@param hangar StockComponent
---@param recipe ProductionDefinition
---@return boolean
local function hasInputs(hangar, recipe)
    for _, entry in ipairs(recipe.inputs) do
        if hangar:count(entry.item.id) < entry.count then return false end
    end
    return true
end

---@param hangar StockComponent
---@param recipe ProductionDefinition
---@return boolean taken
local function takeInputs(hangar, recipe)
    if not hasInputs(hangar, recipe) then return false end
    for _, entry in ipairs(recipe.inputs) do
        hangar:remove(entry.item.id, entry.count)
    end
    return true
end

---@param hangar StockComponent
---@param recipe ProductionDefinition
---@return boolean
local function hasRoomForOutputs(hangar, recipe)
    for _, entry in ipairs(recipe.outputs) do
        if hangar:getRoomFor(entry.item.id) < entry.count then return false end
    end
    return true
end

--- Move the player's rented lines on at one station. Call it after
--- `ProductionSystem:update`, which claims the station's crew for its own
--- lines first.
---@param station Entity the station entity, for its crew and its cut
---@param key string the station key
---@param dt number real seconds
---@return table[] events `{ text = string, good = boolean }` for the player to be told about
function PlayerFactories:update(station, key, dt)
    local events = {}
    local record = self.stations[key]
    if not record or #record.leases == 0 then return events end
    local cfg = Config.game.production
    local scaled = dt * cfg.timeScale
    if scaled <= 0 then return events end

    local hangar = record.hangar
    local workforce = station:get(Economy.Workforce)
    local needed = cfg.workersPerLine

    local index = 1
    while index <= #record.leases do
        local lease = record.leases[index]
        local recipe = Productions:getDefinition(lease.id)
        local released = false
        if recipe then
            lease.crewed = not workforce or workforce:claim(needed)
            local left = lease.crewed and scaled or 0
            -- A long step (coming back to a system) can finish several runs
            while left > 0 do
                if not lease.running then
                    if hasRoomForOutputs(hangar, recipe) and takeInputs(hangar, recipe) then
                        lease.running = true
                        lease.progress = 0
                    else
                        break
                    end
                end
                local remaining = recipe.duration - lease.progress
                if left < remaining then
                    lease.progress = lease.progress + left
                    left = 0
                else
                    left = left - remaining
                    lease.running = false
                    lease.progress = 0
                    -- The station takes its cut of the run; if the credits
                    -- are not there it keeps the goods and the lease ends
                    local fee = self:feeFor(recipe, key)
                    if PlayerWallet:remove(fee, "Factory fee: " .. recipe.displayName) then
                        for _, entry in ipairs(recipe.outputs) do
                            local added = hangar:add(entry.item.id, entry.count)
                            if added < entry.count then
                                StationTradeSystem:deliver(station, entry.item.id, entry.count - added)
                                events[#events + 1] = {
                                    text = string.format("Hangar full: %d %s went to the station",
                                        entry.count - added, entry.item.displayName),
                                }
                            end
                        end
                        -- A job of so many runs ends with its last
                        if lease.runs then
                            lease.runs = lease.runs - 1
                            if lease.runs <= 0 then
                                table.remove(record.leases, index)
                                released = true
                                events[#events + 1] = {
                                    text = string.format("Job done: %s", recipe.displayName),
                                }
                                break
                            end
                        end
                    else
                        for _, entry in ipairs(recipe.outputs) do
                            StationTradeSystem:deliver(station, entry.item.id, entry.count)
                        end
                        table.remove(record.leases, index)
                        released = true
                        events[#events + 1] = {
                            text = string.format("%s: the fee of %d credits went unpaid, the lease is up",
                                recipe.displayName, fee),
                        }
                        break
                    end
                end
            end
        else
            table.remove(record.leases, index)
            released = true
        end
        if not released then index = index + 1 end
    end
    return events
end

--- Credit the time the player was away: a lease keeps working while they are
--- out of the system, up to `Config.game.factory.offlineCatchUpMax` seconds
--- of it. Called when a system is populated again.
---@param station Entity
---@param key string
---@param now number the game's running clock, in seconds
---@return table[] events
function PlayerFactories:catchUp(station, key, now)
    local record = self.stations[key]
    if not record then return {} end
    local last = record.lastTick
    record.lastTick = now
    if not last or #record.leases == 0 then return {} end
    local away = math.min(now - last, Config.game.factory.offlineCatchUpMax)
    if away <= 0 then return {} end
    local workforce = station:get(Economy.Workforce)
    if workforce then workforce:beginTick() end
    return self:update(station, key, away / Config.game.production.timeScale)
end

--- Note that this station is being ticked live, so `catchUp` does not credit
--- the same time twice.
---@param key string
---@param now number
function PlayerFactories:mark(key, now)
    local record = self.stations[key]
    if record then record.lastTick = now end
end

--- The leases at a station, for the docked screen: `{ index, recipe, running,
--- progress, crewed, fee, waiting }`.
---@param key string
---@return table[]
function PlayerFactories:status(key)
    local rows = {}
    for index, lease in ipairs(self:leases(key)) do
        local recipe = Productions:getDefinition(lease.id)
        if recipe then
            local hangar = self:hangar(key)
            rows[#rows + 1] = {
                index = index,
                recipe = recipe,
                running = lease.running,
                progress = recipe.duration > 0 and math.min(1, lease.progress / recipe.duration) or 0,
                crewed = lease.crewed ~= false,
                fee = self:feeFor(recipe, key),
                waiting = not lease.running and not hasInputs(hangar, recipe),
                runs = lease.runs, -- left to make (nil: until stopped)
                hangarFull = not lease.running and not hasRoomForOutputs(hangar, recipe),
            }
        end
    end
    return rows
end

--- What is missing from the hangar for one run of a recipe, in words
--- ("Siderite x4, Energy Cell x2"), or nil when everything is there.
---@param key string
---@param recipe ProductionDefinition
---@return string|nil
function PlayerFactories:missingFor(key, recipe)
    local hangar = self:hangar(key)
    local parts = {}
    for _, entry in ipairs(recipe.inputs) do
        local short = entry.count - hangar:count(entry.item.id)
        if short > 0 then
            parts[#parts + 1] = string.format("%s x%d", entry.item.displayName, short)
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

--- Everything the player has in hangars, for a count on the HUD.
---@return integer stations, integer units
function PlayerFactories:totals()
    local count, units = 0, 0
    for _, record in pairs(self.stations) do
        local total = record.hangar:getTotalUnits()
        if total > 0 or #record.leases > 0 then
            count = count + 1
            units = units + total
        end
    end
    return count, units
end

return PlayerFactories
