# Items, Ore, Trade and Production

The item list of the game, as it exists in the code today, in one place: what an item is, every
item that is defined, which of them can be mined, which can be traded, and the production chains
that turn one into another. It is meant to be edited: the tables are the design surface, and the
Status sections say how much of each is actually wired up.

Status summary (2026-11): it all runs. 68 items with permanent ids; every belt and ring has a
composition and mining reads it; a rock knows what it holds; stations hold stock, price it by how
short they are, run the production chains against it, and trade with the player on a docked screen;
every station has an order book where prices are whatever
someone will pay, and the player can take the best order or place one of their own; the player has
a hold, a mining laser, credits, a hangar at every station and lines they can rent there; NPC
workers are the hands the factory floors run on. Legacy's economy is deleted. Since 0.2.0 the
equipment is no longer decoration: weapons go in a hull's mounts, modules in its slots, some of
them fire on a key, and a hull itself is a thing you buy and switch into at a station (section 8).
What is missing is listed in the last section — chiefly NPC traders that actually haul, and
saving.

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
| Player credits (bounties, repairs) | `script/Modules/Economy/Managers/PlayerWallet.lua`, `Config.game.economy` |
| **The production recipes** | `script/Shared/Definitions/ProductionDefs.lua`, `Shared/Registries/Productions.lua`, `Shared/Types/ProductionDefinition.lua` |
| **The market**: order books, matching, escrow, fees | `script/Modules/Economy/Systems/MarketSystem.lua`, `Components/OrderBookComponent.lua` |
| What a station reckons things are worth, its stock and imports | `script/Modules/Economy/Systems/StationTradeSystem.lua` |
| What is known of other systems' markets | `script/Modules/Economy/Managers/MarketIntel.lua` |
| Stations making things | `script/Modules/Economy/Systems/ProductionSystem.lua`, `Components/ProductionComponent.lua` |
| A store of goods (stations, the hold) | `script/Modules/Economy/Components/StockComponent.lua` |
| The player's hold | `script/Modules/Economy/Managers/PlayerCargo.lua` |
| The docked station screen | `script/UI/HmGui/Views/Gameplay/Station.lua` |
| The player's hangar and rented lines | `script/Modules/Economy/Managers/PlayerFactories.lua` |
| A station's crew | `script/Modules/Economy/Components/WorkforceComponent.lua`, `Modules/NPC/Jobs/Work.lua` |
| **The hulls and the fittings** | `script/Shared/Definitions/HullDefs.lua`, `FittingDefs.lua` (section 8) |
| Mining and trade tuning | `Config.game.mining`, `Config.game.trade`, `Config.game.production`, `Config.game.factory`, `Config.game.cargo`, `Config.game.fitting` |

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
| Infolytic Chip | 3 | 1.35 | 4 | 430 |

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
| Copper | 5 | 1 | 5 | 70 |
| Aluminum | 3 | 1.8 | 5 | 55 |
| Silver | 5 | 1.5 | 8 | 150 |
| Gold | 6 | 2 | 12 | 200 |
| Platinum | 8 | 3 | 24 | 250 |
| Steel | 7 | 1 | 7 | 150 |
| Transparent Aluminum | 5 | 1.7 | 8 | 165 |
| Glassiron | 11 | 1 | 11 | 250 |
| Plastic | 3 | 1.9 | 6 | 70 |
| Thorium | 9 | 27 | 243 | 300 |
| Silicon | 2 | 1.7 | 3 | 55 |
| Carbon | 2 | 1.3 | 3 | 60 |
| Beryllium | 2 | 1.3 | 3 | 65 |
| Lithium | 1 | 1.2 | 1 | 70 |
| Boron | 2 | 1.2 | 2 | 50 |
| Hydrocarbons | 6 | 3.5 | 21 | 55 |

### Gases

