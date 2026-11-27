---One item of the game's economy. `name` is the key the registry files it
---under: the plain letters of the name (`IronOre`, `ShipEngineThruster`).
---`displayName` is the name as it was written ("Iron Ore", "Ship Engine,
---Thruster") and is what the UI and the logs show. `id` is
---written by hand in `res/data/items.toml` and must never change:
---see the note in `Shared/Registries/Items.lua`.
---@class ItemDefinition
---@field id integer
---@field group string
---@field name string
---@field displayName string
---@field mass number
---@field energy number
---@field startEquilibriumPrice number|nil
---@overload fun(args: {id: integer, name: string, mass: number, energyDensity: number, startEquilibriumPrice: number|nil, displayName: string|nil}): ItemDefinition
local ItemDefinition = Class("ItemDefinition")

function ItemDefinition.new(args)
    if not args.name then
        Log.Warn("No name Set for ItemDefinition")
        return nil
    end

    local self = setmetatable({}, ItemDefinition)
    self.id = args.id
    self.name = args.name
    self.displayName = args.displayName or args.name
    self.mass = args.mass
    self.energy = Math.Round(math.max(0, (args.energyDensity or 1) * args.mass))
    self.startEquilibriumPrice = args.startEquilibriumPrice or nil
    return self
end

return ItemDefinition
