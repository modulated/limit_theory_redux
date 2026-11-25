local Component = require("Core.ECS.Component")

--- A jump gate's place in the galaxy's gate network: the link it is one end
--- of, and the star system at the other end (see GalaxyGenerator).
---@class JumpGateComponent: Component
---@overload fun(self: JumpGateComponent, linkId: integer, systemId: integer, destinationId: integer, destinationName: string): JumpGateComponent subclass internal
---@overload fun(linkId: integer, systemId: integer, destinationId: integer, destinationName: string): JumpGateComponent subclass external
local JumpGateComponent = Subclass("JumpGateComponent", Component, function(self, linkId, systemId, destinationId, destinationName)
    self:setComponentName("NavigationJumpGate")
    self.linkId = linkId
    self.systemId = systemId
    self.destinationId = destinationId
    self.destinationName = destinationName
end)

---@return integer linkId index in Galaxy.links
function JumpGateComponent:getLinkId()
    return self.linkId
end

---@return integer systemId the galaxy system this gate stands in
function JumpGateComponent:getSystemId()
    return self.systemId
end

---@return integer destinationId the galaxy system this gate leads to
function JumpGateComponent:getDestinationId()
    return self.destinationId
end

---@return string
function JumpGateComponent:getDestinationName()
    return self.destinationName
end

return JumpGateComponent
