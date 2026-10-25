class_name AudienceDirector
extends Node
## Presentation-only audience state. It never fabricates live events or changes race physics.
## coin_value is the normalized TOTAL of the new combo delta, already multiplied upstream.

signal participation_received(participant: Dictionary)
signal leaderboard_changed(entries: Array[Dictionary])
signal moment_requested(kind: String, team: int, display_name: String)

const MAX_TRACKED_USERS: int = 5000
const MAX_EVENT_IDS: int = 5000
## Session monetary ledger has a separate 100k-donor limit.
const MAX_TRACKED_SUPPORTERS: int = 100000
const MAX_TOP_SUPPORTERS: int = 5
const STATE_SCHEMA_VERSION: int = 1
const MAX_PERSISTED_COUNTER: int = 9007199254740991
const COUNT_KEYS: Array[String] = ["votes", "coins", "likes", "shares", "gifts", "follows"]
const NAME_COOLDOWN_MS: int = 2000
const MAX_NAME_LENGTH: int = 24

## Optional deterministic clock for tests; production uses local monotonic time.
var time_provider: Callable = Callable()
var _bus: LiveEventBusInstance = null
var _users: Dictionary = {}
var _user_order: Array[String] = []
var _supporters: Dictionary = {}
var _top_supporters: Array[Dictionary] = []
var _seen_events: Dictionary = {}
var _event_order: Array[String] = []
var _round_counts: Dictionary = {}
var _session_counts: Dictionary = {}
var _gift_id_counts: Dictionary = {}
const MAX_TRACKED_GIFT_IDS: int = 4096
const MAX_TRANSIENT_AVATARS: int = 256
var _transient_avatars: Dictionary = {}
var _transient_avatar_order: Array[String] = []
var _ranking_limited: bool = false
var _name_tags: RegEx = RegEx.new()
var _gift_icon_regex: RegEx = RegEx.new()


func _init() -> void:
	_name_tags.compile("\\[/?[a-zA-Z0-9_=#:.,\\s-]*\\]")
	_gift_icon_regex.compile("^/gift-icons/[0-9a-f]{64}$")
	_round_counts = _empty_counts()
	_session_counts = _empty_counts()


func setup(bus: LiveEventBusInstance) -> void:
	_disconnect_bus()
	_bus = bus
	if is_instance_valid(_bus) and not _bus.live_event_accepted.is_connected(_on_live_event_accepted):
		_bus.live_event_accepted.connect(_on_live_event_accepted)


func _exit_tree() -> void:
	_disconnect_bus()


func _disconnect_bus() -> void:
	if is_instance_valid(_bus) and _bus.live_event_accepted.is_connected(_on_live_event_accepted):
		_bus.live_event_accepted.disconnect(_on_live_event_accepted)
	_bus = null


func _on_live_event_accepted(envelope: Dictionary) -> void:
	ingest_event(envelope)


