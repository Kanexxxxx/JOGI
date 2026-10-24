class_name LiveEventBusInstance
extends Node

signal live_event_accepted(envelope: Dictionary)
signal candidate_boost_requested(candidate_slot: int, boost_amount: float, duration: float, voter_name: String, label: String)
signal candidate_vote_registered(candidate_slot: int, vote_weight: int, voter_name: String)
signal candidate_shield_requested(candidate_slot: int, duration: float, voter_name: String)
signal candidate_attack_requested(target_slot: int, obstacle_type: String, voter_name: String)
signal admin_command_requested(command: String, payload: Dictionary)
signal event_rejected(reason: String)
signal duplicate_ignored(event_id: String)
signal connection_state_changed(is_connected: bool, status_text: String)

const SUPPORTED_SCHEMA_VERSION: String = "1.0"
const VALID_SOURCES: Array[String] = ["tiktok", "kwai", "simulator", "admin"]
const VALID_EVENT_TYPES: Array[String] = [
	"gift",
	"vote",
	"like_batch",
	"share",
	"follow",
	"admin_command",
	"system_status"
]
const MAX_DEDUP_CACHE_SIZE: int = 2000
const MAX_DISPLAY_NAME_LEN: int = 24
const MAX_PACKET_BYTES: int = 8192
const MAX_PACKETS_PER_FRAME: int = 10
const MIN_RECONNECT_DELAY: float = 1.0
const MAX_RECONNECT_DELAY: float = 15.0
const VALID_ADMIN_COMMANDS: Array[String] = [
	"restart_race",
	"restart",
	"reset",
	"start_race",
	"skip_lobby",
	"pause_race",
	"resume_race",
	"reset_dedup",
	"boost",
	"turbo",
	"shield",
	"attack",
	"spawn_obstacle",
	"candidate_boost",
	"candidate_shield",
	"candidate_attack",
	"set_live_goal",
	"set_live_goals",
	"set_audio_settings",
	"end_experience"
]

@export var ws_url: String = "ws://127.0.0.1:8765/ws/godot"
@export var auto_connect: bool = true

var is_ws_connected: bool = false
var ws_status_text: String = "OFFLINE (SIMULADOR LOCAL)"
var accepted_count: int = 0
var rejected_count: int = 0
var duplicate_count: int = 0
var reconnect_delay: float = MIN_RECONNECT_DELAY
var reconnect_timer: float = 0.0
var allow_headless_ws: bool = false
## Optional durable journal hook. A failed write must leave the gift unacknowledged.
var gift_commit_hook: Callable = Callable()
## Synchronous dispatch context; never retained after event delivery.
var current_event_type: String = ""
var current_event_payload: Dictionary = {}
var runtime_mode: String = "production"
var session_platform: String = ""
var effects_suspended: bool = false
var admin_command_executor: Callable = Callable()
var last_command_result: Dictionary = {}
var _command_results: Dictionary = {}

var _ws_peer: WebSocketPeer = null
var _connect_in_progress: bool = false
var _seen_event_order: Array[String] = []
var _seen_event_lookup: Dictionary = {}
var _bbcode_regex: RegEx = null


func _ready() -> void:
	runtime_mode = "development" if OS.get_environment("JOGI_MODE").strip_edges().to_lower() == "development" else "production"
	session_platform = OS.get_environment("LIVE_PLATFORM").strip_edges().to_lower()
	if runtime_mode == "production" and not session_platform in ["tiktok", "kwai"]:
		auto_connect = false
	var configured_url: String = OS.get_environment("LIVE_BRIDGE_WS_URL").strip_edges()
	if not configured_url.is_empty():
		ws_url = configured_url
	# A bancada pode ser aberta pelo launcher, CLI ou F6, antes de existir current_scene.
	if runtime_mode == "development" and (OS.get_cmdline_user_args().has("--asset-preview") or OS.get_cmdline_args().has("res://scenes/characters/character_preview.tscn")):
		auto_connect = false
	_ws_peer = WebSocketPeer.new()
	_bbcode_regex = RegEx.new()
	_bbcode_regex.compile("\\[/?[a-zA-Z0-9_=#:.,\\s-]*\\]")
	if auto_connect and (allow_headless_ws or not DisplayServer.get_name().begins_with("headless")):
		_attempt_ws_connect()
	else:
		ws_status_text = "MODO LOCAL / HEADLESS"


