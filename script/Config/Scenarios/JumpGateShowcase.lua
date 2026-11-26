-- Jump Gate Showcase: the placeholder jump-gate model up close, next to the
-- player's ship. The camera starts orbiting it. The gate leads nowhere: it is
-- not part of a galaxy (the star-system scenarios build those).

local JumpGateGenerator = require("Modules.Navigation.Managers.JumpGateGenerator")
local NavigationComponents = require("Modules.Navigation.Components")
local Helpers = require("Config.Scenarios.Helpers")

local function spawnGate(game)
    local radius = Config.game.jumpGates.radius
    local gateCmp = NavigationComponents.JumpGate(0, 0, 0, "Nowhere")
    local position = Helpers.outward(game, radius * 4)
    local gate = JumpGateGenerator:createGate(game.rng:get64(), gateCmp, position, nil, radius)
    game:addSceneEntity(gate, { label = "Jump Gate", addBody = true })
    game.scenarioData.gate = gate
    game:setOrbitFocus(gate, game:orbitDistances(radius))
end

return {
    name = "Jump Gate Showcase",
    description = "The placeholder jump gate up close.",
    stations = false,

    setup = spawnGate,

    regenerate = function(game)
        game:removeSceneEntity(game.scenarioData.gate)
        spawnGate(game)
    end,

    overlayLines = function(game)
        return {
            "Jump Gate Showcase",
            "C: camera / fly    Right mouse: orbit    Wheel: zoom",
        }
    end,
}
