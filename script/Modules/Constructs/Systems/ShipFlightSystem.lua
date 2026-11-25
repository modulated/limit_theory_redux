local PhysicsComponents   = require("Modules.Physics.Components")
local ConstructComponents = require("Modules.Constructs.Components")
local ShipActions         = require("Input.ActionBindings.ShipActions")
local UserSettings        = require("Shared.UserSettings")

--- Ship flight system — direct port of Legacy ThrustController into ECS.
--- Raw input -> forces/torques each frame. Physics handles the rest.
--- Per-ship FPS aiming state stored in ShipFlightControlComponent.
---@class ShipFlightSystem
local ShipFlightSystem = {}

-- Chase steering: the cursor's offset from the screen centre, as a fraction
-- of the half-screen, is the turn rate. Within the dead zone (around the
-- centre, where the cursor rests) the ship holds its heading.
local CURSOR_DEAD_ZONE = 0.06

--- Turn rate toward the cursor (chase): the cursor's offset from the screen
--- centre, outside the dead zone, scaled by the Mouse Sensitivity setting.
--- Also the gamepad's right stick (the same bindings).
---@return number yaw
---@return number pitch
local function cursorSteering()
    local yaw = ShipActions.Yaw:get()
    local pitch = ShipActions.Pitch:get()
    local len = math.sqrt(yaw * yaw + pitch * pitch)
    if len < CURSOR_DEAD_ZONE then return 0, 0 end
    -- Rescale so the rate starts from 0 at the dead zone's edge
    local scale = (len - CURSOR_DEAD_ZONE) / (1 - CURSOR_DEAD_ZONE) / len
        * UserSettings.mouseSensitivityFactor()
    return Math.Clamp(yaw * scale, -1, 1), Math.Clamp(pitch * scale, -1, 1)
end

