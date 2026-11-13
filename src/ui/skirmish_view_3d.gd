class_name SkirmishView3D
extends Node3D
## The 3D look of a skirmish: the MapScene3D world, a fixed-angle RTS camera, units
## (the main game's animated battle sprites as camera-facing billboards, SpriteUnit),
## settlements, buildings and resource piles. Reads Skirmish and SimWorld state only;
## Skirmish keeps all input and orders. Sim pixels map to metres via TerrainField.

## The camera looks down steeply when zoomed out (overview) and tilts flatter as it
## comes in, so close-ups show the land rolling away rather than a map.
const PITCH_FAR := 58.0
const PITCH_NEAR := 42.0
const FOV := 35.0
const BASE_DIST := 30.0  ## metres from the camera target at zoom 1
## Hero class bodies (3D, one per class): the campaign journey map walks them, and
## tools/render_hero_sprites.gd bakes them into the heroes' battle sprites.
const HEROES3D := "res://assets/heroes3d/"
const BUILDINGS3D := "res://assets/buildings3d/%s.glb"
## Wall piece and tower models (Tripo; see assets/source/buildings3d/buildings.json "fort_*").
const FORTS3D := "res://assets/forts3d/%s.glb"
## How a 4 m Tripo wall section is stretched to a piece: height and thickness factors.
const WALL_HEIGHT_K := 1.8
const WALL_DEPTH_K := 2.0
const TOWER_WIDTH_M := 3.0
## Metres above the ground an archer stands on a tower (matches economy.json forts.tower.lift).
const TOWER_TOP_M := 4.2
const SETTLEMENTS3D := "res://assets/settlements3d/%s.glb"
const NATURE3D := "res://assets/nature/%s.glb"
const RESOURCES3D := "res://assets/resources3d/res_%s.glb"
const SETTLEMENT_MAX_M := 24.0  ## settlement models keep natural scale up to this width (fits settlement_clearance)
const HALL_M := 11.0  ## a home sector shows its faction's main hall this wide instead of a settlement
const MOVE_MIN_MS := 0.25  ## slower than this (m/s) is not walking (crowd nudges)
const MOVE_HOLD_S := 0.2  ## stops shorter than this keep the walk going
const FLY_LIFT := 2.6
const CORPSE_TIME := 6.0
## Stand-in building and settlement sprites are drawn this much larger than their
## footprint so they read next to life-size 3D units.
const ART_SCALE := 1.5
const HIT_FLASH_S := 0.06  ## a struck figure flashes white this long...
const HIT_FADE_S := 0.26  ## ...then flushes red until this

var sk: Skirmish
var world: SimWorld
var field: TerrainField
var scene: MapScene3D
var camera: Camera3D
var overlay: Control
var _units: Dictionary = {}  ## id -> {root, body, su, ring, sprite, h, ...}
var _corpses: Array = []  ## {root, t}
var _buildings: Dictionary = {}  ## id -> {root, sprite, ring}
var _sectors: Dictionary = {}  ## id -> {sprite, ring, ring_mat, size, owner}
var _nodes: Dictionary = {}  ## id -> Sprite3D
## Ink outlines and the living-land ambience over the 3D map (WbSettings.outlines / ambience).
var look: LookFx3D
var _sites: Dictionary = {}  ## site id -> Node3D (lair rocks, shrine stone, merchant stall)
var _ghost: Sprite3D
var _ghost_ring: MeshInstance3D
var _ring_mesh := TorusMesh.new()
var _team_mats: Array = []
var _select_mat: StandardMaterial3D
var _dying: Dictionary = {}  ## unit id -> true, from death events
## Arrows, spells, blood and impacts (see CombatFx3D).
var fx: CombatFx3D


func setup(owner_view: Skirmish) -> void:
	sk = owner_view
	_ring_mesh.inner_radius = 0.9
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 4
	for c in Skirmish.TEAM_COLORS:
		_team_mats.append(_flat_mat(Color(c, 0.9)))
	_select_mat = _flat_mat(Skirmish.SELECT_COLOR)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.5
	camera.far = 900.0
	add_child(camera)
	var cl := CanvasLayer.new()
	cl.layer = 0
	add_child(cl)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	cl.add_child(overlay)
	fx = CombatFx3D.new()
	fx.setup(self)
	add_child(fx)


func _flat_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	return m


## Builds the 3D world for a new game.
func rebuild(w: SimWorld, seed_value: int) -> void:
	world = w
	for d in [_units, _buildings, _sectors, _nodes, _sites]:
		for k in d:
			var v = d[k]
			var n: Node = v["root"] if v is Dictionary else v
			n.queue_free()
		d.clear()
	for c in _corpses:
		c["root"].queue_free()
	_corpses.clear()
	fx.clear()
	if scene != null:
		scene.queue_free()
	field = TerrainField.new()
	SimTerrain.build(field, w, seed_value)
	scene = MapScene3D.create(field, seed_value)
	add_child(scene)
	if look != null:
		look.queue_free()
	WbSettings.ensure_loaded()
	look = LookFx3D.create(scene.atmosphere, WbSettings.outlines, WbSettings.ambience)
	add_child(look)
	_build_borders()
	_ghost = _billboard(null, 1.0 / 32.0)
	_ghost.visible = false
	add_child(_ghost)
	_ghost_ring = _ring(_select_mat)
	_ghost_ring.visible = false
	add_child(_ghost_ring)
	# Fog of war: one decal over the whole map darkens what the player can't see.
	if _fog != null:
		_fog.queue_free()
	# Fog of war: a full-screen pass darkens what the player can't see (see fog_of_war.gdshader).
	_fog = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_fog.mesh = quad
	_fog.extra_cull_margin = 16384.0
	_fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = load("res://src/ui/fog_of_war.gdshader")
	_fog_mat.set_shader_parameter("map_size", w.nav.world_size() / TerrainField.PX)
	_fog_mat.set_shader_parameter("grey_ref", Skirmish.FOG_GREY.r)
	_fog_mat.set_shader_parameter("gl_depth", RenderingServer.get_current_rendering_method() == "gl_compatibility")
	_fog_mat.render_priority = Material.RENDER_PRIORITY_MAX  # after water and rings
	_fog.material_override = _fog_mat
	add_child(_fog)


# --- Coordinates ---------------------------------------------------------------

func ground(p_sim: Vector2, lift: float = 0.0) -> Vector3:
	var m := TerrainField.to_world(p_sim)
	return Vector3(m.x, field.height_at(m.x, m.y) + lift, m.y)


func sim_to_screen(p_sim: Vector2, lift: float = 0.0) -> Vector2:
	return camera.unproject_position(ground(p_sim, lift))


func on_screen(p_sim: Vector2, lift: float = 0.0) -> bool:
	return not camera.is_position_behind(ground(p_sim, lift))


## The ground point under a screen position, in sim pixels.
func screen_to_sim(sp: Vector2) -> Vector2:
	var o := camera.project_ray_origin(sp)
	var d := camera.project_ray_normal(sp)
	if absf(d.y) < 0.001:
		return TerrainField.to_sim(Vector2(o.x, o.z))
	var h := 0.0
	var hit := Vector3.ZERO
	for i in 4:  # settle onto the heightmap
		var t := (h - o.y) / d.y
		hit = o + d * t
		h = field.height_at(hit.x, hit.z)
	return TerrainField.to_sim(Vector2(hit.x, hit.z))


