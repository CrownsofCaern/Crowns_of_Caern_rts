extends SceneTree
## Renders the 3D world layer for a look: a skirmish map and the battle preset.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/world3d_shots.gd -- <out dir> [seed] [skirmish|battle|weather|materials|biomes|all] [base biome] [east faction]

var out := "/tmp/world3d"
var seed_value := 101
var only := ""
var biome := ""
var east_faction := "hollow"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		seed_value = int(args[1])
	if args.size() > 2:
		only = args[2]  ## "skirmish" or "battle"
	if args.size() > 3:
		biome = args[3]  ## base biome (data/biomes.json); homes keep their factions' biomes
	if args.size() > 4:
		east_faction = args[4]  ## the east player's faction (its home biome), west is concord
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/" + name + ".jpg", 0.88)
	print("saved ", name)


func _cam(target: Vector3, dist: float, pitch: float, yaw: float, fov: float = 35.0) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 800.0
	root.add_child(cam)
	var dir := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(-pitch)) * Vector3(0, 0, 1)
	cam.look_at_from_position(target + dir * dist, target)
	cam.make_current()
	return cam


func _run() -> void:
	root.size = Vector2i(1600, 900)
	if only == "weather":
		await _weather()
		quit()
		return
	if only == "biomes":
		await _biomes()
		quit()
		return
	if only == "materials":
		await _materials()
		quit()
		return
	if only != "battle":
		await _skirmish()
	if only != "skirmish":
		await _battle()
	quit()


func _skirmish() -> void:
	var t0 := Time.get_ticks_msec()
	var w := SkirmishScenario.build_skirmish(seed_value, ["concord", east_faction])
	var f := TerrainField.new()
	SimTerrain.build(f, w, seed_value, biome)
	var t1 := Time.get_ticks_msec()
	var scene := MapScene3D.create(f, seed_value)
	root.add_child(scene)
	print("field %d ms, scene %d ms, decoration %s" % [t1 - t0, Time.get_ticks_msec() - t1, scene.stats])
	var mid := Vector3(f.play_w * 0.5, 0.0, f.play_h * 0.5)
	var home := TerrainField.to_world(_home(w, 0))
	var cam := _cam(Vector3(home.x, 0, home.y), 45.0, 55.0, 0.0)
	await _shot("01_rts_home")
	cam.queue_free()
	cam = _cam(Vector3(mid.x, 0, mid.z), 45.0, 55.0, 0.0)
	await _shot("02_rts_centre")
	cam.queue_free()
	cam = _cam(mid, 175.0, 60.0, 0.0)
	await _shot("03_whole_map")
	cam.queue_free()
	cam = _cam(Vector3(home.x + 10, 0, home.y), 30.0, 22.0, -60.0, 50.0)
	await _shot("04_low_angle")
	cam.queue_free()
	# The second home, in the east faction's biome.
	var east := TerrainField.to_world(_home(w, 1))
	cam = _cam(Vector3(east.x, 0, east.y), 45.0, 55.0, 0.0)
	await _shot("07_east_home")
	cam.queue_free()
	cam = _cam(Vector3(east.x - 8, 0, east.y), 30.0, 22.0, 60.0, 50.0)
	await _shot("08_east_low_angle")
	cam.queue_free()
	scene.queue_free()
	await process_frame


static func _home(w: SimWorld, owner: int) -> Vector2:
	for s: Sector in w.economy.sectors:
		if s.home_of == owner:
			return s.center
	return w.economy.sectors[0].center


func _battle() -> void:
	var bf := TerrainField.new()
	bf.build_battlefield(80, 50, seed_value, Vector2(30.0, 13.0), 12.0, biome)
	var bs := MapScene3D.create(bf, seed_value)
	root.add_child(bs)
	print("battlefield decoration %s" % bs.stats)
	var cam := _cam(Vector3(0, 0, 0), 38.0, 35.0, 0.0, 45.0)
	await _shot("05_battlefield")
	cam.queue_free()
	cam = _cam(Vector3(0, 0, -5), 110.0, 55.0, 0.0)
	await _shot("06_battlefield_top")
	cam.queue_free()
	bs.queue_free()


## The RTS view at a home settlement under clear sky, rain and a storm (mid-flash).
func _weather() -> void:
	var w := SkirmishScenario.build_skirmish(seed_value, ["concord", east_faction])
	var f := TerrainField.new()
	SimTerrain.build(f, w, seed_value, biome)
	var scene := MapScene3D.create(f, seed_value)
	root.add_child(scene)
	var home := TerrainField.to_world(_home(w, 0))
	var cam := _cam(Vector3(home.x, 0, home.y), 40.0, 55.0, 0.0)
	var a := scene.atmosphere
	a.muted = true
	a.set_process(false)  # frames take about a second here: hold each look still
	for spell in ["clear", "rain", "storm"]:
		a.set_weather(spell, 999.0)
		a.cloud = Atmosphere3D.SPELLS[spell]["cloud"]
		a.rain = Atmosphere3D.SPELLS[spell]["rain"]
		a._process(0.0)
		await _shot("w_" + spell)
	a.strike()
	a.step(0.03)
	a._process(0.0)
	await _shot("w_storm_flash")
	cam.queue_free()
	scene.queue_free()
	await process_frame


## Close look at units, heroes and a building with the imported (glossy) materials, then matte.
func _materials() -> void:
	var bf := TerrainField.new()
	bf.build_battlefield(80, 50, seed_value, Vector2(30.0, 13.0), 12.0, biome)
	var scene := MapScene3D.create(bf, seed_value)
	root.add_child(scene)
	var a := scene.atmosphere
	a.matte_models = false
	a.set_process(false)
	a.muted = true
	var group := Node3D.new()
	root.add_child(group)
	var models := ["units3d/iron_margrave", "units3d/shieldwarden", "units3d/anvil_guard", "heroes3d/anvilbreaker",
		"units3d/gibbet_knight", "units3d/de_obsidian_guard", "units3d/lightbearer", "units3d/fm_shellback"]
	for i in models.size():
		var path := "res://assets/%s.glb" % models[i]
		if not ResourceLoader.exists(path):
			continue
		var m: Node3D = (load(path) as PackedScene).instantiate()
		m.position = Vector3(-7.0 + i * 2.0, 0.0, (i % 2) * 1.5)
		m.rotation.y = 0.5
		group.add_child(m)
	var b: Node3D = (load("res://assets/buildings3d/c_dw3.glb") as PackedScene).instantiate()
	b.position = Vector3(0, 0, -9)
	group.add_child(b)
	var cam := _cam(Vector3(0, 1.2, -1.5), 15.0, 22.0, 0.0, 45.0)
	await _shot("m_before")
	MatteMaterials.apply(group)
	await _shot("m_after")
	cam.queue_free()
	group.queue_free()
	scene.queue_free()
	await process_frame


## Every biome's ground on the battlefield preset, one still each (b_<biome>.jpg).
func _biomes() -> void:
	var names: Array = Biomes.data()["biomes"].keys()
	names.sort()
	for b in names:
		var bf := TerrainField.new()
		bf.build_battlefield(80, 50, seed_value, Vector2(30.0, 13.0), 12.0, b)
		var bs := MapScene3D.create(bf, seed_value)
		bs.atmosphere.set_process(false)
		bs.atmosphere.muted = true
		root.add_child(bs)
		var cam := _cam(Vector3(0, 0, -6), 34.0, 40.0, 0.0, 45.0)
		await _shot("b_" + b)
		cam.queue_free()
		bs.queue_free()
		await process_frame
