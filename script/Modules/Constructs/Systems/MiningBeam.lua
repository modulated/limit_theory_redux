local Entity = require("Core.ECS.Entity")
local Registry = require("Core.ECS.Registry")
local Physics = require("Modules.Physics.Components")
local Rendering = require("Modules.Rendering.Components")
local CameraManager = require("Modules.Cameras.Managers.CameraManager")
local Pipelines = require("Render.Pipelines")
local ffi = require("ffi")

--- The mining laser, seen: while the laser runs, a beam from the ship's nose
--- to the rock, cutting at one spot on the face toward the ship, then
--- lifting and striking another. Each strike flares in, holds with a
--- flicker, and the hit point glows (a point light at the cut).
---
--- One entity while it runs (a render fn and the light), gone when it stops.
--- Looks only: what is cut and when is LimitTheoryRedux:updateMining's.
---@class MiningBeam
local MiningBeam = {
    entity = nil,
    state = nil,
}

local COLOR = { 1.00, 0.55, 0.20 }  -- a hot orange cutting beam
local LIGHT_COLOR = Color(1.0, 0.6, 0.25, 1.0)
local WIDTH = 0.004                  -- game units (40 m)
local STRIKE_MIN, STRIKE_MAX = 0.7, 1.6 -- seconds on one spot
local GAP = 0.09                     -- seconds the beam is off between spots
local FLARE = 0.12                   -- seconds a strike takes to come up

local beamMesh, beamShader, DrawBlock

local rng = RNG.Create(7331)

---@param entity Entity|nil
---@return Position|nil, number radius, Quat|nil
local function place(entity)
    if not entity or not entity:isValid() then return nil, 0, nil end
    local rbCmp = entity:get(Physics.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    if body then return body:getPos(), body:getBoundingRadius() or 0, body:getRot() end
    local transform = entity:get(Physics.Transform)
    if transform then return transform:getPos(), transform:getScale() or 0, nil end
    return nil, 0, nil
end

--- A new spot on the rock's face toward the ship: a direction from the
--- rock's centre, kept in the rock's own frame so the cut turns with it.
---@param s table
local function newSpot(s)
    local shipPos = place(s.ship)
    local rockPos = place(s.rock)
    if not shipPos or not rockPos then return end
    local rel = shipPos:relativeTo(rockPos)
    local len = rel:length()
    if len < 1e-9 then return end
    -- Toward the ship, tipped by up to ~55 degrees
    local x, y, z = rel.x / len, rel.y / len, rel.z / len
    x = x + (rng:getUniform() * 2 - 1) * 0.8
    y = y + (rng:getUniform() * 2 - 1) * 0.8
    z = z + (rng:getUniform() * 2 - 1) * 0.8
    local l = math.sqrt(x * x + y * y + z * z)
    if l < 1e-6 then x, y, z, l = rel.x / len, rel.y / len, rel.z / len, 1 end
    s.spot = { x / l, y / l, z / l }
    s.strikeTime = STRIKE_MIN + rng:getUniform() * (STRIKE_MAX - STRIKE_MIN)
    s.t = 0
    s.seed = rng:getUniform() * 100
end

--- Where the beam starts and where it hits, this frame.
---@param s table
---@return Position|nil from, Position|nil to
local function endpoints(s)
    local shipPos, shipRadius, shipRot = place(s.ship)
    local rockPos, rockRadius = place(s.rock)
    if not shipPos or not rockPos or not s.spot then return nil, nil end
    local from = shipPos
    if shipRot then
        local f = shipRot:getForward()
        local k = shipRadius * 0.6
        from = Position(shipPos.x + f.x * k, shipPos.y + f.y * k, shipPos.z + f.z * k)
    end
    -- The surface is rough: a little inside the collider's sphere
    local r = rockRadius * 0.85
    local to = Position(rockPos.x + s.spot[1] * r, rockPos.y + s.spot[2] * r, rockPos.z + s.spot[3] * r)
    return from, to
end

--- How bright the beam is now (0 between strikes).
---@param s table
---@return number
local function strength(s)
    if s.t < 0 then return 0 end
    local up = math.min(1, s.t / FLARE)
    local flicker = 0.80 + 0.20 * math.sin(s.t * 47 + s.seed) * math.sin(s.t * 13.7 + s.seed * 2)
    return up * flicker
end

local function render(entity, blendMode)
    if blendMode ~= BlendMode.Additive then return end
    local s = MiningBeam.state
    if not s then return end
    local a = strength(s)
    if a <= 0.01 then return end
    local from, to = endpoints(s)
    if not from then return end

    local axis = Vec3f(to.x - from.x, to.y - from.y, to.z - from.z)
    local length = axis:length()
    if not (length > 1e-6) then return end

    if not beamMesh then
        beamMesh = Gen.Primitive.Billboard(-1, 0, 1, 1)
        beamShader = Cache.Shader("billboard/axis_draw", "effect/beam_draw")
        DrawBlock = beamShader:blockType("DrawBlock")
    end

    local eye = CameraManager:getEye()
    local startRelative = Vec3f(from.x - eye.x, from.y - eye.y, from.z - eye.z)
    local direction = axis:normalize()
    local matrix = Matrix.LookUp(startRelative, -direction, Math.OrthoVector(direction))

    local pass = Renderer:currentPass()
    pass:setPipeline(Pipelines.get(beamShader, Pipelines.Additive))
    local d = pass:alloc(DrawBlock)
    ffi.copy(d.mWorld, matrix, 64)
    local user = d.drawUser
    user[0], user[1], user[2], user[3] = COLOR[1], COLOR[2], COLOR[3], a
    user[4], user[5], user[6] = WIDTH * (0.7 + 0.3 * a), length, s.seed
    pass:drawMesh(beamMesh)
end

--- Start the beam (mining began), or keep it on the same rock.
---@param ship Entity
---@param rock Entity
function MiningBeam:start(ship, rock)
    if self.state and self.state.rock == rock and self.state.ship == ship then return end
    self:stop()
    self.state = { ship = ship, rock = rock, t = 0 }
    newSpot(self.state)
    self.entity = Entity.Create("MiningBeamEntity",
        Physics.Transform(),
        Rendering.PointLight(LIGHT_COLOR, 0.25, 0),
        Rendering.Render(render))
end

--- Stop the beam (mining stopped).
function MiningBeam:stop()
    if self.entity and self.entity:isValid() then
        Registry:destroyEntity(self.entity, Enums.Registry.EntityDestroyMode.DestroyChildren)
    end
    self.entity, self.state = nil, nil
end

--- Each frame: move between strikes, and keep the light on the cut.
---@param dt number
function MiningBeam:update(dt)
    local s = self.state
    if not s then return end
    if not (s.ship and s.ship:isValid() and s.rock and s.rock:isValid()) then
        self:stop()
        return
    end
    s.t = s.t + (dt or 0)
    if s.t >= s.strikeTime then
        newSpot(s)
        s.t = -GAP -- dark for a moment: the beam lifts and strikes anew
    end

    local entity = self.entity
    if not entity or not entity:isValid() then return end
    local _, to = endpoints(s)
    local transform = entity:get(Physics.Transform)
    if transform and to then transform:setPos(to) end
    local light = entity:get(Rendering.PointLight)
    if light and light.setIntensity then light:setIntensity(2.5 * strength(s)) end
end

return MiningBeam
