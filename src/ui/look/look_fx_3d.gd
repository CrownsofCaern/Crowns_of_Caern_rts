class_name LookFx3D
extends Node3D
## The finishing touches of the 3D skirmish view, on top of the shared Atmosphere3D.
## Purely visual: it never reads or changes the sim.
##
## Ink outlines (WbSettings.outlines): dark contour lines wherever the depth jumps or
## bends (buildings, trees, units against the ground), a one-texel ink outline round every
## battle sprite (SpriteUnit.set_ink) and a punchier grade, after the art bible's "strongly
## outlined, highly readable" sprites.
##
## Living land (WbSettings.ambience): cloud shadows sliding over the fields, wisps of mist
## in the low ground, and motes hanging in the air round the view that follow the biome
## (pollen over meadows, fireflies in the fens, spores in the deep woods, ice glitter on
## the snow, violet sparks in the gloom, embers rising over ash lands).
##
## The passes are full-screen quads that read the depth buffer (the Compatibility
## renderer has no post-processing stack). They draw before the fog of war
## (RENDER_PRIORITY_MAX), which redraws hidden land from the opaque picture.

const SHADERS := "res://src/ui/look/%s.gdshader"
const INK_PRIORITY := 100
const CLOUD_PRIORITY := 90
const MIST_PRIORITY := 95
## Ink look: S-curve, saturation and warm/cool split of the grade, as factors on ColorGrade.
const INK_CONTRAST := 0.38
const INK_SATURATION := 1.12
const INK_SPLIT := 1.6
const INK_SAT_BOOST := 1.22  ## on the atmosphere's own saturation (which drops under cloud)
const INK_SUN_BOOST := 1.1
const CLOUD_SHADOW := 0.5  ## darkest cloud shadow under a clear sky
const MOTES := 420
const MOTES_MOBILE := 160
const MOTE_BOX := Vector3(42.0, 3.5, 30.0)  ## half extents of the air the motes fill
## Motes per biome: colour, size (m), drift speed (m/s), rise (m/s^2), glow.
const MOTE_KINDS := {
	"meadow": {"color": Color(1.0, 0.72, 0.38), "size": 0.07, "speed": 0.45, "rise": 0.02, "glow": 1.2},
	"swamp": {"color": Color(0.78, 1.0, 0.35), "size": 0.09, "speed": 0.3, "rise": 0.0, "glow": 2.2},
	"deepwood": {"color": Color(0.82, 0.95, 0.72), "size": 0.06, "speed": 0.25, "rise": 0.01, "glow": 1.0},
	"snowfield": {"color": Color(0.85, 0.92, 1.0), "size": 0.05, "speed": 0.5, "rise": -0.02, "glow": 1.4},
	"gloomcrag": {"color": Color(0.78, 0.55, 1.0), "size": 0.07, "speed": 0.3, "rise": 0.03, "glow": 1.8},
	"ashland": {"color": Color(1.0, 0.42, 0.12), "size": 0.08, "speed": 0.6, "rise": 0.35, "glow": 2.4},
}

static var _ink_lut: ImageTexture3D

var ink: bool = true:
	set(v):
		ink = v
		_refresh()
var ambience: bool = true:
	set(v):
		ambience = v
		_refresh()
var atmosphere: Atmosphere3D
var ink_pass: MeshInstance3D
var cloud_pass: MeshInstance3D
var mist_pass: MeshInstance3D
var motes: CPUParticles3D
var mote_biome: String = ""
var _mote_mat: StandardMaterial3D
## The last values this node wrote, so a boost is laid on the atmosphere's value once.
var _sun_set: float = -1.0
var _sat_set: float = -1.0


static func create(atmo: Atmosphere3D, ink_on: bool, ambience_on: bool) -> LookFx3D:
	var l := LookFx3D.new()
	l.name = "LookFx3D"
	l.atmosphere = atmo
	l.process_priority = 100  # after the atmosphere has lit the frame
	l.ink_pass = _screen_pass("ink_edges", INK_PRIORITY)
	l.cloud_pass = _screen_pass("cloud_shadows", CLOUD_PRIORITY)
	l.mist_pass = _screen_pass("ground_mist", MIST_PRIORITY)
	for p in [l.ink_pass, l.cloud_pass, l.mist_pass]:
		l.add_child(p)
	l._make_motes()
	l.ink = ink_on
	l.ambience = ambience_on
	return l


