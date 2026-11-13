class_name OnlineGame
extends RefCounted
## An online skirmish in progress: the connection, the lockstep and who plays
## which house. The lobby makes one when the host starts the match and sets
## OnlineGame.current before switching to the skirmish scene; the skirmish
## pumps it every frame (pump, then Lockstep.advance, then flush).

## The online match being played (null: a game alone at the keyboard).
static var current: OnlineGame = null

var net: NetSession
var lockstep: Lockstep
## The owner (house index) this computer plays.
var me: int = 0
## Peer id of the person playing each owner (-1: a computer player).
var seats: Array = []
## Display name per owner ("" for computer players).
var names: Array = []
## Why the match can't go on ("" while it can): the host left, the connection dropped.
var ended: String = ""
## Things to tell the player ("Mara left the game"); the skirmish shows and clears them.
var notices: Array[String] = []


## seats: one entry per owner, the peer id playing it or -1 for a computer.
func _init(session: NetSession, seat_peers: Array, seat_names: Array) -> void:
	net = session
	seats = seat_peers.duplicate()
	names = seat_names.duplicate()
	me = seats.find(net.my_id)
	var humans: Array = []
	for o in seats.size():
		if int(seats[o]) >= 0:
			humans.append(o)
	lockstep = Lockstep.new(humans, me)


## Host: the start message for the people in the lobby (host first; each
## {id, name, faction, hero}) plus `computers` computer players. Houses, heroes
## and the seed left on "random" are rolled here, once, from `roll`, so every
## computer builds the very same map.
static func make_start(people: Array, computers: int, map: String, roll: int, difficulty: String = "normal") -> Dictionary:
	var setup := SkirmishSetup.new()
	setup.slots = []
	var seat_ids: Array = []
	var seat_names: Array = []
	for p: Dictionary in people:
		var slot := SkirmishSetup.new_slot("human", String(p.get("faction", "random")))
		slot["hero"] = String(p.get("hero", "random"))
		setup.slots.append(slot)
		seat_ids.append(int(p["id"]))
		seat_names.append(String(p["name"]))
	for i in clampi(computers, 0, SkirmishSetup.max_players() - people.size()):
		var slot := SkirmishSetup.new_slot("computer", "random")
		slot["difficulty"] = difficulty
		setup.slots.append(slot)
		seat_ids.append(-1)
		seat_names.append("Computer")
	setup.map = map
	setup.seed_value = 0
	var done := setup.resolved(roll)
	return {"t": "start", "setup": done.to_dict(), "seats": seat_ids, "names": seat_names}


## Everyone: sets up the match from the host's start message (SkirmishSetup.current and
## OnlineGame.current). Returns "" or why it can't be played.
static func begin_from(session: NetSession, msg: Dictionary) -> String:
	var raw_setup: Variant = msg.get("setup")
	var raw_seats: Variant = msg.get("seats")
	var raw_names: Variant = msg.get("names")
	if not (raw_setup is Dictionary and raw_seats is Array and raw_names is Array):
		return "The host sent a broken start."
	var setup := SkirmishSetup.from_dict(raw_setup)
	var n := setup.active_slots().size()
	if (raw_seats as Array).size() != n or (raw_names as Array).size() != n:
		return "The host sent a broken start."
	var g := OnlineGame.new(session, raw_seats, raw_names)
	if g.me < 0:
		return "The host started without you."
	SkirmishSetup.current = setup
	CampaignSetup.current = null
	OnlineGame.current = g
	return ""


## Owner played from this peer id (-1: none).
func owner_of_peer(id: int) -> int:
	return seats.find(id)


## Reads the connection and hands game messages to the lockstep.
func pump() -> void:
	for msg in net.poll():
		receive(msg)


func receive(msg: Dictionary) -> void:
	match String(msg.get("t", "")):
		"cmds", "hash", "hold", "fix":
			lockstep.receive(msg)
		"_left":
			var o := owner_of_peer(int(msg.get("id", -1)))
			if o >= 0 and o != me:
				lockstep.drop_player(o)
				notices.append("%s left the game. Their house stands idle." % names[o])
		"_closed":
			if ended == "":
				ended = String(msg.get("reason", "The connection was lost."))


## Sends what the lockstep has for the others.
func flush() -> void:
	for msg in lockstep.take_outbox():
		net.send(msg)


## Gives a command of this computer's player (it runs a moment later, everywhere).
func issue(c: Dictionary) -> void:
	lockstep.issue(c)


## Leaves the match.
func leave() -> void:
	net.close()
	if OnlineGame.current == self:
		OnlineGame.current = null


## The waiting line for the HUD ("" when nobody is late).
func waiting_text() -> String:
	var late := lockstep.waiting_for()
	if late.is_empty():
		return ""
	return "Waiting for %s..." % ", ".join(late.map(func(o: int) -> String: return String(names[o])))


## For UI parts that change the world: the skirmish's command funnel when there is one
## (online it goes through the lockstep), else straight into the world.
static func send_command(skirmish: Object, w: SimWorld, owner: int, c: Dictionary) -> bool:
	if skirmish != null and skirmish.has_method("act"):
		return skirmish.act(c)
	return WorldCommands.apply(w, owner, c)
