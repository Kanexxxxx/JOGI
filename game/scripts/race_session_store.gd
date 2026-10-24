class_name RaceSessionStore
extends RefCounted
## Single-writer local persistence. Channel names never become arbitrary filesystem paths.
## A successful append means FileAccess.flush() completed, not a hardware power-loss guarantee.

const SCHEMA_VERSION: int = 1
const CHANNELS: Array[String] = ["local", "tiktok", "kwai"]
const DEFAULT_DIRECTORY: String = "user://sessions"
const TEST_DIRECTORY_PREFIX: String = "user://session-store-tests/"
const MAX_SNAPSHOT_BYTES: int = 64 * 1024 * 1024
const MAX_JOURNAL_BYTES: int = 2 * 1024 * 1024 * 1024
const MAX_GIFT_RECORD_BYTES: int = 16 * 1024
const MAX_REPLAY_BYTES: int = 32 * 1024 * 1024
const MAX_REPLAY_EVENTS: int = 20000
const MAX_JSON_DEPTH: int = 32
const MAX_CONTAINER_ITEMS: int = 150000
const MAX_EXACT_JSON_INTEGER: int = 9007199254740991

var last_error: String = ""
var loaded_from_backup: bool = false
var last_replay_cursor: int = 0
var _channel: String = ""
var _directory: String = ""
var _configured: bool = false


func _init(channel: String = "local", base_directory: String = DEFAULT_DIRECTORY) -> void:
	configure(channel, base_directory)


func configure(channel: String, base_directory: String = DEFAULT_DIRECTORY) -> bool:
	last_error = ""
	_configured = false
	_channel = ""
	_directory = ""
	if not CHANNELS.has(channel) or not _safe_base_directory(base_directory):
		last_error = "invalid_storage_location"
		return false
	_channel = channel
	_directory = base_directory.path_join(channel)
	_configured = true
	return true


func get_storage_directory() -> String:
	return _directory


func save_snapshot(state: Dictionary) -> bool:
	last_error = ""
	if not _ready_for_write():
		return false
	if not _is_json_safe(state):
		return _fail("snapshot_invalid_state")
	var wrapper: Dictionary = {
		"schema_version": SCHEMA_VERSION, "channel": _channel,
		"saved_at_unix_ms": int(Time.get_unix_time_from_system() * 1000.0), "state": state
	}
	var bytes: PackedByteArray = JSON.stringify(wrapper).to_utf8_buffer()
	if bytes.size() > MAX_SNAPSHOT_BYTES:
		return _fail("snapshot_size_limit")
	var main_path: String = _directory.path_join("snapshot.json")
	var temporary_path: String = main_path + ".tmp"
	var backup_path: String = main_path + ".bak"
	if not _write_bytes(temporary_path, bytes):
		return false
	# Preserve only a validated previous snapshot. A corrupt main must not replace a good backup.
	if FileAccess.file_exists(main_path):
		var current: Dictionary = _read_snapshot_file(main_path)
		if bool(current.get("ok", false)):
			var backup_temporary: String = backup_path + ".tmp"
			if DirAccess.copy_absolute(main_path, backup_temporary) != OK:
				return _fail("snapshot_backup_copy_failed")
			if DirAccess.rename_absolute(backup_temporary, backup_path) != OK:
				return _fail("snapshot_backup_replace_failed")
	if DirAccess.rename_absolute(temporary_path, main_path) != OK:
		return _fail("snapshot_replace_failed")
	return true


func load_snapshot() -> Dictionary:
	last_error = ""
	loaded_from_backup = false
	if not _configured:
		last_error = "not_configured"
		return {}
	var main_path: String = _directory.path_join("snapshot.json")
	var primary: Dictionary = _read_snapshot_file(main_path)
	if bool(primary.get("ok", false)):
		return (primary["state"] as Dictionary).duplicate(true)
	var backup: Dictionary = _read_snapshot_file(main_path + ".bak")
	if bool(backup.get("ok", false)):
		loaded_from_backup = true
		return (backup["state"] as Dictionary).duplicate(true)
	last_error = String(primary.get("error", "snapshot_unavailable"))
	if last_error == "snapshot_missing" and String(backup.get("error", "")) != "snapshot_missing":
		last_error = String(backup.get("error", "snapshot_unavailable"))
	return {}


