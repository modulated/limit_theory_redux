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

--- How much what is fitted helps the ship turn: a module that helps it, or
--- armour plate that does not (ShipFittingSystem writes `fitTurnScale`). It
--- scales how quickly the ship reaches the rate asked for.
---@param shipEntity Entity
---@return number
local function fitTurnScale(shipEntity)
    local flightCtrl = shipEntity:get(ConstructComponents.ShipFlightControl)
    if not flightCtrl then return 1 end
    return flightCtrl.fitTurnScale or 1
end

--- How much the ship's thrust is scaled by what is fitted: engines up,
--- plating and cargo pods down, an afterburner while it burns
--- (ShipFittingSystem writes `fitThrustScale`; AbilitySystem the boost).
---@param shipEntity Entity
---@return number
local function thrustScale(shipEntity)
    local flightCtrl = shipEntity:get(ConstructComponents.ShipFlightControl)
    if not flightCtrl then return 1 end
    return (flightCtrl.fitThrustScale or 1) * (flightCtrl.abilityThrustScale or 1)
end

-- LTR_DEBUG_INPUT=1 logs what the mouse is actually telling the game, once a
-- second while the mouse is steering: the cursor's position against the
-- window's size, the movement reported this frame, the steering that came
-- out of it and the rate the ship is turning at. The numbers say which of
-- those is lying when the ship will not fly straight.
local DEBUG_INPUT = (os.getenv("LTR_DEBUG_INPUT") or "") ~= ""
local debugTimer = 0

---@param rb RigidBody
---@param yaw number
---@param pitch number
---@param spin table the ship's angular velocity, in its own axes
---@param dt number
local function logSteering(rb, yaw, pitch, spin, dt)
    debugTimer = debugTimer + (dt or 0)
    if debugTimer < 1.0 then return end
    debugTimer = 0
    local pos = Input:mouse():position()
    local delta = Input:mouse():delta()
    Log.Info(
        "input: cursor (%.0f, %.0f) of %.0fx%.0f logical, %.0fx%.0f physical" ..
        "  ·  moved (%.1f, %.1f)  ·  steering yaw %.3f pitch %.3f" ..
        "  ·  turning (%.2f, %.2f, %.2f) rad/s  ·  scheme %s",
        pos.x, pos.y, Window:width(), Window:height(),
        Window:physicalWidth(), Window:physicalHeight(),
        delta.x, delta.y, yaw, pitch, spin.x, spin.y, spin.z,
        tostring(Config.game.shipFlight.chaseSteering))
end

--- Steer the ship toward the turn rate the input asks for.
---
--- The input asks for a *rate* (a share of `maxTurnRate`), and the ship's
--- turn rate is moved toward it directly: by `turnRateGain` of the difference
--- a second, never faster than `maxTurnAccel` (scaled by what is fitted), and
--- set on the body as an angular velocity.
---
--- It used to be done with torque, converting the acceleration wanted into a
--- torque through an *estimate* of the hull's inertia (a sphere's). The
--- physics works out the real inertia from the collider's shape, and a long
--- hull's about its roll axis is a small fraction of a sphere's: every
--- correction there landed many times too hard, overshot, and the next one
--- harder still, until the ship span at whatever the torque limit allowed
--- (with `torqueScale` up to 400). The chase camera turns with the ship's up,
--- so the whole view span with it: the "slight mouse movement and the camera
--- goes wild" bug. Setting the rate needs no inertia at all, so it cannot
--- ring, whatever the hull.
---
--- Letting go brings the ship back to straight at the same pace, which also
--- recovers from a spin a collision started.
---@param shipEntity Entity
---@param rb RigidBody
---@param pitch number -1..1
---@param yaw number -1..1
---@param roll number -1..1
---@param dt number
---@param rateScale number|nil a share of the maximum turn rate (travel drive)
local function applySteering(shipEntity, rb, pitch, yaw, roll, dt, rateScale)
    local cfg = Config.game.shipFlight
    local rot = rb:getRot()
    local maxRate = (cfg.maxTurnRate or 1.8) * (rateScale or 1)
    local rollRate = maxRate * (cfg.rollRateShare or 0.6)
    local gain = cfg.turnRateGain or 6.0
    local step = math.max(dt or 0, 1e-4)
    local accelLimit = (cfg.maxTurnAccel or 8.0) * fitTurnScale(shipEntity) * step

    -- Where the ship is turning now, in its own axes
    local spin = rot:inverse():mulV(rb:getVelocityA())

    --- The new rate about one axis: toward the rate asked for, by the gain's
    --- share of the difference, at most the acceleration limit this step.
    local function axisRate(input, current, limit)
        local desired = Math.Clamp(input, -1, 1) * limit
        local change = (desired - current) * math.min(1, gain * step)
        return current + Math.Clamp(change, -accelLimit, accelLimit)
    end

    local x = axisRate(pitch, spin.x, maxRate)
    local y = axisRate(-yaw, spin.y, maxRate)
    local z = axisRate(-roll, spin.z, rollRate)

    -- The physics damps angular velocity by angularDrag during the step that
    -- follows (rapier: by 1 / (1 + dt * damping)); set it that much higher so
    -- the rate the ship turns at is the one worked out here
    local undamp = 1 + step * (cfg.angularDrag or 0)
    rb:setVelocityA(rot:mulV(Vec3f(x * undamp, y * undamp, z * undamp)))

    if DEBUG_INPUT then logSteering(rb, yaw, pitch, spin, dt) end
