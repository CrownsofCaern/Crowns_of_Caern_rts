class_name MapScene3D
extends Node3D
## The 3D world of a map: terrain, water, trees, rocks, bushes, sky and light.
## Built from a TerrainField (plain data). Shared by the Warbound skirmish view and
## the 3D battle: `MapScene3D.create(field)` returns a ready node to add anywhere.
## Assets are CC0: ambientCG ground/rock textures, Quaternius nature models.

const CHUNK := 32  ## metres per terrain chunk and decoration batch
const NATURE := "res://assets/nature/%s.glb"
## Rock texture for the stone of set pieces (CC0 ambientCG Rock023, the terrain's own).
const STONE_ALBEDO := "res://assets/terrain3d/rock023_alb_ht.png"
const STONE_NORMAL := "res://assets/terrain3d/rock023_nrm_rgh.png"
const TEX := "res://assets/terrain3d/%s.png"
## Texture layers are this many pixels square (half on phones, to save memory).
const LAYER_SIZE := 1024
## Model -> [min height, max height] in metres (models are rescaled to these).
const TREES := {"pine_tree_1": [3.8, 5.5], "pine_tree_2": [3.5, 5.0], "pine_tree_3": [3.8, 5.5],
	"pine_tree_4": [3.6, 5.2], "pine_tree_5": [3.2, 4.5], "normal_tree_1": [3.2, 4.6], "normal_tree_2": [3.2, 4.4],
	"normal_tree_3": [3.0, 4.2], "normal_tree_4": [3.2, 4.4], "normal_tree_5": [3.4, 4.8], "birch_tree_1": [3.6, 5.0],
	"birch_tree_2": [3.4, 4.8], "birch_tree_3": [3.6, 5.2], "maple_tree_1": [3.2, 4.4], "maple_tree_3": [3.0, 4.2]}
const DEAD := {"dead_tree_1": [3.0, 4.2], "dead_tree_2": [2.8, 4.0], "dead_tree_3": [2.6, 3.8], "dead_tree_4": [3.0, 4.2],
	"dead_tree_5": [2.6, 3.6], "dead_tree_6": [2.8, 4.0], "dead_tree_7": [2.6, 3.8], "dead_tree_8": [2.4, 3.4],
	"dead_tree_9": [2.6, 3.4], "dead_tree_10": [2.8, 3.8]}
const ROCKS := {"rock_1": [1.1, 2.2], "rock_2": [1.1, 2.2], "rock_3": [1.0, 2.0], "rock_4": [1.0, 1.9],
	"rock_5": [1.1, 2.2]}
const GRASS := {"grass": [0.28, 0.5]}
## Tufts per square metre on open grass (cheap crossed cards, drawn only near the camera).
const GRASS_DENSITY := 1.6
const BUSHES := {"bush": [0.6, 1.0], "bush_large": [0.8, 1.3], "bush_small": [0.4, 0.7]}
## Low ground cover for open land: ferns, grass clumps and a few muted flowers.
const COVER := {"grass_large": [0.45, 0.8], "grass_small": [0.35, 0.6], "flower_3_clump": [0.25, 0.45],
	"flower_4_clump": [0.25, 0.45]}
