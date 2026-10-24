class_name RaceSoundEffects
extends Node
## Quatro canais locais para SFX; locução permanece no RaceAudio separado.

const MANIFEST_PATH: String = "res://resources/audio/sfx_manifest.json"
const POOL_SIZE: int = 4
const KINDS: Array[String] = ["boost", "shield", "impact", "victory"]

@export var enabled: bool = true
@export_range(-30.0, -6.0, 1.0) var volume_db: float = -16.0

var sfx_ready: bool = false
var sound_status: String = "efeitos_pendentes"
var _players: Array[AudioStreamPlayer] = []
var _priorities: Array[int] = []
var _streams: Dictionary = {}
var _settings: Dictionary = {}
var _next_allowed: Dictionary = {}
var _clock: float = 0.0
var _paused: bool = false
var _ducked: bool = false


func _ready() -> void:
	_ensure_bus()
	for index: int in range(POOL_SIZE):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "CanalSFX%d" % (index + 1)
		player.bus = &"RaceSFX"
		player.volume_db = volume_db
		add_child(player)
		_players.append(player)
		_priorities.append(0)
	if FileAccess.file_exists(MANIFEST_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if parsed is Dictionary:
			configure_manifest(parsed as Dictionary)


func _process(delta: float) -> void:
	if not enabled:
		stop_all()
		return
	if not _paused:
		_clock += maxf(0.0, delta)


func _exit_tree() -> void:
	stop_all()
	for player: AudioStreamPlayer in _players:
		player.stream = null
	_streams.clear()


func configure_manifest(data: Dictionary) -> void:
	stop_all()
	_streams.clear()
	_settings.clear()
	sfx_ready = false
	sound_status = "efeitos_pendentes"
	if int(data.get("schema_version", 0)) != 1 or not data.get("clips", []) is Array:
		return
	for raw: Variant in data.get("clips", []) as Array:
		if not raw is Dictionary:
			continue
		var clip: Dictionary = raw as Dictionary
		var kind: String = String(clip.get("kind", ""))
		var path: String = String(clip.get("clip_path", ""))
		if not KINDS.has(kind):
			continue
		_settings[kind] = {"priority":clampi(int(clip.get("priority", 30)), 0, 100), "cooldown":clampf(float(clip.get("cooldown_seconds", .3)), .1, 10.0)}
		if not _safe_path(path) or not FileAccess.file_exists(path):
			continue
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if bytes.size() < 128 or bytes.size() > 1000000:
			continue
		var stream: AudioStreamMP3 = AudioStreamMP3.new()
		stream.data = bytes
		if stream.get_length() > 0.0 and stream.get_length() <= 4.0:
			_streams[kind] = stream
	sfx_ready = _streams.size() == KINDS.size()
	sound_status = "efeitos_locais_prontos" if sfx_ready else "efeitos_pendentes"


func play_event(kind: String, team: int = 0) -> bool:
	if not enabled or _paused or team < 0 or team > 2:
		return false
	var canonical: String = kind.to_lower()
	if canonical == "turbo" or canonical == "super_turbo":
		canonical = "boost"
	elif canonical == "attack" or canonical == "stumble":
		canonical = "impact"
	elif canonical == "podium" or canonical == "tie":
		canonical = "victory"
	if not KINDS.has(canonical) or not _streams.has(canonical) or _clock < float(_next_allowed.get(canonical, -1.0)):
		return false
	var priority: int = int((_settings[canonical] as Dictionary)["priority"])
	var selected: int = -1
	for index: int in range(_players.size()):
		if not _players[index].playing:
			selected = index
			break
	if selected == -1:
		var lowest_priority: int = 101
		for index: int in range(_priorities.size()):
			if _priorities[index] < lowest_priority:
				lowest_priority = _priorities[index]
				selected = index
		if priority <= lowest_priority:
			return false
	var player: AudioStreamPlayer = _players[selected]
	player.stop()
	player.stream = _streams[canonical] as AudioStream
	player.volume_db = volume_db - (6.0 if _ducked else 0.0)
	player.pitch_scale = 1.0
	player.play()
	_priorities[selected] = priority
	_next_allowed[canonical] = _clock + float((_settings[canonical] as Dictionary)["cooldown"])
	return true


func set_paused(value: bool) -> void:
	_paused = value
	for player: AudioStreamPlayer in _players:
		player.stream_paused = value


func set_ducked(value: bool) -> void:
	_ducked = value
	for player: AudioStreamPlayer in _players:
		player.volume_db = volume_db - (6.0 if value else 0.0)


func stop_all() -> void:
	_next_allowed.clear()
	for player: AudioStreamPlayer in _players:
		player.stop()
	for index: int in range(_priorities.size()):
		_priorities[index] = 0


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
	if AudioServer.get_bus_index(&"RaceSFX") >= 0:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, &"RaceSFX")
	AudioServer.set_bus_send(index, &"Master")
	var limiter: AudioEffectLimiter = AudioEffectLimiter.new()
	limiter.ceiling_db = -1.0
	AudioServer.add_bus_effect(index, limiter)
