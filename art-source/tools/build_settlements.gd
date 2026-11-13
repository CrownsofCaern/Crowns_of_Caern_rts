extends SceneTree
## Assembles the neutral Warbound settlements from the 3D pieces:
##
##   godot --headless --path . --script res://tools/assets/build_settlements.gd
##
## Pieces: assets/source/buildings3d/pieces/<key>.glb (export_buildings.gd; metres, door at +Z).
## Layouts: "settlements" in assets/source/buildings3d/buildings.json, one list of
## [piece, x, z, yaw_degrees or null] per size. yaw null turns the door toward the yard centre (0, 0).
## Each size should hold the pieces of the one before plus more, so a settlement visibly grows.
## Output: assets/settlements3d/<size>.glb (feet y = 0, centred, front toward +Z).

const SPEC := "res://assets/source/buildings3d/buildings.json"
const PIECES := "res://assets/source/buildings3d/pieces/"
const OUT := "res://assets/settlements3d/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	var layouts: Dictionary = spec.get("settlements", {})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var cache := {}
	for size in layouts:
		var wrap := Node3D.new()
		wrap.name = String(size)
		var count := 0
		for row in layouts[size]:
			var key := String(row[0])
			if not cache.has(key):
				cache[key] = _load(PIECES + key + ".glb")
			if cache[key] == null:
				push_error("missing piece " + key)
				continue
			var piece := (cache[key] as Node3D).duplicate() as Node3D
			piece.name = "%s_%d" % [key, count]
			var pos := Vector3(float(row[1]), 0.0, float(row[2]))
			var yaw: float
			if row.size() > 3 and row[3] != null:
				yaw = float(row[3])
			elif pos.length() < 0.01:
				yaw = 0.0
			else:
				var d := -pos.normalized()
				yaw = rad_to_deg(atan2(d.x, d.z))
			piece.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos)
			wrap.add_child(piece)
			_own(piece, wrap)
			count += 1
		var path := OUT + String(size) + ".glb"
		var doc := GLTFDocument.new()
		doc.image_format = "JPEG"
		doc.lossy_quality = 0.85
		var st := GLTFState.new()
		if doc.append_from_scene(wrap, st) != OK or doc.write_to_filesystem(st, ProjectSettings.globalize_path(path)) != OK:
			push_error("cannot write " + path)
		else:
			print("%s: %d pieces, %d tris, %d KB" % [size, count, _tris(wrap), FileAccess.get_file_as_bytes(path).size() / 1024])
		wrap.free()
	for key in cache:
		if cache[key] != null:
			(cache[key] as Node).free()
	quit()


func _load(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		return null
	return doc.generate_scene(st) as Node3D


func _tris(top: Node) -> int:
	var n := 0
	for node in top.find_children("*", "MeshInstance3D", true, false):
		var m := (node as MeshInstance3D).mesh
		for s in m.get_surface_count():
			n += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
	node.owner = owner_node
