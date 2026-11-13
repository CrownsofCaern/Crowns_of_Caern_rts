class_name Lockstep
extends RefCounted
## Lockstep for online skirmishes: every computer runs the whole simulation, and
## only the players' commands travel.
##
## Time is cut into turns of TICKS_PER_TURN ticks. A command given now is
## scheduled DELAY_TURNS turns ahead, and each computer sends its commands for a
## turn (an empty list too) to the others. A turn runs only once the commands of
## every human player for it are in, so all computers apply the same commands
## before the same tick and stay identical (SimWorld is deterministic: same seed
## and same commands, same game). Computer players run on every computer.
##
## Every HASH_EVERY turns each computer sends a fingerprint of its world. If two
## differ, the games have drifted apart (desync) and `desync_turn` says when.
## Then the drift is repaired: the host (the lowest human owner) names a turn a
## little ahead that no computer can have passed yet ("hold"), everyone stops
## there, the host sends a WorldSnapshot of its world ("fix") and the others copy
## it, and play goes on. Only when that can't work (the worlds hold different
## units, or it keeps happening) is the match out of sync for good (`failed`).
##
## No networking here: messages go out through `outbox` and come in through
## `receive`, so tests can pass them by hand. Messages are plain dictionaries:
##   {"t": "cmds", "turn": int, "player": int, "cmds": Array}
##   {"t": "hash", "turn": int, "player": int, "hash": int}
##   {"t": "hold", "turn": int, "player": int}       (host: everyone stops before this turn)
##   {"t": "fix", "turn": int, "player": int, "state": PackedByteArray}

const TICKS_PER_TURN := 2  ## 0.1 s at 20 ticks a second
const DELAY_TURNS := 2  ## a command runs 0.2 s after it was given (time to reach the others)
const HASH_EVERY := 10  ## compare fingerprints once a second
## Turns run per frame when this computer lags behind the others (catching up).
const MAX_TURNS_PER_FRAME := 4
## Repairs per match before giving up (a drift that keeps coming back is a real bug).
const MAX_REPAIRS := 5

## Owners that are people (each sends commands every turn), ascending.
var players: Array = []
## The owner this computer plays.
var me: int = 0
## The next turn to run.
var turn: int = 0
## Messages to send to every other computer.
var outbox: Array[Dictionary] = []
## The first turn at which fingerprints differed (-1: none so far).
var desync_turn: int = -1
## Players that left: their turns are no longer waited for.
var gone: Array = []
## This computer's last fingerprints, [turn, fingerprint] (for tools and bug reports).
var my_hashes: Array = []
## Drifts repaired so far.
var repairs: int = 0
## Out of sync for good: the match can't go on.
var failed: bool = false
## Objects outside the world that a repair copies too (the computer players).
var extras: Array = []
## The turn everyone stops before while a drift is repaired (-1: none).
var hold_at: int = -1

var _fix: Dictionary = {}  ## the host's fix message, once it is here
var _settled: int = -1  ## fingerprints of turns before this one are from before a repair: ignored

var _pending: Array = []  ## commands given since the last send
var _inbox: Dictionary = {}  ## turn -> {player -> Array of commands}
var _hashes: Dictionary = {}  ## turn -> {player -> fingerprint}
var _acc: float = 0.0


func _init(human_players: Array = [0, 1], my_player: int = 0) -> void:
	players = human_players.duplicate()
	players.sort()
	me = my_player
	# The first turns have nothing in them: nobody could have sent anything yet.
	for t in DELAY_TURNS:
		for p: int in players:
			_put(t, p, [])


## Schedules a command of this computer's player (see WorldCommands).
func issue(c: Dictionary) -> void:
	# The copy that runs here is the copy the others get, bit for bit.
	_pending.append(bytes_to_var(var_to_bytes(c)))


## A message from another computer.
func receive(msg: Dictionary) -> void:
	var t := int(msg.get("turn", -1))
	var p := int(msg.get("player", -1))
	if t < 0 or not players.has(p) or p == me:
		return
	match String(msg.get("t", "")):
		"cmds":
			if t < turn:
				return  # already run (can't happen on a reliable channel)
			var cmds: Array = []
			var raw: Variant = msg.get("cmds", [])
			if raw is Array:
				for c: Variant in raw:
					if WorldCommands.is_command(c):
						cmds.append(c)
			_put(t, p, cmds)
		"hash":
			_note_hash(t, p, int(msg.get("hash", 0)))
		"hold":
			if p != authority():
				return
			if t < turn:
				failed = true  # can't happen: the host picks a turn nobody has reached
			elif hold_at < 0 or t < hold_at:
				hold_at = t
		"fix":
			if p == authority():
				_fix = msg


## The player left the match: stop waiting for their turns (their army stands idle).
func drop_player(p: int) -> void:
	if not gone.has(p):
		gone.append(p)


## True when every human player's commands for the next turn are here.
func can_run() -> bool:
	if failed or (hold_at >= 0 and turn >= hold_at):
		return false
	var got: Dictionary = _inbox.get(turn, {})
	for p: int in players:
		if not got.has(p) and not gone.has(p):
			return false
	return true


## The players whose commands for the next turn are missing (for "Waiting for ...").
func waiting_for() -> Array:
	var got: Dictionary = _inbox.get(turn, {})
	return players.filter(func(p: int) -> bool: return not got.has(p) and not gone.has(p))


## How many turns are ready to run right now (more than one: this computer is behind).
func turns_ready() -> int:
	var n := 0
	var t := turn
	while true:
		var got: Dictionary = _inbox.get(t, {})
		for p: int in players:
			if not got.has(p) and not gone.has(p):
				return n
		n += 1
		t += 1
	return n