| Item | Mass | E/mass | Energy | Price |
|------|------|--------|--------|-------|
| Hydrogen | 1 | 2 | 2 | 25 |
| Helium | 1 | 1.01 | 1 | 10 |
| Nitrogen | 1 | 1.05 | 1 | 12 |
| Oxygen | 1 | 1.5 | 2 | 30 |

### Consumables

| Item | Mass | E/mass | Energy | Price |
|------|------|--------|--------|-------|
| Biomass | 4 | 4 | 16 | 60 |
| Water Ice | 5 | 1 | 5 | 20 |
| Liquid Water | 4 | 1 | 4 | 25 |

### Equipment (ship modules)

| Item | Mass | E/mass | Energy | Price |
|------|------|--------|--------|-------|
| Ship Computer | 110 | 22 | 2420 | 2600 |
| Ship Sensor | 80 | 19 | 1520 | 2500 |
| Ship Engine, Thruster | 600 | 20 | 12000 | 7200 |
| Ship Engine, Impeller | 1500 | 18 | 27000 | 4000 |
| Ship Weapon, Pulse Turret | 100 | 10 | 1000 | 2800 |
| Ship Weapon, Beam Turret | 120 | 10 | 1200 | 3600 |
| Ship Weapon, Launcher Turret | 90 | 8 | 720 | 3200 |
| Ship Weapon, Pulse Bay | 1000 | 9 | 9000 | 3000 |
| Ship Weapon, Beam Bay | 1200 | 9 | 10800 | 14000 |
| Ship Weapon, Cannon Bay | 2500 | 10 | 25000 | 9000 |
| Ship Weapon, Launcher Bay | 800 | 7 | 5600 | 2500 |
| Shield Capacitor | 120 | 13 | 1560 | 1500 |
| Armour Plating | 400 | 3 | 1200 | 900 |
| Cargo Pod | 250 | 4 | 1000 | 1100 |
| Manoeuvring Thrusters | 150 | 12 | 1800 | 1400 |
| Shield Booster | 90 | 20 | 1800 | 1800 |
| Afterburner | 180 | 16 | 2880 | 2200 |
| Hull Repair Pulse | 200 | 15 | 3000 | 2600 |
| Mining Laser | 160 | 14 | 2240 | 1700 |
| Survey Scanner | 70 | 18 | 1260 | 2000 |
| Market Datalink | 60 | 21 | 1260 | 3400 |

Every one of these is a *fitting* as well as a good: see section 8. The weapon prices follow the
mount size classes — a medium turret costs a few thousand, an L or XL bay weapon a multiple of
that — so a hull with heavy mounts is worth flying to.

### Constructs (hulls and stations)

| Item | Mass | E/mass | Energy | Price |
|------|------|--------|--------|-------|
| Ship Hull, Solo | 15000 | 50 | 750000 | 24000 |
| Ship Hull, Small | 32000 | 49 | 1568000 | 30000 |
| Ship Hull, Compact | 75000 | 47 | 3525000 | 70000 |
| Ship Hull, Medium | 102500 | 46 | 4715000 | 100000 |
| Ship Hull, Large | 237250 | 45 | 10676250 | 200000 |
| Ship Hull, Very Large | 518000 | 42 | 21756000 | 500000 |
| Space Station, Small | 1550000 | 40 | 62000000 | 1000000 |
| Refinery Outpost Kit | 2000 | 30 | 60000 | 450000 |
| Manufacturing Outpost Kit | 2000 | 30 | 60000 | 650000 |

The first four hulls are flyable (`Shared/Definitions/HullDefs.lua`): buy one, and a station's
shipyard will put you in it. Large and Very Large are still goods only. The two kits (Drydock
recipes 48 and 49) and the Small Space Station deploy the player's own outposts (section 6).

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
| Radioactive Isotopes | 13 | 50 | 650 | 600 |

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

## 4. Trade: the market

Every station has an **order book**, and what a thing is worth there is what someone will pay for
it. Nothing has a price of its own any more.

