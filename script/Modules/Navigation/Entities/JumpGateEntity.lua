local PhysicalEntity = require("Modules.PhysicalEntity")
local Physics = require("Modules.Physics.Components")
local Rendering = require("Modules.Rendering.Components")
local Core = require("Modules.Core.Components")
local Navigation = require("Modules.Navigation.Components")

---A jump gate: a ring that leads to another star system.
---@param seed integer
---@param meshes MeshWithMaterial[]
---@param gate JumpGateComponent where it leads
---@return Entity
return function(seed, meshes, gate)
    return PhysicalEntity("JumpGateEntity", seed,
        Physics.RigidBody(),
        Rendering.Render(meshes),
        Core.Name("Gate to " .. gate:getDestinationName()),
        gate)
end