## What the camera sees of the ground, as a sim-pixel rectangle.
func view_rect() -> Rect2:
	var s := get_viewport().get_visible_rect().size
	var r := Rect2(screen_to_sim(Vector2.ZERO), Vector2.ZERO)
	for c in [Vector2(s.x, 0), Vector2(0, s.y), s]:
		r = r.expand(screen_to_sim(c))
	return r


## Sim pixels per screen pixel at the camera target (for drag panning).
func sim_per_pixel() -> float:
	var dist := camera.global_position.distance_to(ground(sk.cam.position))
	var metres := 2.0 * dist * tan(deg_to_rad(FOV * 0.5)) / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	return metres * TerrainField.PX


## Whether a screen point falls on an upright billboard of this size standing at p_sim.
func billboard_hit(p_sim: Vector2, width_m: float, height_m: float, sp: Vector2) -> bool:
	if not on_screen(p_sim):
		return false
	var foot := sim_to_screen(p_sim)
	var top := sim_to_screen(p_sim, height_m)
	var half := absf(foot.y - top.y) * width_m / maxf(height_m, 0.01) * 0.5
	return sp.x > foot.x - half and sp.x < foot.x + half and sp.y > top.y and sp.y < foot.y + 6.0


## The unit drawn at screen point sp; the workers of skip_workers_of (a player, -1: none)
## are passed by, so a click on one falls through to what is behind or under it.
func unit_at_screen(sp: Vector2, skip_workers_of: int = -1) -> SimUnit:
	var best: SimUnit = null
	var best_d := INF
	for u in world.units:
		if not sk.can_see(u) or (u.owner == skip_workers_of and u.is_worker()):
			continue
		var e: Dictionary = _units.get(u.id, {})
		var h: float = e.get("h", 1.8)
		var lift := FLY_LIFT if u.is_flying() else 0.0
		var foot := sim_to_screen(sk._draw_pos(u), lift)
		var head := sim_to_screen(sk._draw_pos(u), lift + h)
		var mid := (foot + head) * 0.5
		var r := maxf(absf(foot.y - head.y) * 0.55, 10.0)
		var d := mid.distance_to(sp)
		if d < r and d < best_d:
			best_d = d
			best = u
	return best


# --- Frame update --------------------------------------------------------------

func on_event(e: Dictionary) -> void:
	if e["type"] == "death":
		_dying[int(e["unit"])] = true
		if bool(_units.get(int(e["unit"]), {}).get("asc", false)):
			return  # an Ascendant leaves no blood: it burns away in light (_ascend_away)
	if sk.mode_3d:
		fx.on_event(e)


## The type of a unit the view shows (also one that died this tick), or "".
func unit_type(id: int) -> String:
	return String(_units.get(id, {}).get("type", ""))


## A point on a unit's body as shown (0 = feet, 1 = top of the head), or Vector3.INF
## when the view has no body for it.
func unit_point(id: int, frac: float) -> Vector3:
	var e: Dictionary = _units.get(id, {})
	if e.is_empty():
		var st := world.get_unit(id)
		if st != null and st.is_structure():
			return ground(st.pos, 2.6 * frac)  # a wall piece: the face of the stones
		return Vector3.INF
	var root: Node3D = e["root"]
	var body: Node3D = e["body"]
	return root.position + Vector3(0.0, body.position.y + float(e["h"]) * frac, 0.0)


func update(delta: float) -> void:
	var target := ground(sk.cam.position)
	target.y = maxf(target.y, 0.0)
	var dist := BASE_DIST / sk.cam.zoom.x
	var pitch := deg_to_rad(pitch_for(sk.cam.zoom.x))
	var dir := Vector3(0.0, sin(pitch), cos(pitch))
	camera.global_position = target + dir * dist
	camera.look_at(target, Vector3.UP)
	if scene.atmosphere != null:
		scene.atmosphere.set_biome(field.biome_at(Vector2(target.x, target.z)))
	if look != null:
		look.follow(target)
	_sync_fog()
	_sync_units(delta)
	_sync_sectors()
	_sync_buildings()
	_sync_nodes()
	_sync_sites()
	_sync_ghost()
	fx.update(delta)
	for c in _corpses:
		c["t"] += delta
		if c.has("fade"):
			# An Ascendant burning away into light, then gone (no body is left).
			(c["fade"] as SpriteUnit).set_dissolve(c["t"] / ASC_FADE)
			var light: OmniLight3D = c["light"]
			light.light_energy = 1.2 * maxf(0.0, 1.0 - c["t"] / (ASC_FADE + 0.4))
			if c["t"] >= ASC_FADE + 0.4:
				c["t"] = CORPSE_TIME
			continue
		if c["t"] > CORPSE_TIME - 1.5:
			c["root"].position.y -= delta * 0.4
	for c in _corpses.filter(func(c): return c["t"] >= CORPSE_TIME):
		c["root"].queue_free()
	_corpses = _corpses.filter(func(c): return c["t"] < CORPSE_TIME)
	overlay.queue_redraw()


## The tint of a figure just struck: a white-hot flash, then a red flush fading out.
static func hit_tint(since_hit: float) -> Color:
	if since_hit < HIT_FLASH_S:
		return Color(2.3, 2.1, 1.9)
	if since_hit < HIT_FADE_S:
		var k := (HIT_FADE_S - since_hit) / (HIT_FADE_S - HIT_FLASH_S)
		return Color(1.0 + 0.8 * k, 1.0 - 0.2 * k, 1.0 - 0.2 * k)
	return Color.WHITE


## Camera pitch in degrees at a zoom (Skirmish.ZOOM_MIN..ZOOM_MAX).
static func pitch_for(zoom: float) -> float:
	var t := clampf((zoom - Skirmish.ZOOM_MIN) / (Skirmish.ZOOM_MAX - Skirmish.ZOOM_MIN), 0.0, 1.0)
	return lerpf(PITCH_FAR, PITCH_NEAR, pow(t, 0.7))


func _billboard(tex: Texture2D, pixel: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = pixel
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = false
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.centered = true
	return s


## A static 3D model scaled so its footprint is width_m across, or null when the
## model does not exist yet (the billboard sprite stays then).
## natural: width_m is only a cap and the model keeps its own origin (a settlement's
## origin is the centre of its square).
func _static_model(path: String, width_m: float, natural: bool = false) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var n: Node3D = (load(path) as PackedScene).instantiate()
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != n:
			if cur is Node3D:
				t = (cur as Node3D).transform * t
			cur = cur.get_parent()
		var b := t * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var holder := Node3D.new()
	holder.add_child(n)
	if not first:
		var k := width_m / maxf(maxf(box.size.x, box.size.z), 0.01)
		if natural:
			k = minf(1.0, k)  # width_m is only a cap
		holder.scale = Vector3.ONE * k
		holder.set_meta("height_m", box.size.y * k)
		n.position = Vector3(0.0 if natural else -box.get_center().x, -box.position.y,
			0.0 if natural else -box.get_center().z)
	return holder


## A tall pole with a gold-trimmed flag in the owner's colour beside an upgraded dwelling.
func _upgrade_banner(b: Building) -> Node3D:
	var root := Node3D.new()
	var r := b.radius * 0.95 / TerrainField.PX
	root.position = Vector3(-r * 0.7, 0.0, r * 0.7)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.09
	pm.height = 6.0
	pole.mesh = pm
	pole.position.y = 3.0
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.22, 0.16, 0.1)
	wood.roughness = 0.95
	pole.material_override = wood
	root.add_child(pole)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(1.4, 1.0, 0.05)
	flag.mesh = fm
	flag.position = Vector3(0.72, 5.3, 0.0)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Skirmish.TEAM_COLORS[b.owner].darkened(0.15)
	cloth.roughness = 0.9
	flag.material_override = cloth
	root.add_child(flag)
	var trim := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(1.4, 0.16, 0.07)
	trim.mesh = tm
	trim.position = Vector3(0.72, 4.82, 0.0)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Skirmish.UPGRADE_COLOR
	gold.metallic = 0.6
	gold.roughness = 0.5
	trim.material_override = gold
	root.add_child(trim)
	return root


