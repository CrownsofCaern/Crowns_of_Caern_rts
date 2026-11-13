class_name CombatFx3D
extends Node3D
## Per-attack combat effects of the 3D skirmish view. Archers' arrows, crossbow bolts,
## harpoons, thrown axes, sling stones and bombard shells fly in an arc from the shooter
## to its target; casters fire a glowing orb with a trail and a light. Where a blow or a
## missile lands the target bleeds (blood, ichor, bone dust, sparks, embers, sap, by what
## it is made of) and spells burst in their element. The fallen leave a pool. Healers send
## motes of light, hero skills strike, burst and rain in their element.
##
## Which element, gore and missile a unit uses comes from data/combat_fx.json; the colour
## ramps are the main game's BattleFx and BattleGore palettes, so both games read alike.
## Chunky square particles (CPUParticles3D, no textures), phone friendly, with caps on how
## many effects and lights live at once. Pure presentation: it reads SimWorld events and
## projectiles and never touches rules or GameRng. Particle spread uses Godot's particle
## randomness and spots vary by hash, neither of which feeds back into the game.

const PATH := "res://data/combat_fx.json"
const ELEMENTS := ["fire", "frost", "storm", "poison", "shadow", "blast", "arcane", "holy", "life", "blood", "tide"]
const GORES := ["blood", "ichor", "bone", "sparks", "ember", "sap", "ice", "wisp"]
const MISSILES := ["arrow", "bolt", "harpoon", "axe", "stone", "shell", "orb", "lob"]
const SHAPES := ["bolt", "strike", "area", "nova", "aura", "summon", "leap", "rain"]

## The 2D palettes speak in battle-view pixels; this many metres per pixel.
const PX2M := 0.022
## Particles are drawn this much bigger than the 2D palettes' pixels, so they read
## from the RTS camera (about 20-40 m away). They are soft round flecks
## (particle_texture), not square pixels, so they can stay small.
const GRAIN := 1.15
## Live caps: effects beyond them are skipped (a big melee stays cheap).
const MAX_BURSTS := 64
const MAX_LIGHTS := 6
## A unit spurts at most this often (s), so a swarm on one target doesn't flood it.
const SPURT_GAP := 0.16
## Missile arc height per metre flown.
const ARC := {"arrow": 0.2, "bolt": 0.06, "harpoon": 0.1, "axe": 0.14, "stone": 0.18, "shell": 0.32,
	"orb": 0.03, "lob": 0.32}
## Seconds a pool stays on the ground (it fades over the last third).
const POOL_TIME := 14.0
const SMOULDER_EVERY := 0.9  ## seconds between smoke puffs from a badly hurt building
const SLASH_TIME := 0.2  ## seconds a melee arc stays on screen
const MAX_SLASHES := 32
const SLASH_VARIANTS := 4
const HEAVY_RADIUS := 14.0  ## fighters this big (px) throw up dust where they strike
const DUST_HIT := Color(0.46, 0.4, 0.32)
## Colour of a plain weapon's arc (an element tints it).
const SLASH_STEEL := Color(1.0, 0.93, 0.78)

## Element styles, copied from the main game's BattleFx.STYLES (2D pixel units).
const STYLES := {
	"fire": {"colors": ["#fff2a8", "#ffb238", "#f0561c", "#8a1a10"], "gravity": -160.0, "speed": 120.0, "amount": 34, "core": "#ffcf5a", "size": 4.0},
	"frost": {"colors": ["#ffffff", "#c8f0ff", "#6cc2ef", "#2c5f9e"], "gravity": 260.0, "speed": 190.0, "amount": 28, "core": "#d8f6ff", "size": 4.0},
	"storm": {"colors": ["#ffffff", "#e6f2ff", "#8fb8ff", "#4a58c8"], "gravity": 0.0, "speed": 260.0, "amount": 24, "core": "#e8f0ff", "size": 3.0},
	"poison": {"colors": ["#e4ff8a", "#9ee04a", "#4f9a2a", "#24521c"], "gravity": -70.0, "speed": 70.0, "amount": 30, "core": "#b6f052", "size": 5.0},
	"shadow": {"colors": ["#f0c8ff", "#b46ef0", "#6a2ab0", "#2a0f4a"], "gravity": 0.0, "speed": -90.0, "amount": 30, "core": "#c890ff", "size": 4.0},
	"blast": {"colors": ["#ffe0a0", "#c8783a", "#5a4a42", "#2a2422"], "gravity": 120.0, "speed": 210.0, "amount": 40, "core": "#3a3030", "size": 5.0},
	"arcane": {"colors": ["#ffffff", "#ffe6a8", "#e0a8ff", "#7a5ad8"], "gravity": -30.0, "speed": 140.0, "amount": 26, "core": "#ffe6c0", "size": 3.0},
	"holy": {"colors": ["#ffffff", "#fff2b8", "#f0c860", "#a87a28"], "gravity": -120.0, "speed": 50.0, "amount": 24, "core": "#fff2b8", "size": 3.0},
	"life": {"colors": ["#f4ffd0", "#b8f07a", "#5ac85a", "#2a7a3a"], "gravity": -110.0, "speed": 40.0, "amount": 20, "core": "#b8f07a", "size": 3.0},
	"blood": {"colors": ["#ffb0a0", "#e0402a", "#a01a1a", "#4a0a0e"], "gravity": 40.0, "speed": 110.0, "amount": 26, "core": "#e0402a", "size": 4.0},
	"tide": {"colors": ["#e0fff8", "#7ae0d0", "#2a9aa8", "#164a6a"], "gravity": 220.0, "speed": 170.0, "amount": 32, "core": "#9af0e0", "size": 4.0},
}
## Elements bright enough to light the ground where they land.
const GLOWING := ["fire", "frost", "storm", "poison", "shadow", "arcane", "holy", "life", "tide", "blast"]
## How long an element lingers on the ground after it lands (s), as in BattleFx.LINGER.
const LINGER := {"fire": 2.6, "frost": 2.0, "holy": 1.6, "shadow": 1.6, "poison": 2.2, "blast": 1.8, "tide": 1.4}

