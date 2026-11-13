class_name MenuAudio
extends Node
## Menu music and UI sounds (the main game's ui_click/open/close/error and its
## menu theme). One per menu screen or pause overlay.

const SOUNDS := {
	"click": ["ui_click", "ui_click_2", "ui_click_3"],
	"open": ["ui_open"],
	"close": ["ui_close"],
	"error": ["ui_error"],
}

var _streams: Dictionary = {}
var _sfx: AudioStreamPlayer
var _music: AudioStreamPlayer
var _pick: int = 0


func _ready() -> void:
	for k: String in SOUNDS:
		_streams[k] = []
		for n: String in SOUNDS[k]:
			var path := "res://assets/audio/sfx/%s.ogg" % n
			if ResourceLoader.exists(path):
				_streams[k].append(load(path))
	_sfx = AudioStreamPlayer.new()
	_sfx.volume_db = -6.0
	_sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sfx)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -10.0
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)


func play(kind: String) -> void:
	var list: Array = _streams.get(kind, [])
	if list.is_empty() or _sfx == null:
		return
	_pick += 1
	_sfx.stream = list[_pick % list.size()]
	_sfx.pitch_scale = 0.97 + float((_pick * 37) % 7) / 100.0
	_sfx.play()


func play_music() -> void:
	if _music == null or not WbSettings.music_on:
		return
	var path := "res://assets/audio/music/menu.ogg"
	if not ResourceLoader.exists(path):
		return
	var s: AudioStreamOggVorbis = load(path)
	s.loop = true
	_music.stream = s
	_music.play()


func stop_music() -> void:
	if _music != null:
		_music.stop()


## Every Button under root clicks when pressed.
func wire_clicks(root: Node) -> void:
	for child in root.get_children():
		if child is BaseButton and not child.has_meta("wb_click"):
			child.set_meta("wb_click", true)
			(child as BaseButton).pressed.connect(play.bind("click"))
		wire_clicks(child)