- **A station posts orders** (`MarketSystem:refreshStation`, every `market.refreshInterval`): a bid
  for everything it deals in until it holds all it wants, and an offer of whatever it has beyond
  the reserve it keeps back (`reserveShare`). Both sit `stationMargin` either side of its own
  *valuation* — `StationTradeSystem:basePrice`, the item's base value scaled by how far its shelves
  are from its target. So a station drowning in ore bids next to nothing for more and offers it
  cheap; one that has run out of energy cells bids over the odds. The valuation is the station's
  opinion, not the price: the price is the book's.
- **The player trades two ways.** At the market: take the best orders standing, for whatever they
  are asking. Or with a **limit order**: name a price and wait. Credits are escrowed for a buy
  order and the goods taken for a sell order, both returned if it is cancelled or lapses
  (`orderLifetime`). Placing one costs a broker's fee (`brokerFee`), and a sale pays tax
  (`salesTax`), which are the two reasons not to place orders carelessly. Undercut the best ask by
  a credit and you are first in line.
- **A trade happens at the resting order's price**, oldest first at the same price, so undercutting
  works and a big market order walks up the book instead of clearing it at the first price.
- **Orders are backed by goods that are there.** The market trades out of the player's **hangar**
  at that station, not the ship's hold; the Hangar tab moves goods between the two.
- **Nothing is stranded.** Whatever nobody bids for, the station takes as scrap at `scrapFactor`
  of its valuation. A scrap sale is not a market price and is kept out of the book's history.

**Reading other markets.** Only the system you are in is simulated, so other books cannot be read
live — what can be read is what was last seen of them. Every station's book is written down when
you are there (`Modules/Economy/Managers/MarketIntel.lua`), and the station screen's **Nearby** tab
shows those notes for systems within `market.remoteJumps` jumps (3), with their age and the best
spreads they imply: buy here at this price, sell there at that one. The range is a config number so
a ship module can raise it later (`MarketIntel:setRange`).

**What moves the stock behind the orders:**

| Source | What it does |
|--------|--------------|
| The station's own production | makes its outputs, eats its inputs (section 5) |
| NPC miners | `Jobs/Mining.lua` unloads a full hold into the station it docks at, which becomes an offer |
| The player | every fill on the book, and scrap sales |
| Imports | a trickle (`importPerSecond`) of what the station cannot make itself, capped at `importFloor` of its target, standing in for the freighters nobody sees |

**The player's side:** `PlayerCargo` is the ship's hold, kept beside the wallet rather than on the
ship (which is destroyed and rebuilt on undocking, on a jump and on a respawn); its capacity is a
mass, so ore fills it and data cubes do not. Mining (E held) takes a unit at a time out of the
nearest rock in reach, from the same yield the NPC miners work. Credits are `PlayerWallet`.

The order-book `MarketplaceSystem` that came with the ECS port is **gone**, along with its order
entities, price and marketplace components and its test state: there is one market model now.

## 5. Production (crafting)

The recipes are `script/Shared/Definitions/ProductionDefs.lua`, in the `Productions` registry, and
`Modules/Economy/Systems/ProductionSystem.lua` runs them: a line takes its inputs out of the
station's stock when it starts, counts down its duration (compressed by
`Config.game.production.timeScale`) and puts the outputs in when it finishes. Nothing is made out
of nothing, so a refinery with no ore waits for a miner. Each station gets a powerplant (mostly a
solar array, which needs no fuel) plus a refinery or a factory or two from its seed, and one
station in a system may also build hulls.

**A line needs hands.** Every station has a `Workforce`: its own standing crew
(`production.stationCrew`) plus the workers docked there right now. A line claims
`production.workersPerLine` of them or stands idle showing "no crew" on the docked screen.
Workers are an NPC role with a job of their own (`Modules/NPC/Jobs/Work.lua`): fly in, dock, work a
shift, undock, go somewhere else. A Secure system spawns four of them and a Lawless one none, so
lawless space has idle factories — and shooting a system's worker shuttles down slows its industry.
The station's own lines claim the crew first; the player's rented lines (below) take what is left.