func _ring(mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _new_unit(u: SimUnit) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var body := Node3D.new()
	root.add_child(body)
	var e := {"root": root, "body": body, "sprite": null, "su": null, "h": 1.8, "action": "", "type": u.type_id,
		"asc": u.is_ascendant()}
	var su := _spawn_sprite_unit(u)
	var r_m := u.radius() / TerrainField.PX
	if su != null and u.is_ascendant():
		root.add_child(_ascendant_aura(r_m, su.height))
	if su != null:
		body.add_child(su)
		e["su"] = su
		e["h"] = su.height
		# Painted sprites cast no real shadow: a soft dark blob grounds them.
		var blob := MeshInstance3D.new()
		blob.mesh = _blob_mesh()
		blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blob.scale = Vector3.ONE * maxf(r_m * 2.4, su.height * 0.45)
		blob.position.y = 0.04
		root.add_child(blob)
	else:
		# No animation sheet: the unit's still sprite, as tall as the 2D view draws it.
		var h := u.radius() * 0.2
		var tex := sk.unit_texture(u.type_id)
		var s := _billboard(tex, h / 128.0)
		s.offset = Vector2(0, 64)
		body.add_child(s)
		e["sprite"] = s
		e["h"] = h
	var ring := _ring(_team_mats[u.owner])
	ring.scale = Vector3(r_m * 1.15, 1.0, r_m * 1.15)
	ring.position.y = 0.06
	root.add_child(ring)
	e["ring"] = ring
	return e


## The unit's animated battle sprite (the sheet of its still sprite). A hero has its own
## class sheet, baked from its 3D body (tools/bake_hero_sprites.py); until one exists it
## shows the unit it stands in for, a little larger. Workers have their own sheets (a
## worker without one would show its still sprite's sheet, smaller).
func _spawn_sprite_unit(u: SimUnit) -> SpriteUnit:
	var def: Dictionary = world.catalog.get_unit(u.type_id)
	var id := String(def.get("sprite", "")).get_file().get_basename()
	var k := 1.0
	if def.get("hero", false):
		var own := "hero_%s" % def.get("class", "")
		if SpriteUnit.exists(own):
			id = own
		else:
			k = SPRITE_HERO_SCALE
	elif u.is_worker():
		if SpriteUnit.exists(u.type_id):
			id = u.type_id  # the worker's own body, baked from its 3D model at its own size
		else:
			k = WORKER_SCALE
	var asc := u.is_ascendant() and SpriteUnit.exists(ASC_PREFIX + id)
	if asc:
		id = ASC_PREFIX + id  # the main game's level-five art (tools/sync_ascendant_anims.py)
	var su := SpriteUnit.spawn(id, k)
	if su != null:
		su.face(u.facing >= 0)
		if u.is_ascendant():
			su.set_ascendant(true)
	return su


const ASC_PREFIX := "asc_"
const ASC_GLOW := Color(1.0, 0.8, 0.38)
## Seconds an Ascendant takes to burn away into light when it falls.
const ASC_FADE := 1.8
var _asc_disc: QuadMesh


## The soft aura round an Ascendant's feet: a pulsing golden glow on the ground and a few
## motes of light drifting up past it. Named "aura" so the view can find and stop it.
func _ascendant_aura(r_m: float, h: float) -> Node3D:
	var aura := Node3D.new()
	aura.name = "aura"
	if _asc_disc == null:
		_asc_disc = QuadMesh.new()
		_asc_disc.size = Vector2.ONE
		_asc_disc.orientation = PlaneMesh.FACE_Y
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec3 glow : source_color = vec3(1.0, 0.8, 0.38);
void fragment() {
	float d = length((UV - 0.5) * 2.0);
	float pulse = 0.75 + 0.25 * sin(TIME * 2.6);
	float ring = smoothstep(1.0, 0.75, d) * smoothstep(0.35, 0.8, d);
	ALBEDO = glow * (0.35 * (1.0 - smoothstep(0.0, 1.0, d)) + 0.55 * ring) * pulse;
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		_asc_disc.material = m
	var disc := MeshInstance3D.new()
	disc.name = "disc"
	disc.mesh = _asc_disc
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.scale = Vector3.ONE * maxf(r_m * 3.2, h * 0.7)
	disc.position.y = 0.05
	aura.add_child(disc)
	var motes := CPUParticles3D.new()
	motes.name = "motes"
	motes.mesh = CombatFx3D._quad(true)
	motes.amount = 10
	motes.lifetime = 1.8
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	motes.emission_ring_axis = Vector3.UP
	motes.emission_ring_radius = maxf(r_m * 1.3, 0.35)
	motes.emission_ring_inner_radius = maxf(r_m * 0.6, 0.15)
	motes.emission_ring_height = 0.1
	motes.direction = Vector3.UP
	motes.spread = 12.0
	motes.gravity = Vector3(0.0, 0.5, 0.0)
	motes.initial_velocity_min = 0.25
	motes.initial_velocity_max = 0.6
	motes.scale_amount_min = 0.04
	motes.scale_amount_max = 0.08
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.7, 0.0))
	g.add_point(0.2, Color(1.0, 0.9, 0.55, 0.9))
	g.set_color(g.get_point_count() - 1, Color(ASC_GLOW, 0.0))
	motes.color_ramp = g
	motes.position.y = 0.1
	aura.add_child(motes)
	return aura


## A unit changed form (a veteran promotion) or turned Ascendant: a new body in its place.
func _rebuild_body(u: SimUnit, e: Dictionary) -> void:
	var root: Node3D = e["root"]
	(e["root"] as Node).queue_free()
	var fresh := _new_unit(u)
	(fresh["root"] as Node3D).position = root.position
	for k in fresh:
		e[k] = fresh[k]
	if u.is_ascendant():
		var at := root.position + Vector3(0.0, float(e["h"]) * 0.5, 0.0)
		fx.ring_burst(root.position, "holy", 0.8, true)
		fx.element_burst(at, "holy", 1.4)


const SPRITE_HERO_SCALE := 1.15
var _blob: QuadMesh


