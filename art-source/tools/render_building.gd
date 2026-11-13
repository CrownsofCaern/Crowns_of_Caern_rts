extends SceneTree
## Review renders of a building GLB (needs a display: xvfb-run -a ... --rendering-driver opengl3):
##
##   godot --path . --rendering-driver opengl3 --script res://tools/assets/render_building.gd -- GLB OUT_PREFIX [px]
##
## Writes OUT_PREFIX_rts.png (the Warbound camera: 55 degrees up, looking toward -Z, a 1.8 m soldier
## marker beside it) and OUT_PREFIX_turn.png (four sides, 90 degrees apart, front first).

var _px := 512


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 2:
		_px = int(args[2])
	_run.call_deferred(args[0], args[1])


func _run(glb: String, prefix: String) -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(glb, st) != OK:
		push_error("cannot read " + glb)
		quit(1)
		return
	var model := doc.generate_scene(st) as Node3D
	var vp := SubViewport.new()
	vp.size = Vector2i(_px, _px)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.13, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.5, 0.55)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.86, 0.72)
	sun.shadow_enabled = true
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.24, 0.27, 0.17)
	ground.material_override = gm
	vp.add_child(ground)
	var pivot := Node3D.new()
	vp.add_child(pivot)
	pivot.add_child(model)
	var box := _bounds(model)
	var marker := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.25
	cap.height = 1.8
	marker.mesh = cap
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.75, 0.15, 0.12)
	marker.material_override = mm
	marker.position = Vector3(box.end.x + 0.6, 0.9, box.get_center().z + box.size.z * 0.3)
	vp.add_child(marker)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	var span := maxf(box.size.length(), 2.5) * 1.15
	cam.size = span
	var center := box.get_center()
	# RTS view: pitch 55 down, looking toward -Z (camera on +Z side).
	cam.rotation_degrees = Vector3(-55, 0, 0)
	cam.position = center + cam.transform.basis.z * 30.0
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(prefix + "_rts.png")
	marker.visible = false
	var sheet := Image.create(_px * 4, _px, false, Image.FORMAT_RGBA8)
	for i in 4:
		pivot.rotation_degrees.y = -90.0 * i
		cam.rotation_degrees = Vector3(-25, 0, 0)
		cam.position = center + cam.transform.basis.z * 30.0
		await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, _px, _px), Vector2i(_px * i, 0))
	sheet.save_png(prefix + "_turn.png")
	quit()


func _bounds(top: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in top.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
