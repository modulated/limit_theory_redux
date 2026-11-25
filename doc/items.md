# Items, Ore, Trade and Production

The item list of the game, as it exists in the code today, in one place: what an item is, every
item that is defined, which of them can be mined, which can be traded, and the production chains
that turn one into another. It is meant to be edited: the tables are the design surface, and the
Status sections say how much of each is actually wired up.

Status summary (2026-11): the item **registry** is live (58 items, hand-written permanent ids), the
galaxy generator gives every belt and ring a composition from it, and mining reads that composition. The **market**, **inventory** and **production** code exists but nothing
trades or crafts in a running game: the only credits that move are bounties and hull repair, and a
miner that fills its hold sells it to a log line.

## 1. Where it lives

| What | File |
|------|------|
| Item type (`mass`, `energy`, `startEquilibriumPrice`) | `script/Shared/Types/ItemDefinition.lua` |
| Item group type | `script/Shared/Types/ItemGroup.lua` |
| Item registry (`Items.RawMaterials.IronOre`, `Items:getDefinition(id)`) | `script/Shared/Registries/Items.lua` |
| **The item list** | `script/Shared/Definitions/ItemDefs.lua` |
| Asteroid/ring composition (which ore a rock holds) | `script/Config/Gen/Rulesets/*.lua` (`composition`) |
| Asteroid entity carrying an item + quantity | `script/Modules/CelestialObjects/Entities/AsteroidEntity.lua` |
| Mineable rocks, yields and regrowth | `script/Modules/NPC/Managers/MiningField.lua`, `Config.game.mining` |
| Miner job (mine, dock, sell) | `script/Modules/NPC/Jobs/Mining.lua`, `Actions/MineAt.lua` |
| Inventory (ECS) | `script/Modules/Economy/Components/{InventoryComponent,ItemComponent}.lua`, `Managers/InventoryManager.lua` |
| Market (price discovery, orders) | `script/Modules/Economy/Systems/MarketplaceSystem.lua`, `Entities/OrderEntity.lua` |
| Player credits (bounties, repairs) | `script/Modules/Economy/Managers/PlayerWallet.lua`, `Config.game.economy` |
| Legacy item list and production chains | `script/Legacy/GameObjects/Elements/Economy/Content.lua` |
| Legacy production/factory/market/yield | `script/Legacy/Systems/Economy/`, `script/Legacy/GameObjects/Elements/Economy/` |

### Item definition

```lua
ItemDefinition { name = "Iron Ore", mass = 6, energyDensity = 1.68, startEquilibriumPrice = 30 }
```

- `energy` is stored as `round(mass * energyDensity)`; `energyDensity` itself is not kept.
- **`id` is written by hand and is permanent.** It is the only part of an item that may end up in
  saved data, so it is never changed and never reused: a new item takes the next free number (the
  last line of `ItemDefs.lua` says which), and a removed item leaves its number unused. The registry
  asserts that every item has an id and that no two share one, so a mistake fails at load instead of
  quietly turning someone's cargo into something else. Ids 1–51 are the numbers the old
  registration-order scheme had given out, so nothing shifted when they were written down.
- **Two names.** `name` is the lookup key with the spaces taken out (`Items.RawMaterials.IronOre`,
  `def.name == "IronOre"`); `displayName` is the name as written (`"Iron Ore"`) and is what the UI
  and the logs show. Rewording an item is therefore free — only the id matters.
- `Items:getByName(name)` finds an item by either spelling (`"Iron Ore"` or `"IronOre"`), which is
  how config and save data should name one.
- `startEquilibriumPrice` is the market's starting equilibrium price. Items without one
  (only `Credit`) are not priced.

## 2. The item list

Energy is the derived `mass × energyDensity`. Price is `startEquilibriumPrice`.

### Virtual

| Item | Mass | E/mass | Energy | Price |
|------|------|--------|--------|-------|
| Credit | 0 | 0 | 0 | — |

### Data

| Item | Mass | E/mass | Energy | Price |
|------|------|--------|--------|-------|
| Data Cube | 1 | 2.1 | 2 | 50 |
| Info Wafer | 1 | 3.82 | 4 | 75 |
| Infolytic Chip | 3 | 1.35 | 4 | 100 |

### Raw Materials (mined)

