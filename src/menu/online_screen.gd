class_name OnlineScreen
extends PanelContainer
## Online skirmish lobby: host a match or join one by address, pick your house
## and hero, and (host) the map and computer players, then start. Talks to the
## other computers through a NetSession; the match itself runs in the skirmish
## scene with OnlineGame.current set (begin_from).

signal back_requested
## The match is set up (SkirmishSetup.current, OnlineGame.current): switch scenes.
signal start_requested

var net: NetSession
var name_edit: LineEdit
var address_edit: LineEdit
var host_button: Button
var join_button: Button
var status: Label
var addresses: Label
var lobby: VBoxContainer
var people_box: VBoxContainer
var mixed_label: Label
var faction_pick: OptionButton
var hero_pick: OptionButton
var map_pick: OptionButton
var ai_pick: OptionButton
var start_button: Button
var _factions: Array = []
var _map_ids: Array = []


func build() -> void:
	WbSettings.ensure_loaded()
	add_theme_stylebox_override("panel", WbStyle.frame_panel("concord", 26))
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.custom_minimum_size.x = 600
	add_child(root)
	root.add_child(WbStyle.heading("Online skirmish", 28))
	var help := WbStyle.label("One player hosts, the others join with the host's address. From afar, both install Tailscale"
		+ " (free) and join with the host's Tailscale address (100.x.y.z). Both need the same build of the game.", 13, WbStyle.TEXT_DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 560
	root.add_child(help)
	name_edit = _field(root, "Your name", WbSettings.online_name, "Name others see")
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 12)
	root.add_child(host_row)
	host_button = _button(host_row, "Host a match", _host)
	addresses = WbStyle.label("", 13, WbStyle.TEXT_DIM)
	addresses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	addresses.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_row.add_child(addresses)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	root.add_child(join_row)
	address_edit = LineEdit.new()
	address_edit.text = WbSettings.online_address
	address_edit.placeholder_text = "Host address, e.g. 100.101.102.103"
	address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(address_edit)
	join_button = _button(join_row, "Join", _join)
	status = WbStyle.label("", 14, WbStyle.BRASS)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 560
	root.add_child(status)

	lobby = VBoxContainer.new()
	lobby.add_theme_constant_override("separation", 8)
	lobby.visible = false
	root.add_child(lobby)
	lobby.add_child(WbStyle.section("Players"))
	people_box = VBoxContainer.new()
	lobby.add_child(people_box)
	mixed_label = WbStyle.label("", 13, WbStyle.BAD)
	mixed_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mixed_label.custom_minimum_size.x = 560
	mixed_label.visible = false
	lobby.add_child(mixed_label)
	_factions = SkirmishSetup.playable_factions()
	faction_pick = _option(lobby, "Your house", ["Random"] + _factions.map(func(f: String) -> String: return WbStyle.faction_name(f)))
	faction_pick.item_selected.connect(func(_i: int) -> void:
		_fill_heroes()
		_send_pick())
	hero_pick = _option(lobby, "Your hero", ["Random"])
	hero_pick.item_selected.connect(func(_i: int) -> void: _send_pick())
	map_pick = _option(lobby, "Map", ["Random"])
	ai_pick = _option(lobby, "Computer players", ["None", "1", "2"])
	ai_pick.item_selected.connect(func(_i: int) -> void: _fill_maps())
	start_button = _button(lobby, "Start match", _start)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(buttons)
	_button(buttons, "Back", func() -> void:
		leave()
		back_requested.emit())


## Closes any connection (Back, or leaving the screen).
func leave() -> void:
	if net != null and OnlineGame.current == null:
		net.close()
	net = null
	lobby.visible = false
	host_button.disabled = false
	join_button.disabled = false
	addresses.text = ""


func _process(_delta: float) -> void:
	if net == null or not visible:
		return
	var msgs := net.poll()
	for i in msgs.size():
		var msg: Dictionary = msgs[i]
		match String(msg["t"]):
			"_connected":
				status.text = "Connected. Waiting for the host to let you in..."
			"welcome":
				status.text = "You are in. The host starts the match."
				_show_lobby()
			"lobby":
				_show_people()
			"_joined":
				status.text = "%s joined." % net.name_of(int(msg["id"]))
			"_left":
				status.text = "%s left." % String(msg.get("name", "Someone"))
			"_closed":
				status.text = String(msg.get("reason", "Disconnected."))
				net = null
				leave()
				return
			"start":
				var why := OnlineGame.begin_from(net, msg)
				if why != "":
					status.text = why
					return
				# Turns that came in the same breath belong to the match.
				for rest in msgs.slice(i + 1):
					OnlineGame.current.receive(rest)
				start_requested.emit()
				return


func _host() -> void:
	var why := _remember()
	if why == "":
		net = NetSession.new()
		why = net.host(name_edit.text)
	if why != "":
		status.text = why
		net = null
		return
	var lines: Array = []
	for a: Dictionary in NetSession.local_addresses():
		lines.append("%s (%s)" % [a["address"], a["label"]])
	addresses.text = "Others join with: %s" % (", ".join(lines) if not lines.is_empty() else "this computer's address")
	addresses.text += "  ·  port %d" % NetSession.DEFAULT_PORT
	status.text = "Hosting. Waiting for players to join..."
	_show_lobby()
	_send_pick()


