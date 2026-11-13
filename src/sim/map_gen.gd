class_name MapGen
extends RefCounted
## Template-based skirmish maps (data/map_templates.json). A template lists zones (one
## sector each, with its settlement), links between them (roads, trails, mountain passes,
## bridges, fords, land bridges), sites (guarded lairs, shrines, merchants) and terrain
## features (sea, islands, lakes, rivers, ridges, big woods). The generator copies them by
## the template's symmetry, jitters them by the seed, carves every link through whatever
## lies in its way (a link over water becomes a bridge, through rock a pass), scatters
## woods, rocks and ponds, makes sure everything is reachable, and dresses sites and some
## zones with set pieces (CC0 ruins, temples, graveyards: assets/props3d).
## Headless and deterministic: all randomness comes from the world's GameRng.
## The view reads the result from world.map_info (roads, bridges, props, biome regions).

const PATH := "res://data/map_templates.json"
const SYMMETRIES := {"none": 1, "mirror_x": 2, "rot180": 2, "mirror4": 4}
## Corridor width (cells) carved along each kind of link.
const LINK_WIDTH := {"road": 4.0, "trail": 3.0, "pass": 3.0, "bridge": 3.0, "ford": 4.0, "land": 10.0}
## Links drawn as dirt roads on the ground (the others are just open ground).
const PAINTED := ["road", "bridge", "pass"]
const SITE_KINDS := ["lair", "shrine", "merchant"]
## Quarter (image) -> owner on a mirror4 map: opposite corners first, as before.
const OWNER_OF_QUARTER := [0, 2, 3, 1]
## Clear ground (cells) around a zone centre: settlements need room for buildings.
const HOME_CLEAR := 20.0
## A home's timber and ore lie this many cells beyond the edge of the town (settlement_clearance).
const HOME_PILE_GAP := [1.5, 4.0]
const ZONE_CLEAR := 15.0
const WAYSTONE_CLEAR := 8.0
const CLIFF_BAND := 1.6  ## width of a plateau's cliff ring, in cells
## Set pieces: parts are [model, x, y (cells, local frame: front is +y), yaw (deg), scale,
## block radius (cells, 0 = walk-through)]; clear = radius of open ground the piece needs.
const SET_PIECES := {
	"temple_ruin": {"clear": 15.0, "parts": [["tp_pantheon", 0, -5.5, 0, 0.6, 4.0],
		["dn_column", -7, -1, 0, 1.0, 0.9], ["dn_column_broken", 7, -2, 70, 1.0, 1.2], ["dn_column", -8, -6, 0, 1.0, 0.9],
		["dn_column_stump", 8, -7, 0, 1.0, 0.7], ["dn_column_2", -6, 3, 0, 1.0, 0.8], ["dn_column_stump", 6, 3, 30, 1.0, 0.7],
		["dn_statue_horse", -3.5, 1.5, 180, 0.9, 0.9], ["dn_statue_horse", 3.5, 1.5, 180, 0.9, 0.9],
		["gy_debris", 3, -3, 40, 1.0, 0], ["dn_candelabrum", -1.6, -1.5, 0, 1.0, 0], ["dn_candelabrum", 1.6, -1.5, 0, 1.0, 0]]},
	"ziggurat": {"clear": 16.0, "parts": [["tp_ziggurat", 0, -6.5, 0, 0.65, 5.5], ["gy_obelisk", -7, 1, 0, 1.0, 0.6],
		["gy_obelisk", 7, 1, 0, 1.0, 0.6], ["dn_woodfire", -3, 1, 0, 1.4, 0], ["dn_woodfire", 3, 1, 0, 1.4, 0],
		["dn_bones", -5, 4, 20, 1.6, 0], ["dn_skull", 4.5, 4, 200, 1.3, 0], ["dn_spikes", -9, -3, 0, 1.0, 0.8],
		["dn_spikes", 9, -3, 0, 1.0, 0.8]]},
	"graveyard": {"clear": 11.0, "parts": [["gy_crypt", 0, -6, 0, 1.0, 3.2], ["gy_grave_cross_large", -4, -2, 0, 1.0, 0],
		["gy_grave_round", -2, -2, 0, 1.0, 0], ["gy_grave_broken", 2, -2, 0, 1.0, 0], ["gy_grave_cross", 4, -2, 0, 1.0, 0],
		["gy_grave_decorative", -4, 1, 0, 1.0, 0], ["gy_grave_roof", -2, 1, 0, 1.0, 0], ["gy_grave_debris", 2, 1, 30, 1.0, 0],
		["gy_grave_round", 4, 1, 0, 1.0, 0], ["gy_grave", -3, 4, 90, 0.9, 0], ["gy_coffin", 3, 4, 80, 1.0, 0],
		["gy_cross", -7, -6, 0, 1.0, 0.5], ["gy_lantern", -6, 5, 0, 1.0, 0], ["gy_lantern", 6, 5, 0, 1.0, 0],
		["gy_fence_iron", -8, -3, 90, 1.0, 0], ["gy_fence_iron", -8, -1, 90, 1.0, 0], ["gy_fence_broken", -8, 1.5, 90, 1.0, 0],
		["gy_fence_iron", 8, -3, 90, 1.0, 0], ["gy_fence_iron", 8, -1, 90, 1.0, 0], ["gy_fence_iron", 8, 1, 90, 1.0, 0],
		["gy_urn", 1.5, -4.5, 0, 1.0, 0], ["gy_urn", -1.5, -4.5, 0, 1.0, 0]]},
	"watch_ruin": {"clear": 10.0, "parts": [["md_tower_large", -4.5, -5, 0, 1.0, 1.7], ["cs_wall_half", 0, -6, 0, 0.9, 1.9],
		["cs_wall_corner", 4.5, -5, 90, 0.9, 1.9], ["gy_debris", 2, -2, 15, 1.2, 0], ["dn_column_stump", -2, -2, 0, 1.0, 0],
		["gy_debris", -6, -1, 70, 1.0, 0], ["dn_banner", 0, -3.5, 0, 1.0, 0]]},
	"dragon_bones": {"clear": 11.0, "parts": [["dn_skull", 0, -5, 180, 5.0, 1.4], ["dn_bones", -4, -2, 30, 4.0, 0],
		["dn_bones_2", 4, -1, 200, 4.0, 0], ["dn_bones", 2, 4, 120, 3.0, 0], ["dn_column_broken", -7, -6, 20, 1.0, 1.2],
		["dn_spikes", 7, -6, 0, 1.0, 0.8], ["dn_spikes", -7, 4, 0, 1.0, 0.8], ["gy_debris", 6, 3, 10, 1.2, 0]]},
	"war_camp": {"clear": 11.0, "parts": [["md_watchtower", 0, -7, 0, 1.0, 1.6], ["cs_trebuchet", -5, -4, 20, 1.0, 2.2],
		["cs_catapult", 5, -3, -30, 1.0, 1.8], ["dn_woodfire", 0, 0, 0, 1.2, 0], ["dn_barrel", -2, -3, 0, 1.0, 0],
		["dn_barrel", -2.8, -2.4, 0, 1.0, 0], ["dn_crate", 2.4, -3, 15, 1.0, 0], ["dn_crate", 2.4, -3, 15, 1.0, 0],
		["cs_banner", -3, 3, 90, 1.0, 0], ["cs_banner", 3, 3, 90, 1.0, 0]]},
	"stone_circle": {"clear": 8.0, "parts": [["gy_obelisk", 0, -5, 0, 1.0, 0.6], ["gy_pillar", 3.5, -3.5, 45, 1.0, 0.5],
		["gy_obelisk", 5, 0, 0, 1.0, 0.6], ["gy_pillar", -3.5, -3.5, -45, 1.0, 0.5], ["gy_obelisk", -5, 0, 0, 1.0, 0.6],
		["gy_pillar", 3.5, 3.5, 45, 0.8, 0.5], ["gy_pillar", -3.5, 3.5, -45, 0.8, 0.5], ["dn_pedestal_2", 0, 0, 0, 0.9, 0],
		["dn_candelabrum", 1.2, 1.2, 0, 1.0, 0], ["dn_candelabrum", -1.2, 1.2, 0, 1.0, 0]]},
	"trading_post": {"clear": 9.0, "parts": [["md_watchtower_roof", -4, -4, 0, 1.0, 1.6], ["dn_barrel", 2, -3, 0, 1.0, 0],
		["dn_barrel", 2.9, -3.3, 0, 1.0, 0], ["dn_barrel", 2.4, -2.4, 0, 1.0, 0], ["dn_crate", 4, -2, 20, 1.1, 0],
		["dn_crate", 4.2, -0.8, -10, 1.0, 0], ["dn_woodfire", 0, 1, 0, 1.0, 0], ["cs_banner", -1, -4, 90, 0.8, 0],
		["dn_chest_gold", -2, -1.5, 30, 0.8, 0]]},
	"small_ruin": {"clear": 6.0, "parts": [["cs_wall_half", 0, 0, 0, 0.8, 1.6], ["gy_debris", 2.5, 1.5, 20, 1.0, 0],
		["dn_column_stump", -2.6, 1.2, 0, 1.0, 0.6]]},
	"small_graves": {"clear": 5.0, "parts": [["gy_cross", 0, -1.5, 0, 0.9, 0.4], ["gy_grave_round", -1.5, 0.5, 0, 1.0, 0],
		["gy_grave_cross", 0, 0.5, 0, 1.0, 0], ["gy_grave_broken", 1.5, 0.5, 0, 1.0, 0], ["gy_grave", 0, 2.5, 90, 0.8, 0]]},
	"column_ring": {"clear": 6.0, "parts": [["dn_column", -3, -2, 0, 0.9, 0.8], ["dn_column_stump", 3, -2, 0, 1.0, 0.6],
		["dn_column_broken", 3, 2.5, 80, 0.8, 1.0], ["dn_column_2", -3, 2, 0, 0.9, 0.7], ["dn_pedestal", 0, 0, 0, 0.8, 0.6]]},
	"siege_wreck": {"clear": 6.0, "parts": [["cs_catapult", 0, 0, 25, 0.9, 1.6], ["gy_debris", 2.5, 2, 0, 0.9, 0],
		["dn_skull", -2, 1.5, 0, 1.0, 0], ["dn_bones", -1.5, 2.5, 50, 1.0, 0]]},
	"lone_tower": {"clear": 5.0, "parts": [["md_tower_pointy", 0, 0, 0, 0.9, 1.6], ["gy_debris", 2.2, 1.0, 40, 0.8, 0]]},
	"siege_tower": {"clear": 6.0, "parts": [["cs_siege_tower", 0, 0, 10, 0.9, 2.0], ["dn_crate", 2.6, 1.5, 0, 1.0, 0]]},
	# Landmarks modelled (Tripo) from the main game's encounter and place paintings.
	"cinder_gate": {"clear": 13.0, "parts": [["lm_cindermaw_gate", 0, -5, 0, 1.0, 4.0], ["dn_spikes", -7, -1, 0, 1.0, 0.8],
		["dn_spikes", 7, -1, 0, 1.0, 0.8], ["dn_bones", -3, 3, 30, 1.5, 0], ["dn_skull", 3, 3, 200, 1.2, 0]]},
	"pyre_hold": {"clear": 14.0, "parts": [["lm_pyrehold", 0, -5.5, 0, 1.0, 4.5], ["dn_woodfire", -4, 2, 0, 1.4, 0],
		["dn_woodfire", 4, 2, 0, 1.4, 0], ["gy_obelisk", -7.5, 0, 0, 1.0, 0.6], ["gy_obelisk", 7.5, 0, 0, 1.0, 0.6]]},
	"citadel_ruin": {"clear": 15.0, "parts": [["lm_shattered_citadel", 0, -6, 0, 1.0, 5.0], ["gy_debris", -6, 2, 30, 1.2, 0],
		["gy_debris", 6, 1, 200, 1.0, 0], ["dn_banner", -3, 2.5, 0, 1.0, 0], ["dn_column_broken", 7, -3, 80, 1.0, 1.0]]},
	"echo_hall": {"clear": 13.0, "parts": [["lm_hall_of_echoes", 0, -5, 0, 1.0, 4.0], ["dn_column_stump", -6, 2, 0, 1.0, 0.6],
		["dn_column_broken", 6, 2, 60, 1.0, 1.0], ["gy_debris", 2, 2.5, 20, 1.0, 0], ["dn_candelabrum", -1.5, 1, 0, 1.0, 0]]},
	"barrow_camp": {"clear": 11.0, "parts": [["lm_barrow_camp", 0, -4, 0, 1.0, 3.5], ["dn_woodfire", 0, 2.5, 0, 1.2, 0],
		["dn_barrel", -3.5, 1.5, 0, 1.0, 0], ["dn_crate", 3.5, 1.5, 20, 1.0, 0]]},
	"wolf_den": {"clear": 9.0, "parts": [["lm_thornwolf_den", 0, -3, 0, 1.0, 2.8], ["dn_bones", -3, 2, 40, 1.3, 0],
		["dn_skull", 2.5, 2, 0, 1.0, 0]]},
	"drowned_chapel": {"clear": 9.0, "parts": [["lm_drowned_chapel", 0, -3, 0, 1.0, 2.8], ["dn_candelabrum", -1.6, 1.2, 0, 1.0, 0],
		["dn_candelabrum", 1.6, 1.2, 0, 1.0, 0]]},
	"saint_shrine": {"clear": 8.0, "parts": [["lm_ashen_saint_shrine", 0, -3, 0, 1.0, 2.4], ["dn_candelabrum", -1.4, 1, 0, 1.0, 0],
		["dn_candelabrum", 1.4, 1, 0, 1.0, 0]]},
	"orrin_rest": {"clear": 9.0, "parts": [["lm_saint_orrins_rest", 0, -3, 0, 1.0, 3.0], ["dn_pedestal_2", 0, 1.5, 0, 0.8, 0]]},
	"trader_stall": {"clear": 9.0, "parts": [["lm_trader_stall", 0, -3, 0, 1.0, 2.4], ["dn_barrel", 3.5, -1, 0, 1.0, 0],
		["dn_barrel", 4.2, -0.2, 0, 1.0, 0], ["dn_crate", -3.6, -0.5, 15, 1.0, 0], ["dn_woodfire", 0, 2, 0, 1.0, 0]]},
	"lockstone": {"clear": 5.0, "parts": [["lm_lockstone", 0, 0, 0, 1.0, 1.8]]},
	"obelisk": {"clear": 4.0, "parts": [["lm_obelisk", 0, 0, 0, 1.0, 1.3]]},
}
## Set pieces dressing ordinary zones now and then (one at most per zone).
const FLAVOUR := ["small_ruin", "small_graves", "column_ring", "siege_wreck", "lone_tower", "siege_tower", "small_ruin",
	"lockstone", "obelisk", "lockstone"]