## Runs the next turn: its commands in player order, then TICKS_PER_TURN ticks
## through `tick` (a Callable that steps the world once: computer players, then
## world.step()). Call only when can_run().
func run_turn(w: SimWorld, tick: Callable) -> void:
	# What this computer gives during this turn runs DELAY_TURNS later; send it now.
	var send_turn := turn + DELAY_TURNS
	_put(send_turn, me, _pending)
	outbox.append({"t": "cmds", "turn": send_turn, "player": me, "cmds": _pending})
	_pending = []
	var got: Dictionary = _inbox.get(turn, {})
	for p: int in players:
		for c: Variant in got.get(p, []):
			WorldCommands.apply(w, p, c)
	_inbox.erase(turn)
	for i in TICKS_PER_TURN:
		tick.call()
	if turn % HASH_EVERY == 0:
		var h := fingerprint(w)
		outbox.append({"t": "hash", "turn": turn, "player": me, "hash": h})
		_note_hash(turn, me, h)
		my_hashes.append([turn, h])
		if my_hashes.size() > 30:
			my_hashes.pop_front()
	turn += 1


## Real time passed: runs the turns that are due and ready. Returns how many ran.
func advance(w: SimWorld, tick: Callable, delta: float) -> int:
	repair(w)
	var turn_time := float(TICKS_PER_TURN) * w.dt
	_acc = minf(_acc + delta, turn_time * float(MAX_TURNS_PER_FRAME))
	var ran := 0
	while ran < MAX_TURNS_PER_FRAME and can_run():
		# Behind the others (more than the delay's worth of turns waiting): run one extra.
		var behind := turns_ready() > DELAY_TURNS + 1
		if _acc < turn_time and not behind:
			break
		_acc = maxf(0.0, _acc - turn_time)
		run_turn(w, tick)
		ran += 1
	if not can_run():
		_acc = minf(_acc, turn_time)  # waiting: don't bank time to rush through later
	return ran


## The player whose world counts when a drift is repaired (the host plays the lowest owner).
func authority() -> int:
	return int(players[0])


## True while a drift is being repaired (play stops for a moment).
func repairing() -> bool:
	return not failed and (desync_turn >= 0 or hold_at >= 0)


## Repairs a drift once everyone has stopped at the hold turn: the host sends its
## world, the others copy it. Call every frame (advance does).
func repair(w: SimWorld) -> void:
	if failed or hold_at < 0 or turn != hold_at:
		return
	if me == authority():
		outbox.append({"t": "fix", "turn": turn, "player": me, "state": WorldSnapshot.pack(WorldSnapshot.capture(w, extras))})
		_repaired()
	elif int(_fix.get("turn", -1)) == turn:
		var raw: Variant = _fix.get("state")
		var snap := WorldSnapshot.unpack(raw) if raw is PackedByteArray else {}
		_fix = {}
		if snap.is_empty() or not WorldSnapshot.apply(w, snap, extras):
			failed = true
			return
		_repaired()


func _repaired() -> void:
	repairs += 1
	hold_at = -1
	desync_turn = -1
	_settled = turn
	for t: int in _hashes.keys():
		if t < turn:
			_hashes.erase(t)


## Hands out what to send and empties the outbox.
func take_outbox() -> Array[Dictionary]:
	var out := outbox
	outbox = []
	return out


## A fingerprint of everything that matters: units (place, health), resources
## and the tick. Equal worlds give equal numbers; drifted worlds almost surely don't.
static func fingerprint(w: SimWorld) -> int:
	var h := w.checksum()
	h = (h * 31 + w.tick) & 0x7FFFFFFF
	h = (h * 31 + w.units.size()) & 0x7FFFFFFF
	h = (h * 31 + w.projectiles.size()) & 0x7FFFFFFF
	if w.economy != null:
		for pl: PlayerState in w.economy.players:
			for r: String in pl.res:
				h = (h * 31 + int(float(pl.res[r]) * 16.0)) & 0x7FFFFFFF
		for b: Building in w.economy.buildings:
			h = (h * 31 + b.id * 7 + b.owner) & 0x7FFFFFFF
		for s: Sector in w.economy.sectors:
			h = (h * 31 + s.owner + 1) & 0x7FFFFFFF
		for n: ResNode in w.economy.nodes:
			h = (h * 31 + n.amount + 1) & 0x7FFFFFFF
	for st: SimUnit in w.structures:
		h = (h * 31 + int(st.hp * 16.0)) & 0x7FFFFFFF
	return h


## Host: a drift was seen; everyone stops before a turn nobody can have run yet.
## Others have this computer's commands up to turn + DELAY_TURNS, so they can't be
## past turn + DELAY_TURNS + 1.
func _start_repair() -> void:
	if failed or me != authority() or hold_at >= 0:
		return
	if repairs >= MAX_REPAIRS:
		failed = true
		return
	hold_at = turn + DELAY_TURNS + 1
	outbox.append({"t": "hold", "turn": hold_at, "player": me})


func _put(t: int, p: int, cmds: Array) -> void:
	if not _inbox.has(t):
		_inbox[t] = {}
	_inbox[t][p] = cmds


func _note_hash(t: int, p: int, h: int) -> void:
	if t < _settled:
		return  # from before the last repair
	if not _hashes.has(t):
		_hashes[t] = {}
	_hashes[t][p] = h
	var seen: Dictionary = _hashes[t]
	var first: Variant = null
	for v: Variant in seen.values():
		if first == null:
			first = v
		elif v != first and (desync_turn < 0 or t < desync_turn):
			desync_turn = t
			_start_repair()
	# Keep the fingerprint table small: everyone has reported old turns long ago.
	if seen.size() >= players.size():
		_hashes.erase(t)