| Item | Mass | E/mass | Energy | Price |
|------|------|--------|--------|-------|
| Silicate Ore | 4 | 1.3 | 5 | 20 |
| Iron Ore | 6 | 1.68 | 10 | 30 |
| Copper Ore | 7 | 1.74 | 12 | 35 |
| Aluminum Ore | 4 | 1.6 | 6 | 25 |
| Beryllium Ore | 4 | 1.45 | 6 | 40 |
| Thorium Ore | 7 | 7.5 | 52 | 100 |
| Carboniferous Ore | 6 | 1.4 | 8 | 28 |

### Refined Materials

| Item | Mass | E/mass | Energy | Price |
|------|------|--------|--------|-------|
| Iron | 5 | 1 | 5 | 50 |
| Copper | 5 | 1 | 5 | 60 |
| Aluminum | 3 | 1.8 | 5 | 55 |
| Silver | 5 | 1.5 | 8 | 150 |
| Gold | 6 | 2 | 12 | 200 |
| Platinum | 8 | 3 | 24 | 250 |
| Steel | 7 | 1 | 7 | 70 |
| Transparent Aluminum | 5 | 1.7 | 8 | 80 |
| Glassiron | 11 | 1 | 11 | 90 |
| Plastic | 3 | 1.9 | 6 | 45 |
| Thorium | 9 | 27 | 243 | 300 |
| Silicon | 2 | 1.7 | 3 | 40 |
| Carbon | 2 | 1.3 | 3 | 35 |
| Beryllium | 2 | 1.3 | 3 | 65 |
| Lithium | 1 | 1.2 | 1 | 70 |
| Boron | 2 | 1.2 | 2 | 50 |
| Hydrocarbons | 6 | 3.5 | 21 | 55 |

### Gases

| Item | Mass | E/mass | Energy | Price |
|------|------|--------|--------|-------|
| Hydrogen | 1 | 2 | 2 | 15 |
| Helium | 1 | 1.01 | 1 | 10 |
| Nitrogen | 1 | 1.05 | 1 | 12 |
| Oxygen | 1 | 1.5 | 2 | 18 |

### Consumables

| Item | Mass | E/mass | Energy | Price |
|------|------|--------|--------|-------|
| Biomass | 4 | 4 | 16 | 60 |
| Water Ice | 5 | 1 | 5 | 20 |
| Liquid Water | 4 | 1 | 4 | 25 |

### Equipment (ship modules)

| Item | Mass | E/mass | Energy | Price |
|------|------|--------|--------|-------|
| Ship Computer | 110 | 22 | 2420 | 500 |
| Ship Sensor | 80 | 19 | 1520 | 400 |
| Ship Engine, Thruster | 600 | 20 | 12000 | 2000 |
| Ship Engine, Impeller | 1500 | 18 | 27000 | 4000 |
| Ship Weapon, Pulse Turret | 100 | 10 | 1000 | 600 |
| Ship Weapon, Beam Turret | 120 | 10 | 1200 | 650 |
| Ship Weapon, Launcher Turret | 90 | 8 | 720 | 550 |
| Ship Weapon, Pulse Bay | 1000 | 9 | 9000 | 3000 |
| Ship Weapon, Beam Bay | 1200 | 9 | 10800 | 3500 |
| Ship Weapon, Cannon Bay | 2500 | 10 | 25000 | 5000 |
| Ship Weapon, Launcher Bay | 800 | 7 | 5600 | 2500 |

These are economy *goods*, with no link yet to the weapons the ships actually fit
(`script/Shared/Definitions/WeaponDefs.lua`, `Shared/Registries/WeaponRegistry.lua`) or to the
procedural modules in `Shared/Content/ProceduralCatalog.lua`. Fitting an "Equipment" item to a hull
is not implemented.

### Constructs (hulls and stations)

| Item | Mass | E/mass | Energy | Price |
|------|------|--------|--------|-------|
| Ship Hull, Solo | 15000 | 50 | 750000 | 15000 |
| Ship Hull, Small | 32000 | 49 | 1568000 | 30000 |
| Ship Hull, Compact | 75000 | 47 | 3525000 | 70000 |
| Ship Hull, Medium | 102500 | 46 | 4715000 | 100000 |
| Ship Hull, Large | 237250 | 45 | 10676250 | 200000 |
| Ship Hull, Very Large | 518000 | 42 | 21756000 | 500000 |
| Space Station, Small | 1550000 | 40 | 62000000 | 1000000 |

### Waste

| Item | Mass | E/mass | Energy | Price |
|------|------|--------|--------|-------|
| Waste | 1 | 1 | 1 | 5 |
| Radioactive Waste | 10 | 2.5 | 25 | 30 |
| Anode Sludge | 9 | 1 | 9 | 15 |

