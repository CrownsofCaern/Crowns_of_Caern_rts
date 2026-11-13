class_name ResourceBar
extends PanelContainer
## The battle's top bar in the main game's style: a framed strip with resource
## icons and amounts, people, hall level and sectors, plus small status flags
## on the right. It only reads the skirmish's state.

var skirmish: Node
var _row: HBoxContainer
var _values: Dictionary = {}  ## key -> Label
var _weights: Dictionary = {}  ## resource -> Label with its gather weight ("2x")
var _flags: Label
var _faction: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 18)
	add_child(_row)


## Rebuilds the icons for the player's faction (its own rare resources).
func rebuild() -> void:
	if skirmish == null or skirmish.world == null or _row == null:
		return
	var eco: Economy = skirmish.world.economy
	var pl: PlayerState = eco.player(skirmish.PLAYER)
	_faction = pl.faction
	add_theme_stylebox_override("panel", _strip_box(_faction))
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	_values.clear()
	_weights.clear()
	# A campaign hero chapter has no economy: the hero bar shows its marks, so the strip stays empty.
	var hero_map := not eco.settlements_active
	for r: String in [] if hero_map else ["gold"] + Array(eco.gather_resources(skirmish.PLAYER)):
		var nm := String(eco.e["resources"].get(r, r.capitalize()))
		if r == "gold":
			_add(r, WbStyle.resource_icon(r), nm + ": from settlements")
		else:
			_add(r, WbStyle.resource_icon(r), nm + ": the number after it is how many shares of your workers gather it.\n"
				+ "Left click: one more (up to %dx). Right click: one less (0x: none)." % int(eco.e["gather_weights"]["max"]))
	if not hero_map:
		_add("people", null, "People: soldiers and workers / cap")
		_add("hall", null, "Hall level: unlocks higher tiers")
		_add("sectors", null, "Sectors you hold")
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(gap)
	_flags = WbStyle.label("", 13, WbStyle.TEXT_DIM)
	_flags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_flags)


func _add(key: String, tex: Texture2D, tip: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	h.tooltip_text = tip
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	if tex != null:
		h.add_child(WbStyle.icon(tex, Vector2(22, 22)))
	else:
		var cap := WbStyle.label(tip.get_slice(":", 0).get_slice(" ", 0), 13, WbStyle.TEXT_DIM)
		cap.add_theme_font_override("font", WbStyle.DISPLAY_FONT)
		h.add_child(cap)
	var v := WbStyle.label("0", 15, WbStyle.TEXT)
	v.add_theme_font_override("font", WbStyle.DISPLAY_FONT)
	h.add_child(v)
	_values[key] = v
	_row.add_child(h)
	if tex != null and key != "gold":
		var wl := WbStyle.label("1x", 13, WbStyle.BRASS)
		wl.add_theme_font_override("font", WbStyle.DISPLAY_FONT)
		h.add_child(wl)
		_weights[key] = wl
		h.mouse_filter = Control.MOUSE_FILTER_STOP
		h.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		h.gui_input.connect(func(ev: InputEvent) -> void: _on_resource_input(key, ev))


## Left click raises a resource's gather weight, right click (or the wheel) lowers it.
func _on_resource_input(key: String, ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var step := 0
	match mb.button_index:
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_UP:
			step = 1
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_DOWN:
			step = -1
	if step == 0:
		return
	var eco: Economy = skirmish.world.economy
	OnlineGame.send_command(skirmish, skirmish.world, skirmish.PLAYER,
		{"t": "weight", "res": key, "weight": eco.gather_weight(skirmish.PLAYER, key) + step})
	accept_event()
	skirmish.audio.play("click", skirmish._time, 0.7)


func _process(_delta: float) -> void:
	if skirmish == null or skirmish.world == null:
		return
	var eco: Economy = skirmish.world.economy
	var pl: PlayerState = eco.player(skirmish.PLAYER)
	if pl.faction != _faction or (_values.is_empty() and eco.settlements_active):
		rebuild()
	for r: String in _values:
		if r in ["people", "hall", "sectors"]:
			continue
		_values[r].text = str(pl.amount(r))
		if _weights.has(r):
			var wt := eco.gather_weight(skirmish.PLAYER, r)
			_weights[r].text = "%dx" % wt
			_weights[r].add_theme_color_override("font_color", WbStyle.BRASS if wt > 0 else WbStyle.TEXT_DIM)
	if _values.has("people"):
		var people := eco.people(skirmish.PLAYER)
		var cap := int(eco.e["people_cap"])
		_values["people"].text = "%d/%d" % [people, cap]
		_values["people"].add_theme_color_override("font_color", WbStyle.WARN if people >= cap else WbStyle.TEXT)
		_values["hall"].text = ["I", "II", "III", "IV"][clampi(pl.hall_level - 1, 0, 3)] + (" ↑" if pl.hall_upgrading > 0.0 else "")
		_values["sectors"].text = str(eco.sectors_of(skirmish.PLAYER))
	var flags: Array = []
	if skirmish.paused:
		flags.append("paused")
	if not skirmish.ai.enabled and skirmish.mission == null:
		flags.append("enemy AI off")
	if skirmish.audio.muted:
		flags.append("sound off")
	flags.append("%d FPS" % Engine.get_frames_per_second())
	_flags.text = "  ·  ".join(flags)


static func _strip_box(faction: String) -> StyleBoxFlat:
	var info := WbStyle.faction_info(faction)
	var bg := Color(String(info.get("panel", "#1d1813")))
	bg.a = 0.94
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = WbStyle.accent(faction).darkened(0.25)
	sb.border_width_bottom = 2
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 4
	return sb