**Legacy's quantities were rebalanced.** As ported, almost every recipe destroyed value: the Iron
Refinery ate 5 energy cells and 7 iron ore (310 credits at equilibrium) to make one iron (50), and
the reactors made energy out of almost nothing. `luajit tools/economy-sim.lua --recipes` showed it
and `--rebalance` fixed it: input counts are scaled so a run is worth about 1.4 times what it eats,
with a handful of built goods repriced where a single unit of an ingredient already cost more than
the product (Steel 70 → 150, Glassiron 90 → 250, Infolytic Chip 100 → 430, Ship Sensor 400 → 2,500,
and so on). Every recipe now pays for its inputs and the station's cut.

Classes: **Powerplant** (Legacy's P0), **Refinery** (P1), **Factory** (P2), **Drydock** (P3),
**Misc** (P4). "Energy" in the inputs is the **Energy Cell** item.

| Class | Recipe | Inputs | Outputs | Seconds |
|-------|--------|--------|---------|---------|
| Powerplant | Solar Energy Array | -- | Energy Cell x10 | 8 |
| Powerplant | Nuclear Reactor | Radioactive Isotopes x6 | Energy Cell x240, Radioactive Waste x8 | 20 |
| Powerplant | Fusion Reactor | Liquid Water x572 | Energy Cell x1000, Radioactive Waste x1 | 40 |
| Powerplant | Waste Recycler | Waste x14 | Energy Cell x5 | 4 |
| Refinery | Water Melter | Energy Cell x3, Water Ice x15 | Liquid Water x20 | 6 |
| Refinery | Silicon Refinery | Energy Cell x1, Silicate Ore x2 | Silicon x1, Waste x6 | 12 |
| Refinery | Carbon Refinery | Energy Cell x1, Carboniferous Ore x1 | Carbon x1, Waste x3 | 13 |
| Refinery | Beryllium Refinery | Energy Cell x1, Beryllium Ore x1 | Beryllium x1, Waste x7 | 22 |
| Refinery | Aluminum Refinery | Energy Cell x1, Aluminum Ore x1 | Aluminum x1, Waste x5 | 15 |
| Refinery | Iron Refinery | Energy Cell x1, Iron Ore x1 | Iron x1, Waste x4 | 14 |
| Refinery | Copper Refinery | Energy Cell x2, Copper Ore x3 | Copper x2, Anode Sludge x1, Waste x7 | 16 |
| Refinery | Thorium Refinery | Energy Cell x2, Thorium Ore x2 | Thorium x1, Radioactive Waste x2, Waste x5 | 20 |
| Refinery | Hydrocarbon Refinery | Energy Cell x1, Biomass x1 | Hydrocarbons x1, Waste x15 | 14 |
| Factory | Water Electrolyser | Energy Cell x1, Liquid Water x1 | Hydrogen x2, Oxygen x1 | 5 |
| Factory | Steel Foundry | Energy Cell x1, Iron x1, Carbon x1 | Steel x1, Waste x4 | 13 |
| Factory | Silver Recovery Plant | Energy Cell x4, Anode Sludge x3 | Silver x1, Waste x6 | 18 |
| Factory | Gold Recovery Plant | Energy Cell x5, Anode Sludge x4 | Gold x1, Waste x7 | 21 |
| Factory | Platinum Recovery Plant | Energy Cell x7, Anode Sludge x5 | Platinum x1, Waste x9 | 25 |
| Factory | Isotope Factory | Energy Cell x1, Thorium x2 | Radioactive Isotopes x1, Radioactive Waste x7, Waste x3 | 11 |
| Factory | Plastics Factory | Energy Cell x1, Hydrocarbons x1 | Plastic x1, Waste x8 | 9 |
| Factory | Infolytic Chip Factory | Energy Cell x1, Plastic x1, Gold x1, Silicon x1 | Infolytic Chip x1, Waste x2 | 11 |
| Factory | Transparent Aluminum Factory | Energy Cell x1, Silicon x1, Aluminum x1 | Transparent Aluminum x1, Waste x3 | 13 |
| Factory | Glassiron Factory | Energy Cell x2, Silicon x1, Iron x1, Beryllium x1 | Glassiron x1, Waste x3 | 17 |
| Factory | Ship Sensor Factory | Energy Cell x2, Glassiron x3, Transparent Aluminum x2, Steel x2, Infolytic Chip x2 | Ship Sensor x1, Waste x55 | 450 |
| Factory | Ship Computer Factory | Energy Cell x2, Glassiron x2, Transparent Aluminum x2, Steel x2, Silicon x2, Infolytic Chip x2 | Ship Computer x1, Waste x70 | 360 |
| Factory | Thruster Engine Factory | Energy Cell x2, Glassiron x12, Transparent Aluminum x2, Steel x2, Infolytic Chip x2, Thorium x2 | Ship Engine, Thruster x1, Waste x55 | 900 |
| Factory | Pulse Turret Weapon Factory | Energy Cell x2, Glassiron x3, Transparent Aluminum x2, Steel x2, Infolytic Chip x2 | Ship Weapon, Pulse Turret x1, Waste x40 | 790 |
| Drydock | Solo Ship Hull Drydock | Energy Cell x4, Glassiron x21, Transparent Aluminum x3, Steel x5, Gold x1, Platinum x1, Infolytic Chip x1, Thorium x1, Ship Sensor x1, Ship Computer x1, Ship Engine, Thruster x1 | Ship Hull, Solo x1, Waste x725 | 1800 |
| Drydock | Space Station Fabricator | Energy Cell x716, Glassiron x2046, Transparent Aluminum x369, Steel x809, Gold x116, Platinum x19, Infolytic Chip x18, Ship Sensor x1, Ship Computer x1, Thorium x1 | Space Station, Small x1, Waste x9750 | 14400 |

Only one weapon (Pulse Turret), one engine (Thruster) and one hull (Solo) have a recipe; the rest of
the Equipment and Constructs items are sold but not buildable. Legacy's "Piracy" recipe (energy in,
credits out) was not ported: pirates earn by raiding.