## Biome scenery (data/biomes.json "scenery"; Quaternius CC0, tools/nature/convert_scenery.py):
## model -> [min height, max height] in metres.
const SCENERY := {"sn_pine_1": [3.8, 5.6], "sn_pine_2": [3.6, 5.2], "sn_pine_3": [3.8, 5.6], "sn_pine_4": [3.4, 5.0],
	"sn_pine_5": [3.2, 4.6], "sn_dead_1": [2.8, 4.0], "sn_dead_2": [2.8, 4.0], "sn_dead_3": [2.6, 3.6],
	"sn_bush_1": [0.7, 1.2], "sn_bush_2": [0.7, 1.2], "sn_rock_1": [1.0, 2.1], "sn_rock_2": [1.0, 2.0],
	"sn_rock_3": [1.0, 2.0], "sn_rock_4": [1.0, 1.9], "sn_stump": [0.45, 0.7],
	"fn_willow_1": [3.4, 4.8], "fn_willow_2": [3.4, 4.8], "fn_willow_3": [3.2, 4.6], "fn_willow_4": [3.2, 4.4],
	"fn_willow_dead_1": [2.8, 4.0], "fn_willow_dead_2": [2.8, 4.0], "fn_willow_dead_3": [2.6, 3.8], "fn_lilypad": [0.08, 0.1],
	"mo_rock_1": [0.9, 1.8], "mo_rock_2": [0.9, 1.8], "mo_rock_3": [0.9, 1.7], "mo_rock_4": [1.0, 1.9],
	"mo_stump": [0.45, 0.7], "mo_log": [0.45, 0.6], "stump": [0.45, 0.7], "log": [0.45, 0.6],
	"ch_stump": [0.45, 0.7], "ch_log": [0.4, 0.55], "ch_tree_1": [2.8, 4.0], "ch_tree_2": [2.6, 3.8], "ch_tree_3": [2.6, 3.6],
	"fern": [0.45, 0.8], "mushrooms": [0.25, 0.4], "shelf_fungus": [0.3, 0.5], "reeds": [0.7, 1.2],
	"twisted_tree_1": [3.6, 5.0], "twisted_tree_2": [3.4, 4.8], "twisted_tree_3": [3.4, 4.6],
	"gl_tree_1": [3.6, 5.2], "gl_tree_2": [3.6, 5.0], "gl_fungus": [0.3, 0.55], "gl_mushrooms": [0.3, 0.5]}
## Litter lies on the ground: a model taller than it is long is laid on its side.
const LIE := ["mo_log", "log", "ch_log"]
## Albedo lift for small nature models: their textures are dark and read as black blobs
## against the lit terrain under the blood-red sky.
const LIFT := {"bush": Color(1.05, 0.95, 0.8), "bush_large": Color(1.05, 0.95, 0.8), "bush_small": Color(1.05, 0.95, 0.8),
	"grass_large": Color(1.3, 1.25, 1.05), "grass_small": Color(1.3, 1.25, 1.05), "rock_1": Color(1.6, 1.6, 1.6),
	"rock_2": Color(1.6, 1.6, 1.6), "rock_3": Color(1.6, 1.6, 1.6), "rock_4": Color(1.6, 1.6, 1.6), "rock_5": Color(1.6, 1.6, 1.6)}

var field: TerrainField
var terrain_material: ShaderMaterial
var sun: DirectionalLight3D
var environment: Environment
var atmosphere: Atmosphere3D  ## mood and weather (null when built without an environment)
## Counts of placed decoration, for tests and tools.
var stats: Dictionary = {}
var _protos: Dictionary = {}  ## model -> [Mesh, Transform3D base, float native height]
var _stone_mats: Dictionary = {}  ## a prop's grey material -> its rock-textured copy
var _batches: Dictionary = {}
var _colors: Dictionary = {}  ## batch key -> Array[Color] (grass tufts tinted per biome)
var _seed: int = 1
var _biome_tex: ImageTexture  ## "model:cx:cz" -> Array[Transform3D]


static func create(f: TerrainField, seed_value: int = 1, with_environment: bool = true) -> MapScene3D:
	var m := MapScene3D.new()
	m.name = "MapScene3D"
	m.build(f, seed_value, with_environment)
	return m


func build(f: TerrainField, seed_value: int = 1, with_environment: bool = true) -> void:
	field = f
	_seed = seed_value
	_terrain()
	_water()
	_bridges()
	_props()
	_decorate(seed_value)
	if with_environment:
		_environment()


# --- Terrain -------------------------------------------------------------------

