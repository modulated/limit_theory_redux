local Component = require("Core.ECS.Component")
local Productions = require("Shared.Registries.Productions")

--- What a station makes: the recipes it runs and how far along each one is.
--- `ProductionSystem` takes the inputs out of the station's `Stock` when a
--- run starts and puts the outputs in when it finishes.
---@class ProductionComponent: Component
---@overload fun(self: ProductionComponent, recipeIds: integer[]|nil): ProductionComponent subclass internal
---@overload fun(recipeIds: integer[]|nil): ProductionComponent subclass external
local ProductionComponent = Subclass("ProductionComponent", Component, function(self, recipeIds)
    self:setComponentName("EconomyProduction")
    --- One line per recipe: { id, progress (seconds done), running (inputs taken) }
    self.lines = {}
    for _, id in ipairs(recipeIds or {}) do self:addRecipe(id) end
end)

--- Run this recipe here too.
---@param recipeId integer
---@return boolean added false when the id names no recipe, or it is already run here
function ProductionComponent:addRecipe(recipeId)
    if not Productions:getDefinition(recipeId) then
        Log.Warn("ProductionComponent: no recipe with id %s", tostring(recipeId))
        return false
    end
    for _, line in ipairs(self.lines) do
        if line.id == recipeId then return false end
    end
    table.insert(self.lines, { id = recipeId, progress = 0, running = false })
    return true
end

---@return table[] lines { id, progress, running }
function ProductionComponent:getLines()
    return self.lines
end

--- The recipes this station runs.
---@return ProductionDefinition[]
function ProductionComponent:getRecipes()
    local recipes = {}
    for _, line in ipairs(self.lines) do
        local def = Productions:getDefinition(line.id)
        if def then recipes[#recipes + 1] = def end
    end
    return recipes
end

return ProductionComponent