func _exit_tree() -> void:
	if _ws_peer != null:
		_ws_peer.close()
		_ws_peer = null
	_seen_event_order.clear()
	_seen_event_lookup.clear()
	_bbcode_regex = null


func is_loopback_ws_url(url: String) -> bool:
	var normalized: String = url.strip_edges().to_lower()
	var pattern: RegEx = RegEx.new()
	pattern.compile("^ws://(?:127\\.0\\.0\\.1|localhost):([0-9]{1,5})/ws/godot$")
	var match_result: RegExMatch = pattern.search(normalized)
	return match_result != null and int(match_result.get_string(1)) >= 1 and int(match_result.get_string(1)) <= 65535


func _handshake_headers() -> PackedStringArray:
	var token: String = OS.get_environment("LIVE_BRIDGE_PRODUCER_TOKEN").strip_edges()
	if token.is_empty() or token == "change_me_local_random_token":
		token = OS.get_environment("LIVE_BRIDGE_LOCAL_TOKEN").strip_edges()
	if token.is_empty() or token == "change_me_local_random_token":
		return PackedStringArray()
	return PackedStringArray(["X-JOGI-Token: " + token])


func connect_to_local_bridge(custom_url: String = "") -> Error:
	if not custom_url.strip_edges().is_empty():
		ws_url = custom_url.strip_edges()
	if not is_loopback_ws_url(ws_url):
		_reject("non_loopback_ws_url_forbidden")
		return ERR_UNAUTHORIZED
	allow_headless_ws = true
	auto_connect = true
	if _ws_peer != null:
		_ws_peer.close()
	_ws_peer = WebSocketPeer.new()
	_ws_peer.inbound_buffer_size = 65536
	_ws_peer.handshake_headers = _handshake_headers()
	var err: Error = _ws_peer.connect_to_url(ws_url)
	_connect_in_progress = (err == OK)
	return err


func poll_ws(delta: float = 0.016) -> void:
	_process(delta)


func send_packet(dict: Dictionary) -> bool:
	if _ws_peer == null or not is_ws_connected:
		return false
	if _ws_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var json_str: String = JSON.stringify(dict)
	var err: Error = _ws_peer.send_text(json_str)
	return err == OK


func send_telemetry(data: Dictionary) -> bool:
	return send_packet(data)


func _process(delta: float) -> void:
	if not auto_connect or _ws_peer == null:
		return
	if DisplayServer.get_name().begins_with("headless") and not allow_headless_ws and not _connect_in_progress and not is_ws_connected:
		return

	_ws_peer.poll()
	var state: WebSocketPeer.State = _ws_peer.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not is_ws_connected:
				is_ws_connected = true
				_connect_in_progress = false
				reconnect_delay = MIN_RECONNECT_DELAY
				ws_status_text = "CONECTADO (LIVE WS)"
				connection_state_changed.emit(true, ws_status_text)
			var processed_this_frame: int = 0
			while _ws_peer.get_available_packet_count() > 0 and processed_this_frame < MAX_PACKETS_PER_FRAME:
				processed_this_frame += 1
				var pkt: PackedByteArray = _ws_peer.get_packet()
				if pkt.size() > MAX_PACKET_BYTES:
					_reject("oversized_ws_packet")
					continue
				var raw_str: String = pkt.get_string_from_utf8()
				ingest_raw_json(raw_str)

		WebSocketPeer.STATE_CONNECTING:
			pass

		WebSocketPeer.STATE_CLOSING:
			pass

		WebSocketPeer.STATE_CLOSED:
			if is_ws_connected or _connect_in_progress:
				is_ws_connected = false
				_connect_in_progress = false
				ws_status_text = "RECONECTANDO (%.0fs)..." % reconnect_delay
				connection_state_changed.emit(false, ws_status_text)
				reconnect_timer = reconnect_delay
				reconnect_delay = minf(reconnect_delay * 2.0, MAX_RECONNECT_DELAY)
			else:
				reconnect_timer = maxf(0.0, reconnect_timer - delta)
				if reconnect_timer <= 0.0:
					_attempt_ws_connect()


