class_name RaceMemeBoard
extends Node
## Clipes do usuário: só toca seleção revisada e habilitada no manifesto local.

const MANIFEST_PATH: String = "res://resources/audio/user_meme_manifest.json"
const KINDS: Array[String] = ["boost", "shield", "impact", "victory", "overtake", "reaction"]
const GLOBAL_COOLDOWN: float = 45.0

@export var enabled: bool = false
@export_range(-30.0, -12.0, 1.0) var volume_db: float = -18.0

var _player: AudioStreamPlayer = null
var _clips: Array[Dictionary] = []
var _streams: Dictionary = {}
var _clock: float = 0.0
var _next_allowed: float = 0.0
var _clip_cooldowns: Dictionary = {}
var _paused: bool = false
var _voice_busy: bool = false
var _pending: Dictionary = {}
var _variant: int = 0


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "MemeRevisado"
	_player.volume_db = volume_db
	add_child(_player)
	if FileAccess.file_exists(MANIFEST_PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if data is Dictionary:
			configure_manifest(data as Dictionary)


func configure_manifest(data: Dictionary) -> void:
	stop_all()
	_clips.clear()
	_streams.clear()
	enabled = false
	if int(data.get("schema_version", 0)) != 1 or not data.get("clips", []) is Array:
		return
	enabled = data.get("enabled", false) is bool and bool(data.get("enabled", false))
	for raw: Variant in data.get("clips", []) as Array:
		if not raw is Dictionary:
			continue
		var clip: Dictionary = raw as Dictionary
		if clip.get("enabled", false) != true or String(clip.get("review_status", "")) != "approved":
			continue
		var kind: String = String(clip.get("kind", ""))
		var path: String = String(clip.get("clip_path", ""))
		var team: int = int(clip.get("team", -1))
		if not KINDS.has(kind) or team < 0 or team > 2 or not _safe_path(path) or not FileAccess.file_exists(path):
			continue
		var body: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if body.size() < 128 or body.size() > 1000000:
			continue
		var stream: AudioStreamMP3 = AudioStreamMP3.new()
		stream.data = body
		if stream.get_length() < 0.1 or stream.get_length() > 5.0:
			continue
		var id: String = path.get_file().trim_suffix(".mp3")
		_streams[id] = stream
		_clips.append({"id": id, "kind": kind, "team": team, "cooldown": clampf(float(clip.get("cooldown_seconds", 60.0)), 45.0, 600.0)})


func play_event(kind: String, team: int = 0) -> bool:
	if not enabled or _paused or _clock < _next_allowed or _player == null or _player.playing or not _pending.is_empty():
		return false
	var options: Array[Dictionary] = []
	for clip: Dictionary in _clips:
		if String(clip["kind"]) == kind and (int(clip["team"]) == team or int(clip["team"]) == 0) and _clock >= float(_clip_cooldowns.get(clip["id"], -1.0)):
			options.append(clip)
	if options.is_empty():
		return false
	var selected: Dictionary = options[_variant % options.size()]
	_variant += 1
	_pending = {"clip": selected, "queued_at": _clock}
	return true


func _process(delta: float) -> void:
	if not enabled:
		stop_all()
		return
	if _paused:
		return
	_clock += maxf(0.0, delta)
	if _pending.is_empty():
		return
	if _clock - float(_pending["queued_at"]) > 2.0:
		_pending.clear()
		return
	if _voice_busy:
		return
	var clip: Dictionary = _pending["clip"] as Dictionary
	_player.stream = _streams.get(clip["id"]) as AudioStream
	_player.volume_db = clampf(volume_db, -30.0, -12.0)
	_player.play()
	_next_allowed = _clock + GLOBAL_COOLDOWN
	_clip_cooldowns[clip["id"]] = _clock + float(clip["cooldown"])
	_pending.clear()


func set_ducked(value: bool) -> void:
	_voice_busy = value
	if value and _player != null and _player.playing:
		_player.stop()


func set_paused(value: bool) -> void:
	_paused = value
	if _player != null:
		_player.stream_paused = value


func stop_all() -> void:
	_pending.clear()
	if _player != null:
		_player.stop()


func get_status() -> Dictionary:
	return {"enabled": enabled, "approved_clips": _clips.size(), "playing": _player != null and _player.playing}


func _safe_path(path: String) -> bool:
	if path.get_base_dir() != "res://assets/audio/user-memes" or not path.ends_with(".mp3"):
		return false
	var stem: String = path.get_file().trim_suffix(".mp3")
	if stem.length() != 64:
		return false
	for character: String in stem:
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _exit_tree() -> void:
	stop_all()
	if _player != null:
		_player.stream = null
	_streams.clear()