## Gore kinds, copied from the main game's BattleGore.KINDS (2D pixel units).
const GORE := {
	"blood": {"colors": ["#ff8a78", "#d0281c", "#8a1010", "#3a0608"], "gravity": 420.0, "speed": 150.0, "pool": "#6e0c0e"},
	"ichor": {"colors": ["#c8ffe0", "#4ac0a0", "#1e7a6a", "#0a3a34"], "gravity": 420.0, "speed": 140.0, "pool": "#123e38"},
	"bone": {"colors": ["#f4ecd8", "#cfc3a4", "#8e846c", "#4a4436"], "gravity": 260.0, "speed": 110.0, "pool": "#4a4436"},
	"sparks": {"colors": ["#fff6c0", "#ffc040", "#d06018", "#3a3030"], "gravity": 380.0, "speed": 220.0, "pool": "#1e1a1a"},
	"ember": {"colors": ["#fff0a0", "#ff9a30", "#c0300c", "#2a0a06"], "gravity": -140.0, "speed": 120.0, "pool": "#3e140a"},
	"sap": {"colors": ["#e8f0a0", "#9ab840", "#5a6a20", "#2a2a10"], "gravity": 360.0, "speed": 120.0, "pool": "#2e3410"},
	"ice": {"colors": ["#ffffff", "#d8f4ff", "#7ac0e8", "#2c5a8a"], "gravity": 380.0, "speed": 170.0, "pool": "#c8e4f0"},
	"wisp": {"colors": ["#f0e8ff", "#b8a0f0", "#6a50b0", "#20183a"], "gravity": -120.0, "speed": 80.0, "pool": ""},
}
## Gore that glows (drawn additive) rather than staining.
const GORE_GLOWS := ["sparks", "ember", "wisp"]

static var _table: Dictionary = {}
static var _quads: Dictionary = {}  ## "add"/"mix" -> QuadMesh with its particle material
static var _glow_tex: Texture2D
static var _fleck_tex: Texture2D
static var _pool_texs: Array = []
static var _slash_meshes: Dictionary = {}  ## variant -> ArrayMesh (slash_mesh)

var view: SkirmishView3D
var _shots: Dictionary = {}  ## sim projectile id -> shot dict ({} = not shown)
var _flights: Array = []  ## presentation-only missiles (heal motes, skill bolts, rain)
var _pools: Array = []  ## {node, mat, t, color}
var _bursts := 0
var _slashes := 0
var _lights := 0
var _spurt_at: Dictionary = {}  ## unit id -> time of its last spurt
var _time := 0.0
var _smoulder_tick := -1  ## the last SMOULDER_EVERY step that puffed smoke from hurt buildings


# --- Table ------------------------------------------------------------------------

static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_table = parsed if parsed is Dictionary else {"units": {}, "classes": {}, "skills": {}}
	return _table


## {element, gore, missile} of a unit type (hero types read their class).
static func type_fx(type_id: String) -> Dictionary:
	var t := table()
	if type_id.begins_with("hero_"):
		var c: Dictionary = t.get("classes", {}).get(type_id.substr(5), {})
		return {"element": String(c.get("element", "")), "gore": "blood", "missile": String(c.get("missile", ""))}
	var u: Dictionary = t.get("units", {}).get(type_id, {})
	return {"element": String(u.get("element", "")), "gore": String(u.get("gore", "blood")),
		"missile": String(u.get("missile", ""))}


## Missile of a unit: its listed one, or for a shooter missing from the table an arrow
## (an orb if it has an element).
static func missile_of(type_id: String, ranged: bool) -> String:
	var fx := type_fx(type_id)
	if fx["missile"] != "" or not ranged:
		return fx["missile"]
	return "orb" if fx["element"] != "" else "arrow"


## {element, shape} of a hero skill cast by a hero of `class_id`. `s` is the skill's
## heroes.json entry (its target and effects pick the shape when the table leaves it open).
static func skill_fx(skill_id: String, class_id: String, s: Dictionary, ranged: bool) -> Dictionary:
	var entry: Dictionary = table().get("skills", {}).get(skill_id, {})
	var element := String(entry.get("element", ""))
	var cls: Dictionary = table().get("classes", {}).get(class_id, {})
	if element == "":
		element = String(cls.get("skill_element", cls.get("element", "")))
	if element == "":
		element = String(cls.get("element", ""))
	if element == "":
		element = "arcane"
	var shape := String(entry.get("shape", ""))
	if shape == "":
		shape = shape_from(s, ranged)
	return {"element": element, "shape": shape}


## Shape from a skill's data: what it targets and what it does.
static func shape_from(s: Dictionary, ranged: bool) -> String:
	var kinds := []
	for e in s.get("effects", []):
		kinds.append(String(e.get("type", "")))
	if "leap" in kinds:
		return "leap"
	if "summon" in kinds or "raise" in kinds or "resurrect" in kinds:
		return "summon"
	match String(s.get("target", "self")):
		"enemy", "ally":
			return "bolt" if ranged or String(s.get("target")) == "ally" else "strike"
		"point":
			return "area"
		"aura":
			return "aura"
	if float(s.get("radius", 0)) > 0.0 and ("damage" in kinds or "dot" in kinds or "drain" in kinds):
		return "nova"
	return "aura"


static func style(element: String) -> Dictionary:
	return STYLES.get(element, STYLES["arcane"])


static func gore_style(kind: String) -> Dictionary:
	return GORE.get(kind, GORE["blood"])


# --- Life cycle -------------------------------------------------------------------

func setup(owner_view: SkirmishView3D) -> void:
	view = owner_view
	name = "CombatFx"


## Drops every effect (a new game).
func clear() -> void:
	for c in get_children():
		c.queue_free()
	_shots.clear()
	_flights.clear()
	_pools.clear()
	_spurt_at.clear()


func on_event(e: Dictionary) -> void:
	if view == null or view.world == null:
		return
	match String(e["type"]):
		"hit":
			_on_hit(e)
		"death":
			_on_death(e)
		"heal":
			_on_heal(e)
		"skill":
			_on_skill(e)
		"summon":
			_on_summon(e)
		"building_destroyed", "hall_destroyed":
			# A building or a hall comes down: timber and stone dust, smoke and embers.
			if _seen(e["pos"]):
				var big := 1.6 if String(e["type"]) == "hall_destroyed" else 1.0
				var g := view.ground(e["pos"], 0.4)
				_dust(g, Color(0.45, 0.4, 0.34), 2.8 * big)
				_smoke(g + Vector3(0, 1.2, 0), 2.2 * big)
				gore_burst(g + Vector3(0, 0.8, 0), "ember", Vector3.UP, 1.4 * big)
				_linger(g, "fire", 1.6 * big)
		"fort_broken":
			# A wall piece comes down: a cloud of stone dust and smoke.
			if _seen(e["pos"]):
				var g := view.ground(e["pos"], 0.4)
				_dust(g, Color(0.42, 0.4, 0.37), 2.2)
				_smoke(g + Vector3(0, 1.0, 0), 1.6)


