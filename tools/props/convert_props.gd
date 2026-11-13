extends SceneTree
## Converts picked CC0 models into Warbound map props (assets/props3d/<id>.glb): one mesh per
## prop, merged from all parts, feet at y = 0, centred, scaled to a height in metres, and
## recoloured toward the art bible (darker, colder stone; bright blue paint turns blood red).
## Sources (all CC0), from github.com/beep2bleep/FreeAssetsByKenneyNLandQuaternius:
##   kgy     Kenney "Graveyard Kit (0.2)"            Models/*.fbx
##   kcastle Kenney "Castle Kit (1.0)"               Models/*.fbx
##   qdun1   Quaternius "Modular Dungeon Pack" (Jan 2018)        FBX/
##   qdun2   Quaternius "Updated Modular Dungeon" (May 2019)     FBX/
##   qmed    Quaternius "Modular Medieval Buildings" (Jul 2017)  FBX/
##   qciv    Quaternius "Civilization Buildings" (May 2018)      FBX/
## Run inside a scratch Godot project that holds those folders at res://src/<key>/:
##   godot --headless --path <scratch> --script res://convert_props.gd -- <out dir>

## id -> [source, height m, tone]; tone: "stone", "wood", "keep" (colours as they are), "bone".
const PICK := {
	"gy_crypt": ["kgy/crypt.fbx", 3.4, "stone"],
	"gy_grave_broken": ["kgy/gravestoneBroken.fbx", 0.9, "stone"],
	"gy_grave_cross": ["kgy/gravestoneCross.fbx", 1.4, "stone"],
	"gy_grave_cross_large": ["kgy/gravestoneCrossLarge.fbx", 1.9, "stone"],
	"gy_grave_decorative": ["kgy/gravestoneDecorative.fbx", 1.1, "stone"],
	"gy_grave_round": ["kgy/gravestoneRound.fbx", 1.0, "stone"],
	"gy_grave_roof": ["kgy/gravestoneRoof.fbx", 1.1, "stone"],
	"gy_grave_debris": ["kgy/gravestoneDebris.fbx", 0.7, "stone"],
	"gy_cross": ["kgy/cross.fbx", 2.4, "stone"],
	"gy_obelisk": ["kgy/pillarObelisk.fbx", 4.2, "stone"],
	"gy_pillar": ["kgy/pillarSquare.fbx", 3.4, "stone"],
	"gy_lantern": ["kgy/lanternDouble.fbx", 2.6, "keep"],
	"gy_fence_iron": ["kgy/fenceIron.fbx", 1.6, "iron"],
	"gy_fence_broken": ["kgy/fenceBroken.fbx", 1.1, "wood"],
	"gy_debris": ["kgy/debris.fbx", 0.8, "stone"],
	"gy_urn": ["kgy/urn.fbx", 0.9, "stone"],
	"gy_coffin": ["kgy/coffin.fbx", 0.6, "wood"],
	"gy_grave": ["kgy/grave.fbx", 0.35, "wood"],
	"cs_wall": ["kcastle/wall.fbx", 5.0, "stone"],
	"cs_wall_half": ["kcastle/wallHalf.fbx", 4.6, "stone"],
	"cs_wall_corner": ["kcastle/wallCorner.fbx", 5.0, "stone"],
	"cs_wall_tower": ["kcastle/wallCornerHalfTower.fbx", 5.0, "stone"],
	"cs_tower_arch": ["kcastle/towerSquareArch.fbx", 5.5, "stone"],
	"cs_tower_base": ["kcastle/towerSquareBase.fbx", 4.0, "stone"],
	"cs_catapult": ["kcastle/siegeCatapult.fbx", 3.0, "wood"],
	"cs_trebuchet": ["kcastle/siegeTrebuchet.fbx", 5.5, "wood"],
	"cs_ballista": ["kcastle/siegeBallista.fbx", 2.2, "wood"],
	"cs_siege_tower": ["kcastle/siegeTower.fbx", 7.5, "wood"],
	"cs_banner": ["kcastle/flagBannerLong.fbx", 5.5, "wood"],
	"dn_column": ["qdun1/Column.fbx", 4.6, "stone"],
	"dn_column_broken": ["qdun1/Column_Broken.fbx", 3.0, "stone"],
	"dn_column_stump": ["qdun1/Column_Broken2.fbx", 1.8, "stone"],
	"dn_bones": ["qdun1/Bones.fbx", 0.45, "bone"],
	"dn_bones_2": ["qdun1/Bones2.fbx", 0.5, "bone"],
	"dn_candelabrum": ["qdun1/Candelabrum_tall.fbx", 1.9, "keep"],
	"dn_arch": ["qdun2/Arch.fbx", 4.6, "stone"],
	"dn_statue_horse": ["qdun2/Statue_Horse.fbx", 3.8, "stone"],
	"dn_pedestal": ["qdun2/Pedestal.fbx", 1.6, "stone"],
	"dn_pedestal_2": ["qdun2/Pedestal2.fbx", 1.7, "stone"],
	"dn_woodfire": ["qdun2/Woodfire.fbx", 0.8, "keep"],
	"dn_coin_pile": ["qdun2/Coin_Pile.fbx", 0.35, "keep"],
	"dn_chest_gold": ["qdun2/Chest_Gold.fbx", 0.9, "keep"],
	"dn_banner": ["qdun2/Banner.fbx", 3.6, "keep"],
	"dn_skull": ["qdun2/Skull.fbx", 0.45, "bone"],
	"dn_spikes": ["qdun2/Spikes.fbx", 1.2, "iron"],
	"dn_column_2": ["qdun2/Column2.fbx", 4.6, "stone"],
	"dn_wall_deco": ["qdun2/Decorative_Wall.fbx", 2.4, "stone"],
	"dn_wall_block": ["qdun2/Wall_Modular.fbx", 3.0, "stone"],
	"dn_barrel": ["qdun2/Barrel.fbx", 1.0, "keep"],
	"dn_crate": ["qdun2/Crate.fbx", 1.0, "keep"],
	"md_watchtower": ["qmed/Watchtower.fbx", 7.0, "wood"],
	"md_watchtower_roof": ["qmed/WatchTowerWRoof.fbx", 8.0, "wood"],
	"md_tower_large": ["qmed/LargeTower.fbx", 10.0, "stone"],
	"md_tower_pointy": ["qmed/PointyTower.fbx", 10.0, "stone"],
	"md_tower": ["qmed/Tower.fbx", 8.5, "stone"],
	"md_gatehouse": ["qmed/TallWallEntrance.fbx", 6.5, "stone"],
	"md_wall_gate": ["qmed/WallEntrance.fbx", 4.5, "stone"],
	"md_wall": ["qmed/Wall.fbx", 4.5, "stone"],
	"tp_pantheon": ["qciv/Pantheon.fbx", 9.0, "stone"],
	"tp_ziggurat": ["qciv/MayanTemple.fbx", 9.5, "stone"],
}


