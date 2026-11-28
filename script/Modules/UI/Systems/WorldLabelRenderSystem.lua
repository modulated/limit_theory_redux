local PhysicsComponents   = require("Modules.Physics.Components")
local CameraManager       = require("Modules.Cameras.Managers.CameraManager")
local UniverseScaleConfig = require("Config.Gen.UniverseScaleConfig")
local DrawEx              = require("UI.DrawEx")

--- WorldLabelRenderSystem — projects 3D entity labels onto the screen.
---@class WorldLabelRenderSystem
local WorldLabelRenderSystem = {}

--- Draw labels for a list of labeled entities
---@param labeledEntities table Array of { entity, label, isMoon, parentPos }
---@param moonDistThreshold number|nil Max camera distance to parent for moon labels (default 100000)
function WorldLabelRenderSystem:draw(labeledEntities, moonDistThreshold)
    if not labeledEntities then return end
    moonDistThreshold = moonDistThreshold or 100000

    local camEntity = CameraManager:getActiveCameraEntity()
    if not camEntity then return end
    local camTransform = camEntity:get(PhysicsComponents.Transform)
    if not camTransform then return end
    local camPos = camTransform:getPos()

    local resX = Window:width()
    local resY = Window:height()

    -- The camera is the same for every label: its axes and projection once
    -- per frame, not once per label
    local camRot = CameraManager:getViewRot()
    local camFwd = camRot:getForward()
    local camRight = camRot:getRight()
    local camUp = camRot:getUp()
    local fx, fy, fz = camFwd.x, camFwd.y, camFwd.z
    local rx, ry, rz = camRight.x, camRight.y, camRight.z
    local ux, uy, uz = camUp.x, camUp.y, camUp.z
    local tanHalfFov = math.tan(math.rad(CameraManager:getFov()) / 2)
    local aspect = resX / resY
    local cx, cy, cz = camPos.x, camPos.y, camPos.z

    for _, entry in ipairs(labeledEntities) do
        -- A ship beyond sensor range carries no label (LimitTheoryRedux:updateSensors)
        if entry.hidden then goto next_label end
        -- Hide moon labels unless camera is near the parent planet
        if entry.isMoon and entry.parentPos then
            local dx = cx - entry.parentPos.x
            local dy = cy - entry.parentPos.y
            local dz = cz - entry.parentPos.z
            local distToParent = math.sqrt(dx * dx + dy * dy + dz * dz)
            if distToParent > moonDistThreshold then goto next_label end
        end

        local entity = entry.entity
        local label = entry.label

        local transform = entity:get(PhysicsComponents.Transform)
        if not transform then goto next_label end
        local pos = transform:getPos()

        -- Relative position from the camera
        local relX, relY, relZ = pos.x - cx, pos.y - cy, pos.z - cz

        -- Skip if behind camera
        local dot = relX * fx + relY * fy + relZ * fz
        if dot < 0 then goto next_label end

        -- Project onto screen axes
        local screenX = (relX * rx + relY * ry + relZ * rz) / (dot * tanHalfFov * aspect)
        local screenY = (relX * ux + relY * uy + relZ * uz) / (dot * tanHalfFov)

        -- Convert from [-1,1] to screen pixels
        local px = (screenX + 1) * 0.5 * resX
        local py = (1 - screenY) * 0.5 * resY

        -- Only draw if on screen
        if px >= -100 and px <= resX + 100 and py >= -50 and py <= resY + 50 then
            -- The text is remade only when the label or the distance moved
            -- enough to show (half a percent): formatting it every frame for
            -- every label is most of what this costs
            local dist = math.sqrt(relX * relX + relY * relY + relZ * relZ)
            local shown = entry.shownDist
            if entry.shownLabel ~= label or not shown or math.abs(dist - shown) > shown * 0.005 then
                entry.shownLabel = label
                entry.shownDist = dist
                entry.shownText = label .. " [" .. UniverseScaleConfig:formatDistance(dist) .. "]"
            end
            -- An entry may have its own colour {r, g, b} (an NPC's faction)
            local c = entry.color
            DrawEx.TextAdditive('Unageo-Medium', entry.shownText, 12, px - 50, py - 8, 200, 16,
                c and c[1] or 1.0, c and c[2] or 1.0, c and c[3] or 0.5, 0.9, 0.5, 0.5)
        end

        ::next_label::
    end
end

--- Draw labels for nearby asteroids from belt components
---@param beltEntities table Array of entities with AsteroidBeltComponent
---@param maxDist number|nil Maximum distance to show labels (default 500000)
function WorldLabelRenderSystem:drawAsteroidMarkers(beltEntities, maxDist)
    if not beltEntities then return end
    maxDist = maxDist or 500000

    local camEntity = CameraManager:getActiveCameraEntity()
    if not camEntity then return end
    local camTransform = camEntity:get(PhysicsComponents.Transform)
    if not camTransform then return end
    local camPos = camTransform:getPos()
    local camRot = CameraManager:getViewRot()
    local camFwd = camRot:getForward()
    local camRight = camRot:getRight()
    local camUp = camRot:getUp()

    local resX = Window:width()
    local resY = Window:height()
    local fovRad = math.rad(CameraManager:getFov())
    local tanHalfFov = math.tan(fovRad / 2)
    local aspect = resX / resY

    local CelestialComponents = require("Modules.CelestialObjects.Components")

    for _, beltEntity in ipairs(beltEntities) do
        local beltCmp = beltEntity:get(CelestialComponents.AsteroidBelt)
        if not beltCmp then goto next_belt end

        local asteroids = beltCmp:getAsteroidData()
        for idx, a in ipairs(asteroids) do
            local rx = a.px - camPos.x
            local ry = a.py - camPos.y
            local rz = a.pz - camPos.z
            local dist = math.sqrt(rx*rx + ry*ry + rz*rz)

            if dist > maxDist then goto next_asteroid end

            -- Behind camera check
            local dot = rx * camFwd.x + ry * camFwd.y + rz * camFwd.z
            if dot < 0 then goto next_asteroid end

            -- Project to screen
            local sx = (rx * camRight.x + ry * camRight.y + rz * camRight.z) / (dot * tanHalfFov * aspect)
            local sy = (rx * camUp.x + ry * camUp.y + rz * camUp.z) / (dot * tanHalfFov)
            local px = (sx + 1) * 0.5 * resX
            local py = (1 - sy) * 0.5 * resY

            if px >= -100 and px <= resX + 100 and py >= -50 and py <= resY + 50 then
                local distStr = " [" .. UniverseScaleConfig:formatDistance(dist) .. "]"
                local text = "Asteroid " .. idx .. distStr
                DrawEx.TextAdditive('Unageo-Medium', text, 10, px - 40, py - 6, 200, 14,
                    0.7, 0.5, 0.3, 0.7, 0.5, 0.5)
            end

            ::next_asteroid::
        end
        ::next_belt::
    end
end

return WorldLabelRenderSystem
