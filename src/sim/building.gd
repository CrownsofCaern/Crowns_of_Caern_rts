class_name Building
extends RefCounted
## A placed building: dwelling (trains one unit line), storehouse, or the hall; or a piece of a
## wall (kind wall | gate | tower, see Fortifications).

var id: int = 0
var owner: int = 0
var key: String = ""  ## art and name key, e.g. c_dw1
var kind: String = "dwelling"  ## hall | dwelling | storehouse | special | wall | gate | tower
var special: String = ""  ## kind special: the faction building's id (economy.json faction_buildings)
var tier: int = 0  ## dwellings: the lowest tier they train (their slot, economy.json dwelling_slots)
var tiers: Array = []  ## dwellings: every tier they train (tiers 1 and 2 share one, 3 and 4 another)
var units: Dictionary = {}  ## dwellings: tier -> the unit it trains (the upgraded one once bought)
var unit_type: String = ""  ## dwellings: the unit of its lowest tier (units[tier])
var pos: Vector2 = Vector2.ZERO
var radius: float = 40.0
var progress: float = 1.0  ## 0..1 while under construction
var build_seconds: float = 20.0
var queue: Array = []  ## unit types waiting (already paid)
var train_left: float = 0.0  ## seconds left on the unit in training (0 = none)
var train_total: float = 0.0  ## seconds the unit in training takes in all (for progress bars)
var recruit: int = -1  ## unused since drafting starts training at once (kept for saves)
var has_recruit: bool = false  ## a worker was drafted; training of queue[0] runs
var rally: Vector2 = Vector2.ZERO
## Dwellings: the tiers whose permanent upgrade was bought (tier -> true), any of them, and the
## upgrade under way (seconds left, 0 = none, and its tier).
var upgraded_tiers: Dictionary = {}
var upgraded: bool = false
var refit_left: float = 0.0
var refit_tier: int = 0
var cells: Array = []  ## nav cells this building blocks
## Faction buildings (see FactionBuildings): seconds until its button works again, a running timer
## (research left, spawn or income progress), and the units it raised or spawned that still stand.
var cooldown: float = 0.0
var timer: float = 0.0
var spawned: Array[int] = []
## Storehouses: the worker upgrade under way there (a resource, "" = none) and its seconds left.
var study: String = ""
var study_left: float = 0.0
var study_total: float = 0.0


func done() -> bool:
	return progress >= 1.0


## Dwellings: whether it trains this tier.
func trains(t: int) -> bool:
	return t in tiers


## Dwellings: the unit it trains for this tier ("" if none).
func unit_of(t: int) -> String:
	return String(units.get(t, ""))

## id of the structure SimUnit that carries its hit points (wall pieces, and dwellings and
## faction buildings, see BaseDefense), -1 for none.
var structure: int = -1

## Wall pieces only.
var chain: int = 0  ## pieces placed by one order share a chain (workers move on along it)
var axis: Vector2 = Vector2.RIGHT  ## the way the wall runs, for the view
var length: float = 96.0  ## px along the axis, for the view
var upgrade_left: float = 0.0  ## seconds left on turning into a gate or tower
var upgrade_to: String = ""
var garrison: Array[int] = []  ## towers: ids of the archers inside
var gate_open: bool = false


func is_fort() -> bool:
	return kind == "wall" or kind == "gate" or kind == "tower"
