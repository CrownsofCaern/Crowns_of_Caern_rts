class_name ConstructionFx3D
extends RefCounted
## A building site in the 3D view: wooden scaffolding round the footprint, dust rolling
## off the ground and wood chips flying while the builders work, and a hoist rope that
## swings. The model itself rises out of the ground with the progress (rise()).
## Purely visual; the skirmish view drives it (SkirmishView3D._sync_construction).

const WOOD := Color(0.42, 0.3, 0.19)
const WOOD_DARK := Color(0.27, 0.19, 0.12)
const DUST := Color(0.66, 0.58, 0.47)
## Seconds the dust keeps rolling after the last bit of progress (builders hit in turns).
const WORK_HOLD := 1.2
## How much of the model is still underground at progress 0 (a stump of it shows).
const SUNK := 0.85

static var _wood_mats: Dictionary = {}


## How far below the ground the model sits at this progress (0..1), for a model this tall.
static func rise(progress: float, height_m: float) -> float:
	var p := clampf(progress, 0.0, 1.0)
	return -(1.0 - p) * height_m * SUNK


## The site of a building `width_m` across whose finished model stands `height_m` tall.
## salt varies the scaffold a little from one site to the next.
static func site(width_m: float, height_m: float, salt: int) -> Node3D:
	var root := Node3D.new()
	root.name = "BuildSite"
	var half := width_m * 0.5 + 0.25
	var top := clampf(height_m * 0.75, 1.6, 6.5)
	var poles := Node3D.new()
	poles.name = "Scaffold"
	root.add_child(poles)
	# Poles at the corners and along the front and the sides, planks at two levels.
	var spots: Array[Vector2] = [Vector2(-half, -half), Vector2(half, -half), Vector2(-half, half), Vector2(half, half),
		Vector2(0.0, half), Vector2(-half, 0.0), Vector2(half, 0.0)]
	for i in spots.size():
		var p := spots[i]
		var h := top * (0.8 + 0.2 * float((salt + i * 7) % 5) / 4.0)
		poles.add_child(_beam(Vector3(0.14, h, 0.14), Vector3(p.x, h * 0.5, p.y), WOOD))
	for level in [0.38, 0.72]:
		var y: float = top * level
		poles.add_child(_beam(Vector3(width_m + 0.5, 0.12, 0.32), Vector3(0.0, y, half), WOOD_DARK))
		poles.add_child(_beam(Vector3(0.32, 0.12, width_m + 0.5), Vector3(-half, y, 0.0), WOOD_DARK))
		poles.add_child(_beam(Vector3(0.32, 0.12, width_m + 0.5), Vector3(half, y, 0.0), WOOD_DARK))
	# A diagonal brace on the front.
	var brace := _beam(Vector3(0.1, top * 0.9, 0.1), Vector3(-half * 0.5, top * 0.42, half + 0.05), WOOD)
	brace.rotation.z = 0.6
	poles.add_child(brace)
	# The hoist: an arm off the tallest pole and a rope with a load that swings.
	var arm := _beam(Vector3(1.6, 0.12, 0.12), Vector3(half - 0.7, top * 1.02, half), WOOD_DARK)
	poles.add_child(arm)
	var rope := Node3D.new()
	rope.name = "Rope"
	rope.position = Vector3(half - 1.4, top * 1.0, half)
	rope.add_child(_beam(Vector3(0.04, top * 0.35, 0.04), Vector3(0.0, -top * 0.175, 0.0), Color(0.6, 0.55, 0.45)))
	rope.add_child(_beam(Vector3(0.4, 0.3, 0.4), Vector3(0.0, -top * 0.35 - 0.15, 0.0), WOOD_DARK))
	root.add_child(rope)
	root.add_child(_dust_cloud(half))
	root.add_child(_chips(half, top))
	return root


## Per frame: dust and chips while builders are at work, the rope swinging, the
## scaffold standing. `t` is the view's clock.
static func sync_site(site_node: Node3D, progress: float, working: bool, t: float) -> void:
	var dust: CPUParticles3D = site_node.get_node("Dust")
	var chips: CPUParticles3D = site_node.get_node("Chips")
	dust.emitting = working
	chips.emitting = working
	var rope: Node3D = site_node.get_node("Rope")
	var swing := 0.25 if working else 0.06
	rope.rotation.z = sin(t * 1.7) * swing
	rope.rotation.x = sin(t * 1.1 + 0.8) * swing * 0.5
	# The load is hauled up as the walls go up.
	var load_box := rope.get_child(1) as Node3D
	load_box.position.y = lerpf(load_box.position.y, -0.6 - (1.0 - progress) * 2.0, 0.1)


static func _beam(size: Vector3, at: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	if not _wood_mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.95
		m.metallic_specular = 0.1
		_wood_mats[c] = m
	mi.material_override = _wood_mats[c]
	mi.position = at
	return mi


## Dust rolling off the ground round the footprint.
static func _dust_cloud(half: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Dust"
	p.amount = 40
	p.lifetime = 2.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = half + 0.3
	p.emission_ring_inner_radius = half * 0.6
	p.emission_ring_height = 0.1
	p.position.y = 0.3
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0.0, 0.15, 0.0)
	p.damping_min = 0.3
	p.damping_max = 0.6
	p.scale_amount_min = 1.3
	p.scale_amount_max = 2.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(DUST, 0.0), Color(DUST, 0.8), Color(DUST.darkened(0.25), 0.0)])
	p.color_ramp = ramp
	p.mesh = _puff_quad()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p


## Wood chips and splinters flying off the work.
static func _chips(half: float, top: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Chips"
	p.amount = 14
	p.lifetime = 0.9
	p.explosiveness = 0.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(half, top * 0.3, half)
	p.position.y = top * 0.45
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0.0, -9.0, 0.0)
	p.scale_amount_min = 0.07
	p.scale_amount_max = 0.13
	p.color = Color(0.75, 0.6, 0.38)
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = CombatFx3D.particle_texture()
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p


static var _puff: QuadMesh


## A soft round puff (the glow texture, blended normally rather than added).
static func _puff_quad() -> QuadMesh:
	if _puff == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = CombatFx3D.glow_texture()
		_puff = QuadMesh.new()
		_puff.size = Vector2.ONE
		_puff.material = m
	return _puff