func _attempt_ws_connect() -> void:
	if not is_loopback_ws_url(ws_url):
		_reject("non_loopback_ws_url_forbidden")
		auto_connect = false
		return
	if _ws_peer == null:
		_ws_peer = WebSocketPeer.new()
	_ws_peer.inbound_buffer_size = 65536
	_ws_peer.handshake_headers = _handshake_headers()
	var err: Error = _ws_peer.connect_to_url(ws_url)
	if err == OK:
		_connect_in_progress = true
	else:
		_connect_in_progress = false
		reconnect_timer = reconnect_delay
		reconnect_delay = minf(reconnect_delay * 2.0, MAX_RECONNECT_DELAY)


func reset_deduplication() -> void:
	_seen_event_order.clear()
	_seen_event_lookup.clear()
	accepted_count = 0
	rejected_count = 0
	duplicate_count = 0


func sanitize_display_name(raw_name: String) -> String:
	var stage: String = raw_name
	if _bbcode_regex == null:
		_bbcode_regex = RegEx.new()
		_bbcode_regex.compile("\\[/?[a-zA-Z0-9_=#:.,\\s-]*\\]")
	stage = _bbcode_regex.sub(stage, "", true)

	var out_chars: PackedStringArray = PackedStringArray()
	for i: int in range(stage.length()):
		var code: int = stage.unicode_at(i)
		# Strip C0/C1 control chars
		if code <= 0x001F or (code >= 0x007F and code <= 0x009F):
			if code == 0x0009 or code == 0x000A or code == 0x000D:
				out_chars.append(" ")
			continue
		# Strip Zero-Width, BOM, and Bidi/RTL Override characters ([ALTO-02])
		if code == 0x061C or (code >= 0x200B and code <= 0x200F) or (code >= 0x202A and code <= 0x202E) or (code >= 0x2060 and code <= 0x2069) or code == 0xFEFF:
			continue
		# Strip remaining brackets and angle brackets
		if code == 0x005B or code == 0x005D or code == 0x003C or code == 0x003E:
			continue
		out_chars.append(String.chr(code))

	var cleaned: String = "".join(out_chars).strip_edges()
	while cleaned.contains("  "):
		cleaned = cleaned.replace("  ", " ")
	if cleaned.is_empty():
		return "Espectador"
	if cleaned.length() > MAX_DISPLAY_NAME_LEN:
		cleaned = cleaned.substr(0, MAX_DISPLAY_NAME_LEN).strip_edges()
	return cleaned if not cleaned.is_empty() else "Espectador"


func ingest_raw_json(raw_text: String) -> bool:
	var trimmed: String = raw_text.strip_edges()
	if trimmed.is_empty() or trimmed.length() > MAX_PACKET_BYTES:
		_reject("empty_or_oversized_json")
		return false

	if not trimmed.begins_with("{") or not trimmed.ends_with("}"):
		_reject("invalid_json_envelope")
		return false

	var json_parser: JSON = JSON.new()
	var parse_err: Error = json_parser.parse(trimmed)
	if parse_err != OK or typeof(json_parser.data) != TYPE_DICTIONARY:
		_reject("invalid_json_envelope")
		return false

	var envelope: Dictionary = json_parser.data as Dictionary
	return ingest_envelope(envelope)