func ingest_event(envelope: Dictionary) -> bool:
	if envelope.get("schema_version") != "1.0":
		return false
	if not envelope.get("event_type") is String or not envelope.get("source") is String:
		return false
	var kind: String = String(envelope.get("event_type", ""))
	if not kind in ["vote", "gift", "like_batch", "share", "follow"]:
		return false
	var event_id_value: Variant = envelope.get("event_id")
	var user_value: Variant = envelope.get("user")
	var payload_value: Variant = envelope.get("payload")
	var source: String = String(envelope.get("source", ""))
	if not source in ["tiktok", "kwai", "simulator"]:
		return false
	if not event_id_value is String or String(event_id_value).length() < 8 or String(event_id_value).length() > 128:
		return false
	if not user_value is Dictionary or not payload_value is Dictionary:
		return false
	var user: Dictionary = user_value as Dictionary
	var payload: Dictionary = payload_value as Dictionary
	if not user.get("user_id") is String or not user.get("display_name") is String:
		return false
	var user_id: String = String(user.get("user_id", "")).strip_edges()
	if user_id.is_empty() or user_id.length() > 64:
		return false
	var identity: String = source + ":" + user_id
	var event_id: String = source + ":" + String(event_id_value)
	if _seen_events.has(event_id):
		return false
	var team: int = _strict_integer(payload.get("candidate_slot", 0), 0, 2)
	if team < 0 or (kind == "vote" and team == 0):
		return false
	var amount: int = 1
	var gift_quantity: int = 0
	if kind == "gift":
		# Unknown real prices are represented as zero upstream; acknowledge without inventing coins.
		amount = _strict_integer(payload.get("coin_value", 0), 0, 100000000)
		gift_quantity = _strict_integer(payload.get("repeat_count", 1), 1, 1000)
		if gift_quantity < 1:
			return false
	elif kind == "like_batch":
		amount = _strict_integer(payload.get("like_count", 0), 1, 50000)
	if amount < 0 or (kind != "gift" and amount < 1):
		return false
	_record_event_id(event_id)
	var display_name: String = sanitize_name(String(user.get("display_name", "")))
	var avatar_icon_path: String = _safe_avatar_path(user.get("avatar_icon_path", ""))
	if not avatar_icon_path.is_empty():
		_remember_transient_avatar(identity, avatar_icon_path)
	elif _transient_avatars.has(identity):
		avatar_icon_path = String(_transient_avatars[identity])
	var participant: Dictionary = _get_or_create_user(identity, display_name)
	participant["display_name"] = display_name
	var joined: bool = false
	var switched: bool = false
	if kind == "vote":
		var previous_team: int = int(participant.get("team", 0))
		joined = previous_team == 0
		switched = previous_team > 0 and previous_team != team
		participant["team"] = team
	# A missing target stays neutral. A later vote never reassigns previous gift coins.
	var count_key: String = {"vote": "votes", "gift": "coins", "like_batch": "likes", "share": "shares", "follow": "follows"}[kind]
	_increment_count(_round_counts, count_key, team, amount)
	_increment_count(_session_counts, count_key, team, amount)
	var safe_gift_id: String = ""
	var safe_gift_name: String = ""
	var safe_gift_icon_path: String = ""
	if kind == "gift":
		_increment_count(_round_counts, "gifts", team, gift_quantity)
		_increment_count(_session_counts, "gifts", team, gift_quantity)
		var gift_id: String = String(payload.get("gift_id", "")).strip_edges()
		if not gift_id.is_empty() and gift_id.length() <= 64:
			safe_gift_id = gift_id
			var gift_key: String = source + ":" + gift_id
			if _gift_id_counts.has(gift_key) or _gift_id_counts.size() < MAX_TRACKED_GIFT_IDS:
				_gift_id_counts[gift_key] = int(_gift_id_counts.get(gift_key, 0)) + gift_quantity
		var raw_gift_name: String = String(payload.get("gift_name", "")).strip_edges()
		if not raw_gift_name.is_empty():
			safe_gift_name = sanitize_name(raw_gift_name)
		safe_gift_icon_path = _safe_gift_icon_path(payload.get("gift_icon_path", ""))
	if kind == "gift" and amount > 0:
		_register_gift(identity, display_name, team, amount)
	var now_ms: int = _now_ms()
	var last_shown: int = int(participant.get("last_shown_ms", -NAME_COOLDOWN_MS))
	# Paid acknowledgements cannot disappear because the same person just voted.
	# The presentation layer may combine successive combo deltas into one visible card.
	var emit_moment: bool = kind in ["gift", "follow"] or now_ms - last_shown >= NAME_COOLDOWN_MS
	if emit_moment:
		participant["last_shown_ms"] = now_ms
	var card_payload: Dictionary = {
		"identity": identity,
		"display_name": display_name, "team": team, "kind": kind,
		"amount": amount, "gift_quantity": gift_quantity, "joined": joined, "switched_team": switched,
		"source": source
	}
	if not avatar_icon_path.is_empty():
		card_payload["avatar_icon_path"] = avatar_icon_path
	if not safe_gift_id.is_empty():
		card_payload["gift_id"] = safe_gift_id
	if not safe_gift_name.is_empty():
		card_payload["gift_name"] = safe_gift_name
	if not safe_gift_icon_path.is_empty():
		card_payload["gift_icon_path"] = safe_gift_icon_path
	participation_received.emit(card_payload)
	var moment: String = "join" if kind == "vote" else kind
	if emit_moment:
		moment_requested.emit(moment, team, display_name)
	return true


