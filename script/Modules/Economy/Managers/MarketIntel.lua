local Items = require("Shared.Registries.Items")

--- What the player knows of other markets.
---
--- Only the system you are in is simulated, so the books of other systems
--- cannot be read live. What can be read is what was last seen of them: every
--- time you are at a station, its book is written down here, with the time.
--- The station screen shows those notes for systems within
--- `Config.game.market.remoteJumps` jumps, with their age, which is where
--- the price differences worth flying for show up.
---
--- The range is a number in the config so a future ship module can raise it:
--- `MarketIntel:setRange(jumps)`.
---@class MarketIntel
local MarketIntel = {
    ---@type table<string, table> station key -> { systemId, label, at, quotes }
    stations = {},
    ---@type integer|nil
    range = nil,
}

--- A new game: nothing known.
function MarketIntel:reset()
    self.stations = {}
    self.range = nil
end

--- How many jumps out the books can still be read.
---@return integer
function MarketIntel:getRange()
    return self.range or Config.game.market.remoteJumps
end

--- Raise (or lower) the reach, for a module that improves it.
---@param jumps integer|nil nil to go back to the configured range
function MarketIntel:setRange(jumps)
    self.range = jumps
end

--- Write down what a station's book says right now.
---@param key string the station key
---@param systemId integer
---@param label string
---@param book OrderBookComponent
---@param now number the game clock
function MarketIntel:record(key, systemId, label, book, now)
    local quotes = {}
    for _, itemId in ipairs(book:items()) do
        local last = book:last(itemId)
        local bid, ask = book:bid(itemId), book:ask(itemId)
        if bid or ask or last then
            quotes[itemId] = { bid = bid, ask = ask, last = last }
        end
    end
    self.stations[key] = {
        systemId = systemId,
        label = label,
        at = now,
        quotes = quotes,
    }
end

--- The systems within `range` jumps of `fromId`, by breadth first search over
--- the galaxy's links: id -> jumps away (0 for the system itself).
---@param galaxy table the galaxy (GalaxyGenerator)
---@param fromId integer
---@param range integer
---@return table<integer, integer>
local function withinJumps(galaxy, fromId, range)
    local distance = { [fromId] = 0 }
    local frontier = { fromId }
    for jumps = 1, range do
        local next = {}
        for _, id in ipairs(frontier) do
            local system = galaxy.systems[id]
            -- A system's `links` are link ids into `galaxy.links`
            for _, linkId in ipairs(system and system.links or {}) do
                local link = galaxy.links[linkId]
                local other = link and (link.a == id and link.b or link.a)
                if other and distance[other] == nil then
                    distance[other] = jumps
                    next[#next + 1] = other
                end
            end
        end
        frontier = next
        if #frontier == 0 then break end
    end
    return distance
end

--- What is known of the markets within reach of a system, nearest first:
--- one row per station, with how long ago it was seen.
---@param galaxy table|nil
---@param fromId integer the system the player is in
---@param now number the game clock
---@return table[] rows { key, label, systemId, systemName, jumps, age, quotes }
function MarketIntel:nearby(galaxy, fromId, now)
    local rows = {}
    local distance = galaxy and withinJumps(galaxy, fromId, self:getRange()) or { [fromId] = 0 }
    for key, record in pairs(self.stations) do
        local jumps = distance[record.systemId]
        if jumps then
            local system = galaxy and galaxy.systems[record.systemId]
            rows[#rows + 1] = {
                key = key,
                label = record.label,
                systemId = record.systemId,
                systemName = system and system.name or ("System " .. record.systemId),
                jumps = jumps,
                age = math.max(0, now - record.at),
                quotes = record.quotes,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.jumps ~= b.jumps then return a.jumps < b.jumps end
        return a.key < b.key
    end)
    return rows
end

--- Where one item is dearest and cheapest within reach, out of what is
--- known: the trading opportunity, as far as the player can see it.
---@param galaxy table|nil
---@param fromId integer
---@param itemId integer
---@param now number
---@return table[] rows { label, systemName, jumps, age, bid, ask, last }
function MarketIntel:forItem(galaxy, fromId, itemId, now)
    local rows = {}
    for _, record in ipairs(self:nearby(galaxy, fromId, now)) do
        local quote = record.quotes[itemId]
        if quote then
            rows[#rows + 1] = {
                label = record.label,
                systemName = record.systemName,
                jumps = record.jumps,
                age = record.age,
                bid = quote.bid,
                ask = quote.ask,
                last = quote.last,
            }
        end
    end
    table.sort(rows, function(a, b) return (a.bid or 0) > (b.bid or 0) end)
    return rows
end

--- The best spread known within reach: buy here, sell there. What a trader
--- wants to see on arriving in a system.
---@param galaxy table|nil
---@param fromId integer
---@param now number
---@param limit integer|nil how many to return (default 6)
---@return table[] rows { item, buyAt, buyPrice, sellAt, sellPrice, margin, jumps, age }
function MarketIntel:bestSpreads(galaxy, fromId, now, limit)
    local nearby = self:nearby(galaxy, fromId, now)
    local best = {}
    for _, from in ipairs(nearby) do
        for itemId, quote in pairs(from.quotes) do
            if quote.ask then
                for _, to in ipairs(nearby) do
                    local other = to.quotes[itemId]
                    if to.key ~= from.key and other and other.bid and other.bid > quote.ask then
                        local def = Items:getDefinition(itemId)
                        if def then
                            best[#best + 1] = {
                                item = def,
                                buyAt = from, buyPrice = quote.ask,
                                sellAt = to, sellPrice = other.bid,
                                margin = other.bid - quote.ask,
                                jumps = math.max(from.jumps, to.jumps),
                                age = math.max(from.age, to.age),
                            }
                        end
                    end
                end
            end
        end
    end
    table.sort(best, function(a, b) return a.margin > b.margin end)
    while #best > (limit or 6) do table.remove(best) end
    return best
end

--- "4 minutes ago" for the age of a note.
---@param seconds number
---@return string
function MarketIntel.describeAge(seconds)
    if seconds < 90 then return string.format("%ds ago", math.floor(seconds)) end
    if seconds < 5400 then return string.format("%dm ago", math.floor(seconds / 60)) end
    return string.format("%dh ago", math.floor(seconds / 3600))
end

return MarketIntel
