class_name SettingsScreen
extends PanelContainer
## Volume, music, fullscreen, V-Sync and the controls help. Changes apply at
## once and are saved when the screen closes. Used by the main and pause menus.

signal back_requested
signal changed

var volume_slider: HSlider
var music_check: CheckBox
var fullscreen_check: CheckBox
var vsync_check: CheckBox
var weather_check: CheckBox
var outlines_check: CheckBox
var ambience_check: CheckBox


func build() -> void:
	WbSettings.ensure_loaded()
	add_theme_stylebox_override("panel", WbStyle.frame_panel("concord", 26))
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.custom_minimum_size.x = 520
	add_child(root)
	root.add_child(WbStyle.heading("Settings", 28))
	root.add_child(WbStyle.section("Sound"))
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 12)
	root.add_child(vol_row)
	var cap := WbStyle.label("Volume", 15, WbStyle.TEXT_DIM)
	cap.custom_minimum_size.x = 90
	vol_row.add_child(cap)
	volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = WbSettings.volume
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume_slider.value_changed.connect(func(v: float) -> void:
		WbSettings.volume = v
		_changed())
	vol_row.add_child(volume_slider)
	music_check = _check(root, "Music", WbSettings.music_on, func(on: bool) -> void: WbSettings.music_on = on)
	root.add_child(WbStyle.section("Display"))
	fullscreen_check = _check(root, "Fullscreen", WbSettings.fullscreen, func(on: bool) -> void: WbSettings.fullscreen = on)
	vsync_check = _check(root, "V-Sync", WbSettings.vsync, func(on: bool) -> void: WbSettings.vsync = on)
	weather_check = _check(root, "Weather: rain, snow and thunderstorms now and then (F6 in battle changes it)",
		WbSettings.weather, func(on: bool) -> void: WbSettings.weather = on)
	outlines_check = _check(root, "Ink outlines round buildings, trees and units",
		WbSettings.outlines, func(on: bool) -> void: WbSettings.outlines = on)
	ambience_check = _check(root, "Living land: drifting cloud shadows, mist and motes in the air",
		WbSettings.ambience, func(on: bool) -> void: WbSettings.ambience = on)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(buttons)
	var back := Button.new()
	back.name = "Back"
	back.text = "Done"
	back.custom_minimum_size = Vector2(130, 42)
	back.pressed.connect(func() -> void:
		WbSettings.save_settings()
		back_requested.emit())
	buttons.add_child(back)


func _check(parent: Node, text: String, value: bool, setter: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.toggled.connect(func(on: bool) -> void:
		setter.call(on)
		_changed())
	parent.add_child(c)
	return c


func _changed() -> void:
	WbSettings.apply()
	changed.emit()
