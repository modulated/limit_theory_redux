local Entity        = require("Core.ECS.Entity")
local Core          = require("Modules.Core.Components")
local Physics       = require("Modules.Physics.Components")
local Rendering     = require("Modules.Rendering.Components")
local CameraManager = require("Modules.Cameras.Managers.CameraManager")
local Pipelines     = require("Render.Pipelines")

--- Space dust: the flecks of Legacy Effects/Dust.lua on the new renderer.
--- A fixed cloud of points that wraps around the camera (it never runs out)
--- drawn as faint streaks along the way the camera moves: still space shows
--- nothing, flying shows the speed. One draw in the additive pass
--- (vertex/billboard/dustfleck_draw.glsl x fragment/effect/dustfleck_draw.glsl).
---
--- Legacy's dust *clouds* are not ported: they need a texture rendered
--- first (effect/dustcloudtex) and their shaders still use loose uniforms.
---
--- `SpaceDust.create(getVelocity)` returns the entity (a scene entity: it
--- goes with the scene); `getVelocity()` gives the camera's velocity (the
--- player's ship's), {x, y, z} in game units per second, or nil.
local SpaceDust = {}

local mesh, shader, DrawBlock

--- The fleck cloud: four vertices per fleck at a random point in the cube,
--- uv.x -1..1 across and uv.y 0..1 along the streak.
local function ensureAssets()
    if mesh then return end
    local cfg = Config.game.dust
    local rng = RNG.Create(0xD057)
    local half = 0.5 * cfg.cubeSize
    mesh = Mesh.Create()
    for _ = 1, cfg.count do
        local x = rng:getUniformRange(-half, half)
        local y = rng:getUniformRange(-half, half)
        local z = rng:getUniformRange(-half, half)
        local base = mesh:getVertexCount()
        mesh:addVertex(x, y, z, 0, 0, 1, -1, 0)
        mesh:addVertex(x, y, z, 0, 0, 1, 1, 0)
        mesh:addVertex(x, y, z, 0, 0, 1, 1, 1)
        mesh:addVertex(x, y, z, 0, 0, 1, -1, 1)
        mesh:addQuad(base, base + 3, base + 2, base + 1)
    end
    shader = Cache.Shader("billboard/dustfleck_draw", "effect/dustfleck_draw")
    DrawBlock = shader:blockType("DrawBlock")
end

local function positiveMod(a, b)
    return a - b * math.floor(a / b)
end

---@param getVelocity fun(): table|nil
local function makeRender(getVelocity)
    return function(entity, blendMode)
        if blendMode ~= BlendMode.Additive then return end
        local cfg = Config.game.dust
        local v = getVelocity()
        if not v then return end
        local speed = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        if speed < cfg.minSpeed then return end

        ensureAssets()
        local eye = CameraManager:getEye()
        if not eye then return end

        local pass = Renderer:currentPass()
        pass:setPipeline(Pipelines.get(shader, Pipelines.Additive))
        local d = pass:alloc(DrawBlock)
        local m = d.mWorld
        m[0], m[5], m[10], m[15] = 1, 1, 1, 1
        local user = d.drawUser
        -- drawUser[0]: the camera's place in the dust's repeating cube, and
        -- the cube's size (the shader wraps the flecks around the camera)
        local size = cfg.cubeSize
        user[0], user[1], user[2] = positiveMod(eye.x, size), positiveMod(eye.y, size), positiveMod(eye.z, size)
        user[3] = size
        -- drawUser[1]: the motion axis, and the streak length
        user[4], user[5], user[6] = v.x / speed, v.y / speed, v.z / speed
        user[7] = math.min(cfg.maxLength, speed * cfg.lengthScale)
        -- drawUser[2]: the streak width
        user[8] = cfg.width
        pass:drawMesh(mesh)
    end
end

---@param getVelocity fun(): table|nil
---@return Entity
function SpaceDust.create(getVelocity)
    return Entity.Create(
        "SpaceDustEntity",
        Core.Seed(0),
        Physics.Transform(),
        Rendering.Render(makeRender(getVelocity)))
end

return SpaceDust
