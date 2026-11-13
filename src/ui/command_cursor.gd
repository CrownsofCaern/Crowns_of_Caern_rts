class_name CommandCursor
extends Node
## The mouse cursor shows what a click would do: move, attack, capture, gather, build...
## The art is Warbound's own set (assets/ui/cursors/cursor_<action>.png, 40 x 40, hotspot 2,2):
## the game's own dark fantasy cursor set plus a hammer badge for building. Skirmish.cursor_action picks one.

const ACTIONS := ["default", "move", "attack", "town", "capture", "pickup", "build", "encounter", "select", "blocked", "wait"]
const HOTSPOT := Vector2(2, 2)
## How often the hover target is looked up again (seconds).
const REFRESH := 0.06

var current_action := ""
var _textures: Dictionary = {}
var _wait := 0.0


func _ready() -> void:
	show_action("default")


func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)


static func texture_path(action: String) -> String:
	return "res://assets/ui/cursors/cursor_%s.png" % action


func _texture(action: String) -> Texture2D:
	if not _textures.has(action):
		var path := texture_path(action)
		_textures[action] = load(path) if ResourceLoader.exists(path) else null
	return _textures[action]


func show_action(action: String) -> void:
	if action == current_action:
		return
	current_action = action
	if DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(_texture(action), Input.CURSOR_ARROW, HOTSPOT)


## Called every frame by the view with a function that works out the action; it is
## only asked again a few times a second.
func refresh(delta: float, pick: Callable) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = REFRESH
	show_action(String(pick.call()))