func _terrain() -> void:
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = load("res://src/world3d/terrain.gdshader")
	# Each biome brings its own open ground and rock (biomes.json ground_tex, rock_tex),
	# stacked into texture arrays with one layer per distinct texture on this map.
	# Roads and yards share the grey-brown stone (ambientCG Rock023).
	_layers(terrain_material, "ground_tex", "ground_alb", "ground_nrm", "b_layer")
	_layers(terrain_material, "rock_tex", "rock_alb", "rock_nrm", "b_rlayer")
	var embers := PackedFloat32Array()
	for b in field.biomes:
		embers.append(clampf(float(b.get("embers", 0.0)), 0.0, 1.0))
	terrain_material.set_shader_parameter("b_embers", embers)
	terrain_material.set_shader_parameter("dirt_alb", load(TEX % "rock023_alb_ht"))
	terrain_material.set_shader_parameter("dirt_nrm", load(TEX % "rock023_nrm_rgh"))
	terrain_material.set_shader_parameter("splat", ImageTexture.create_from_image(field.splat))
	var mn := NoiseTexture2D.new()
	mn.width = 256
	mn.height = 256
	mn.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.012
	fn.fractal_octaves = 3
	mn.noise = fn
	terrain_material.set_shader_parameter("macro_noise", mn)
	_biome_params(terrain_material, {"grass": "b_grass", "lush": "b_lush", "dry": "b_dry", "dirt": "b_dirt",
		"rock": "b_rock", "moss": "b_moss", "ash": "b_ash"})
	var snow := PackedFloat32Array()
	for b in field.biomes:
		snow.append(clampf(float(b.get("snow", 0.0)), 0.0, 1.0))
	terrain_material.set_shader_parameter("b_snow", snow)
	# Sample (i, j) sits at the centre of splat pixel (i, j).
	terrain_material.set_shader_parameter("origin", field.origin - Vector2.ONE * 0.5 / TerrainField.RES)
	terrain_material.set_shader_parameter("size", Vector2(field.sw, field.sh) / TerrainField.RES)
	var step := CHUNK * TerrainField.RES
	var root := Node3D.new()
	root.name = "Terrain"
	add_child(root)
	for j0 in range(0, field.sh - 1, step):
		for i0 in range(0, field.sw - 1, step):
			var mi := MeshInstance3D.new()
			mi.mesh = _chunk_mesh(i0, j0, mini(i0 + step, field.sw - 1), mini(j0 + step, field.sh - 1))
			mi.material_override = terrain_material
			root.add_child(mi)


func _h(i: int, j: int) -> float:
	return field.heights[clampi(j, 0, field.sh - 1) * field.sw + clampi(i, 0, field.sw - 1)]


func _chunk_mesh(i0: int, j0: int, i1: int, j1: int) -> ArrayMesh:
	var cw := i1 - i0 + 1
	var ch := j1 - j0 + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var idx := PackedInt32Array()
	verts.resize(cw * ch)
	normals.resize(cw * ch)
	tangents.resize(cw * ch * 4)
	var d := 1.0 / TerrainField.RES
	for j in ch:
		for i in cw:
			var gi := i0 + i
			var gj := j0 + j
			var v := j * cw + i
			verts[v] = Vector3(field.origin.x + gi * d, _h(gi, gj), field.origin.y + gj * d)
			var dx := _h(gi + 1, gj) - _h(gi - 1, gj)
			var dz := _h(gi, gj + 1) - _h(gi, gj - 1)
			var n := Vector3(-dx, 2.0 * d, -dz).normalized()
			normals[v] = n
			var t := Vector3(2.0 * d, dx, 0.0)
			t = (t - n * n.dot(t)).normalized()
			tangents[v * 4] = t.x
			tangents[v * 4 + 1] = t.y
			tangents[v * 4 + 2] = t.z
			tangents[v * 4 + 3] = 1.0
	for j in ch - 1:
		for i in cw - 1:
			var a := j * cw + i
			idx.append_array([a, a + 1, a + cw, a + 1, a + cw + 1, a + cw])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Builds an albedo and a normal texture array from the biomes' textures (key in
