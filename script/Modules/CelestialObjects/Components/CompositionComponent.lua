local Component = require("Core.ECS.Component")

--- What a belt or ring is made of: the list of `{ id, weight }` its ruleset
--- gives it for its field type (rocky, icy), which `MiningField` turns into
--- the ore each rock holds. Empty or nil for a field the ruleset says nothing
--- about; mining then falls back to `Config.game.mining.ores`.
---@class CompositionComponent: Component
---@overload fun(self: CompositionComponent, composition: table|nil): CompositionComponent subclass internal
---@overload fun(composition: table|nil): CompositionComponent subclass external
local CompositionComponent = Subclass("CompositionComponent", Component, function(self, composition)
    self:setComponentName("CelestialCompositionComponent")
    self:setComposition(composition)
end)

---@param composition table|nil list of { id = integer, weight = number }
function CompositionComponent:setComposition(composition)
    self.composition = composition
end

---@return table|nil composition list of { id = integer, weight = number }
function CompositionComponent:getComposition()
    return self.composition
end

return CompositionComponent
