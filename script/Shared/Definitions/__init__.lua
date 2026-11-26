-- The game's data tables, loaded in dependency order.
--
-- A definitions file fills a registry by calling into it (`Items:add`,
-- `Productions:add`, ...), so requiring the registry alone gives you an empty
-- one: something has to require the definitions. That used to happen by
-- accident -- a ruleset pulled in `ItemDefs`, the weapon config pulled in
-- `WeaponDefs` -- which left the production and fitting registries empty
-- until a tool happened to require them. `Main.lua` requires this list once,
-- after the enums and the config, so every registry is full before anything
-- asks it a question.
--
-- Order matters: fittings and hulls name items, and productions name items.
require("Shared.Definitions.ItemDefs")
require("Shared.Definitions.ProductionDefs")
require("Shared.Definitions.FittingDefs")
require("Shared.Definitions.HullDefs")

return {
    Items = require("Shared.Registries.Items"),
    Productions = require("Shared.Registries.Productions"),
    Fittings = require("Shared.Registries.Fittings"),
    Hulls = require("Shared.Registries.Hulls"),
}
