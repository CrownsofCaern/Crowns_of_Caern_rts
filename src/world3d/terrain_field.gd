class_name TerrainField
extends RefCounted
## Heights and ground paint for a 3D map, as plain data (no Nodes).
## One metre per sim cell (CELL_PX pixels). RES samples per metre.
## Built from a cell grid for skirmishes (build_map; Warbound's SimTerrain feeds it a
## SimWorld), or as a battlefield; other views can fill `heights` and `splat` themselves
## and hand the field to MapScene3D. Shared with the main game: no Warbound-only types here.

const RES := 2
const CELL_PX := 32
const PX := float(CELL_PX)  ## sim pixels per metre
## Cell kinds in build_map's grid (same numbers as Warbound's NavGrid.Kind).
const KIND_GROUND := 0
const KIND_ROCK := 1
const KIND_WATER := 2
const KIND_FOREST := 4

var margin: int = 36  ## metres of scenery outside the play area on every side
## Height of a bridge deck (MapScene3D lays the planks at this height).
const BRIDGE_DECK := 0.35
var play_w: int = 0  ## play area in metres
var play_h: int = 0
var sw: int = 0  ## samples
var sh: int = 0
var origin := Vector2.ZERO  ## world xz of sample (0, 0)
var heights := PackedFloat32Array()
## R = dirt (roads, yards), G = rock, B = forest floor, A = ash.
var splat: Image
var water_level: float = -0.45
## Cell kinds of the play area, kept for decoration.
var kinds := PackedByteArray()
## Decoration wanted per sample, in objects per square metre (MapScene3D scatters them).
var tree_d := PackedFloat32Array()
var rock_d := PackedFloat32Array()
var bush_d := PackedFloat32Array()
## Above this z nothing taller than a tuft is placed (keeps a camera's near edge open).
var tall_max_z: float = INF
var roads: Array = []  ## [Vector2 a, Vector2 b] in metres
var yards: Array = []  ## [Vector2 centre, dirt radius, level radius] in metres (settlements)
## Biomes: up to SLOTS dictionaries (Biomes.get_biome): slot 0 is the base, slots 1-4 are
## weighted per sample by the biome map's R, G, B and A; the rest is the base biome.
## With homes only, slot 1 is the west home and slot 2 the east home.
const SLOTS := 5
var biomes: Array = []
var biome_names: Array = []
var biome_map: Image
## Wooden bridges: [Vector2 a, Vector2 b, width] in metres (the ground under them is a raised causeway).
var bridges: Array = []
## Set pieces: [model id, Vector2 xz (m), yaw (rad), scale] placed by MapScene3D (assets/props3d).
var props: Array = []
## What lies outside the play area: "mountains" (default) or "sea".
var border: String = "mountains"
## Raised ground: [Vector2 centre (m), radius (m), height (m)], with a smooth ramp around it.
var plateaus: Array = []
const PLATEAU_RAMP := 6.0
var _noise := FastNoiseLite.new()
var _noise2 := FastNoiseLite.new()
var _noise3 := FastNoiseLite.new()


static func to_world(px: Vector2) -> Vector2:
	return px / PX


static func to_sim(m: Vector2) -> Vector2:
	return m * PX


func size_m() -> Vector2:
	return Vector2(sw - 1, sh - 1) / float(RES)


func _setup(w: int, h: int, seed_value: int) -> void:
	play_w = w
	play_h = h
	sw = (w + margin * 2) * RES + 1
	sh = (h + margin * 2) * RES + 1
	origin = Vector2(-margin, -margin)
	heights.resize(sw * sh)
	tree_d.resize(sw * sh)
	tree_d.fill(0.0)
	rock_d.resize(sw * sh)
	rock_d.fill(0.0)
	bush_d.resize(sw * sh)
	bush_d.fill(0.0)
	splat = Image.create(sw, sh, false, Image.FORMAT_RGBA8)
	_noise.seed = seed_value
	_noise.frequency = 0.045
	_noise.fractal_octaves = 4
	_noise2.seed = seed_value + 7
	_noise2.frequency = 0.012
	_noise2.fractal_octaves = 3
	_noise3.seed = seed_value + 13
	_noise3.frequency = 0.09
	_noise3.fractal_octaves = 2
	biome_map = Image.create(sw, sh, false, Image.FORMAT_RGBA8)
	biome_map.fill(Color(0, 0, 0, 0))
	if biomes.is_empty():
		set_biomes(Biomes.data()["base"], "", "")