const LAIR_SETS := {1: ["war_camp", "watch_ruin", "small_graves", "wolf_den", "wolf_den"],
	2: ["graveyard", "watch_ruin", "war_camp", "barrow_camp", "echo_hall", "barrow_camp"],
	3: ["temple_ruin", "dragon_bones", "ziggurat", "cinder_gate", "pyre_hold", "citadel_ruin"]}
const SITE_SETS := {"shrine": ["stone_circle", "drowned_chapel", "saint_shrine", "orrin_rest"],
	"merchant": ["trading_post", "trader_stall", "trader_stall"]}

static var _data: Dictionary = {}

var world: SimWorld
var r: GameRng
var noise := FastNoiseLite.new()
var tid: String = ""
var t: Dictionary = {}
var sym: String = "none"
var factions: Array = []
var W: int = 0
var H: int = 0
var kinds := PackedByteArray()  ## NavGrid.Kind per cell
var keep := PackedByteArray()  ## 1 = left open (corridors, centres, sites): no scatter
var corridor := PackedByteArray()  ## 1 = on a link (no resource piles)
## Zones and sites: {id, kind ("zone" | "site"), def, pos (cells), img, owner, size, biome, clear}
var nodes: Array = []
var _by_ref: Dictionary = {}  ## "id#img" -> node index
var roads_px: Array = []
var bridges_px: Array = []
var props: Array = []
var _wild: Array = []
var _base_biome: String = "meadow"
var site_ids: Dictionary = {}  ## node index -> MapSites id
## True on handcrafted campaign layouts: their settlements keep the plain militia they were tuned with.
var plain_militia: bool = false


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data


## Template ids that hold this many players, sorted.
static func template_ids(players: int) -> Array:
	var out: Array = []
	for id: String in data()["templates"]:
		if players in (data()["templates"][id]["players"] as Array).map(func(x: Variant) -> int: return int(x)):
			out.append(id)
	out.sort()
	return out


static func template_name(id: String) -> String:
	return String(data()["templates"].get(id, {}).get("name", id))


## One or two sentences on the layout, for the setup screen.
static func template_desc(id: String) -> String:
	return String(data()["templates"].get(id, {}).get("desc", ""))


## Builds the map into a fresh SimWorld (no map set up yet). template_id "" or "random"
## picks one from the seed. Returns the template used.
static func generate(w: SimWorld, seed_value: int, facs: Array, template_id: String = "") -> String:
	var g := MapGen.new()
	g.world = w
	g.r = w.rng.fork(5)
	g.factions = facs
	var ids := template_ids(facs.size())
	assert(not ids.is_empty(), "no map template for %d players" % facs.size())
	var id := template_id
	if id == "" or id == "random" or not ids.has(id):
		id = ids[GameRng.mix(seed_value, 77) % ids.size()]
	g._build(id)
	return id


