class_name RaceAmbience
extends Node
## Torcida original em cache. Dois players fixos fazem transição suave no loop.

const MANIFEST_PATH: String = "res://resources/audio/ambience_manifest.json"
const CROSSFADE_SECONDS: float = 0.7

@export var enabled: bool = true
@export_range(-40.0, -20.0, 1.0) var volume_db: float = -27.0

var ambience_ready: bool = false
var sound_status: String = "torcida_pendente"
var _players: Array[AudioStreamPlayer] = []
var _stream: AudioStreamMP3 = null
var _current: int = 0
var _elapsed: float = 0.0
var _fade_elapsed: float = -1.0
var _paused: bool = false
var _ducked: bool = false
var _running: bool = false
var _energy: float = 1.0
var _level: float = 0.0


func _ready() -> void:
	_ensure_bus()
	for index: int in range(2):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Torcida%d" % (index + 1)
		player.bus = &"RaceCrowd"
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)
	if FileAccess.file_exists(MANIFEST_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if parsed is Dictionary:
			configure_manifest(parsed as Dictionary)


func configure_manifest(data: Dictionary) -> void:
	stop_all()
	_stream = null
	ambience_ready = false
	sound_status = "torcida_pendente"
	if int(data.get("schema_version", 0)) != 1 or String(data.get("pack_kind", "")) != "arena_ambience":
		return
	var clips: Variant = data.get("clips", [])
	if not clips is Array or (clips as Array).size() != 1 or not (clips as Array)[0] is Dictionary:
		return
	var clip: Dictionary = (clips as Array)[0] as Dictionary
	var path: String = String(clip.get("clip_path", ""))
	if String(clip.get("kind", "")) != "crowd" or not _safe_path(path) or not FileAccess.file_exists(path):
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() < 128 or bytes.size() > 1000000:
		return
	var stream: AudioStreamMP3 = AudioStreamMP3.new()
	stream.data = bytes
	if stream.get_length() < 2.0 or stream.get_length() > 11.0:
		return
	_stream = stream
	for player: AudioStreamPlayer in _players:
		player.stream = _stream
	ambience_ready = true
	sound_status = "torcida_local_pronta"


func update_state(running: bool, speed_ratio: float = 1.0) -> void:
	_running = running
	_energy = clampf(speed_ratio, 0.0, 2.0) if is_finite(speed_ratio) else 1.0


func set_paused(value: bool) -> void:
	_paused = value
	for player: AudioStreamPlayer in _players:
		player.stream_paused = value


func set_ducked(value: bool) -> void:
	_ducked = value


func stop_all() -> void:
	for player: AudioStreamPlayer in _players:
		player.stop()
	_elapsed = 0.0
	_fade_elapsed = -1.0
	_current = 0
	_level = 0.0


func _process(delta: float) -> void:
	if not enabled:
		if _players.size() == 2 and (_players[0].playing or _players[1].playing):
			stop_all()
		return
	if _paused or not ambience_ready or _players.size() != 2:
		return
	var dt: float = maxf(delta, 0.0)
	var target_db: float = clampf(volume_db, -40.0, -20.0) - (9.0 if _ducked else 0.0) - (0.0 if _running else 5.0)
	target_db += minf(_energy, 1.5) * 1.5
	_level = lerpf(_level, db_to_linear(target_db), 1.0 - exp(-4.0 * dt))
	if not _players[_current].playing and _fade_elapsed < 0.0:
		_players[_current].play()
		_elapsed = 0.0
	_elapsed += dt
	if _fade_elapsed < 0.0 and _elapsed >= _stream.get_length() - CROSSFADE_SECONDS:
		_players[1 - _current].play()
		_fade_elapsed = 0.0
	if _fade_elapsed >= 0.0:
		_fade_elapsed += dt
		var factor: float = clampf(_fade_elapsed / CROSSFADE_SECONDS, 0.0, 1.0)
		_players[_current].volume_db = linear_to_db(maxf(0.0001, _level * cos(factor * PI * 0.5)))
		_players[1 - _current].volume_db = linear_to_db(maxf(0.0001, _level * sin(factor * PI * 0.5)))
		if factor >= 1.0:
			_players[_current].stop()
			_current = 1 - _current
			_elapsed = CROSSFADE_SECONDS
			_fade_elapsed = -1.0
	else:
		_players[_current].volume_db = linear_to_db(maxf(0.0001, _level))
		_players[1 - _current].volume_db = -80.0


func get_status() -> Dictionary:
	return {"ready": ambience_ready, "status": sound_status, "enabled": enabled, "paused": _paused, "players": _players.size(), "seconds": _stream.get_length() if _stream != null else 0.0}


func _safe_path(path: String) -> bool:
	if path.get_base_dir() != "res://assets/audio/elevenlabs-sfx" or not path.ends_with(".mp3"):
		return false
	var stem: String = path.get_file().trim_suffix(".mp3")
	if stem.length() != 64:
		return false
	for character: String in stem:
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _ensure_bus() -> void:
	if AudioServer.get_bus_index(&"RaceCrowd") >= 0:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, &"RaceCrowd")
	AudioServer.set_bus_send(index, &"Master")
	var limiter: AudioEffectLimiter = AudioEffectLimiter.new()
	limiter.ceiling_db = -6.0
	AudioServer.add_bus_effect(index, limiter)


func _exit_tree() -> void:
	stop_all()
	for player: AudioStreamPlayer in _players:
		player.stream = null
	_stream = null
