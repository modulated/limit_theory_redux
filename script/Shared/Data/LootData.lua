local Toml = require("Shared.Data.Toml")
local Fields = require("Shared.Data.Fields")
-- The drops name items, so the item registry has to be filled first
require("Shared.Definitions.ItemDefs")
local Items = require("Shared.Registries.Items")

--- What a destroyed ship drops, by its role, from `res/data/loot.toml`. Read
--- once, on first use.
---@class LootData
local LootData = {}

local FILE = "loot.toml"
local tables

local function load()
    if tables then return tables end
    local raw = Toml.load(FILE)
    tables = {}
    for role, entry in pairs(raw.role or {}) do
        local f = Fields.of(entry, "loot for role '" .. tostring(role) .. "'", { "drops" })
        local drops = {}
        for i, drop in ipairs(f:tbl("drops")) do
            -- Inline tables carry no line of their own: errors name the role's
            if type(drop) ~= "table" then f:fail("drop %d is not { item = ..., chance = ... }", i) end
            for k in pairs(drop) do
                if k ~= "item" and k ~= "chance" and k ~= "min" and k ~= "max" then
                    f:fail("drop %d has an unknown field '%s' (item, chance, min, max)", i, tostring(k))
                end
            end
            local item = Items:getByName(drop.item)
            if not item then
                f:fail("drop %d names no item '%s' (names are as in items.toml)", i, tostring(drop.item))
            end
            local chance = drop.chance
            if type(chance) ~= "number" or chance < 0 or chance > 1 then
                f:fail("drop %d (%s) needs a `chance` from 0 to 1", i, drop.item)
            end
            local min = drop.min == nil and 1 or drop.min
            local max = drop.max == nil and min or drop.max
            if type(min) ~= "number" or type(max) ~= "number" or min < 1 or max < min
                or min % 1 ~= 0 or max % 1 ~= 0 then
                f:fail("drop %d (%s): `min` and `max` must be whole numbers, 1 <= min <= max", i, drop.item)
            end
            drops[#drops + 1] = { id = item.id, chance = chance, min = min, max = max }
        end
        tables[role] = drops
    end
    return tables
end

--- Every role with a loot table, sorted (for tools).
---@return string[]
function LootData.roles()
    local list = {}
    for role in pairs(load()) do list[#list + 1] = role end
    table.sort(list)
    return list
end

--- A role's drops, as { id, chance, min, max } (nil: it drops nothing).
---@param role string
---@return table[]|nil
function LootData.drops(role)
    return load()[role]
end

--- Roll what a wreck of `role` leaves: { { id, units }, ... }, possibly empty.
---@param role string
---@param rng table with getUniform() and getInt(lo, hi)
---@return table[]
function LootData.roll(role, rng)
    local contents = {}
    for _, drop in ipairs(load()[role] or {}) do
        if rng:getUniform() < drop.chance then
            contents[#contents + 1] = { id = drop.id, units = rng:getInt(drop.min, drop.max) }
        end
    end
    return contents
end

return LootData
