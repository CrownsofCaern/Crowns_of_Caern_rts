extends SceneTree
## Converts picked Quaternius "Ultimate Stylized Nature" (CC0) FBX models into small GLBs
## with 512 px textures, darkened toward the art bible. Run inside a scratch Godot project
## that holds the pack at res://ultimate-stylized-nature/ (git clone
## https://github.com/walterpalladino/godot-quaternius-ultimate-stylized-nature):
##   godot --headless --path <scratch> --script res://convert_nature.gd -- <out dir>
## The GLBs land in assets/nature/ of Warbound; this script is kept for re-runs.

const SRC := "res://ultimate-stylized-nature/sources/"
const PICK := ["PineTree_1", "PineTree_2", "PineTree_3", "PineTree_5", "NormalTree_2", "NormalTree_4",
	"DeadTree_1", "DeadTree_3", "DeadTree_4", "DeadTree_7", "DeadTree_9",
	"Rock_1", "Rock_2", "Rock_3", "Rock_4", "Rock_5", "Bush", "Bush_Large", "Bush_Small", "Plant_1",
	# Second pass (fuller maps): birches, maples, more trees, ferns, grass and muted flowers.
	"BirchTree_1", "BirchTree_2", "BirchTree_3", "MapleTree_1", "MapleTree_3", "NormalTree_1", "NormalTree_3",
	"NormalTree_5", "PineTree_4", "DeadTree_2", "DeadTree_5", "DeadTree_6", "DeadTree_8", "DeadTree_10",
	"Plant_2", "Grass_Large", "Grass_Small", "Flower_3_Clump", "Flower_4_Clump"]
## Material name -> [albedo file, tint]
const MATS := {
	"PineTree_Bark": ["PineTree_Bark.png", Color(0.62, 0.55, 0.5)],
	"PineTree_Leaves": ["PineTree_Leaves.png", Color(0.55, 0.62, 0.5)],
	"NormalTree_Bark": ["NormalTree_Bark.png", Color(0.55, 0.5, 0.48)],
	"NormalTree_Leaves": ["NormalTree_Leaves_Dark.png", Color(0.6, 0.62, 0.48)],
	"Bush_Leaves": ["Bush_Leaves.png", Color(0.6, 0.62, 0.5)],
	"Rock": ["Rocks.png", Color(0.58, 0.55, 0.56)],
	"Plant": ["Leaves_BW.png", Color(0.32, 0.36, 0.24)],
	"BirchTree_Bark": ["BirchTree_Bark.png", Color(0.5, 0.47, 0.45)],
	"BirchTree_Leaves": ["BirchTree_Leaves.png", Color(0.5, 0.5, 0.36)],
	"MapleTree_Bark": ["MapleTree_Bark.png", Color(0.5, 0.45, 0.42)],
	"MapleTree_Leaves": ["MapleTree_Leaves.png", Color(0.62, 0.42, 0.34)],
	"Grass": ["Grass.png", Color(0.42, 0.44, 0.3)],
	"Flowers": ["Flowers.png", Color(0.55, 0.38, 0.38)],
}


func _tex(file: String) -> ImageTexture:
	var img: Image = (load(SRC + "Textures/" + file) as Texture2D).get_image()
	img.decompress()
	if img.get_width() > 512:
		img.resize(512, 512 * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _init() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var cache := {}
	for n in PICK:
		var scn: Node3D = load(SRC + "FBX/%s.fbx" % n).instantiate()
		var root := Node3D.new()
		root.name = n
		for c in scn.find_children("*", "MeshInstance3D", true, false):
			var src := c as MeshInstance3D
			var mesh: ArrayMesh = src.mesh.duplicate()
			for i in mesh.get_surface_count():
				var old := mesh.surface_get_material(i)
				var key := old.resource_name if old != null else ""
				var spec: Array = MATS.get(key, MATS.get(key.split("_")[0], ["Rocks.png", Color(0.6, 0.6, 0.6)]))
				if not cache.has(key):
					var m := StandardMaterial3D.new()
					m.resource_name = key
					m.albedo_texture = _tex(spec[0])
					m.albedo_color = spec[1]
					m.roughness = 0.9
					if "Leaves" in key or key in ["Plant", "Grass", "Flowers"]:
						m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
						m.alpha_scissor_threshold = 0.4
						m.cull_mode = BaseMaterial3D.CULL_DISABLED
					cache[key] = m
				mesh.surface_set_material(i, cache[key])
			var mi := MeshInstance3D.new()
			mi.name = src.name
			mi.mesh = mesh
			# The mesh data is already Y-up; the FBX node only carries Blender's axis
			# rotation, which would lay the model on its side.
			mi.transform = Transform3D.IDENTITY
			root.add_child(mi)
			mi.owner = root
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		doc.append_from_scene(root, state)
		var path := "%s/%s.glb" % [out, n.to_snake_case()]
		doc.write_to_filesystem(state, path)
		print("wrote ", path)
	quit()
