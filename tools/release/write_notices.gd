extends SceneTree
## Writes the Godot Engine licence and its third-party notices for a release build.
## Usage: godot --headless --path . --script res://tools/release/write_notices.gd -- <output file>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: write_notices.gd -- <output file>")
		quit(2)
		return
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s: %s" % [args[0], error_string(FileAccess.get_open_error())])
		quit(1)
		return
	var out := PackedStringArray()
	out.append("Crowns of Caern: Warbound is built with the Godot Engine (godotengine.org).")
	out.append("")
	out.append("Godot Engine")
	out.append("============")
	out.append(Engine.get_license_text())
	out.append("")
	out.append("Third-party components of the Godot Engine")
	out.append("==========================================")
	for info: Dictionary in Engine.get_copyright_info():
		out.append("")
		out.append("- %s" % info["name"])
		for part: Dictionary in info["parts"]:
			for c: String in part["copyright"]:
				out.append("  (c) %s" % c)
			out.append("  License: %s" % part["license"])
	out.append("")
	out.append("Licence texts")
	out.append("=============")
	var licenses := Engine.get_license_info()
	for key: String in licenses:
		out.append("")
		out.append("----- %s -----" % key)
		out.append(licenses[key])
	file.store_string("\n".join(out) + "\n")
	file.close()
	print("Wrote ", args[0])
	quit(0)