func update(delta: float) -> void:
	_time += delta
	_sync_shots()
	_fly(delta)
	_smoulder()
	for p in _pools:
		p["t"] += delta
		var k: float = clampf(float(p["t"]) / 1.2, 0.0, 1.0)
		var node: MeshInstance3D = p["node"]
		node.scale = Vector3.ONE * float(p["size"]) * (0.35 + 0.65 * sqrt(k))
		var fade: float = clampf((POOL_TIME - float(p["t"])) / (POOL_TIME / 3.0), 0.0, 1.0)
		(p["mat"] as StandardMaterial3D).albedo_color.a = 0.92 * fade
	for p in _pools.filter(func(p): return p["t"] >= POOL_TIME):
		(p["node"] as Node).queue_free()
	_pools = _pools.filter(func(p): return p["t"] < POOL_TIME)


## Buildings and halls below half strength smoke, harder the closer they are to falling.
func _smoulder() -> void:
	var w := view.world
	if w == null or w.economy == null or w.defense == null:
		return
	var tick := int(_time / SMOULDER_EVERY)
	if tick == _smoulder_tick:
		return
	_smoulder_tick = tick
	var hurt: Array = []  # [sim pos, hp ratio, size]
	for b in w.economy.buildings:
		var st := w.defense.building_structure(b)
		if st != null and b.done():
			hurt.append([b.pos, st.hp_ratio(), 1.0])
	for sec in w.economy.sectors:
		var hs := w.defense.hall_structure(sec)
		if hs != null:
			hurt.append([sec.center, hs.hp_ratio(), 1.5])
	for h in hurt:
		var r: float = h[1]
		if r < 0.5 and _seen(h[0]):
			var g := view.ground(h[0], 0.4)
			_smoke(g + Vector3(0, 1.4, 0), float(h[2]) * (0.6 + (0.5 - r)))


# --- Where things are -------------------------------------------------------------

func _seen(p_sim: Vector2) -> bool:
	var sk := view.sk
	if sk.fog_enabled and not view.world.vision.is_visible(sk.PLAYER, p_sim):
		return false
	return view.view_rect().grow(160.0).has_point(p_sim)


func _sim_pos(id: int) -> Variant:
	var u := view.world.get_unit(id)
	return u.pos if u != null else null


## A point on a unit's body (0 = feet, 1 = top), from the view, or INF if it has none.
func _point(id: int, frac: float) -> Vector3:
	return view.unit_point(id, frac)


func _ground_normal(at: Vector3) -> Vector3:
	var f := view.field
	var d := 0.5
	var hx := f.height_at(at.x + d, at.z) - f.height_at(at.x - d, at.z)
	var hz := f.height_at(at.x, at.z + d) - f.height_at(at.x, at.z - d)
	return Vector3(-hx, 2.0 * d, -hz).normalized()


# --- Events -----------------------------------------------------------------------

func _on_hit(e: Dictionary) -> void:
	var tid := int(e["unit"])
	var at := _point(tid, 0.55)
	if at == Vector3.INF:
		return
	var struck := view.world.get_unit(tid)
	if struck != null and struck.is_structure():
		if _seen(struck.pos):
			_dust(at, Color(0.45, 0.42, 0.38), 0.7)  # stone chips, not blood
		return
	var tpos: Variant = _sim_pos(tid)
	if tpos != null and not _seen(tpos):
		return
	var tfx := _fx_of_id(tid)
	var a := view.world.get_unit(int(e.get("attacker", -1)))
	var afx := type_fx(a.type_id) if a != null else {"element": "", "missile": ""}
	var missile := missile_of(a.type_id, a.is_ranged()) if a != null else ""
	var away := Vector3.UP
	if a != null and tpos != null:
		var d: Vector2 = (tpos as Vector2) - a.pos
		if d.length() > 0.1:
			d = d.normalized()
			away = Vector3(d.x, 0.7, d.y).normalized()
	var t := view.world.get_unit(tid)
	var strength := 1.0
	if t != null:
		strength = clampf(0.6 + float(e.get("damage", 0.0)) / maxf(t.max_hp, 1.0) * 4.0, 0.6, 1.4)
	match missile:
		"orb", "lob":
			var big := 1.25 if missile == "lob" else 1.0
			element_burst(at, String(afx["element"]), strength * big)
			_flash(at, String(afx["element"]), 1.0 * big)
			_linger(_ground_at(at), String(afx["element"]), 0.5 * big)
		"shell":
			var g := _ground_at(at)
			element_burst(g + Vector3(0, 0.3, 0), "blast", 1.6)
			element_burst(g + Vector3(0, 0.4, 0), "fire", 0.8)
			_flash(g, "fire", 1.6)
			_linger(g, "blast", 0.8)
			_spurt(tid, at, String(tfx["gore"]), away, strength)
		"":
			_spurt(tid, at, String(tfx["gore"]), away, strength)
			if String(afx["element"]) != "":
				element_burst(at, String(afx["element"]), 0.55)
			# The blow itself: a bright arc where the weapon swept through, bigger for big
			# fighters, and a shove of dust off the ground under a heavy one.
			var r := a.radius() if a != null else 9.0
			slash(at, String(afx["element"]), clampf(r / 9.0, 0.8, 2.2) * (0.85 + 0.25 * strength), tid + int(_time * 60.0))
			if r >= HEAVY_RADIUS and t != null:
				_dust(view.ground(t.pos, 0.15), DUST_HIT, clampf(r / 16.0, 0.7, 1.4))
		_:
			# Arrows, bolts, harpoons, axes and stones: a spurt where they bite.
			_spurt(tid, at, String(tfx["gore"]), away, strength * (1.2 if missile in ["harpoon", "axe"] else 0.9))


func _on_death(e: Dictionary) -> void:
	var id := int(e["unit"])
	var p: Vector2 = e["pos"]
	if not _seen(p):
		return
	var fx := type_fx(String(e["type_id"]))
	var kind := String(fx["gore"])
	var at := _point(id, 0.45)
	if at == Vector3.INF:
		at = view.ground(p, 0.8)
	var size := 1.0
	var def := view.world.catalog.get_unit(String(e["type_id"]))
	if not def.is_empty():
		size = clampf(float(def["radius"]) / 9.0, 0.8, 2.4)
	gore_burst(at, kind, Vector3.UP, 1.5 * sqrt(size), 1.6)
	match kind:
		"wisp":
			element_burst(at, "shadow", 1.0 * size)
		"sparks":
			_smoke(at, size)
		"bone":
			_dust(view.ground(p, 0.2), Color("#8e846c"), size)
		"ember":
			_linger(view.ground(p), "fire", size)
	var pool := String(gore_style(kind)["pool"])
	if pool != "":
		_pool(view.ground(p), Color(pool), 1.1 * size, id)