func append_gift(envelope: Dictionary) -> bool:
	last_error = ""
	if not _ready_for_write():
		return false
	if not _valid_gift(envelope) or not _is_json_safe(envelope):
		return _fail("invalid_gift_envelope")
	var wrapper: Dictionary = {"schema_version": SCHEMA_VERSION, "channel": _channel, "gift": envelope}
	var bytes: PackedByteArray = (JSON.stringify(wrapper) + "\n").to_utf8_buffer()
	if bytes.size() > MAX_GIFT_RECORD_BYTES:
		return _fail("gift_record_size_limit")
	var path: String = _directory.path_join("gifts.jsonl")
	var mode: FileAccess.ModeFlags = FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE_READ
	var file: FileAccess = FileAccess.open(path, mode)
	if file == null:
		return _fail("journal_open_failed")
	var previous_length: int = file.get_length()
	if previous_length > MAX_JOURNAL_BYTES - bytes.size():
		file.close()
		return _fail("journal_size_limit")
	if previous_length > 0:
		file.seek(previous_length - 1)
		if file.get_8() != 10:
			file.close()
			return _fail("journal_incomplete_tail")
	file.seek_end()
	file.store_buffer(bytes)
	file.flush()
	var write_error: Error = file.get_error()
	var position: int = file.get_position()
	file.close()
	if write_error != OK or position != previous_length + bytes.size():
		return _fail("journal_write_failed")
	return true


func get_journal_cursor() -> int:
	last_error = ""
	if not _configured:
		last_error = "not_configured"
		return -1
	var path: String = _directory.path_join("gifts.jsonl")
	if not FileAccess.file_exists(path):
		return 0
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "journal_open_failed"
		return -1
	var length: int = file.get_length()
	if length > MAX_JOURNAL_BYTES:
		file.close()
		last_error = "journal_size_limit"
		return -1
	if length > 0:
		file.seek(length - 1)
		if file.get_8() != 10:
			file.close()
			last_error = "journal_incomplete_tail"
			return -1
	file.close()
	return length


func load_gifts_since(cursor: int) -> Array[Dictionary]:
	last_error = ""
	last_replay_cursor = cursor
	var gifts: Array[Dictionary] = []
	if not _configured:
		last_error = "not_configured"
		return gifts
	var path: String = _directory.path_join("gifts.jsonl")
	if not FileAccess.file_exists(path):
		if cursor != 0:
			last_error = "journal_cursor_out_of_range"
		return gifts
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "journal_open_failed"
		return gifts
	var length: int = file.get_length()
	if cursor < 0 or cursor > length or length > MAX_JOURNAL_BYTES:
		file.close()
		last_error = "journal_cursor_out_of_range"
		return gifts
	if length - cursor > MAX_REPLAY_BYTES:
		file.close()
		last_error = "journal_replay_byte_limit"
		return gifts
	if cursor > 0:
		file.seek(cursor - 1)
		if file.get_8() != 10:
			file.close()
			last_error = "journal_cursor_not_record_boundary"
			return gifts
	file.seek(cursor)
	while file.get_position() < length:
		if gifts.size() >= MAX_REPLAY_EVENTS:
			last_error = "journal_replay_event_limit"
			break
		var start: int = file.get_position()
		var line: String = file.get_line()
		var end: int = file.get_position()
		if end <= start or end - start > MAX_GIFT_RECORD_BYTES:
			last_error = "journal_record_size_limit"
			break
		# EOF can also be reached after a partial final JSON value. Only newline-terminated records commit.
		file.seek(end - 1)
		var last_byte: int = file.get_8()
		if last_byte != 10:
			last_error = "journal_incomplete_tail"
			break
		var parser: JSON = JSON.new()
		if parser.parse(line) != OK or not parser.data is Dictionary:
			last_error = "journal_invalid_json"
			break
		var wrapper: Dictionary = parser.data as Dictionary
		if _integer(wrapper.get("schema_version"), SCHEMA_VERSION, SCHEMA_VERSION) < 0 or wrapper.get("channel") != _channel or not wrapper.get("gift") is Dictionary:
			last_error = "journal_invalid_record"
			break
		var gift: Dictionary = wrapper["gift"] as Dictionary
		if not _valid_gift(gift) or not _is_json_safe(gift):
			last_error = "journal_invalid_gift"
			break
		gifts.append(gift)
	file.close()
	if not last_error.is_empty():
		# All-or-nothing replay: caller must not save a cursor beyond a corrupt or oversized tail.
		gifts.clear()
		return gifts
	last_replay_cursor = length
	return gifts


