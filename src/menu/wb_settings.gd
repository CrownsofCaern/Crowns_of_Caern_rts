class_name WbSettings
extends RefCounted
## Player settings and the last skirmish setup, kept in user://warbound_settings.cfg.
## Plain values; apply() pushes them to the engine (audio bus, window mode).

const PATH := "user://warbound_settings.cfg"

## Where settings live; tests point it at a scratch file.
static var path: String = PATH

static var volume: float = 0.8  ## master volume, 0..1
static var music_on: bool = true
static var fullscreen: bool = false
static var vsync: bool = true
static var weather: bool = true  ## rain, snow and storms now and then in the 3D view
static var outlines: bool = true  ## ink outlines round buildings, trees and units (LookFx3D)
static var ambience: bool = true  ## cloud shadows, mist and motes in the air (LookFx3D)
static var last_setup: Dictionary = {}
## Online: the name you play under and the last host address you joined.
static var online_name: String = ""
static var online_address: String = ""
static var _loaded: bool = false


static func load_settings(from: String = "") -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(from if from != "" else path) != OK:
		return
	volume = clampf(float(cfg.get_value("audio", "volume", volume)), 0.0, 1.0)
	music_on = bool(cfg.get_value("audio", "music_on", music_on))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("video", "vsync", vsync))
	weather = bool(cfg.get_value("video", "weather", weather))
	outlines = bool(cfg.get_value("video", "outlines", outlines))
	ambience = bool(cfg.get_value("video", "ambience", ambience))
	var setup: Variant = cfg.get_value("skirmish", "last_setup", {})
	last_setup = setup if setup is Dictionary else {}
	online_name = String(cfg.get_value("online", "name", online_name))
	online_address = String(cfg.get_value("online", "address", online_address))


static func save_settings(to: String = "") -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "music_on", music_on)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "weather", weather)
	cfg.set_value("video", "outlines", outlines)
	cfg.set_value("video", "ambience", ambience)
	cfg.set_value("skirmish", "last_setup", last_setup)
	cfg.set_value("online", "name", online_name)
	cfg.set_value("online", "address", online_address)
	cfg.save(to if to != "" else path)


static func ensure_loaded() -> void:
	if not _loaded:
		load_settings()


## Pushes the settings to the engine. Window changes are skipped headless.
static func apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(bus, volume <= 0.001)
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
