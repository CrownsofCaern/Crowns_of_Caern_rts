class_name PauseMenu
extends CanvasLayer
## The in-battle menu (Esc or F10) and the end-of-battle card, in the menu style.
## It does not touch the rules: the skirmish pauses itself while it is open and
## acts on the signals.

signal resume_requested
signal restart_requested
signal new_map_requested
signal main_menu_requested

var audio: MenuAudio
var root: Control
var panel: PanelContainer
var title: Label
var subtitle: Label
var buttons: VBoxContainer
var settings: SettingsScreen
var mode: String = "pause"  ## "pause", "victory" or "defeat"


func _init() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	build()


func build() -> void:
	if root != null:
		return
	audio = MenuAudio.new()
	add_child(audio)
	root = Control.new()
	root.name = "PauseRoot"
	root.theme = WbStyle.menu_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var veil := WbStyle.veil(0.55)
	root.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var stack := VBoxContainer.new()
	center.add_child(stack)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", WbStyle.frame_panel("concord", 28))
	stack.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size.x = 340
	panel.add_child(v)
	title = WbStyle.heading("Paused", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	subtitle = WbStyle.label("", 14, WbStyle.TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(subtitle)
	v.add_child(WbStyle.spacer(4))
	buttons = VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(buttons)
	settings = SettingsScreen.new()
	settings.build()
	settings.back_requested.connect(func() -> void:
		settings.hide()
		panel.show())
	settings.hide()
	stack.add_child(settings)
	root.hide()


func is_open() -> bool:
	return root != null and root.visible


## Opens as the pause menu, or as the victory/defeat card.
## Online match: no restart or new map, and the match goes on under the menu.
var online: bool = false


func open(kind: String = "pause", detail: String = "") -> void:
	build()
	mode = kind
	for c in buttons.get_children():
		buttons.remove_child(c)
		c.queue_free()
	match kind:
		"victory":
			title.text = "Victory"
			title.add_theme_color_override("font_color", Color("#e8c15a"))
			if not online:
				_add("Play again", restart_requested)
				_add("New map", new_map_requested)
			_add("Keep watching", resume_requested)
		"defeat":
			title.text = "Defeat"
			title.add_theme_color_override("font_color", WbStyle.BAD)
			if not online:
				_add("Try again", restart_requested)
				_add("New map", new_map_requested)
			_add("Keep watching", resume_requested)
		_:
			title.text = "Online match" if online else "Paused"
			title.add_theme_color_override("font_color", WbStyle.BRASS)
			_add("Resume", resume_requested)
			if not online:
				_add("Restart battle", restart_requested)
				_add("New map", new_map_requested)
			buttons.add_child(WbStyle.menu_button("Settings", func() -> void:
				panel.hide()
				settings.show(), 260))
	_add("Leave match" if online else "Main menu", main_menu_requested)
	subtitle.text = detail
	subtitle.visible = detail != ""
	audio.wire_clicks(root)
	settings.hide()
	panel.show()
	root.show()
	audio.play("open")


func close() -> void:
	if root == null or not root.visible:
		return
	if settings.visible:
		WbSettings.save_settings()
	root.hide()
	audio.play("close")


func _add(text: String, sig: Signal) -> void:
	buttons.add_child(WbStyle.menu_button(text, func() -> void: sig.emit(), 260))


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_F10]:
		if settings.visible:
			WbSettings.save_settings()
			settings.hide()
			panel.show()
		else:
			resume_requested.emit()
		get_viewport().set_input_as_handled()