static func _screen_pass(shader: String, priority: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = shader
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	mi.mesh = q
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = load(SHADERS % shader)
	m.set_shader_parameter("gl_depth", RenderingServer.get_current_rendering_method() == "gl_compatibility")
	m.render_priority = priority
	mi.material_override = m
	return mi


func _make_motes() -> void:
	motes = CPUParticles3D.new()
	motes.name = "Motes"
	motes.amount = MOTES_MOBILE if OS.has_feature("mobile") else MOTES
	motes.lifetime = 14.0
	motes.preprocess = 14.0
	motes.local_coords = false  # the air stays put while the camera moves over it
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = MOTE_BOX
	motes.direction = Vector3(1.0, 0.3, 0.4)
	motes.spread = 60.0
	motes.scale_amount_min = 0.5
	motes.scale_amount_max = 1.4
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	motes.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_mote_mat = StandardMaterial3D.new()
	_mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mote_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mote_mat.billboard_keep_scale = true
	_mote_mat.vertex_color_use_as_albedo = true
	_mote_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mote_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mote_mat.albedo_texture = CombatFx3D.glow_texture()
	q.material = _mote_mat
	motes.mesh = q
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(motes)
	set_mote_biome("meadow")


## Gives the motes the look of a biome (by name; unknown names get the meadow's).
func set_mote_biome(biome: String) -> void:
	var b := biome if MOTE_KINDS.has(biome) else "meadow"
	if b == mote_biome:
		return
	mote_biome = b
	var k: Dictionary = MOTE_KINDS[b]
	var c: Color = k["color"]
	_mote_mat.albedo_color = Color(c.r * float(k["glow"]), c.g * float(k["glow"]), c.b * float(k["glow"]), 0.75)
	var s: float = k["size"]
	motes.scale_amount_min = s * 0.6
	motes.scale_amount_max = s * 1.4
	motes.initial_velocity_min = float(k["speed"]) * 0.3
	motes.initial_velocity_max = float(k["speed"])
	motes.gravity = Vector3(0.0, float(k["rise"]), 0.0)


## Keeps the motes round the point the camera looks at (call each frame).
func follow(target: Vector3) -> void:
	if motes != null and motes.emitting:
		motes.global_position = target + Vector3(0.0, 3.0, 0.0)


func _refresh() -> void:
	if ink_pass == null:
		return
	ink_pass.visible = ink
	SpriteUnit.set_ink(ink)
	cloud_pass.visible = ambience
	mist_pass.visible = ambience
	motes.visible = ambience
	motes.emitting = ambience
	if atmosphere != null:
		atmosphere.environment.adjustment_color_correction = ink_lut() if ink else ColorGrade.texture()
		if not ink:
			# The atmosphere re-lights every frame, which drops the boost.
			_sun_set = -1.0
			_sat_set = -1.0
	_lay_on()


func _process(_delta: float) -> void:
	_lay_on()


## The per-frame part: boosts on the atmosphere's light, the motes' biome, and how strong
## the cloud shadows are under the current sky (none under full overcast).
func _lay_on() -> void:
	if atmosphere == null:
		return
	if ink:
		var sun := atmosphere.sun
		if not is_equal_approx(sun.light_energy, _sun_set):
			sun.light_energy *= INK_SUN_BOOST
			_sun_set = sun.light_energy
		var env := atmosphere.environment
		if not is_equal_approx(env.adjustment_saturation, _sat_set):
			env.adjustment_saturation = minf(1.0, env.adjustment_saturation * INK_SAT_BOOST)
			_sat_set = env.adjustment_saturation
	if ambience:
		set_mote_biome(atmosphere.mood_biome)
		var clear := 1.0 - atmosphere.cloud
		(cloud_pass.material_override as ShaderMaterial).set_shader_parameter("strength", CLOUD_SHADOW * clear)


## The ink look's colour grade: ColorGrade's warm lights and cool darks, pushed further,
## with a stronger S-curve and richer colour.
static func ink_lut() -> ImageTexture3D:
	if _ink_lut == null:
		_ink_lut = build_lut(ColorGrade.SIZE, INK_CONTRAST, INK_SATURATION, INK_SPLIT)
	return _ink_lut


static func build_lut(n: int, contrast: float, sat: float, split: float) -> ImageTexture3D:
	var layers: Array[Image] = []
	for b in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for g in n:
			for r in n:
				img.set_pixel(r, g, grade(Color(float(r) / (n - 1), float(g) / (n - 1), float(b) / (n - 1)),
					contrast, sat, split))
		layers.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, n, n, n, false, layers)
	return tex


static func grade(c: Color, contrast: float, sat: float, split: float) -> Color:
	var v := Vector3(c.r, c.g, c.b)
	var s := v * v * (Vector3.ONE * 3.0 - v * 2.0)
	v = v.lerp(s, contrast)
	var lum := v.dot(Vector3(0.2126, 0.7152, 0.0722))
	v = Vector3.ONE * lum + (v - Vector3.ONE * lum) * sat
	var dark := (1.0 - lum) * (1.0 - lum)
	v += (ColorGrade.SHADOW_TINT * dark + ColorGrade.HIGHLIGHT_TINT * lum * lum) * split
	v = ColorGrade.LIFT + v * (Vector3.ONE - ColorGrade.LIFT)
	return Color(clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0), clampf(v.z, 0.0, 1.0))