### Miscellaneous

| Item | Mass | E/mass | Energy | Price |
|------|------|--------|--------|-------|
| Energy Cell | 1 | 1 | 1 | 20 |
| Radioactive Isotopes | 13 | 50 | 650 | 500 |

## 3. Mined ore

Two halves, and they now agree: the generator says what a field is made of, and mining reads it.

**a) What a field is made of (generator, live).** Each belt and ring is given a `composition` by its
ruleset: a list of item ids with weights, per field type (rocky or icy), stored on the entity as a
`Composition` component. The field's type comes from its own `type` rule and is in the generation
context as `beltType`/`ringType`, which is what the composition's `ByType` rule looks up
(`parentKey`). `StandardSolarSystem` rings:

| Field type | Composition (weights sum to 1) |
|------------|--------------------------------|
| Rocky ring | Silicate Ore 0.45, Iron Ore 0.28, Carboniferous Ore 0.12, Aluminum Ore 0.1, Beryllium Ore 0.05 |
| Icy ring | Water Ice 0.55, Silicate Ore 0.2, Hydrogen 0.1, Carboniferous Ore 0.05, Helium 0.05, Nitrogen 0.03, Oxygen 0.02 |

Its belts: rocky Silicate 0.5 / Iron 0.4 / Carboniferous 0.1; icy Water Ice 0.65 / Hydrogen 0.15 /
Helium 0.1 / Carboniferous 0.05 / Silicate 0.05. `SinglePlanetWithBelt` and `PlanetShowcase` use
Silicate 0.45 / Iron 0.35 / Carboniferous 0.1 / Aluminum 0.1.

**b) What a rock holds (gameplay, live).** `Shared/Helpers/AsteroidOre.lua` is the one place that
decides it, so every part of the game agrees:

- the ore follows from the field's composition and the asteroid's **own seed**, so asking twice
  gives the same answer and nothing has to be stored;
- `MiningField:build` uses it for the rocks the NPC miners work (`rock.item`, `rock.itemId`), and
  registers itself as the live yield source, so a rock being stripped reports what is **left**;
- `AsteroidFieldSystem` gives every rock it spawns near the player `Item` and `Quantity`
  components from it, refreshed as the miners work, so **the rock itself can be asked what it
  holds** — `AsteroidOre.ofEntity(entity)` returns the item and the units, and
  `AsteroidOre.describeEntity(entity)` says it in words ("Iron Ore x1240", "Iron Ore, spent").
  This is the hook a prospecting scanner reads;
- a planet's ring is materialized as a child belt entity, so the composition lookup walks up to
  the parent that holds it.

Nothing shows the ore in the HUD yet: the rocks carry it, and reading it is the scanner's job.

`Config.game.mining.ores` is the fallback for a field the generator gave no composition (it is
logged at debug level when that happens):

| Ore | Weight | Share |
|-----|--------|-------|
| Silicate Ore | 5 | 28.1% |
| Iron Ore | 4 | 22.5% |
| Aluminum Ore | 3 | 16.9% |
| Carboniferous Ore | 2.5 | 14.0% |
| Copper Ore | 2 | 11.2% |
| Beryllium Ore | 1 | 5.6% |
| Thorium Ore | 0.3 | 1.7% |

Other `Config.game.mining` knobs: `rocksPerBelt = 24`, `unitsPerScale = 0.004` (a rock's size sets
its unit count), `regrowPerSecond = 0.02`, `timePerUnit = 3.0` s to mine one unit, `sellTime = 8.0`
s docked to sell the hold.

A miner's hold carries the ore's id and display name (`npc.cargo.itemId`, `npc.cargo.item`), but
selling still only logs a line (`Jobs/Mining.lua`, `SellCargo`) because stations hold no stock. The
player cannot mine at all.

## 4. Trade

What exists:

- `MarketplaceSystem` (a `PreRender` subscriber) runs price discovery per marketplace entity:
  random-walk volatility, a pull toward a shifting equilibrium, pull timeouts, a price history and
  a pending-trade buffer. Every `SpaceStationEntity` gets a `Marketplace` component.
- `OrderEntity` (buy/sell orders), `ItemEntity`, `ItemComponent`, `QuantityComponent`,
  `InventoryComponent` and `InventoryManager` for holding items.