--- The Invert Vertical Look setting (and the config's inversions), read every
--- frame so changing it applies straight away.
---@return number yaw
---@return number pitch
local function applyInversion(yaw, pitch)
    local cfg = Config.game.shipFlight
    if cfg.invertYaw then yaw = -yaw end
    if cfg.invertPitch or GameState.input.invertPitch then pitch = -pitch end
    return yaw, pitch
end

--- How much a ship's turning torque is scaled: a bigger hull of the same
--- mass turns slower (inertia grows with the radius squared), so a ship can
--- carry a multiplier that keeps the reference fighter's feel
--- (ShipFlightControl.torqueScale, set when the ship is built; default 1).
local function torqueScale(shipEntity)
    local flightCtrl = shipEntity:get(ConstructComponents.ShipFlightControl)
    return flightCtrl and flightCtrl.torqueScale or 1
end

--- Update ship from input.
---@param dt number
---@param shipEntity Entity
---@param mouseAim boolean Mouse controls ship rotation
---@param useDelta boolean Use mouse delta (first person) vs steering toward the cursor (chase)
function ShipFlightSystem:update(dt, shipEntity, mouseAim, useDelta)
    if not shipEntity then return end

    local rbCmp = shipEntity:get(PhysicsComponents.RigidBody)
    if not rbCmp then return end
    local rb = rbCmp:getRigidBody()
    if not rb then return end

    local cfg = Config.game.shipFlight

    -- Read thrust input
    local forward = ShipActions.ThrustZ:get()
    local right   = ShipActions.ThrustX:get()
    local up      = ShipActions.ThrustY:get()
    local roll    = ShipActions.Roll:get()
    local boost   = ShipActions.Boost:get()

    -- Disable boost during travel drive
    local drive = shipEntity:get(ConstructComponents.TravelDrive)
    if drive and drive:isActive() then
        boost = 0
    end

    -- Read rotation input
    local yaw   = 0
    local pitch = 0
    if mouseAim then
        if useDelta then
            -- FPS mode: indirect aiming with accumulation and decay
            local flightCtrl = shipEntity:get(ConstructComponents.ShipFlightControl)
            if flightCtrl then
                local delta = Input:mouse():delta()
                local sx = Window:width()
                local sy = Window:height()
                local sens = UserSettings.mouseSensitivityFactor() -- Mouse Sensitivity setting

                local tYaw = Math.Clamp(
                    flightCtrl:getTargetYaw() + delta.x / sx * sens, -0.8, 0.8)
                local tPitch = Math.Clamp(
                    flightCtrl:getTargetPitch() - delta.y / sy * sens, -0.8, 0.8)

                yaw   = tYaw
                pitch = tPitch

                -- Decay toward center when mouse stops
                flightCtrl:setTargetYaw(tYaw * (1.0 - 4.0 * dt))
                flightCtrl:setTargetPitch(tPitch * (1.0 - 4.0 * dt))
            end
            -- Dead zones
            if math.abs(yaw)   < 0.004 then yaw   = 0 end
            if math.abs(pitch) < 0.008 then pitch = 0 end
        else
            -- Chase: turn toward the cursor (legacy style)
            yaw, pitch = cursorSteering()
        end
        yaw, pitch = applyInversion(yaw, pitch)
    end

    -- Boost (matches legacy: 1.0 + 2.0 * boost)
    local mult = 1.0 + 2.0 * boost

    -- Ship orientation
    local rot = rb:getRot()

    -- Apply translational forces
    if math.abs(forward) > 1e-6 then
        rb:applyForce(rot:getForward():scale(forward * cfg.thrustForward * mult))
    end
    if math.abs(right) > 1e-6 then
        rb:applyForce(rot:getRight():scale(right * cfg.thrustRight * 0.5))
    end
    if math.abs(up) > 1e-6 then
        rb:applyForce(rot:getUp():scale(up * cfg.thrustUp))
    end

    -- Apply torque in local space
    if math.max(math.max(math.abs(pitch), math.abs(yaw)), math.abs(roll)) > 1e-6 then
        local k = torqueScale(shipEntity)
        local localTorque = Vec3f(
            pitch * cfg.torquePitch * k,
            -yaw  * cfg.torqueYaw * k,
            -roll * cfg.torqueRoll * 0.5 * k
        )
        rb:applyTorque(rot:mulV(localTorque))
    end
end

--- Reduced steering only (for travel drive — no thrust, slower rotation)
---@param dt number
---@param shipEntity Entity
---@param mouseAim boolean Mouse controls ship rotation
---@param useDelta boolean Use mouse delta (first person) vs steering toward the cursor (chase)
function ShipFlightSystem:updateSteeringOnly(dt, shipEntity, mouseAim, useDelta)
    if not shipEntity then return end

    local rbCmp = shipEntity:get(PhysicsComponents.RigidBody)
    if not rbCmp then return end
    local rb = rbCmp:getRigidBody()
    if not rb then return end

    local cfg = Config.game.shipFlight
    local roll = ShipActions.Roll:get()
    local yaw, pitch = 0, 0
    if mouseAim then
        if useDelta then
            local delta = Input:mouse():delta()
            local sx, sy = Window:width(), Window:height()
            local sens = UserSettings.mouseSensitivityFactor()
            yaw   = Math.Clamp(delta.x / sx * 4.0 * sens, -1.0, 1.0)
            pitch = Math.Clamp(-delta.y / sy * 4.0 * sens, -1.0, 1.0)
            if math.abs(yaw)   < 0.0001 then yaw   = 0 end
            if math.abs(pitch) < 0.0001 then pitch = 0 end
        else
            yaw, pitch = cursorSteering()
        end
        yaw, pitch = applyInversion(yaw, pitch)
    end

    -- Reduced torque at high speed (10% of normal)
    local steerFactor = 0.1
    local rot = rb:getRot()
    if math.max(math.max(math.abs(pitch), math.abs(yaw)), math.abs(roll)) > 1e-6 then
        local k = torqueScale(shipEntity) * steerFactor
        local localTorque = Vec3f(
            pitch * cfg.torquePitch * k,
            -yaw  * cfg.torqueYaw * k,
            -roll * cfg.torqueRoll * 0.5 * k
        )
        rb:applyTorque(rot:mulV(localTorque))
    end
end

---@param shipEntity Entity
---@return number
function ShipFlightSystem:getSpeed(shipEntity)
    local rbCmp = shipEntity:get(PhysicsComponents.RigidBody)
    if not rbCmp then return 0 end
    local rb = rbCmp:getRigidBody()
    if not rb then return 0 end
    return rb:getSpeed()
end

return ShipFlightSystem