func get_top_supporters() -> Array[Dictionary]:
	var top: Array[Dictionary] = []
	for cached_entry: Dictionary in _top_supporters:
		var entry: Dictionary = cached_entry.duplicate(true)
		var identity: String = String(entry.get("_identity", ""))
		entry.erase("_identity")
		if not identity.is_empty() and _transient_avatars.has(identity):
			entry["avatar_icon_path"] = String(_transient_avatars[identity])
		top.append(entry)
	return top


func get_snapshot() -> Dictionary:
	var participants_by_team: Array[int] = [0, 0, 0]
	for participant_value: Variant in _users.values():
		var participant: Dictionary = participant_value as Dictionary
		participants_by_team[int(participant.get("team", 0))] += 1
	return {
		"participants": _users.size(), "participants_by_team": participants_by_team,
		"round": _round_counts.duplicate(true), "session": _session_counts.duplicate(true),
		"top_supporters": get_top_supporters(), "ranking_limited": _ranking_limited,
		"participant_capacity": MAX_TRACKED_USERS, "supporter_capacity": MAX_TRACKED_SUPPORTERS,
		"tracked_supporters": _supporters.size(), "retained_event_ids": _seen_events.size()
	}


func get_session_counts() -> Dictionary:
	return _session_counts.duplicate(true)


func get_gift_count(gift_id: String, source: String = "") -> int:
	if not source.is_empty():
		return int(_gift_id_counts.get(source + ":" + gift_id, 0))
	var total: int = 0
	for platform: String in ["tiktok", "kwai", "simulator"]:
		total += int(_gift_id_counts.get(platform + ":" + gift_id, 0))
	return total


func reset_round() -> void:
	# Current choices, donation ranking, cooldowns and replay protection survive round changes.
	_round_counts = _empty_counts()


func reset_session() -> void:
	_users.clear()
	_user_order.clear()
	_supporters.clear()
	_top_supporters.clear()
	_seen_events.clear()
	_event_order.clear()
	_transient_avatars.clear()
	_transient_avatar_order.clear()
	_round_counts = _empty_counts()
	_session_counts = _empty_counts()
	_ranking_limited = false
	_gift_id_counts.clear()
	leaderboard_changed.emit(get_top_supporters())


func export_state() -> Dictionary:
	var users: Dictionary = {}
	var now_ms: int = _now_ms()
	for identity_value: Variant in _users:
		var identity: String = String(identity_value)
		var user: Dictionary = _users[identity] as Dictionary
		users[identity] = {
			"display_name": String(user.get("display_name", "Espectador")),
			"team": int(user.get("team", 0)),
			# A monotonic clock starts over after a process restart. Persist a duration instead.
			"cooldown_remaining_ms": clampi(NAME_COOLDOWN_MS - (now_ms - int(user.get("last_shown_ms", -NAME_COOLDOWN_MS))), 0, NAME_COOLDOWN_MS)
		}
	return {
		"schema_version": STATE_SCHEMA_VERSION, "users": users,
		"user_order": _user_order.duplicate(), "supporters": _supporters.duplicate(true),
		"event_ids": _event_order.duplicate(), "round": _round_counts.duplicate(true),
		"session": _session_counts.duplicate(true), "ranking_limited": _ranking_limited,
		"gift_id_counts": _gift_id_counts.duplicate()
	}


