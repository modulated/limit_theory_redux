local CameraController = require("Modules.Cameras.Managers").CameraController
local PhysicsComponents = require("Modules.Physics.Components")

local UIMouse = require("Input.UIMouse")
local FreeLook = require("Modules.Cameras.FreeLook")
local ConstructComponents = require("Modules.Constructs.Components")
--- NaN is the only value that is not equal to itself; infinities compare
--- out of range.
---@param v number
---@return boolean
local function isFiniteNumber(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

---@param p Position|Vec3f
---@return boolean
local function isFinitePosition(p)
    return p ~= nil and isFiniteNumber(p.x) and isFiniteNumber(p.y) and isFiniteNumber(p.z)
end

---@param q Quat
---@return boolean
local function isFiniteQuat(q)
    return q ~= nil and isFiniteNumber(q.x) and isFiniteNumber(q.y)
        and isFiniteNumber(q.z) and isFiniteNumber(q.w)
end

--- Chase camera — follows behind the ship, smoothly interpolating.
--- Direct port of Legacy CameraChase into ECS controller pattern.
---@class ChaseCameraController : CameraController
---@overload fun(entity: Entity, config?: table): ChaseCameraController
local ChaseCameraController = Subclass("ChaseCameraController", CameraController, function(self, entity, config)
    self:initController(entity)

    config = config or {}

    self.target    = nil
    self.posRel    = config.posRel or Vec3f(0, 2.5, -10)     -- Position behind/above ship (local space)
    self.lookAtRel = config.lookAtRel or Vec3f(0, 0, 1000)   -- Look-at point ahead of ship (local space)
    self.radius    = config.radius or 1.0                     -- Zoom multiplier
    self.radiusT   = self.radius
    self.minRadius = config.minRadius or 0.5
    self.maxRadius = config.maxRadius or 10.0
    self.zoomSpeed = config.zoomSpeed or 0.1

    -- Smoothed position and rotation (lerp targets)
    self.posT   = Position(0, 0, 0)
    self.rotT   = Quat.Identity()
    self.posSmooth = Position(0, 0, 0)
    -- The camera's place relative to the ship, smoothed (not its place in
    -- the world: see onPreRender)
    self.offsetSmooth = { x = 0, y = 0, z = 0 }
    -- How far back the travel drive has drawn the camera (0..1, smoothed)
    self.warpPull = 0
    self.rotSmooth = Quat.Identity()
    self.initialized = false
end)

---@param target Entity
function ChaseCameraController:setTarget(target)
    self.target = target
    self.initialized = false
end

function ChaseCameraController:modRadius(scrollDelta)
    -- Exponential zoom: each scroll tick multiplies radius by a fixed factor
    -- Feels proportional at all distances
    local factor = math.exp(-scrollDelta * self.zoomSpeed)
    self.radiusT = Math.Clamp(self.radiusT * factor, self.minRadius, self.maxRadius)
end

function ChaseCameraController:onInput(dt)
    if not self.enabled or not Window:isFocused() then return end

    -- Zoom with mouse wheel (not over a panel)
    local scroll = Input:mouse():value(MouseControl.ScrollY)
    if math.abs(scroll) > 0.001 and not UIMouse.overPanel then
        self:modRadius(scroll)
    end
end