func _valid_live_goals_payload(raw_goals: Variant) -> bool:
	if not raw_goals is Dictionary:
		return false
	var goals: Dictionary = raw_goals as Dictionary
	if goals.size() != 3:
		return false
	for slot: String in ["likes", "gifts", "follows"]:
		if not goals.get(slot) is Dictionary:
			return false
		var spec: Dictionary = goals[slot] as Dictionary
		var kind: String = str(spec.get("goal_kind", ""))
		if slot == "likes" and kind != "likes":
			return false
		if slot == "follows" and kind != "follows":
			return false
		if slot == "gifts" and not (kind in ["gifts", "coins", "gift_specific"]):
			return false
		if not spec.get("goal_label") is String:
			return false
		var label_str: String = String(spec["goal_label"]).strip_edges()
		if label_str.is_empty() or label_str.length() > 40:
			return false
		var target_var: Variant = spec.get("goal_target", null)
		if not typeof(target_var) in [TYPE_INT, TYPE_FLOAT]:
			return false
		var target_f: float = float(target_var)
		if not is_finite(target_f) or target_f < 1.0 or target_f > 1000000000.0 or target_f != floorf(target_f):
			return false
		if slot == "gifts" and kind == "gift_specific" and not _valid_gift_identifier(spec.get("goal_gift_id")):
			return false
		if slot == "follows" and spec.has("follower_baseline") and spec["follower_baseline"] != null:
			var base_var: Variant = spec["follower_baseline"]
			if not typeof(base_var) in [TYPE_INT, TYPE_FLOAT]:
				return false
			var base_f: float = float(base_var)
			if not is_finite(base_f) or base_f < 0.0 or base_f > 1000000000.0 or base_f != floorf(base_f):
				return false
	return true


