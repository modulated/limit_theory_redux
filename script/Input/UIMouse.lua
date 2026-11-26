--- Who the mouse belongs to this frame: an in-game panel, or the world.
---
--- While the cursor is over a panel (the overview), its clicks, its wheel and
--- its right button are the panel's: the cameras do not start a drag or zoom,
--- the free camera does not toggle mouse look, and a left click is not the
--- fire button. The panel sets `overPanel` as it draws; the game clears it
--- whenever no panel is up.
---
--- It lives here rather than in GameState.ui because everything in
--- GameState.ui is written to user.ini, and this is per frame, not a setting.
---@class UIMouse
local UIMouse = {
    ---@type boolean the cursor is over an in-game panel
    overPanel = false,
}

return UIMouse
