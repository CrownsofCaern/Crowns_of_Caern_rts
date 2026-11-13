extends SceneTree
## Plays an online skirmish between two copies of the game on this computer, each
## driving its own house with a few orders, and prints the lockstep fingerprints.
## Run both (two terminals, or the second with &):
##   godot --headless --path . --script res://tools/online_selftest.gd -- host [port] [turns] [computers]
##   godot --headless --path . --script res://tools/online_selftest.gd -- join [port] [turns] [drift]
## Each prints "TURN <n> <fingerprint>" lines and finally "RESULT ok" or "RESULT <problem>".
## The fingerprints of both runs must match turn for turn (the game checks this too and
## repairs a drift by copying the host's world). drift = 1 on the joining copy knocks its
## own world off by a little at turn 100, to watch a repair: the result says "repairs 1".

var role := "host"
var port := NetSession.DEFAULT_PORT
var turns := 300
var computers := 0  ## host: computer players to add (their AI runs on both copies)
var drift := false  ## join: push one of our units aside at turn 100 (a fake drift)
var net: NetSession
var sk: Node
var _t0 := 0
var _printed := -1
var _next_order := 0
var _ending := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		role = args[0]
	if args.size() > 1:
		port = int(args[1])
	if args.size() > 2:
		turns = int(args[2])
	if args.size() > 3:
		computers = int(args[3])
		drift = role == "join" and computers > 0
	net = NetSession.new()
	var why := net.host("Host", port) if role == "host" else net.join("127.0.0.1", "Guest", port)
	if why != "":
		_finish(why)
		return
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_lobby)


func _lobby() -> void:
	if Time.get_ticks_msec() - _t0 > 30000:
		_finish("nobody came")
		return
	var msgs := net.poll()
	if role == "host":
		if net.people.size() >= 2:
			var start := OnlineGame.make_start(_people_with(net.people), computers, "random", 4242)
			net.send(start)
			_begin(start, [])
		return
	for i in msgs.size():
		if msgs[i]["t"] == "_closed":
			_finish(String(msgs[i]["reason"]))
			return
		if msgs[i]["t"] == "start":
			_begin(msgs[i], msgs.slice(i + 1))
			return


func _people_with(people: Array) -> Array:
	var out := people.duplicate(true)
	out[0]["faction"] = "concord"
	out[1]["faction"] = "hollow"
	return out


func _begin(start: Dictionary, rest: Array) -> void:
	process_frame.disconnect(_lobby)
	var why := OnlineGame.begin_from(net, start)
	if why != "":
		_finish(why)
		return
	for m in rest:
		OnlineGame.current.receive(m)
	sk = load("res://scenes/skirmish.tscn").instantiate()
	root.add_child(sk)
	process_frame.connect(_match)


func _match() -> void:
	var g: OnlineGame = sk.online
	if g == null:
		_finish("the match ended")
		return
	var ls := g.lockstep
	if g.ended != "" and ls.turn < turns:
		_finish(g.ended)
		return
	if ls.failed:
		_finish("out of sync, repair failed")
		return
	if drift and ls.turn == 100 and ls.repairs == 0:
		drift = false
		for u in sk.world.units:
			if u.owner == g.me:
				u.pos += Vector2(7, 3)
				u.hp *= 0.9
				break
	# Orders through the skirmish's own funnel, as clicks would give them.
	if ls.turn >= _next_order:
		_next_order = ls.turn + 25
		var mine: Array = []
		for u in sk.world.units:
			if u.owner == g.me and not u.is_worker():
				mine.append(u.id)
		var hall: Sector = sk.world.economy.hall_of(g.me)
		var off := Vector2(150 + (ls.turn % 3) * 40, 80 - (ls.turn % 4) * 40)
		if not mine.is_empty():
			sk.act({"t": "order", "ids": mine, "cmd": {"type": "move", "point": hall.center + off}, "queued": false})
		for b in sk.world.economy.buildings:
			if b.owner == g.me and b.kind == "dwelling" and b.done():
				sk.act({"t": "train", "building": b.id, "tier": 0})
		sk.act({"t": "weight", "res": "wood", "weight": 2 + ls.turn % 5})
	for h: Array in ls.my_hashes:
		if int(h[0]) > _printed:
			_printed = int(h[0])
			print("TURN %d %d" % [h[0], h[1]])
	if ls.turn >= turns and not _ending:
		_ending = true
		var counts: Array = []
		for o in sk.factions.size():
			counts.append(sk.world.count_alive(o))
		print("UNITS %s" % str(counts))
		# Let the last fingerprints cross before leaving.
		await create_timer(1.5).timeout
		g.pump()
		print("REPAIRS %d" % ls.repairs)
		_finish("out of sync" if ls.failed or ls.desync_turn >= 0 else "ok")


func _finish(result: String) -> void:
	print("RESULT %s" % result)
	if sk != null and sk.online != null:
		sk.online.leave()
	elif net != null:
		net.close()
	quit(0 if result == "ok" else 1)
