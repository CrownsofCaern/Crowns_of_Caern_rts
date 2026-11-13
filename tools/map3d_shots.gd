extends SceneTree
## 3D stills of a generated skirmish map: the whole map, both homes, a bridge, the
## biggest lair's set piece, a shrine and a merchant (when the map has them).
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/map3d_shots.gd -- <out dir> <template> [seed] [factions,comma,separated] [shots: map,home0,home1,low0,bridge,lair,lair_rts,plateau0,plateau1,shrines,merchants]

var out := "/tmp/map3d"
var template := "sundered_isles"
var seed_value := 101
var factions: Array = ["concord", "hollow"]
var only: Array = []  ## shot names to take (empty: all)


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	if a.size() > 1:
		template = a[1]
	if a.size() > 2:
		seed_value = int(a[2])
	if a.size() > 3:
		factions = Array(a[3].split(","))
	if a.size() > 4:
		only = Array(a[4].split(","))
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg("%s/%s_%s.jpg" % [out, template, name], 0.85)
	print("saved ", name)


func _cam(target: Vector3, dist: float, pitch: float, yaw: float, fov: float = 35.0) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 1200.0
	root.add_child(cam)
	var dir := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(-pitch)) * Vector3(0, 0, 1)
	cam.look_at_from_position(target + dir * dist, target)
	cam.make_current()
	return cam


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var t0 := Time.get_ticks_msec()
	var w := SkirmishScenario.build_skirmish(seed_value, factions, template)
	var t1 := Time.get_ticks_msec()
	var f := TerrainField.new()
	SimTerrain.build(f, w, seed_value)
	var t2 := Time.get_ticks_msec()
	var scene := MapScene3D.create(f, seed_value)
	root.add_child(scene)
	scene.atmosphere.set_weather("clear", 999.0)
	scene.atmosphere.set_process(false)
	print("%s: sim %d ms, field %d ms, scene %d ms, %s" % [template, t1 - t0, t2 - t1, Time.get_ticks_msec() - t2, scene.stats])
	var info := w.map_info
	var mid := Vector3(f.play_w * 0.5, 0.0, f.play_h * 0.5)
	var shots: Array = [["map", mid, maxf(f.play_w, f.play_h) * 1.45, 62.0, 0.0, 35.0]]
	for o in factions.size():
		var h := TerrainField.to_world(w.economy.hall_of(o).center)
		shots.append(["home%d" % o, Vector3(h.x, 0, h.y), 48.0, 55.0, 0.0, 35.0])
		shots.append(["low%d" % o, Vector3(h.x + 14.0 * (1 - 2 * (o % 2)), 0, h.y), 34.0, 24.0, 70.0 if o % 2 == 0 else -70.0, 50.0])
	if not info["bridges"].is_empty():
		var b: Array = info["bridges"][0]
		var bc := TerrainField.to_world(((b[0] as Vector2) + (b[1] as Vector2)) * 0.5)
		shots.append(["bridge", Vector3(bc.x, 0, bc.y), 34.0, 40.0, 25.0, 40.0])
	var best: Array = []
	for l in info["lairs"]:
		if best.is_empty() or int(l[1]) > int(best[1]):
			best = l
	if not best.is_empty():
		var lc := TerrainField.to_world(best[0])
		shots.append(["lair", Vector3(lc.x, 0, lc.y), 36.0, 38.0, 20.0, 40.0])
		shots.append(["lair_rts", Vector3(lc.x, 0, lc.y), 45.0, 55.0, 0.0, 35.0])  # the game's RTS view
	for i in mini(2, info.get("plateaus", []).size()):
		var pc := TerrainField.to_world(info["plateaus"][i][0])
		shots.append(["plateau%d" % i, Vector3(pc.x, 2.0, pc.y), 46.0, 32.0, 35.0 + 90.0 * i, 45.0])
	for kind in ["shrines", "merchants"]:
		if not info[kind].is_empty():
			var sc := TerrainField.to_world(info[kind][0])
			shots.append([kind, Vector3(sc.x, 0, sc.y), 26.0, 40.0, -20.0, 40.0])
	print("shots: ", shots.map(func(x: Array) -> String: return x[0]))
	for s in shots:
		if not only.is_empty() and not only.has(s[0]):
			continue
		var cam := _cam(s[1], s[2], s[3], s[4], s[5])
		await _shot(s[0])
		cam.queue_free()
	quit()