func _join() -> void:
	var why := _remember()
	if why == "" and address_edit.text.strip_edges() == "":
		why = "Enter the host's address."
	if why == "":
		net = NetSession.new()
		why = net.join(address_edit.text, name_edit.text)
	if why != "":
		status.text = why
		net = null
		return
	host_button.disabled = true
	join_button.disabled = true
	status.text = "Connecting to %s..." % address_edit.text.strip_edges()


func _remember() -> String:
	if NetSession.clean_name(name_edit.text) == "":
		return "Enter your name first."
	WbSettings.online_name = NetSession.clean_name(name_edit.text)
	WbSettings.online_address = address_edit.text.strip_edges()
	WbSettings.save_settings()
	return ""


func _show_lobby() -> void:
	lobby.visible = true
	host_button.disabled = true
	join_button.disabled = true
	var host := net != null and net.is_host
	map_pick.get_parent().visible = host
	ai_pick.get_parent().visible = host
	start_button.visible = host
	_fill_heroes()
	_show_people()


func _show_people() -> void:
	if net == null:
		return
	for c in people_box.get_children():
		c.queue_free()
	for p: Dictionary in net.people:
		var f := String(p.get("faction", "random"))
		var h := String(p.get("hero", "random"))
		var text := "%s%s: %s, %s" % [String(p["name"]), " (host)" if int(p["id"]) == 1 else "",
			"random house" if f == "random" else WbStyle.faction_name(f),
			"random hero" if h == "random" else _hero_name(h)]
		people_box.add_child(WbStyle.label(text + "  (%s)" % String(p.get("platform", "?")), 15))
	mixed_label.text = NetSession.mixed_warning(net.people)
	mixed_label.visible = mixed_label.text != ""
	if net.is_host:
		_fill_maps()
		start_button.disabled = net.people.size() + ai_pick.selected < 2
		start_button.tooltip_text = "Waits for a second player (or a computer player)." if start_button.disabled else ""


func _fill_heroes() -> void:
	var keep := hero_pick.get_item_text(hero_pick.selected) if hero_pick.selected >= 0 else "Random"
	hero_pick.clear()
	hero_pick.add_item("Random")
	var f := _my_faction()
	if f != "random":
		for c: String in SkirmishSetup.hero_classes(f):
			hero_pick.add_item(_hero_name(c))
			hero_pick.set_item_metadata(hero_pick.item_count - 1, c)
	hero_pick.select(0)
	for i in hero_pick.item_count:
		if hero_pick.get_item_text(i) == keep:
			hero_pick.select(i)


func _fill_maps() -> void:
	if net == null:
		return
	var n := clampi(net.people.size() + ai_pick.selected, 2, SkirmishSetup.max_players())
	var ids := MapGen.template_ids(n)
	if ids == _map_ids:
		return
	var keep: String = _map_ids[map_pick.selected - 1] if map_pick.selected > 0 and map_pick.selected - 1 < _map_ids.size() else ""
	_map_ids = ids
	map_pick.clear()
	map_pick.add_item("Random")
	for id: String in ids:
		map_pick.add_item(MapGen.template_name(id))
	map_pick.select(maxi(0, ids.find(keep) + 1))


static func _hero_name(class_id: String) -> String:
	return String(HeroCatalog.get_default().classes.get(class_id, {}).get("name", class_id.capitalize()))


func _my_faction() -> String:
	var i := faction_pick.selected
	return "random" if i <= 0 else String(_factions[i - 1])


func _my_hero() -> String:
	var i := hero_pick.selected
	return "random" if i <= 0 else String(hero_pick.get_item_metadata(i))


func _send_pick() -> void:
	if net != null and net.active():
		net.set_my_pick(_my_faction(), _my_hero())


func _start() -> void:
	if net == null or not net.is_host:
		return
	var map: String = "random" if map_pick.selected <= 0 else String(_map_ids[map_pick.selected - 1])
	var msg := OnlineGame.make_start(net.people, ai_pick.selected, map, int(Time.get_ticks_usec() % 2147483647))
	net.send(msg)
	var why := OnlineGame.begin_from(net, msg)
	if why != "":
		status.text = why
		return
	start_requested.emit()


func _field(parent: Control, caption: String, value: String, hint: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var cap := WbStyle.label(caption, 15, WbStyle.TEXT_DIM)
	cap.custom_minimum_size.x = 150
	row.add_child(cap)
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = hint
	e.max_length = 20
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	return e


func _option(parent: Control, caption: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var cap := WbStyle.label(caption, 15, WbStyle.TEXT_DIM)
	cap.custom_minimum_size.x = 150
	row.add_child(cap)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it: String in items:
		o.add_item(it)
	o.select(0)
	row.add_child(o)
	return o


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 40)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
