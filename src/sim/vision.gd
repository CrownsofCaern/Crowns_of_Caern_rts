class_name Vision
extends RefCounted
## Fog of war: what each player sees now and what it has ever seen, on a coarse grid.
## Units see their sight radius (times a faction's sight_factor), buildings and held
## sectors light their surroundings. Updated every UPDATE_TICKS ticks; deterministic.
## The rules don't use it yet (computer players still see everything); the view hides
## what the human player can't see.

const CELL := 64.0  ## px per vision cell
const UPDATE_TICKS := 5
const BUILDING_SIGHT := 280.0  ## px beyond a building's footprint
const SECTOR_SIGHT := 340.0  ## px around a held settlement's centre

const HIDDEN := 0
const EXPLORED := 1
const VISIBLE := 2

var width: int = 0
var height: int = 0
var _state: Dictionary = {}  ## owner -> PackedByteArray of HIDDEN / EXPLORED / VISIBLE


func setup(world_size: Vector2) -> void:
	width = maxi(1, int(ceil(world_size.x / CELL)))
	height = maxi(1, int(ceil(world_size.y / CELL)))
	_state.clear()


func _grid(owner: int) -> PackedByteArray:
	if not _state.has(owner):
		var g := PackedByteArray()
		g.resize(width * height)
		g.fill(HIDDEN)
		_state[owner] = g
	return _state[owner]


## Recomputes every player's sight from the world (visible cells fade to explored).
func update(world: SimWorld) -> void:
	if width == 0:
		setup(world.nav.world_size())
	# Units see a little farther than they pick fights (rules.vision_scale).
	var scale := float(world.catalog.rules.get("vision_scale", 1.0))
	var owners: Array = []
	var eco := world.economy
	for pl in eco.players:
		owners.append(pl.owner)
	for o in owners:
		var g := _grid(o)
		for i in g.size():
			if g[i] == VISIBLE:
				g[i] = EXPLORED
	for u in world.units:
		if u.alive and u.owner in owners:
			_light(_grid(u.owner), u.pos, world._sight(u) * scale)
	for b in eco.buildings:
		if b.owner in owners:
			_light(_grid(b.owner), b.pos, b.radius + maxf(BUILDING_SIGHT, world.specials.sight_of(b)))
	for s in eco.sectors:
		if s.owner in owners:
			_light(_grid(s.owner), s.center, SECTOR_SIGHT)


func _light(g: PackedByteArray, p: Vector2, r: float) -> void:
	var cx := int(p.x / CELL)
	var cy := int(p.y / CELL)
	var n := int(ceil(r / CELL))
	var r2 := r * r
	for y in range(maxi(0, cy - n), mini(height, cy + n + 1)):
		for x in range(maxi(0, cx - n), mini(width, cx + n + 1)):
			var c := Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)
			if c.distance_squared_to(p) <= r2:
				g[y * width + x] = VISIBLE


func state_at(owner: int, p: Vector2) -> int:
	if width == 0 or not _state.has(owner):
		return HIDDEN
	var x := clampi(int(p.x / CELL), 0, width - 1)
	var y := clampi(int(p.y / CELL), 0, height - 1)
	return _state[owner][y * width + x]


func is_visible(owner: int, p: Vector2) -> bool:
	return state_at(owner, p) == VISIBLE


func is_explored(owner: int, p: Vector2) -> bool:
	return state_at(owner, p) != HIDDEN


## The owner's fog as raw cells (row-major, width x height), for the view's textures.
func cells(owner: int) -> PackedByteArray:
	return _grid(owner)