## Builds a handcrafted campaign map (a template written for one fixed layout: symmetry
## "none", "jitter" 0 keeps every position exact) into a fresh SimWorld. Zones may carry an
## "owner" (a player index; a "home" zone is that player's start) and a "name"; lair sites may
## list fixed "guards" ([[unit, count], ...]). world.map_info["refs"] maps every zone and site
## id to its place: {kind, pos (px), sector or site id}.
static func build_layout(w: SimWorld, seed_value: int, facs: Array, layout: Dictionary, id: String = "campaign") -> void:
	var g := MapGen.new()
	g.world = w
	g.r = w.rng.fork(5)
	g.factions = facs
	g.t = layout
	g.plain_militia = true
	g._build(id)


# --- Images (symmetry) -------------------------------------------------------------

func _images() -> int:
	return int(SYMMETRIES.get(sym, 1))


## Image q of a point in map fractions.
func _img(p: Vector2, q: int) -> Vector2:
	match sym:
		"mirror_x":
			return Vector2(1.0 - p.x, p.y) if q == 1 else p
		"rot180":
			return Vector2(1.0 - p.x, 1.0 - p.y) if q == 1 else p
		"mirror4":
			return Vector2(1.0 - p.x if q & 1 else p.x, 1.0 - p.y if q & 2 else p.y)
	return p


## Image q of a cell.
func _img_cell(c: Vector2i, q: int) -> Vector2i:
	var f := _img(Vector2(c.x + 0.5, c.y + 0.5) / Vector2(W, H), q) * Vector2(W, H)
	return Vector2i(int(floor(f.x)), int(floor(f.y)))


## Image q of a yaw (radians, the 3D view turns props about the up axis).
func _img_yaw(a: float, q: int) -> float:
	var fx := (sym == "mirror_x" and q == 1) or (sym == "mirror4" and q & 1)
	var fy := sym == "mirror4" and q & 2
	if sym == "rot180" and q == 1:
		return a + PI
	if fx and fy:
		return a + PI
	if fx:
		return PI - a
	if fy:
		return -a
	return a


## The player whose side image q is (-1: nobody).
func _owner_of(q: int) -> int:
	var o := q
	if sym == "mirror4":
		o = OWNER_OF_QUARTER[q]
	return o if o < factions.size() else -1


func _cells(p: Vector2) -> Vector2:
	return p * Vector2(W, H)


# --- Build -------------------------------------------------------------------------

func _build(id: String) -> void:
	tid = id
	if t.is_empty():
		t = data()["templates"][id]
	sym = String(t.get("symmetry", "none"))
	W = int(t["size"][0])
	H = int(t["size"][1])
	noise.seed = r.next_int(1, 1 << 30)
	noise.frequency = 0.08
	kinds.resize(W * H)
	keep.resize(W * H)
	keep.fill(0)
	corridor.resize(W * H)
	corridor.fill(0)
	var feats: Dictionary = t.get("features", {})
	kinds.fill(NavGrid.Kind.WATER if feats.get("sea", false) else NavGrid.Kind.GROUND)
	_base_biome = String(t.get("base", Biomes.data()["base"]))
	_pick_wild()
	_make_nodes()
	_features(feats)
	for n in nodes:
		var c := float(n["clear"])
		_clear_disc(n["pos"], c, true, c * 0.8 if n["kind"] == "zone" else 0.0)
	_links()
	_scatter()
	_set_pieces()
	_dressing()
	_cliffs()
	_connect()
	_to_world()