## biomes.json) and tells the shader which layer each biome slot uses.
func _layers(mat: ShaderMaterial, key: String, alb_param: String, nrm_param: String, slot_param: String) -> void:
	var names: Array[String] = []
	var slots := PackedFloat32Array()
	for b in field.biomes:
		var n := str(b.get(key, ""))
		if not ResourceLoader.exists(TEX % (n + "_alb_ht")):
			n = "ground003" if key == "ground_tex" else "rock030"
		if not n in names:
			names.append(n)
		slots.append(float(names.find(n)))
	mat.set_shader_parameter(slot_param, slots)
	var size := LAYER_SIZE / 2 if OS.has_feature("mobile") else LAYER_SIZE
	for pair in [[alb_param, "_alb_ht"], [nrm_param, "_nrm_rgh"]]:
		var images: Array[Image] = []
		for n in names:
			var img: Image = (load(TEX % (n + pair[1])) as Texture2D).get_image()
			if img.is_compressed():
				img.decompress()
			img.clear_mipmaps()
			img.convert(Image.FORMAT_RGBA8)
			if img.get_width() != size:
				img.resize(size, size, Image.INTERPOLATE_BILINEAR)
			img.generate_mipmaps()
			images.append(img)
		var arr := Texture2DArray.new()
		arr.create_from_images(images)
		mat.set_shader_parameter(pair[0], arr)


# --- Water ---------------------------------------------------------------------

## Hands the biomes' colours (TerrainField.SLOTS, base first) and the biome map to a shader.
func _biome_params(mat: ShaderMaterial, keys: Dictionary) -> void:
	if _biome_tex == null:
		_biome_tex = ImageTexture.create_from_image(field.biome_map)
	mat.set_shader_parameter("biome_map", _biome_tex)
	for k in keys:
		var arr := PackedVector3Array()
		for b in field.biomes:
			var c := Biomes.color(b, k)
			arr.append(Vector3(c.r, c.g, c.b))
		mat.set_shader_parameter(keys[k], arr)


func _water() -> void:
	var lowest := INF
	for v in field.heights:
		lowest = minf(lowest, v)
	if lowest >= field.water_level:
		return
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var waves := NoiseTexture2D.new()
	waves.width = 256
	waves.height = 256
	waves.seamless = true
	waves.as_normal_map = true
	waves.bump_strength = 4.0
	waves.noise = noise
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/world3d/water.gdshader")
	mat.set_shader_parameter("waves", waves)
	_biome_params(mat, {"water_deep": "b_deep", "water_sky": "b_sky"})
	var lava := PackedFloat32Array()
	for b in field.biomes:
		lava.append(1.0 if b["lava"] else 0.0)
	mat.set_shader_parameter("b_lava", lava)
	mat.set_shader_parameter("origin", field.origin - Vector2.ONE * 0.5 / TerrainField.RES)
	mat.set_shader_parameter("size", Vector2(field.sw, field.sh) / TerrainField.RES)
	var pm := PlaneMesh.new()
	pm.size = field.size_m()
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = pm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(field.origin.x + pm.size.x * 0.5, field.water_level, field.origin.y + pm.size.y * 0.5)
	add_child(mi)


# --- Bridges and set pieces ----------------------------------------------------