function ChaseCameraController:onPreRender(dt)
    if not self.enabled or not self.target then return end

    -- Smooth radius
    local f = 1.0 - math.exp(-8.0 * dt)
    self.radius = self.radius + (self.radiusT - self.radius) * f

    -- Get ship rigid body
    local rbCmp = self.target:get(PhysicsComponents.RigidBody)
    if not rbCmp then return end
    local rb = rbCmp:getRigidBody()
    if not rb then return end

    local shipPos = rb:getPos()
    local shipRot = rb:getRot()
    -- A ship whose physics went bad (not a number anywhere in its transform)
    -- is not followed: the camera holds where it was, and says once what
    -- was wrong, which is the lead to where it went bad
    if not isFinitePosition(shipPos) or not isFiniteQuat(shipRot) then
        if not self.reportedBadShip then
            self.reportedBadShip = true
            Log.Warn("ChaseCamera: the ship's %s is not finite (pos %s, rot %s); holding the camera",
                isFinitePosition(shipPos) and "rotation" or "position", tostring(shipPos), tostring(shipRot))
        end
        return
    end
    local shipFwd = shipRot:getForward()
    local shipRt  = shipRot:getRight()
    local shipUp  = shipRot:getUp()
    -- Scale relative position by ship radius and zoom. The camera
    -- distance is proportional to the target's actual radius (same
    -- convention as the benchmark's body zoom: dist = radius * factor),
    -- so a 50m fighter and a 500m cruiser both sit at the same multiple
    -- of their own size. A floor of 1 GU would treat every small ship as
    -- a 1 GU object and push the camera hundreds of ship-lengths away.
    local shipRadius = math.max(rb:getBoundingRadius(), 1e-4)
    -- In travel, the camera draws back a little as the drive winds up (a
    -- stretch, with the ship held in the middle of the warp), and comes
    -- back in as it winds down
    local drive = self.target:get(ConstructComponents.TravelDrive)
    local mult = drive and drive:getCurrentMult() or 1
    if not isFiniteNumber(mult) then mult = 1 end
    local pullT = mult > 1.5 and math.min(1, math.log(mult) / math.log(40000)) or 0
    self.warpPull = self.warpPull + (pullT - self.warpPull) * (1.0 - math.exp(-2.0 * dt))
    if not isFiniteNumber(self.warpPull) then self.warpPull = 0 end
    if not isFiniteNumber(self.radius) then self.radius = self.radiusT end
    local scale = 0.25 * self.radius * shipRadius * (1 + 0.35 * self.warpPull)
    -- Free look (right button held) swings the camera round the ship
    local prx, pry, prz = FreeLook.apply(self.posRel.x, self.posRel.y, self.posRel.z)
    local pr = { x = prx, y = pry, z = prz }

    -- Transform posRel from ship-local to world space (matches legacy toWorld)
    self.posT = Position(
        shipPos.x + (shipRt.x * pr.x + shipUp.x * pr.y + shipFwd.x * pr.z) * scale,
        shipPos.y + (shipRt.y * pr.x + shipUp.y * pr.y + shipFwd.y * pr.z) * scale,
        shipPos.z + (shipRt.z * pr.x + shipUp.z * pr.y + shipFwd.z * pr.z) * scale
    )

    -- Look-at point in world space (far ahead of ship)
    local la = self.lookAtRel
    local lookWorld = Vec3f(
        shipPos.x + (shipRt.x * la.x + shipUp.x * la.y + shipFwd.x * la.z),
        shipPos.y + (shipRt.y * la.x + shipUp.y * la.y + shipFwd.y * la.z),
        shipPos.z + (shipRt.z * la.x + shipUp.z * la.y + shipFwd.z * la.z)
    )

    -- Compute target rotation: look from camera toward ship (always valid direction)
    local lookDir = Vec3f(
        shipPos.x - self.posT.x,
        shipPos.y - self.posT.y,
        shipPos.z - self.posT.z
    )
    local len = lookDir:length()
    -- (written so a NaN length takes this branch too)
    if not (len > 1e-6) then
        lookDir = shipFwd
    else
        lookDir = lookDir:normalize()
    end
    self.rotT = Quat.FromLook(lookDir, shipUp)

    -- Smoothing (1 - exp(-10 * dt)) of where the camera sits *relative to
    -- the ship*, not of where it is in the world. Smoothing the world
    -- position trails a tenth of a second of travel behind: unnoticed at
    -- flight speed, tens of thousands of kilometres in travel mode, where
    -- the ship shot off into the distance and the camera was left behind.
    -- Relative to the ship, the camera is held to it at any speed and still
    -- swings round smoothly when the ship turns.
    local offX, offY, offZ = self.posT.x - shipPos.x, self.posT.y - shipPos.y, self.posT.z - shipPos.z
    local off = self.offsetSmooth
    if not self.initialized then
        off.x, off.y, off.z = offX, offY, offZ
        self.rotSmooth = self.rotT
        self.initialized = true
    else
        local lerpF = 1.0 - math.exp(-10.0 * dt)
        off.x = off.x + (offX - off.x) * lerpF
        off.y = off.y + (offY - off.y) * lerpF
        off.z = off.z + (offZ - off.z) * lerpF
        self.rotSmooth = self.rotSmooth:slerp(self.rotT, lerpF)
    end
    self.posSmooth = Position(shipPos.x + off.x, shipPos.y + off.y, shipPos.z + off.z)

    -- A number that is not a number poisons everything downstream: slerp
    -- keeps it, the view matrix inherits it, and the frame is drawn from
    -- garbage. Quat.FromLook no longer produces one, but a target whose
    -- physics went bad still could, so the last good transform is kept
    -- rather than passed on.
    if not isFinitePosition(self.posSmooth) or not isFiniteQuat(self.rotSmooth) then
        Log.Warn("ChaseCamera: the target's transform is not finite; holding the last good one")
        self.posSmooth = self.transform:getPos()
        self.rotSmooth = self.transform:getRot()
        self.initialized = false
        return
    end

    -- Set camera transform directly
    self.transform:setPos(self.posSmooth)
    self.transform:setRot(self.rotSmooth)
end

return ChaseCameraController