func _pick_wild() -> void:
	var used := {}
	for f: String in factions:
		used[Biomes.for_faction(f)] = true
	var pool: Array = []
	for b: String in Biomes.data()["biomes"]:
		if b != _base_biome and not used.has(b):
			pool.append(b)
	pool.sort()
	for i in range(pool.size() - 1, 0, -1):
		var j := r.next_int(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	# Lava wilds turn every river and sea of the region into lava: striking, so kept rare,
	# and never on maps built around water (seas, rivers, lakes) unless the base is ash.
	var f: Dictionary = t.get("features", {})
	var watery: bool = f.get("sea", false) or not (f.get("rivers", []) as Array).is_empty() \
		or not (f.get("lakes", []) as Array).is_empty()
	for k in mini(2, pool.size()):
		if pool[k] == "ashland" and pool.size() > (1 if watery else 2) and (watery or r.chance(0.65)):
			pool.remove_at(k)
			pool.append("ashland")
	var room := 4 - used.keys().filter(func(b: String) -> bool: return b != _base_biome).size()
	_wild = [_base_biome, _base_biome]
	if room >= 1 and pool.size() >= 1:
		_wild = [pool[0], pool[0]]
	if room >= 2 and pool.size() >= 2:
		_wild[1] = pool[1]


func _biome_for(name: String, owner: int) -> String:
	match name:
		"home":
			return Biomes.for_faction(factions[owner]) if owner >= 0 else _base_biome
		"wild":
			return _wild[0]
		"wild2":
			return _wild[1]
		"", "base":
			return _base_biome
	return name if Biomes.data()["biomes"].has(name) else _base_biome


func _make_nodes() -> void:
	var defs: Array = []
	for z: Dictionary in t.get("zones", []):
		defs.append(["zone", z])
	for s: Dictionary in t.get("sites", []):
		defs.append(["site", s])
	for d in defs:
		var def: Dictionary = d[1]
		var jit := (0.006 if def.get("home", false) else 0.02) * float(t.get("jitter", 1.0))
		var raw := Vector2(float(def["at"][0]), float(def["at"][1]))
		var j := Vector2(r.next_float_range(-jit, jit), r.next_float_range(-jit, jit) * 1.2)
		# On a mirror line the jitter must be its own image, or the copies drift apart.
		for q in range(1, _images()):
			if _img(raw, q).distance_to(raw) < 0.01:
				j = (j + (_img(raw + j, q) - _img(raw, q))) * 0.5
		var at := raw + j
		var size := "waystone"
		if d[0] == "zone":
			var sz: Variant = def["size"]
			size = String(sz[r.next_int(0, (sz as Array).size() - 1)]) if sz is Array else String(sz)
		# Some places stand on a plateau: a cliff ring (rock in the sim) broken by ramps
		# where the roads come in. In 3D the ground rises there.
		var lift := 0.0
		var want: Variant = def.get("plateau", null)
		if d[0] == "zone" and not def.get("home", false):
			if (want == null and r.chance(0.5 if def.get("rich", false) else 0.35)) or want == true:
				lift = r.next_float_range(4.0, 5.5)
		elif d[0] == "site" and int(def.get("tier", 0)) >= 2 and want != false:
			if want == true or r.chance(0.4):
				lift = r.next_float_range(3.0, 4.2)
		var set_name := ""
		if d[0] == "site":
			set_name = String(def.get("set", ""))
			if set_name == "":
				set_name = _pick(LAIR_SETS[int(def.get("tier", 1))] if def["kind"] == "lair" else SITE_SETS[def["kind"]])
		for q in _images():
			var p := _img(at, q)
			var hit := -1
			for i in nodes.size():
				if nodes[i]["id"] == def["id"] and (nodes[i]["pos"] as Vector2).distance_to(_cells(p)) < 1.0:
					hit = i
			if hit >= 0:
				_by_ref["%s#%d" % [def["id"], q]] = hit
				nodes[hit]["axis"] = true
				continue
			var owner := _owner_of(q)
			var n := {"id": def["id"], "kind": d[0], "def": def, "pos": _cells(p), "img": q, "owner": owner,
				"size": size, "home": d[0] == "zone" and bool(def.get("home", false)), "axis": false, "set": set_name,
				"plateau": lift}
			if def.has("owner"):
				n["owner"] = int(def["owner"])
			if n["home"] and not def.has("owner"):
				n["size"] = "town"
			if d[0] == "zone":
				n["clear"] = HOME_CLEAR if n["home"] else (WAYSTONE_CLEAR if size == "waystone" else ZONE_CLEAR)
			else:
				n["clear"] = float(SET_PIECES[set_name]["clear"])
			_by_ref["%s#%d" % [def["id"], q]] = nodes.size()
			nodes.append(n)
	# Biomes after the axis flags are known: a zone on the mirror line belongs to nobody.
	for n in nodes:
		var owner: int = -1 if n["axis"] else int(n["owner"])
		n["side"] = owner
		var bname := String(n["def"].get("biome", "home" if n["home"] else "base"))
		n["biome"] = _biome_for(bname, owner)


func _pick(arr: Array) -> Variant:
	return arr[r.next_int(0, arr.size() - 1)]


func _node(ref: String, q: int) -> int:
	var id := ref
	var base_q := 0
	if "#" in ref:
		id = ref.split("#")[0]
		base_q = int(ref.split("#")[1])
	var key := "%s#%d" % [id, base_q ^ q]
	return int(_by_ref.get(key, _by_ref.get("%s#0" % id, -1)))


# --- Grid helpers --------------------------------------------------------------------

func _in(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func _k(c: Vector2i) -> int:
	return kinds[c.y * W + c.x]


func _set_kind(c: Vector2i, kind: int) -> void:
	if _in(c):
		kinds[c.y * W + c.x] = kind


## Open ground around a centre. Rock and woods give way within rad, water only within
## wet_rad (so a site on an island does not drain the lake around it).
func _clear_disc(centre: Vector2, rad: float, mark: bool, wet_rad: float = -1.0) -> void:
	if wet_rad < 0.0:
		wet_rad = rad
	for y in range(int(centre.y - rad - 2), int(centre.y + rad + 3)):
		for x in range(int(centre.x - rad - 2), int(centre.x + rad + 3)):
			var c := Vector2i(x, y)
			if not _in(c):
				continue
			var d := Vector2(x + 0.5, y + 0.5).distance_to(centre)
			var edge := rad + _nz(x, y, 1.7) * 1.5
			if d <= edge and (kinds[y * W + x] != NavGrid.Kind.WATER or d <= wet_rad):
				kinds[y * W + x] = NavGrid.Kind.GROUND
			if mark and d <= rad + 2.0:
				keep[y * W + x] = 1


## Disc of `kind` with a ragged edge (r in cells).
func _disc(centre: Vector2, rad: float, kind: int) -> void:
	for y in range(int(centre.y - rad * 1.4 - 2), int(centre.y + rad * 1.4 + 3)):
		for x in range(int(centre.x - rad * 1.4 - 2), int(centre.x + rad * 1.4 + 3)):
			var c := Vector2i(x, y)
			if not _in(c):
				continue
			var d := Vector2(x + 0.5, y + 0.5).distance_to(centre) / maxf(rad, 0.5)
			if d + _nz(x, y, 0.9) * 0.28 <= 1.0:
				kinds[y * W + x] = kind


## A line of `kind` along a polyline (cells), w cells wide with a wobbling edge.
func _line(pts: PackedVector2Array, w: float, kind: int) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var pad := w + 3.0
	for y in range(maxi(0, int(lo.y - pad)), mini(H, int(hi.y + pad) + 1)):
		for x in range(maxi(0, int(lo.x - pad)), mini(W, int(hi.x + pad) + 1)):
			var p := Vector2(x + 0.5, y + 0.5)
			var d := _poly_dist(pts, p)
			if d <= w * 0.5 * (1.0 + _nz(x, y, 0.6) * 0.35):
				kinds[y * W + x] = kind


## Noise that follows the map's symmetry: every image of a cell reads the same value,
## so ragged edges are mirrored too.
func _nz(x: int, y: int, f: float) -> float:
	var cx := x
	var cy := y
	match sym:
		"mirror_x":
			cx = mini(x, W - 1 - x)
		"rot180":
			if x * 2 + 1 > W or (x * 2 + 1 == W and y * 2 + 1 > H):
				cx = W - 1 - x
				cy = H - 1 - y
		"mirror4":
			cx = mini(x, W - 1 - x)
			cy = mini(y, H - 1 - y)
	return noise.get_noise_2d(cx * f, cy * f)


func _poly_dist(pts: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in pts.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
	return best


func _features(f: Dictionary) -> void:
	for spec in [["land", NavGrid.Kind.GROUND], ["lakes", NavGrid.Kind.WATER], ["woods", NavGrid.Kind.FOREST]]:
		for d: Dictionary in f.get(spec[0], []):
			var at := Vector2(float(d["at"][0]), float(d["at"][1]))
			var seen: Array = []
			for q in (1 if d.get("whole", false) else _images()):
				var c := _cells(_img(at, q))
				if seen.any(func(s: Vector2) -> bool: return s.distance_to(c) < 1.0):
					continue
				seen.append(c)
				_disc(c, float(d["r"]) * H, spec[1])
	for spec in [["rivers", NavGrid.Kind.WATER], ["ridges", NavGrid.Kind.ROCK]]:
		for d: Dictionary in f.get(spec[0], []):
			# Every image, even for a "whole" line: a line across the mirror is drawn with
			# its own image, so its bends stay symmetric (drawing it twice is harmless).
			for q in _images():
				var pts := PackedVector2Array()
				for p in d["pts"]:
					pts.append(_cells(_img(Vector2(float(p[0]), float(p[1])), q)))
				_line(pts, float(d.get("w", 6)), spec[1])
	# Islands last, so they stand in the lakes and rivers drawn before them.
	for d: Dictionary in f.get("isles", []):
		var at := Vector2(float(d["at"][0]), float(d["at"][1]))
		var seen: Array = []
		for q in (1 if d.get("whole", false) else _images()):
			var c := _cells(_img(at, q))
			if seen.any(func(s: Vector2) -> bool: return s.distance_to(c) < 1.0):
				continue
			seen.append(c)
			_disc(c, float(d["r"]) * H, NavGrid.Kind.GROUND)


# --- Links ---------------------------------------------------------------------------

func _links() -> void:
	var done := {}
	for l: Array in t.get("links", []):
		var kind := String(l[2])
		var bend := 0.0
		if kind in ["road", "trail"] and not "#" in String(l[0]) and not "#" in String(l[1]):
			bend = r.next_float_range(-0.07, 0.07)
		for q in _images():
			var a := _node(String(l[0]), q)
			var b := _node(String(l[1]), q)
			if a < 0 or b < 0 or a == b:
				continue
			var key := "%d-%d" % [mini(a, b), maxi(a, b)]
			if done.has(key):
				continue
			done[key] = true
			var pa: Vector2 = nodes[a]["pos"]
			var pb: Vector2 = nodes[b]["pos"]
			# The bend is drawn in image 0 and mirrored, so both sides get the same road.
			var mid := (pa + pb) * 0.5
			if bend != 0.0:
				var a0 := _node(String(l[0]), 0)
				var b0 := _node(String(l[1]), 0)
				var p0: Vector2 = nodes[a0]["pos"]
				var p1: Vector2 = nodes[b0]["pos"]
				var m0 := (p0 + p1) * 0.5 + (p1 - p0).orthogonal() * bend
				mid = _cells(_img(m0 / Vector2(W, H), q))
			_carve(PackedVector2Array([pa, mid, pb]), kind)


## Opens a corridor along pts. Water on the way becomes a bridge (or a ford, or land);
## rock becomes a pass. Records bridges and painted roads for the view.
func _carve(pts: PackedVector2Array, kind: String) -> void:
	var w: float = LINK_WIDTH.get(kind, 3.0)
	# Water runs along the line, from the terrain as it was, for the bridges.
	if kind != "land" and kind != "ford":
		var runs: Array = []
		var start := Vector2.INF
		var prev := pts[0]
		for i in pts.size() - 1:
			var seg_len := pts[i].distance_to(pts[i + 1])
			var steps := maxi(1, int(seg_len * 2.0))
			for s in steps + 1:
				var p := pts[i].lerp(pts[i + 1], float(s) / steps)
				var c := Vector2i(int(floor(p.x)), int(floor(p.y)))
				var wet := _in(c) and _k(c) == NavGrid.Kind.WATER
				if wet and start == Vector2.INF:
					start = prev
				elif not wet and start != Vector2.INF:
					runs.append([start, p])
					start = Vector2.INF
				prev = p
		if start != Vector2.INF:
			runs.append([start, pts[pts.size() - 1]])
		for run in runs:
			var a: Vector2 = run[0]
			var b: Vector2 = run[1]
			var dir := (b - a).normalized()
			bridges_px.append([(a - dir * 1.2) * NavGrid.CELL, (b + dir * 1.2) * NavGrid.CELL, (w + 0.6) * NavGrid.CELL])
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	for y in range(maxi(0, int(lo.y - w - 3)), mini(H, int(hi.y + w + 3) + 1)):
		for x in range(maxi(0, int(lo.x - w - 3)), mini(W, int(hi.x + w + 3) + 1)):
			var d := _poly_dist(pts, Vector2(x + 0.5, y + 0.5))
			var i := y * W + x
			if d <= w * 0.5:
				kinds[i] = NavGrid.Kind.GROUND
				corridor[i] = 1
			if d <= w * 0.5 + 2.5:
				keep[i] = 1
	if kind in PAINTED:
		for i in pts.size() - 1:
			roads_px.append([pts[i] * NavGrid.CELL, pts[i + 1] * NavGrid.CELL])


# --- Scatter -------------------------------------------------------------------------

## Random woods, rock outcrops and ponds, copied to every image; never on corridors,
## centres or sites, and only where every image is open ground.
func _scatter() -> void:
	var sc: Dictionary = t.get("scatter", {})
	var plan := [["peaks", NavGrid.Kind.ROCK], ["woods", NavGrid.Kind.FOREST], ["rocks", NavGrid.Kind.ROCK],
		["ponds", NavGrid.Kind.WATER]]
	for spec in plan:
		var want := int(sc.get(spec[0], 0))
		# Mountains rather than ponds: impassable peaks read better than scattered pools.
		if spec[0] == "peaks" and not sc.has("peaks"):
			want = 2 + int(sc.get("ponds", 0))
		elif spec[0] == "ponds":
			want = mini(want, 1)
		var placed := 0
		for attempt in want * 6:
			if placed >= want:
				break
			var c := Vector2i(r.next_int(3, W - 4), r.next_int(3, H - 4))
			var cells: Array = []
			match spec[0]:
				"woods":
					var rad := r.next_float_range(2.5, 5.5)
					for dy in range(-7, 8):
						for dx in range(-7, 8):
							if Vector2(dx, dy * 1.2).length() <= rad + r.next_float() * 1.4:
								cells.append(c + Vector2i(dx, dy))
				"peaks":
					var rad := r.next_float_range(4.0, 7.5)
					var stretch := r.next_float_range(0.7, 1.4)
					for dy in range(-10, 11):
						for dx in range(-10, 11):
							var wob := _nz(c.x + dx, c.y + dy, 0.35) * 2.2
							if Vector2(dx * stretch, dy / stretch).length() <= rad + wob:
								cells.append(c + Vector2i(dx, dy))
				"rocks":
					var size := r.next_int(1, 3)
					for dy in range(-size, size + 1):
						for dx in range(-size - 1, size + 2):
							if Vector2(dx, dy).length() <= size + 0.5 + r.next_float() * 0.6:
								cells.append(c + Vector2i(dx, dy))
				"ponds":
					for dy in range(-3, 4):
						for dx in range(-4, 5):
							if Vector2(dx * 0.8, dy).length() <= 2.6 + r.next_float() * 0.8:
								cells.append(c + Vector2i(dx, dy))
			var all: Array = []
			var ok := true
			for q in _images():
				for cell: Vector2i in cells:
					var m := _img_cell(cell, q)
					if not _in(m) or keep[m.y * W + m.x] == 1 or _k(m) != NavGrid.Kind.GROUND:
						ok = false
						break
					all.append(m)
				if not ok:
					break
			if not ok:
				continue
			placed += 1
			for m: Vector2i in all:
				_set_kind(m, spec[1])


# --- Set pieces ----------------------------------------------------------------------

func _set_pieces() -> void:
	# Sites: the set piece faces the nearest zone (the way visitors come from).
	var done := {}
	for i in nodes.size():
		var n: Dictionary = nodes[i]
		if n["kind"] != "site" or done.has(n["id"]):
			continue
		done[n["id"]] = true
		var face := _facing(n)
		var parts := _layout(String(n["set"]))
		for j in nodes.size():
			if nodes[j]["id"] == n["id"]:
				_place_parts(parts, nodes[j]["pos"], face, int(nodes[j]["img"]), int(n["img"]))
	# Flavour: about half the ordinary zones get a small ruin off to one side.
	var seen := {}
	for n in nodes:
		if n["kind"] != "zone" or n["home"] or seen.has(n["id"]) or not r.chance(0.85):
			continue
		seen[n["id"]] = true
		var parts := _layout(String(_pick(FLAVOUR)))
		var clear := 6.0
		for attempt in 12:
			var a := r.next_float() * TAU
			var d := float(n["clear"]) + r.next_float_range(3.0, 8.0)
			var off := Vector2(cos(a), sin(a)) * d
			var ok := true
			for m in nodes:
				if m["id"] == n["id"]:
					var p := (m["pos"] as Vector2) + _img_vec(off, int(m["img"]) ^ int(n["img"]))
					if not _free_disc(p, clear):
						ok = false
			if not ok:
				continue
			for m in nodes:
				if m["id"] == n["id"]:
					var q := int(m["img"]) ^ int(n["img"])
					_place_parts(parts, (m["pos"] as Vector2) + _img_vec(off, q), -off.normalized(), int(m["img"]), int(n["img"]))
			break


## Ruins in the open: small set pieces on free ground away from settlements and sites,
## the same in every image, so the land between places is never bare.
func _dressing() -> void:
	var want := int(t.get("scatter", {}).get("ruins", 6 if _images() == 2 else 4))
	var placed := 0
	for attempt in want * 12:
		if placed >= want:
			break
		var c := Vector2(r.next_int(6, W - 7), r.next_int(6, H - 7))
		var far := true
		for n in nodes:
			if c.distance_to(n["pos"]) < float(n["clear"]) + 6.0:
				far = false
				break
		if not far:
			continue
		var ok := true
		for q in _images():
			if not _free_disc(_img(c / Vector2(W, H), q) * Vector2(W, H), 5.0):
				ok = false
				break
		if not ok:
			continue
		var parts := _layout(String(_pick(FLAVOUR)))
		var face := Vector2.from_angle(r.next_float() * TAU)
		for q in _images():
			_place_parts(parts, _img(c / Vector2(W, H), q) * Vector2(W, H), face, q, 0)
		placed += 1


## Plateau rims: a ring of rock (a cliff in 3D) around every raised place, left open
## where a road or trail comes in (the ramps) and never on set pieces or other places.
func _cliffs() -> void:
	for n in nodes:
		# Islands and shores stay low: bridges and fords land at the water's level.
		if float(n.get("plateau", 0.0)) > 0.0 and _wet_share(n["pos"], plateau_rim(n) + 5.0) > 0.04:
			n["plateau"] = 0.0
	# Every map gets high ground: failing that, the driest open zone rises (in every image).
	if not nodes.any(func(n: Dictionary) -> bool: return float(n["plateau"]) > 0.0):
		var best := -1
		var best_wet := 0.04
		for i in nodes.size():
			var n: Dictionary = nodes[i]
			if n["kind"] == "zone" and not n["home"] and n["def"].get("plateau", null) != false:
				var wet := _wet_share(n["pos"], plateau_rim(n) + 5.0)
				if wet <= best_wet:
					best = i
					best_wet = wet - 0.0001
		if best >= 0:
			var lift := r.next_float_range(4.0, 5.5)
			for m in nodes:
				if m["id"] == nodes[best]["id"]:
					m["plateau"] = lift
	for n in nodes:
		var lift := float(n.get("plateau", 0.0))
		if lift <= 0.0:
			continue
		var c: Vector2 = n["pos"]
		var rim := plateau_rim(n)
		for y in range(int(c.y - rim - 3), int(c.y + rim + 4)):
			for x in range(int(c.x - rim - 3), int(c.x + rim + 4)):
				var cell := Vector2i(x, y)
				if not _in(cell) or _k(cell) != NavGrid.Kind.GROUND:
					continue
				var d := Vector2(x + 0.5, y + 0.5).distance_to(c) + _nz(x, y, 0.35) * 2.2 + _nz(x, y, 1.1) * 0.5
				if d < rim or d > rim + CLIFF_BAND:
					continue
				if _near_corridor(cell, 2) or _near_other_node(Vector2(x + 0.5, y + 0.5), n):
					continue
				kinds[y * W + x] = NavGrid.Kind.ROCK


## The inner radius (cells) of a node's plateau rim.
static func plateau_rim(n: Dictionary) -> float:
	return float(n["clear"]) * 0.8


func _near_corridor(c: Vector2i, rad: int) -> bool:
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var o := c + Vector2i(dx, dy)
			if _in(o) and corridor[o.y * W + o.x] == 1:
				return true
	return false


func _near_other_node(p: Vector2, own: Dictionary) -> bool:
	for m in nodes:
		if m != own and p.distance_to(m["pos"]) < float(m["clear"]) * 0.7 + 1.5:
			return true
	for pr: Array in props:
		if p.distance_to((pr[1] as Vector2) / NavGrid.CELL) < 2.5:
			return true
	return false


func _img_vec(v: Vector2, q: int) -> Vector2:
	return _img(v / Vector2(W, H) + Vector2(0.5, 0.5), q) * Vector2(W, H) - Vector2(W, H) * 0.5


func _free_disc(p: Vector2, rad: float) -> bool:
	for y in range(int(p.y - rad), int(p.y + rad) + 1):
		for x in range(int(p.x - rad), int(p.x + rad) + 1):
			var c := Vector2i(x, y)
			if not _in(c):
				return false
			if Vector2(x + 0.5, y + 0.5).distance_to(p) <= rad and (keep[y * W + x] == 1 or _k(c) != NavGrid.Kind.GROUND):
				return false
	return true


## Which way a site faces (toward the nearest zone), in image 0 of that site.
func _facing(site: Dictionary) -> Vector2:
	var best := Vector2(W, H) * 0.5
	var bd := INF
	for n in nodes:
		if n["kind"] == "zone":
			var d := (n["pos"] as Vector2).distance_to(site["pos"])
			if d < bd:
				bd = d
				best = n["pos"]
	var f := best - (site["pos"] as Vector2)
	return f.normalized() if f.length() > 0.1 else Vector2(0, 1)


## A set piece's parts with a little random jitter (the same for every image).
func _layout(name: String) -> Array:
	var out: Array = []
	for p: Array in SET_PIECES[name]["parts"]:
		var jit := 0.25 if float(p[5]) == 0.0 else 0.0
		out.append([p[0], Vector2(float(p[1]) + r.next_float_range(-jit, jit), float(p[2]) + r.next_float_range(-jit, jit)),
			deg_to_rad(float(p[3]) + r.next_float_range(-8.0, 8.0)), float(p[4]) * r.next_float_range(0.93, 1.07), float(p[5])])
	return out


## Places parts around a centre (cells). face: the piece's front direction in image `src_img`;
## the parts are laid out there and mirrored into image `img`.
func _place_parts(parts: Array, centre: Vector2, face: Vector2, img: int, src_img: int) -> void:
	var q := img ^ src_img
	# Local frame: +y is the front. Rotate so +y points along face (in the source image),
	# then mirror the offset into this image.
	var ang := atan2(face.y, face.x) - PI * 0.5
	for p in parts:
		var off: Vector2 = (p[1] as Vector2).rotated(ang)
		var block: float = p[4]
		var pos := centre + _img_vec(off, q)
		# On a small island, pull a big piece in toward the centre until its footprint is dry.
		for tries in 5:
			if block < 2.0 or _wet_share(pos, block) < 0.1:
				break
			off *= 0.75
			pos = centre + _img_vec(off, q)
		var yaw := _img_yaw(-(ang + float(p[2])), q)
		var under := Vector2i(int(floor(pos.x)), int(floor(pos.y)))
		if not _in(under) or _k(under) == NavGrid.Kind.WATER:
			continue  # never stand a piece in the water
		if block > 0.0:
			for y in range(int(pos.y - block - 1), int(pos.y + block + 2)):
				for x in range(int(pos.x - block - 1), int(pos.x + block + 2)):
					var c := Vector2i(x, y)
					if _in(c) and Vector2(x + 0.5, y + 0.5).distance_to(pos) <= block and _k(c) == NavGrid.Kind.GROUND \
							and corridor[y * W + x] == 0:
						_set_kind(c, NavGrid.Kind.BUILDING)
		for y in range(int(pos.y - 3), int(pos.y + 4)):
			for x in range(int(pos.x - 3), int(pos.x + 4)):
				if _in(Vector2i(x, y)):
					keep[y * W + x] = 1
		props.append([p[0], pos * NavGrid.CELL, yaw, p[3], block * NavGrid.CELL])


## Share of the cells within rad of pos that are water.
func _wet_share(pos: Vector2, rad: float) -> float:
	var wet := 0
	var all := 0
	for y in range(int(pos.y - rad), int(pos.y + rad) + 1):
		for x in range(int(pos.x - rad), int(pos.x + rad) + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(pos) <= rad:
				all += 1
				if not _in(Vector2i(x, y)) or _k(Vector2i(x, y)) == NavGrid.Kind.WATER:
					wet += 1
	return float(wet) / float(maxi(all, 1))


# --- Reachability --------------------------------------------------------------------

func _walkable(c: Vector2i) -> bool:
	return _in(c) and _k(c) == NavGrid.Kind.GROUND


## Cells reachable on foot from c (4-neighbour flood fill).
func _flood(from: Vector2i) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(W * H)
	seen.fill(0)
	if not _walkable(from):
		return seen
	var stack: Array[Vector2i] = [from]
	seen[from.y * W + from.x] = 1
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if _walkable(n) and seen[n.y * W + n.x] == 0:
				seen[n.y * W + n.x] = 1
				stack.append(n)
	return seen


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x), 0, W - 1), clampi(int(p.y), 0, H - 1))


## Every zone and site reachable from the first home: an unreachable one gets a trail
## (a bridge over water) to the nearest reachable one, in every image.
func _connect() -> void:
	var home := -1
	for i in nodes.size():
		if nodes[i]["home"] and home < 0:
			home = i
	if home < 0:
		home = 0
	for round_i in 8:
		var seen := _flood(_cell(nodes[home]["pos"]))
		var lost := -1
		for i in nodes.size():
			var c := _cell(nodes[i]["pos"])
			if seen[c.y * W + c.x] == 0:
				lost = i
				break
		if lost < 0:
			return
		var from: Vector2 = nodes[lost]["pos"]
		var best := Vector2.INF
		for n in nodes:
			var c := _cell(n["pos"])
			if seen[c.y * W + c.x] == 1 and (best == Vector2.INF or from.distance_to(n["pos"]) < from.distance_to(best)):
				best = n["pos"]
		if best == Vector2.INF:
			return
		for q in _images():
			var a := _img_vec(from - Vector2(W, H) * 0.5, q) + Vector2(W, H) * 0.5
			var b := _img_vec(best - Vector2(W, H) * 0.5, q) + Vector2(W, H) * 0.5
			_carve(PackedVector2Array([a, b]), "trail")


# --- Into the world ------------------------------------------------------------------

func _to_world() -> void:
	var rocks: Array = []
	var water: Array = []
	var forest: Array = []
	var built: Array = []
	for y in H:
		for x in W:
			match kinds[y * W + x]:
				NavGrid.Kind.ROCK:
					rocks.append(Vector2i(x, y))
				NavGrid.Kind.WATER:
					water.append(Vector2i(x, y))
				NavGrid.Kind.FOREST:
					forest.append(Vector2i(x, y))
				NavGrid.Kind.BUILDING:
					built.append(Vector2i(x, y))
	world.setup_map(W, H, rocks, water, forest)
	for c: Vector2i in built:
		world.nav.set_blocked(c, true, NavGrid.Kind.BUILDING)
	var eco := world.economy
	var sector_of := {}
	for i in nodes.size():
		var n: Dictionary = nodes[i]
		if n["kind"] == "zone":
			var size: String = n["size"]
			if n["home"] and int(n["owner"]) < 0:
				size = "town"  # an empty corner on a 3-player map: a neutral town
			sector_of[i] = eco.add_sector((n["pos"] as Vector2) * NavGrid.CELL, size)
			sector_of[i].label = String(n["def"].get("name", ""))
			if n["def"].has("owner") and not n["home"]:
				sector_of[i].owner = int(n["def"]["owner"])
	for o in factions.size():
		eco.add_player(o, factions[o])
	_resources(sector_of)
	for i in sector_of:
		var n: Dictionary = nodes[i]
		if n["home"] and int(n["owner"]) >= 0:
			eco.setup_home(int(n["owner"]), sector_of[i])
	var garrisons := {}
	if eco.settlements_active:
		if plain_militia:
			eco.spawn_militia()
		else:
			garrisons = _garrisons(sector_of)
	var lairs: Array = []
	var shrines: Array = []
	var merchants: Array = []
	_sites(lairs, shrines, merchants)
	var regions: Array = []
	var plateaus: Array = []
	for n in nodes:
		if n["kind"] == "zone":
			regions.append([(n["pos"] as Vector2) * NavGrid.CELL, n["biome"]])
		if float(n.get("plateau", 0.0)) > 0.0:
			plateaus.append([(n["pos"] as Vector2) * NavGrid.CELL, plateau_rim(n) * NavGrid.CELL, n["plateau"],
				CLIFF_BAND * NavGrid.CELL])
	var bridges: Array = []
	for b: Array in bridges_px:
		if not bridges.any(func(o: Array) -> bool: return (o[0] as Vector2).distance_to(b[0]) < 40.0 and (o[1] as Vector2).distance_to(b[1]) < 40.0):
			bridges.append(b)
	bridges_px = bridges
	var refs := {}
	for i in nodes.size():
		var n: Dictionary = nodes[i]
		if not refs.has(n["id"]):
			refs[n["id"]] = {"kind": n["kind"], "pos": (n["pos"] as Vector2) * NavGrid.CELL}
			if sector_of.has(i):
				refs[n["id"]]["sector"] = (sector_of[i] as Sector).id
			if site_ids.has(i):
				refs[n["id"]]["site"] = site_ids[i]
	world.map_info = {"template": tid, "name": String(t.get("name", template_name(tid))), "refs": refs, "roads": roads_px, "bridges": bridges_px,
		"props": props, "regions": regions, "base_biome": _base_biome, "border": String(t.get("border", "mountains")),
		"lairs": lairs, "shrines": shrines, "merchants": merchants, "plateaus": plateaus, "garrisons": garrisons}


# --- Garrisons -----------------------------------------------------------------------

## What one unit adds to a fight, for scaling garrisons: sqrt(effective hit points x damage
## a second), ranged units x1.3 (they strike first and from behind the line).
static func unit_worth(def: Dictionary) -> float:
	var ehp := float(def["hp"]) / maxf(0.05, 1.0 - float(def.get("armor_pct", 0.0)))
	var dps := float(def["damage"]) / maxf(0.1, float(def["attack_interval"]))
	return sqrt(ehp * dps) * (1.3 if float(def.get("range", 0.0)) > 50.0 else 1.0)


## The strength a settlement of this size is held with: its militia count in militia worth.
static func garrison_budget(size: String) -> float:
	var cat := UnitCatalog.get_default()
	return float(cat.economy["settlements"][size]["militia"]) * unit_worth(cat.get_unit("militia"))


## A garrison group scaled to a budget: one count per entry of its "units" (same order), or
## [] when it does not fit (the leader would drop out, a mixed group would turn plain, too
## many bodies, or the total lands outside 80-125% of the budget).
static func garrison_fit(group: Dictionary, budget: float) -> Array:
	var cat := UnitCatalog.get_default()
	var comp: Array = group["units"]
	if budget <= 0.0 or comp.is_empty():
		return []
	var worth: Array = []
	var whole := 0.0
	for e: Array in comp:
		worth.append(unit_worth(cat.get_unit(String(e[0]))))
		whole += float(e[1]) * float(worth[-1])
	var k := budget / whole
	var counts: Array = []
	var total := 0.0
	for i in comp.size():
		counts.append(int(floor(float(comp[i][1]) * k)))
		total += int(counts[i]) * float(worth[i])
	# Round up the entries that lost the most, while the total stays near the budget.
	var order: Array = range(comp.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var fa := float(comp[a][1]) * k - int(counts[a])
		var fb := float(comp[b][1]) * k - int(counts[b])
		return fa > fb or (fa == fb and a < b))
	for i: int in order:
		if total + float(worth[i]) <= budget * 1.15:
			counts[i] = int(counts[i]) + 1
			total += float(worth[i])
	var kinds_left := counts.filter(func(c: int) -> bool: return c > 0).size()
	var bodies := 0
	for c: int in counts:
		bodies += c
	if int(counts[0]) == 0 or bodies > int(data()["garrisons"].get("max_units", 18)):
		return []
	if comp.size() >= 2 and kinds_left < 2:
		return []
	if total < budget * 0.8 or total > budget * 1.25:
		return []
	return counts


## The groups that may hold a settlement of this size in this biome, as [group, weight]
## pairs (a group of the biome itself counts twice; biome "" takes only the "any" groups).
static func garrison_options(size: String, biome: String) -> Array:
	var out: Array = []
	var budget := garrison_budget(size)
	for g: Dictionary in data()["garrisons"]["groups"]:
		var where: Array = g.get("biomes", ["any"])
		var w := 0.0
		if "any" in where:
			w = 1.0
		elif biome != "" and biome in where:
			w = 2.0
		if w <= 0.0 or garrison_fit(g, budget).is_empty():
			continue
		out.append([g, w * float(g.get("weight", 1.0))])
	return out


## One garrison per neutral settlement (not homes or waystones), from its own random stream
## so the terrain of a seed stays as it was. Copies of one zone get the same group; a zone
## whose copies stand in different biomes (a house's own land) takes only the "any" groups.
## Returns sector id -> {id, name, units: [[unit, count], ...]} for the view.
func _garrisons(sector_of: Dictionary) -> Dictionary:
	var eco := world.economy
	var gr := GameRng.new(GameRng.mix(noise.seed, 4411))
	var chosen := {}  ## zone id -> {id, name, units}
	var out := {}
	var ids: Array = sector_of.keys()
	ids.sort()
	for i: int in ids:
		var s: Sector = sector_of[i]
		var n: Dictionary = nodes[i]
		if s.owner != -1 or int(eco.e["settlements"][s.size]["militia"]) <= 0:
			continue
		if not chosen.has(n["id"]):
			var biome := String(n["biome"])
			for m in nodes:
				if m["id"] == n["id"] and String(m["biome"]) != biome:
					biome = ""
			var opts := garrison_options(s.size, biome)
			if opts.is_empty():
				chosen[n["id"]] = {"id": "militia", "name": "Militia",
					"units": [["militia", int(eco.e["settlements"][s.size]["militia"])]]}
			else:
				var g: Dictionary = opts[gr.weighted_index(opts.map(func(o: Array) -> float: return o[1]))][0]
				var counts := garrison_fit(g, garrison_budget(s.size))
				var units: Array = []
				for k in counts.size():
					if int(counts[k]) > 0:
						units.append([String(g["units"][k][0]), int(counts[k])])
				chosen[n["id"]] = {"id": String(g["id"]), "name": String(g["name"]), "units": units}
		var pick: Dictionary = chosen[n["id"]]
		var types: Array = []
		for e: Array in pick["units"]:
			for k in int(e[1]):
				types.append(String(e[0]))
		eco.spawn_garrison(s, types)
		out[s.id] = pick
	return out


## Resource piles around each zone. One pattern per zone of image 0, mirrored into the
## other images; "own" piles take the rares of the player whose side the image is.
func _resources(sector_of: Dictionary) -> void:
	var eco := world.economy
	if not eco.settlements_active:
		return  # a campaign hero map: nobody gathers
	var home_links := {}  ## zone id -> true when linked to a home (gets the sure rares)
	var home_ids := {}
	for z: Dictionary in t.get("zones", []):
		if z.get("home", false):
			home_ids[z["id"]] = true
	var near_home: Array = []
	for l: Array in t.get("links", []):
		for pair in [[l[0], l[1]], [l[1], l[0]]]:
			var a := String(pair[0]).split("#")[0]
			var b := String(pair[1]).split("#")[0]
			if home_ids.has(a) and not home_ids.has(b) and not near_home.has(b) and not "#" in String(pair[1]):
				near_home.append(b)
	for k in near_home.size():
		home_links[near_home[k]] = "gems" if k == 0 else ("own" if k == 1 else "")
	var done := {}
	for i in nodes.size():
		var n: Dictionary = nodes[i]
		if n["kind"] != "zone" or done.has(n["id"]) or int(n["def"].get("nodes", -1)) == 0:
			continue
		done[n["id"]] = true
		var st: Dictionary = eco.e["settlements"][n["size"] if not n["home"] else "town"]
		var kinds_list: Array = []
		if n["home"]:
			kinds_list = ["wood", "ore"]
		else:
			var cnt := r.next_int(int(st["nodes"][0]), int(st["nodes"][1]))
			if n["def"].get("rich", false):
				cnt += 2
			for j in cnt:
				var roll := r.next_float()
				if j == 0 or roll < 0.35:
					kinds_list.append("wood")
				elif j == 1 or roll < 0.6:
					kinds_list.append("ore")
				elif roll < 0.8:
					kinds_list.append("gems")
				else:
					kinds_list.append("own")
			var want: String = home_links.get(n["id"], "")
			if want != "" and not want in kinds_list and kinds_list.size() >= 2:
				kinds_list[kinds_list.size() - 1] = want
			if n["def"].get("rich", false):
				kinds_list[kinds_list.size() - 1] = "own"
				kinds_list[kinds_list.size() - 2] = "gems"
		var images: Array = []
		for j in nodes.size():
			if nodes[j]["id"] == n["id"]:
				images.append(j)
		var home_offs: Array[Vector2] = []
		for kind: String in kinds_list:
			var off := Vector2.ZERO
			var ok := false
			if n["home"]:
				off = _home_pile(n, images, home_offs)
				home_offs.append(off)
				ok = true
			for attempt in (0 if ok else 30):
				var a := r.next_float() * TAU
				var d := r.next_float_range(7.0, 13.0)
				off = Vector2(cos(a), sin(a) * 0.85) * d
				ok = true
				for j: int in images:
					var p: Vector2 = (nodes[j]["pos"] as Vector2) + _img_vec(off, int(nodes[j]["img"]) ^ int(n["img"]))
					var c := Vector2i(int(floor(p.x)), int(floor(p.y)))
					if not _walkable(c) or corridor[c.y * W + c.x] == 1 or c.x < 2 or c.y < 2 or c.x > W - 3 or c.y > H - 3:
						ok = false
				if ok:
					break
			for j: int in images:
				var m: Dictionary = nodes[j]
				var p: Vector2 = (m["pos"] as Vector2) + _img_vec(off, int(m["img"]) ^ int(n["img"]))
				var px := world.nav.nearest_free(p * NavGrid.CELL)
				if kind == "own":
					if m["axis"]:
						# A contested centre: one of every player's own rares.
						for o in factions.size():
							var rr := _own_rare(o)
							var spread := Vector2(cos(o * 2.4), sin(o * 2.4)) * 70.0
							eco.add_node(world.nav.nearest_free(px + spread), rr if rr != "" else "gems")
						continue
					var rare := _own_rare(int(m["side"]))
					eco.add_node(px, rare if rare != "" else "gems")
				else:
					eco.add_node(px, kind)


## Where a home's own timber or ore pile goes (offset in cells from the hall, image 0's
## frame): just outside the town's footprint (settlement_clearance), so it is close and in
## plain sight, never under the town model; off the sides where the starting dwelling
## stands, apart from the other home piles, off the roads, and in a straight walk from the
## hall on every mirrored copy. Falls back to the best spot found if nothing fits.
func _home_pile(n: Dictionary, images: Array, taken: Array[Vector2]) -> Vector2:
	var eco := world.economy
	var town := float(eco.e["settlement_clearance"]) / NavGrid.CELL
	var best := Vector2.ZERO
	var best_score := -INF
	for attempt in 80:
		var a := r.next_float() * TAU
		var d := town + r.next_float_range(HOME_PILE_GAP[0], HOME_PILE_GAP[1])
		var off := Vector2(cos(a), sin(a)) * d
		var score := 0.0
		if absf(sin(a)) < 0.55:
			score -= 4.0  # the starting dwelling stands beside the hall, left or right
		for o: Vector2 in taken:
			if absf(o.angle_to(off)) < 1.0:
				score -= 2.0
		for j: int in images:
			var m: Dictionary = nodes[j]
			var centre: Vector2 = m["pos"]
			var p: Vector2 = centre + _img_vec(off, int(m["img"]) ^ int(n["img"]))
			var c := Vector2i(int(floor(p.x)), int(floor(p.y)))
			if c.x < 2 or c.y < 2 or c.x > W - 3 or c.y > H - 3 or not _walkable(c):
				score -= 100.0
				continue
			if corridor[c.y * W + c.x] == 1:
				score -= 3.0
			if not world.nav.line_clear(centre * NavGrid.CELL, p * NavGrid.CELL):
				score -= 10.0
		if score > best_score:
			best_score = score
			best = off
			if score >= 0.0:
				break
	return best


## The first rare a player's workers gather that is not wood, ore or gems ("" if none).
func _own_rare(owner: int) -> String:
	if owner < 0 or owner >= factions.size():
		return ""
	for x: String in world.catalog.faction_resources(factions[owner]):
		if x != "wood" and x != "ore" and x != "gems":
			return x
	return ""


## Lairs (wild guards over loot), shrines and merchants. The sites module (world.sites,
## when there is one) runs them; without it the guards are spawned here on hold.
func _sites(lairs: Array, shrines: Array, merchants: Array) -> void:
	var guards: Dictionary = data()["lair_guards"]
	var picked := {}
	for i in nodes.size():
		var n: Dictionary = nodes[i]
		if n["kind"] != "site":
			continue
		var def: Dictionary = n["def"]
		var p: Vector2 = world.nav.nearest_free((n["pos"] as Vector2) * NavGrid.CELL)
		match String(def["kind"]):
			"lair":
				var tier := clampi(int(def.get("tier", 1)), 1, 3)
				if def.has("guards"):
					picked[n["id"]] = def["guards"]
				if not picked.has(n["id"]):
					var opts: Array = []
					var tg: Dictionary = guards[str(tier)]
					opts.append_array(tg.get("any", []))
					opts.append_array(tg.get(_biome_near(n["pos"]), []))
					opts.append_array(tg.get(_biome_near(n["pos"]), []))  # the local beasts twice as likely
					picked[n["id"]] = _pick(opts)
				var types: Array = []
				for g: Array in picked[n["id"]]:
					for k in int(g[1]):
						types.append(String(g[0]))
				lairs.append([p, tier])
				site_ids[i] = world.sites.add_lair(p, tier, types, int(n["def"].get("keeper", -1)))["id"]
			"shrine":
				shrines.append(p)
				site_ids[i] = world.sites.add_shrine(p)["id"]
			"merchant":
				merchants.append(p)
				site_ids[i] = world.sites.add_merchant(p)["id"]


func _biome_near(p: Vector2) -> String:
	var best := _base_biome
	var bd := INF
	for n in nodes:
		if n["kind"] == "zone" and (n["pos"] as Vector2).distance_to(p) < bd:
			bd = (n["pos"] as Vector2).distance_to(p)
			best = n["biome"]
	return best


# --- Validation ----------------------------------------------------------------------

static func validate() -> Array[String]:
	var errors: Array[String] = []
	var d := data()
	var units: Dictionary = UnitCatalog.get_default().units
	var biomes: Dictionary = Biomes.data()["biomes"]
	var sizes: Dictionary = UnitCatalog.get_default().economy["settlements"]
	for id: String in d.get("templates", {}):
		var tp: Dictionary = d["templates"][id]
		var where := "map %s: " % id
		if not SYMMETRIES.has(String(tp.get("symmetry", "none"))):
			errors.append(where + "unknown symmetry")
		if (tp.get("size", []) as Array).size() != 2 or int(tp["size"][0]) < 64 or int(tp["size"][1]) < 48:
			errors.append(where + "size must be [w, h], at least 64 x 48")
		if not biomes.has(String(tp.get("base", "meadow"))):
			errors.append(where + "unknown base biome")
		var ids := {}
		var homes := 0
		for z: Dictionary in tp.get("zones", []):
			ids[z["id"]] = true
			if z.get("home", false):
				homes += 1
			for s in (z["size"] if z["size"] is Array else [z["size"]]):
				if not sizes.has(s):
					errors.append(where + "zone %s: unknown settlement %s" % [z["id"], s])
			var b := String(z.get("biome", "base"))
			if not b in ["home", "base", "wild", "wild2"] and not biomes.has(b):
				errors.append(where + "zone %s: unknown biome %s" % [z["id"], b])
		if homes != 1:
			errors.append(where + "needs exactly one home zone (the others are its images)")
		for s: Dictionary in tp.get("sites", []):
			ids[s["id"]] = true
			if not s.get("kind", "") in SITE_KINDS:
				errors.append(where + "site %s: unknown kind" % s["id"])
			if s.has("set") and not SET_PIECES.has(s["set"]):
				errors.append(where + "site %s: unknown set piece %s" % [s["id"], s["set"]])
		for l: Array in tp.get("links", []):
			for e in [l[0], l[1]]:
				if not ids.has(String(e).split("#")[0]):
					errors.append(where + "link to unknown %s" % e)
			if not LINK_WIDTH.has(String(l[2])):
				errors.append(where + "unknown link kind %s" % l[2])
		var images := int(SYMMETRIES.get(String(tp.get("symmetry", "none")), 1))
		for p in tp.get("players", []):
			if int(p) < 2 or int(p) > images:
				errors.append(where + "%s players do not fit its symmetry" % p)
	for tier: String in d.get("lair_guards", {}):
		if tier.begins_with("_"):
			continue
		for b: String in d["lair_guards"][tier]:
			if b != "any" and not biomes.has(b):
				errors.append("lair_guards %s: unknown biome %s" % [tier, b])
			for opt: Array in d["lair_guards"][tier][b]:
				for g: Array in opt:
					if not units.has(g[0]):
						errors.append("lair_guards %s: unknown unit %s" % [tier, g[0]])
	var gids := {}
	for g: Dictionary in d.get("garrisons", {}).get("groups", []):
		var where := "garrison %s: " % g.get("id", "?")
		if gids.has(g.get("id", "")) or String(g.get("name", "")) == "":
			errors.append(where + "needs a unique id and a name")
		gids[g.get("id", "")] = true
		if (g.get("units", []) as Array).is_empty():
			errors.append(where + "no units")
		for e: Array in g.get("units", []):
			if not units.has(e[0]) or int(e[1]) < 1:
				errors.append(where + "bad entry %s" % [e])
		for b: String in g.get("biomes", ["any"]):
			if b != "any" and not biomes.has(b):
				errors.append(where + "unknown biome %s" % b)
	if d.has("garrisons"):
		for size: String in sizes:
			if int(sizes[size].get("militia", 0)) > 0 and garrison_options(size, "").size() < 3:
				errors.append("garrisons: fewer than three groups fit a %s anywhere" % size)
	for name: String in SET_PIECES:
		for p: Array in SET_PIECES[name]["parts"]:
			if not ResourceLoader.exists("res://assets/props3d/%s.glb" % p[0]):
				errors.append("set piece %s: model %s missing" % [name, p[0]])
	return errors