### Feedstock items

The chain needs five items between the ores and the built goods that the registry did not have at
first: **Silicon**, **Carbon**, **Carboniferous Ore** (carbonaceous chondrite), **Beryllium** and
**Hydrocarbons**; **Lithium** and **Boron** came along with them as Legacy fillers. All seven are in
the tables above now (ids 52–58), with Legacy's masses and energy densities. Legacy's "Petroleum"
is this registry's **Hydrocarbons**: it is biomass cracked into fuel and plastics feedstock, and the
name says so.

Legacy tiered its items T0–T8 (energy, information, raw inanimate, raw animate, processed
elemental, processed constructed, ship component, ship hull, station), which the registry's groups
mostly mirror. Those Legacy files are gone now; the recipes above are the port.

## 6. The player's own industry

Docked, the **Factory** tab shows the station's own lines and what it will rent out, and the
**Hangar** tab what the player keeps there. `Modules/Economy/Managers/PlayerFactories.lua` holds
both, beside the wallet and the hold, because stations are destroyed and rebuilt when a system is
generated again; everything is keyed by `system id:station index`, which is stable.

- **A hangar at every station** used, `factory.hangarCapacity` of mass (20,000 t against the ship's
  2,400). The Hangar tab moves goods either way between it and the ship, and sells from it; the
  Market tab has a `trade with: ship hold | hangar` switch, so inputs can be bought straight into
  the hangar.
