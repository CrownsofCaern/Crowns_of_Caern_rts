extends SceneTree
## Converts the hero weapon meshes from Quaternius' CC0 "Medieval Weapons Pack" (Sept 2018) and
## "RPG Asset Pack" (May 2017) into small GLBs, one per weapon kind, darkened toward the art bible.
## Run inside a scratch Godot project whose res://src/ holds the FBX files (Staff.fbx of the RPG
## pack renamed Staff_RPG.fbx). Source: github.com/beep2bleep/FreeAssetsByKenneyNLandQuaternius,
## "FreeModels by Quaternius[Patreon]/Medieval/".
##   godot --headless --path <scratch> --script res://convert_weapons.gd -- <out dir>
## Output: <kind>.glb, metres, the long axis along +Y, the origin at the grip (shield: its centre).

## kind -> [source file, length in metres along the long axis]
const PICK := {
	"sword": ["Sword_2", 0.95],
	"axe": ["Axe", 0.8],
	"club": ["Hammer_Small", 0.75],
	"great_weapon": ["Sword_Big", 1.45],
	"polearm": ["Spear", 2.1],
	"scythe": ["Scythe", 1.9],
	"bow": ["Bow_Wooden", 1.3],
	"thrown": ["Axe_Small", 0.5],
	"dagger": ["Dagger", 0.45],
	"staff": ["Staff_RPG", 1.7],
	"shield": ["Shield_Heater", 0.85],
}
## Material name -> colour (darker, rougher than the pack's bright low-poly look)
const COLORS := {
	"Steel": Color("5f6369"), "LightSteel": Color("7b7f86"), "DarkSteel": Color("45464a"),
	"LightWood": Color("4f3826"), "DarkWood": Color("3a281c"), "Wood": Color("43301f"),
	"White": Color("b8b2a6"), "Gold": Color("7d6a3e"), "LightGold": Color("8f7a48"),
	"Gem": Color("9a2a22"), "Red": Color("7a2a2a"), "Black": Color("1e1a19"),
}


func _init() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var cache := {}
	for kind in PICK:
		var spec: Array = PICK[kind]
		var scn: Node3D = load("res://src/%s.fbx" % spec[0]).instantiate()
		var meshes := scn.find_children("*", "MeshInstance3D", true, false)
		var box := AABB()
		for i in meshes.size():
			var a: AABB = (meshes[i] as MeshInstance3D).mesh.get_aabb()
			box = a if i == 0 else box.merge(a)
		# The pack's meshes are centimetre-sized and point along +Z (the FBX node rotation is
		# Blender's axis fix-up, dropped here). Long axis -> +Y; the pack's pivot is the grip.
		var long_axis := box.size.z if kind != "shield" else box.size.z
		var s: float = float(spec[1]) / long_axis
		var xf := Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0.0, 0.0)).scaled(Vector3(s, s, s)), Vector3.ZERO)
		var root := Node3D.new()
		root.name = kind
		for c in meshes:
			var src := c as MeshInstance3D
			var mesh: ArrayMesh = src.mesh.duplicate()
			for i in mesh.get_surface_count():
				var old := mesh.surface_get_material(i)
				var key := old.resource_name if old != null else ""
				if not cache.has(key):
					var m := StandardMaterial3D.new()
					m.resource_name = key
					m.albedo_color = COLORS.get(key, Color("5a5a5a"))
					m.roughness = 0.55 if "Steel" in key or "Gold" in key else 0.9
					m.metallic = 0.0
					cache[key] = m
				mesh.surface_set_material(i, cache[key])
			var mi := MeshInstance3D.new()
			mi.name = src.name
			mi.mesh = mesh
			mi.transform = xf
			root.add_child(mi)
			mi.owner = root
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		doc.append_from_scene(root, state)
		var path := "%s/%s.glb" % [out, kind]
		doc.write_to_filesystem(state, path)
		print("wrote ", path)
	quit()