## Plank bridges over the causeways the field raised: a deck of cross planks on two
## stringers, with posts and a rail on each side. Built from boxes, one mesh per bridge.
func _bridges() -> void:
	if field.bridges.is_empty():
		return
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.24, 0.17, 0.12)
	wood.roughness = 0.95
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.13, 0.1, 0.08)
	dark.roughness = 1.0
	wood.cull_mode = BaseMaterial3D.CULL_DISABLED
	dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	var root := Node3D.new()
	root.name = "Bridges"
	add_child(root)
	for br in field.bridges:
		var a: Vector2 = br[0]
		var b: Vector2 = br[1]
		var w: float = br[2]
		var len := a.distance_to(b) + 1.6
		var dir := (b - a).normalized()
		var mid := (a + b) * 0.5
		var deck := TerrainField.BRIDGE_DECK
		var planks := SurfaceTool.new()
		planks.begin(Mesh.PRIMITIVE_TRIANGLES)
		var beams := SurfaceTool.new()
		beams.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := int(len / 0.45)
		for i in n:
			var t := -len * 0.5 + (i + 0.5) * len / n
			var jig := sin(i * 12.9898) * 0.04
			_box(planks, Vector3(t, deck + jig * 0.5, jig), Vector3(len / n * 0.86, 0.09, w + 0.2))
		for side in [-1.0, 1.0]:
			_box(beams, Vector3(0, deck - 0.14, side * (w * 0.5 - 0.15)), Vector3(len, 0.18, 0.22))
			_box(beams, Vector3(0, deck + 0.85, side * (w * 0.5 + 0.05)), Vector3(len, 0.1, 0.1))
			var posts := int(len / 2.2) + 1
			for i in posts:
				var t := -len * 0.5 + i * len / maxf(posts - 1, 1)
				_box(beams, Vector3(t, deck + 0.2, side * (w * 0.5 + 0.05)), Vector3(0.16, 1.8, 0.16))
		var mi := MeshInstance3D.new()
		var mesh := planks.commit()
		mesh.surface_set_material(0, wood)
		beams.commit(mesh)
		mesh.surface_set_material(1, dark)
		mi.mesh = mesh
		mi.transform = Transform3D(Basis(Vector3.UP, -atan2(dir.y, dir.x)), Vector3(mid.x, 0.0, mid.y))
		root.add_child(mi)
	stats["bridges"] = field.bridges.size()


func _box(st: SurfaceTool, c: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var faces := [[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP]]
	for f in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := c + nrm * h
		var du := u * h
		var dv := v * h
		var q := [o - du - dv, o + du - dv, o + du + dv, o - du + dv]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(nrm)
			st.add_vertex(q[idx])


## Set pieces (ruins, temples, graveyards...) listed in field.props: CC0 models from
## assets/props3d, batched per model like the trees.
func _props() -> void:
	for pr in field.props:
		var model := "props3d/" + String(pr[0])
		var pos: Vector2 = pr[1]
		var p := _proto(model)
		var s: float = pr[3]
		var y := field.height_at(pos.x, pos.y)
		# On a slope, sink the model to the lowest corner of its footprint so it never floats.
		var aabb: AABB = (p[1] as Transform3D) * (p[0] as Mesh).get_aabb()
		var r := maxf(aabb.size.x, aabb.size.z) * 0.4 * s
		for d in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
			y = minf(y, field.height_at(pos.x + d.x, pos.y + d.y))
		var xf := Transform3D(Basis(Vector3.UP, float(pr[2])).scaled(Vector3.ONE * s), Vector3(pos.x, y - 0.05, pos.y)) \
			* (p[1] as Transform3D)
		var key := "%s:%d:%d" % [model, int(floor(pos.x / CHUNK)), int(floor(pos.y / CHUNK))]
		if not _batches.has(key):
			_batches[key] = []
		_batches[key].append(xf)
		stats["props"] = int(stats.get("props", 0)) + 1


# --- Decoration ----------------------------------------------------------------

func _proto(model: String) -> Array:
	if _protos.has(model):
		return _protos[model]
	if model == "grass":
		_protos[model] = [_grass_mesh(), Transform3D.IDENTITY, 1.0]
		return _protos[model]
	var path := ("res://assets/%s.glb" % model) if model.begins_with("props3d/") else (NATURE % model)
	var scn: Node3D = (load(path) as PackedScene).instantiate()
	var mi: MeshInstance3D = scn.find_children("*", "MeshInstance3D", true, false)[0]
	var base := _rel_transform(scn, mi)
	var mesh: Mesh = mi.mesh
	if model in LIE:
		var bb := base * mesh.get_aabb()
		if bb.size.y > maxf(bb.size.x, bb.size.z):
			base = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3.ZERO) * base
	if model.begins_with("props3d/"):
		mesh = _stone_props(mesh)
	if LIFT.has(model):
		mesh = mesh.duplicate()
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i) as StandardMaterial3D
			if m != null:
				m = m.duplicate()
				m.albedo_color = m.albedo_color * LIFT[model]
				mesh.surface_set_material(i, m)
	var aabb := base * mesh.get_aabb()
	# Feet on the ground: lift so the model's lowest point sits at y = 0.
	base.origin.y -= aabb.position.y
	var p := [mesh, base, maxf(aabb.size.y, 0.01)]
	scn.free()
	_protos[model] = p
	return p


