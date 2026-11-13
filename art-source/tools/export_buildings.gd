extends SceneTree
## Slims the raw Tripo building GLBs into light static GLBs for the Warbound RTS:
##
##   godot --headless --path . --script res://tools/assets/export_buildings.gd -- [--tris N] [--tex PX] [keys...]
##
## Input: assets/source/buildings3d/buildings.json (entries with a "raw" GLB on disk; no keys = all).
## Output: assets/buildings3d/<key>.glb; resource piles (group "resource") go to assets/resources3d/, and
## neutral settlement pieces (group "neutral") to assets/source/buildings3d/pieces/, where
## build_settlements.gd assembles them into assets/settlements3d/<size>.glb. Each file has
## - the mesh decimated to about --tris triangles (default 12000; entry "tris" overrides) and unused
##   vertices dropped, textures --tex px (default 1024) stored as JPEG;
## - metres: the footprint's wider side scaled to the entry "width_m" (default 3.6), centred on x/z,
##   feet on y = 0, turned by the entry "yaw_degrees" (default -90: Tripo puts the left face of an
##   isometric painting at +X, and the town art draws the entrance on that face) so the door faces +Z.
## The decimation copies _slim/_compact from tools/assets/export_live_units.gd (units).

const SPEC := "res://assets/source/buildings3d/buildings.json"
## Output folder per entry group (default assets/buildings3d/).
const DIRS := {"resource": "res://assets/resources3d/", "neutral": "res://assets/source/buildings3d/pieces/",
	"fort": "res://spinoff/warbound/assets/forts3d/"}

var _tris := 12000
var _tex := 1024


func _initialize() -> void:
	var keys: Array[String] = []
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--tris":
				i += 1
				_tris = int(args[i])
			"--tex":
				i += 1
				_tex = int(args[i])
			_:
				keys.append(args[i])
		i += 1
	_run.call_deferred(keys)


func _run(keys: Array[String]) -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	var buildings: Dictionary = spec["buildings"]
	var names: Array = keys if not keys.is_empty() else buildings.keys()
	names.sort()
	for key in names:
		var entry: Dictionary = buildings[key]
		if not entry.has("raw") or not FileAccess.file_exists("res://" + String(entry["raw"])):
			continue
		print(_export(String(key), entry))
	quit()


func _export(key: String, entry: Dictionary) -> String:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path("res://" + String(entry["raw"])), st) != OK:
		return key + ": cannot read"
	var model := doc.generate_scene(st) as Node3D
	root.add_child(model)
	var target := int(entry.get("tris", _tris))
	var tris := 0
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var total := 0
	for node in meshes:
		var m := (node as MeshInstance3D).mesh
		for s in m.get_surface_count():
			total += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	for node in meshes:
		tris += _slim(node as MeshInstance3D, target, total, bool(entry.get("metal", false)), entry.get("tint", [1.0, 1.0, 1.0]))
	var yaw := float(entry.get("yaw_degrees", -90.0))
	var turn := Node3D.new()
	turn.name = "Turn"
	turn.rotation_degrees.y = yaw
	root.remove_child(model)
	turn.add_child(model)
	root.add_child(turn)
	var box := _bounds(turn)
	var k := float(entry.get("width_m", 3.6)) / maxf(0.001, maxf(box.size.x, box.size.z))
	root.remove_child(turn)
	var wrap := Node3D.new()
	wrap.name = key
	turn.scale = Vector3.ONE * k
	turn.position = Vector3(-box.get_center().x * k, -box.position.y * k, -box.get_center().z * k)
	wrap.add_child(turn)
	_own(turn, wrap)
	var dir := String(DIRS.get(String(entry.get("group", "")), "res://assets/buildings3d/"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir + key + ".glb"
	var out := GLTFDocument.new()
	out.image_format = "JPEG"
	out.lossy_quality = 0.85
	var ost := GLTFState.new()
	if out.append_from_scene(wrap, ost) != OK or out.write_to_filesystem(ost, ProjectSettings.globalize_path(path)) != OK:
		wrap.free()
		return key + ": cannot write " + path
	wrap.free()
	return "%s: %d -> %d tris, %.1f x %.1f x %.1f m, %d KB" % [key, total, tris, box.size.x * k, box.size.y * k,
		box.size.z * k, FileAccess.get_file_as_bytes(path).size() / 1024]


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
	node.owner = owner_node


func _bounds(top: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in top.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var b: AABB = top.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _compact(arrays: Array) -> Array:
	# Drop the vertices the decimated index list no longer uses.
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var remap := PackedInt32Array()
	remap.resize(count)
	remap.fill(-1)
	var keep := PackedInt32Array()
	for v in index:
		if remap[v] < 0:
			remap[v] = keep.size()
			keep.append(v)
	var new_index := PackedInt32Array()
	new_index.resize(index.size())
	for n in index.size():
		new_index[n] = remap[index[n]]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for slot in Mesh.ARRAY_MAX:
		var src = arrays[slot]
		if src == null or slot == Mesh.ARRAY_INDEX:
			continue
		var stride: int = src.size() / count
		var dst = src.duplicate()
		dst.resize(keep.size() * stride)
		for n in keep.size():
			for c in stride:
				dst[n * stride + c] = src[keep[n] * stride + c]
		out[slot] = dst
	out[Mesh.ARRAY_INDEX] = new_index
	return out


func _slim(mi: MeshInstance3D, target: int, total: int, metal: bool, tint: Array) -> int:
	# Decimate each surface and shrink the textures.
	var src := mi.mesh as ArrayMesh
	var out := ArrayMesh.new()
	var tris := 0
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var want := int(float(target) * index.size() / 3.0 / maxf(1.0, total)) * 3
		if want < index.size():
			var st := SurfaceTool.new()
			st.create_from_arrays(arrays)
			var lod := st.generate_lod(0.5, want)
			if lod.size() >= 3:
				arrays[Mesh.ARRAY_INDEX] = lod
		arrays = _compact(arrays)
		tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := src.surface_get_material(s)
		if mat is StandardMaterial3D:
			mat = (mat as StandardMaterial3D).duplicate()
			# Tripo's PBR map makes stone and slate read as polished metal; buildings are matte
			# unless the entry says "metal": true (iron flasks, ore).
		if mat is StandardMaterial3D and not metal:
			mat.metallic = 0.0
			mat.metallic_texture = null
			mat.roughness = 1.0
			mat.metallic_specular = 0.25
		if mat is StandardMaterial3D:
			# Entry "tint" [r, g, b] multiplies the albedo (Tripo painted the ore pile pink).
			mat.albedo_color = Color(float(tint[0]), float(tint[1]), float(tint[2]))
			for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_METALLIC,
					BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION, BaseMaterial3D.TEXTURE_EMISSION]:
				var tex: Texture2D = mat.get_texture(slot)
				if tex != null and tex.get_width() > _tex:
					var img := tex.get_image()
					if img.is_compressed():
						img.decompress()
					img.resize(_tex, _tex, Image.INTERPOLATE_LANCZOS)
					mat.set_texture(slot, ImageTexture.create_from_image(img))
		out.surface_set_material(s, mat)
	mi.mesh = out
	return tris