end

--- Steering from the mouse's *movement*: the ship holds a turn while the
--- mouse is pushed, and the turn decays back to straight when the mouse
--- stops. Nothing here depends on where the cursor is, which is what makes
--- it work when the cursor cannot be trusted -- it is confined at the
--- window's edge, or a remote desktop session is placing it.
---@param shipEntity Entity
---@param dt number
---@return number yaw
---@return number pitch
local function movementSteering(shipEntity, dt)
    local flightCtrl = shipEntity:get(ConstructComponents.ShipFlightControl)
    if not flightCtrl then return 0, 0 end
    local cfg = Config.game.shipFlight
    local delta = Input:mouse():delta()
    local sx = math.max(Window:width(), 1)
    local sy = math.max(Window:height(), 1)
    local sens = UserSettings.mouseSensitivityFactor() -- Mouse Sensitivity setting

    local yaw = Math.Clamp(flightCtrl:getTargetYaw() + delta.x / sx * sens, -0.8, 0.8)
    local pitch = Math.Clamp(flightCtrl:getTargetPitch() - delta.y / sy * sens, -0.8, 0.8)

    -- Back toward straight when the mouse stops. Clamped so a long frame
    -- cannot send the factor negative and flip the turn.
    local keep = Math.Clamp(1.0 - (cfg.steeringDecay or 4.0) * dt, 0, 1)
    flightCtrl:setTargetYaw(yaw * keep)
    flightCtrl:setTargetPitch(pitch * keep)

    -- Dead zones
    if math.abs(yaw) < 0.004 then yaw = 0 end
    if math.abs(pitch) < 0.008 then pitch = 0 end
    return yaw, pitch
end

--- What the mouse is asking the ship to do, by the scheme in force.
---@param shipEntity Entity
---@param dt number
---@param useDelta boolean first person: always by movement
---@return number yaw
---@return number pitch
local function mouseSteering(shipEntity, dt, useDelta)
    local scheme = Config.game.shipFlight.chaseSteering or "movement"
    if useDelta or scheme ~= "cursor" then
        return movementSteering(shipEntity, dt)
    end
    return cursorSteering()
end

--- Update ship from input.
---@param dt number
---@param shipEntity Entity
---@param mouseAim boolean Mouse controls ship rotation
---@param useDelta boolean First person (always steers by movement)
function ShipFlightSystem:update(dt, shipEntity, mouseAim, useDelta)
    if not shipEntity then return end

    local rbCmp = shipEntity:get(PhysicsComponents.RigidBody)
    if not rbCmp then return end
    local rb = rbCmp:getRigidBody()
    if not rb then return end

    local cfg = Config.game.shipFlight

    local fitThrust = thrustScale(shipEntity)
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
        yaw, pitch = mouseSteering(shipEntity, dt, useDelta)
        yaw, pitch = applyInversion(yaw, pitch)
    end

    -- Boost (matches legacy: 1.0 + 2.0 * boost)
    local mult = 1.0 + 2.0 * boost

    -- Ship orientation
    local rot = rb:getRot()

    -- Apply translational forces
    if math.abs(forward) > 1e-6 then
        rb:applyForce(rot:getForward():scale(forward * cfg.thrustForward * mult * fitThrust))
    end
    if math.abs(right) > 1e-6 then
        rb:applyForce(rot:getRight():scale(right * cfg.thrustRight * 0.5 * fitThrust))
    end
    if math.abs(up) > 1e-6 then
        rb:applyForce(rot:getUp():scale(up * cfg.thrustUp * fitThrust))
    end

    -- Steer toward the rate asked for (and brake toward a stop with no input)
    applySteering(shipEntity, rb, pitch, yaw, roll, dt)
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

    local roll = ShipActions.Roll:get()
    local yaw, pitch = 0, 0
    if mouseAim then
        yaw, pitch = mouseSteering(shipEntity, dt, useDelta)
        yaw, pitch = applyInversion(yaw, pitch)
    end

    -- A tenth of the turn rate under travel drive: the ship is covering
    -- ground, not dogfighting
    applySteering(shipEntity, rb, pitch, yaw, roll, dt, 0.1)
end

--- Turn a ship at a rate (shares of maxTurnRate), the way manual flight
--- does: for the autopilot, which must not steer by torque either.
---@param shipEntity Entity
---@param pitch number -1..1
---@param yaw number -1..1
---@param dt number
function ShipFlightSystem:steer(shipEntity, pitch, yaw, dt)
    local rbCmp = shipEntity and shipEntity:get(PhysicsComponents.RigidBody)
    local rb = rbCmp and rbCmp:getRigidBody()
    if not rb then return end
    applySteering(shipEntity, rb, pitch, yaw, 0, dt)
end

--- How much the ship's thrust is scaled by what is fitted (and an
--- afterburner): for the autopilot's engine limit.
---@param shipEntity Entity
---@return number
function ShipFlightSystem:thrustScale(shipEntity)
    return thrustScale(shipEntity)
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
