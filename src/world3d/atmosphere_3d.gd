class_name Atmosphere3D
extends Node3D
## Sky, light, fog and weather of a 3D map: a dark, blood-red gothic mood, and now and
## then clouds, rain and thunderstorms with lightning. Snow fields get snow and ash lands
## falling ash instead of rain. Purely visual: a seeded generator of its own (never the
## game's), so it cannot change a match. Made by MapScene3D; the RTS view and the 3D
## battle both get it. Works on the Compatibility renderer (no volumetric fog there),
## and stays cheap: rain is one MultiMesh moved by its shader, lightning is a light flash.

## Weather spells: weight (how often it is picked), seconds [min, max], cloud cover 0..1,
## precipitation 0..1, lightning.
const SPELLS := {
	"clear": {"weight": 5.0, "time": [70.0, 150.0], "cloud": 0.0, "rain": 0.0, "storm": false},
	"overcast": {"weight": 3.0, "time": [50.0, 110.0], "cloud": 0.6, "rain": 0.0, "storm": false},
	"rain": {"weight": 2.0, "time": [45.0, 90.0], "cloud": 0.85, "rain": 0.7, "storm": false},
	"storm": {"weight": 1.5, "time": [40.0, 80.0], "cloud": 1.0, "rain": 1.0, "storm": true},
}
const ORDER := ["clear", "overcast", "rain", "storm"]
const BLEND_RATE := 0.1  ## per second: weather changes over roughly 10-20 s
const DROPS := 2400  ## precipitation quads at full strength (desktop)
const DROPS_MOBILE := 900
## What falls in a biome (by its name); everything else gets rain.
const FALL := {"snowfield": "snow", "ashland": "ash"}
const KINDS := {
	"rain": {"speed": 14.0, "wind": Vector2(1.6, 0.7), "length": 1.1, "width": 0.045, "streak": true,
		"sway": 0.0, "tint": Color(0.62, 0.66, 0.74, 0.4), "ember": Color(1, 1, 1, 0), "lightning": true},
	"snow": {"speed": 1.6, "wind": Vector2(1.2, 0.4), "length": 0.09, "width": 0.09, "streak": false,
		"sway": 0.6, "tint": Color(0.92, 0.94, 1.0, 0.75), "ember": Color(1, 1, 1, 0), "lightning": false},
	"ash": {"speed": 1.1, "wind": Vector2(0.8, 0.3), "length": 0.08, "width": 0.08, "streak": false,
		"sway": 0.45, "tint": Color(0.16, 0.14, 0.14, 0.8), "ember": Color(1.0, 0.38, 0.1, 1.0), "lightning": true},
}
## Clear-sky mood per biome (sun, ambient, fog, sky top, horizon), after the main
## game's battlefield paintings: warm, golden light against cool slate shadows, with
## the biome's colour in the air: red dusk over meadows, green murk over the fens,
## cold green-grey in the deep woods, blue frost, violet gloom, a burning sky over ash.
## The light stays near neutral in the dark biomes so buildings and units read
## against the ground. The view blends toward the biome under the camera (set_biome).
const MOODS := {
	"meadow": [Color(1.0, 0.84, 0.64), Color(0.4, 0.43, 0.54), Color(0.3, 0.22, 0.22), Color(0.1, 0.03, 0.04), Color(0.58, 0.14, 0.08)],
	"swamp": [Color(0.94, 0.94, 0.74), Color(0.42, 0.47, 0.46), Color(0.18, 0.23, 0.17), Color(0.04, 0.06, 0.05), Color(0.26, 0.32, 0.2)],
	"deepwood": [Color(1.0, 0.9, 0.7), Color(0.42, 0.47, 0.47), Color(0.15, 0.21, 0.19), Color(0.04, 0.06, 0.07), Color(0.3, 0.34, 0.3)],
	"snowfield": [Color(0.88, 0.93, 1.0), Color(0.4, 0.46, 0.6), Color(0.34, 0.38, 0.46), Color(0.06, 0.08, 0.14), Color(0.42, 0.48, 0.6)],
	"gloomcrag": [Color(0.96, 0.93, 1.0), Color(0.44, 0.43, 0.47), Color(0.17, 0.15, 0.2), Color(0.05, 0.03, 0.08), Color(0.3, 0.18, 0.4)],
	"ashland": [Color(1.0, 0.84, 0.7), Color(0.44, 0.42, 0.44), Color(0.21, 0.19, 0.19), Color(0.12, 0.02, 0.01), Color(0.75, 0.16, 0.04)],
}
## Sun strength per biome (default 1): fresh snow takes the full sun and burns out.
const SUN_ENERGY := {"snowfield": 0.8}
const MOOD_RATE := 0.8  ## per second: how fast the light follows the camera into another biome
const SUN_CLOUD := Color(0.62, 0.62, 0.72)
const AMBIENT_CLOUD := Color(0.34, 0.35, 0.42)
const FOG_CLOUD := Color(0.13, 0.12, 0.15)
const BOLT_RED := Color(1.0, 0.45, 0.3)  ## ash lands: red lightning
const BOLT_WHITE := Color(0.82, 0.86, 1.0)
const THUNDER := ["weather_thunder", "weather_thunder_2", "weather_thunder_3"]
const SFX := "res://assets/audio/sfx/%s.ogg"

