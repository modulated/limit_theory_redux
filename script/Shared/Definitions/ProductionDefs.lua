-- Types --
local ProductionDefinition = require("Shared.Types.ProductionDefinition")
local Productions = require("Shared.Registries.Productions")
-- The recipes name items, so the item registry has to be filled first.
require("Shared.Definitions.ItemDefs")
local Items = require("Shared.Registries.Items")
local Toml = require("Shared.Data.Toml")
local Fields = require("Shared.Data.Fields")

-- What a station can make out of what it holds: the production chains of the
-- game, from res/data/recipes.toml (its header explains every field). Read
-- doc/items.md for the chains as a whole.
--
-- A recipe's id is permanent: a station records which recipes it runs, so
-- renumbering would change what every station in a saved game produces.
--
-- `duration` is Legacy's seconds for one run; the production system scales
-- them by `Config.game.production.timeScale`.

local FIELDS = { "id", "name", "class", "duration", "inputs", "outputs" }

local file = Toml.load("recipes.toml")
if type(file.recipe) ~= "table" or #file.recipe == 0 then
    error("res/data/recipes.toml has no [[recipe]] entries", 0)
end

--- A recipe's `inputs` or `outputs`, as { item = ItemDefinition, count }.
---@param f Fields
---@param key string
---@return table[]
local function entries(f, key)
    local list = f:tbl(key)
    local out = {}
    for i, entry in ipairs(list) do
        if type(entry) ~= "table" then f:fail("%s, entry %d is not { item = ..., count = ... }", key, i) end
        for k in pairs(entry) do
            if k ~= "item" and k ~= "count" then f:fail("%s, entry %d has an unknown field '%s'", key, i, tostring(k)) end
        end
        local item = Items:getByName(entry.item)
        if not item then
            f:fail("%s, entry %d names no item '%s' (names are as in items.toml)", key, i, tostring(entry.item))
        end
        if type(entry.count) ~= "number" or entry.count < 1 or entry.count % 1 ~= 0 then
            f:fail("%s, entry %d (%s) needs a whole `count` of at least 1", key, i, entry.item)
        end
        out[#out + 1] = { item = item, count = entry.count }
    end
    return out
end

local ids, names = {}, {}
for _, entry in ipairs(file.recipe) do
    local f = Fields.of(entry, "recipe", FIELDS)
    local id = f:id()
    f:unique(ids, id)
    local name = f:str("name")
    local key = name:gsub("[^%w]", "")
    if names[key] then f:fail("has the same name as '%s'", names[key]) end
    names[key] = name
    local outputs = entries(f, "outputs")
    if #outputs == 0 then f:fail("makes nothing: `outputs` is empty") end
    Productions:add(ProductionDefinition {
        id = id,
        name = name,
        class = f:oneOf("class", ProductionDefinition.Class),
        duration = f:num("duration", 0.001),
        inputs = entries(f, "inputs"),
        outputs = outputs,
    })
end

return Productions
