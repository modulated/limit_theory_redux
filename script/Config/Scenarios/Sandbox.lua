-- The sandbox: the game as a career from nothing. A basic ship with one gun
-- and a mining laser, a few credits, and a quiet star system to start in;
-- the rest of the galaxy is as dangerous as it is. Everything after that --
-- mining, trading, a better ship, factories, outposts and the ships that
-- guard them -- is up to the player.
local Rulesets = require("Config.Gen.Rulesets")

return {
    name = "Sandbox",
    description = "Start from nothing: a basic ship, one gun, a mining laser and a few credits, in a peaceful system.",
    ruleset = Rulesets.SinglePlanetWithBelt,
    -- What the game starts with, instead of Config.game.fitting/economy's
    -- defaults (LimitTheoryRedux:resetGalaxy, assignHostility)
    start = {
        credits = 500,
        hull = "Solo Hull",
        weapons = { "Pulse Turret" },
        modules = { "Mining Laser" },
        -- Config.game.hostility.levels[0]: Peaceful
        homeLevel = 0,
    },
}