## Grey, untextured surfaces of a set piece get the rock texture (world triplanar, so big
## and small pieces share one grain), keeping their tint; wood, iron and paint stay as they are.
func _stone_props(mesh: Mesh) -> Mesh:
	var out: Mesh = mesh.duplicate()
	for i in out.get_surface_count():
		var m := out.surface_get_material(i) as StandardMaterial3D
		if m == null or m.albedo_texture != null or m.metallic > 0.3 or m.albedo_color.s > 0.18:
			continue
		if not _stone_mats.has(m):
			var n: StandardMaterial3D = m.duplicate()
			n.albedo_texture = load(STONE_ALBEDO)
			n.normal_enabled = true
			n.normal_texture = load(STONE_NORMAL)
			n.normal_scale = 0.8
			n.uv1_triplanar = true
			n.uv1_world_triplanar = true
			n.uv1_scale = Vector3.ONE * 0.4
			n.albedo_color = Color(m.albedo_color.r * 1.35, m.albedo_color.g * 1.3, m.albedo_color.b * 1.3)
			_stone_mats[m] = n
		out.surface_set_material(i, _stone_mats[m])
	return out


## A grass tuft: three crossed cards with a drawn blade texture, 1 m tall before scaling.
func _grass_mesh() -> ArrayMesh:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.42, 0.48, 0.28, 0.0))  # blade colour under the alpha, so mipmaps stay green
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for b in 16:
		var x0 := rng.randf_range(6.0, 58.0)
		var lean := rng.randf_range(-10.0, 10.0)
		var top := rng.randf_range(4.0, 30.0)
		var shade := rng.randf_range(0.75, 1.0)
		for y in range(63, int(top), -1):
			var t := (63.0 - y) / (63.0 - top)
			var cx := x0 + lean * t * t
			var half := lerpf(1.6, 0.3, t)
			for x in range(int(cx - half), int(cx + half) + 1):
				if x >= 0 and x < 64:
					var c := Color(0.55, 0.62, 0.38) * lerpf(0.45, 1.0, t) * shade
					img.set_pixel(x, y, Color(c, 1.0))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.vertex_color_use_as_albedo = true  # per-tuft biome tint (MultiMesh colours)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.roughness = 1.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in 3:
		var a := q * PI / 3.0
		var d := Vector3(cos(a), 0.0, sin(a)) * 0.45
		var v := [-d, d, d + Vector3.UP, -d + Vector3.UP]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		# Both windings with an upward normal: lit like the ground from either side
		# (a culling-disabled card would flip the normal on its back and go black).
		for idx in [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])
	st.set_material(mat)
	return st.commit()