## A 1 m soft round shadow lying on the ground (shared by all sprite units).
func _blob_mesh() -> QuadMesh:
	if _blob == null:
		_blob = QuadMesh.new()
		_blob.size = Vector2(1.0, 0.6)
		_blob.orientation = PlaneMesh.FACE_Y
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;
void fragment() {
	float d = length((UV - 0.5) * 2.0);
	ALBEDO = vec3(0.0);
	ALPHA = 0.55 * (1.0 - smoothstep(0.35, 1.0, d));
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		_blob.material = m
	return _blob


## Workers borrow a soldier's art, so they are drawn smaller, carry their load on the
## shoulder and swing their tool at the pile.
const WORKER_SCALE := 0.72
const CARRY_M := 0.5


func _sync_carry(u: SimUnit, e: Dictionary) -> void:
	var want := u.carry_type if u.carry_amount > 0 else ""
	if String(e.get("carry", "")) == want:
		return
	if e.get("carry_node") != null:
		(e["carry_node"] as Node).queue_free()
		e["carry_node"] = null
	e["carry"] = want
	if want == "":
		return
	var m := _static_model(RESOURCES3D % want, CARRY_M)
	if m == null:
		return
	var body: Node3D = e["body"]
	m.position = Vector3(0.0, float(e["h"]) / maxf(body.scale.y, 0.01) * 0.92, 0.0)
	m.rotation.y = float(u.id % 7)
	body.add_child(m)
	e["carry_node"] = m


var _fog: MeshInstance3D
var _fog_mat: ShaderMaterial


func _sync_fog() -> void:
	if _fog == null:
		return
	_fog.visible = sk.fog_enabled
	if sk.fog_enabled:
		_fog_mat.set_shader_parameter("fog", sk.fog_texture())


func _sync_units(delta: float) -> void:
	var alpha := sk._alpha()
	var seen := {}
	for u in world.units:
		seen[u.id] = true
		if not _units.has(u.id):
			_units[u.id] = _new_unit(u)
		var e: Dictionary = _units[u.id]
		if String(e["type"]) != u.type_id or bool(e.get("asc", false)) != u.is_ascendant():
			_rebuild_body(u, e)
		var p := u.prev_pos.lerp(u.pos, alpha)
		var root: Node3D = e["root"]
		root.position = ground(p) + Vector3(0.0, TOWER_TOP_M if u.garrison_of >= 0 else 0.0, 0.0)
		root.visible = sk.can_see(u)
		var body: Node3D = e["body"]
		body.position.y = FLY_LIFT + sin(sk._time * 3.0 + u.id) * 0.15 if u.is_flying() else 0.0
		(e["ring"] as MeshInstance3D).material_override = _select_mat if u.id in sk.selection else _team_mats[u.owner]
		# While the world waits (pause, a conversation) nobody moves, though the last tick's
		# step is still in prev_pos.
		var step := u.pos - u.prev_pos if sk.sim_running() else Vector2.ZERO
		# Walk only above a real pace, and keep walking briefly through short stops, so
		# units nudged by crowding don't flip between walk and idle every tick.
		var speed_m := step.length() / world.dt / TerrainField.PX
		var moving: bool = e.get("moving", false)
		if speed_m >= MOVE_MIN_MS:
			moving = true
			e["still"] = 0.0
		else:
			e["still"] = float(e.get("still", 0.0)) + delta
			if float(e["still"]) > MOVE_HOLD_S:
				moving = false
		e["moving"] = moving
		e["speed"] = lerpf(float(e.get("speed", speed_m)), speed_m, minf(1.0, delta * 8.0))
		var su: SpriteUnit = e["su"]
		if su != null:
			_sync_sprite_unit(u, e, su, step, moving)
		if u.is_worker():
			_sync_carry(u, e)
		if su == null:
			var s: Sprite3D = e["sprite"]
			s.flip_h = u.facing < 0
			s.modulate = hit_tint(u.since_hit)
			s.position.x = u.facing * 0.12 if u.since_attack < 0.12 else 0.0
	for id in _units.keys():
		if seen.has(id):
			continue
		var e: Dictionary = _units[id]
		_units.erase(id)
		if _dying.has(id):
			_dying.erase(id)
			(e["ring"] as Node).queue_free()
			var su: SpriteUnit = e["su"]
			if su != null and bool(e.get("asc", false)):
				_ascend_away(e, su)
				continue
			if su != null and su.has_clip("death"):
				su.modulate = Color.WHITE
				su.die()
			elif su != null:
				su.die()
				su.modulate = Color(0.45, 0.4, 0.4)
				su.lay_flat()
			else:
				var s: Sprite3D = e["sprite"]
				s.modulate = Color(0.35, 0.3, 0.3)
				s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
				s.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
				s.position.y = 0.05
			_corpses.append({"root": e["root"], "t": 0.0})
		else:
			(e["root"] as Node).queue_free()


## An Ascendant does not fall: its aura flares, a column of golden light rises and the
## figure burns away into it, pixel by pixel (SpriteUnit.set_dissolve), leaving nothing.
func _ascend_away(e: Dictionary, su: SpriteUnit) -> void:
	var root: Node3D = e["root"]
	su.play("idle")
	su.set_process(false)  # holds its last pose while it fades
	var aura := root.get_node_or_null("aura")
	if aura != null:
		(aura.get_node("motes") as CPUParticles3D).emitting = false
		var disc := aura.get_node("disc") as Node3D
		disc.scale *= 1.4
	var h := float(e["h"])
	var light := OmniLight3D.new()
	light.light_color = ASC_GLOW
	light.light_energy = 1.2
	light.omni_range = maxf(3.0, h * 2.0)
	light.position.y = h * 0.6
	light.shadow_enabled = false
	root.add_child(light)
	fx.ring_burst(root.position, "holy", 0.9, true)
	var rise := fx.element_burst(root.position + Vector3(0.0, h * 0.5, 0.0), "holy", 0.9)
	if rise != null:
		rise.lifetime = 1.6
		rise.gravity = Vector3(0.0, 1.6, 0.0)
	_corpses.append({"root": root, "t": 0.0, "fade": su, "light": light})


## Which way the art faces (by the screen direction of the walk or of the
## foe being struck) and which clip runs.
func _sync_sprite_unit(u: SimUnit, e: Dictionary, su: SpriteUnit, step: Vector2, moving: bool) -> void:
	var face := step
	var tgt := world.get_unit(u.target_id) if u.target_id >= 0 else null
	if tgt != null and u.since_attack < 1.0:
		face = tgt.pos - u.pos
	var stats := world.catalog.get_unit(u.type_id)
	var interval := float(stats["attack_interval"])
	var fighting := tgt != null and u.since_attack < interval + 0.6 and not moving
	var working := u.is_worker() and not moving and ((u.order == SimUnit.Order.GATHER and u.gather_timer > 0.0
			and u.carry_amount == 0) or u.order == SimUnit.Order.BUILD)
	if working and u.order == SimUnit.Order.GATHER:
		var n := world.economy.node(u.job)
		if n != null:
			face = n.pos - u.pos
	if face.length() > 0.01:
		var side := Vector3(face.x, 0.0, face.y).dot(camera.global_basis.x)
		# A little dead zone, so a unit walking straight up or down the screen keeps its side.
		if absf(side) > 0.2 * face.length():
			su.face(side > 0.0)
	# A new blow: since_attack drops back to zero when the sim strikes.
	var last := float(e.get("since_attack", 99.0))
	e["since_attack"] = u.since_attack
	if u.since_attack < last and u.since_attack < 0.1:
		su.strike(interval)
	elif working:
		if not su.busy():
			su.strike(1.0)
	elif su.busy() and su.action == "attack":
		pass  # let the blow finish
	elif moving:
		su.walk(maxf(float(e["speed"]), MOVE_MIN_MS))
	elif not fighting or not su.busy():
		su.play("idle")
	su.modulate = hit_tint(u.since_hit)


func _sync_sectors() -> void:
	var eco := world.economy
	var cr := float(eco.e["capture_radius"]) / TerrainField.PX
	for sec in eco.sectors:
		if not _sectors.has(sec.id):
			var root := Node3D.new()
			add_child(root)
			var s := _billboard(null, ART_SCALE / TerrainField.PX)
			root.add_child(s)
			var mat := _flat_mat(Color(1, 1, 1, 0.5))
			var ring := _ring(mat)
			ring.scale = Vector3(cr, 1.0, cr)
			ring.position.y = 0.07
			root.add_child(ring)
			_sectors[sec.id] = {"root": root, "sprite": s, "ring": ring, "mat": mat, "size": "", "owner": -9}
		var e: Dictionary = _sectors[sec.id]
		(e["root"] as Node3D).position = ground(sec.center)
		# The capital is the faction's main hall while its founder holds it. A settlement
		# never explored looks unclaimed (the skirmish shows that land greyed out).
		var known := TacticalMap.known_owner(sk, sec)
		var hall := ""
		if sec.home_of >= 0 and known >= 0 and known == sec.home_of:
			hall = String(eco.e["buildings"][eco.player(known).faction]["hall"])
		var shown := hall if hall != "" else sec.size
		if e["size"] != shown:
			e["size"] = shown
			var tex := sk._tex_at("res://assets/buildings/%s.png" % hall if hall != "" else "res://assets/settlements/%s.png" % sec.size)
			var s: Sprite3D = e["sprite"]
			s.texture = tex
			if tex != null:
				s.offset = Vector2(0, tex.get_height() * 0.3)
			if e.has("model"):
				(e["model"] as Node).queue_free()
				e.erase("model")
			var model := _static_model(BUILDINGS3D % hall, HALL_M) if hall != "" \
				else _static_model(SETTLEMENTS3D % sec.size, SETTLEMENT_MAX_M, true)
			s.visible = model == null
			if model != null:
				(e["root"] as Node3D).add_child(model)
				e["model"] = model
		var col: Color = Color(0.8, 0.75, 0.55, 0.35) if known < 0 else Color(Skirmish.TEAM_COLORS[known], 0.5)
		if sec.id == sk.selected_sector:
			col = Skirmish.SELECT_COLOR
		(e["mat"] as StandardMaterial3D).albedo_color = col


func _sync_buildings() -> void:
	var seen := {}
	for b in world.economy.buildings:
		seen[b.id] = true
		if b.is_fort():
			_sync_fort(b)
			continue
		if not _buildings.has(b.id):
			var root := Node3D.new()
			add_child(root)
			var tex := sk._tex_at("res://assets/buildings/%s.png" % b.key)
			var w_px := b.radius * 2.6
			var s := _billboard(tex, (w_px / float(tex.get_width()) if tex != null else 1.0) * ART_SCALE / TerrainField.PX)
			if tex != null:
				s.offset = Vector2(0, tex.get_height() * 0.32)
			root.add_child(s)
			var model := _static_model(BUILDINGS3D % b.key, w_px / TerrainField.PX)
			if model != null:
				s.visible = false
				root.add_child(model)
			var ring := _ring(_team_mats[b.owner])
			var r := b.radius * 1.1 / TerrainField.PX
			ring.scale = Vector3(r, 1.0, r)
			ring.position.y = 0.07
			root.add_child(ring)
			_buildings[b.id] = {"root": root, "sprite": s, "ring": ring, "model": model,
				"w_m": w_px / TerrainField.PX, "progress": b.progress, "work": 0.0}
		var e: Dictionary = _buildings[b.id]
		_sync_construction(b, e)
		if b.upgraded and not e.has("banner"):
			e["banner"] = _upgrade_banner(b)
			(e["root"] as Node3D).add_child(e["banner"])
		(e["root"] as Node3D).position = ground(b.pos)
		(e["root"] as Node3D).visible = b.owner == sk.PLAYER or sk.has_explored(b.pos)
		(e["sprite"] as Sprite3D).modulate = Color.WHITE if b.done() else Color(0.8, 0.75, 0.6, 0.35 + 0.5 * b.progress)
		(e["ring"] as MeshInstance3D).material_override = _select_mat if b.id == sk.selected_building \
			else _team_mats[b.owner]
	for id in _buildings.keys():
		if not seen.has(id):
			(_buildings[id]["root"] as Node).queue_free()
			_buildings.erase(id)


## A building going up: scaffolding round it, the model rising out of the ground with the
## work, dust and wood chips while builders are at it (ConstructionFx3D), and a cloud of
## dust when it is finished. A building placed finished (a start hall's dwellings) has none.
func _sync_construction(b: Building, e: Dictionary) -> void:
	var dt := get_process_delta_time()
	if b.progress > float(e["progress"]) + 0.00001:
		e["work"] = ConstructionFx3D.WORK_HOLD
	else:
		e["work"] = maxf(0.0, float(e["work"]) - dt)
	e["progress"] = b.progress
	var model: Node3D = e.get("model")
	var height := float(model.get_meta("height_m", 3.0)) if model != null else float(e["w_m"]) * 0.7
	if not b.done():
		if not e.has("site"):
			e["site"] = ConstructionFx3D.site(float(e["w_m"]), height, b.id)
			(e["root"] as Node3D).add_child(e["site"])
		ConstructionFx3D.sync_site(e["site"], b.progress, float(e["work"]) > 0.0, sk._time)
		if model != null:
			model.position.y = ConstructionFx3D.rise(b.progress, height)
	elif e.has("site"):
		(e["site"] as Node).queue_free()
		e.erase("site")
		if model != null:
			model.position.y = 0.0
		if (e["root"] as Node3D).visible:
			fx.dust_burst(ground(b.pos, 0.2), ConstructionFx3D.DUST, float(e["w_m"]) * 0.45)


## A wall piece, gate or tower: the Tripo model stretched along the piece (a box when the
## model is missing), on a thin strip in the owner's colour. Rebuilt when the kind changes.
func _sync_fort(b: Building) -> void:
	var e: Dictionary = _buildings.get(b.id, {})
	if e.is_empty() or e["kind"] != b.kind:
		if not e.is_empty():
			(e["root"] as Node).queue_free()
		e = _new_fort(b)
		_buildings[b.id] = e
	var root: Node3D = e["root"]
	root.position = ground(b.pos)
	root.visible = b.owner == sk.PLAYER or sk.has_explored(b.pos)
	var body: Node3D = e["body"]
	# A site rises as it is built.
	body.scale.y = lerpf(0.25, 1.0, b.progress) * float(e["sy"])
	(e["strip"] as MeshInstance3D).material_override = _select_mat if b.id == sk.selected_building \
		else _team_mats[b.owner]
	var door: Node3D = e.get("door")
	if door != null:
		door.position.y = lerpf(door.position.y, -2.5 if b.gate_open else 0.0, 0.25)


func _new_fort(b: Building) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	root.rotation.y = -atan2(b.axis.y, b.axis.x)
	var len_m := b.length / TerrainField.PX
	var body := Node3D.new()
	root.add_child(body)
	var sy := 1.0
	var out := {"root": root, "body": body, "kind": b.kind, "sprite": Sprite3D.new()}
	if b.kind == "tower":
		var m := _static_model(FORTS3D % "fort_tower", TOWER_WIDTH_M)
		if m != null:
			m.scale *= 1.25
			body.add_child(m)
		else:
			body.add_child(_solid(Vector3(TOWER_WIDTH_M, 5.5, TOWER_WIDTH_M), Color(0.3, 0.29, 0.28), Vector3(0, 2.75, 0)))
	elif b.kind == "gate":
		# A low gatehouse: the tower model, shorter, with a timber door in its arch that sinks
		# into the ground while the gate stands open. The arch faces across the wall.
		var m := _static_model(FORTS3D % "fort_tower", TOWER_WIDTH_M)
		if m != null:
			m.scale = Vector3(m.scale.x, m.scale.y * 0.75, m.scale.z)
			body.add_child(m)
		else:
			body.add_child(_solid(Vector3(len_m, 3.4, 1.6), Color(0.33, 0.31, 0.29), Vector3(0, 1.7, 0)))
		var door := Node3D.new()
		for z in [-1.0, 1.0]:
			door.add_child(_solid(Vector3(1.1, 1.9, 0.12), Color(0.24, 0.15, 0.08), Vector3(0, 0.95, z * TOWER_WIDTH_M * 0.47)))
			for y in [0.5, 1.4]:
				door.add_child(_solid(Vector3(1.15, 0.1, 0.16), Color(0.1, 0.1, 0.11), Vector3(0, y, z * TOWER_WIDTH_M * 0.47)))
		body.add_child(door)
		out["door"] = door
	else:
		var m := _static_model(FORTS3D % "fort_wall", 4.0)
		if m != null:
			# The model is 4 m long on X: stretch it to the piece, raise and thicken it.
			m.scale = Vector3(m.scale.x * len_m / 4.0, m.scale.y * WALL_HEIGHT_K, m.scale.z * WALL_DEPTH_K)
			body.add_child(m)
		else:
			body.add_child(_solid(Vector3(len_m, 2.8, 1.0), Color(0.3, 0.29, 0.28), Vector3(0, 1.4, 0)))
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(len_m if b.kind != "tower" else TOWER_WIDTH_M, 0.04, 1.3 if b.kind != "tower" else TOWER_WIDTH_M)
	strip.mesh = sm
	strip.position.y = 0.04
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(strip)
	out["strip"] = strip
	out["sy"] = sy
	return out


func _sync_nodes() -> void:
	for n in world.economy.nodes:
		if not _nodes.has(n.id):
			var root := Node3D.new()
			add_child(root)
			var model := _static_model(RESOURCES3D % n.resource, 1.6, true)
			if model != null:
				model.rotation.y = float(n.id * 37 % 360) * PI / 180.0
				root.add_child(model)
			else:
				var tex := sk._tex_at("res://assets/resources/%s.png" % n.resource)
				var sp := _billboard(tex, 0.62 / TerrainField.PX)
				sp.offset = Vector2(0, 30)
				root.add_child(sp)
			# Piles this player cannot use sit on a grey ring; usable ones on a gold ring.
			var usable := world.economy.uses(Skirmish.PLAYER, n.resource)
			var ring := _ring(_flat_mat(Color(0.95, 0.8, 0.35, 0.7) if usable else Color(0.4, 0.4, 0.4, 0.5)))
			ring.scale = Vector3(0.9, 1.0, 0.9)
			ring.position.y = 0.05
			root.add_child(ring)
			_nodes[n.id] = root
		var r: Node3D = _nodes[n.id]
		r.position = ground(n.pos)
		# A pile shrinks as it is worked and is gone once empty.
		r.visible = not n.depleted()
		if not n.endless():
			var k := 0.55 + 0.45 * n.fraction()
			r.scale = Vector3(k, k, k)


## A monster lair dressed for the land it stands in: the biome's own dead tree and boulders
## (snowy, mossy, charred...) round a ruined den, which grows with the tier: bones and a
## trap at tier 1, a broken wall and a torch at 2, a gothic gate and an old statue at 3.
## Ruins are Quaternius CC0 (assets/props3d/ru_*, tools/nature/convert_scenery.py).
func _build_lair(root: Node3D, st: Dictionary) -> void:
	var id: int = st["id"]
	var tier := int(st["tier"])
	var sc: Dictionary = Biomes.get_biome(field.biome_at(TerrainField.to_world(st["pos"]))).get("scenery", {})
	var deads: Array = sc.get("dead", ["dead_tree_1", "dead_tree_3", "dead_tree_4"])
	var rocks: Array = sc.get("rocks", ["rock_1", "rock_2", "rock_3", "rock_4", "rock_5"])
	var tree := _static_model(NATURE3D % deads[id % deads.size()], 2.6)
	if tree != null:
		tree.position = Vector3(-1.2, 0.0, -1.0)
		root.add_child(tree)
	var n := 3 + tier
	for i in n:
		var rock := _static_model(NATURE3D % rocks[(id + i) % rocks.size()], 1.1 + 0.3 * float(i % 2))
		if rock != null:
			var a := TAU * float(i) / float(n) + 0.3
			rock.position = Vector3(cos(a), 0.0, sin(a)) * (2.6 + 0.3 * float(tier))
			rock.rotation.y = a * 2.0
			root.add_child(rock)
	# [model, width m, x, z, yaw degrees, from tier]
	var parts := [["dn_bones", 0.9, 0.8, 0.9, 30.0, 1], ["dn_skull", 0.45, -0.4, 1.3, 200.0, 1],
		["ru_bear_trap", 0.8, 1.6, -0.4, 10.0, 1], ["ru_wall_broken", 2.4, 0.6, -1.9, 8.0, 2],
		["ru_torch", 0.35, -1.6, 1.0, 0.0, 2], ["ru_bricks", 1.0, 1.9, 0.9, 40.0, 2],
		["ru_arch", 2.6, 0.0, -2.2, 0.0, 3], ["ru_statue_stag", 1.0, 2.2, -1.5, -30.0, 3],
		["ru_column", 0.7, -2.3, -1.8, 0.0, 3]]
	if tier >= 3:
		parts[3] = ["ru_wall_ivy", 2.8, 1.2, -2.6, 12.0, 2]
	for pt in parts:
		if tier < int(pt[5]):
			continue
		var m := _static_model("res://assets/props3d/%s.glb" % pt[0], float(pt[1]))
		if m != null:
			m.position = Vector3(float(pt[2]), 0.0, float(pt[3]))
			m.rotation.y = deg_to_rad(float(pt[4]))
			root.add_child(m)


## Hero sites from scenery we already have: a lair is a ruined den in its biome's dress,
## a shrine a standing stone, a merchant a small market stall with the peddler. Hidden until explored.
func _sync_sites() -> void:
	for st in world.sites.all:
		var id: int = st["id"]
		if not _sites.has(id):
			var root := Node3D.new()
			add_child(root)
			root.position = ground(st["pos"])
			match st["kind"]:
				"lair":
					_build_lair(root, st)
				"shrine":
					var stone := _static_model(SETTLEMENTS3D % "waystone", 3.2, true)
					if stone != null:
						root.add_child(stone)
				_:
					var stall := _static_model(BUILDINGS3D % "c_market", 4.0)
					if stall != null:
						stall.rotation.y = PI * 0.25
						root.add_child(stall)
					# The travelling peddler minds the stall (sprite baked from his 3D body).
					var peddler := SpriteUnit.spawn("npc_peddler")
					if peddler != null:
						peddler.position = Vector3(1.6, 0.0, 1.4)
						peddler.face(false)
						root.add_child(peddler)
			_sites[id] = root
		var r: Node3D = _sites[id]
		r.visible = sk.has_explored(st["pos"])


func _sync_ghost() -> void:
	var on := not sk._placing.is_empty() and String(sk._placing.get("kind", "")) != "wall"  # walls: drawn in the overlay
	_ghost.visible = on
	_ghost_ring.visible = on
	if not on:
		return
	var eco := world.economy
	var wp := sk._mouse_world()
	var radius := sk.placing_radius()
	var ok := eco.can_place(Skirmish.PLAYER, wp, radius)
	var col := Color(0.4, 1.0, 0.4, 0.6) if ok else Color(1.0, 0.3, 0.25, 0.6)
	var key := sk.placing_key()
	var tex := sk._tex_at("res://assets/buildings/%s.png" % key)
	_ghost.texture = tex
	if tex != null:
		_ghost.pixel_size = radius * 2.6 / float(tex.get_width()) * ART_SCALE / TerrainField.PX
		_ghost.offset = Vector2(0, tex.get_height() * 0.32)
	_ghost.modulate = Color(col, 0.6)
	_ghost.position = ground(wp)
	var r := radius * 1.15 / TerrainField.PX
	_ghost_ring.scale = Vector3(r, 1.0, r)
	_ghost_ring.position = ground(wp, 0.07)
	_ghost_ring.material_override = _flat_mat(col)


## Sector borders draped over the ground as thin dark lines.
func _build_borders() -> void:
	var im := ImmediateMesh.new()
	var lines: PackedVector2Array = sk._border_lines
	if lines.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(0, lines.size() - 1, 2):
		var a := lines[i]
		var b := lines[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 16.0))
		for k in n:
			im.surface_add_vertex(ground(a.lerp(b, float(k) / n), 0.08))
			im.surface_add_vertex(ground(a.lerp(b, float(k + 1) / n), 0.08))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = _flat_mat(Color(0.08, 0.06, 0.04, 0.32))  # a hint, not a fence
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(mi)


