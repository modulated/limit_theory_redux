local CameraController  = require("Modules.Cameras.Managers").CameraController
local PhysicsComponents = require("Modules.Physics.Components")
local CameraActions     = require("Input.ActionBindings.CameraActions")
local CursorManager     = require("Input.CursorManager")
local UserSettings      = require("Shared.UserSettings")

---@class OrbitCameraController : CameraController
---@overload fun(entity: Entity, config?: table): OrbitCameraController
local OrbitCameraController = Subclass("OrbitCameraController", CameraController, function(self, entity, config)
    self:initController(entity)

    config = config or {}

    self.target = nil
    self.targetOffset = config.targetOffset or Vec3f(0, 0, 0)

    self.distance = config.distance or 20.0
    self.minDistance = config.minDistance or 2.0
    self.maxDistance = config.maxDistance or 100.0
    self.zoomSpeed = config.zoomSpeed or 5.0
    -- When set, each zoom step changes the distance by this fraction of it
    -- (for targets of very different sizes) instead of by zoomSpeed.
    self.zoomRatio = config.zoomRatio

    self.mouseSensitivity = config.mouseSensitivity or 0.003
    self.yaw = config.initialYaw or 0.0
    self.pitch = config.initialPitch or 0.3
    self.minPitch = config.minPitch or -math.pi / 2 + 0.01
    self.maxPitch = config.maxPitch or math.pi / 2 - 0.01

    self.smoothing = config.smoothing or 0.1
    self.currentDistance = self.distance

    -- Right mouse held: the cursor is hidden and held in the window, so the
    -- drag can't wander off it (or out of the window)
    self.dragging = false
end)

function OrbitCameraController:setTarget(target)
    self.target = target
    self:updateCameraPosition(0)
end

function OrbitCameraController:setTargetOffset(offset)
    self.targetOffset = offset
end

function OrbitCameraController:setDistance(distance)
    self.distance = Math.Clamp(distance, self.minDistance, self.maxDistance)
end

---Sets the zoom range and jumps to the distance (no zoom animation).
---@param distances { distance: number, minDistance: number, maxDistance: number, zoomSpeed: number|nil, zoomRatio: number|nil }
function OrbitCameraController:setDistances(distances)
    self.minDistance = distances.minDistance
    self.maxDistance = distances.maxDistance
    self.zoomSpeed = distances.zoomSpeed or self.zoomSpeed
    self.zoomRatio = distances.zoomRatio
    self.distance = Math.Clamp(distances.distance, self.minDistance, self.maxDistance)
    self.currentDistance = self.distance
end

---The zoom range and distance, as `setDistances` takes them.
function OrbitCameraController:getDistances()
    return {
        distance = self.distance,
        minDistance = self.minDistance,
        maxDistance = self.maxDistance,
        zoomSpeed = self.zoomSpeed,
        zoomRatio = self.zoomRatio,
    }
end

--- Start or end the right-mouse drag: hide and hold the cursor while it
--- lasts, free it after.
---@param dragging boolean
function OrbitCameraController:setDragging(dragging)
    if dragging == self.dragging then return end
    self.dragging = dragging
    if dragging then
        CursorManager:locked()
    else
        CursorManager:free()
    end
end

--- Disabled mid-drag (a camera switch, a map): the drag ends without
--- touching the cursor, which whatever comes next sets.
function OrbitCameraController:disable()
    self.dragging = false
    CameraController.disable(self)
end

---@param dt number
function OrbitCameraController:onInput(dt)
    if not self.enabled or not Window:isFocused() then
        -- The window lost focus mid-drag: let go of the cursor
        if self.dragging then self:setDragging(false) end
        return
    end

    -- Update bindings
    CameraActions.Yaw:update(dt)
    CameraActions.Pitch:update(dt)
    CameraActions.Zoom:update(dt)
    CameraActions.MouseCapture:update(dt)

    -- Hold right mouse to rotate (CameraActions.Yaw/Pitch are Combo with
    -- MouseRight). A right press over a panel is the panel's (the overview's
    -- context menu): it starts no drag, though a drag begun elsewhere carries
    -- on across one.
    local overPanel = GameState.ui.mouseOverPanel
    self:setDragging(CameraActions.MouseCapture:isDown() and (self.dragging or not overPanel))

    -- The Mouse Sensitivity setting scales the mouse; Invert Vertical Look
    -- flips up and down
    local sensitivity = self.mouseSensitivity * UserSettings.mouseSensitivityFactor()
    local invertY = GameState.input.invertPitch and -1 or 1
    local yawInput = self.dragging and CameraActions.Yaw:get() or 0
    local pitchInput = self.dragging and CameraActions.Pitch:get() or 0
    if math.abs(yawInput) > 0.001 or math.abs(pitchInput) > 0.001 then
        self.yaw   = self.yaw - yawInput * sensitivity
        self.pitch = self.pitch + pitchInput * invertY * sensitivity
        self.pitch = Math.Clamp(self.pitch, self.minPitch, self.maxPitch)
    end

    -- Zoom (not with the wheel over a panel)
    local zoom = overPanel and 0 or CameraActions.Zoom:get()
    if math.abs(zoom) > 0.001 then
        local distance
        if self.zoomRatio then
            distance = self.distance * math.max(0.1, 1 - zoom * self.zoomRatio)
        else
            distance = self.distance - zoom * self.zoomSpeed
        end
        self.distance = Math.Clamp(distance, self.minDistance, self.maxDistance)
    end
end

---@param dt number
function OrbitCameraController:onPreRender(dt)
    if not self.enabled then return end
    self:updateCameraPosition(dt)
end

function OrbitCameraController:updateCameraPosition(dt)
    -- A target destroyed this frame (a ship being looked at, shot down):
    -- hold where the camera is until the game points it somewhere else,
    -- rather than read the missing body as the system's origin
    if not self.target or not self.target:isValid() then return end

    local zoomLerp = math.min(1.0, 4.0 * dt)
    self.currentDistance = self.currentDistance + (self.distance - self.currentDistance) * zoomLerp

    -- The target's rigid body, or its Transform when it has no body (an
    -- empty anchor, an effect)
    local targetPos = Position(0, 0, 0)
    local rbCmp = self.target:get(PhysicsComponents.RigidBody)
    if rbCmp and rbCmp:getRigidBody() then
        targetPos = rbCmp:getRigidBody():getPos()
    else
        local transform = self.target:get(PhysicsComponents.Transform)
        if transform then
            targetPos = transform:getPos()
        end
    end

    local cx = targetPos.x + self.targetOffset.x
    local cy = targetPos.y + self.targetOffset.y
    local cz = targetPos.z + self.targetOffset.z

    local cosPitch = math.cos(self.pitch)
    local camPos = Position(
        cx + cosPitch * math.sin(self.yaw) * self.currentDistance,
        cy + math.sin(self.pitch) * self.currentDistance,
        cz + cosPitch * math.cos(self.yaw) * self.currentDistance
    )

    self.transform:setPos(camPos)

    local lookDir = Vec3f(cx - camPos.x, cy - camPos.y, cz - camPos.z):normalize()
    local rot = Quat.FromLook(lookDir, Vec3f(0, 1, 0))
    self.transform:setRot(rot)
end

function OrbitCameraController:getAngles()
    return self.yaw, self.pitch
end

function OrbitCameraController:setAngles(yaw, pitch)
    self.yaw = yaw
    self.pitch = Math.Clamp(pitch, self.minPitch, self.maxPitch)
end

return OrbitCameraController