func _on_heal(e: Dictionary) -> void:
	var tid := int(e["target"])
	var tpos: Variant = _sim_pos(tid)
	if tpos == null or not _seen(tpos):
		return
	if _time - float(_spurt_at.get(-tid, -9.0)) < 0.3:
		return
	_spurt_at[-tid] = _time
	var src := view.world.get_unit(int(e["unit"]))
	var element := "life"
	if src != null and String(type_fx(src.type_id)["element"]) == "holy":
		element = "holy"
	var at := _point(tid, 0.5)
	if src != null and src.id != tid and src.hero == null:
		# A healer sends a mote of light to the one it mends.
		var from := _point(src.id, 0.8)
		if from != Vector3.INF:
			var land := func(p: Vector3) -> void:
				element_burst(p, element, 0.6)
			launch(from, tid, at, "orb", element, land, 0.55)
			return
	if at != Vector3.INF:
		element_burst(at, element, 0.45)


func _on_skill(e: Dictionary) -> void:
	var u := view.world.get_unit(int(e["unit"]))
	var hs := view.world.heroes
	if u == null or u.hero == null or hs == null:
		return
	var s := hs.cat.skill(String(e["skill"]))
	if s.is_empty():
		return
	var pos: Vector2 = e["pos"]
	if not (_seen(pos) or _seen(u.pos)):
		return
	var fx := skill_fx(String(e["skill"]), u.hero.class_id, s, u.is_ranged())
	var element := String(fx["element"])
	var r_m := maxf(float(s.get("radius", 0)) / TerrainField.PX, 0.0)
	var dot_s := 0.0
	for eff in s.get("effects", []):
		if String(eff.get("type", "")) == "dot":
			var secs: Variant = eff.get("seconds", 4.0)
			dot_s = float(secs[0] if secs is Array else secs)
	var me := _point(u.id, 0.6)
	if me == Vector3.INF:
		me = view.ground(u.pos, 1.1)
	var tid := int(e.get("target", -1))
	match String(fx["shape"]):
		"bolt":
			var to := _point(tid, 0.55) if tid >= 0 else Vector3.INF
			if to == Vector3.INF:
				to = view.ground(pos, 1.0)
			# A skill shot is the hero's own missile, charged with the skill's element:
			# a ranger's arrow glows, a mystic's orb is bigger and brighter.
			var miss := missile_of(u.type_id, u.is_ranged())
			if miss == "":
				miss = "orb"
			var land := func(p: Vector3) -> void:
				element_burst(p, element, 1.7)
				_flash(p, element, 1.5)
				_shockwave(_ground_at(p), element, 1.4)
			launch(me, tid, to, miss, element, land, 1.0, true)
		"strike":
			var at := _point(tid, 0.5) if tid >= 0 else view.ground(pos, 1.0)
			if at == Vector3.INF:
				at = view.ground(pos, 1.0)
			# A charged blow: the weapon sweeps an arc of the element, and the target
			# is struck by a column of it.
			_slash(me, at, element)
			element_burst(at, element, 1.6)
			_flash(at, element, 1.2)
			_pillar(_ground_at(at), element, 0.8)
			_dust(_ground_at(at), Color("#5a4a42"), 0.9)
		"area":
			var g := view.ground(pos, 0.15)
			ring_burst(g, element, maxf(r_m, 1.5))
			element_burst(g + Vector3(0, 0.6, 0), element, 1.6)
			_flash(g, element, 2.0)
			_shockwave(g, element, maxf(r_m, 1.5))
			_pillar(g, element, 1.4)
			if dot_s > 0.0:
				_linger(g, element, maxf(r_m, 1.5) / 1.5, dot_s)
		"nova":
			var g := view.ground(u.pos, 0.3)
			nova(g, element, maxf(r_m, 1.5))
			_flash(g, element, 1.6)
			_shockwave(g, element, maxf(r_m, 1.5))
			if dot_s > 0.0:
				_linger(g, element, maxf(r_m, 1.5) / 1.5, dot_s)
		"aura":
			ring_burst(view.ground(u.pos, 0.1), element, clampf(r_m, 1.2, 6.0), true)
			element_burst(me, element, 1.0)
			_shockwave(view.ground(u.pos, 0.05), element, clampf(r_m, 1.2, 6.0), 0.9)
			_pillar(view.ground(u.pos), element, 1.0)
		"summon":
			element_burst(view.ground(u.pos, 0.8), element, 1.8)
			_flash(view.ground(u.pos, 0.5), element, 1.5)
			_shockwave(view.ground(u.pos, 0.05), element, 3.0)
		"leap":
			var g := view.ground(pos, 0.1)
			_dust(g, Color("#6a5a4a"), 1.6)
			ring_burst(g, element, maxf(r_m, 1.5))
			_shockwave(g, element, maxf(r_m, 1.5))
		"rain":
			_rain(u, pos, maxf(r_m, 1.5), element, dot_s)


func _on_summon(e: Dictionary) -> void:
	var id := int(e["unit"])
	var p: Variant = _sim_pos(id)
	if p == null or not _seen(p):
		return
	element_burst(view.ground(p, 0.6), "shadow", 0.9)


## Effects of a unit by id (also one that just died: the view still knows its type).
func _fx_of_id(id: int) -> Dictionary:
	var u := view.world.get_unit(id)
	var type_id := u.type_id if u != null else view.unit_type(id)
	return type_fx(type_id) if type_id != "" else {"element": "", "gore": "blood", "missile": ""}


func _ground_at(at: Vector3) -> Vector3:
	return Vector3(at.x, view.field.height_at(at.x, at.z), at.z)


# --- Missiles from the sim --------------------------------------------------------

func _sync_shots() -> void:
	var world := view.world
	var alpha := view.sk._alpha()
	var seen := {}
	for pr in world.projectiles:
		var id := int(pr.get("id", 0))
		if id == 0:
			continue
		seen[id] = true
		if not _shots.has(id):
			_shots[id] = _new_shot(pr)
		var s: Dictionary = _shots[id]
		if s.is_empty():
			continue
		var p: Vector2 = (pr.get("prev", pr["pos"]) as Vector2).lerp(pr["pos"], alpha)
		var tgt := world.get_unit(int(pr["target"]))
		var to := _point(tgt.id, 0.55) if tgt != null else Vector3.INF
		if to != Vector3.INF:
			s["to"] = to
		var tsim: Vector2 = tgt.pos if tgt != null else p
		var from_sim: Vector2 = pr["from"]
		var d_from := from_sim.distance_to(p)
		var d_to := p.distance_to(tsim)
		var k := d_from / maxf(d_from + d_to, 0.01)
		var m := TerrainField.to_world(p)
		var y := lerpf((s["from"] as Vector3).y, (s["to"] as Vector3).y, k)
		y += float(ARC.get(s["kind"], 0.1)) * (d_from + d_to) / TerrainField.PX * 4.0 * k * (1.0 - k)
		_place(s, Vector3(m.x, y, m.y))
		(s["node"] as Node3D).visible = _seen(p)
	for id in _shots.keys():
		if seen.has(id):
			continue
		var s: Dictionary = _shots[id]
		_shots.erase(id)
		if not s.is_empty():
			_retire(s["node"])