func ingest_envelope(envelope: Dictionary) -> bool:
	# 1. Validate schema_version ([MEDIO-01] strict string check)
	var schema_var: Variant = envelope.get("schema_version", null)
	if typeof(schema_var) != TYPE_STRING or String(schema_var) != SUPPORTED_SCHEMA_VERSION:
		_reject("unsupported_schema_version")
		return false

	# 2. Validate event_id (8..128 chars)
	var event_id_var: Variant = envelope.get("event_id", null)
	if typeof(event_id_var) != TYPE_STRING:
		_reject("missing_or_invalid_event_id")
		return false
	var event_id: String = String(event_id_var).strip_edges()
	if event_id.length() < 8 or event_id.length() > 128:
		_reject("invalid_event_id_length")
		return false

	# 3. Validate source
	var source_var: Variant = envelope.get("source", null)
	if typeof(source_var) != TYPE_STRING:
		_reject("invalid_source_type")
		return false
	var source: String = String(source_var).strip_edges()
	if not VALID_SOURCES.has(source):
		_reject("invalid_source")
		return false
	if source in ["tiktok", "kwai"] and session_platform in ["tiktok", "kwai"] and source != session_platform:
		_reject("platform_mismatch")
		return false

	# 4. Validate event_type
	var event_type_var: Variant = envelope.get("event_type", null)
	if typeof(event_type_var) != TYPE_STRING:
		_reject("invalid_event_type")
		return false
	var event_type: String = String(event_type_var).strip_edges()
	if not VALID_EVENT_TYPES.has(event_type):
		_reject("invalid_event_type")
		return false

	# [ALTO-01] Restrict admin_command to source == "admin"
	if event_type == "admin_command" and source != "admin":
		_reject("unauthorized_admin_source")
		return false

	# 5. Validate user dictionary
	var user_var: Variant = envelope.get("user", null)
	if typeof(user_var) != TYPE_DICTIONARY:
		_reject("missing_user_dictionary")
		return false
	var user_dict: Dictionary = user_var as Dictionary
	var uid_var: Variant = user_dict.get("user_id", null)
	var dname_var: Variant = user_dict.get("display_name", null)
	if typeof(uid_var) != TYPE_STRING or typeof(dname_var) != TYPE_STRING:
		_reject("invalid_user_field_types")
		return false
	var user_id: String = String(uid_var).strip_edges()
	var raw_display_name: String = String(dname_var)
	if user_id.is_empty() or user_id.length() > 64 or raw_display_name.strip_edges().is_empty():
		_reject("missing_user_fields")
		return false
	var safe_display_name: String = sanitize_display_name(raw_display_name)

	# 6. Validate payload dictionary
	var payload_var: Variant = envelope.get("payload", null)
	if typeof(payload_var) != TYPE_DICTIONARY:
		_reject("missing_payload_dictionary")
		return false
	var payload: Dictionary = payload_var as Dictionary
	if payload.has("gift_id") and not _valid_gift_identifier(payload["gift_id"]):
		_reject("invalid_gift_id")
		return false
	for numeric_key: String in ["boost_amount", "boost_duration", "shield_duration", "coin_value", "repeat_count", "like_count", "goal_target"]:
		if payload.has(numeric_key):
			var numeric_value: Variant = payload[numeric_key]
			if not typeof(numeric_value) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(numeric_value)) or float(numeric_value) < 0.0:
				_reject("invalid_numeric_payload")
				return false

	# Validate candidate_slot for candidate-targeted events
	var candidate_slot: int = 0
	var requires_slot: bool = event_type == "vote"
	if requires_slot or (payload.has("candidate_slot") and payload.get("candidate_slot") != null):
		var slot_var: Variant = payload.get("candidate_slot", null)
		if typeof(slot_var) == TYPE_INT:
			candidate_slot = int(slot_var)
		elif typeof(slot_var) == TYPE_FLOAT:
			var slot_f: float = float(slot_var)
			if is_nan(slot_f) or is_inf(slot_f) or not is_equal_approx(slot_f, roundf(slot_f)):
				_reject("fractional_or_invalid_candidate_slot")
				return false
			candidate_slot = int(roundf(slot_f))
		else:
			_reject("invalid_candidate_slot_type")
			return false
		var min_slot: int = 1 if requires_slot else 0
		if candidate_slot < min_slot or candidate_slot > 2:
			_reject("candidate_slot_out_of_range")
			return false

	if event_type == "admin_command":
		var cmd_check: String = String(payload.get("command", payload.get("action_id", ""))).strip_edges().to_lower()
		if cmd_check == "admin_restart":
			cmd_check = "restart_race"
		var is_valid_cmd: bool = VALID_ADMIN_COMMANDS.has(cmd_check)
		if not is_valid_cmd:
			for prefix: String in ["boost", "turbo", "shield"]:
				if cmd_check.begins_with(prefix):
					is_valid_cmd = true
					break
		if not is_valid_cmd:
			_reject("invalid_admin_command")
			return false
		if cmd_check == "set_audio_settings":
			for key: String in ["voices_enabled", "sfx_enabled", "crowd_enabled", "memes_enabled"]:
				if typeof(payload.get(key)) != TYPE_BOOL:
					_reject("invalid_audio_settings")
					return false
		if cmd_check == "set_live_goal":
			if not payload.get("goal_kind") in ["likes", "follows", "gifts", "coins", "gift_specific"] or not payload.get("goal_label") is String:
				_reject("invalid_live_goal")
				return false
			var label_text: String = String(payload["goal_label"]).strip_edges()
			if label_text.is_empty() or label_text.length() > 40:
				_reject("invalid_live_goal_label")
				return false
			var goal_target: float = float(payload.get("goal_target", 0.0))
			if goal_target < 1.0 or goal_target > 1000000000.0 or goal_target != floorf(goal_target):
				_reject("invalid_live_goal_target")
				return false
			if payload.get("goal_kind") == "gift_specific" and not _valid_gift_identifier(payload.get("goal_gift_id")):
				_reject("invalid_goal_gift_id")
				return false
		if cmd_check == "set_live_goals":
			if not _valid_live_goals_payload(payload.get("live_goals")):
				_reject("invalid_live_goals")
				return false
	if source == "simulator" and runtime_mode != "development":
		_reject("simulator_forbidden_in_production")
		return false

	# 7. Idempotent Deduplication (FIFO/LRU up to 2000 IDs)
	var sanitized_user: Dictionary = user_dict.duplicate()
	sanitized_user["user_id"] = user_id
	sanitized_user["display_name"] = safe_display_name
	var clean_envelope: Dictionary = envelope.duplicate()
	clean_envelope["event_id"] = event_id
	clean_envelope["user"] = sanitized_user
	if _seen_event_lookup.has(event_id):
		duplicate_count += 1
		duplicate_ignored.emit(event_id)
		if event_type == "gift":
			send_packet({"type": "event_ack", "event_id": event_id})
		elif event_type == "admin_command" and _command_results.has(event_id):
			send_packet(_command_results[event_id] as Dictionary)
		return false
	if event_type == "gift" and gift_commit_hook.is_valid() and not bool(gift_commit_hook.call(clean_envelope)):
		_reject("gift_journal_unavailable")
		return false

	_record_event_id(event_id)
	accepted_count += 1

	var previous_type: String = current_event_type
	var previous_payload: Dictionary = current_event_payload
	current_event_type = event_type
	current_event_payload = payload
	live_event_accepted.emit(clean_envelope)
	if event_type == "admin_command":
		_execute_admin_command(event_id, payload)
	elif not effects_suspended:
		_dispatch_typed_signals(event_type, candidate_slot, safe_display_name, payload)
	current_event_type = previous_type
	current_event_payload = previous_payload
	if event_type == "gift":
		send_packet({"type": "event_ack", "event_id": event_id})
	return true


