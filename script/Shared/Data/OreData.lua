local Toml = require("Shared.Data.Toml")
-- The compositions name items, so the item registry has to be filled first
require("Shared.Definitions.ItemDefs")
local Items = require("Shared.Registries.Items")

--- What the asteroids hold, from `res/data/ores.toml`: the compositions the
--- rulesets give their belts and rings, and the fallback for a field without
--- one. Read once, on first use.
---@class OreData
local OreData = {}

local FILE = "ores.toml"
local data

--- A list of `{ item, weight }` entries as `{ id, weight }`, checked.
---@param list table
---@param where string for errors
---@return table[]
local function resolve(list, where)
    if type(list) ~= "table" or #list == 0 then
        error(string.format("res/data/%s: %s needs a non-empty `ores` list", FILE, where), 0)
    end
    local out = {}
    for i, entry in ipairs(list) do
        local def = type(entry) == "table" and Items:getByName(entry.item)
        if not def then
            error(string.format("res/data/%s: %s, ore %d names no item '%s' (see items.toml)",
                FILE, where, i, tostring(type(entry) == "table" and entry.item or entry)), 0)
        end
        if type(entry.weight) ~= "number" or entry.weight <= 0 then
            error(string.format("res/data/%s: %s, ore %d (%s) needs a positive weight",
                FILE, where, i, entry.item), 0)
        end
        out[#out + 1] = { id = def.id, weight = entry.weight }
    end
    return out
end

local function load()
    if data then return data end
    local raw = Toml.load(FILE)
    data = { compositions = {} }
    data.fallback = resolve(raw.fallback and raw.fallback.ores, "[fallback]")
    for key, comp in pairs(raw.composition or {}) do
        data.compositions[key] = resolve(comp.ores, "[composition." .. key .. "]")
    end
    return data
end

--- A composition by its key in ores.toml, as `{ { id, weight }, ... }` (a
--- fresh copy: a ruleset may keep it).
---@param key string
---@return table[]
function OreData.composition(key)
    local list = load().compositions[key]
    if not list then
        error(string.format("res/data/%s has no [composition.%s] (a ruleset asks for it)", FILE, key), 0)
    end
    local copy = {}
    for i, e in ipairs(list) do copy[i] = { id = e.id, weight = e.weight } end
    return copy
end

--- The fallback ores, for a field with no composition: `{ { id, weight } }`.
---@return table[]
function OreData.fallback()
    return load().fallback
end

--- Every composition key, sorted (for tools).
---@return string[]
function OreData.keys()
    local keys = {}
    for key in pairs(load().compositions) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

return OreData
