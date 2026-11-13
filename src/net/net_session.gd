class_name NetSession
extends RefCounted
## The connection of an online skirmish: one computer hosts, the others join it
## by address (on the same network, or over Tailscale / ZeroTier from afar).
##
## Plain ENet packets, no RPCs and no Nodes: whoever owns the session calls
## poll() every frame and gets the messages that came in. Every message is a
## dictionary with a "t" (its kind), sent with var_to_bytes and read with
## bytes_to_var (which never builds objects, so a packet can't run code).
##
## Clients only talk to the host; the host passes game messages ("cmds", "hash")
## on to everyone else, so it works the same with two players or four.
##
## Lobby messages:
##   client -> host  hello {name, version}     host -> client  welcome {id} / refuse {reason}
##   client -> host  pick {faction, hero}      host -> all     lobby {people}
##   host -> all     start {setup, seats}      anyone          bye {}
## In the match: Lockstep's cmds and hash, and "chat" {text}.
## poll() also reports what happened to the connection as messages of its own:
##   _connected {}, _joined {id}, _left {id, name}, _closed {reason}

const DEFAULT_PORT := 24690
const MAX_PEOPLE := 4
## Bump when the messages change, so old and new builds refuse each other.
const PROTOCOL := 2
## Messages the host passes on to every other client.
const RELAYED := ["cmds", "hash", "hold", "fix", "chat"]

var is_host: bool = false
var my_name: String = ""
## This computer's peer id (the host is 1; 0 = not connected yet).
var my_id: int = 0
## Host: everyone in the lobby, host first: [{id, name, faction, hero}]. Clients get a copy.
var people: Array = []
## The build identity both sides must share (game version and data); see version().
var version_text: String = ""

var _peer: ENetMultiplayerPeer
var _connected: bool = false
var _out: Array[Dictionary] = []  ## messages for the caller from this poll
var _known: Dictionary = {}  ## host: peer id -> true for everyone who said hello
var _departed: Array = []  ## host: peers whose connection dropped since the last poll
var _kick_at: Dictionary = {}  ## host: refused peer id -> msec when to cut it off


func _init(version_override: String = "") -> void:
	version_text = version_override if version_override != "" else NetSession.version()


func active() -> bool:
	return _peer != null


## Opens the game for others to join. Returns "" or why it failed.
func host(person: String, port: int = DEFAULT_PORT) -> String:
	var who := clean_name(person)
	if who == "":
		return "Enter your name first."
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEOPLE - 1)
	if err != OK:
		return "Could not open port %d (%s). Is another game already hosting?" % [port, error_string(err)]
	_peer = peer
	_peer.peer_disconnected.connect(func(id: int) -> void: _departed.append(id))
	is_host = true
	my_id = 1
	my_name = who
	_connected = true
	people = [{"id": 1, "name": who, "faction": "random", "hero": "random", "platform": NetSession.platform()}]
	return ""


## Connects to a host; the answer comes later from poll() (welcome, refuse or _closed).
## The address may carry a port: "100.64.1.2:24690".
func join(address: String, person: String, port: int = DEFAULT_PORT) -> String:
	var who := clean_name(person)
	if who == "":
		return "Enter your name first."
	var addr := address.strip_edges()
	if addr.count(":") == 1:
		var bits := addr.split(":")
		addr = bits[0]
		port = int(bits[1])
	if addr == "":
		return "Enter the host's address."
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(addr, port)
	if err != OK:
		return "Could not connect to %s (%s)." % [addr, error_string(err)]
	_peer = peer
	is_host = false
	my_id = 0
	my_name = who
	_connected = false
	people = []
	return ""


## Leaves (the host ends the game for everyone).
func close() -> void:
	if _peer == null:
		return
	if _connected:
		send({"t": "bye"})
		_peer.poll()
	_peer.close()
	_peer = null
	_connected = false
	is_host = false
	my_id = 0
	people = []
	_known.clear()
	_departed.clear()
	_kick_at.clear()


## Sends a message: to = 0 for everyone (a client's "everyone" goes through the host),
## or one peer id (host only).
func send(msg: Dictionary, to: int = 0) -> void:
	if _peer == null or (not is_host and not _connected):
		return
	var bytes := var_to_bytes(msg)
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	_peer.transfer_channel = 0
	_peer.set_target_peer(to if is_host else MultiplayerPeer.TARGET_PEER_SERVER)
	_peer.put_packet(bytes)


## Pumps the connection; returns the messages that came in (see the class notes).
func poll() -> Array[Dictionary]:
	_out = []
	if _peer == null:
		return _out
	_peer.poll()
	var status := _peer.get_connection_status()
	if not is_host:
		if status == MultiplayerPeer.CONNECTION_CONNECTED and not _connected:
			_connected = true
			my_id = _peer.get_unique_id()
			_out.append({"t": "_connected"})
			send({"t": "hello", "name": my_name, "version": version_text, "protocol": PROTOCOL, "platform": NetSession.platform()})
		elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			_lost("Could not reach the host." if not _connected else "The host left the game.")
			return _out
	while _peer != null and _peer.get_available_packet_count() > 0:
		var from := _peer.get_packet_peer()
		var raw := _peer.get_packet()
		var msg: Variant = bytes_to_var(raw)
		if msg is Dictionary and (msg as Dictionary).get("t") is String:
			_handle(from, msg)
	if is_host and _peer != null:
		for id: int in _departed:
			_drop_peer(id)
			_kick_at.erase(id)
		_departed.clear()
		for id: int in _kick_at.keys():
			if Time.get_ticks_msec() >= int(_kick_at[id]):
				_kick_at.erase(id)
				if _peer.get_peer(id) != null:
					_peer.disconnect_peer(id)
	return _out


