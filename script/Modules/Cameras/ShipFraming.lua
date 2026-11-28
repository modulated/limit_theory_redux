--- How big a camera's target is, and how close a camera may come to it.
---
--- Every camera that follows a ship keeps outside it: a fixed distance that
--- frames a fighter puts the camera inside a capital hull. The radius is the
--- body's bounding sphere, or its compound one when the hull is built of
--- several colliders, whichever is larger.
local PhysicsComponents = require("Modules.Physics.Components")

local ShipFraming = {}

--- Closest a camera comes to the centre, in target radii
ShipFraming.CLEARANCE = 1.35

---@param body RigidBody|nil
---@return number radius (0 without a body)
function ShipFraming.bodyRadius(body)
    if not body then return 0 end
    local r = body:getBoundingRadius() or 0
    if body.getBoundingRadiusCompound then
        local compound = body:getBoundingRadiusCompound() or 0
        if compound > r then r = compound end
    end
    -- (a NaN radius reads as none)
    if not (r > 0) or r == math.huge then return 0 end
    return r
end

---@param entity Entity|nil
---@return number radius (0 when it has no body)
function ShipFraming.radius(entity)
    if not entity or not entity:isValid() then return 0 end
    local rbCmp = entity:get(PhysicsComponents.RigidBody)
    return ShipFraming.bodyRadius(rbCmp and rbCmp:getRigidBody())
end

--- The closest a camera may sit to the entity's centre.
---@param entity Entity|nil
---@return number
function ShipFraming.minDistance(entity)
    return ShipFraming.radius(entity) * ShipFraming.CLEARANCE
end

return ShipFraming