func _init() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var ids := PICK.keys()
	ids.sort()
	for id: String in ids:
		var spec: Array = PICK[id]
		var scn: Node3D = (load("res://src/" + spec[0]) as PackedScene).instantiate()
		var mesh := _merge(scn, spec[2])
		scn.free()
		var ab := mesh.get_aabb()
		var s: float = float(spec[1]) / maxf(ab.size.y, 0.001)
		var mi := MeshInstance3D.new()
		mi.name = id
		mi.mesh = mesh
		# Feet on the ground, centred on the origin, metres.
		mi.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s),
			-Vector3(ab.get_center().x, ab.position.y, ab.get_center().z) * s)
		var root := Node3D.new()
		root.name = id
		root.add_child(mi)
		mi.owner = root
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		doc.append_from_scene(root, state)
		doc.write_to_filesystem(state, "%s/%s.glb" % [out, id])
		root.free()
		print("wrote %s (%.1f x %.1f x %.1f m)" % [id, ab.size.x * s, ab.size.y * s, ab.size.z * s])
	quit()


## All mesh surfaces of a scene in one mesh, node transforms baked in, materials recoloured.
func _merge(scn: Node3D, tone: String) -> ArrayMesh:
	var out := ArrayMesh.new()
	var mats := {}
	for m in scn.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var t := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != scn:
			if cur is Node3D:
				t = (cur as Node3D).transform * t
			cur = cur.get_parent()
		for i in mi.mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.create_from(mi.mesh, i)
			st.generate_normals() if mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_NORMAL] == null else null
			var arr := st.commit_to_arrays()
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for k in v.size():
				v[k] = t * v[k]
			for k in n.size():
				n[k] = (t.basis * n[k]).normalized()
			arr[Mesh.ARRAY_VERTEX] = v
			arr[Mesh.ARRAY_NORMAL] = n
			arr[Mesh.ARRAY_TANGENT] = null
			var old: Material = mi.get_active_material(i)
			var key := old.get_instance_id() if old != null else 0
			if not mats.has(key):
				mats[key] = _recolour(old, tone)
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(out.get_surface_count() - 1, mats[key])
	return out


func _recolour(old: Material, tone: String) -> StandardMaterial3D:
	var c := Color(0.8, 0.8, 0.8)
	var tex: Texture2D = null
	if old is BaseMaterial3D:
		c = (old as BaseMaterial3D).albedo_color
		tex = (old as BaseMaterial3D).albedo_texture
	var m := StandardMaterial3D.new()
	m.roughness = 0.92
	m.albedo_texture = tex
	var lum := c.get_luminance()
	if c.s > 0.25 and c.h > 0.5 and c.h < 0.72:
		c = Color(0.42, 0.07, 0.06)  # bright blue paint -> blood red
	elif tone == "stone":
		# Pale stone -> weathered dark stone, a hint of the original hue.
		var g := 0.2 + lum * 0.28
		c = Color(g, g * 0.97, g * 0.98).lerp(c * 0.5, 0.15)
	elif tone == "iron":
		c = Color(0.12, 0.12, 0.13)
		m.metallic = 0.6
		m.roughness = 0.6
	elif tone == "wood":
		c = Color(c.r * 0.55, c.g * 0.47, c.b * 0.42)
	elif tone == "bone":
		c = Color(0.55, 0.5, 0.42)
	else:
		c = c * Color(0.78, 0.75, 0.74)
	m.albedo_color = c
	return m