- **Renting a line.** A station rents out `factory.rentableLines` of them, for
  `factory.rentChoices` recipes of the trades its own floor knows — *not* the ones it is running
  itself, because a renter fighting the station for the same ore buys dear and sells cheap. A
  recipe that needs no inputs (a solar array) is never rented out.
- **The cut.** Holding a lease is free; the station takes `factory.rentShare` of what each finished
  run is worth (at least `factory.rentMinFee`). If the credits are not there when a run finishes,
  the station keeps the goods and the lease lapses.
- **Inputs and outputs** are the hangar's: a line eats from it and fills it back up, so it stalls
  with "needs Iron Ore x4" or "hangar full" rather than quietly spending money.
- **Crew is shared** with the station, its own lines first, so a rented line can read "no crew".
- **While you are away** a lease keeps working: the time is credited when you come back to the
  system, up to `factory.offlineCatchUpMax` (an hour) of it.

What it pays: `--crafter` in the sim rents the best line at a station, buys its inputs there and
sells the output back, which is the worst case — about 130 credits an hour. The gain is in sourcing
the inputs yourself (ore you mined, goods bought where they are cheap), where a refined good is
worth roughly twice the ore it came from.

### Outposts: stations of your own

`Modules/Economy/Managers/PlayerStations.lua`, configured by `Config.game.outposts`. An outpost is
deployed from a kit, picked from the overview's right-click menu on a planet or an asteroid belt
("Deploy ..."): the autopilot flies to the nearest free slot and the kit is spent there. The kit
comes out of the hold, or out of a hangar at a station in the same system (the Small Space
Station, at 1,550,000 t, only ever travels that way).

- **Where.** `orbitSlots` slots on the ring the generated stations sit on around each planet
  (offset half a step from their angles), and `beltSlots` along each belt. A slot within
  `minSpacing` of a station, an outpost or a gate is taken.
- **What kind.** A **Refinery Outpost** runs any Refinery or Powerplant recipe, a **Manufacturing
  Outpost** any Factory or Drydock recipe, four lines each, with no fee and no crew to share; a
  **Trading Post** (the Small Space Station) has no lines.
- **Storage** is the hangar, as at any station, filed under the outpost's key `p:<id>`.
- **The market** is the owner's orders and nothing else: the outpost posts none of its own and
  buys no scrap. The owner pays no broker fee and no sales tax there. NPCs whose faction is not
  hostile to the player dock and trade: a miner sells its hold into the owner's bids, at their
  price, down to `minerMinPrice` of the ore's base price (it picks the outpost only if the bids
  cover its whole hold, and takes anything left to the next station); a trader buys the
  cheapest listings up to `traderMaxMarkup` of base, spending up to `traderBudget` a visit. The
  sales tax an NPC pays on a sale there is the owner's; the Factory tab shows what it has earned.

Outposts are saved with the game, and built again from their records whenever the player comes
back to the system.

## 7. Tuning it without running the game

`tools/economy-sim.lua` runs this economy headless: it loads the real
`Config.game`, the real item and production registries and the real
`StationTradeSystem` and `ProductionSystem`, then steps a model of a system —
stations making and trading, miners bringing ore in, optionally a trader
hauling between stations and a prospector mining and selling. A simulated day
takes about a second, so the numbers in `Config.game.{trade,production,mining,cargo}`
can be tuned by running it rather than by flying around. The actors trade on
the real order books: the trader works the spreads between stations, the
prospector sells its ore into the best bid it can find, and the crafter rents
a line, buys its inputs off the book and sells the output back.

```sh
luajit tools/economy-sim.lua                                   # a two-day run
luajit tools/economy-sim.lua --seeds 8 --prospector --trader    # the spread over eight systems
luajit tools/economy-sim.lua --set trade.spread=0.2 --hours 12  # try a setting
luajit tools/economy-sim.lua --csv /tmp/economy.csv             # the hourly series
luajit tools/economy-sim.lua --help
```

