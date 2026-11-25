--[[----------------------------------------------------------------------------
  economy-sim: run the game's economy without the game.

  It loads the real `Config.game` (GameConfig.lua), the real item and
  production registries, and the real `StationTradeSystem` and
  `ProductionSystem`, then steps a model of a star system: a few stations
  making things and trading, miners bringing ore in, and optionally a trader
  arbitraging between the stations. Nothing is drawn, no engine is needed, and
  a simulated day takes about a second, so the numbers in
  `Config.game.{trade,production,mining,cargo}` can be tuned by running this
  rather than by flying around.

  What is modelled here instead of run for real: a miner is a delivery every
  so often (its hold, its mining rate and its sell time are the real config
  values, plus a travel time), and the trader is a simple "buy the best
  margin, sell it where it is dearest" loop. Everything about prices, stock,
  production and imports is the game's own code.

  Usage (from the repository root):

      luajit tools/economy-sim.lua
      luajit tools/economy-sim.lua --days 7 --stations 3 --miners 6
      luajit tools/economy-sim.lua --set trade.spread=0.2 --set production.timeScale=5
      luajit tools/economy-sim.lua --trader --csv /tmp/economy.csv
      luajit tools/economy-sim.lua --watch "Iron Ore,Iron,Steel,Energy Cell"

  Options:
      --days N           days to simulate (default 2)
      --hours N          hours to simulate (overrides --days)
      --step S           seconds per step (default 2; smaller is slower, no
                         more accurate: production and imports are linear)
      --stations N       stations in the system (default 2)
      --miners N         miners bringing ore in (default: the Secure
                         hostility level's miner count, Config.game.hostility)
      --trip S           seconds a miner spends flying per run (default 120)
      --trader           run a trader between the stations and report its profit
      --prospector       run a miner-player (fill the hold, sell it) and report
                         its profit, to compare mining with hauling
      --seed N           the seed everything is drawn from (default 1)
      --seeds N          run N seeds (seed..seed+N-1) and report the spread of
                         the outcomes: income swings by a lot with which
                         recipes a system's stations happen to get
      --set path=value   override a Config.game value, e.g. trade.spread=0.2
      --watch "a,b,c"    the items the per-hour table shows (display names)
      --csv FILE         write the per-hour series as CSV
      --quiet            only the summary
      --help

  Read the summary for: lines that never ran (starved: their inputs have no
  source), prices pinned at the scarcity bounds (the target or the softness is
  wrong), stock running away (nothing consumes it), and the trader's profit
  per hour (whether hauling is worth the flying).
----------------------------------------------------------------------------]]

------------------------------------------------------------------------------
-- The game's Lua, with the engine stubbed out
------------------------------------------------------------------------------

local repoRoot = (function()
    -- Run from anywhere: resolve the repository root from this file's path
    local thisFile = debug.getinfo(1, "S").source:gsub("^@", "")
    local dir = thisFile:match("^(.*)[/\\]tools[/\\]economy%-sim%.lua$")
    return dir or "."
end)()

package.path = table.concat({
    repoRoot .. "/script/?.lua",
    repoRoot .. "/script/?/__init__.lua",
    package.path,
}, ";")

dofile(repoRoot .. "/script/Core/Structures/Class.lua")

local quiet = false
--- The report: always printed (`--quiet` only drops the per-hour table).
local function out(fmt, ...)
    print(select('#', ...) > 0 and string.format(fmt, ...) or fmt)
end

-- Globals the game's files expect. Only what the economy touches is real.
Log = {
    Warn = function(fmt, ...) io.stderr:write("WARN  " .. string.format(fmt, ...) .. "\n") end,
    Error = function(fmt, ...) io.stderr:write("ERROR " .. string.format(fmt, ...) .. "\n") end,
    Info = function() end,
    Debug = function() end,
}
Math = { Round = function(x) return math.floor(x + 0.5) end }
function SetLengthMetamethod(_) end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function Vec3f(x, y, z) return { x = x, y = y, z = z } end
function Vec2f(x, y) return { x = x, y = y } end
Enums = setmetatable({}, {
    __index = function(t, k)
        local v = setmetatable({}, { __index = function() return 1 end })
        t[k] = v
        return v
    end
})

--- A deterministic RNG with the engine's interface (xorshift64*).
---@param seed integer
local function RNGCreate(seed)
    local state = (seed or 1) * 2654435761 % 0x7FFFFFFF
    if state == 0 then state = 1 end
    local rng = {}
    local function nextValue()
        -- 31-bit Lehmer: plenty for tuning, and the same on every machine
        state = (state * 48271) % 0x7FFFFFFF
        return state
    end
    function rng:getUniform() return nextValue() / 0x7FFFFFFF end
    function rng:getUniformRange(lo, hi) return lo + (hi - lo) * self:getUniform() end
    function rng:getInt(lo, hi) return lo + math.floor(self:getUniform() * (hi - lo + 1 - 1e-12)) end
    function rng:get31() return nextValue() end
    function rng:get64() return nextValue() end
    return rng
end
RNG = { Create = RNGCreate, FromTime = function() return RNGCreate(os.time()) end }

-- The ECS, down to what a component needs: the economy components only ever
-- set a name and keep their own fields.
local ComponentStub = Class("Component", function() end)
function ComponentStub:setComponentName(name) self.componentName = name end
function ComponentStub:getComponentName() return self.componentName end
package.loaded["Core.ECS.Component"] = ComponentStub

Config = { gen = {}, game = {} }
require("Config.General.GameConfig")

-- The real registries and systems
require("Shared.Definitions.ItemDefs")
local Items = require("Shared.Registries.Items")
require("Shared.Definitions.ProductionDefs")
local Productions = require("Shared.Registries.Productions")
local StockComponent = require("Modules.Economy.Components.StockComponent")
local ProductionComponent = require("Modules.Economy.Components.ProductionComponent")

-- Modules.Economy.Components pulls in components that need the engine's
-- Entity and TimeStamp; the trade and production systems only use these two.
package.loaded["Modules.Economy.Components"] = {
    Stock = StockComponent,
    Production = ProductionComponent,
}

local StationTradeSystem = require("Modules.Economy.Systems.StationTradeSystem")
local ProductionSystem = require("Modules.Economy.Systems.ProductionSystem")
local PlayerWallet = require("Modules.Economy.Managers.PlayerWallet")

------------------------------------------------------------------------------
-- Arguments
------------------------------------------------------------------------------

-- The miner count a Secure system actually spawns, so the default run is the
-- game's own supply of ore rather than a number made up here.
local defaultMiners = (function()
    local levels = Config.game.hostility and Config.game.hostility.levels
    local level = levels and levels[Config.game.hostility.homeLevel or 1]
    return level and level.npcs and level.npcs.miner or 2
end)()

local args = {
    hours = 48,
    step = 2,
    stations = 2,
    miners = defaultMiners,
    trip = 120,
    seed = 1,
    seeds = 1,
    trader = false,
    prospector = false,
    csv = nil,
    watch = nil,
}

local function fail(message)
    io.stderr:write("economy-sim: " .. message .. "\n")
    os.exit(1)
end

--- Set `Config.game.a.b = value` from a `a.b=value` string.
---@param assignment string
local function applyOverride(assignment)
    local path, value = assignment:match("^([%w_%.]+)=(.+)$")
    if not path then fail("--set wants path=value, not '" .. assignment .. "'") end
    local target = Config.game
    local keys = {}
    for key in path:gmatch("[^%.]+") do keys[#keys + 1] = key end
    for i = 1, #keys - 1 do
        target = target[keys[i]]
        if type(target) ~= "table" then fail("no such config table: " .. path) end
    end
    local last = keys[#keys]
    if target[last] == nil then fail("no such config value: Config.game." .. path) end
    local number = tonumber(value)
    if number then
        target[last] = number
    elseif value == "true" or value == "false" then
        target[last] = value == "true"
    else
        target[last] = value
    end
end

local overrides = {}
do
    local i = 1
    while i <= #arg do
        local a = arg[i]
        local function nextArg()
            i = i + 1
            if not arg[i] then fail(a .. " wants a value") end
            return arg[i]
        end
        if a == "--help" or a == "-h" then
            local source = io.open(debug.getinfo(1, "S").source:gsub("^@", ""))
            local text = source:read("*a")
            source:close()
            print((text:match("%-%-%[%[%-*(.-)%-*%]%]")))
            os.exit(0)
        elseif a == "--days" then args.hours = tonumber(nextArg()) * 24
        elseif a == "--hours" then args.hours = tonumber(nextArg())
        elseif a == "--step" then args.step = tonumber(nextArg())
        elseif a == "--stations" then args.stations = tonumber(nextArg())
        elseif a == "--miners" then args.miners = tonumber(nextArg())
        elseif a == "--trip" then args.trip = tonumber(nextArg())
        elseif a == "--seed" then args.seed = tonumber(nextArg())
        elseif a == "--seeds" then args.seeds = tonumber(nextArg())
        elseif a == "--trader" then args.trader = true
        elseif a == "--prospector" then args.prospector = true
        elseif a == "--csv" then args.csv = nextArg()
        elseif a == "--watch" then args.watch = nextArg()
        elseif a == "--quiet" then quiet = true
        elseif a == "--set" then overrides[#overrides + 1] = nextArg()
        else fail("unknown option " .. a .. " (try --help)")
        end
        i = i + 1
    end
end
for _, assignment in ipairs(overrides) do applyOverride(assignment) end

------------------------------------------------------------------------------
-- Many seeds: run this same tool once per seed and gather the outcomes. What
-- a system's stations happen to make swings the income by a lot, so one seed
-- says little about a setting.
------------------------------------------------------------------------------

if args.seeds > 1 then
    local selfPath = debug.getinfo(1, "S").source:gsub("^@", "")
    -- Everything except --seeds, --csv and --quiet is passed straight on
    local passed = {}
    local skip = false
    for index, value in ipairs(arg) do
        if skip then
            skip = false
        elseif value == "--seeds" or value == "--seed" or value == "--csv" then
            skip = true
        elseif value ~= "--quiet" then
            passed[#passed + 1] = value
        end
    end
    local rows = {}
    for seed = args.seed, args.seed + args.seeds - 1 do
        local command = string.format("%q %q %s --quiet --seed %d",
            arg[-1] or "luajit", selfPath, table.concat(passed, " "), seed)
        local pipe = assert(io.popen(command))
        local text = pipe:read("*a")
        pipe:close()
        local row = { seed = seed }
        row.mining = tonumber(text:match("Prospector:.-%((%-?%d+) credits/hour%)")) or 0
        row.trading = tonumber(text:match("Trader:.-%((%-?%d+) credits/hour%)")) or 0
        row.starved = select(2, text:gsub("STARVED", "")) or 0
        row.idle = select(2, text:gsub("idle %d+%%", "")) or 0
        row.bounds = select(2, text:gsub("at the %w+ bound", "")) or 0
        rows[#rows + 1] = row
    end
    local function stat(field)
        local values = {}
        for _, row in ipairs(rows) do values[#values + 1] = row[field] end
        table.sort(values)
        local sum = 0
        for _, v in ipairs(values) do sum = sum + v end
        return values[1], values[math.ceil(#values / 2)], values[#values], sum / #values
    end
    out("economy-sim: %d seeds, %d hours each", args.seeds, args.hours)
    out("")
    out("    %6s %12s %12s %9s %7s %8s", "seed", "mining cr/h", "trading cr/h", "starved", "idle", "pinned")
    for _, row in ipairs(rows) do
        out("    %6d %12d %12d %9d %7d %8d", row.seed, row.mining, row.trading,
            row.starved, row.idle, row.bounds)
    end
    out("")
    for _, field in ipairs({ "mining", "trading", "starved", "bounds" }) do
        local lo, mid, hi, mean = stat(field)
        out("    %-9s min %8d   median %8d   max %8d   mean %8.0f", field, lo, mid, hi, mean)
    end
    out("")
    out("`starved` counts production lines that never completed a run, `idle` lines")
    out("idle more than half the time, `pinned` prices stuck at a scarcity bound.")
    os.exit(0)
end

------------------------------------------------------------------------------
-- The system: stations, miners, a trader
------------------------------------------------------------------------------

--- A stand-in for an ECS entity: a bag of components, keyed by their class.
local function FakeEntity(name)
    local entity = { name = name, comps = {} }
    function entity:add(component)
        self.comps[getmetatable(component)] = component
        return component
    end
    function entity:get(class) return self.comps[class] end
    function entity:isValid() return true end
    return entity
end

--- The ores of the system, as `Config.game.mining.ores` names them.
---@return table[] { def, weight }, with `total`
local function systemOres()
    local ores, total = {}, 0
    for _, ore in ipairs(Config.game.mining.ores) do
        local def = Items:getByName(ore.name)
        if def then
            ores[#ores + 1] = { def = def, weight = ore.weight }
            total = total + ore.weight
        end
    end
    ores.total = total
    return ores
end

local rng = RNGCreate(args.seed)
local ores = systemOres()
local oreIds = {}
for _, ore in ipairs(ores) do oreIds[#oreIds + 1] = ore.def.id end

--- The stations, each with the real stock, recipes and opening shelves.
local stations = {}
for index = 1, args.stations do
    local station = FakeEntity("Station " .. index)
    station:add(StockComponent())
    ProductionSystem:assign(station, rng, index == 1, oreIds)
    StationTradeSystem:stock(station, rng, oreIds)
    -- Count a line's completed runs: a line only leaves `running` by finishing
    station.lineState = {}
    for _, line in ipairs(station:get(ProductionComponent):getLines()) do
        station.lineState[line] = { wasRunning = false, runs = 0, idleSeconds = 0 }
    end
    stations[index] = station
end

--- The miners: each one brings a hold of one ore to a station, over and over.
--- Its hold, its mining rate and its time docked are the real config values;
--- the time it spends flying is `--trip`.
local miners = {}
for index = 1, args.miners do
    local cargo = (Config.game.npc and Config.game.npc.roles and Config.game.npc.roles.miner
        and Config.game.npc.roles.miner.cargo) or 12
    local pick = rng:getUniformRange(0, ores.total)
    local ore = ores[#ores].def
    for _, candidate in ipairs(ores) do
        pick = pick - candidate.weight
        if pick <= 0 then ore = candidate.def break end
    end
    miners[index] = {
        ore = ore,
        units = cargo,
        station = stations[rng:getInt(1, #stations)],
        -- One run: mine the hold, fly, sell
        runSeconds = cargo * Config.game.mining.timePerUnit + args.trip + Config.game.mining.sellTime,
        timer = rng:getUniformRange(0, 60),
        delivered = 0,
    }
end

PlayerWallet:reset()
local trader = {
    hold = StockComponent(Config.game.cargo.holdCapacity),
    station = stations[1],
    timer = 0,
    bought = 0,
    sold = 0,
    trips = 0,
    startCredits = PlayerWallet:get(),
}

--- The trader: at each station in turn, sell whatever it is carrying, then
--- fill the hold with the one good whose margin against another station's
--- buy-back price is best. The point is not to be clever: it is to see
--- whether hauling can pay at all at the current settings.
---@param dt number
local function updateTrader(dt)
    trader.timer = trader.timer - dt
    if trader.timer > 0 then return end
    trader.timer = args.trip
    trader.trips = trader.trips + 1

    local here = trader.station
    -- Sell the hold
    for _, row in ipairs(trader.hold:list()) do
        local sold, earned = StationTradeSystem:sell(here, trader.hold, row.item.id, row.units)
        trader.sold = trader.sold + earned
        if sold == 0 then break end
    end

    -- Where to next, and with what: the best (buy here, sell there) margin
    local bestItem, bestTarget, bestMargin = nil, nil, 0
    for _, there in ipairs(stations) do
        if there ~= here then
            for _, row in ipairs(StationTradeSystem:listing(here)) do
                if row.units > 0 then
                    local margin = StationTradeSystem:sellPrice(there, row.item.id) - row.buy
                    if margin > bestMargin then
                        bestItem, bestTarget, bestMargin = row.item, there, margin
                    end
                end
            end
        end
    end
    if bestItem then
        -- Buy while it is still worth buying: each unit pushes the price up
        -- here, so a trader stops when the margin is gone rather than
        -- emptying the shelves at the first price it saw
        local spent = 0
        while true do
            local margin = StationTradeSystem:sellPrice(bestTarget, bestItem.id)
                - StationTradeSystem:buyPrice(here, bestItem.id)
            if margin <= 0 then break end
            local bought, paid = StationTradeSystem:buy(here, trader.hold, bestItem.id, 1)
            if bought < 1 then break end
            spent = spent + paid
        end
        trader.bought = trader.bought + spent
        trader.station = bestTarget
    else
        -- Nothing worth hauling: move on anyway
        trader.station = stations[(function()
            for i, s in ipairs(stations) do if s == here then return i % #stations + 1 end end
            return 1
        end)()]
    end
end

--- Where goods come from and go to, in units, per item: the answer to "is
--- this station living off its miners or off its imports?".
local flows = { production = {}, imports = {}, mined = {}, trader = {} }
local function addFlow(bucket, itemId, units)
    if units == 0 then return end
    bucket[itemId] = (bucket[itemId] or 0) + units
end

--- A snapshot of every station's stock, to difference against.
---@return table<integer, integer>
local function snapshot()
    local counts = {}
    for _, station in ipairs(stations) do
        for _, row in ipairs(station:get(StockComponent):list()) do
            counts[row.item.id] = (counts[row.item.id] or 0) + row.units
        end
    end
    return counts
end

--- The change since `before`, into `bucket`.
---@param bucket table
---@param before table<integer, integer>
local function record(bucket, before)
    local after = snapshot()
    for id, units in pairs(after) do
        addFlow(bucket, id, units - (before[id] or 0))
    end
    for id, units in pairs(before) do
        if not after[id] then addFlow(bucket, id, -units) end
    end
end

--- The other way a player makes money: fill the hold out of a belt and sell
--- it. Mining takes the real `playerTimePerUnit` per unit and the hold is
--- the real capacity, so this is the mining income the game actually offers,
--- next to the trader's hauling income.
local prospector = {
    hold = StockComponent(Config.game.cargo.holdCapacity),
    ore = ores[rng:getInt(1, #ores)].def,
    state = "mining",
    timer = 0,
    trips = 0,
    earned = 0,
    mined = 0,
}
prospector.unitsPerTrip = math.max(1, math.floor(Config.game.cargo.holdCapacity / prospector.ore.mass))
prospector.timer = prospector.unitsPerTrip * Config.game.mining.playerTimePerUnit

---@param dt number
local function updateProspector(dt)
    prospector.timer = prospector.timer - dt
    if prospector.timer > 0 then return end
    if prospector.state == "mining" then
        -- The hold is full: fly to a station
        prospector.hold:add(prospector.ore.id, prospector.unitsPerTrip)
        prospector.mined = prospector.mined + prospector.unitsPerTrip
        addFlow(flows.mined, prospector.ore.id, prospector.unitsPerTrip)
        prospector.state = "flying"
        prospector.timer = args.trip
    elseif prospector.state == "flying" then
        -- Sell the lot where it pays best
        local best, bestPrice
        for _, station in ipairs(stations) do
            local price = StationTradeSystem:sellPrice(station, prospector.ore.id)
            if not bestPrice or price > bestPrice then best, bestPrice = station, price end
        end
        local _, earned = StationTradeSystem:sell(best, prospector.hold, prospector.ore.id,
            prospector.hold:count(prospector.ore.id))
        prospector.earned = prospector.earned + earned
        prospector.trips = prospector.trips + 1
        prospector.state = "mining"
        prospector.timer = prospector.unitsPerTrip * Config.game.mining.playerTimePerUnit
    end
end

------------------------------------------------------------------------------
-- The run
------------------------------------------------------------------------------

--- The items the per-hour table shows: what was asked for, else the first
--- ore plus whatever the stations make.
---@return ItemDefinition[]
local function watchedItems()
    local watched, seen = {}, {}
    local function add(def)
        if def and not seen[def.id] then
            seen[def.id] = true
            watched[#watched + 1] = def
        end
    end
    if args.watch then
        for name in args.watch:gmatch("[^,]+") do
            local def = Items:getByName((name:gsub("^%s+", ""):gsub("%s+$", "")))
            if not def then fail("no such item: " .. name) end
            add(def)
        end
        return watched
    end
    add(ores[1].def)
    for _, station in ipairs(stations) do
        for _, recipe in ipairs(station:get(ProductionComponent):getRecipes()) do
            for _, entry in ipairs(recipe.outputs) do add(entry.item) end
        end
    end
    while #watched > 6 do table.remove(watched) end
    return watched
end

local watched = watchedItems()
local csv = args.csv and assert(io.open(args.csv, "w"))
if csv then
    local header = { "hour" }
    for index in ipairs(stations) do
        for _, def in ipairs(watched) do
            header[#header + 1] = string.format("s%d_%s_stock", index, def.name)
            header[#header + 1] = string.format("s%d_%s_buy", index, def.name)
        end
    end
    header[#header + 1] = "credits"
    csv:write(table.concat(header, ",") .. "\n")
end

-- Price extremes per station and item, for the summary
local priceRange = {}
local function recordPrices()
    for index, station in ipairs(stations) do
        for _, def in ipairs(watched) do
            local key = index .. ":" .. def.id
            local price = StationTradeSystem:buyPrice(station, def.id)
            local range = priceRange[key]
            if not range then
                priceRange[key] = { min = price, max = price, sum = price, n = 1 }
            else
                range.min = math.min(range.min, price)
                range.max = math.max(range.max, price)
                range.sum = range.sum + price
                range.n = range.n + 1
            end
        end
    end
end

out("economy-sim: %d station(s), %d miner(s)%s, %d hours at %gs steps, seed %d",
    #stations, #miners, args.trader and ", a trader" or "", args.hours, args.step, args.seed)
out("")
for index, station in ipairs(stations) do
    out("%s", station.name)
    for _, recipe in ipairs(station:get(ProductionComponent):getRecipes()) do
        out("    %s", recipe:describe())
    end
end
out("")

if not quiet then
    local header = { string.format("%5s", "hour") }
    for index in ipairs(stations) do
        for _, def in ipairs(watched) do
            header[#header + 1] = string.format("%18s", string.format("s%d %s", index, def.displayName))
        end
    end
    header[#header + 1] = string.format("%12s", "credits")
    print(table.concat(header, " "))
end

--- One hour's row: stock and buy price per station and watched item.
local function reportHour(hour)
    local row = { string.format("%5d", hour) }
    local csvRow = { tostring(hour) }
    for index, station in ipairs(stations) do
        local stock = station:get(StockComponent)
        for _, def in ipairs(watched) do
            local units = stock:count(def.id)
            local price = StationTradeSystem:buyPrice(station, def.id)
            row[#row + 1] = string.format("%18s", string.format("%d @ %d", units, price))
            csvRow[#csvRow + 1] = tostring(units)
            csvRow[#csvRow + 1] = tostring(price)
        end
    end
    row[#row + 1] = string.format("%12d", PlayerWallet:get())
    csvRow[#csvRow + 1] = tostring(PlayerWallet:get())
    if not quiet then print(table.concat(row, " ")) end
    if csv then csv:write(table.concat(csvRow, ",") .. "\n") end
end

local totalSeconds = args.hours * 3600
local step = args.step
local nextHour = 3600
local elapsed = 0
local deliveries = 0

while elapsed < totalSeconds do
    -- The game's own two updates, with the stock differenced around each one
    -- so production and imports can be told apart
    local before = snapshot()
    ProductionSystem:update(stations, step)
    record(flows.production, before)
    before = snapshot()
    StationTradeSystem:update(stations, step)
    record(flows.imports, before)

    -- Lines: count the runs, and the time spent waiting for stock
    for _, station in ipairs(stations) do
        for _, line in ipairs(station:get(ProductionComponent):getLines()) do
            local state = station.lineState[line]
            if state.wasRunning and not line.running then state.runs = state.runs + 1 end
            if not line.running then state.idleSeconds = state.idleSeconds + step end
            state.wasRunning = line.running
        end
    end

    -- Miners unloading
    for _, miner in ipairs(miners) do
        miner.timer = miner.timer - step
        if miner.timer <= 0 then
            miner.timer = miner.timer + miner.runSeconds
            StationTradeSystem:deliver(miner.station, miner.ore.id, miner.units)
            addFlow(flows.mined, miner.ore.id, miner.units)
            miner.delivered = miner.delivered + miner.units
            deliveries = deliveries + 1
        end
    end

    if args.trader then
        before = snapshot()
        updateTrader(step)
        record(flows.trader, before)
    end
    if args.prospector then updateProspector(step) end

    elapsed = elapsed + step
    recordPrices()
    if elapsed >= nextHour then
        reportHour(math.floor(elapsed / 3600))
        nextHour = nextHour + 3600
    end
end

if csv then csv:close() end

------------------------------------------------------------------------------
-- The summary: what the numbers say about the settings
------------------------------------------------------------------------------

out("")
out("After %d hours", args.hours)
out("")
local cfg = Config.game.trade
for index, station in ipairs(stations) do
    out("%s", station.name)
    for _, line in ipairs(station:get(ProductionComponent):getLines()) do
        local recipe = Productions:getDefinition(line.id)
        local state = station.lineState[line]
        local idleShare = 100 * state.idleSeconds / totalSeconds
        local note = ""
        if state.runs == 0 then
            note = "  <- STARVED: never completed a run"
        elseif idleShare > 50 then
            note = string.format("  <- idle %.0f%% of the time", idleShare)
        end
        out("    %-34s %5d runs (%.1f/h)%s", recipe.displayName, state.runs,
            state.runs / args.hours, note)
    end
    local stock = station:get(StockComponent)
    local rows = stock:list()
    table.sort(rows, function(a, b) return a.units > b.units end)
    local parts = {}
    for i = 1, math.min(6, #rows) do
        parts[#parts + 1] = string.format("%s %d", rows[i].item.displayName, rows[i].units)
    end
    out("    stock: %s", table.concat(parts, ", "))
end

out("")
out("Prices (buy price per unit, over the run)")
out("    %-22s %-10s %8s %8s %8s %8s", "item", "station", "equil", "min", "mean", "max")
for index, station in ipairs(stations) do
    for _, def in ipairs(watched) do
        local range = priceRange[index .. ":" .. def.id]
        if range then
            local equilibrium = def.startEquilibriumPrice or cfg.defaultPrice
            local note = ""
            local pinnedLow = math.ceil(equilibrium * cfg.minScarcity * (1 + cfg.spread))
            local pinnedHigh = math.ceil(equilibrium * cfg.maxScarcity * (1 + cfg.spread))
            if range.max >= pinnedHigh then note = note .. " at the shortage bound" end
            if range.min <= pinnedLow then note = note .. " at the glut bound" end
            out("    %-22s %-10s %8d %8d %8.0f %8d%s", def.displayName, station.name,
                equilibrium, range.min, range.sum / range.n, range.max, note)
        end
    end
end

out("")
out("Where the goods came from, in units over the run (a negative number is")
out("what was consumed or carried away)")
out("    %-22s %12s %12s %12s %12s", "item", "produced", "imported", "mined", "hauled")
do
    local seen = {}
    for _, bucket in pairs(flows) do
        for id in pairs(bucket) do seen[id] = true end
    end
    local ids = {}
    for id in pairs(seen) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local def = Items:getDefinition(id)
        local produced = flows.production[id] or 0
        local imported = flows.imports[id] or 0
        local mined = flows.mined[id] or 0
        local hauled = flows.trader[id] or 0
        if produced ~= 0 or imported ~= 0 or mined ~= 0 or hauled ~= 0 then
            out("    %-22s %12d %12d %12d %12d", def.displayName, produced, imported, mined, hauled)
        end
    end
end

out("")
out("Miners: %d deliveries, %d units of ore in total (%.1f units/hour)",
    deliveries, (function()
        local units = 0
        for _, miner in ipairs(miners) do units = units + miner.delivered end
        return units
    end)(), (function()
        local units = 0
        for _, miner in ipairs(miners) do units = units + miner.delivered end
        return units / args.hours
    end)())

if args.prospector then
    out("Prospector: %d loads of %s (%d units a load), %d units mined, earned %d (%.0f credits/hour)",
        prospector.trips, prospector.ore.displayName, prospector.unitsPerTrip,
        prospector.mined, prospector.earned, prospector.earned / args.hours)
end

if args.trader then
    local profit = PlayerWallet:get() - trader.startCredits
        - (args.prospector and prospector.earned or 0)
    out("Trader: %d trips, spent %d, earned %d, profit %d (%.0f credits/hour)",
        trader.trips, trader.bought, trader.sold, profit, profit / args.hours)
    if profit <= 0 then
        out("        <- hauling does not pay at these settings (look at trade.spread,")
        out("           trade.targetValue and how much the miners bring in)")
    end
end
out("")
out("Settings used: trade.spread=%.2f targetValue=%d priceSoftness=%d scarcity=%.2f..%.2f",
    cfg.spread, cfg.targetValue, cfg.priceSoftness, cfg.minScarcity, cfg.maxScarcity)
out("               importPerSecond=%.2f importFloor=%.2f production.timeScale=%.1f",
    cfg.importPerSecond, cfg.importFloor, Config.game.production.timeScale)