func _read_snapshot_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "snapshot_missing"}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "snapshot_open_failed"}
	var length: int = file.get_length()
	if length <= 0 or length > MAX_SNAPSHOT_BYTES:
		file.close()
		return {"ok": false, "error": "snapshot_size_limit"}
	var bytes: PackedByteArray = file.get_buffer(length)
	file.close()
	if bytes.size() != length:
		return {"ok": false, "error": "snapshot_read_failed"}
	var parser: JSON = JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "snapshot_invalid_json"}
	var wrapper: Dictionary = parser.data as Dictionary
	if _integer(wrapper.get("schema_version"), SCHEMA_VERSION, SCHEMA_VERSION) < 0 or wrapper.get("channel") != _channel or not wrapper.get("state") is Dictionary:
		return {"ok": false, "error": "snapshot_invalid_schema"}
	if not _is_json_safe(wrapper["state"]):
		return {"ok": false, "error": "snapshot_invalid_state"}
	return {"ok": true, "state": wrapper["state"]}


func _ready_for_write() -> bool:
	if not _configured:
		return _fail("not_configured")
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		return _fail("storage_directory_unavailable")
	return true


func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail("snapshot_write_open_failed")
	file.store_buffer(bytes)
	file.flush()
	var write_error: Error = file.get_error()
	var position: int = file.get_position()
	file.close()
	if write_error != OK or position != bytes.size():
		return _fail("snapshot_write_failed")
	return true


func _safe_base_directory(path: String) -> bool:
	if path == DEFAULT_DIRECTORY:
		return true
	if not path.begins_with(TEST_DIRECTORY_PREFIX) or path.length() > 180:
		return false
	var suffix: String = path.substr(TEST_DIRECTORY_PREFIX.length())
	if suffix.is_empty() or suffix.contains("/") or suffix.contains("\\") or suffix in [".", ".."]:
		return false
	for index: int in range(suffix.length()):
		var code: int = suffix.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code in [45, 95]):
			return false
	return true


func _valid_gift(envelope: Dictionary) -> bool:
	if envelope.get("schema_version") != "1.0" or envelope.get("event_type") != "gift":
		return false
	if not envelope.get("source") in ["tiktok", "kwai", "simulator"]:
		return false
	if not envelope.get("event_id") is String or not envelope.get("user") is Dictionary or not envelope.get("payload") is Dictionary:
		return false
	var event_id: String = String(envelope["event_id"])
	if event_id.length() < 8 or event_id.length() > 128:
		return false
	var user: Dictionary = envelope["user"] as Dictionary
	if not user.get("user_id") is String or not user.get("display_name") is String:
		return false
	if String(user["user_id"]).is_empty() or String(user["user_id"]).length() > 64 or String(user["display_name"]).length() > 24:
		return false
	var payload: Dictionary = envelope["payload"] as Dictionary
	if _integer(payload.get("coin_value", 0), 0, 100000000) < 0:
		return false
	if payload.has("candidate_slot") and _integer(payload["candidate_slot"], 0, 2) < 0:
		return false
	return true


func _integer(value: Variant, minimum: int, maximum: int) -> int:
	if typeof(value) == TYPE_INT:
		var integer: int = int(value)
		return integer if integer >= minimum and integer <= maximum else -1
	if typeof(value) == TYPE_FLOAT:
		var number: float = float(value)
		if is_finite(number) and number == floorf(number) and number >= minimum and number <= maximum:
			return int(number)
	return -1


func _is_json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_JSON_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			var integer: int = int(value)
			return integer >= -MAX_EXACT_JSON_INTEGER and integer <= MAX_EXACT_JSON_INTEGER
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			var values: Array = value as Array
			if values.size() > MAX_CONTAINER_ITEMS:
				return false
			for child: Variant in values:
				if not _is_json_safe(child, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			var values: Dictionary = value as Dictionary
			if values.size() > MAX_CONTAINER_ITEMS:
				return false
			for key: Variant in values:
				if not key is String or not _is_json_safe(values[key], depth + 1):
					return false
			return true
	return false


func _fail(error: String) -> bool:
	last_error = error
	return false