func _new_shot(pr: Dictionary) -> Dictionary:
	var a := view.world.get_unit(int(pr["attacker"]))
	var tgt := view.world.get_unit(int(pr["target"]))
	var from_sim: Vector2 = pr["from"]
	if not _seen(from_sim) and (tgt == null or not _seen(tgt.pos)):
		return {}
	var kind := missile_of(a.type_id, true) if a != null else "arrow"
	var element := String(type_fx(a.type_id)["element"]) if a != null else ""
	var from := _point(a.id, 0.7) if a != null else Vector3.INF
	if from == Vector3.INF:
		from = view.ground(from_sim, float(pr.get("lift", 1.2)))  # halls and towers shoot from the roof
	var to := _point(tgt.id, 0.55) if tgt != null else Vector3.INF
	if to == Vector3.INF:
		to = view.ground(tgt.pos, 1.0) if tgt != null else from
	var node := missile(kind, element)
	add_child(node)
	node.position = from
	if kind in ["orb", "lob"]:
		_attach_light(node, element, 1.3, 3.5)
	return {"node": node, "kind": kind, "from": from, "to": to}


## Moves a missile and turns it along its flight (axes spin end over end).
func _place(s: Dictionary, p: Vector3) -> void:
	var node: Node3D = s["node"]
	var step := p - node.position
	node.position = p
	if step.length() > 0.001:
		var up := Vector3.UP if absf(step.normalized().y) < 0.98 else Vector3.FORWARD
		node.basis = Basis.looking_at(step.normalized(), up)
	if s["kind"] == "axe":
		var spin := node.get_node_or_null("Spin") as Node3D
		if spin != null:
			spin.rotation.x -= 0.6


## Ends a missile: its trail fades out instead of vanishing.
func _retire(node: Node3D) -> void:
	for c in node.get_children():
		if c is CPUParticles3D:
			(c as CPUParticles3D).emitting = false
		elif c is OmniLight3D:
			c.queue_free()
		elif c is Node3D:
			(c as Node3D).visible = false
	_free_later(node, 0.5)


func _free_later(node: Node, seconds: float) -> void:
	if not node.is_inside_tree():
		node.queue_free()
		return
	var tw := node.create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(node.queue_free)


# --- Presentation-only flights (heal motes, skill bolts, rain) --------------------

## Flies a missile from `from` to unit `target_id` (or to `to` if it is gone), then
## calls `on_land` with where it landed. `speed` scales the flight time.
## `charged` (hero skills) makes it bigger and wraps it in its element's glow and light.
func launch(from: Vector3, target_id: int, to: Vector3, kind: String, element: String, on_land: Callable,
		speed: float = 1.0, charged: bool = false) -> void:
	if to == Vector3.INF:
		to = from
	var node := missile(kind, element, charged)
	add_child(node)
	node.position = from
	if kind in ["orb", "lob"] or charged:
		_attach_light(node, element, 2.0 if charged else 1.3, 4.5 if charged else 3.5)
	var dur := clampf(from.distance_to(to) / (16.0 * speed), 0.15, 1.2)
	_flights.append({"node": node, "kind": kind, "from": from, "to": to, "target": target_id, "t": 0.0,
		"dur": dur, "land": on_land})


func _fly(delta: float) -> void:
	var done: Array = []
	for f in _flights:
		f["t"] += delta
		if int(f["target"]) >= 0:
			var p := _point(int(f["target"]), 0.55)
			if p != Vector3.INF:
				f["to"] = p
		var k: float = clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0)
		var a: Vector3 = f["from"]
		var b: Vector3 = f["to"]
		var flat := Vector2(b.x - a.x, b.z - a.z).length()
		var p := a.lerp(b, k)
		p.y += float(ARC.get(f["kind"], 0.1)) * flat * 4.0 * k * (1.0 - k)
		_place(f, p)
		if k >= 1.0:
			done.append(f)
	for f in done:
		_flights.erase(f)
		_retire(f["node"])
		(f["land"] as Callable).call(f["to"])


## Missiles fall on an area: arrows, axes or shells by the hero's class.
## Skill missiles glow in the skill's element and spark where they land.
func _rain(u: SimUnit, centre: Vector2, r_m: float, element: String, dot_s: float) -> void:
	var kind := missile_of(u.type_id, true)
	if kind in ["orb", "lob", "harpoon", "bolt"]:
		kind = "arrow"
	var is_shell := element == "blast"
	if is_shell:
		kind = "shell"
	var count := 9 if dot_s <= 0.0 else mini(int(dot_s * 4.0), 24)
	if is_shell:
		count = 4
	var spread_s := 0.5 if dot_s <= 0.0 else dot_s
	var g := view.ground(centre)
	_shockwave(view.ground(centre, 0.05), element, r_m, 0.6)
	for i in count:
		var a := _noise(i, u.id) * TAU
		var r := sqrt(_noise(i, u.id + 7)) * r_m
		var land := Vector3(g.x + cos(a) * r, 0.0, g.z + sin(a) * r)
		land.y = view.field.height_at(land.x, land.z)
		var from := land + Vector3(-2.5, 9.0, 3.0)
		var delay := spread_s * float(i) / float(count)
		var hit := func(p: Vector3) -> void:
			if is_shell:
				element_burst(p + Vector3(0, 0.3, 0), "blast", 1.4)
				element_burst(p + Vector3(0, 0.4, 0), "fire", 0.7)
				_flash(p, "fire", 1.4)
			else:
				_dust(p, Color("#5a4a42"), 0.35)
				element_burst(p + Vector3(0, 0.2, 0), element, 0.6)
		var fire := func() -> void:
			if is_inside_tree():
				launch(from, -1, land, kind, "" if is_shell else element, hit, 1.0, not is_shell)
		if delay <= 0.0 or not is_inside_tree():
			fire.call()
		else:
			get_tree().create_timer(delay).timeout.connect(fire)


# --- Building blocks --------------------------------------------------------------