func import_state(state: Dictionary) -> bool:
	# Validate into temporary collections; a corrupt checkpoint cannot partially reset a live session.
	if _strict_integer(state.get("schema_version"), STATE_SCHEMA_VERSION, STATE_SCHEMA_VERSION) < 0:
		return false
	if not state.get("users") is Dictionary or not state.get("supporters") is Dictionary:
		return false
	if not state.get("user_order") is Array or not state.get("event_ids") is Array:
		return false
	if typeof(state.get("ranking_limited")) != TYPE_BOOL:
		return false
	var source_users: Dictionary = state["users"] as Dictionary
	var source_supporters: Dictionary = state["supporters"] as Dictionary
	var source_order: Array = state["user_order"] as Array
	var source_events: Array = state["event_ids"] as Array
	if source_users.size() > MAX_TRACKED_USERS or source_order.size() != source_users.size():
		return false
	if source_supporters.size() > MAX_TRACKED_SUPPORTERS or source_events.size() > MAX_EVENT_IDS:
		return false
	var next_round: Dictionary = _validated_counts(state.get("round"))
	var next_session: Dictionary = _validated_counts(state.get("session"))
	if next_round.is_empty() or next_session.is_empty():
		return false
	var raw_gift_counts: Variant = state.get("gift_id_counts", {})
	if not raw_gift_counts is Dictionary or (raw_gift_counts as Dictionary).size() > MAX_TRACKED_GIFT_IDS:
		return false
	var next_gift_counts: Dictionary = {}
	var tracked_gift_total: int = 0
	for key: Variant in raw_gift_counts as Dictionary:
		if not _valid_persisted_identity(key, 1, 64):
			return false
		var count: int = _strict_integer((raw_gift_counts as Dictionary)[key], 0, MAX_PERSISTED_COUNTER)
		if count < 0 or tracked_gift_total > MAX_PERSISTED_COUNTER - count:
			return false
		next_gift_counts[String(key)] = count
		tracked_gift_total += count
	var session_gifts: int = 0
	for amount: Variant in next_session["gifts"] as Array:
		session_gifts += int(amount)
	if tracked_gift_total > session_gifts:
		return false
	for key: String in COUNT_KEYS:
		for team: int in range(3):
			if int(next_round[key][team]) > int(next_session[key][team]):
				return false
	var next_users: Dictionary = {}
	var next_order: Array[String] = []
	var now_ms: int = _now_ms()
	for identity_value: Variant in source_order:
		if not _valid_persisted_identity(identity_value, 1, 64):
			return false
		var identity: String = String(identity_value)
		if next_users.has(identity) or not source_users.get(identity) is Dictionary:
			return false
		var source_user: Dictionary = source_users[identity] as Dictionary
		if not _valid_persisted_name(source_user.get("display_name")):
			return false
		var team: int = _strict_integer(source_user.get("team"), 0, 2)
		var cooldown: int = _strict_integer(source_user.get("cooldown_remaining_ms"), 0, NAME_COOLDOWN_MS)
		if team < 0 or cooldown < 0:
			return false
		next_users[identity] = {
			"display_name": source_user["display_name"], "team": team,
			"last_shown_ms": now_ms - NAME_COOLDOWN_MS + cooldown
		}
		next_order.append(identity)
	var next_supporters: Dictionary = {}
	var supporter_total: int = 0
	for identity_value: Variant in source_supporters:
		if not _valid_persisted_identity(identity_value, 1, 64):
			return false
		var identity: String = String(identity_value)
		if not source_supporters[identity] is Dictionary:
			return false
		var supporter: Dictionary = source_supporters[identity] as Dictionary
		if not _valid_persisted_name(supporter.get("display_name")):
			return false
		var team: int = _strict_integer(supporter.get("team"), 0, 2)
		var coins: int = _strict_integer(supporter.get("coins"), 1, MAX_PERSISTED_COUNTER)
		if team < 0 or coins < 0 or supporter_total > MAX_PERSISTED_COUNTER - coins:
			return false
		supporter_total += coins
		next_supporters[identity] = {"display_name": supporter["display_name"], "team": team, "coins": coins}
	var session_coin_total: int = 0
	for team: int in range(3):
		session_coin_total += int(next_session["coins"][team])
	if supporter_total > session_coin_total:
		return false
	var next_events: Array[String] = []
	var next_seen: Dictionary = {}
	for event_value: Variant in source_events:
		if not _valid_persisted_identity(event_value, 8, 128):
			return false
		var event_id: String = String(event_value)
		if next_seen.has(event_id):
			return false
		next_events.append(event_id)
		next_seen[event_id] = true
	_users = next_users
	_user_order = next_order
	_supporters = next_supporters
	_event_order = next_events
	_seen_events = next_seen
	_round_counts = next_round
	_session_counts = next_session
	_gift_id_counts = next_gift_counts
	_ranking_limited = bool(state["ranking_limited"])
	_rebuild_top_supporters()
	# Restoring a checkpoint must not replay on-screen thanks, sounds or other acknowledgements.
	return true


