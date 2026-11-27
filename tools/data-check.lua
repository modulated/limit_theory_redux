--[[----------------------------------------------------------------------------
  data-check: load the game's data files and check them as a whole.

  The game reads res/data/items.toml, recipes.toml, modules.toml and ores.toml
  at start-up, and each loader stops on a mistake in a single entry (a
  misspelt field, an unknown item, a repeated id). This runs those same
  loaders without the game, then checks what no single entry can:

    * every module and every flyable hull can be made by some recipe;
    * every recipe input can be had: mined (ores.toml), or made by a recipe;
    * every ore in ores.toml is an item that something uses;
    * which ids are next free in each file.

  And it can write a file out as CSV, for a spreadsheet:

      luajit tools/data-check.lua                  check, and print a summary
      luajit tools/data-check.lua --csv items      items as CSV on stdout
      luajit tools/data-check.lua --csv recipes    one row per recipe, with
                                                   input cost, output value
                                                   and margin at base prices
      luajit tools/data-check.lua --csv modules

  Exit status 1 when a check fails, so it can run in CI.
------------------------------------------------------------------------------]]

local repoRoot = (function()
    local thisFile = debug.getinfo(1, "S").source:gsub("^@", "")
    local dir = thisFile:match("^(.*)[/\\]tools[/\\]data%-check%.lua$")
    return dir or "."
end)()

package.path = table.concat({
    repoRoot .. "/script/?.lua",
    repoRoot .. "/script/?/__init__.lua",
    package.path,
}, ";")

dofile(repoRoot .. "/script/Core/Structures/Class.lua")
Log = {
    Warn = function(fmt, ...) io.stderr:write("WARN  " .. string.format(fmt, ...) .. "\n") end,
    Error = function(fmt, ...) io.stderr:write("ERROR " .. string.format(fmt, ...) .. "\n") end,
    Info = function() end,
    Debug = function() end,
}
Math = { Round = function(x) return math.floor(x + 0.5) end }
function SetLengthMetamethod(_) end
Enums = {}
dofile(repoRoot .. "/script/Enums/WeaponEnums.lua")
require("Shared.Data.Toml").addSearchPath(repoRoot .. "/res/data/")

local args = { ... }
local csv
for i = 1, #args do
    if args[i] == "--csv" then csv = args[i + 1] end
    if args[i] == "-h" or args[i] == "--help" then
        print("usage: luajit tools/data-check.lua [--csv items|recipes|modules]")
        os.exit(0)
    end
end

local ok, reg = pcall(require, "Shared.Definitions")
if not ok then
    io.stderr:write(tostring(reg) .. "\n")
    os.exit(1)
end
local OreData = require("Shared.Data.OreData")
local Items, Productions, Fittings, Hulls = reg.Items, reg.Productions, reg.Fittings, reg.Hulls