static func _quad(additive: bool) -> QuadMesh:
	var key := "add" if additive else "mix"
	if _quads.has(key):
		return _quads[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true  # else every particle is a 1 m card
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = particle_texture()
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = m
	_quads[key] = q
	return q


## A round fleck with a solid middle and a soft rim: what every particle is drawn with.
static func particle_texture() -> Texture2D:
	if _fleck_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.4, 0.75, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 32
		t.height = 32
		_fleck_tex = t
	return _fleck_tex


static func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	var n := colors.size()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in n:
		offsets.append(0.8 * float(i) / float(maxi(1, n - 1)))
		cols.append(Color(colors[i]))
	g.offsets = offsets
	g.colors = cols
	g.add_point(1.0, Color(Color(colors[n - 1]), 0.0))
	return g


## A one-shot particle burst; `g2`, `v2` and `px` are in the 2D palettes' pixels.
func _particles(at: Vector3, colors: Array, g2: float, v2: float, amount: float, px: float, additive: bool,
		strength: float, dir := Vector3.UP, spread := 180.0, life := 0.6) -> CPUParticles3D:
	if _bursts >= MAX_BURSTS:
		return null
	var p := CPUParticles3D.new()
	p.mesh = _quad(additive)
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = clampi(int(amount * strength), 4, 90)
	p.lifetime = life
	p.direction = dir
	p.spread = spread
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12 * strength
	var v := v2 * PX2M
	if v < 0.0:
		# Implodes: starts on a shell and is pulled to the centre.
		p.emission_sphere_radius = 0.7 * strength
		p.radial_accel_min = -9.0
		p.radial_accel_max = -6.0
		v = 0.3
	p.initial_velocity_min = v * 0.45
	p.initial_velocity_max = v
	p.gravity = Vector3(0.0, -g2 * PX2M, 0.0)
	p.damping_min = 0.8
	p.damping_max = 2.0
	var size := px * 1.25 * PX2M * GRAIN * clampf(strength, 0.8, 1.5)
	p.scale_amount_min = size * 0.55
	p.scale_amount_max = size
	p.color_ramp = _ramp(colors)
	p.position = at
	add_child(p)
	_bursts += 1
	p.tree_exiting.connect(func() -> void: _bursts -= 1)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## An element bursting at `at` (1 = a normal hit).
func element_burst(at: Vector3, element: String, strength: float = 1.0) -> CPUParticles3D:
	var st := style(element)
	return _particles(at, st["colors"], float(st["gravity"]), float(st["speed"]), float(st["amount"]),
		float(st["size"]), element != "blast", strength)


## Gore thrown off a wound, mostly along `dir` (away from the blow).
func gore_burst(at: Vector3, kind: String, dir: Vector3, strength: float = 1.0, amount_k: float = 1.0) -> CPUParticles3D:
	var st := gore_style(kind)
	var p := _particles(at, st["colors"], float(st["gravity"]), float(st["speed"]), 16.0 * amount_k, 3.5,
		kind in GORE_GLOWS, strength, dir, 50.0 if amount_k <= 1.0 else 120.0, 0.7)
	return p


func _spurt(id: int, at: Vector3, kind: String, dir: Vector3, strength: float) -> void:
	if _time - float(_spurt_at.get(id, -9.0)) < SPURT_GAP:
		return
	_spurt_at[id] = _time
	gore_burst(at, kind, dir, strength)


## A burst on a ring on the ground (an area spell); `rising` makes it a slow aura.
func ring_burst(at: Vector3, element: String, radius_m: float, rising: bool = false) -> CPUParticles3D:
	if _bursts >= MAX_BURSTS:
		return null
	var st := style(element)
	var p := _particles(at, st["colors"], float(st["gravity"]), absf(float(st["speed"])),
		float(st["amount"]) * clampf(radius_m * 0.8, 1.0, 3.0), float(st["size"]), element != "blast", 1.0,
		Vector3.UP, 15.0, 0.9 if rising else 0.6)
	if p == null:
		return null
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius_m
	p.emission_ring_inner_radius = radius_m * (0.85 if rising else 0.2)
	p.emission_ring_height = 0.1
	p.radial_accel_min = 0.0
	p.radial_accel_max = 0.0
	if rising:
		p.explosiveness = 0.3
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 1.4
		p.gravity = Vector3(0, 0.8, 0)
	return p


## A wave rushing out from a point along the ground.
func nova(at: Vector3, element: String, radius_m: float) -> CPUParticles3D:
	var st := style(element)
	var p := _particles(at, st["colors"], 0.0, 40.0, float(st["amount"]) * 2.0, float(st["size"]),
		element != "blast", 1.0, Vector3.UP, 10.0, 0.5)
	if p == null:
		return null
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.4
	p.emission_ring_inner_radius = 0.3
	p.emission_ring_height = 0.2
	p.radial_accel_min = radius_m * 7.0
	p.radial_accel_max = radius_m * 9.0
	p.damping_min = 0.0
	p.damping_max = 0.0
	return p


func _smoke(at: Vector3, size: float) -> void:
	_particles(at, ["#8a8480", "#4a4644", "#2a2826", "#1a1818"], -60.0, 40.0, 14.0 * size, 6.0, false, 1.0,
		Vector3.UP, 30.0, 1.4)


## A ring of dust thrown up from the ground (a building finished, a heavy blow).
func dust_burst(at: Vector3, c: Color, size: float) -> void:
	_dust(at, c, size)


## A melee arc: a crescent of light that sweeps open and fades where a blow lands.
## `salt` picks the angle of the swing.
func slash(at: Vector3, element: String, size: float, salt: int) -> MeshInstance3D:
	if _slashes >= MAX_SLASHES:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = slash_mesh(posmod(salt, SLASH_VARIANTS))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var c := SLASH_STEEL
	if element != "":
		c = c.lerp(Color(String(style(element)["colors"][1])), 0.7)
	m.albedo_color = Color(c.r * 2.2, c.g * 2.2, c.b * 2.2, 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.scale = Vector3.ONE * size * 0.6
	add_child(mi)
	_slashes += 1
	mi.tree_exiting.connect(func() -> void: _slashes -= 1)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 1.1, SLASH_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(m, "albedo_color:a", 0.0, SLASH_TIME).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)
	return mi


## A crescent in the camera plane (billboarded), about 1.1 m across, swung at one of
## SLASH_VARIANTS angles; thick and bright in the middle, thin at the tips.
static func slash_mesh(variant: int) -> ArrayMesh:
	if _slash_meshes.has(variant):
		return _slash_meshes[variant]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tilt := -0.9 + 1.8 * float(variant) / float(maxi(1, SLASH_VARIANTS - 1))
	var flip := 1.0 if variant % 2 == 0 else -1.0
	var n := 12
	var r := 0.55
	var prev_in := Vector3.ZERO
	var prev_out := Vector3.ZERO
	var prev_c := Color.WHITE
	for i in n + 1:
		var f := float(i) / float(n)
		var a := tilt + flip * lerpf(-1.1, 1.1, f)
		var w := sin(f * PI) * 0.22
		var dir := Vector3(cos(a), sin(a), 0.0)
		var outer := dir * (r + w * 0.3)
		var inner := dir * (r - w)
		var c := Color(1, 1, 1, minf(1.0, sin(f * PI) * (0.6 + 0.8 * f)))  # brightest where the blade ends
		if i > 0:
			for v in [[prev_out, prev_c], [outer, c], [inner, c], [prev_out, prev_c], [inner, c], [prev_in, prev_c]]:
				st.set_color(v[1])
				st.add_vertex(v[0])
		prev_in = inner
		prev_out = outer
		prev_c = c
	var mesh := st.commit()
	_slash_meshes[variant] = mesh
	return mesh


func _dust(at: Vector3, c: Color, size: float) -> void:
	var cols := [c.lightened(0.3).to_html(), c.to_html(), c.darkened(0.4).to_html()]
	var p := _particles(at, cols, 60.0, 110.0, 18.0 * size, 5.0, false, size, Vector3.UP, 70.0, 0.8)
	if p != null:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_axis = Vector3.UP
		p.emission_ring_radius = 0.4 * size
		p.emission_ring_inner_radius = 0.1
		p.emission_ring_height = 0.05


## An element hanging on the ground for a while (embers, frost mist, poison).
func _linger(at: Vector3, element: String, size: float = 1.0, seconds: float = -1.0) -> void:
	if not LINGER.has(element) or _bursts >= MAX_BURSTS:
		return
	if seconds < 0.0:
		seconds = float(LINGER[element])
	var st := style(element)
	var p := CPUParticles3D.new()
	p.mesh = _quad(true)
	p.amount = clampi(int(8.0 * size), 4, 48)
	p.lifetime = 1.0
	p.direction = Vector3.UP
	p.spread = 25.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.6 * size, 0.05, 0.6 * size)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.7
	p.gravity = Vector3(0, 0.9 if float(st["gravity"]) < 0.0 else 0.15, 0)
	var px := float(st["size"]) * PX2M * GRAIN
	p.scale_amount_min = px * 0.6
	p.scale_amount_max = px * 1.1
	p.color_ramp = _ramp(st["colors"])
	p.position = at + Vector3(0, 0.1, 0)
	add_child(p)
	_bursts += 1
	p.tree_exiting.connect(func() -> void: _bursts -= 1)
	p.emitting = true
	if p.is_inside_tree():
		var tw := p.create_tween()
		tw.tween_interval(seconds)
		tw.tween_callback(func() -> void: p.emitting = false)
		tw.tween_interval(p.lifetime)
		tw.tween_callback(p.queue_free)


