class_name RaceAudio
extends Node
## Reprodução offline: a chave e a API nunca entram no processo Godot.
## Integração: add_child(RaceAudio.new()); audio.play_event("boost", 1).

signal cue_started(kind: String, team: int, has_voice: bool)

const MANIFEST_PATH: String = "res://resources/audio/voice_manifest.json"
const MAX_QUEUE: int = 8
const MAX_WAIT_SECONDS: float = 6.0
const MIN_GAP_SECONDS: float = 0.45
const KINDS: Array[String] = ["start", "tie", "boost", "shield", "attack", "super_turbo", "podium", "vote", "overtake", "final_stretch", "next_round"]

@export var enabled: bool = true
@export var local_cues_enabled: bool = true
@export_range(-30.0, 0.0, 1.0) var voice_volume_db: float = -8.0

var voices_ready: bool = false
var voice_status: String = "vozes_pendentes"
var _player: AudioStreamPlayer = null
var _queue: Array[Dictionary] = []
var _clips: Array[Dictionary] = []
var _streams: Dictionary = {}
var _cooldowns: Dictionary = {}
var _variants: Dictionary = {}
var _cues: Dictionary = {}
var _clock: float = 0.0
var _next_start: float = 0.0
var _active_priority: int = 0
var _active_kind: String = ""
var _active_team: int = 0
var _current_leader: int = -1
var _paused: bool = false