func _rel_transform(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _place(model: String, sizes: Array, x: float, z: float, rng: RandomNumberGenerator, sink: float = 0.1,
		tilt: float = 0.0, color := Color.WHITE, at_y: float = NAN) -> void:
	var p := _proto(model)
	var want := rng.randf_range(sizes[0], sizes[1])
	var s: float = want / float(p[2])
	var b := Basis(Vector3.UP, rng.randf() * TAU)
	if tilt > 0.0:
		b = Basis(Vector3(rng.randf() - 0.5, 0.0, rng.randf() - 0.5).normalized(), rng.randf() * tilt) * b
	var y := (field.height_at(x, z) - sink * want) if is_nan(at_y) else at_y
	var xf := Transform3D(b.scaled(Vector3.ONE * s), Vector3(x, y, z)) * (p[1] as Transform3D)
	var key := "%s:%d:%d" % [model, int(floor(x / CHUNK)), int(floor(z / CHUNK))]
	if not _batches.has(key):
		_batches[key] = []
	_batches[key].append(xf)
	if model == "grass":
		if not _colors.has(key):
			_colors[key] = []
		_colors[key].append(color)
	stats[model] = int(stats.get(model, 0)) + 1


func _pick(d: Dictionary, rng: RandomNumberGenerator) -> String:
	var keys := d.keys()
	keys.sort()
	return keys[rng.randi() % keys.size()]


## Size range of any decoration model.
static func size_of(model: String) -> Array:
	for d: Dictionary in [TREES, DEAD, ROCKS, BUSHES, COVER, SCENERY]:
		if d.has(model):
			return d[model]
	return []


## A model of one kind ("trees", "dead", "rocks", "bushes", "cover", "litter") for the biome
## at sample (i, j): that biome's own scenery list when it has one, else the shared set.
## Blended edges pick a biome by its weight, so two lands mingle where they meet.
func _scenery(kind: String, i: int, j: int, rng: RandomNumberGenerator) -> String:
	var w := field.biome_weights(i, j)
	var r := rng.randf()
	var slot := 0
	for k in mini(w.size(), field.biomes.size()):
		r -= w[k]
		slot = k
		if r <= 0.0:
			break
	var sc: Dictionary = (field.biomes[slot] as Dictionary).get("scenery", {})
	if kind == "litter":
		# Litter takes litter_share of the low cover.
		var lit: Array = sc.get("litter", [])
		if lit.is_empty() or rng.randf() >= float(sc.get("litter_share", 0.0)):
			return ""
		return lit[rng.randi() % lit.size()]
	var own: Array = sc.get(kind, [])
	if not own.is_empty():
		return own[rng.randi() % own.size()]
	var d: Dictionary = {"trees": TREES, "dead": DEAD, "rocks": ROCKS, "bushes": BUSHES, "cover": COVER}[kind]
	return _pick(d, rng)


## Scatters decoration by the field's densities. Purely visual: a seeded generator
## of its own, so the same map always looks the same.
func _decorate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 17
	var cell := 1.0 / TerrainField.RES
	var area := cell * cell
	for j in field.sh:
		for i in field.sw:
			var k := j * field.sw + i
			var x := field.origin.x + i * cell
			var z := field.origin.y + j * cell
			var td: float = field.tree_d[k] * field.biome_value(i, j, "trees")
			var rd: float = field.rock_d[k]
			var bd: float = field.bush_d[k] * field.biome_value(i, j, "bushes")
			if td <= 0.0 and rd <= 0.0 and bd <= 0.0:
				continue
			var jx := x + rng.randf_range(-0.5, 0.5) * cell
			var jz := z + rng.randf_range(-0.5, 0.5) * cell
			var tall_ok := jz <= field.tall_max_z
			var roll := rng.randf()
			if tall_ok and roll < td * area:
				var sp := field.splat.get_pixel(i, j)
				var dead := sp.a > 0.35 or field.heights[k] > 9.0 or rng.randf() < field.biome_value(i, j, "dead_trees")
				var m := _scenery("dead" if dead else "trees", i, j, rng)
				_place(m, size_of(m), jx, jz, rng)
			elif tall_ok and roll < (td + rd) * area:
				var m := _scenery("rocks", i, j, rng)
				_place(m, size_of(m), jx, jz, rng, 0.3, 0.5)
			elif roll < (td + rd + bd) * area:
				# Mostly low cover on open land; leafy bushes along wood edges; now and then
				# the biome's litter (fallen logs, stumps, fungus).
				var edge := field.splat.get_pixel(i, j).b > 0.15
				var m := _scenery("litter", i, j, rng)
				if m == "":
					m = _scenery("bushes" if tall_ok and (edge or rng.randf() < 0.3) else "cover", i, j, rng)
				_place(m, size_of(m), jx, jz, rng, 0.05)
	_water_plants(rng)
	_grass(seed_value)
	_flush()


## Floating plants (lily pads) on still, shallow water in biomes that list "water" scenery.
func _water_plants(rng: RandomNumberGenerator) -> void:
	var cell := 1.0 / TerrainField.RES
	for j in range(0, field.sh, 2):
		for i in range(0, field.sw, 2):
			var h: float = field.heights[j * field.sw + i]
			if h > field.water_level - 0.08 or h < field.water_level - 0.9 or rng.randf() > 0.12:
				continue
			var w := field.biome_weights(i, j)
			var slot := 0
			for k in mini(w.size(), field.biomes.size()):
				if w[k] > w[slot]:
					slot = k
			var own: Array = (field.biomes[slot] as Dictionary).get("scenery", {}).get("water", [])
			if own.is_empty() or field.biome_value(i, j, "lava") > 0.5:
				continue
			var m: String = own[rng.randi() % own.size()]
			var x := field.origin.x + (i + rng.randf_range(-1.0, 1.0)) * cell
			var z := field.origin.y + (j + rng.randf_range(-1.0, 1.0)) * cell
			_place(m, size_of(m), x, z, rng, 0.0, 0.0, Color.WHITE, field.water_level + 0.01)


func _grass(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 104729 + 3
	var cell := 1.0 / TerrainField.RES
	var p := GRASS_DENSITY * cell * cell
	var clumps := FastNoiseLite.new()
	clumps.seed = seed_value + 31
	clumps.frequency = 0.09
	for j in field.sh:
		for i in field.sw:
			# Tufts grow in clumps: dense where the noise is high, none where it is low.
			var c := clampf(clumps.get_noise_2d(i * cell, j * cell) * 2.5 + 0.5, 0.0, 2.0)
			if rng.randf() >= p * c * field.biome_value(i, j, "tufts"):
				continue
			var k := j * field.sw + i
			var sp := field.splat.get_pixel(i, j)
			if sp.r > 0.25 or sp.g > 0.3 or field.heights[k] < field.water_level + 0.15 or field.heights[k] > 8.0:
				continue
			var x := field.origin.x + (i + rng.randf_range(-0.5, 0.5)) * cell
			var z := field.origin.y + (j + rng.randf_range(-0.5, 0.5)) * cell
			var bw := field.biome_weights(i, j)
			var tint := Color(0, 0, 0)
			for b in bw.size():
				if bw[b] > 0.0:
					tint += Biomes.color(field.biomes[b], "tuft") * bw[b]
			_place("grass", GRASS["grass"], x, z, rng, 0.0, 0.0, Color(tint, 1.0))


func _flush() -> void:
	var root := Node3D.new()
	root.name = "Decoration"
	add_child(root)
	var keys := _batches.keys()
	keys.sort()
	for key: String in keys:
		var model := key.split(":")[0]
		var xfs: Array = _batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = _colors.has(key)
		mm.mesh = _proto(model)[0]
		mm.instance_count = xfs.size()
		for n in xfs.size():
			mm.set_instance_transform(n, xfs[n])
			if mm.use_colors:
				mm.set_instance_color(n, _colors[key][n])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if BUSHES.has(model) or COVER.has(model) or (SCENERY.has(model) and float(SCENERY[model][1]) < 1.3):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 90.0
		elif model == "grass":
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 65.0
		root.add_child(mmi)
	_batches.clear()
	_colors.clear()


# --- Sky and light -------------------------------------------------------------

## Sky, light, fog and weather live in Atmosphere3D (atmosphere_3d.gd).
func _environment() -> void:
	atmosphere = Atmosphere3D.create(_seed, field.biome_names[0] if not field.biome_names.is_empty() else "")
	add_child(atmosphere)
	environment = atmosphere.environment
	sun = atmosphere.sun
