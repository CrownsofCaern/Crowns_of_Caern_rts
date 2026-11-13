extends SceneTree
## Renders the hero classes' 3D bodies (assets/heroes3d/<class>.glb, with their weapons from
## HeroGear3D) as raw battle-sprite frames for tools/bake_hero_sprites.py, which turns them
## into pixel art. Same look as the main game's bake (tools/assets/render_model.gd there):
## orthographic camera a little above the ground, the figure turned a quarter towards the
## viewer and facing right, warm key light from the top left, cool fill, faint red rim.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/render_hero_sprites.gd -- <out dir> [class,...] [--units]
## --units: the names are live units in assets/units3d (workers, say) instead of hero classes, without gear.
## Writes <out>/<class>/<action>_<n>.png at 4x the final size, plus <out>/<class>/info.json.

const HEROES3D := "res://assets/heroes3d/"
## Frames per action (loops leave out the closing frame, one-shots keep it).
const FRAMES := {"idle": 6, "move": 8, "attack": 8, "death": 8}
const SIZE := Vector2i(1280, 1024)  ## 4x the 320x256 battle cell
const PITCH := 18.0
const YAW := -28.0  ## turn the +X-facing body a little towards the camera
## Metres the frame is tall: the battle art draws a 1.8 m man about 125 px of 256.
const FRAME_M := 256.0 * 1.8 / 125.0

var _out := "/tmp/hero_frames"
var _only: Array = []
var _units := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_units = args.has("--units")
	if args.size() > 1 and args[1] != "--units":
		_only = Array(args[1].split(","))
	_run.call_deferred()


func _stage() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	vp.own_world_3d = true
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.45, 0.55)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -35, 0)
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = 1.5
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 160, 0)
	rim.light_color = Color(0.9, 0.18, 0.12)
	rim.light_energy = 1.2
	vp.add_child(rim)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = FRAME_M
	var p := deg_to_rad(PITCH)
	# The feet (origin) sit at the battle anchor row, 207 of 256 px from the top.
	var look := Vector3(0.0, FRAME_M * (207.0 - 128.0) / 256.0 * cos(p), 0.0)
	cam.position = look + Vector3(0.0, sin(p), cos(p)) * 20.0
	vp.add_child(cam)
	cam.look_at(look)
	return vp


func _run() -> void:
	var vp := _stage()
	var hc := HeroCatalog.get_default()
	var done: Array = []
	var names: Array = _only if _units else hc.classes.keys()
	var dir3d := LiveUnit.DIR if _units else HEROES3D
	for cls: String in names:
		if not _only.is_empty() and not _only.has(cls):
			continue
		if not LiveUnit.exists(cls, dir3d):
			print("no body: ", cls)
			continue
		var unit := LiveUnit.spawn(cls, dir3d)
		if not _units:
			HeroGear3D.equip(unit, hc.classes[cls].get("weapons", []))
		unit.set_process(false)
		unit.rotation_degrees.y = YAW
		MatteMaterials.apply(unit)  # cloth, leather and old iron, as in the game
		vp.add_child(unit)
		var dir := _out + "/" + cls
		DirAccess.make_dir_recursive_absolute(dir)
		var info := {"height": unit.height, "clips": {}}
		for action: String in FRAMES:
			if not unit.has_clip(action):
				continue
			var anim := unit.player.get_animation(action)
			var n: int = FRAMES[action]
			var loop := action in LiveUnit.LOOPS
			info["clips"][action] = {"length": anim.length, "frames": n}
			unit.player.play(action, 0.0)
			for i in n:
				var t := anim.length * float(i) / float(n if loop else n - 1)
				unit.player.seek(minf(t, anim.length - 0.001), true)
				unit.player.pause()
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				vp.get_texture().get_image().save_png("%s/%s_%d.png" % [dir, action, i])
		var f := FileAccess.open(dir + "/info.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(info))
		f.close()
		unit.queue_free()
		await process_frame
		done.append(cls)
		print("rendered ", cls)
	print("done %d" % done.size())
	quit()