var environment: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var kind: String = "rain"
## Off: the sky stays clear (the dark mood stays). Set by the game's settings.
var weather_enabled: bool = true:
	set(v):
		weather_enabled = v
		if not v:
			set_weather("clear")
var muted: bool = false:
	set(v):
		muted = v
		if v and _rain_audio != null:
			_rain_audio.stop()
## Current weather: the spell's name and how far the sky has got toward it.
var weather: String = "clear"
var cloud: float = 0.0
var rain: float = 0.0
var flash: float = 0.0  ## lightning brightness right now, 0..1
var strikes: int = 0  ## lightning strikes so far (tests, tools)

var _rng := RandomNumberGenerator.new()
var _spell_left: float = 0.0
var _next_strike: float = 0.0
var _flash_t: float = -1.0
var _bolt: MeshInstance3D
var _bolt_mat: StandardMaterial3D
var _drops: MultiMeshInstance3D
var _drop_mat: ShaderMaterial
var _vignette_mat: ShaderMaterial
var _rain_audio: AudioStreamPlayer
var _thunder: Array[AudioStreamPlayer] = []
var _thunder_streams: Array = []
var _pending_thunder: Array = []  ## [seconds left, take, volume dB]
var _sky_cloud: float = -1.0
var _drop_count: int = DROPS
var _mood: Array = MOODS["meadow"].duplicate()
var _mood_target: Array = MOODS["meadow"]
var _sun_energy: float = 1.0
var _mood_moved: float = 0.0  ## mood change since the sky was last re-lit
## Name of the biome whose light the view is heading for.
var mood_biome: String = "meadow"
## Models added under this viewport lose their plastic shine (MatteMaterials).
var matte_models: bool = true


static func create(seed_value: int = 1, biome: String = "") -> Atmosphere3D:
	var a := Atmosphere3D.new()
	a.name = "Atmosphere3D"
	a.build(seed_value, biome)
	return a


func build(seed_value: int, biome: String = "") -> void:
	_rng.seed = seed_value * 6151 + 29
	kind = FALL.get(biome, "rain")
	mood_biome = biome if MOODS.has(biome) else "meadow"
	_mood_target = MOODS[mood_biome]
	_mood = _mood_target.duplicate()
	_sun_energy = SUN_ENERGY.get(mood_biome, 1.0)
	_drop_count = DROPS_MOBILE if OS.has_feature("mobile") else DROPS
	_environment()
	_precipitation()
	_lightning()
	_vignette()
	_audio()
	# Start under a clear or grey sky; the first change comes within a few minutes.
	weather = "overcast" if _rng.randf() < 0.3 else "clear"
	cloud = SPELLS[weather]["cloud"]
	_spell_left = _rng.randf_range(40.0, 100.0)
	_apply()


# --- Setup ---------------------------------------------------------------------

func _enter_tree() -> void:
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


## Every mesh that joins this 3D view (units, heroes, buildings, props) is made matte
## once it is set up (deferred: scenes fill in their meshes as they are added).
func _on_node_added(n: Node) -> void:
	if matte_models and n is MeshInstance3D and n.get_viewport() == get_viewport():
		_matte_later.call_deferred(n)


func _matte_later(n: Node) -> void:
	if is_instance_valid(n) and n.is_inside_tree():
		MatteMaterials.apply(n)