func _validated_counts(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var source: Dictionary = value as Dictionary
	for key_value: Variant in source:
		if not key_value is String or not COUNT_KEYS.has(String(key_value)):
			return {}
	var result: Dictionary = {}
	for key: String in COUNT_KEYS:
		# Schema 1 checkpoints created before follows/gift quantities remain valid.
		if key in ["gifts", "follows"] and not source.has(key):
			result[key] = [0, 0, 0]
			continue
		if not source.get(key) is Array or (source[key] as Array).size() != 3:
			return {}
		var counts: Array[int] = []
		for counter: Variant in source[key] as Array:
			var integer: int = _strict_integer(counter, 0, MAX_PERSISTED_COUNTER)
			if integer < 0:
				return {}
			counts.append(integer)
		result[key] = counts
	return result


func _valid_persisted_identity(value: Variant, minimum: int, maximum: int) -> bool:
	if not value is String:
		return false
	var identity: String = String(value)
	var separator: int = identity.find(":")
	if separator < 1 or not identity.substr(0, separator) in ["tiktok", "kwai", "simulator"]:
		return false
	var suffix: String = identity.substr(separator + 1)
	if suffix.length() < minimum or suffix.length() > maximum:
		return false
	for index: int in range(identity.length()):
		var code: int = identity.unicode_at(index)
		if code <= 32 or (code >= 127 and code <= 159):
			return false
	return true


func _valid_persisted_name(value: Variant) -> bool:
	return value is String and not String(value).is_empty() and String(value).length() <= MAX_NAME_LENGTH and sanitize_name(String(value)) == String(value)


func _rebuild_top_supporters() -> void:
	_top_supporters.clear()
	for identity_value: Variant in _supporters:
		var identity: String = String(identity_value)
		var entry: Dictionary = (_supporters[identity] as Dictionary).duplicate(true)
		entry["_identity"] = identity
		_top_supporters.append(entry)
		_top_supporters.sort_custom(_supporter_before)
		if _top_supporters.size() > MAX_TOP_SUPPORTERS:
			_top_supporters.resize(MAX_TOP_SUPPORTERS)


func parse_vote_team_comment(comment: String) -> int:
	# Local simulator helper. Production comments must be normalized by the bridge.
	# Exact commands avoid treating 130, 2022, telephone numbers or mixed 13/22 as votes.
	match comment.strip_edges().to_lower():
		"13", "#13", "1", "#1", "lula":
			return 1
		"22", "#22", "2", "#2", "flávio", "flavio", "flávio bolsonaro", "flavio bolsonaro":
			return 2
	return 0


func sanitize_name(raw_name: String) -> String:
	var stage: String = _name_tags.sub(raw_name, "", true)
	var result: String = ""
	for index: int in range(stage.length()):
		var code: int = stage.unicode_at(index)
		if code in [9, 10, 13]:
			result += " "
		elif code <= 31 or (code >= 127 and code <= 159):
			continue
		elif code == 0x061C or (code >= 0x200B and code <= 0x200F) or (code >= 0x202A and code <= 0x202E) or (code >= 0x2060 and code <= 0x2069) or code == 0xFEFF:
			continue
		elif code in [60, 62, 91, 93]:
			continue
		else:
			result += String.chr(code)
	while result.contains("  "):
		result = result.replace("  ", " ")
	result = result.strip_edges().substr(0, MAX_NAME_LENGTH).strip_edges()
	return "Espectador" if result.is_empty() else result


func _get_or_create_user(identity: String, display_name: String) -> Dictionary:
	if not _users.has(identity):
		while _user_order.size() >= MAX_TRACKED_USERS:
			_users.erase(_user_order.pop_front())
		_users[identity] = {"display_name": display_name, "team": 0, "last_shown_ms": -NAME_COOLDOWN_MS}
		_user_order.append(identity)
	return _users[identity] as Dictionary


func _register_gift(identity: String, display_name: String, team: int, coins: int) -> void:
	var previous_top: Array[Dictionary] = get_top_supporters()
	if not _supporters.has(identity):
		if _supporters.size() >= MAX_TRACKED_SUPPORTERS:
			# Explicitly expose a capacity limit instead of silently discarding old monetary totals.
			_ranking_limited = true
			return
		_supporters[identity] = {"display_name": display_name, "team": team, "coins": 0}
	var supporter: Dictionary = _supporters[identity] as Dictionary
	supporter["display_name"] = display_name
	supporter["team"] = team
	supporter["coins"] = int(supporter.get("coins", 0)) + coins
	# Only the changed supporter can enter the top five because totals only increase.
	# Sorting at most six entries keeps gift processing independent of audience size.
	var contenders: Array[Dictionary] = []
	for existing: Dictionary in _top_supporters:
		if String(existing.get("_identity", "")) != identity:
			contenders.append(existing)
	var updated: Dictionary = supporter.duplicate(true)
	updated["_identity"] = identity
	contenders.append(updated)
	contenders.sort_custom(_supporter_before)
	_top_supporters.clear()
	for index: int in range(mini(MAX_TOP_SUPPORTERS, contenders.size())):
		_top_supporters.append(contenders[index])
	var current_top: Array[Dictionary] = get_top_supporters()
	if previous_top != current_top:
		leaderboard_changed.emit(current_top)


func _supporter_before(a: Dictionary, b: Dictionary) -> bool:
	var a_coins: int = int(a.get("coins", 0))
	var b_coins: int = int(b.get("coins", 0))
	if a_coins != b_coins:
		return a_coins > b_coins
	return String(a.get("_identity", "")) < String(b.get("_identity", ""))


func _record_event_id(event_id: String) -> void:
	_seen_events[event_id] = true
	_event_order.append(event_id)
	while _event_order.size() > MAX_EVENT_IDS:
		_seen_events.erase(_event_order.pop_front())


func _empty_counts() -> Dictionary:
	return {"votes": [0, 0, 0], "coins": [0, 0, 0], "likes": [0, 0, 0], "shares": [0, 0, 0], "gifts": [0, 0, 0], "follows": [0, 0, 0]}


func _increment_count(counts: Dictionary, key: String, team: int, amount: int) -> void:
	var values: Array = counts[key] as Array
	values[team] = int(values[team]) + amount


func _strict_integer(value: Variant, minimum: int, maximum: int) -> int:
	if typeof(value) == TYPE_INT:
		var integer: int = int(value)
		return integer if integer >= minimum and integer <= maximum else -1
	if typeof(value) == TYPE_FLOAT:
		var number: float = float(value)
		if not is_finite(number) or number != floorf(number) or number < minimum or number > maximum:
			return -1
		return int(number)
	return -1


func _now_ms() -> int:
	return int(time_provider.call()) if time_provider.is_valid() else Time.get_ticks_msec()


func _safe_avatar_path(value: Variant) -> String:
	if not value is String:
		return ""
	var candidate: String = String(value).strip_edges()
	return candidate if AvatarVisualCache.is_safe_avatar_path(candidate) else ""


func _safe_gift_icon_path(value: Variant) -> String:
	if not value is String:
		return ""
	var candidate: String = String(value).strip_edges()
	return candidate if _gift_icon_regex.search(candidate) != null else ""


func _remember_transient_avatar(identity: String, avatar_path: String) -> void:
	if _transient_avatars.has(identity):
		_transient_avatar_order.erase(identity)
	else:
		while _transient_avatar_order.size() >= MAX_TRANSIENT_AVATARS:
			var evicted: String = String(_transient_avatar_order.pop_front())
			_transient_avatars.erase(evicted)
	_transient_avatars[identity] = avatar_path
	_transient_avatar_order.append(identity)
