--- Engine plumes: the jets out of a ship's stern while it accelerates.
---
--- Every ship gets nozzles at its stern, more for bigger hulls (by its
--- Targetable size class): one for a small ship, up to four for a capital,
--- side by side across the hull. Each nozzle draws, additively:
---   * a glow at the nozzle (the projectile's pulse head shader), and
---   * the jet (effect/thrusterplume_draw): a white-hot core going over to
---     the engine's colour, narrowing to its tip, flickering, with shock
---     diamonds near the nozzle at full throttle.
---
--- The throttle is how hard the ship is pushing forward: for the player,
--- the thrust key (and boost) as it is pressed; for everyone (the
--- autopilot, NPCs), how fast their speed along their heading is growing.
--- It eases up and down rather than snapping. A ship at rest or coasting
--- shows a faint idle glow; under the travel drive the jet is long and
--- bright. A hidden ship (docked, lost) shows none.
---
--- One render entity draws every ship's plumes (`ensureRenderEntity`), like
--- WeaponCombatSystem's projectiles; `clear` removes it with the scene.
local ffi = require("ffi")
local Pipelines = require("Render.Pipelines")
local Primitive = require("Legacy.Systems.Gen.Primitive")
local Entity = require("Core.ECS.Entity")
local PhysicsComponents = require("Modules.Physics.Components")
local RenderingComponents = require("Modules.Rendering.Components")
local ConstructComponents = require("Modules.Constructs.Components")
local CameraManager = require("Modules.Cameras.Managers.CameraManager")

local EnginePlumeSystem = {
    ships = {},       -- the ships drawn this frame: { entity, team }
    state = {},       -- entity id (string) -> { throttle, lastPos, lastSpeed }
    plumes = {},      -- this frame's nozzles to draw
    renderEntity = nil,
    time = 0,
}

-- The look, in the ship's radius (its bounding sphere)
local CFG = {
    stern = 0.92,         -- the nozzles this far back from the centre
    spread = 0.20,        -- side by side, this far apart
    headSize = 0.16,      -- the nozzle glow, at full throttle
    width = 0.10,         -- the jet's half-width at the nozzle
    idleLength = 0.25,    -- the jet at idle
    fullLength = 2.4,     -- at full throttle (boost goes past it)
    travelLength = 7.0,   -- under the travel drive
    idleAlpha = 0.12,
    refAccel = 0.08,      -- game units/s^2 along the heading that reads as full throttle
    ease = 7.0,           -- how fast the throttle follows (per second)
}

local NOZZLES = { small = 1, medium = 2, large = 3, capital = 4 }

-- The engine's colour, by team
local COLORS = {
    player   = { 0.45, 0.75, 1.00 },
    pirate   = { 1.00, 0.48, 0.20 },
    security = { 0.40, 0.60, 1.00 },
    trader   = { 0.75, 0.90, 1.00 },
    miner    = { 0.95, 0.80, 0.45 },
}
local DEFAULT_COLOR = { 0.55, 0.78, 1.00 }

local meshHead, meshTail, shaderHead, shaderPlume, DrawBlock
local function ensureResources()
    if meshHead then return end
    meshHead = Primitive.Billboard(-1, -1, 1, 1)
    meshTail = Primitive.Billboard(-1, -1, 1, 0)
    shaderHead = Cache.Shader("billboard/quad_draw", "effect/pulsehead_draw")
    shaderPlume = Cache.Shader("billboard/axis_draw", "effect/thrusterplume_draw")
    DrawBlock = shaderHead:blockType("DrawBlock")
end

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

--- Set the ships to draw plumes for, and how hard each pushes. Once a
--- simulation step.
---@param dt number
---@param ships table[] { entity, team }
function EnginePlumeSystem:update(dt, ships)
    self.time = (self.time + dt) % 1000
    local seen = {}
    local plumes = self.plumes
    local count = 0
    local ease = 1.0 - math.exp(-CFG.ease * math.max(dt, 0))

    for _, s in ipairs(ships) do
        local entity = s.entity
        if entity and entity:isValid() then
            local render = entity:get(RenderingComponents.Render)
            local rbCmp = entity:get(PhysicsComponents.RigidBody)
            local rb = rbCmp and rbCmp:getRigidBody()
            if rb and not (render and render.isVisible and not render:isVisible()) then
                local key = tostring(entity.id)
                seen[key] = true
                local st = self.state[key]
                local pos = rb:getPos()
                local rot = rb:getRot()
                local fwd = rot:getForward()
                if not st then
                    st = { throttle = 0, lastPos = Position(pos.x, pos.y, pos.z), lastSpeed = 0 }
                    self.state[key] = st
                end

                -- How fast it moves along its heading, from where it went
                -- (kinematic NPCs report no velocity of their own)
                local speed = 0
                if dt > 0 then
                    local dx, dy, dz = pos.x - st.lastPos.x, pos.y - st.lastPos.y, pos.z - st.lastPos.z
                    speed = (dx * fwd.x + dy * fwd.y + dz * fwd.z) / dt
                end
                local accel = dt > 0 and (speed - st.lastSpeed) / dt or 0
                st.lastPos = Position(pos.x, pos.y, pos.z)
                st.lastSpeed = speed
                local target = clamp(accel / CFG.refAccel, 0, 1)

                -- The player's own thrust key, as pressed
                local ctrl = entity:get(ConstructComponents.ShipFlightControl)
                if ctrl and ctrl.thrustInput then
                    local pushed = math.max(0, ctrl.thrustInput) * (1 + (ctrl.boostInput or 0) * 0.6)
                    target = math.max(target, pushed)
                    ctrl.thrustInput, ctrl.boostInput = nil, nil
                end
                local drive = entity:get(ConstructComponents.TravelDrive)
                local travel = drive and drive:isActive()
                if travel then target = 1.0 end
                st.throttle = st.throttle + (target - st.throttle) * ease

                -- The nozzles at the stern
                local radius = math.max(rb:getBoundingRadius(), 1e-4)
                local targetable = entity:get(ConstructComponents.Targetable)
                local n = NOZZLES[targetable and targetable:getSizeClass() or "small"] or 1
                local right = rot:getRight()
                local color = COLORS[s.team or ""] or DEFAULT_COLOR
                local th = st.throttle
                local length = travel and CFG.travelLength
                    or (CFG.idleLength + (CFG.fullLength - CFG.idleLength) * th)
                local alpha = travel and 1.0 or (CFG.idleAlpha + (1 - CFG.idleAlpha) * math.min(1, th))
                for i = 1, n do
                    local side = (i - (n + 1) / 2) * CFG.spread * radius
                    count = count + 1
                    local p = plumes[count]
                    if not p then
                        p = {}
                        plumes[count] = p
                    end
                    p.x = pos.x - fwd.x * CFG.stern * radius + right.x * side
                    p.y = pos.y - fwd.y * CFG.stern * radius + right.y * side
                    p.z = pos.z - fwd.z * CFG.stern * radius + right.z * side
                    p.fx, p.fy, p.fz = fwd.x, fwd.y, fwd.z
                    p.r, p.g, p.b = color[1], color[2], color[3]
                    p.alpha = alpha
                    p.throttle = travel and 1.5 or th
                    p.head = CFG.headSize * radius * (0.45 + 0.55 * math.min(1, th))
                    p.width = CFG.width * radius * (travel and 1.3 or (0.6 + 0.4 * math.min(1, th)))
                    p.length = length * radius
                    p.seed = (i * 7.31 + (tonumber(entity.id) or 0) % 97) % 31
                end
            end
        end
    end
    for index = #plumes, count + 1, -1 do plumes[index] = nil end
    -- Ships that went
    for key in pairs(self.state) do
        if not seen[key] then self.state[key] = nil end
    end
    if count > 0 then self:ensureRenderEntity() end
end

--- Draw one sprite per plume
local function draw(pass, shader, mesh, plumes, eye, fill)
    pass:setPipeline(Pipelines.get(shader, Pipelines.Additive))
    for i = 1, #plumes do
        local p = plumes[i]
        local pos = Position(p.x, p.y, p.z)
        local dir = Vec3f(p.fx, p.fy, p.fz)
        local m = Matrix.LookUp(pos:relativeTo(eye), Vec3f(-p.fx, -p.fy, -p.fz), Math.OrthoVector(dir))
        local d = pass:alloc(DrawBlock)
        ffi.copy(d.mWorld, m.m, 64)
        local user = d.drawUser
        user[0], user[1], user[2], user[3] = p.r, p.g, p.b, p.alpha
        fill(user, p)
        pass:drawMesh(mesh)
    end
end

function EnginePlumeSystem:ensureRenderEntity()
    if self.renderEntity and self.renderEntity:isValid() then return end
    self.renderEntity = Entity.Create(
        "EnginePlumes",
        RenderingComponents.Render(function(_, blendMode)
            if blendMode ~= BlendMode.Additive or #self.plumes == 0 then return end
            local eye = CameraManager:getEye()
            if not eye then return end
            ensureResources()
            local pass = Renderer:currentPass()
            local time = self.time
            Profiler.Begin("EnginePlumes")
            -- The jets first, the nozzle glows over them
            draw(pass, shaderPlume, meshTail, self.plumes, eye, function(user, p)
                user[4], user[5] = p.width, p.length
                user[8], user[9], user[10] = p.throttle, p.seed, time
            end)
            draw(pass, shaderHead, meshHead, self.plumes, eye, function(user, p)
                user[4] = p.head
            end)
            Profiler.End()
        end))
end

--- Forget every ship and remove the render entity (with the scene).
function EnginePlumeSystem:clear()
    self.state = {}
    for i = #self.plumes, 1, -1 do self.plumes[i] = nil end
    if self.renderEntity and self.renderEntity:isValid() then
        local Registry = require("Core.ECS.Registry")
        Registry:destroyEntity(self.renderEntity, Registry.DESTROY_MODE.DESTROY_CHILDREN)
    end
    self.renderEntity = nil
end

return EnginePlumeSystem