- `Config.game.economy`: `startingCredits = 1000`, `hullRepairCost = 2.0` credits per hull point
  (shields recharge free), bounties (`pirate` 600, `pirateMerchant` 300, default 250) paid by
  `security` for the killing blow on an outlaw. This is the only live flow of credits.
- Legacy has a full market (`Elements/Economy/Market.lua`), a black market with escrow TODOs
  (`BlackMarket.lua`), traders and a universe economy; none of it is loaded by the current states.

What is missing for trade to be playable: a station inventory stocked with items, a UI to buy and
sell while docked, a player cargo hold, and NPC traders that move actual items instead of waiting
6–12 s at a stop.

## 5. Production (crafting)

The recipes are Legacy (`Content.lua`) and are not loaded by the game today. They are the design
intent, so they are listed here in full. Classes: **P0** powerplant, **P1** refinery, **P2**
factory, **P3** drydock, **P4** misc. "Energy" in the inputs is the **Energy Cell** item.

| Class | Recipe | Inputs | Outputs | Seconds |
|-------|--------|--------|---------|---------|
| P0 | Solar Energy Array | — | Energy Cell ×10 | 8 |
| P0 | Nuclear Reactor | Isotopes ×1 | Energy Cell ×240, Radioactive Waste ×8 | 20 |
| P0 | Fusion Reactor | Liquid Water ×320 | Energy Cell ×1000, Radioactive Waste ×1 | 40 |
| P0 | Waste Recycler | Waste ×20 | Energy Cell ×5 | 4 |
| P1 | Water Melter | Energy ×2, Water Ice ×10 | Liquid Water ×20 | 6 |
| P1 | Silicon Refinery | Energy ×3, Silicate Ore ×12 | Silicon ×1, Waste ×6 | 12 |
| P1 | Carbon Refinery | Energy ×3, Carboniferous Ore ×4 | Carbon ×1, Waste ×3 | 13 |
| P1 | Beryllium Refinery | Energy ×8, Beryllium Ore ×13 | Beryllium ×1, Waste ×7 | 22 |
| P1 | Aluminum Refinery | Energy ×6, Aluminum Ore ×8 | Aluminum ×1, Waste ×5 | 15 |
| P1 | Iron Refinery | Energy ×5, Iron Ore ×7 | Iron ×1, Waste ×4 | 14 |
| P1 | Copper Refinery | Energy ×7, Copper Ore ×11 | Copper ×2, Anode Sludge ×1, Waste ×7 | 16 |
| P1 | Thorium Refinery | Energy ×13, Thorium Ore ×12 | Thorium ×1, Radioactive Waste ×2, Waste ×5 | 20 |
| P1 | Hydrocarbon Refinery | Energy ×6, Biomass ×22 | Hydrocarbons ×1, Waste ×15 | 14 |
| P2 | Water Electrolyser | Energy ×3, Liquid Water ×1 | Hydrogen ×2, Oxygen ×1 | 5 |
| P2 | Steel Foundry | Energy ×8, Iron ×8, Carbon ×2 | Steel ×1, Waste ×4 | 13 |
| P2 | Silver Recovery Plant | Energy ×12, Anode Sludge ×8 | Silver ×1, Waste ×6 | 18 |
| P2 | Gold Recovery Plant | Energy ×14, Anode Sludge ×11 | Gold ×1, Waste ×7 | 21 |
| P2 | Platinum Recovery Plant | Energy ×20, Anode Sludge ×16 | Platinum ×1, Waste ×9 | 25 |
| P2 | Isotope Factory | Energy ×5, Thorium ×12 | Radioactive Isotopes ×1, Radioactive Waste ×7, Waste ×3 | 11 |
| P2 | Plastics Factory | Energy ×11, Hydrocarbons ×7 | Plastic ×1, Waste ×8 | 9 |
| P2 | Infolytic Chip Factory | Energy ×10, Plastic ×8, Gold ×1, Silicon ×1 | Infolytic Chip ×1, Waste ×2 | 11 |
| P2 | Transparent Aluminum Factory | Energy ×5, Silicon ×5, Aluminum ×3 | Transparent Aluminum ×1, Waste ×3 | 13 |
| P2 | Glassiron Factory | Energy ×18, Silicon ×5, Iron ×3, Beryllium ×3 | Glassiron ×1, Waste ×3 | 17 |
| P2 | Ship Sensor Factory | Energy ×210, Glassiron ×500, Transp. Alum ×30, Steel ×75, Infolytic ×35 | Ship Sensor ×1, Waste ×55 | 450 |
| P2 | Ship Computer Factory | Energy ×240, Glassiron ×420, Transp. Alum ×28, Steel ×65, Silicon ×25, Infolytic ×150 | Ship Computer ×1, Waste ×70 | 360 |
| P2 | Thruster Engine Factory | Energy ×120, Glassiron ×1000, Transp. Alum ×20, Steel ×170, Infolytic ×12, Thorium ×2 | Ship Engine, Thruster ×1, Waste ×55 | 900 |
| P2 | Pulse Turret Weapon Factory | Energy ×180, Glassiron ×800, Transp. Alum ×32, Steel ×210, Infolytic ×12 | Ship Weapon, Pulse Turret ×1, Waste ×40 | 790 |
| P3 | Solo Ship Hull Drydock | Energy ×1500, Glassiron ×10000, Transp. Alum ×900, Steel ×1850, Gold ×285, Platinum ×95, Infolytic ×165, Thorium ×35, Ship Sensor ×1, Ship Computer ×1, Thruster ×1 | Ship Hull, Solo ×1, Waste ×725 | 1800 |
| P3 | Space Station Fabricator | Energy ×350000, Glassiron ×1000000, Transp. Alum ×180000, Steel ×395000, Gold ×57000, Platinum ×9100, Infolytic ×8500, Ship Sensor ×100, Ship Computer ×100, Thorium ×640 | Space Station, Small ×1, Waste ×9750 | 14400 |
| P4 | Piracy | Energy ×1 | Credit ×10 | 1 |