## A bright flash where a spell lands: a soft glow card and, while the budget lasts,
## a short light that colours the ground and the units around it.
func _flash(at: Vector3, element: String, strength: float) -> void:
	if not element in GLOWING or not is_inside_tree():
		return
	var st := style(element)
	var c := Color(st["colors"][1])
	var card := glow_card(c, 1.2 * strength)
	card.position = at
	add_child(card)
	var tw := card.create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "scale", Vector3.ONE * 1.8, 0.3).from(Vector3.ONE * 0.6)
	tw.tween_property(card.material_override, "albedo_color:a", 0.0, 0.3).from(0.9)
	tw.chain().tween_callback(card.queue_free)
	if _lights >= MAX_LIGHTS:
		return
	var l := OmniLight3D.new()
	l.light_color = c
	l.omni_range = 3.0 + 2.0 * strength
	l.light_energy = 2.4 * strength
	l.shadow_enabled = false
	l.position = at + Vector3(0, 0.5, 0)
	add_child(l)
	_count_light(l)
	var lt := l.create_tween()
	lt.tween_property(l, "light_energy", 0.0, 0.35)
	lt.tween_callback(l.queue_free)


func _attach_light(node: Node3D, element: String, energy: float, range_m: float) -> void:
	if _lights >= MAX_LIGHTS or not element in GLOWING:
		return
	var l := OmniLight3D.new()
	l.light_color = Color(style(element)["colors"][1])
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = false
	node.add_child(l)
	_count_light(l)


func _count_light(l: OmniLight3D) -> void:
	_lights += 1
	l.tree_exiting.connect(func() -> void: _lights -= 1)


## A ring of light that sweeps out over the ground from `at` to `radius_m`.
func _shockwave(at: Vector3, element: String, radius_m: float, time: float = 0.45) -> void:
	if not is_inside_tree():
		return
	var c := Color(style(element)["colors"][1])
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 2.0
	mi.mesh = plane
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = ring_texture()
	m.albedo_color = Color(c, 0.9)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at + Vector3(0, 0.08, 0)
	add_child(mi)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius_m, 1.0, radius_m), time).from(Vector3(0.2, 1.0, 0.2)) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, time).from(0.9).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## A column of the element's light rising from the ground (a spell coming down).
func _pillar(at: Vector3, element: String, strength: float) -> void:
	if not is_inside_tree():
		return
	var st := style(element)
	var card := glow_card(Color(st["colors"][1]), 1.0)
	(card.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	card.position = at + Vector3(0, 1.6 * strength, 0)
	card.scale = Vector3(0.9 * strength, 3.4 * strength, 1.0)
	add_child(card)
	var tw := card.create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "scale:x", 0.1, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_property(card.material_override, "albedo_color:a", 0.0, 0.5).from(1.0)
	tw.chain().tween_callback(card.queue_free)
	var p := _particles(at + Vector3(0, 0.2, 0), st["colors"], -300.0, 60.0, float(st["amount"]) * 0.8,
		float(st["size"]), element != "blast", strength, Vector3.UP, 12.0, 0.7)
	if p != null:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_axis = Vector3.UP
		p.emission_ring_radius = 0.45 * strength
		p.emission_ring_inner_radius = 0.1
		p.emission_ring_height = 0.1


## A weapon's sweep of the element in front of the hero, towards `at`.
func _slash(from: Vector3, at: Vector3, element: String) -> void:
	var st := style(element)
	var d := Vector3(at.x - from.x, 0.0, at.z - from.z)
	if d.length() < 0.05:
		d = Vector3.RIGHT
	d = d.normalized()
	var side := d.cross(Vector3.UP)
	for i in 7:
		var k := float(i) / 6.0 - 0.5
		var p := from + d * (0.7 + 0.25 * cos(k * PI)) + side * k * 1.6 + Vector3(0, -0.1 + 0.4 * k, 0)
		var b := _particles(p, st["colors"], 0.0, 30.0, 4.0, float(st["size"]), element != "blast", 1.0,
			d, 20.0, 0.3)
		if b != null:
			b.emission_sphere_radius = 0.05


static var _ring_tex: Texture2D


static func ring_texture() -> Texture2D:
	if _ring_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.6, 0.85, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.15), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_ring_tex = t
	return _ring_tex


static func glow_texture() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_glow_tex = t
	return _glow_tex