## Base biome everywhere, and optionally a west and an east home biome.
func set_biomes(base: String, west: String, east: String) -> void:
	set_biome_slots([base, west, east])


## Base biome first, then up to SLOTS - 1 more ("" or missing = the base).
func set_biome_slots(names: Array) -> void:
	var base: String = names[0] if not names.is_empty() and names[0] != "" else Biomes.data()["base"]
	biome_names = [base]
	for i in range(1, SLOTS):
		var n: String = names[i] if i < names.size() and names[i] != "" else base
		biome_names.append(n)
	biomes = biome_names.map(func(n: String) -> Dictionary: return Biomes.get_biome(n))


## Weights of the SLOTS biomes at sample (i, j), base first.
func biome_weights(i: int, j: int) -> PackedFloat32Array:
	var c := biome_map.get_pixel(i, j)
	return PackedFloat32Array([maxf(0.0, 1.0 - c.r - c.g - c.b - c.a), c.r, c.g, c.b, c.a])


## Name of the strongest biome at world point m (metres, x/z), e.g. for the light.
func biome_at(m: Vector2) -> String:
	if biome_names.is_empty() or biome_map == null:
		return ""
	var i := clampi(int(roundf((m.x - origin.x) * RES)), 0, sw - 1)
	var j := clampi(int(roundf((m.y - origin.y) * RES)), 0, sh - 1)
	var w := biome_weights(i, j)
	var best := 0
	for k in mini(w.size(), biome_names.size()):
		if w[k] > w[best]:
			best = k
	return biome_names[best]


## Blended number from the biomes at sample (i, j).
func biome_value(i: int, j: int, key: String) -> float:
	var w := biome_weights(i, j)
	var v := 0.0
	for k in SLOTS:
		if w[k] > 0.0:
			v += float(biomes[k][key]) * w[k]
	return v


## Ground sinking softly into a pool: a shallow bank from thr - 0.06, under water past thr.
func _pool_height(h: float, pn: float, thr: float) -> float:
	var target := water_level - 0.04 - maxf(0.0, pn - thr) * 0.8
	# Fades out on rising ground, so a pool never cuts a wall into a slope.
	var t := smoothstep(thr - 0.06, thr + 0.03, pn) * (1.0 - smoothstep(0.3, 1.6, h))
	return minf(h, lerpf(h, target, t))


