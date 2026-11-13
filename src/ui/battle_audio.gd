class_name BattleAudio
extends Node
## Battle sounds and music. Sounds come from the main game (tools/audio/synth.py).
## Rate-limited, with a small pool of players, and quieter the farther they are
## from the middle of the screen, so 300 units do not turn into noise.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const GROUPS := {
	"hit": ["battle_hit", "battle_hit_2", "battle_hit_3", "battle_hit_4"],
	"shot": ["battle_shot", "battle_shot_2", "battle_shot_3"],
	"horn": ["battle_horn"],
	"start": ["battle_start"],
	"click": ["ui_click", "ui_click_2"],
	"error": ["ui_error"],
}
## Minimum seconds between two sounds of the same group.
const GAP := {"hit": 0.07, "shot": 0.09, "click": 0.03}
const POOL := 12

var muted: bool = false
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _last: Dictionary = {}
var _music: AudioStreamPlayer
var _pick: int = 0


func _ready() -> void:
	for g in GROUPS:
		_streams[g] = []
		for n in GROUPS[g]:
			_streams[g].append(load(SFX_DIR + n + ".ogg"))
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -14.0
	add_child(_music)


## volume_scale 0..1 (from distance); time = the view's clock.
func play(group: String, time: float, volume_scale: float = 1.0) -> void:
	if muted or volume_scale <= 0.05 or not _streams.has(group):
		return
	if time - float(_last.get(group, -10.0)) < float(GAP.get(group, 0.0)):
		return
	_last[group] = time
	var list: Array = _streams[group]
	_pick += 1
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = list[_pick % list.size()]
	p.volume_db = linear_to_db(volume_scale) - (8.0 if group in ["hit", "shot"] else 2.0)
	p.pitch_scale = 0.92 + float((_pick * 37) % 17) / 100.0
	p.play()


func music(name: String, loop: bool) -> void:
	var s: AudioStreamOggVorbis = load(MUSIC_DIR + name + ".ogg")
	s.loop = loop
	_music.stream = s
	_music.stream_paused = false
	if not muted:
		_music.play()


func set_muted(m: bool) -> void:
	muted = m
	_music.stream_paused = m