Only one weapon (Pulse Turret), one engine (Thruster) and one hull (Solo) have a recipe; the rest of
the Equipment and Constructs items are sold but not buildable.

### Feedstock items

The chain needs five items between the ores and the built goods that the registry did not have at
first: **Silicon**, **Carbon**, **Carboniferous Ore** (carbonaceous chondrite), **Beryllium** and
**Hydrocarbons**; **Lithium** and **Boron** came along with them as Legacy fillers. All seven are in
the tables above now (ids 52–58), with Legacy's masses and energy densities. Legacy's "Petroleum"
is this registry's **Hydrocarbons**: it is biomass cracked into fuel and plastics feedstock, and the
name says so.

Legacy also tiers its items T0–T8 (energy, information, raw inanimate, raw animate, processed
elemental, processed constructed, ship component, ship hull, station), which the new registry's
groups mostly mirror.

## 6. Gaps and implementation order

- [x] **Add the missing items** so the production chains close (ids 52–58).
- [x] **Give Carboniferous Ore a source**: weighted into `Config.game.mining.ores` (14%) and into
      every ruleset's rocky and icy `composition` lists.
- [x] **One source of truth for ore.** `MiningField` takes each rock's ore from its field's
      generated composition and keeps the item id on the rock; `Config.game.mining.ores` is only
      the fallback.
- [x] **Asteroid entities agree.** Spawned rocks carry `Item`/`Quantity` from the same
      `AsteroidOre` answer the mining field uses, kept up to date as they are mined.
- [ ] **Prospecting scanner**: a ship module that sweeps for rocks and reads
      `AsteroidOre.ofEntity`, with a range and a sweep time, so the ore is something you find
      rather than something you are told. Needs a HUD readout and a target-info panel.
- [ ] **Player cargo hold**: an `InventoryComponent` on the player's ship, a HUD readout, and a
      capacity by hull size.
- [ ] **Player mining**: a mining laser mount that calls into `MiningField:take`, reusing the NPC
      `MineAt` timing.
- [ ] **Docked trade UI**: a station marketplace screen (buy/sell at the `MarketplaceSystem` price),
      paid through `PlayerWallet`.
- [ ] **Station stock**: give stations an inventory seeded from their system's ore, and make NPC
      traders and miners move real items through it (`SellCargo` should sell into the station's
      market instead of logging).
- [ ] **Port production**: a `Modules/Economy` production/factory system from Legacy's
      `Production`/`Factory`, with recipes moved out of `script/Legacy/.../Content.lua` into
      `script/Shared/Definitions/ProductionDefs.lua` + a registry, like the other definition files.
- [ ] **Fit Equipment items to ships**: link the Equipment group to `WeaponRegistry` and the
      procedural module catalog so a bought turret can be mounted.
- [x] **Stable item ids**: written by hand in `ItemDefs.lua`, never reused, asserted unique by the
      registry.
