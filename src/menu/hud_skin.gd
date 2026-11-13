class_name HudSkin
extends RefCounted
## Dresses the skirmish HUD in the main game's look: the framed resource bar on
## top, the faction's framed panel behind the unit panel and build menu, a brass
## frame round the minimap, and the Lora/Cinzel fonts. Layout stays where the
## skirmish puts it; this only restyles and adds the bar.

const BAR_H := 40.0


static func apply(sk: Node, faction: String) -> ResourceBar:
	var layer: Node = sk.hud_top.get_parent()
	var bar: ResourceBar = sk.get_meta("wb_resource_bar") if sk.has_meta("wb_resource_bar") else null
	if bar == null:
		bar = ResourceBar.new()
		bar.name = "ResourceBar"
		bar.skirmish = sk
		bar.anchor_right = 1.0
		bar.offset_bottom = BAR_H
		layer.add_child(bar)
		layer.move_child(bar, 0)
		sk.set_meta("wb_resource_bar", bar)
		# The old text line now only carries hints (attack-move), under the bar.
		# Right of the hero bar, which sits top left.
		sk.hud_top.position = Vector2(700, BAR_H + 6)
		# The controls list opens under the ? button (top right).
		if "help_button" in sk and sk.help_button != null:
			sk.help_button.offset_top = BAR_H + 8
			sk.help_button.offset_bottom = BAR_H + 44
		if "map_button" in sk and sk.map_button != null:
			sk.map_button.offset_top = BAR_H + 8
			sk.map_button.offset_bottom = BAR_H + 44
		if "group_bar" in sk and sk.group_bar != null:
			sk.group_bar.offset_top = BAR_H + 8
			sk.group_bar.offset_bottom = BAR_H + 8 + GroupBar.CARD.y
		# Below the control group portraits, which share the row with the ? button.
		sk.hud_help.offset_top = BAR_H + 66
		sk.hud_help.offset_bottom = BAR_H + 66
		for l: Label in [sk.hud_top, sk.hud_help, sk.hud_center]:
			l.add_theme_font_override("font", WbStyle.BODY_FONT)
		sk.hud_center.add_theme_font_override("font", WbStyle.DISPLAY_FONT)
		sk.hud_center.add_theme_color_override("font_color", Color("#eadcba"))
		sk.hud_center.add_theme_color_override("font_outline_color", Color("#100b08"))
		sk.hud_center.add_theme_constant_override("outline_size", 5)
		var help_box := StyleBoxFlat.new()
		help_box.bg_color = Color(0.05, 0.04, 0.03, 0.72)
		help_box.border_color = Color("#826c45")
		help_box.set_border_width_all(1)
		help_box.set_corner_radius_all(2)
		help_box.set_content_margin_all(10)
		sk.hud_help.add_theme_stylebox_override("normal", help_box)
	bar.rebuild()
	var frame := WbStyle.frame_panel(faction, 10)
	sk.panel.frame = frame
	sk.panel._font = WbStyle.BODY_FONT
	if "hero_bar" in sk and sk.hero_bar != null:
		sk.hero_bar.frame = frame
	sk.minimap.frame = WbStyle.frame_panel(faction, 0)
	sk.build_panel.theme = WbStyle.menu_theme()
	sk.build_panel.add_theme_stylebox_override("panel", WbStyle.frame_panel(faction, 14))
	return bar