func _ready() -> void:
	_ensure_bus()
	_player = AudioStreamPlayer.new()
	_player.name = "Announcer"
	_player.bus = &"RaceAnnouncer"
	_player.volume_db = voice_volume_db
	_player.finished.connect(_on_finished)
	add_child(_player)
	if FileAccess.file_exists(MANIFEST_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if parsed is Dictionary:
			configure_manifest(parsed as Dictionary)


func _process(delta: float) -> void:
	if not enabled:
		if not _queue.is_empty() or (_player != null and _player.playing):
			clear_pending()
		return
	if _paused:
		return
	_clock += maxf(0.0, delta)
	if _player == null or _player.playing or _clock < _next_start:
		return
	while not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		var expiry: float = 2.5 if String((item["clip"] as Dictionary)["kind"]) == "overtake" else MAX_WAIT_SECONDS
		if _clock - float(item["queued_at"]) > expiry:
			continue
		var clip: Dictionary = item["clip"] as Dictionary
		if String(clip["kind"]) == "overtake" and _current_leader >= 0 and int(clip["team"]) != _current_leader:
			continue
		var stream: AudioStream = _streams.get(String(clip.get("id", ""))) as AudioStream
		var has_voice: bool = stream != null
		if stream == null and local_cues_enabled:
			stream = _cue(String(clip["kind"]))
		if stream == null:
			continue
		_player.stream = stream
		_player.volume_db = voice_volume_db if has_voice else minf(voice_volume_db, -14.0)
		_player.play()
		_active_priority = int(item["priority"])
		_active_kind = String(clip["kind"])
		_active_team = int(clip["team"])
		cue_started.emit(String(clip["kind"]), int(clip["team"]), has_voice)
		return


func _exit_tree() -> void:
	if _player != null:
		_player.stop()
		_player.stream = null
	_streams.clear()
	_cues.clear()


func configure_manifest(data: Dictionary) -> void:
	clear_pending()
	_clips.clear()
	_streams.clear()
	voices_ready = false
	voice_status = "vozes_pendentes"
	if int(data.get("schema_version", 0)) != 1 or not data.get("clips", []) is Array:
		return
	var raw_clips: Array = data.get("clips", []) as Array
	for raw: Variant in raw_clips:
		if not raw is Dictionary:
			continue
		var clip: Dictionary = (raw as Dictionary).duplicate(true)
		var kind: String = String(clip.get("kind", ""))
		var team: int = int(clip.get("team", -1))
		var id: String = String(clip.get("id", ""))
		if not KINDS.has(kind) or team < 0 or team > 2 or id.is_empty():
			continue
		clip["priority"] = clampi(int(clip.get("priority", 20)), 0, 100)
		clip["cooldown_seconds"] = clampf(float(clip.get("cooldown_seconds", 6.0)), 1.0, 60.0)
		_clips.append(clip)
		var path: String = String(clip.get("clip_path", ""))
		if _safe_clip_path(path) and FileAccess.file_exists(path):
			var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
			if bytes.size() >= 128 and bytes.size() <= 10000000:
				var mp3: AudioStreamMP3 = AudioStreamMP3.new()
				mp3.data = bytes
				if mp3.get_length() > 0.0:
					_streams[id] = mp3
	voices_ready = not _clips.is_empty() and _streams.size() == _clips.size()
	voice_status = "vozes_locais_prontas" if voices_ready else "vozes_pendentes"


func play_event(kind: String, team: int = 0) -> bool:
	if team < 0 or team > 2:
		return false
	var canonical: String = kind.to_lower()
	if canonical == "turbo":
		canonical = "boost"
	elif canonical == "round_start":
		canonical = "start"
	if not KINDS.has(canonical):
		return false
	# Atualizar a verdade da corrida vem antes do cooldown: 1 -> 2 -> 1
	# não pode deixar a fala de 2 na fila só porque a nova fala de 1 foi limitada.
	if canonical == "overtake":
		set_current_leader(team)
	if not enabled or _paused:
		return false
	if canonical in ["start", "tie", "final_stretch", "next_round"]:
		team = 0
	var key: String = "%s:%d" % [canonical, team]
	if _clock < float(_cooldowns.get(key, -1.0)):
		return false
	var matches: Array[Dictionary] = []
	for clip: Dictionary in _clips:
		if clip["kind"] == canonical and int(clip["team"]) == team:
			matches.append(clip)
	if matches.is_empty():
		return false
	var variant_index: int = int(_variants.get(key, 0)) % matches.size()
	var selected: Dictionary = matches[variant_index]
	var priority: int = int(selected["priority"])
	# A vitória cancela impulsos antigos; uma ultrapassagem substitui outra
	# ainda na fila para não anunciar um líder que já perdeu a posição.
	if canonical in ["podium", "tie"]:
		_queue.clear()
		if _player != null and _active_priority < priority:
			_player.stop()
			_next_start = _clock
	elif canonical == "overtake":
		for index: int in range(_queue.size() - 1, -1, -1):
			if String((_queue[index]["clip"] as Dictionary)["kind"]) == "overtake":
				_queue.remove_at(index)
	if _queue.size() >= MAX_QUEUE:
		var lowest: int = _queue.size() - 1
		if priority <= int(_queue[lowest]["priority"]):
			return false
		_queue.remove_at(lowest)
	var item: Dictionary = {"clip": selected, "priority": priority, "queued_at": _clock}
	var inserted: bool = false
	for index: int in range(_queue.size()):
		if priority > int(_queue[index]["priority"]):
			_queue.insert(index, item)
			inserted = true
			break
	if not inserted:
		_queue.append(item)
	_cooldowns[key] = _clock + float(selected["cooldown_seconds"])
	_variants[key] = variant_index + 1
	return true


func set_current_leader(team: int) -> void:
	if team < 0 or team > 2:
		return
	_current_leader = team
	for index: int in range(_queue.size() - 1, -1, -1):
		var clip: Dictionary = _queue[index]["clip"] as Dictionary
		if String(clip["kind"]) == "overtake" and int(clip["team"]) != team:
			_queue.remove_at(index)
	if _active_kind == "overtake" and _active_team != team:
		if _player != null:
			_player.stop()
		_active_priority = 0
		_active_kind = ""
		_active_team = 0
		_next_start = maxf(_next_start, _clock + MIN_GAP_SECONDS)


func clear_pending(stop_current: bool = true) -> void:
	_queue.clear()
	_cooldowns.clear()
	if stop_current and _player != null:
		_player.stop()
	_next_start = _clock + MIN_GAP_SECONDS
	_current_leader = -1
	if stop_current or _player == null or not _player.playing:
		_active_priority = 0
		_active_kind = ""
		_active_team = 0


func set_paused(value: bool) -> void:
	_paused = value
	if _player != null:
		_player.stream_paused = value


func is_voice_playing() -> bool:
	return _player != null and _player.playing and not _paused


func _on_finished() -> void:
	_next_start = _clock + MIN_GAP_SECONDS
	_active_priority = 0
	_active_kind = ""
	_active_team = 0


func _safe_clip_path(path: String) -> bool:
	if not path.begins_with("res://assets/audio/elevenlabs/") or not path.ends_with(".mp3"):
		return false
	var filename: String = path.get_file()
	var stem: String = filename.trim_suffix(".mp3")
	if stem.length() != 64 or path.get_base_dir() != "res://assets/audio/elevenlabs":
		return false
	for character: String in stem:
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _ensure_bus() -> void:
	var master: int = AudioServer.get_bus_index(&"Master")
	var has_limiter: bool = false
	for effect_index: int in range(AudioServer.get_bus_effect_count(master)):
		if AudioServer.get_bus_effect(master, effect_index) is AudioEffectLimiter:
			has_limiter = true
	if not has_limiter:
		var master_limiter: AudioEffectLimiter = AudioEffectLimiter.new()
		master_limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(master, master_limiter)
	if AudioServer.get_bus_index(&"RaceAnnouncer") >= 0:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, &"RaceAnnouncer")
	AudioServer.set_bus_send(index, &"Master")
	var limiter: AudioEffectLimiter = AudioEffectLimiter.new()
	limiter.ceiling_db = -1.0
	AudioServer.add_bus_effect(index, limiter)


func _cue(kind: String) -> AudioStreamWAV:
	if _cues.has(kind):
		return _cues[kind] as AudioStreamWAV
	# Sons locais discretos, sem simular uma fala ElevenLabs configurada.
	var frequencies: Dictionary = {"start": 880.0, "tie": 520.0, "boost": 660.0, "shield": 790.0, "attack": 240.0, "super_turbo": 990.0, "podium": 1040.0, "vote": 450.0}
	var sample_rate: int = 22050
	var samples: int = int(float(sample_rate) * 0.20)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples * 2)
	var frequency: float = float(frequencies.get(kind, 660.0))
	for index: int in range(samples):
		var t: float = float(index) / float(sample_rate)
		var envelope: float = sin(PI * float(index) / float(samples))
		var value: int = int(sin(TAU * frequency * t) * envelope * 6500.0)
		bytes.encode_s16(index * 2, value)
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	_cues[kind] = stream
	return stream
