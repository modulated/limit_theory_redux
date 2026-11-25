--- Watches the player's ship against the star system's jump gates: whether it
--- flew through a ring since the last step, and which gate is nearest.
---
--- Flying through: each step the ship's side of each ring's plane is noted.
--- When the side changes, the point where the path crossed the plane is
--- found (between the last position and this one, so a fast ship that
--- passes the plane between two steps still counts) and checked against the
--- ring's opening.
---@class JumpGateSystem
local JumpGateSystem = {}

-- The opening, as a fraction of the ring radius: inside the tube and clamps
local OPENING = 0.85

---@class JumpGateWatch
---@field gates JumpGatePlacement[]
---@field sides number[] the ship's side of each gate's plane last step
---@field lastPos Position|nil

---@param gates JumpGatePlacement[]
---@return JumpGateWatch
function JumpGateSystem:watch(gates)
    return { gates = gates or {}, sides = {}, lastPos = nil }
end

---@param gate JumpGatePlacement
---@param p Position
---@return number offset along the ring's axis
local function axial(gate, p)
    local c, a = gate.position, gate.axis
    return (p.x - c.x) * a.x + (p.y - c.y) * a.y + (p.z - c.z) * a.z
end

---@param gate JumpGatePlacement
---@param x number
---@param y number
---@param z number
---@return number distance from the ring's axis
local function radial(gate, x, y, z)
    local c, a = gate.position, gate.axis
    local dx, dy, dz = x - c.x, y - c.y, z - c.z
    local along = dx * a.x + dy * a.y + dz * a.z
    dx, dy, dz = dx - a.x * along, dy - a.y * along, dz - a.z * along
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- The gate the ship flew through since the last call, or nil.
---@param watch JumpGateWatch
---@param shipPos Position
---@return JumpGatePlacement|nil
function JumpGateSystem:update(watch, shipPos)
    local last = watch.lastPos
    local crossed = nil
    for i, gate in ipairs(watch.gates) do
        local side = axial(gate, shipPos)
        local lastSide = watch.sides[i]
        if last and lastSide and not crossed
            and ((lastSide < 0 and side >= 0) or (lastSide > 0 and side <= 0)) then
            local t = lastSide / (lastSide - side)
            local x = last.x + (shipPos.x - last.x) * t
            local y = last.y + (shipPos.y - last.y) * t
            local z = last.z + (shipPos.z - last.z) * t
            if radial(gate, x, y, z) < gate.radius * OPENING then
                crossed = gate
            end
        end
        watch.sides[i] = side
    end
    watch.lastPos = Position(shipPos.x, shipPos.y, shipPos.z)
    return crossed
end

--- Forget the last position (after the ship was moved, not flown).
---@param watch JumpGateWatch
function JumpGateSystem:reset(watch)
    watch.sides = {}
    watch.lastPos = nil
end

--- Whether a straight move from `from` to `to` came within `range` of the
--- gate's centre: a fast ship (travel drive) can pass through the range
--- between two steps without being inside it at either.
---@param gate JumpGatePlacement
---@param from Position|nil
---@param to Position
---@param range number
---@return boolean
function JumpGateSystem:passedWithin(gate, from, to, range)
    local c = gate.position
    from = from or to
    local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
    local len2 = dx * dx + dy * dy + dz * dz
    local t = 0
    if len2 > 0 then
        t = ((c.x - from.x) * dx + (c.y - from.y) * dy + (c.z - from.z) * dz) / len2
        t = math.max(0, math.min(1, t))
    end
    local px, py, pz = from.x + dx * t - c.x, from.y + dy * t - c.y, from.z + dz * t - c.z
    return px * px + py * py + pz * pz < range * range
end

--- The gate nearest to a position, and how far its centre is.
---@param watch JumpGateWatch
---@param pos Position
---@return JumpGatePlacement|nil
---@return number distance
function JumpGateSystem:nearest(watch, pos)
    local best, bestDist = nil, math.huge
    for _, gate in ipairs(watch.gates) do
        local c = gate.position
        local dx, dy, dz = pos.x - c.x, pos.y - c.y, pos.z - c.z
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if d < bestDist then best, bestDist = gate, d end
    end
    return best, bestDist
end

--- The gate that leads to a system, or nil.
---@param watch JumpGateWatch
---@param systemId integer
---@return JumpGatePlacement|nil
function JumpGateSystem:gateTo(watch, systemId)
    for _, gate in ipairs(watch.gates) do
        if gate.destination.id == systemId then return gate end
    end
    return nil
end

return JumpGateSystem