## Height at world xz (metres), bilinear.
func height_at(x: float, z: float) -> float:
	var fx := clampf((x - origin.x) * RES, 0.0, sw - 1.001)
	var fz := clampf((z - origin.y) * RES, 0.0, sh - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := heights[iz * sw + ix]
	var b := heights[iz * sw + ix + 1]
	var c := heights[(iz + 1) * sw + ix]
	var d := heights[(iz + 1) * sw + ix + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


## Distance (in cells, chamfer) from every play cell to the nearest cell of `kind`.
## Rolling hills over the play area (metres, 0 in the valleys): broad, gentle and walkable.
## Rock on a plateau rim is a cliff face, not a mound: 0.25 there, 1 elsewhere.
func _rim_damp(p: Vector2) -> float:
	for pl in plateaus:
		var d := p.distance_to(pl[0]) - float(pl[1])
		if d > -2.5 and d < float(pl[3]) + 2.5:
			return 0.25
	return 1.0


func hill_at(x: float, z: float) -> float:
	return maxf(0.0, _noise2.get_noise_2d(x * 1.6 + 500.0, z * 1.6) * 4.5 + 0.35)


## Distance (cells) from every cell to the nearest cell of kind; with outside, to the
## nearest cell that is not of kind (how deep inside a region of that kind a cell lies).
func _distance_to(kind: int, outside: bool = false) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(play_w * play_h)
	for i in d.size():
		d[i] = 0.0 if (kinds[i] == kind) != outside else 999.0
	for pass_i in 2:
		var ys := range(play_h) if pass_i == 0 else range(play_h - 1, -1, -1)
		var xs := range(play_w) if pass_i == 0 else range(play_w - 1, -1, -1)
		var s := 1 if pass_i == 0 else -1
		for y in ys:
			for x in xs:
				var i: int = y * play_w + x
				var best := d[i]
				var px: int = x - s
				var py: int = y - s
				if px >= 0 and px < play_w:
					best = minf(best, d[y * play_w + px] + 1.0)
				if py >= 0 and py < play_h:
					best = minf(best, d[py * play_w + x] + 1.0)
					if px >= 0 and px < play_w:
						best = minf(best, d[py * play_w + px] + 1.414)
				d[i] = best
	return d


func _cell_dist(d: PackedFloat32Array, x: float, z: float) -> float:
	# Bilinear between cell centres, so ponds and mounds get round edges, not steps.
	var fx := clampf(x - 0.5, 0.0, play_w - 1.001)
	var fz := clampf(z - 0.5, 0.0, play_h - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := d[iz * play_w + ix]
	var b := d[iz * play_w + mini(ix + 1, play_w - 1)]
	var c := d[mini(iz + 1, play_h - 1) * play_w + ix]
	var e := d[mini(iz + 1, play_h - 1) * play_w + mini(ix + 1, play_w - 1)]
	return lerpf(lerpf(a, b, tx), lerpf(c, e, tx), tz)


## Builds the field for a sector skirmish: gentle ground, rock mounds, ponds, woods,
## roads between settlements, mountains and woods all around the play area. Each
## side's home third takes its faction's biome (data/biomes.json).
##   cells: grid_w x grid_h cell kinds (KIND_*), row-major.
##   homes: [[centre (px), faction]]; road_segments: [[a (px), b (px)]];
##   settlements: [[centre (px), small (bool)]]. Positions are in sim pixels.
##   extra (all optional): regions [[centre (px), biome]] give every part of the map the
##   biome of its nearest region (instead of the home thirds); bridges [[a (px), b (px),
##   width (px)]]; props [[model id, centre (px), yaw, scale, pad radius (px)]] (the ground
##   under a pad is levelled and bare); border "mountains" or "sea".
func build_map(grid_w: int, grid_h: int, cells: PackedByteArray, homes: Array, road_segments: Array,
		settlements: Array, seed_value: int = 1, base_biome: String = "", extra: Dictionary = {}) -> void:
	var west := ""
	var east := ""
	for hm in homes:
		var f := Biomes.for_faction(hm[1])
		if (hm[0] as Vector2).x < grid_w * PX * 0.5:
			west = f
		else:
			east = f
	var base: String = base_biome if base_biome != "" else Biomes.data()["base"]
	var regions: Array = extra.get("regions", [])
	var slot_of := {}
	if regions.is_empty():
		set_biomes(base, west, east)
	else:
		var names: Array = [base]
		for rg in regions:
			var b: String = rg[1]
			if b != base and not names.has(b) and names.size() < SLOTS:
				names.append(b)
		set_biome_slots(names)
		for i in range(1, names.size()):
			slot_of[names[i]] = i
	border = String(extra.get("border", "mountains"))
	_setup(grid_w, grid_h, seed_value)
	bridges.clear()
	for br in extra.get("bridges", []):
		bridges.append([to_world(br[0]), to_world(br[1]), float(br[2]) / PX])
	plateaus.clear()
	for pl in extra.get("plateaus", []):
		plateaus.append([to_world(pl[0]), float(pl[1]) / PX, float(pl[2]), float(pl[3]) / PX if pl.size() > 3 else 0.0])
	props.clear()
	var pads: Array = []
	for pr in extra.get("props", []):
		props.append([String(pr[0]), to_world(pr[1]), float(pr[2]), float(pr[3])])
		if pr.size() > 4 and float(pr[4]) > 0.0:
			pads.append([to_world(pr[1]), float(pr[4]) / PX])
	if not regions.is_empty():
		_paint_regions(regions, slot_of)
	kinds = cells.duplicate()
	var d_rock := _distance_to(KIND_ROCK)
	var d_rock_in := _distance_to(KIND_ROCK, true)
	var d_water := _distance_to(KIND_WATER)
	var d_forest := _distance_to(KIND_FOREST)
	roads.clear()
	yards.clear()
	for sg in road_segments:
		roads.append([to_world(sg[0]), to_world(sg[1])])
	for st in settlements:
		var small: bool = st[1]
		var yc := to_world(st[0])
		yards.append([yc, 3.2 if small else 5.0, 4.0 if small else 11.0, 0.15 + hill_at(yc.x, yc.y)])
	for j in sh:
		for i in sw:
			var x := origin.x + float(i) / RES
			var z := origin.y + float(j) / RES
			var n := _noise.get_noise_2d(x, z)
			var n2 := _noise2.get_noise_2d(x, z)
			var h := 0.12 + absf(n) * 0.35 + n2 * 0.25
			var inside := x >= 0.0 and z >= 0.0 and x < play_w and z < play_h
			# Distance outside the play area, in metres.
			var ox := maxf(maxf(-x, x - play_w), 0.0)
			var oz := maxf(maxf(-z, z - play_h), 0.0)
			var out_d := Vector2(ox, oz).length()
			var rock_w := 0.0
			var dirt_w := 0.0
			var forest_w := 0.0
			var k := j * sw + i
			if regions.is_empty():
				# Home biomes fill each side's outer third, with a ragged edge.
				var nb := _noise.get_noise_2d(x * 0.6 + 40.0, z * 0.6) * 6.0
				var bw := clampf((play_w * 0.36 - x + nb) / 8.0, 0.0, 1.0)
				var be := clampf((x - play_w * 0.64 + nb) / 8.0, 0.0, 1.0)
				biome_map.set_pixel(i, j, Color(bw, be, 0.0, 0.0))
			if inside:
				# Rolling ground: broad hills that sink to the level near water, plus rock,
				# mountains and plateaus below.
				var dr := _cell_dist(d_rock, x, z)
				var dw0 := _cell_dist(d_water, x, z)
				h = 0.12 + n * 0.12 + hill_at(x, z) * smoothstep(1.5, 8.0, dw0)
				var dw := _cell_dist(d_water, x, z)
				var df := _cell_dist(d_forest, x, z)
				var mound := clampf(1.0 - (dr - 0.3) / 2.2, 0.0, 1.0)
				h += pow(mound, 1.4) * (1.5 + n * 0.8) * _rim_damp(Vector2(x, z))
				# Deep inside a rock region the ground climbs into a real mountain.
				var deep := _cell_dist(d_rock_in, x, z)
				if deep > 0.0:
					h += minf(deep * 1.5, 12.0) * (1.0 + n * 0.35)
				rock_w = clampf(1.0 - (dr - 0.6) / 1.2, 0.0, 1.0)
				var pond := clampf(1.0 - (dw - 0.2) / 1.8, 0.0, 1.0)
				h = lerpf(h, -1.1, smoothstep(0.0, 1.0, pond))
				forest_w = clampf(1.0 - (df - 0.4) / 2.0, 0.0, 1.0)
				h += forest_w * 0.15
				# Gentle rise toward the edge so the mountains do not start like a wall.
				var edge := minf(minf(x, z), minf(play_w - x, play_h - z))
				if border != "sea":
					h += clampf(1.0 - edge / 6.0, 0.0, 1.0) * 0.6
				var kind: int = kinds[clampi(int(z), 0, play_h - 1) * play_w + clampi(int(x), 0, play_w - 1)]
				if kind == KIND_FOREST:
					tree_d[k] = 0.4
				elif kind == KIND_ROCK:
					rock_d[k] = 0.5 if _rim_damp(Vector2(x, z)) == 1.0 else 0.05  # a cliff face, not a boulder wall
				elif kind == KIND_GROUND:
					# Open ground is never bare: undergrowth in clumps and scattered groves.
					var clump := clampf(_noise.get_noise_2d(x * 1.3 + 57.0, z * 1.3) * 1.6 + 0.4, 0.0, 1.0)
					var grove := clampf((_noise2.get_noise_2d(x * 0.9 + 300.0, z * 0.9) - 0.18) * 2.2, 0.0, 1.0)
					bush_d[k] = 0.35 if df > 0.5 and df < 2.5 else 0.02 + 0.22 * clump * clump + 0.25 * grove
					tree_d[k] = 0.16 * grove + (0.05 if df < 4.0 else 0.0)
					rock_d[k] = 0.003 * clump
			elif border == "sea":
				# Open water past the edge, with far rocky isles on the horizon.
				var isle := clampf(_noise2.get_noise_2d(x * 1.3, z * 1.3) * 3.0 - 0.6, 0.0, 1.0)
				h = lerpf(h, -1.5, clampf(0.75 + out_d / 3.0, 0.0, 1.0)) + isle * smoothstep(12.0, 24.0, out_d) * (4.0 + n * 3.0)
				rock_w = clampf((h - 1.0) / 2.0, 0.0, 1.0)
				if isle > 0.3 and h > 0.5:
					tree_d[k] = 0.08
			else:
				var ridge := 14.0 + 10.0 * _noise2.get_noise_2d(x * 2.0, z * 2.0) + 5.0 * n
				h += pow(clampf(out_d / 26.0, 0.0, 1.0), 1.6) * ridge + clampf(out_d / 4.0, 0.0, 1.0) * 0.7
				rock_w = clampf((h - 5.0) / 4.0, 0.0, 1.0)
				forest_w = clampf(1.0 - out_d / 10.0, 0.0, 1.0) * 0.7
				var clump := clampf(_noise.get_noise_2d(x * 1.7 + 91.0, z * 1.7) * 2.0 + 0.6, 0.0, 1.0)
				if out_d > 1.0:
					tree_d[k] = clampf(1.0 - out_d / 14.0, 0.0, 1.0) * 0.32 + clump * 0.1 * (1.0 - rock_w)
				rock_d[k] = 0.012 * rock_w
				bush_d[k] = 0.06 * (1.0 - rock_w)
			var p := Vector2(x, z)
			for y in yards:
				var yd := p.distance_to(y[0])
				var r: float = y[1]
				dirt_w = maxf(dirt_w, clampf((r - yd) / 1.6 + n * 0.6, 0.0, 1.0))
				# Settlements (and their 3D houses) sit on level ground.
				var flat: float = y[2]
				h = lerpf(h, float(y[3]), clampf((flat + 1.5 - yd) / 2.5, 0.0, 1.0))
				if yd < flat + 9.0 and not (inside and kinds[clampi(int(z), 0, play_h - 1) * play_w + clampi(int(x), 0, play_w - 1)] == KIND_FOREST):
					tree_d[k] = 0.0  # houses and dwellings stand here (never in the woods)
			for rd in roads:
				var ra: Vector2 = rd[0]
				var rb: Vector2 = rd[1]
				if p.x < minf(ra.x, rb.x) - 3.0 or p.x > maxf(ra.x, rb.x) + 3.0 \
						or p.y < minf(ra.y, rb.y) - 3.0 or p.y > maxf(ra.y, rb.y) + 3.0:
					continue
				var q := Geometry2D.get_closest_point_to_segment(p, ra, rb)
				var dd := p.distance_to(q)
				var width := 1.1 + n * 0.5
				dirt_w = maxf(dirt_w, clampf((width - dd) / 0.7, 0.0, 1.0))
			# Water cells stay water: pads and causeways only lift dry ground.
			var wet_cell := inside and kinds[clampi(int(z), 0, play_h - 1) * play_w + clampi(int(x), 0, play_w - 1)] == KIND_WATER
			# Set pieces stand on level, bare ground.
			for pd in pads:
				var pdd := p.distance_to(pd[0])
				var pr: float = pd[1]
				if pdd < pr + 2.0:
					dirt_w = maxf(dirt_w, clampf((pr - pdd) / 1.5 + n * 0.5, 0.0, 1.0) * 0.8)
					if not wet_cell:
						h = lerpf(h, maxf(h, 0.15) if h < 1.0 else h, clampf((pr + 1.0 - pdd) / 2.0, 0.0, 1.0))
					tree_d[k] = 0.0
					rock_d[k] = 0.0
					bush_d[k] = 0.0
			# Plateaus: the ground (settlement yard and all) lifts as one. Where the rim is
			# rock (a cliff in the sim) it drops steeply; where a road comes in, a long ramp.
			for pl in plateaus:
				var pc: Vector2 = pl[0]
				var dpl := p.distance_to(pc)
				var band: float = pl[3]
				if dpl > float(pl[1]) + band + PLATEAU_RAMP + 6.0:
					continue
				var dir := (p - pc) / maxf(dpl, 0.001)
				var on_rim := pc + dir * (float(pl[1]) + band * 0.5)
				var open := 1.0 if band <= 0.0 else clampf((_cell_dist(d_rock, on_rim.x, on_rim.y) - 0.5) / 2.5, 0.0, 1.0)
				var rim := float(pl[1]) + _noise2.get_noise_2d(x * 1.7 + 11.0, z * 1.7) * 3.0 * open
				var ramp := lerpf(band + 0.6, PLATEAU_RAMP + 7.0, open)
				var lift := smoothstep(rim + ramp, rim, dpl)
				if lift > 0.0 and not wet_cell:
					h += float(pl[2]) * lift
					var slope := lift * (1.0 - lift) * 4.0
					rock_w = maxf(rock_w, slope * lerpf(1.0, 0.35 * clampf(n * 2.0 + 0.6, 0.0, 1.0), open))
					if lift < 0.97 and ramp < 3.5:  # no trees on the cliff face
						bush_d[k] = 0.0
						tree_d[k] = 0.0
			# Bog pools (or lava pockets) in wet or burnt biomes, never on roads or
			# yards; lava only where nobody walks.
			var wet := biome_value(i, j, "puddles")
			var near_yard := false
			for y in yards:
				if p.distance_to(y[0]) < float(y[2]) + 2.0:
					near_yard = true
			if wet > 0.0 and dirt_w < 0.05 and not near_yard and rock_w < 0.3:
				var lava := biome_value(i, j, "lava")
				var cell_ok := not inside
				if inside:
					var kd: int = kinds[clampi(int(z), 0, play_h - 1) * play_w + clampi(int(x), 0, play_w - 1)]
					cell_ok = kd == KIND_GROUND and lava < 0.5
				var pn := _noise3.get_noise_2d(x, z) * 0.5 + 0.5
				var thr := 1.0 - wet * 0.45
				if cell_ok and pn > thr - 0.06 and h < 1.6:
					h = _pool_height(h, pn, thr)
					forest_w = maxf(forest_w, 0.6 * smoothstep(thr - 0.06, thr, pn))
			# Bridges: a causeway at deck height under each bridge, so units walk on the deck.
			for br in bridges:
				var bq := Geometry2D.get_closest_point_to_segment(p, br[0], br[1])
				var bd := p.distance_to(bq)
				var half: float = float(br[2]) * 0.5
				if bd < half + 0.8 and not wet_cell:
					h = lerpf(h, BRIDGE_DECK - 0.1, clampf((half + 0.8 - bd) / 0.8, 0.0, 1.0))
					dirt_w = maxf(dirt_w, 0.5)
			heights[k] = h
			if dirt_w > 0.2 or h < water_level + 0.25:
				tree_d[k] = 0.0
				bush_d[k] = 0.0
				rock_d[k] = 0.0
			var ash := clampf(-n2 * 1.5 - 0.6, 0.0, 1.0) * (1.0 - dirt_w)
			splat.set_pixel(i, j, Color(dirt_w, rock_w, forest_w, ash))


## Biome map from regions: every sample takes the biome of its nearest region centre
## (distances wobbled by noise for ragged borders), blended over a few metres where two
## regions meet. Painted at a quarter of the resolution, then smoothed up.
func _paint_regions(regions: Array, slot_of: Dictionary) -> void:
	var cs := 4
	var lw := (sw - 1) / cs + 1
	var lh := (sh - 1) / cs + 1
	var small := Image.create(lw, lh, false, Image.FORMAT_RGBA8)
	var pts: Array = []
	for rg in regions:
		pts.append([to_world(rg[0]), int(slot_of.get(rg[1], 0))])
	for lj in lh:
		for li in lw:
			var x := origin.x + float(li * cs) / RES
			var z := origin.y + float(lj * cs) / RES
			var best := INF
			var second := INF
			var bs := 0
			var ss := 0
			for qi in pts.size():
				var q: Array = pts[qi]
				var d := Vector2(x, z).distance_to(q[0]) + _noise.get_noise_2d(x * 0.5 + qi * 31.0, z * 0.5) * 9.0
				if d < best:
					second = best
					ss = bs
					best = d
					bs = q[1]
				elif d < second:
					second = d
					ss = q[1]
			var w := [0.0, 0.0, 0.0, 0.0, 0.0]
			var t := clampf(0.5 + (second - best) / 14.0, 0.5, 1.0)
			w[bs] += t
			w[ss] += 1.0 - t
			small.set_pixel(li, lj, Color(w[1], w[2], w[3], w[4]))
	small.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
	biome_map = small


## A battlefield centred on the origin: w x h metres, flat at y = 0 where the armies
## stand (|x| < flat.x, |z| < flat.y), hills, woods and rocks around it, ridges beyond.
## Nothing tall south of `keep_open_z` (a camera looking toward -z sits there).
func build_battlefield(w: int = 80, h: int = 50, seed_value: int = 1, flat := Vector2(30.0, 13.0),
		keep_open_z: float = 12.0, biome: String = "") -> void:
	margin = 30
	set_biomes(biome if biome != "" else Biomes.data()["base"], "", "")
	_setup(w, h, seed_value)
	origin = Vector2(-w * 0.5 - margin, -h * 0.5 - margin)
	tall_max_z = keep_open_z
	kinds = PackedByteArray()
	roads.clear()
	yards.clear()
	for j in sh:
		for i in sw:
			var x := origin.x + float(i) / RES
			var z := origin.y + float(j) / RES
			var k := j * sw + i
			var n := _noise.get_noise_2d(x, z)
			var n2 := _noise2.get_noise_2d(x, z)
			# How far outside the flat battle ground, and outside the whole field.
			var off := Vector2(maxf(absf(x) - flat.x, 0.0), maxf(absf(z) - flat.y, 0.0)).length()
			var out_d := Vector2(maxf(absf(x) - w * 0.5, 0.0), maxf(absf(z) - h * 0.5, 0.0)).length()
			var hill := (absf(n) * 1.6 + n2 * 1.2 + 0.6) * smoothstep(0.0, 10.0, off)
			# Rolling ground behind the battle line (the camera looks that way).
			if z < -flat.y:
				hill += (absf(n2) * 3.5 + absf(n) * 1.5) * smoothstep(0.0, 14.0, -z - flat.y)
			var ridge := (9.0 + 6.0 * _noise2.get_noise_2d(x * 2.0, z * 2.0) + 3.0 * n) \
				* pow(clampf(out_d / 24.0, 0.0, 1.0), 1.5)
			var near := z > keep_open_z
			var hh := hill + ridge
			if near:
				# The camera side only dips and swells gently; it must not block the view.
				hh = minf(hh, 0.3 + n * 0.3) * smoothstep(0.0, 6.0, off)
			# Pools (bog water or lava) off the fighting ground, in wet or burnt biomes.
			var wet := float(biomes[0]["puddles"])
			if wet > 0.0 and off > 3.0 and hh < 1.6:
				var pn := _noise3.get_noise_2d(x, z) * 0.5 + 0.5
				var thr := 1.0 - wet * 0.45
				if pn > thr - 0.06:
					hh = _pool_height(hh, pn, thr)
			heights[k] = hh
			var rock_w := clampf((hh - 6.0) / 4.0, 0.0, 1.0)
			var clump := clampf(_noise.get_noise_2d(x * 1.7 + 91.0, z * 1.7) * 2.2 + 0.2, 0.0, 1.0)
			var wood := clump * smoothstep(3.0, 9.0, off)
			var forest_w := clampf(wood * 1.3, 0.0, 1.0)
			# Trampled ground where the armies meet.
			var dirt_w := clampf((0.25 - absf(n) * 1.4 + n2 * 0.5) * 1.2, 0.0, 1.0) * (1.0 - smoothstep(0.0, 6.0, off))
			var ash := clampf(-n2 * 1.5 - 0.7, 0.0, 1.0) * (1.0 - dirt_w)
			splat.set_pixel(i, j, Color(dirt_w, rock_w, forest_w, ash))
			if not near:
				tree_d[k] = (wood * 0.16 + (0.02 if off > 4.0 else 0.0)) * (1.0 - rock_w)
				rock_d[k] = (0.01 + 0.03 * rock_w) * smoothstep(2.0, 6.0, off)
			bush_d[k] = (0.25 if wood > 0.05 and wood < 0.5 else 0.03) * smoothstep(1.0, 4.0, off)
			if hh < water_level + 0.2:
				tree_d[k] = 0.0
				rock_d[k] = 0.0
				bush_d[k] = 0.0