## A camera-facing additive glow, `size_m` across.
static func glow_card(c: Color, size_m: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size_m
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = glow_texture()
	m.albedo_color = c
	m.no_depth_test = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _box(size: Vector3, c: Color, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	mi.material_override = m
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _ball(r: float, c: Color, additive: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 4
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if additive:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A trail of particles left in the world behind a moving missile.
static func _trail(colors: Array, amount: int, life: float, px: float, additive: bool, rise: float) -> CPUParticles3D:
	var t := CPUParticles3D.new()
	t.mesh = _quad(additive)
	t.amount = amount
	t.lifetime = life
	t.local_coords = false
	t.spread = 180.0
	t.initial_velocity_min = 0.05
	t.initial_velocity_max = 0.4
	t.gravity = Vector3(0, rise, 0)
	t.scale_amount_min = px * 0.5
	t.scale_amount_max = px
	t.color_ramp = _ramp(colors)
	t.emitting = true
	return t


## The node of a missile, its nose along -Z (Basis.looking_at).
static func missile(kind: String, element: String = "", charged: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Missile_" + kind
	var wood := Color("#5a4230")
	var iron := Color("#a8a8a8")
	var fletch := Color("#d8d0c0")
	match kind:
		"arrow":
			root.add_child(_box(Vector3(0.045, 0.045, 0.8), wood))
			root.add_child(_box(Vector3(0.07, 0.07, 0.12), iron, Vector3(0, 0, -0.44)))
			root.add_child(_box(Vector3(0.16, 0.02, 0.18), fletch, Vector3(0, 0, 0.33)))
			root.add_child(_box(Vector3(0.02, 0.16, 0.18), fletch, Vector3(0, 0, 0.33)))
			root.add_child(_trail(["#fff4e0", "#c8c0b0", "#6a6460"], 10, 0.18, 0.05, false, 0.0))
		"bolt":
			root.add_child(_box(Vector3(0.06, 0.06, 0.5), wood.darkened(0.2)))
			root.add_child(_box(Vector3(0.09, 0.09, 0.12), iron, Vector3(0, 0, -0.3)))
			root.add_child(_box(Vector3(0.14, 0.02, 0.12), Color("#3a3030"), Vector3(0, 0, 0.2)))
			root.add_child(_trail(["#fff4e0", "#c8c0b0", "#6a6460"], 10, 0.15, 0.05, false, 0.0))
		"harpoon":
			root.add_child(_box(Vector3(0.06, 0.06, 1.2), Color("#4a5a50")))
			root.add_child(_box(Vector3(0.16, 0.05, 0.2), Color("#c8d8d0"), Vector3(0, 0, -0.66)))
			root.add_child(_trail(["#e0fff8", "#7ae0d0", "#2a9aa8"], 12, 0.25, 0.07, false, -1.0))
		"axe":
			var spin := Node3D.new()
			spin.name = "Spin"
			spin.add_child(_box(Vector3(0.05, 0.5, 0.05), wood))
			spin.add_child(_box(Vector3(0.04, 0.16, 0.22), iron, Vector3(0, 0.2, -0.08)))
			root.add_child(spin)
		"stone":
			root.add_child(_ball(0.1, Color("#8a8278"), false))
			root.add_child(_trail(["#c8c0b0", "#6a6460"], 6, 0.15, 0.05, false, 0.0))
		"shell":
			root.add_child(_ball(0.17, Color("#1e1a1a"), false))
			root.add_child(_trail(["#ffcf5a", "#f0561c", "#4a4644", "#2a2826"], 24, 0.5, 0.14, false, 1.2))
		_:
			# orb and lob: a glowing core in its element with a trail.
			var st := style(element if element != "" else "arcane")
			var r := 0.17 if kind == "lob" else 0.13
			root.add_child(_ball(r, Color(st["core"]), true))
			root.add_child(glow_card(Color(st["colors"][1]), r * 7.0))
			root.add_child(_trail(st["colors"], 30, 0.4, float(st["size"]) * PX2M * GRAIN * 1.2, true,
				-float(st["gravity"]) * PX2M * 0.3))
	if charged:
		# A hero's skill shot: bigger, haloed in its element, with a long bright trail.
		var cst := style(element if element != "" else "arcane")
		root.scale = Vector3.ONE * 1.4
		root.add_child(glow_card(Color(cst["colors"][1]), 1.1))
		root.add_child(_trail(cst["colors"], 40, 0.5, float(cst["size"]) * PX2M * GRAIN * 1.3, true,
			-float(cst["gravity"]) * PX2M * 0.3))
		root.set_meta("charged", true)
	return root


# --- Pools ------------------------------------------------------------------------

## A pixelated, ragged blob (white; tinted per pool). Four looks, picked by hash.
static func pool_texture(variant: int) -> Texture2D:
	if _pool_texs.is_empty():
		for v in 4:
			var n := 32
			var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
			var lobes := []
			for i in 7:
				lobes.append(0.55 + 0.35 * _noise(i, v * 31 + 5))
			for y in n:
				for x in n:
					var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5) / (n * 0.5)
					var a := fposmod(d.angle() / TAU * 7.0, 7.0)
					var i0 := int(a) % 7
					var lim: float = lerpf(lobes[i0], lobes[(i0 + 1) % 7], a - floorf(a))
					var inside := d.length() < lim
					# A few drops thrown off the edge.
					if not inside and d.length() < 1.0 and _noise(x * 37 + y, v + 99) > 0.985:
						inside = true
					var shade := 0.8 + 0.2 * _noise(x + y * 32, v)
					img.set_pixel(x, y, Color(shade, shade, shade, 1.0) if inside else Color(1, 1, 1, 0))
			var t := ImageTexture.create_from_image(img)
			_pool_texs.append(t)
	return _pool_texs[posmod(variant, _pool_texs.size())]


func _pool(at: Vector3, c: Color, size: float, salt: int) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	mi.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_texture = pool_texture(salt)
	m.albedo_color = Color(c, 0.92)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.35  # wet
	# A little of its own colour, so a pool still reads on dark ground at night.
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.35
	m.metallic_specular = 0.6
	m.set_meta("matte", true)  # keeps its sheen (Atmosphere3D mattes models)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var nrm := _ground_normal(at)
	var side := nrm.cross(Vector3.FORWARD).normalized()
	mi.basis = Basis(side, nrm, side.cross(nrm)).rotated(nrm, _noise(salt, 3) * TAU)
	mi.position = at + nrm * 0.04
	mi.scale = Vector3.ONE * size * 0.35
	add_child(mi)
	_pools.append({"node": mi, "mat": m, "t": 0.0, "size": size})
	if _pools.size() > 60:
		(_pools[0]["node"] as Node).queue_free()
		_pools.remove_at(0)


## Cheap deterministic 0..1 noise (as BattleGore.noise).
static func _noise(i: int, salt: int) -> float:
	return float(posmod(hash(Vector2i(i, salt)), 1000)) / 999.0
