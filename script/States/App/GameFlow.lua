--- Where the game is in its life, as one state with checked moves between
--- states, instead of a handful of flags that could each be set on its own.
---
---   Menu ----------> Starting -----> InSystem      (a new game from the menu)
---   Menu ----------> InSystem                      (a game started directly:
---                                                    autostart, the tests)
---   Menu, InSystem, Docked --> Loading --> InSystem (a save; it may then
---                                                    dock, or jump to the
---                                                    system it was saved in)
---   InSystem <-----> Docked
---   InSystem ------> Jumping ------> InSystem      (a gate, the jump drive)
---   InSystem ------> Rebuilding ---> InSystem      (Regenerate)
---   any but Menu --> Menu                          (back to the main menu)
---
--- What each state carries stays where it was (`game.jump` is the jump in
--- hand, `game.pendingLoad` the save being loaded, ...); this only says which
--- of them may be in hand. A move not in the table is refused and logged, so
--- a request at the wrong moment (a new game during a jump, a save during a
--- rebuild, a jump while docked) does nothing rather than half of something.
---
--- `check` compares the state with those flags once a frame and logs any
--- disagreement (once each), which is where a path that sets a flag without
--- saying so shows up.
---@class GameFlow
---@field phase string
local GameFlow = {}
GameFlow.__index = GameFlow

---@enum GamePhase
GameFlow.Phase = {
    Menu = "Menu",
    Starting = "Starting",
    Loading = "Loading",
    Rebuilding = "Rebuilding",
    InSystem = "InSystem",
    Docked = "Docked",
    Jumping = "Jumping",
}
local P = GameFlow.Phase

local MOVES = {
    [P.Menu] = { [P.Starting] = true, [P.Loading] = true, [P.InSystem] = true },
    [P.Starting] = { [P.InSystem] = true, [P.Menu] = true },
    [P.Loading] = { [P.InSystem] = true, [P.Menu] = true },
    [P.InSystem] = { [P.Docked] = true, [P.Jumping] = true, [P.Rebuilding] = true,
                     [P.Loading] = true, [P.Menu] = true },
    [P.Docked] = { [P.InSystem] = true, [P.Loading] = true, [P.Menu] = true },
    [P.Jumping] = { [P.InSystem] = true, [P.Menu] = true },
    [P.Rebuilding] = { [P.InSystem] = true, [P.Menu] = true },
}
GameFlow.MOVES = MOVES

---@return GameFlow
function GameFlow.new()
    return setmetatable({ phase = P.Menu, reported = {} }, GameFlow)
end

--- Whether the flow is in one of the given states.
---@param ... string
---@return boolean
function GameFlow:is(...)
    for i = 1, select("#", ...) do
        if self.phase == select(i, ...) then return true end
    end
    return false
end

--- Whether a move to `to` is allowed from here.
---@param to string
---@return boolean
function GameFlow:can(to)
    return to == self.phase or (MOVES[self.phase] and MOVES[self.phase][to]) == true
end

--- Move to `to`, if allowed (staying put is always allowed). Returns whether
--- the flow is in `to` now.
---@param to string
---@param why string|nil for the log
---@return boolean
function GameFlow:to(to, why)
    if to == self.phase then return true end
    if not self:can(to) then
        Log.Warn("GameFlow: refused %s -> %s%s", self.phase, to, why and (" (" .. why .. ")") or "")
        return false
    end
    Log.Debug("GameFlow: %s -> %s%s", self.phase, to, why and (" (" .. why .. ")") or "")
    self.phase = to
    return true
end

--- The state the game's own flags describe.
---@param game table LimitTheoryRedux
---@return string
function GameFlow.fromFlags(game)
    if game.pendingStart then return P.Starting end
    if game.pendingLoad then return P.Loading end
    if game.rebuildInFrames then return P.Rebuilding end
    if game.jump then return P.Jumping end
    if not game.playerShip then return P.Menu end
    if game.docked then return P.Docked end
    return P.InSystem
end

--- Once a frame: does the state agree with the flags? A disagreement is
--- logged once (a path that changes the flow without saying so).
---@param game table
function GameFlow:check(game)
    local flags = GameFlow.fromFlags(game)
    if flags ~= self.phase then
        local key = self.phase .. "/" .. flags
        if not self.reported[key] then
            self.reported[key] = true
            Log.Warn("GameFlow: in %s, but the flags say %s", self.phase, flags)
        end
    end
end

return GameFlow
