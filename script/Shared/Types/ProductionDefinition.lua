---One thing a station can do with its stock: take the inputs, wait, hand back
---the outputs. The port of Legacy's `Systems/Economy/Production.lua` and the
---recipes of `Legacy/GameObjects/Elements/Economy/Content.lua`.
---
---`id` is written by hand in `Shared/Definitions/ProductionDefs.lua` and must
---never change or be reused, for the same reason item ids must not: a station
---records which recipes it runs. `name` is the lookup key, the plain letters
---of the name; `displayName` is the name as written.
---@class ProductionDefinition
---@field id integer
---@field name string
---@field displayName string
---@field class string one of the ProductionClass values ("Powerplant", ...)
---@field inputs { item: ItemDefinition, count: integer }[]
---@field outputs { item: ItemDefinition, count: integer }[]
---@field duration number seconds for one run at Legacy's pace
---@overload fun(args: table): ProductionDefinition
local ProductionDefinition = Class("ProductionDefinition")

--- What kind of place runs a recipe (Legacy's P0..P4).
ProductionDefinition.Class = {
    Powerplant = "Powerplant", -- P0: makes energy out of fuel or sunlight
    Refinery   = "Refinery",   -- P1: ore and ice into elements
    Factory    = "Factory",    -- P2: elements into parts and goods
    Drydock    = "Drydock",    -- P3: parts into hulls and stations
    Misc       = "Misc",       -- P4: everything else
}

---@param args { id: integer, name: string, class: string, duration: number, inputs: table[]|nil, outputs: table[]|nil }
function ProductionDefinition.new(args)
    assert(args.name, "ProductionDefinition needs a name")
    assert(args.class, "production '" .. args.name .. "' needs a class")
    local self = setmetatable({}, ProductionDefinition)
    self.id = args.id
    self.displayName = args.displayName or args.name
    self.name = (args.name:gsub("[^%w]", ""))
    self.class = args.class
    self.inputs = args.inputs or {}
    self.outputs = args.outputs or {}
    self.duration = args.duration or 1
    return self
end

--- The recipe in one line, e.g. "Iron Refinery: Energy Cell x5, Iron Ore x7 -> Iron x1, Waste x4".
---@return string
function ProductionDefinition:describe()
    local function list(entries)
        if #entries == 0 then return "nothing" end
        local parts = {}
        for _, entry in ipairs(entries) do
            parts[#parts + 1] = string.format("%s x%d", entry.item.displayName, entry.count)
        end
        return table.concat(parts, ", ")
    end
    return string.format("%s: %s -> %s", self.displayName, list(self.inputs), list(self.outputs))
end

return ProductionDefinition