func _environment() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 8.0  # a tight sun: ponds mirror the sky, not a huge white halo
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32  # the sky is re-lit when clouds change: keep it small
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.fog_enabled = true
	environment.fog_sky_affect = 0.5
	environment.glow_enabled = true
	environment.glow_intensity = 0.6
	# Screen blend and a high threshold: only bright things glow (lightning, lava, embers).
	# The default soft-light blend darkens a dark scene a lot on the Compatibility renderer.
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.glow_hdr_threshold = 0.9
	environment.adjustment_enabled = true
	# Gentle: on the Compatibility renderer contrast works before tone mapping and crushes shadows.
	environment.adjustment_contrast = 1.05
	# The final grade (warm lights, cool shadows, soft S-curve): ColorGrade.
	environment.adjustment_color_correction = ColorGrade.texture()
	# Mist settles in the low ground: valleys and riverbanks read deeper than the hills.
	environment.fog_height = 0.6
	environment.fog_height_density = 0.06
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 170.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_blur = 1.5
	# Afternoon sun from the west: shadows that model the land without swallowing it.
	sun.rotation_degrees = Vector3(-47, -128, 0)
	add_child(sun)


func _precipitation() -> void:
	var k: Dictionary = KINDS[kind]
	_drop_mat = ShaderMaterial.new()
	_drop_mat.shader = load("res://src/world3d/precipitation.gdshader")
	_drop_mat.set_shader_parameter("speed", k["speed"])
	_drop_mat.set_shader_parameter("wind", k["wind"])
	_drop_mat.set_shader_parameter("drop_length", k["length"])
	_drop_mat.set_shader_parameter("drop_width", k["width"])
	_drop_mat.set_shader_parameter("streak", k["streak"])
	_drop_mat.set_shader_parameter("sway", k["sway"])
	_drop_mat.set_shader_parameter("tint", k["tint"])
	_drop_mat.set_shader_parameter("ember", k["ember"])
	# One quad: x across (-0.5..0.5), y along the fall (0..1).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)]
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(v[i])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = st.commit()
	mm.instance_count = _drop_count
	var r := RandomNumberGenerator.new()
	r.seed = 7717
	for n in _drop_count:
		mm.set_instance_transform(n, Transform3D(Basis.IDENTITY, Vector3(r.randf(), r.randf(), r.randf())))
	mm.visible_instance_count = 0
	_drops = MultiMeshInstance3D.new()
	_drops.name = "Precipitation"
	_drops.multimesh = mm
	_drops.material_override = _drop_mat
	_drops.top_level = true  # the shader reads world positions from the instance origins
	_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drops.custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 1000, 10000))
	_drops.visible = false
	add_child(_drops)


func _lightning() -> void:
	_bolt_mat = StandardMaterial3D.new()
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bolt_mat.disable_fog = true
	_bolt_mat.vertex_color_use_as_albedo = true  # bright core, faint halo
	_bolt_mat.albedo_color = BOLT_RED if kind == "ash" else BOLT_WHITE
	_bolt = MeshInstance3D.new()
	_bolt.name = "Lightning"
	_bolt.top_level = true
	_bolt.material_override = _bolt_mat
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)


func _vignette() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = load("res://src/world3d/vignette.gdshader")
	_vignette_mat.render_priority = Material.RENDER_PRIORITY_MAX
	var mi := MeshInstance3D.new()
	mi.name = "Vignette"
	mi.mesh = quad
	mi.material_override = _vignette_mat
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _audio() -> void:
	var rain_path := SFX % "weather_rain"
	if kind == "rain" and ResourceLoader.exists(rain_path):
		var s: AudioStreamOggVorbis = load(rain_path)
		s = s.duplicate()
		s.loop = true
		_rain_audio = AudioStreamPlayer.new()
		_rain_audio.stream = s
		add_child(_rain_audio)
	for t in THUNDER:
		if ResourceLoader.exists(SFX % t):
			_thunder_streams.append(load(SFX % t))
	for i in 2:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_thunder.append(p)


# --- Weather -------------------------------------------------------------------

## Lets the light drift toward a biome's mood (the RTS view calls this with the biome
## under the camera). Unknown names are ignored.
func set_biome(biome: String) -> void:
	if MOODS.has(biome) and biome != mood_biome:
		mood_biome = biome
		_mood_target = MOODS[biome]


## Switches to a weather spell now (the sky still takes a few seconds to follow).
func set_weather(spell: String, seconds: float = -1.0) -> void:
	if not SPELLS.has(spell):
		return
	weather = spell
	var t: Array = SPELLS[spell]["time"]
	_spell_left = seconds if seconds > 0.0 else _rng.randf_range(t[0], t[1])
	_next_strike = _rng.randf_range(3.0, 8.0)


