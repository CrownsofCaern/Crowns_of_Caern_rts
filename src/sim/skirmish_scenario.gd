class_name SkirmishScenario
extends RefCounted
## The M1 grey-box battle: a field with rock outcrops and a pond, two armies.

const MAP_W := 120
const MAP_H := 72
## Units per tier for a full army (150 units).
const ARMY_SHAPE := [40, 30, 25, 20, 12, 10, 8, 5]


static func build(seed_value: int, factions: Array = ["concord", "hollow"], army_scale: float = 1.0) -> SimWorld:
	var world := SimWorld.new(seed_value)
	var map_rng := world.rng.fork(1)
	var water: Array = []
	var rocks := _obstacles(map_rng, water)
	world.setup_map(MAP_W, MAP_H, rocks, water)
	for side in 2:
		_place_army(world, side, factions[side], army_scale)
	return world


static func _obstacles(r: GameRng, water: Array) -> Array:
	var cells: Array = []
	var seen := {}
	# Rock outcrops in the middle band, kept away from both deployment zones.
	for i in 14:
		var c := Vector2i(r.next_int(30, MAP_W - 31), r.next_int(6, MAP_H - 7))
		var size := r.next_int(1, 3)
		for dy in range(-size, size + 1):
			for dx in range(-size - 1, size + 2):
				if Vector2(dx, dy).length() <= size + 0.5 + r.next_float() * 0.6:
					_add(cells, seen, c + Vector2i(dx, dy))
	# A pond near the centre, with land on both sides to go around.
	var pc := Vector2i(MAP_W / 2, r.next_int(MAP_H / 2 - 8, MAP_H / 2 + 8))
	for dy in range(-5, 6):
		for dx in range(-4, 5):
			if Vector2(dx * 1.2, dy).length() <= 5.0:
				_add(water, seen, pc + Vector2i(dx, dy))
	return cells


static func _add(cells: Array, seen: Dictionary, c: Vector2i) -> void:
	if c.x < 0 or c.y < 0 or c.x >= MAP_W or c.y >= MAP_H or seen.has(c):
		return
	seen[c] = true
	cells.append(c)


static func _place_army(world: SimWorld, side: int, faction: String, scale: float) -> void:
	var ids: Array = world.catalog.faction_units(faction)
	var x_front: float = 18.0 * NavGrid.CELL if side == 0 else (MAP_W - 18) * NavGrid.CELL
	var dir: float = -1.0 if side == 0 else 1.0  # rows go back toward the map edge
	var row := 0
	for tier_i in ids.size():
		var n := int(round(ARMY_SHAPE[tier_i] * scale))
		if n <= 0:
			continue
		var d: Dictionary = world.catalog.get_unit(ids[tier_i])
		var step := float(d["radius"]) * 2.0 + 6.0
		var per_row := maxi(1, int(floor(MAP_H * NavGrid.CELL * 0.6 / step)))
		# Ranged and support stand behind the melee line.
		var back: bool = d["role"] in ["ranged", "support"]
		for i in n:
			var r := row + i / per_row + (6 if back else 0)
			var col := i % per_row
			var y := MAP_H * NavGrid.CELL * 0.5 + (float(col) - float(mini(n, per_row) - 1) * 0.5) * step
			var x: float = x_front + dir * (float(r) * 30.0)
			world.spawn(ids[tier_i], side, Vector2(x, y))
		if not back:
			row += int(ceil(float(n) / per_row))


# --- The sector skirmish -------------------------------------------------------------

const MAX_PLAYERS := 4


## A skirmish for 2 to MAX_PLAYERS players (owner i plays factions[i]) on a generated map
## (MapGen, data/map_templates.json). template: a template id, or "" / "random" for one
## picked by the seed among those that hold this many players.
static func build_skirmish(seed_value: int, factions: Array = ["concord", "hollow"], template: String = "") -> SimWorld:
	assert(factions.size() >= 2 and factions.size() <= MAX_PLAYERS, "2 to %d players" % MAX_PLAYERS)
	var world := SimWorld.new(seed_value)
	MapGen.generate(world, seed_value, factions, template)
	return world


## Map templates a skirmish with this many players can use, as [id, name] pairs.
static func templates(players: int) -> Array:
	return MapGen.template_ids(players).map(func(id: String) -> Array: return [id, MapGen.template_name(id)])


## Road segments ([a, b] in px) of the map: the generator's when there is one, else
## straight lines between the centres of sectors that lie side by side.
static func roads(eco: Economy) -> Array:
	var info: Dictionary = eco.world.map_info
	if info.has("roads"):
		return info["roads"]
	var out: Array = []
	for i in eco.sectors.size():
		for j in range(i + 1, eco.sectors.size()):
			var a: Vector2 = eco.sectors[i].center
			var b: Vector2 = eco.sectors[j].center
			if a.distance_to(b) < 1600.0:
				out.append([a, b])
	return out