func _execute_admin_command(event_id: String, payload: Dictionary) -> void:
	var command: String = String(payload.get("command", payload.get("action_id", ""))).strip_edges().to_lower()
	if command == "admin_restart":
		command = "restart_race"
	var result: Dictionary = {"applied": false, "message": "engine_not_ready"}
	if admin_command_executor.is_valid():
		var outcome: Variant = admin_command_executor.call(command, payload)
		if outcome is Dictionary:
			result = outcome as Dictionary
	last_command_result = {"type": "command_result", "event_id": event_id, "command": command,
		"status": "applied" if bool(result.get("applied", false)) else "rejected",
		"message": String(result.get("message", "")).substr(0, 96)}
	_command_results[event_id] = last_command_result.duplicate()
	while _command_results.size() > MAX_DEDUP_CACHE_SIZE:
		_command_results.erase(_command_results.keys()[0])
	admin_command_requested.emit(command, payload)
	send_packet(last_command_result)


func _resolve_gift_tier_number(payload: Dictionary) -> int:
	if payload.has("gift_tier") and typeof(payload.get("gift_tier")) == TYPE_STRING:
		var tier_str: String = String(payload.get("gift_tier")).strip_edges().to_upper()
		if tier_str.begins_with("T") and tier_str.length() >= 2:
			return clampi(int(tier_str.substr(1)), 1, 5)
	return clampi(int(payload.get("tier", 1)), 1, 5)


func _valid_gift_identifier(value: Variant) -> bool:
	if not value is String or String(value).is_empty() or String(value).length() > 64:
		return false
	for index: int in range(String(value).length()):
		var code: int = String(value).unicode_at(index)
		if code < 33 or code in [60, 62, 91, 93, 127, 8206, 8207, 8234, 8235, 8236, 8237, 8238, 8294, 8295, 8296, 8297]:
			return false
	return true