## The next spell in the list (F6 in the skirmish, for a quick look).
func next_weather() -> void:
	set_weather(ORDER[(ORDER.find(weather) + 1) % ORDER.size()])


func _pick_spell() -> String:
	var total := 0.0
	for s in ORDER:
		if s != weather:
			total += float(SPELLS[s]["weight"])
	var roll := _rng.randf() * total
	for s in ORDER:
		if s == weather:
			continue
		roll -= float(SPELLS[s]["weight"])
		if roll <= 0.0:
			return s
	return "clear"


## Advances the weather by delta seconds. Runs from _process; tools and tests call it directly.
func step(delta: float) -> void:
	_spell_left -= delta
	if _spell_left <= 0.0:
		set_weather(_pick_spell() if weather_enabled else "clear")
	var spell: Dictionary = SPELLS[weather]
	var k := 1.0 - exp(-BLEND_RATE * delta)
	var km := 1.0 - exp(-MOOD_RATE * delta)
	for i in _mood.size():
		var was: Color = _mood[i]
		_mood[i] = was.lerp(_mood_target[i], km)
		_mood_moved += absf(was.r - _mood[i].r) + absf(was.g - _mood[i].g) + absf(was.b - _mood[i].b)
	_sun_energy = lerpf(_sun_energy, SUN_ENERGY.get(mood_biome, 1.0), km)
	cloud = lerpf(cloud, spell["cloud"], k)
	rain = lerpf(rain, spell["rain"], k)
	if bool(spell["storm"]) and KINDS[kind]["lightning"] and rain > 0.6:
		_next_strike -= delta
		if _next_strike <= 0.0:
			strike()
			_next_strike = _rng.randf_range(5.0, 16.0)
	if _flash_t >= 0.0:
		_flash_t += delta
		flash = _flash_curve(_flash_t)
		if _flash_t > 0.7:
			_flash_t = -1.0
			flash = 0.0
			_bolt.visible = false
	for p in _pending_thunder:
		p[0] -= delta
		if p[0] <= 0.0:
			_play_thunder(int(p[1]), float(p[2]))
	_pending_thunder = _pending_thunder.filter(func(p: Array) -> bool: return p[0] > 0.0)
	_apply()


## Two quick pulses, then a fade: how a strike lights the field.
func _flash_curve(t: float) -> float:
	if t < 0.06:
		return 1.0
	if t < 0.12:
		return 0.35
	if t < 0.2:
		return 0.75
	return maxf(0.0, 0.75 * (1.0 - (t - 0.2) / 0.5))


## A lightning strike somewhere in view: a bolt, a flash, and thunder a moment later.
func strike() -> void:
	strikes += 1
	_flash_t = 0.0
	flash = 1.0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var target := _view_target(cam)
	var right := cam.global_basis.x if cam != null else Vector3.RIGHT
	var at := target + right * _rng.randf_range(-18.0, 18.0) + Vector3(0, 0, _rng.randf_range(-12.0, 4.0))
	_bolt.mesh = _bolt_mesh(at, right)
	_bolt.visible = true
	# Far strikes rumble later and softer; a third of them are the crack of a near one.
	var far := _rng.randf()
	var take := 0 if far < 0.33 else (1 if _thunder_streams.size() > 1 else 0)
	if _thunder_streams.size() > 2 and far > 0.75:
		take = 2
	_pending_thunder.append([0.25 + far * 2.2, take, -2.0 - far * 8.0])