func _handle(from: int, msg: Dictionary) -> void:
	var kind := String(msg["t"])
	if is_host:
		match kind:
			"hello":
				var why := ""
				if int(msg.get("protocol", 0)) != PROTOCOL or String(msg.get("version", "")) != version_text:
					why = "Your game is a different version from the host's (%s). Both need the same build." % version_text
				elif people.size() >= MAX_PEOPLE:
					why = "The game is full."
				if why != "":
					# The client closes on "refuse"; cut it off a moment later in case it doesn't
					# (cutting at once would drop the message with the reason).
					send({"t": "refuse", "reason": why}, from)
					_kick_at[from] = Time.get_ticks_msec() + 2000
					return
				var who := _unique_name(clean_name(String(msg.get("name", ""))))
				people.append({"id": from, "name": who, "faction": "random", "hero": "random",
					"platform": String(msg.get("platform", "?")).substr(0, 40)})
				_known[from] = true
				send({"t": "welcome", "id": from}, from)
				share_people()
				_out.append({"t": "_joined", "id": from})
				return
			"pick":
				for p: Dictionary in people:
					if int(p["id"]) == from:
						p["faction"] = String(msg.get("faction", "random"))
						p["hero"] = String(msg.get("hero", "random"))
				share_people()
				return
			"bye":
				_drop_peer(from)
				return
		if not _known.has(from):
			return  # nothing counts before hello
		if RELAYED.has(kind):
			for p: Dictionary in people:
				var id := int(p["id"])
				if id != 1 and id != from:
					send(msg, id)
			msg["from"] = from
			_out.append(msg)
		return
	# Client: everything comes from the host.
	match kind:
		"refuse":
			_lost(String(msg.get("reason", "The host refused.")))
			return
		"welcome":
			my_id = int(msg.get("id", my_id))
		"lobby":
			people = msg.get("people", []) if msg.get("people") is Array else []
		"bye":
			_lost("The host left the game.")
			return
		"left":
			msg["t"] = "_left"
	_out.append(msg)


## Host: tells everyone who is in the lobby.
func share_people() -> void:
	send({"t": "lobby", "people": people})
	_out.append({"t": "lobby", "people": people})


## Host: what the host's own player picked.
func set_my_pick(faction: String, hero: String) -> void:
	if is_host:
		people[0]["faction"] = faction
		people[0]["hero"] = hero
		share_people()
	else:
		send({"t": "pick", "faction": faction, "hero": hero})


func name_of(id: int) -> String:
	for p: Dictionary in people:
		if int(p["id"]) == id:
			return String(p["name"])
	return "?"


func _drop_peer(id: int) -> void:
	if not _known.has(id):
		return
	_known.erase(id)
	var who := name_of(id)
	people = people.filter(func(p: Dictionary) -> bool: return int(p["id"]) != id)
	send({"t": "left", "id": id, "name": who})
	_out.append({"t": "_left", "id": id, "name": who})
	share_people()


func _lost(reason: String) -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	_connected = false
	_out.append({"t": "_closed", "reason": reason})


func _unique_name(n: String) -> String:
	var base := n if n != "" else "Player"
	var out := base
	var k := 2
	while people.any(func(p: Dictionary) -> bool: return String(p["name"]) == out):
		out = "%s %d" % [base, k]
		k += 1
	return out


## The kind of computer: system and processor ("macOS arm64", "Windows x86_64").
static func platform() -> String:
	return "%s %s" % [OS.get_name(), Engine.get_architecture_name()]


## A warning when the people in the lobby play on different kinds of computer ("" if not).
## Lockstep needs every computer to calculate exactly alike; across systems that is likely
## but not certain, so a drift may need repairs (or, rarely, stop the match).
static func mixed_warning(list: Array) -> String:
	var kinds: Array = []
	for p: Dictionary in list:
		var k := String(p.get("platform", "?"))
		if not kinds.has(k):
			kinds.append(k)
	if kinds.size() < 2:
		return ""
	return "Mixed computers (%s): the games may drift apart now and then. The host's game is then copied to the others, which takes a moment." % ", ".join(kinds)


## A display name: printable, at most 20 characters.
static func clean_name(n: String) -> String:
	var out := ""
	for ch in n.strip_edges():
		if ch.unicode_at(0) >= 32:
			out += ch
	return out.substr(0, 20).strip_edges()


## The build both computers must share: the game's version and a fingerprint of
## the rules data (data/*.json). Different data would play a different game.
static func version() -> String:
	var v := String(ProjectSettings.get_setting("application/config/version", "dev"))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var files := Array(DirAccess.get_files_at("res://data"))
	files.sort()
	for f: String in files:
		if f.ends_with(".json"):
			ctx.update(f.to_utf8_buffer())
			ctx.update(FileAccess.get_file_as_bytes("res://data/" + f))
	return "%s-%s" % [v, ctx.finish().hex_encode().substr(0, 10)]


## This computer's addresses others can join by, Tailscale ones first: [{address, label}].
static func local_addresses() -> Array:
	var tail: Array = []
	var lan: Array = []
	for a in IP.get_local_addresses():
		var s := String(a)
		if not s.is_valid_ip_address() or s.contains(":") or s.begins_with("127.") or s.begins_with("169.254."):
			continue
		var parts := s.split(".")
		var second := int(parts[1]) if parts.size() == 4 else 0
		if s.begins_with("100.") and second >= 64 and second <= 127:
			tail.append({"address": s, "label": "Tailscale"})
		else:
			lan.append({"address": s, "label": "Local network"})
	return tail + lan
