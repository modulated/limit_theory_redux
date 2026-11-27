local UIMouse = require("Input.UIMouse")
local UserSettings = require("Shared.UserSettings")

--- Free look: hold the right mouse button in the piloting cameras (chase,
--- first person) and the mouse turns the *camera* around the ship instead of
--- steering it; let go and the view eases back behind the ship.
---
--- The player controller updates it each frame and stops steering by mouse
--- while it is held; the cameras read the offsets. A right click on a panel
--- (the overview's context menu) is the panel's, not a look.
---@class FreeLook
local FreeLook = {
    yaw = 0,    -- radians, about the ship's up (positive: to the right)
    pitch = 0,  -- radians, about the ship's right (positive: up)
    held = false,
}

local SENSITIVITY = 0.004 -- radians per pixel at the default Mouse Sensitivity
local RETURN_RATE = 6.0   -- how fast the view eases back, per second
local MAX_PITCH = 1.45

--- Each frame, from the player controller.
---@param dt number
---@param enabled boolean the camera is a piloting one, and the game is in flight
function FreeLook.update(dt, enabled)
    local mouse = Input:mouse()
    local held = enabled and mouse:isDown(MouseControl.Right)
        and (FreeLook.held or not UIMouse.overPanel)
    FreeLook.held = held
    if held then
        local d = mouse:delta()
        local k = SENSITIVITY * UserSettings.mouseSensitivityFactor()
        local invert = GameState.input.invertPitch and -1 or 1
        FreeLook.yaw = FreeLook.yaw + d.x * k
        -- Kept within a turn either way, so the return takes the short way
        if FreeLook.yaw > math.pi then FreeLook.yaw = FreeLook.yaw - 2 * math.pi end
        if FreeLook.yaw < -math.pi then FreeLook.yaw = FreeLook.yaw + 2 * math.pi end
        FreeLook.pitch = Math.Clamp(FreeLook.pitch - d.y * k * invert, -MAX_PITCH, MAX_PITCH)
    else
        local keep = math.exp(-RETURN_RATE * (dt or 0))
        FreeLook.yaw = FreeLook.yaw * keep
        FreeLook.pitch = FreeLook.pitch * keep
        if math.abs(FreeLook.yaw) < 1e-4 then FreeLook.yaw = 0 end
        if math.abs(FreeLook.pitch) < 1e-4 then FreeLook.pitch = 0 end
    end
end

--- Turn a direction given in the ship's frame (x right, y up, z forward) by
--- the look: yaw about up, then pitch about right.
---@param x number
---@param y number
---@param z number
---@return number, number, number
function FreeLook.apply(x, y, z)
    local cy, sy = math.cos(FreeLook.yaw), math.sin(FreeLook.yaw)
    local x1 = x * cy + z * sy
    local z1 = -x * sy + z * cy
    local cp, sp = math.cos(FreeLook.pitch), math.sin(FreeLook.pitch)
    local y2 = y * cp + z1 * sp
    local z2 = -y * sp + z1 * cp
    return x1, y2, z2
end

--- Whether the view is turned at all.
---@return boolean
function FreeLook.active()
    return FreeLook.yaw ~= 0 or FreeLook.pitch ~= 0
end

--- Straight ahead again at once (a camera switch, a new ship).
function FreeLook.reset()
    FreeLook.yaw, FreeLook.pitch, FreeLook.held = 0, 0, false
end

return FreeLook
