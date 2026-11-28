local Items = require("Shared.Registries.Items")
local Productions = require("Shared.Registries.Productions")

--- The economies of the systems the player is not in, kept going cheaply.
---
--- Only the system the player is in exists in full. Every other system the
--- player has been to keeps a ledger of its stations here: what each holds,
--- what it makes, and what it likes to keep on its shelves. Every
--- `Config.game.galaxyEconomy.interval` seconds each of those ledgers moves
--- on by the time gone by:
---
---  * its production lines run, off its own stock (inputs there, outputs
---    below the store's ceiling), as a station's lines do;
---  * what it cannot make trickles in as imports, up to a share of its target
---    (the freighters nobody sees), as StationTradeSystem has it;
---  * NPC trade evens its shelves out: every good drifts toward its target
---    (`settleTime`), which itself wanders by up to `noise` of it (demand
---    comes and goes), so a glut is sold off and a shortage restocked over
---    time, and prices move.
---
--- Prices come from the same scarcity rule the live markets use
--- (StationTradeSystem:basePrice). The market notes (MarketIntel) are kept
--- current from them, so the station screen shows what the markets of nearby
--- systems are doing now, within the datalink's reach. And a station the
--- player comes back to opens with the ledger's shelves, not fresh ones.
---
--- Systems never visited have no stations yet (a system's stations are built
--- with its planets). They get provisional ones instead (`seedGalaxy`), made
--- from the system's seed by the same rules -- what each makes, what it keeps
--- on its shelves, some of the local ore -- and kept going the same way. On
--- the first visit the real stations take the provisional shelves over for
--- every good they deal in too, so the prices carry on.
---@class GalaxyEconomy
local GalaxyEconomy = {
    ---@type table<string, table> station key -> ledger
    stations = {},
    timer = 0,
}

---@return table
local function cfg()
    return Config.game.galaxyEconomy
end

--- A new game: nothing kept.
function GalaxyEconomy:reset()
    self.stations = {}
    self.timer = 0
end

--- Write a station down as it leaves the scene (a jump).
---@param key string
---@param systemId integer
---@param label string
---@param station Entity
---@param now number the game clock
function GalaxyEconomy:record(key, systemId, label, station, now)
    local Economy = require("Modules.Economy.Components")
    local StationTradeSystem = require("Modules.Economy.Systems.StationTradeSystem")
    local stockCmp = station:get(Economy.Stock)
    if not key or not stockCmp then return end
    local ledger = {
        systemId = systemId,
        label = label,
        at = now,
        stock = {},
        target = {},
        recipes = {},
        seed = (self.stations[key] and self.stations[key].seed) or (#key * 7919 + systemId * 104729),
    }
    for _, row in ipairs(StationTradeSystem:listing(station)) do
        ledger.target[row.item.id] = StationTradeSystem:targetStock(station, row.item.id)
    end
    for itemId, units in pairs(stockCmp.units or {}) do
        if units and units > 0 then ledger.stock[itemId] = units end
    end
    local productionCmp = station:get(Economy.Production)
    for _, recipe in ipairs(productionCmp and productionCmp:getRecipes() or {}) do
        ledger.recipes[#ledger.recipes + 1] = { id = recipe.id, acc = 0 }
    end
    self.stations[key] = ledger
end

--- A station that is not in any scene: enough of an entity for the station
--- rules (ProductionSystem:assign, StationTradeSystem:stock) to work on.
---@return table
local function virtualStation()
    local e = { comps = {} }
    function e:add(c) self.comps[getmetatable(c)] = c; return c end
    function e:get(t) return self.comps[t] end
    function e:isValid() return true end
    return e
end

--- Provisional stations for every system that has none kept (never
--- visited), but the one the player is in.
---@param galaxy table|nil
---@param currentSystemId integer
---@param now number
function GalaxyEconomy:seedGalaxy(galaxy, currentSystemId, now)
    if not galaxy or not galaxy.systems then return end
    local kept = {}
    for _, ledger in pairs(self.stations) do kept[ledger.systemId] = true end
    local Economy = require("Modules.Economy.Components")
    local ProductionSystem = require("Modules.Economy.Systems.ProductionSystem")
    local StationTradeSystem = require("Modules.Economy.Systems.StationTradeSystem")
    local ores = require("Shared.Data.OreData").fallback()
    for _, system in ipairs(galaxy.systems) do
        if system.id ~= currentSystemId and not kept[system.id] then
            local rng = RNG.Create((tonumber(system.seed) or system.id) + 7177)
            -- The local ore: a few of the known ores, by their weights
            local oreIds, picked = {}, {}
            local total = 0
            for _, ore in ipairs(ores) do total = total + ore.weight end
            for _ = 1, rng:getInt(2, 4) do
                local roll, acc = rng:getUniform() * total, 0
                for _, ore in ipairs(ores) do
                    acc = acc + ore.weight
                    if roll <= acc then
                        if not picked[ore.id] then picked[ore.id] = true; oreIds[#oreIds + 1] = ore.id end
                        break
                    end
                end
            end
            for i = 1, rng:getInt(1, cfg().provisionalStations or 3) do
                local station = virtualStation()
                station:add(Economy.Stock())
                ProductionSystem:assign(station, rng, i == 1, oreIds)
                StationTradeSystem:stock(station, rng, oreIds)
                local key = string.format("%d:%d", system.id, i)
                self:record(key, system.id, "Station " .. i, station, now)
                self.stations[key].provisional = true
            end
        end
    end
end

--- The player is in a system: its live stations have taken their ledgers
--- (`restore`); provisional ones with no real station to match are dropped,
--- and so are their market notes.
---@param systemId integer
function GalaxyEconomy:dropSystem(systemId)
    local MarketIntel = require("Modules.Economy.Managers.MarketIntel")
    for key, ledger in pairs(self.stations) do
        if ledger.systemId == systemId then
            self.stations[key] = nil
            if ledger.provisional then MarketIntel.stations[key] = nil end
        end
    end
end

--- A station built again (the player is back): it takes the ledger's
--- shelves, moved on to now. Returns whether there was a ledger.
---@param key string
---@param station Entity
---@param now number
---@return boolean
function GalaxyEconomy:restore(key, station, now)
    local ledger = key and self.stations[key]
    if not ledger then return false end
    local Economy = require("Modules.Economy.Components")
    local stockCmp = station:get(Economy.Stock)
    if not stockCmp then return false end
    self:advance(ledger, now)
    if ledger.provisional then
        -- The real station deals in its own goods: it takes the provisional
        -- shelves of those it shares, and keeps its own of the rest
        local StationTradeSystem = require("Modules.Economy.Systems.StationTradeSystem")
        for itemId, units in pairs(ledger.stock) do
            if StationTradeSystem:trades(station, itemId) then
                stockCmp.units[itemId] = math.floor(units)
            end
        end
    else
        stockCmp.units = {}
        for itemId, units in pairs(ledger.stock) do
            stockCmp.units[itemId] = math.floor(units)
        end
    end
    require("Modules.Economy.Systems.StationTradeSystem"):invalidate(station)
    -- The station is live again: the ledger goes until it leaves
    self.stations[key] = nil
    return true
end

--- A small, repeatable noise for a ledger: -1..1.
---@param ledger table
---@return number
local function noise(ledger)
    -- MINSTD: exact in doubles
    ledger.seed = (math.max(1, math.floor(ledger.seed)) * 48271) % 2147483647
    return (ledger.seed / 2147483647) * 2 - 1
end

--- Move a ledger on from its time to `now`.
---@param ledger table
---@param now number
function GalaxyEconomy:advance(ledger, now)
    local dt = math.min(now - (ledger.at or now), cfg().maxCatchUp)
    ledger.at = now
    if dt <= 0 then return end
    local trade = Config.game.trade
    local production = Config.game.production
    local stock = ledger.stock

    -- Production: the lines run off the station's own stock
    local made = {}
    for _, line in ipairs(ledger.recipes) do
        local recipe = Productions:getDefinition(line.id)
        if recipe and recipe.duration > 0 then
            for _, entry in ipairs(recipe.outputs) do made[entry.item.id] = true end
            line.acc = (line.acc or 0) + dt * production.timeScale / recipe.duration
            local runs = math.floor(line.acc)
            line.acc = line.acc - runs
            for _ = 1, math.min(runs, cfg().maxRunsPerStep) do
                local ok = true
                for _, entry in ipairs(recipe.inputs) do
                    if (stock[entry.item.id] or 0) < entry.count then ok = false break end
                end
                for _, entry in ipairs(recipe.outputs) do
                    local target = ledger.target[entry.item.id]
                    if target and (stock[entry.item.id] or 0) >= target * production.stockCeiling then
                        ok = false
                    end
                end
                if not ok then break end
                for _, entry in ipairs(recipe.inputs) do
                    stock[entry.item.id] = stock[entry.item.id] - entry.count
                end
                for _, entry in ipairs(recipe.outputs) do
                    if ledger.target[entry.item.id] then
                        stock[entry.item.id] = (stock[entry.item.id] or 0) + entry.count
                    end
                end
            end
        end
    end

    -- Imports and NPC trade, good by good
    local settle = 1 - math.exp(-dt / cfg().settleTime)
    for itemId, target in pairs(ledger.target) do
        local held = stock[itemId] or 0
        if not made[itemId] then
            local ceiling = target * trade.importFloor
            if held < ceiling then held = math.min(ceiling, held + trade.importPerSecond * dt) end
        end
        -- Toward the target, off it by a slow random walk of the good's own
        -- (demand comes and goes), so prices wander over hours
        ledger.drift = ledger.drift or {}
        local drift = (ledger.drift[itemId] or 0) + cfg().noise * math.sqrt(dt / 3600) * noise(ledger)
        drift = math.max(-cfg().noise, math.min(cfg().noise, drift))
        ledger.drift[itemId] = drift
        local aim = target * (1 + drift)
        held = held + (aim - held) * settle
        stock[itemId] = math.max(0, held)
    end
end

--- What a ledger's station would ask and bid for an item now (the live
--- markets' scarcity rule, the station's spread either side).
---@param ledger table
---@param itemId integer
---@return number|nil bid, number|nil ask
function GalaxyEconomy:quote(ledger, itemId)
    local trade = Config.game.trade
    local target = ledger.target[itemId]
    if not target then return nil, nil end
    local def = Items:getDefinition(itemId)
    local base = def and def.startEquilibriumPrice or trade.defaultPrice
    local units = ledger.stock[itemId] or 0
    local scarcity = (target + trade.priceSoftness) / (units + trade.priceSoftness)
    scarcity = math.max(trade.minScarcity, math.min(trade.maxScarcity, scarcity))
    local price = base * scarcity
    local half = trade.spread * 0.5
    local bid = math.max(1, math.floor(price * (1 - half)))
    local ask = math.max(bid + 1, math.ceil(price * (1 + half)))
    -- Nothing on the shelves: nothing to sell
    if units < 1 then ask = nil end
    return bid, ask
end

--- Each frame: every so often, move every ledger on and refresh what the
--- market notes say of it.
---@param dt number
---@param now number the game clock
---@param currentSystemId integer the system that is live (its stations have no ledger)
function GalaxyEconomy:update(dt, now, currentSystemId)
    self.timer = self.timer - dt
    if self.timer > 0 then return end
    self.timer = cfg().interval
    local MarketIntel = require("Modules.Economy.Managers.MarketIntel")
    for key, ledger in pairs(self.stations) do
        if ledger.systemId ~= currentSystemId then
            self:advance(ledger, now)
            local quotes = {}
            for itemId in pairs(ledger.target) do
                local bid, ask = self:quote(ledger, itemId)
                if bid or ask then quotes[itemId] = { bid = bid, ask = ask } end
            end
            MarketIntel.stations[key] = {
                systemId = ledger.systemId,
                label = ledger.label,
                at = now,
                quotes = quotes,
            }
        end
    end
end

--- For a save.
---@return table
function GalaxyEconomy:snapshot()
    return { stations = self.stations }
end

--- From a save.
---@param state table|nil
function GalaxyEconomy:restoreState(state)
    self.stations = (state and state.stations) or {}
    self.timer = 0
end

return GalaxyEconomy