func _bolt_mesh(ground: Vector3, right: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := ground + Vector3(_rng.randf_range(-8, 8), 70.0, _rng.randf_range(-8, 8))
	var pts: Array[Vector3] = []
	var n := 14
	for i in n + 1:
		var t := float(i) / n
		var p := top.lerp(ground, t)
		if i > 0 and i < n:
			p += right * _rng.randf_range(-3.0, 3.0) + Vector3(0, 0, _rng.randf_range(-1.5, 1.5))
		pts.append(p)
	_ribbon(st, pts, right, 1.1, Color(1, 1, 1, 0.22))
	_ribbon(st, pts, right, 0.16, Color(1, 1, 1, 1))
	# One or two forks off the main channel.
	for b in 1 + _rng.randi() % 2:
		var from := 3 + _rng.randi() % 7
		var fork: Array[Vector3] = [pts[from]]
		var dir := right * (1.0 if _rng.randf() < 0.5 else -1.0)
		for i in 4:
			fork.append(fork[-1] + dir * _rng.randf_range(1.5, 4.0) + Vector3(0, -_rng.randf_range(3.0, 6.0), 0))
		_ribbon(st, fork, right, 0.5, Color(1, 1, 1, 0.15))
		_ribbon(st, fork, right, 0.08, Color(1, 1, 1, 0.9))
	return st.commit()


func _ribbon(st: SurfaceTool, pts: Array[Vector3], right: Vector3, w: float, col: Color) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var quad := [a - right * w, a + right * w, b + right * w, b - right * w]
		for j in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.add_vertex(quad[j])


func _play_thunder(take: int, db: float) -> void:
	if muted or _thunder_streams.is_empty() or not is_inside_tree() or not is_visible_in_tree():
		return
	var p := _thunder[0] if not _thunder[0].playing else _thunder[1]
	p.stream = _thunder_streams[clampi(take, 0, _thunder_streams.size() - 1)]
	p.volume_db = db
	p.pitch_scale = _rng.randf_range(0.85, 1.05)
	p.play()


# --- Applying the mood -----------------------------------------------------------

func _apply() -> void:
	var c := cloud
	var f := flash
	sun.light_color = (_mood[0] as Color).lerp(SUN_CLOUD, c).lerp(BOLT_WHITE, f)
	sun.light_energy = lerpf(1.2, 0.55, c) * _sun_energy + f * 2.2
	sun.shadow_opacity = lerpf(0.76, 0.45, c)
	environment.ambient_light_color = (_mood[1] as Color).lerp(AMBIENT_CLOUD, c)
	environment.ambient_light_energy = lerpf(0.95, 0.85, c) + f * 1.2
	environment.fog_light_color = (_mood[2] as Color).lerp(FOG_CLOUD, c).lerp(Color(0.5, 0.5, 0.62), f * 0.6)
	environment.fog_density = lerpf(0.0022, 0.005, c) + rain * 0.0015
	environment.adjustment_saturation = lerpf(0.82, 0.62, c)
	_vignette_mat.set_shader_parameter("strength", lerpf(0.3, 0.5, c))
	# The sky is re-lit only when the clouds or the mood really moved (cheap on phones).
	if absf(c - _sky_cloud) > 0.03 or _mood_moved > 0.05:
		_sky_cloud = c
		_mood_moved = 0.0
		sky_mat.sky_top_color = (_mood[3] as Color).lerp(Color(0.05, 0.05, 0.07), c)
		sky_mat.sky_horizon_color = (_mood[4] as Color).lerp(Color(0.2, 0.17, 0.18), c)
		sky_mat.ground_horizon_color = ((_mood[4] as Color) * 0.5).lerp(Color(0.12, 0.1, 0.1), c)
		sky_mat.ground_bottom_color = Color(0.04, 0.02, 0.02)
		sky_mat.sun_curve = lerpf(0.15, 0.4, c)
	# Precipitation: only as many drops as the rain is heavy.
	var shown := int(_drop_count * clampf(rain, 0.0, 1.0))
	_drops.multimesh.visible_instance_count = shown
	_drops.visible = shown > 8
	_drop_mat.set_shader_parameter("flash", f * 0.6)
	var a := 0.95 * f if _bolt.visible else 0.0
	_bolt_mat.albedo_color.a = a
	if _rain_audio != null:
		var want := rain > 0.05 and not muted and is_inside_tree() and is_visible_in_tree()
		if want and not _rain_audio.playing:
			_rain_audio.play()
		elif not want and _rain_audio.playing:
			_rain_audio.stop()
		_rain_audio.volume_db = linear_to_db(maxf(rain, 0.001) * 0.55)


## Where the camera looks at the ground (y = 0 plane), or the origin without a camera.
func _view_target(cam: Camera3D) -> Vector3:
	if cam == null:
		return Vector3.ZERO
	var o := cam.global_position
	var d := -cam.global_basis.z
	if d.y > -0.05:
		return o + d * 30.0
	var t := clampf(-o.y / d.y, 5.0, 150.0)
	return o + d * t


func _process(delta: float) -> void:
	step(delta)
	if not _drops.visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var target := _view_target(cam)
	var dist := cam.global_position.distance_to(target)
	var w := clampf(dist * 1.8, 40.0, 140.0)
	var h := clampf(cam.global_position.y - target.y + 4.0, 20.0, 60.0)
	_drop_mat.set_shader_parameter("center", target + Vector3(0, h * 0.5 - 2.0, 0))
	_drop_mat.set_shader_parameter("box", Vector3(w, h, w))