# --- Overlay (bars, names, box, markers) ----------------------------------------

## Campaign names over named units, and the quest mark (! or ?) over an NPC who has news.
## The bar over a unit: framed, green for own units, red for enemies, amber for neutrals. Heroes get
## a longer bar with their mana under it and their level beside it.
func _draw_unit_bar(o: CanvasItem, font: Font, u: SimUnit, top: Vector2) -> void:
	var hero := u.is_hero()
	var w := 40.0 if hero else 22.0
	var hgt := 5.0 if hero else 3.5
	var tl := top + Vector2(-w * 0.5, -6)
	var own := u.owner == Skirmish.PLAYER
	var base := Color(0.35, 0.85, 0.3) if own else (Color(0.9, 0.7, 0.25) if u.owner == Economy.NEUTRAL else Color(0.88, 0.25, 0.18))
	var ratio := u.hp_ratio()
	var hc := base
	if own and ratio < 0.35:
		hc = Color(0.95, 0.75, 0.2)
	var full := Rect2(tl, Vector2(w, hgt))
	o.draw_rect(full.grow(1.0), Color(0, 0, 0, 0.85))
	o.draw_rect(full, Color(0.12, 0.08, 0.06, 0.9))
	o.draw_rect(Rect2(tl, Vector2(w * ratio, hgt)), hc)
	o.draw_rect(Rect2(tl, Vector2(w * ratio, 1.0)), Color(1, 1, 1, 0.3))
	if hero and u.hero != null:
		var mr := Rect2(tl + Vector2(0, hgt + 1.0), Vector2(w, 2.0))
		o.draw_rect(mr.grow(1.0), Color(0, 0, 0, 0.85))
		o.draw_rect(Rect2(mr.position, Vector2(w * clampf(u.hero.mana / maxf(u.hero.max_mana, 1.0), 0.0, 1.0), 2.0)),
			Color(0.35, 0.55, 1.0))
		var c := tl + Vector2(-7, hgt * 0.5 + 1.0)
		o.draw_circle(c, 7.0, Color(0, 0, 0, 0.9))
		o.draw_circle(c, 6.0, Color("#6b5530"))
		o.draw_arc(c, 6.0, 0, TAU, 16, Color("#e0b450"), 1.0)
		o.draw_string(font, c + Vector2(-8, 4), str(u.hero.level), HORIZONTAL_ALIGNMENT_CENTER, 16, 10, Color.WHITE)


