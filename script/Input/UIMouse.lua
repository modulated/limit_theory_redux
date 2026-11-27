--- Who the mouse belongs to this frame: an in-game panel, or the world.
---
--- While the cursor is over a panel (the overview, the action bar, a
--- window), its clicks, its wheel and its right button are the panel's: the
--- cameras do not start a drag or zoom, the free camera does not toggle mouse
--- look, and a left click is not the fire button.
---
--- Several panels draw each frame, so none of them sets `overPanel` itself:
--- the in-game view calls `beginFrame` before its panels, each panel the
--- cursor is over calls `claim`, and `endFrame` after the last one publishes
--- the answer. The game reads `overPanel` (the answer from the last frame
--- drawn).
---
--- It lives here rather than in GameState.ui because everything in
--- GameState.ui is written to user.ini, and this is per frame, not a setting.
---@class UIMouse
local UIMouse = {
    ---@type boolean the cursor is over an in-game panel
    overPanel = false,
    ---@type boolean a panel has claimed the mouse in the frame being drawn
    pending = false,
}

--- Before the in-game panels draw.
function UIMouse.beginFrame()
    UIMouse.pending = false
end

--- A panel that has the cursor (or holds the mouse, mid-drag).
function UIMouse.claim()
    UIMouse.pending = true
end

--- After the last panel: what the game reads until the next frame is drawn.
function UIMouse.endFrame()
    UIMouse.overPanel = UIMouse.pending
end

return UIMouse