--- Every item, by id.
local function allItems()
    local list = {}
    for id = 1, 10000 do
        local def = Items:getDefinition(id)
        if def then list[#list + 1] = def end
    end
    return list
end

local function price(def)
    return def.startEquilibriumPrice or 0
end

------------------------------------------------------------------------------
-- CSV
------------------------------------------------------------------------------

local function field(v)
    v = tostring(v == nil and "" or v)
    if v:find('[,"\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
    return v
end
local function row(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = field((select(i, ...))) end
    print(table.concat(parts, ","))
end

if csv == "items" then
    row("id", "name", "group", "mass", "energy", "price")
    for _, d in ipairs(allItems()) do row(d.id, d.displayName, d.group, d.mass, d.energy, d.startEquilibriumPrice) end
    os.exit(0)
elseif csv == "recipes" then
    row("id", "name", "class", "duration", "inputs", "outputs", "input_cost", "output_value", "margin")
    for _, r in ipairs(Productions:getAll()) do
        local function list(entries)
            local parts, value = {}, 0
            for _, e in ipairs(entries) do
                parts[#parts + 1] = e.item.displayName .. " x" .. e.count
                value = value + price(e.item) * e.count
            end
            return table.concat(parts, "; "), value
        end
        local ins, cost = list(r.inputs)
        local outs, value = list(r.outputs)
        row(r.id, r.displayName, r.class, r.duration, ins, outs, cost, value, value - cost)
    end
    os.exit(0)
elseif csv == "modules" then
    row("id", "name", "item", "slot", "size", "weapon", "add", "scale", "ability", "cooldown", "price")
    local function kv(t)
        local parts = {}
        for k, v in pairs(t or {}) do parts[#parts + 1] = k .. "=" .. v end
        table.sort(parts)
        return table.concat(parts, "; ")
    end
    for _, f in ipairs(Fittings:getAll()) do
        local item = Items:getDefinition(f.itemId)
        row(f.id, f.displayName, item.displayName, f.slot, f.sizeClass, f.weaponId,
            kv(f.effects and f.effects.add), kv(f.effects and f.effects.scale),
            f.ability and f.ability.key, f.ability and f.ability.cooldown, price(item))
    end
    os.exit(0)
elseif csv then
    io.stderr:write("--csv takes items, recipes or modules\n")
    os.exit(1)
end

------------------------------------------------------------------------------
-- Checks
------------------------------------------------------------------------------

local problems = {}
local function problem(fmt, ...) problems[#problems + 1] = string.format(fmt, ...) end

local made, used = {}, {}
for _, r in ipairs(Productions:getAll()) do
    for _, e in ipairs(r.outputs) do made[e.item.id] = made[e.item.id] or r.displayName end
    for _, e in ipairs(r.inputs) do used[e.item.id] = true end
end
local mined = {}
local function addOres(list)
    for _, e in ipairs(list) do mined[e.id] = true end
end
addOres(OreData.fallback())
for _, key in ipairs(OreData.keys()) do addOres(OreData.composition(key)) end

for _, f in ipairs(Fittings:getAll()) do
    if not made[f.itemId] then
        problem("module %d (%s): no recipe makes %s", f.id, f.displayName, Items:getDefinition(f.itemId).displayName)
    end
end
for _, h in ipairs(Hulls:getAll()) do
    if not made[h.itemId] then
        problem("hull %s: no recipe makes %s", h.displayName, Items:getDefinition(h.itemId).displayName)
    end
end
local warnings = {}
for _, r in ipairs(Productions:getAll()) do
    for _, e in ipairs(r.inputs) do
        if not made[e.item.id] and not mined[e.item.id] then
            warnings[#warnings + 1] = string.format("recipe %d (%s) needs %s, which nothing makes or mines (imports only)",
                r.id, r.displayName, e.item.displayName)
        end
    end
end
for id in pairs(mined) do
    if not used[id] and not made[id] then
        warnings[#warnings + 1] = string.format("the ore %s is mined but no recipe uses it (sold only)",
            Items:getDefinition(id).displayName)
    end
end
table.sort(warnings)

local function nextId(ids)
    local max = 0
    for _, id in ipairs(ids) do max = math.max(max, id) end
    return max + 1
end
local itemIds, recipeIds, moduleIds = {}, {}, {}
for _, d in ipairs(allItems()) do itemIds[#itemIds + 1] = d.id end
for _, r in ipairs(Productions:getAll()) do recipeIds[#recipeIds + 1] = r.id end
for _, f in ipairs(Fittings:getAll()) do moduleIds[#moduleIds + 1] = f.id end

print(string.format("items %d (next id %d), recipes %d (next id %d), modules %d (next id %d), ore compositions %d",
    #itemIds, nextId(itemIds), #recipeIds, nextId(recipeIds), #moduleIds, nextId(moduleIds), #OreData.keys()))
for _, w in ipairs(warnings) do print("note: " .. w) end
for _, p in ipairs(problems) do print("PROBLEM: " .. p) end
if #problems > 0 then os.exit(1) end
print("OK")