func _draw_name_and_mark(o: Control, font: Font, u: SimUnit, top: Vector2) -> void:
	var col: Color = Color(0.92, 0.88, 0.75) if u.passive else Skirmish.TEAM_COLORS[u.owner].lightened(0.35)
	if u.label != "":
		var tw := font.get_string_size(u.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		o.draw_string(font, top + Vector2(-tw * 0.5 + 1, -8), u.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.85))
		o.draw_string(font, top + Vector2(-tw * 0.5, -9), u.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	if sk.mission == null or not u.passive:
		return
	var mk := sk.mission.mark(sk.mission.npc_of(u.id))
	if mk == "":
		return
	var bob := sin(sk._time * 3.0) * 2.0
	var p := top + Vector2(0, -30 + bob)
	o.draw_circle(p + Vector2(0, -7), 10.0, Color(0, 0, 0, 0.55))
	var mw := font.get_string_size(mk, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	o.draw_string_outline(font, p + Vector2(-mw * 0.5, 1), mk, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 4, Color(0.1, 0.06, 0.02))
	o.draw_string(font, p + Vector2(-mw * 0.5, 1), mk, HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
		Color(1.0, 0.82, 0.25) if mk == "!" else Color(0.75, 0.9, 1.0))


func _draw_overlay() -> void:
	if world == null:
		return
	var o := overlay
	var font := ThemeDB.fallback_font
	var eco := world.economy
	for sec in eco.sectors:
		if not on_screen(sec.center) or (sec.owner != sk.PLAYER and not sk.has_explored(sec.center)):
			continue
		var p := sim_to_screen(sec.center)
		var st := eco.settlement(sec)
		var title: String = st["name"] if sec.label == "" else sec.label
		if sec.home_of >= 0 and sec.owner == sec.home_of:
			var hk := String(eco.e["buildings"][eco.player(sec.owner).faction]["hall"])
			title = "%s (%s)" % [world.catalog.building_names.get(hk, st["name"]), Skirmish.ROMAN[eco.player(sec.owner).hall_level - 1]]
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var col: Color = Color(0.9, 0.85, 0.7) if sec.owner < 0 else Skirmish.TEAM_COLORS[sec.owner].lightened(0.3)
		if sec.id == sk.selected_sector:
			col = Skirmish.SELECT_COLOR
		o.draw_string(font, p + Vector2(-tw * 0.5 + 1, 31), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.9))
		o.draw_string(font, p + Vector2(-tw * 0.5, 30), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
		var bar := Rect2(p + Vector2(-40, 37), Vector2(80, 5))
		var k := -1.0
		var bc := Color.WHITE
		var hall_st := world.defense.hall_structure(sec)
		if hall_st != null and (hall_st.hp < hall_st.max_hp or sec.id == sk.selected_sector):
			k = hall_st.hp_ratio()  # the capital's strength: it is torn down, never taken
			bc = Skirmish.hall_bar_color(sec.owner)
		elif sec.capture > 0.0 and sec.capturer >= 0:
			k = sec.capture
			bc = Skirmish.TEAM_COLORS[sec.capturer]
		elif sec.unsettled > 0.0:
			k = 1.0 - sec.unsettled / float(eco.e["unsettled_seconds"])
			bc = Color(0.85, 0.75, 0.4)
		elif sec.growing > 0.0:
			k = 1.0 - sec.growing / float(eco.e["settlement_upgrade"]["seconds"])
			bc = Color(0.5, 0.85, 0.4)
		if k >= 0.0:
			o.draw_rect(bar, Color(0, 0, 0, 0.7))
			o.draw_rect(Rect2(bar.position, Vector2(80 * k, 5)), bc)
	for b in eco.buildings:
		if not on_screen(b.pos) or (b.owner != sk.PLAYER and sk.fog_enabled and not world.vision.is_visible(sk.PLAYER, b.pos)):
			continue
		var p := sim_to_screen(b.pos)
		if not b.done():
			var bar := Rect2(p + Vector2(-30, 8), Vector2(60, 5))
			o.draw_rect(bar, Color(0, 0, 0, 0.7))
			o.draw_rect(Rect2(bar.position, Vector2(60 * b.progress, 5)), Color(0.9, 0.75, 0.35))
		elif not b.queue.is_empty():
			o.draw_string(font, p + Vector2(-8, 18), "x%d" % b.queue.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(1, 0.95, 0.8))
		var bst := world.defense.building_structure(b)
		if bst != null and b.done() and (bst.hp < bst.max_hp or b.id == sk.selected_building):
			_draw_unit_bar(o, font, bst, sim_to_screen(b.pos, 4.2))  # a unit building's strength
		if b.is_fort() and b.done():
			var st := world.get_unit(b.structure)
			if st != null and (st.hp < st.max_hp or b.id == sk.selected_building):
				_draw_unit_bar(o, font, st, sim_to_screen(b.pos, 3.4 if b.kind != "tower" else 6.6))
			if b.upgrade_left > 0.0:
				var k := 1.0 - b.upgrade_left / float(world.forts.conf()[b.upgrade_to]["seconds"])
				var bar := Rect2(p + Vector2(-30, 8), Vector2(60, 5))
				o.draw_rect(bar, Color(0, 0, 0, 0.7))
				o.draw_rect(Rect2(bar.position, Vector2(60 * k, 5)), Color(0.75, 0.75, 0.9))
		if b.id == sk.selected_building and (b.kind == "dwelling" or b.kind == "special"):
			o.draw_dashed_line(p, sim_to_screen(b.rally), Color(0.95, 0.85, 0.4, 0.7), 2.0, 8.0)
			o.draw_circle(sim_to_screen(b.rally), 4.0, Color(0.95, 0.85, 0.4))
	# Worked piles: what is left, as a bar and a number.
	for n in eco.nodes:
		if n.endless() or n.depleted() or n.amount >= n.full or not on_screen(n.pos) or not sk.has_explored(n.pos):
			continue
		var p := sim_to_screen(n.pos)
		var bar := Rect2(p + Vector2(-22, 10), Vector2(44, 4))
		var k := n.fraction()
		o.draw_rect(bar, Color(0, 0, 0, 0.7))
		o.draw_rect(Rect2(bar.position, Vector2(44 * k, 4)), Color(0.85, 0.75, 0.4) if k > 0.25 else Color(0.9, 0.4, 0.3))
		o.draw_string(font, p + Vector2(-14, 27), str(n.amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.9, 0.75))
	_draw_wall_plan(o)
	LootMarks.draw_all(o, world, func(q: Vector2) -> Variant: return sim_to_screen(q) if on_screen(q) else null, sk._time)
	SiteMarks.draw_all(o, world, func(q: Vector2) -> Variant: return sim_to_screen(q) if on_screen(q) else null,
		sk.has_explored, 1.0 / maxf(sim_per_pixel(), 0.01), sk._time)
	var cc := {"wood": Color(0.55, 0.38, 0.2), "ore": Color(0.6, 0.6, 0.65), "gems": Color(0.4, 0.9, 0.6),
		"crystal": Color(0.75, 0.85, 1.0), "mercury": Color(0.85, 0.85, 0.9), "sulfur": Color(0.95, 0.85, 0.3)}
	for u in world.units:
		var e: Dictionary = _units.get(u.id, {})
		if e.is_empty() or not sk.can_see(u):
			continue
		var sel := u.id in sk.selection
		var lift := FLY_LIFT if u.is_flying() else (TOWER_TOP_M if u.garrison_of >= 0 else 0.0)
		var p := sk._draw_pos(u)
		if not on_screen(p, lift):
			continue
		var top := sim_to_screen(p, lift + float(e["h"]) + 0.25)
		if u.carry_amount > 0:
			o.draw_circle(top + Vector2(8, 4), 3.5, cc.get(u.carry_type, Color.WHITE))
		if sel or u.hp < u.max_hp or u.is_hero():
			_draw_unit_bar(o, font, u, top)
		if u.label != "" or (sk.mission != null and u.passive):
			_draw_name_and_mark(o, font, u, top)
	for m in sk._markers:
		var k: float = m["t"] / 0.6
		var c := sim_to_screen(m["pos"])
		o.draw_set_transform(c, 0.0, Vector2(1.0, 0.6))
		o.draw_arc(Vector2.ZERO, 6.0 + 14.0 * k, 0, TAU, 20, Color(m["color"], 1.0 - k), 2.0)
		o.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for line: PackedVector2Array in sk.queued_paths():
		for i in range(1, line.size()):
			if on_screen(line[i - 1]) or on_screen(line[i]):
				o.draw_dashed_line(sim_to_screen(line[i - 1]), sim_to_screen(line[i]), Color(Skirmish.SELECT_COLOR, 0.6), 2.0, 10.0)
			if on_screen(line[i]):
				o.draw_circle(sim_to_screen(line[i]), 4.5, Color(Skirmish.SELECT_COLOR, 0.85))
	if sk._box_active:
		var r := Rect2(sk._drag_start_screen, Vector2.ZERO).expand(get_viewport().get_mouse_position())
		o.draw_rect(r, Color(Skirmish.SELECT_COLOR, 0.12), true)
		o.draw_rect(r, Skirmish.SELECT_COLOR, false, 1.5)


## While a wall is being placed: the cells it would cover, green if it can be built.
func _draw_wall_plan(o: Control) -> void:
	var plan := sk.wall_plan()
	if plan.is_empty():
		return
	var ok: bool = plan["problem"] == ""
	var col := Color(0.4, 1.0, 0.4, 0.45) if ok else Color(1.0, 0.3, 0.25, 0.45)
	var h := NavGrid.CELL * 0.5
	for c: Vector2i in plan["cells"]:
		var q := world.nav.center_of(c)
		if not on_screen(q):
			continue
		var blocked := world.nav.is_blocked_cell(c)
		var pts := PackedVector2Array([sim_to_screen(q + Vector2(-h, -h)), sim_to_screen(q + Vector2(h, -h)),
			sim_to_screen(q + Vector2(h, h)), sim_to_screen(q + Vector2(-h, h))])
		o.draw_colored_polygon(pts, Color(col, 0.15) if blocked else col)


func _solid(size: Vector3, c: Color, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	mi.material_override = m
	mi.position = at
	return mi
