extends SceneTree
## Stills of the 3D combat effects (CombatFx3D): two mixed armies meet in the open, with
## archers, crossbows, a bombard, casters, a healer and a hero who casts a spell.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 --script res://tools/combat_fx_shots.gd -- <out dir> [seed]
## --fixed-fps keeps the sim and the particles in step however slowly frames render.

var _out := "/tmp/combat_fx"
var _seed := 101
var _sk: Skirmish
var _frame := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_seed = int(args[1])
	DirAccess.make_dir_recursive_absolute(_out)
	_sk = load("res://scenes/skirmish.tscn").instantiate()
	root.add_child(_sk)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
		_frame += 1


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(_out + "/" + name + ".jpg", 0.9)
	print("saved %s at %.1f s" % [name, _frame / 30.0])


func _army(owner: int, centre: Vector2, rows: Array) -> Array:
	var w := _sk.world
	var ids: Array = []
	var face := -1.0 if owner == 0 else 1.0
	for r in rows.size():
		var row: Array = rows[r]
		var n: int = row[1]
		for i in n:
			var p := centre + Vector2(face * r * 42.0, (i - (n - 1) * 0.5) * 30.0)
			ids.append(w.spawn(String(row[0]), owner, p).id)
	return ids


func _run() -> void:
	root.size = Vector2i(1600, 900)
	_sk._start(_seed)
	_sk.fog_enabled = false
	_sk.hud_help.visible = false
	_sk.ais.clear()
	var w := _sk.world
	var mid := w.nav.nearest_free(w.nav.world_size() * Vector2(0.5, 0.36))
	var west := mid - Vector2(330, 0)
	var east := mid + Vector2(330, 0)
	var a := _army(0, west, [["pike_militia", 6], ["longbowman", 6], ["rivet_crossbowman", 3],
		["frost_shaman", 2], ["thunder_bombard", 1], ["lightbearer", 1]])
	var b := _army(1, east, [["clan_raider", 5], ["cinderling", 4], ["shambler", 3], ["ash_witch", 2], ["brimstone_hurler", 2],
		["de_veil_adept", 2]])
	var hero := w.heroes.spawn_hero(0, "warlock", west - Vector2(150, 0))
	hero.hero.ranks = [1, 1, 1, 1]
	_sk.cam.position = mid
	_sk.cam.zoom = Vector2(1.35, 1.35)
	await _frames(6)
	w.command_attack_move(a, east)
	w.command_attack_move(b, west)
	# Wait for a volley in the air.
	for i in 300:
		await _frames(1)
		if w.projectiles.size() >= 6:
			break
	await _frames(3)
	await _shot("c1_first_volley")
	await _frames(6)
	await _shot("c2_bolts_in_flight")
	await _frames(45)
	await _shot("c3_impacts")
	await _frames(75)
	await _shot("c4_melee_blood")
	# The hero brings down a cataclysm on the enemy closest to it.
	var target := east
	var best := INF
	for u in w.units:
		if u.owner == 1 and u.pos.distance_to(hero.pos) < best:
			best = u.pos.distance_to(hero.pos)
			target = u.pos
	hero.hero.mana = hero.hero.max_mana
	hero.hero.cooldowns = [0.0, 0.0, 0.0, 0.0]
	print("cast: ", w.heroes.command_cast(0, 3, -1, target))
	for i in 90:
		await _frames(1)
		if hero.hero.cast_slot < 0:
			break
	await _frames(3)
	await _shot("c5_hero_spell")
	await _frames(90)
	# An enemy ranger answers: a glowing power shot, then a volley of glowing arrows.
	var ranger := w.heroes.spawn_hero(1, "ranger", hero.pos + Vector2(190, -60))
	ranger.hero.ranks = [1, 1, 1, 1]
	await _frames(2)
	print("power shot: ", w.heroes.command_cast(1, 1, hero.id))
	await _frames(4)
	await _shot("c8_skill_arrow")
	print("volley: ", w.heroes.command_cast(1, 2, -1, hero.pos))
	await _frames(9)
	await _shot("c9_volley")
	await _frames(140)
	await _shot("c6_aftermath")
	_sk.cam.zoom = Vector2(2.2, 2.2)
	await _frames(4)
	await _shot("c7_close")
	quit()