func _dispatch_typed_signals(
	event_type: String,
	candidate_slot: int,
	voter_name: String,
	payload: Dictionary
) -> void:
	match event_type:
		"vote":
			var weight: int = clampi(int(payload.get("vote_weight", payload.get("repeat_count", payload.get("count", 1)))), 1, 100)
			candidate_vote_registered.emit(candidate_slot, weight, voter_name)
			var boost_amt: float = clampf(float(payload.get("boost_amount", 1.1)), 0.0, 1.5)
			var boost_dur: float = clampf(float(payload.get("boost_duration", payload.get("duration", 1.0))), .3, 1.5)
			if boost_amt > 0.0:
				candidate_boost_requested.emit(candidate_slot, boost_amt, boost_dur, voter_name, "TORCIDA %s" % ("13" if candidate_slot == 1 else "22"))

		"gift":
			if candidate_slot == 0:
				return # Agradecimento/ranking aceitos; equipe ainda não escolhida.
			if payload.has("coin_value") and float(payload["coin_value"]) <= 0.0:
				return # Preço desconhecido: agradecer sem inventar efeito pago.
			var tier: int = _resolve_gift_tier_number(payload)
			var action_id: String = String(payload.get("action_id", ""))
			var gift_name: String = sanitize_display_name(String(payload.get("gift_name", "Presente T%d" % tier)))
			if tier == 3 or action_id == "gift_t3_attack" or action_id == "admin_attack":
				var target_slot: int = clampi(int(payload.get("target_slot", 2 if candidate_slot == 1 else 1)), 1, 2)
				var obs_type: String = String(payload.get("obstacle_type", "pilha_documentos"))
				candidate_attack_requested.emit(target_slot, obs_type, voter_name)
				var boost_amt: float = clampf(float(payload.get("boost_amount", 1.5)), 0.0, 24.0)
				var boost_dur: float = clampf(float(payload.get("boost_duration", 2.0)), .5, 10.0)
				if boost_amt > 0.0:
					candidate_boost_requested.emit(candidate_slot, boost_amt, boost_dur, voter_name, "ATAQUE: " + gift_name)
			else:
				var default_boost: float = 4.5 + float(tier) * 2.0
				var default_dur: float = 3.5 + float(tier) * 0.8
				var boost_amt: float = clampf(float(payload.get("boost_amount", default_boost)), 0.0, 24.0)
				var boost_dur: float = clampf(float(payload.get("boost_duration", payload.get("duration", default_dur))), 0.5, 12.0)
				candidate_boost_requested.emit(candidate_slot, boost_amt, boost_dur, voter_name, gift_name)
				if tier in [2, 4] or action_id in ["gift_t2_shield", "gift_t4_super_rally", "admin_shield"] or bool(payload.get("grant_shield", false)):
					var shield_dur: float = clampf(float(payload.get("shield_duration", maxf(boost_dur, 5.0))), 1.0, 15.0)
					candidate_shield_requested.emit(candidate_slot, shield_dur, voter_name)

		"like_batch":
			if candidate_slot == 0:
				return
			var like_count: int = clampi(int(payload.get("like_count", payload.get("count", payload.get("likes", 10)))), 1, 50000)
			var boost_amt: float = clampf(float(payload.get("boost_amount", 2.2 + float(mini(like_count, 100)) * 0.04)), 0.5, 12.0)
			var boost_dur: float = clampf(float(payload.get("boost_duration", payload.get("duration", 3.0))), 0.5, 8.0)
			var target_slot: int = candidate_slot
			candidate_boost_requested.emit(target_slot, boost_amt, boost_dur, voter_name, "CURTIDAS x%d" % like_count)

		"share":
			if candidate_slot == 0:
				return
			var boost_amt: float = clampf(float(payload.get("boost_amount", 4.0)), 1.0, 15.0)
			var boost_dur: float = clampf(float(payload.get("boost_duration", payload.get("duration", 3.2))), 0.5, 8.0)
			var target_slot: int = candidate_slot
			candidate_boost_requested.emit(target_slot, boost_amt, boost_dur, voter_name, "SHARE BOOST")

		"admin_command":
			var cmd: String = String(payload.get("command", payload.get("action_id", ""))).strip_edges().to_lower()
			if cmd == "admin_restart":
				cmd = "restart_race"
			if cmd in ["attack", "spawn_obstacle", "candidate_attack"]:
				var target_slot: int = clampi(int(payload.get("target_slot", 2 if candidate_slot == 1 else 1)), 1, 2)
				var obs_type: String = String(payload.get("obstacle_type", "pilha_documentos"))
				candidate_attack_requested.emit(target_slot, obs_type, "ADMIN")
			admin_command_requested.emit(cmd, payload)


func _record_event_id(event_id: String) -> void:
	_seen_event_lookup[event_id] = true
	_seen_event_order.append(event_id)
	while _seen_event_order.size() > MAX_DEDUP_CACHE_SIZE:
		var oldest_id: String = _seen_event_order.pop_front()
		_seen_event_lookup.erase(oldest_id)


func export_dedup_state() -> Array[String]:
	return _seen_event_order.duplicate()


func import_dedup_state(ids: Array) -> void:
	reset_deduplication()
	for raw_id: Variant in ids.slice(maxi(0, ids.size() - MAX_DEDUP_CACHE_SIZE)):
		if raw_id is String and String(raw_id).length() >= 8 and String(raw_id).length() <= 128:
			_record_event_id(String(raw_id))


func _reject(reason: String) -> void:
	rejected_count += 1
	event_rejected.emit(reason)
