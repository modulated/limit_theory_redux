-- Types --
local FittingDefinition = require("Shared.Types.FittingDefinition")
local Fittings = require("Shared.Registries.Fittings")
-- The fittings name items, so the item registry has to be filled first.
require("Shared.Definitions.ItemDefs")
local Items = require("Shared.Registries.Items")
local Toml = require("Shared.Data.Toml")
local Fields = require("Shared.Data.Fields")

-- What a ship can be fitted with: the weapons that go in its mounts and the
-- modules that go in its slots. Every one of them is an item you buy or make
-- (see doc/items.md), so a loadout is goods you own and had hauled to where
-- your ship is.
--
-- They come from res/data/modules.toml (its header explains every field).
-- Every fitting carries an explicit `id`, permanent and never reused: a
-- ship's loadout records them.
--
-- Weapons name a weapon definition (Shared/Definitions/WeaponDefs.lua) and
-- the smallest mount they fit. Modules carry `effects`, added up over the
-- whole fit by ShipFittingSystem (`add` summed, `scale` multiplied), and an
-- `ability` when they do something on command.

local Slot = FittingDefinition.Slot
local Stat = FittingDefinition.Stat
local Weapon = Enums.Weapon
local Size = Weapon.MountSizeClass

local FIELDS = { "id", "name", "item", "slot", "description", "weapon", "size", "effects", "ability", "tool" }
local TOOL_KINDS = { mining = true }
local ABILITY_FIELDS = { key = true, cooldown = true, duration = true, magnitude = true }

-- The stats a module may name, as their values in FittingDefinition.Stat
local STATS = {}
for _, value in pairs(Stat) do STATS[value] = true end

--- A module's `effects.add` or `effects.scale`, checked.
---@param f Fields
---@param effects table
---@param kind string "add" or "scale"
---@return table|nil
local function statTable(f, effects, kind)
    local t = effects[kind]
    if t == nil then return nil end
    if type(t) ~= "table" then f:fail("effects.%s must be a table of stats", kind) end
    local out = {}
    for stat, value in pairs(t) do
        if not STATS[stat] then
            local names = {}
            for name in pairs(STATS) do names[#names + 1] = name end
            table.sort(names)
            f:fail("effects.%s names no stat '%s' (stats: %s)", kind, tostring(stat), table.concat(names, ", "))
        end
        if type(value) ~= "number" then f:fail("effects.%s.%s must be a number", kind, stat) end
        out[stat] = value
    end
    return out
end

local file = Toml.load("modules.toml")
if type(file.module) ~= "table" or #file.module == 0 then
    error("res/data/modules.toml has no [[module]] entries", 0)
end

local ids, claimed = {}, {}
local slots = { [Slot.Weapon] = true, [Slot.Module] = true }
for _, entry in ipairs(file.module) do
    local f = Fields.of(entry, "module", FIELDS)
    local id = f:id()
    f:unique(ids, id)
    local name = f:str("name")
    local item = Items:getByName(f:str("item"))
    if not item then f:fail("`item` names no item '%s' (names are as in items.toml)", entry.item) end
    if claimed[item.id] then f:fail("is the item '%s', which '%s' already is", entry.item, claimed[item.id]) end
    claimed[item.id] = name
    local slot = f:oneOf("slot", slots)

    local def = {
        id = id,
        name = name,
        description = f:str("description", true),
        slot = slot,
        itemName = item.name,
    }
    if slot == Slot.Weapon then
        def.sizeClass = Size[f:oneOf("size", Size)]
        if entry.effects or entry.ability then f:fail("a weapon takes no `effects` or `ability`") end
        if entry.tool ~= nil then
            -- A tool on a mount (the mining laser), not a gun
            if entry.weapon ~= nil then f:fail("a mount fitting is a `weapon` or a `tool`, not both") end
            local tool = f:tbl("tool")
            for k in pairs(tool) do
                if k ~= "kind" and k ~= "cycle" and k ~= "units" then
                    f:fail("tool has an unknown field '%s' (kind, cycle, units)", tostring(k))
                end
            end
            if not TOOL_KINDS[tool.kind] then f:fail("tool.kind must be one of: mining") end
            if type(tool.cycle) ~= "number" or tool.cycle <= 0 then f:fail("tool.cycle must be seconds above 0") end
            if type(tool.units) ~= "number" or tool.units < 1 or tool.units % 1 ~= 0 then
                f:fail("tool.units must be a whole number of at least 1")
            end
            def.tool = { kind = tool.kind, cycle = tool.cycle, units = tool.units }
        else
            def.weaponId = Weapon.Type[f:oneOf("weapon", Weapon.Type)]
        end
    else
        if entry.weapon or entry.size or entry.tool then f:fail("only a mount fitting has `weapon`, `tool` and `size`") end
        local effects = f:tbl("effects", true)
        if effects then
            for k in pairs(effects) do
                if k ~= "add" and k ~= "scale" then f:fail("effects has '%s'; only `add` and `scale`", tostring(k)) end
            end
            def.effects = { add = statTable(f, effects, "add"), scale = statTable(f, effects, "scale") }
        end
        local ability = f:tbl("ability", true)
        if ability then
            for k in pairs(ability) do
                if not ABILITY_FIELDS[k] then
                    f:fail("ability has an unknown field '%s' (key, cooldown, duration, magnitude)", tostring(k))
                end
            end
            if type(ability.key) ~= "string" then f:fail("ability needs a `key`") end
            if type(ability.cooldown) ~= "number" or ability.cooldown < 0 then
                f:fail("ability needs a `cooldown` of 0 or more seconds")
            end
            def.ability = {
                key = ability.key, cooldown = ability.cooldown,
                duration = ability.duration, magnitude = ability.magnitude,
            }
        end
    end
    Fittings:add(FittingDefinition(def), item.id)
end

return Fittings