What it reports: runs per production line (and which lines **starved**, never
completing a run), each station's stock with the best bid and ask on its book,
each watched item's traded price range, where every unit came from
(produced, imported, mined, hauled), and the income of the trader and the
prospector in credits an hour. `--seeds N` runs several systems and prints the
spread, which matters: income swings by more than ten times depending on
whether a system's refineries happen to want what its belts hold.

Four things it already caught, all fixed:

- a solar array completed a run every 0.4 s and buried a station in 43,000
  energy cells, so a line now stops when its outputs are piled past
  `production.stockCeiling` times the target (waste is vented instead, or a
  full bin would stop the floor);
- imports were supplying 21,000 units of ore against the miners' nothing, so
  `trade.importPerSecond` came down from 0.5 to 0.02 — a trickle, not a
  supplier;
- stations were handed ship-part factories whose inputs no one in the system
  makes, so recipes above `production.maxLineInputValue` are not assigned, and
  refineries now prefer an ore the local belts hold
  (`production.localRefineryChance`);
- a prospector could dump the same ore on one station for ever at 20,000
  credits an hour, so a station stops buying a thing at `trade.buyCeiling`
  times its target, and mining slowed to the NPC rate (3 s a unit).

The model's shortcuts: a miner is a delivery every so often (its hold, its
mining rate and its time docked are the real config values, plus `--trip`
seconds of flying), the trader buys while the margin lasts and sells at the
next station, and the prospector mines a full hold and sells it where it pays
best. Nothing about prices, stock, production or imports is modelled: that is
the game's own code.

## 8. Fitting: what a ship carries

A ship is a **hull** with **fittings** in it. Both are items, so both are bought, built or looted
like anything else, and the whole of the above economy is what supplies them.

| What | File |
|------|------|
| The hulls that can be flown | `script/Shared/Definitions/HullDefs.lua` -> `Shared/Registries/Hulls.lua` |
| The parts that go in them | `script/Shared/Definitions/FittingDefs.lua` -> `Shared/Registries/Fittings.lua` |
| Working a fit out and applying it | `script/Modules/Constructs/Systems/ShipFittingSystem.lua` |
| Modules that fire on a key | `script/Modules/Constructs/Systems/AbilitySystem.lua` |
| The ships the player owns, and their fits | `Modules/Constructs/Managers/PlayerFleet.lua` |
| The screen you refit on | `script/UI/HmGui/Views/Gameplay/Station.lua` (the Refit tab) |

**A hull** decides three things: its weapon mounts (how many, and what size class each takes), how
many module slots it has, and the hull and shield it starts from.

| Hull | Mounts | Slots | Hull | Shield | Price |
|------|--------|-------|------|--------|-------|
| Solo Hull | 2xM 2xSM | 3 | 420 | 80 | 24000 |
| Small Hull | 4xM 2xSM | 4 | 700 | 160 | 30000 |
| Compact Hull | 2xL 4xM 2xSM | 5 | 1200 | 300 | 70000 |
| Medium Hull | 4xL 4xM 2xSM | 6 | 2200 | 600 | 100000 |

**A fitting** is either a weapon, which goes in a mount of its own size class or larger, or a
module, which goes in a slot. A module either changes a stat or does something on command:

- *Passive*: Shield Capacitor, Armour Plating, Cargo Pod, Manoeuvring Thrusters, Ship Sensor, Ship
  Computer, Thruster Engine, Impeller, Market Datalink. They add to a stat and then scale it, in
  that order, so two of a thing stack sensibly.
- *Active*: Shield Booster, Afterburner, Hull Repair Pulse, Survey Scanner — bound to the number
  keys 1-4, each with its own cooldown, shown as a HUD row. A module that cannot do anything (a
  full shield, an undamaged hull) refuses and costs no cooldown.
- *Held*: the Mining Laser. Without one fitted the mining key says so and nothing happens, which is
  the one place a fitting gates a verb outright.

Two of them change what the player can *know* rather than what the ship can do:

- The **Market Datalink** adds 2 to `marketReach`, the jumps out whose order books can still be
  read. The base is `Config.game.market.remoteJumps` (3), so one datalink sees 5 jumps and two see
  7; the Intel tab's heading follows it. This is the module-upgradeable market reach the order book
  was built for.
- The **Survey Scanner** is prospecting. A rock is "an unsurveyed rock" until the scanner reads it
  — the HUD will not name the ore, though you can still mine it blind — and the scanner reads at
  2.5x the laser's reach, so it finds rocks before you are in cutting range. A unit in the hold
  identifies the rock too: cut it and you have seen what comes out. What is read stays read for
  that rock.

**Refitting** happens docked, out of that station's hangar, for free: the Refit tab lists the mounts
and slots, and what in the hangar will go in them. A part fitted comes out of the hangar; a part
removed goes back into it.

**A fit belongs to its ship, not to the player.** The player owns a *fleet*
(`Modules/Constructs/Managers/PlayerFleet.lua`): each ship has an id, a hull, a name, its own guns
and modules, and the station it is parked at. Taking a different ship out gives you that ship's fit,
not the one you were flying with — so a Compact rigged for mining and a Compact rigged to fight are
two ships, and switching between them costs nothing but the walk across the hangar.

- **Commissioning**: a hull is a good until you fit it out. "Fit out and fly" spends the hull item
  from the hangar and makes a ship with *nothing* in it; the ship you were flying stays at that
  station, fitted as it is.
- **Flying another**: the refit screen lists your ships parked here, each with its hull and its fit.
  One button takes it; the one you arrived in stays behind.
- **Stripping**: one button per ship empties its mounts and slots into this station's hangar — the
  ship you are in, or any of yours parked here. A part the hangar has no room for stays on the ship
  rather than vanishing from both.
- **Breaking up**: an empty ship can be broken up, which puts the bare hull back as an item to
  sell. A ship with anything still in it refuses, and so does the one you are flying, so nothing is
  ever sold out from under its own modules.

Only the mounts with a gun in them shoot: a turret has to name a weapon it can resolve, so an empty
mount is left out of the ship's weapon battery and neither tracks nor fires. A ship with nothing
fitted flies unarmed.

## 9. Gaps and implementation order

Done: the item registry with permanent ids, the feedstock items, ore from each field's own
composition, rocks that know what they hold, station stock and prices, production with a crew of
NPC workers, rebalanced recipes, the player's hold, player mining, the docked station screen, a
hangar and rentable factory lines at every station, the deletion of Legacy's economy, and
(0.2.0) fittings, modules with abilities and buyable hulls — every part has a recipe, so the
whole catalogue can be bought or built.

- [ ] **Biomass has no source.** The Hydrocarbon Refinery (and so plastics, and so chips) runs on
      imports alone. It wants a farm or a station recipe, or a mineable source.
- [ ] **NPC traders should haul goods**, not wait 6–12 s at a stop: buy where a thing is cheap,
      sell where it is dear, which is what would make prices differ between stations for a reason.
      `Jobs/Transport.lua` and `StationTradeSystem` already have the pieces.
- [ ] **Workers are only hands.** A worker shuttle's cargo is irrelevant, it is never paid, and a
      station does not hire. Pay, wages and a labour market would make the crew a real cost.
- [ ] **Prospecting stops at the rock.** A rock's ore is hidden until a Survey Scanner reads it,
      but a belt's *composition* is still public on the system map, so a prospector can tell which
      belt is worth sweeping without owning a scanner. Whether that is a feature or a hole is a
      design call; a surveyed-rock marker in the world would also help more than a HUD line.
- [ ] **Saving.** The hold, the wallet, every station's stock and every production line's progress
      are the state a saved game needs (see item ids, section 1).
- [ ] **Balance.** `Config.game.trade` and `Config.game.production` were set by eye: the target
      value, the spread, the import rate and `timeScale` decide whether trading is worth the flying.
