local PhysicsComponents   = require("Modules.Physics.Components")
local UIMouse = require("Input.UIMouse")
local ConstructComponents = require("Modules.Constructs.Components")
local ShipActions         = require("Input.ActionBindings.ShipActions")
local GravityWellSystem   = require("Modules.Physics.Systems.GravityWellSystem")

--- Travel Drive System — provides high-speed interplanetary travel.
--- Operates on the TravelDriveComponent attached to ship entities.
---
--- States: Idle -> Charging -> Active -> Decelerating -> Idle
---@class TravelDriveSystem
local TravelDriveSystem = {
    --- The large bodies the drive will not fly into: { entity, kind }.
    bodies = {},
}

--- The system's planets, moons and star, on loading a system.
---@param bodies { entity: Entity, kind: string }[]
function TravelDriveSystem:setBodies(bodies)
    self.bodies = bodies or {}
end

---@param entity Entity
---@return Position|nil position, number radius
local function bodyPlace(entity)
    if not entity:isValid() then return nil, 0 end
    local transform = entity:get(PhysicsComponents.Transform)
    if not transform then return nil, 0 end
    local radius = transform:getScale() or 0
    local rbCmp = entity:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    if body then radius = math.max(radius, body:getBoundingRadius() or 0) end
    return transform:getPos(), radius
end

--- The body the ship will reach within `reach` along its velocity, keeping
--- `margin` radii above the surface: the body's kind, or nil.
---@param rb RigidBody
---@param reach number seconds
---@param margin number
---@return string|nil
function TravelDriveSystem:bodyAhead(rb, reach, margin)
    local vel = rb:getVelocity()
    local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
    if not (speed > 1e-6) then return nil end
    local dx, dy, dz = vel.x / speed, vel.y / speed, vel.z / speed
    local range = speed * reach
    local shipPos = rb:getPos()
    for _, b in ipairs(self.bodies) do
        local pos, radius = bodyPlace(b.entity)
        if pos and radius > 0 then
            local rel = pos:relativeTo(shipPos)
            local along = rel.x * dx + rel.y * dy + rel.z * dz
            local distSq = rel.x * rel.x + rel.y * rel.y + rel.z * rel.z
            local safe = radius * (1 + margin)
            -- Already within the margin (setting off from close by): only a
            -- path into the body itself counts, so leaving it is not stopped
            if distSq < safe * safe then safe = radius * 1.02 end
            -- Heading toward it
            if along > 0 then
                local missSq = distSq - along * along
                if missSq < safe * safe then
                    -- How far to where the path enters the margin
                    local entry = along - math.sqrt(safe * safe - missSq)
                    if entry < range then
                        return require("Modules.CelestialObjects.Managers.CelestialNames"):of(b.entity, b.kind)
                    end
                end
            end
        end
    end
    return nil
end

--- Engaged, the ship passes through everything (the big bodies it is kept
--- off by dropping out); back at normal speed, it collides again.
---@param drive TravelDriveComponent
---@param rb RigidBody
---@param phased boolean
local function setPhased(drive, rb, phased)
    if (drive.phased == true) == phased then return end
    drive.phased = phased
    rb:setCollidable(not phased)
end

--- The drive off at once, the ship solid again (docking: the drive cannot
--- be left engaged, or passing through things, inside a station).
---@param shipEntity Entity|nil
function TravelDriveSystem:reset(shipEntity)
    local drive = shipEntity and shipEntity:isValid() and shipEntity:get(ConstructComponents.TravelDrive)
    if not drive then return end
    drive:setState("idle")
    drive:setCurrentMult(1.0)
    local rbCmp = shipEntity:get(PhysicsComponents.RigidBody)
    local rb = rbCmp and rbCmp:getRigidBody()
    if rb then setPhased(drive, rb, false) end
end

--- Update the travel drive for a ship entity
---@param dt number Delta time
---@param shipEntity Entity
function TravelDriveSystem:update(dt, shipEntity)
    if not shipEntity then return end

    local drive = shipEntity:get(ConstructComponents.TravelDrive)
    if not drive then return end

    local rbCmp = shipEntity:get(PhysicsComponents.RigidBody)
    if not rbCmp then return end
    local rb = rbCmp:getRigidBody()
    if not rb then return end

    local cfg = Config.game.travelDrive
    local state = drive:getState()

    -- Toggle travel drive with dedicated key (T)
    if ShipActions.TravelDrive:isPressed() then
        if state == "idle" then
            drive:setState("charging")
            drive:setChargeTime(0)
            state = "charging"
        elseif state == "active" or state == "charging" then
            drive:setState("decelerating")
            state = "decelerating"
        end
    end

    local currentMult = drive:getCurrentMult()

    if state == "idle" then
        currentMult = math.max(1.0, currentMult - cfg.rampDownSpeed * dt)

    elseif state == "charging" then
        local chargeTime = drive:getChargeTime() + dt
        drive:setChargeTime(chargeTime)
        if chargeTime >= cfg.chargeRequired then
            drive:setState("active")
            drive:setActiveTime(0)
        end
        currentMult = math.max(1.0, currentMult - cfg.rampDownSpeed * dt)

    elseif state == "active" then
        drive:setActiveTime(drive:getActiveTime() + dt)

        -- About to fly into a planet, moon or star: drop out now. Without
        -- the drive's thrust, drag brings the ship down to normal speed in
        -- about 1 / linearDrag seconds of travel, so look that far ahead
        -- (and a little more), and keep a margin above the surface.
        local drop = cfg.dropOut or {}
        local drag = math.max(Config.game.shipFlight.linearDrag or 2, 0.1)
        local kind = self:bodyAhead(rb, 1.5 / drag + (drop.reaction or 0.4), drop.margin or 0.25)
        if kind then
            drive:setState("idle")
            drive:setCurrentMult(1.0)
            setPhased(drive, rb, false)
            if LimitTheoryRedux and LimitTheoryRedux.notify then
                LimitTheoryRedux:notify(string.format("Travel drive disengaged: %s ahead", kind),
                    { 1.0, 0.75, 0.35 })
            end
            return
        end

        -- Zone-based speed cap
        local maxSpeed = GravityWellSystem:getMaxDriveSpeed()

        if currentMult > maxSpeed then
            currentMult = math.max(maxSpeed,
                currentMult - (currentMult - maxSpeed) * cfg.rampDownSpeed * dt)
        else
            currentMult = math.min(maxSpeed,
                currentMult + (maxSpeed - 1) * cfg.rampUpSpeed * dt)
        end

        -- Apply forward thrust
        local rot = rb:getRot()
        local fwd = rot:getForward()
        local thrustForward = Config.game.shipFlight.thrustForward
        rb:applyForce(fwd:scale(thrustForward * currentMult))

    elseif state == "decelerating" then
        currentMult = math.max(1.0, currentMult - (cfg.speedMultiplier - 1) * cfg.rampDownSpeed * dt)
        if currentMult <= 1.1 then
            drive:setState("idle")
            currentMult = 1.0
        end
    end

    drive:setCurrentMult(currentMult)

    -- Through smaller things while engaged and coasting down; solid again
    -- once back to normal speed
    state = drive:getState()
    setPhased(drive, rb, state == "active" or state == "decelerating")

    -- Weapon fire cancels the drive (a click on a panel is not fire)
    if ShipActions.Fire and ShipActions.Fire:get() > 0.5 and not UIMouse.overPanel then
        state = drive:getState()
        if state == "active" or state == "charging" then
            drive:setState("decelerating")
        end
    end
end

return TravelDriveSystem
