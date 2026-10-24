class_name RacePersistence
extends Node
## Coordinates a synchronous checkpoint and durable gift journal. One instance per channel.

const STATE_SCHEMA_VERSION: int = 1
const MAX_OBSTACLES: int = 200
const MAX_COUNTER: int = 1000000000
const RUNNER_FLOATS: Dictionary = {
	"progress_m": [0.0, 1000000000.0], "current_speed": [0.0, 500.0],
	"base_speed": [0.1, 200.0], "boost_amount": [0.0, 100.0],
	"boost_timer": [0.0, 3600.0], "shield_timer": [0.0, 3600.0],
	"stumble_timer": [0.0, 3600.0], "grace_timer": [0.0, 3600.0],
	"stumble_penalty_factor": [0.15, 0.85], "finish_time": [0.0, 86400.0],
	"stride_phase": [0.0, 1000000000000.0], "stride_freq": [0.0, 100.0],
	"stride_amp": [0.0, 10.0], "rubber_band_bonus": [-100.0, 100.0],
	"motion_time_scale": [0.0, 10.0]
}
const RUNNER_COUNTERS: Array[String] = ["lobby_votes", "boost_count", "shield_absorbed_count", "stumble_count"]
const RUNNER_BOOLS: Array[String] = ["is_racing", "is_finished"]
const MATCH_FLOATS: Dictionary = {
	"match_duration": [0.1, 86400.0], "track_length": [1.0, 1000000.0],
	"lobby_duration": [0.0, 86400.0], "countdown_duration": [0.0, 86400.0],
	"photo_finish_duration": [0.0, 86400.0], "podium_duration": [0.0, 86400.0],
	"state_timer": [0.0, 86400.0], "countdown_remaining": [0.0, 86400.0],
	"match_time_remaining": [0.0, 86400.0], "race_elapsed_time": [0.0, 86400.0]
}

@export var snapshot_interval: float = 30.0
var is_ready: bool = false
var recovered: bool = false
var last_error: String = ""
var _race: RaceMain = null
var _audience: AudienceDirector = null
var _bus: LiveEventBusInstance = null
var _store: RaceSessionStore = null
var _timer: float = 0.0


func setup(race: RaceMain, audience: AudienceDirector, bus: LiveEventBusInstance, channel: String, store_override: RaceSessionStore = null) -> bool:
	is_ready = false
	recovered = false
	last_error = ""
	_race = race
	_audience = audience
	_bus = bus
	if not _valid_runtime() or not RaceSessionStore.CHANNELS.has(channel):
		return _fail("invalid_persistence_setup")
	_store = store_override if store_override != null else RaceSessionStore.new(channel)
	if _store.get_storage_directory().get_file() != channel:
		return _fail("persistence_channel_mismatch")
	_bus.gift_commit_hook = _deny_gift
	var snapshot: Dictionary = _store.load_snapshot()
	var load_error: String = _store.last_error
	if not load_error.is_empty() and load_error != "snapshot_missing":
		return _fail("load_" + load_error)
	var cursor: int = 0
	if load_error.is_empty():
		if not _validate_snapshot(snapshot):
			return _fail("invalid_race_snapshot")
		cursor = int(snapshot["journal_cursor"])
	else:
		var existing_cursor: int = _store.get_journal_cursor()
		if existing_cursor < 0:
			return _fail("load_" + _store.last_error)
		if existing_cursor > 0:
			# Initial setup always saves a baseline before accepting gifts. A later missing checkpoint
			# with a nonempty historical journal cannot safely be treated as a new race.
			return _fail("checkpoint_missing_with_journal")
	var tail: Array[Dictionary] = _store.load_gifts_since(cursor)
	if not _store.last_error.is_empty():
		return _fail("load_" + _store.last_error)
	if not _valid_replay_tail(tail):
		return _fail("invalid_gift_replay")
	# Setup is synchronous: no race frame or WS poll interleaves validation, restore and replay.
	var was_paused: bool = _race.race_paused
	_race.set_race_paused(true)
	_race.set_meta("restoring_session", true)
	_bus.gift_commit_hook = Callable()
	if load_error.is_empty():
		_apply_snapshot(snapshot)
		was_paused = bool((snapshot["match"] as Dictionary)["race_paused"])
		recovered = true
	var replayed: Dictionary = {}
	for event_id: String in _bus.export_dedup_state():
		replayed[event_id] = true
	var audience_ids: Array = _audience.export_state().get("event_ids", []) as Array
	for identity_value: Variant in audience_ids:
		var identity: String = String(identity_value)
		replayed[identity.substr(identity.find(":") + 1)] = true
	for gift: Dictionary in tail:
		var event_id: String = String(gift["event_id"])
		if replayed.has(event_id):
			continue
		_race.set_meta("replay_reserved_gift", bool(gift.get("_reserved_next_round", false)))
		if not _bus.ingest_envelope(gift):
			_race.set_meta("replay_reserved_gift", false)
			_race.set_meta("restoring_session", false)
			_bus.gift_commit_hook = _deny_gift
			return _fail("gift_replay_rejected")
		_race.set_meta("replay_reserved_gift", false)
		replayed[event_id] = true
	_race.set_meta("restoring_session", false)
	_race.set_race_paused(was_paused)
	_race._update_rankings()
	_race._update_hud()
	_bus.gift_commit_hook = _commit_gift
	is_ready = true
	_timer = 0.0
	# Commit the recovered tail and the first-run baseline before enabling periodic saves.
	return flush_snapshot()


func _process(delta: float) -> void:
	if not is_ready:
		return
	_timer += maxf(0.0, delta)
	if _timer >= clampf(snapshot_interval, 1.0, 300.0):
		_timer = 0.0
		flush_snapshot()


func _exit_tree() -> void:
	if is_ready and _valid_runtime():
		flush_snapshot()
	if is_instance_valid(_bus) and _bus.gift_commit_hook == Callable(self, "_commit_gift"):
		_bus.gift_commit_hook = Callable()


func flush_snapshot() -> bool:
	if not is_ready or not _valid_runtime() or _store == null:
		if last_error.is_empty():
			last_error = "persistence_not_ready"
		return false
	var cursor: int = _store.get_journal_cursor()
	if cursor < 0:
		return _fail("save_" + _store.last_error)
	var state: Dictionary = _capture_snapshot(cursor)
	if state.is_empty() or not _validate_snapshot(state):
		return _fail("invalid_runtime_checkpoint")
	if not _store.save_snapshot(state):
		return _fail("save_" + _store.last_error)
	last_error = ""
	return true


func _commit_gift(envelope: Dictionary) -> bool:
	if not is_ready or _store == null:
		return false
	var committed: Dictionary = envelope.duplicate(true)
	# Local journal context only; external envelopes cannot force deferred mechanics.
	committed["_reserved_next_round"] = _race.current_state in [RaceMain.RaceState.PHOTO_FINISH, RaceMain.RaceState.PODIO]
	if not _store.append_gift(committed):
		return _fail("commit_" + _store.last_error)
	return true


func _deny_gift(_envelope: Dictionary) -> bool:
	return false


func _capture_snapshot(cursor: int) -> Dictionary:
	var match_data: Dictionary = {}
	for field_value: Variant in MATCH_FLOATS:
		var field: String = String(field_value)
		match_data[field] = float(_race.get(field))
	match_data.merge({
		"current_round": _race.current_round, "cycle_number": _race.cycle_number,
		"cycle_wins": _race.cycle_wins.duplicate(), "current_state": int(_race.current_state),
		"round_history": _race.round_history.duplicate(true),
		"race_paused": _race.race_paused, "result_recorded": _race._round_result_recorded,
		"experience_ended": _race.experience_ended,
		"experience_end_reason": _race.experience_end_reason,
		"experience_ended_at": _race.experience_ended_at,
		"recorded_winner_slot": _race._recorded_winner_slot,
		"winner_slot": _race.winner.candidate_id if _race.winner != null else 0,
		"match_events_count": _race.match_events_count,
		"auto_loop_after_podium": _race.auto_loop_after_podium,
		"obstacles_enabled": _race.obstacles_enabled,
		"last_live_event_text": _race.last_live_event_text.substr(0, 512),
		"live_goal": _race.live_goal.duplicate(true),
		"live_goals": _race.live_goals.duplicate(true),
		"audio_settings": _race.audio_settings.duplicate(),
		"pending_round_effects": _race.pending_round_effects.duplicate(true)
	})
	var runners: Array[Dictionary] = []
	for runner: CandidateRunner in _race.runners:
		var state: Dictionary = {
			"candidate_id": runner.candidate_id,
			"start_position": [runner.start_position.x, runner.start_position.y, runner.start_position.z]
		}
		for field_value: Variant in RUNNER_FLOATS:
			var field: String = String(field_value)
			state[field] = float(runner.get(field))
		for field: String in RUNNER_COUNTERS:
			state[field] = int(runner.get(field))
		for field: String in RUNNER_BOOLS:
			state[field] = bool(runner.get(field))
		runners.append(state)
	var obstacles: Array[Dictionary] = []
	for child: Node in _race._obstacles_root.get_children():
		if not child is Area3D or child.is_queued_for_deletion():
			continue
		var area: Area3D = child as Area3D
		var target: int = int(area.get_meta("target_slot", 0))
		var runner: CandidateRunner = _race.get_runner_by_id(target)
		if runner == null:
			return {}
		var relative_z: float = area.global_position.z - runner.global_position.z
		if relative_z > 1.0:
			continue
		obstacles.append({"target_slot": target, "obstacle_type": String(area.get_meta("obstacle_type", "pilha_documentos")), "relative_z": relative_z})
		if obstacles.size() > MAX_OBSTACLES:
			return {}
	return {"schema_version": STATE_SCHEMA_VERSION, "match": match_data, "runners": runners,
		"audience": _audience.export_state(), "bus_event_ids": _bus.export_dedup_state(),
		"obstacles": obstacles, "journal_cursor": cursor}


func _validate_snapshot(state: Dictionary) -> bool:
	if not _integer(state.get("schema_version"), STATE_SCHEMA_VERSION, STATE_SCHEMA_VERSION) or not state.get("match") is Dictionary:
		return false
	if not state.get("runners") is Array or (state["runners"] as Array).size() != 2:
		return false
	if not state.get("audience") is Dictionary or not state.get("bus_event_ids") is Array or not state.get("obstacles") is Array:
		return false
	if not _integer(state.get("journal_cursor"), 0, RaceSessionStore.MAX_JOURNAL_BYTES):
		return false
	var data: Dictionary = state["match"] as Dictionary
	if data.has("round_history"):
		if not data["round_history"] is Array or (data["round_history"] as Array).size() > 50:
			return false
		for result: Variant in data["round_history"] as Array:
			if not result is Dictionary:
				return false
			if not _integer(result.get("cycle"), 1, 1000000000) or not _integer(result.get("round"), 1, 50) or not _integer(result.get("winner_slot"), 0, 2):
				return false
			if not _number(result.get("lula_m"), 0.0, 1000000000000.0) or not _number(result.get("flavio_m"), 0.0, 1000000000000.0):
				return false
	if data.has("experience_ended"):
		if typeof(data["experience_ended"]) != TYPE_BOOL or not data.get("experience_end_reason") is String or not _number(data.get("experience_ended_at"), 0.0, 100000000000.0):
			return false
		if bool(data["experience_ended"]) and (not bool(data.get("race_paused", false)) or bool(data.get("auto_loop_after_podium", true))):
			return false
	if data.has("audio_settings"):
		if not data["audio_settings"] is Dictionary:
			return false
		for key: String in ["voices_enabled", "sfx_enabled", "crowd_enabled", "memes_enabled"]:
			if typeof(data["audio_settings"].get(key)) != TYPE_BOOL:
				return false
	if data.has("pending_round_effects") and not _valid_pending_effects(data["pending_round_effects"]):
		return false
	if data.has("live_goal"):
		if not data["live_goal"] is Dictionary:
			return false
		var goal: Dictionary = data["live_goal"] as Dictionary
		if not goal.get("goal_kind") in ["likes", "follows", "gifts", "coins", "gift_specific"] or not _integer(goal.get("goal_target"), 1, MAX_COUNTER):
			return false
		if goal.get("goal_kind") == "gift_specific" and (not goal.get("goal_gift_id") is String or String(goal["goal_gift_id"]).is_empty() or String(goal["goal_gift_id"]).length() > 64):
			return false
		if not goal.get("goal_label") is String or String(goal["goal_label"]).is_empty() or String(goal["goal_label"]).length() > 40:
			return false
	if data.has("live_goals") and not _valid_live_goals(data["live_goals"]):
		return false
	for field_value: Variant in MATCH_FLOATS:
		var field: String = String(field_value)
		var limits: Array = MATCH_FLOATS[field] as Array
		if not _number(data.get(field), float(limits[0]), float(limits[1])):
			return false
	if float(data["match_time_remaining"]) > float(data["match_duration"]) or float(data["race_elapsed_time"]) > float(data["match_duration"]):
		return false
	if absf(float(data["race_elapsed_time"]) + float(data["match_time_remaining"]) - float(data["match_duration"])) > 0.01:
		return false
	if not _integer(data.get("current_round"), 1, 50) or not _integer(data.get("cycle_number"), 1, MAX_COUNTER) or not _integer(data.get("current_state"), 0, 4):
		return false
	if not _integer(data.get("winner_slot"), 0, 2) or not _integer(data.get("recorded_winner_slot"), 0, 2) or not _integer(data.get("match_events_count"), 0, MAX_COUNTER):
		return false
	for field: String in ["race_paused", "result_recorded", "auto_loop_after_podium", "obstacles_enabled"]:
		if typeof(data.get(field)) != TYPE_BOOL:
			return false
	if not data.get("last_live_event_text") is String or String(data["last_live_event_text"]).length() > 512:
		return false
	if not data.get("cycle_wins") is Array or (data["cycle_wins"] as Array).size() != 2:
		return false
	for wins: Variant in data["cycle_wins"] as Array:
		if not _integer(wins, 0, 50):
			return false
	if int(data["cycle_wins"][0]) + int(data["cycle_wins"][1]) > 50:
		return false
	if int(data["cycle_wins"][0]) + int(data["cycle_wins"][1]) > int(data["current_round"]):
		return false
	var result_recorded: bool = bool(data["result_recorded"])
	if result_recorded != (int(data["current_state"]) >= RaceMain.RaceState.PHOTO_FINISH):
		return false
	if int(data["winner_slot"]) != int(data["recorded_winner_slot"]) or (not result_recorded and int(data["winner_slot"]) != 0):
		return false
	if result_recorded and float(data["match_time_remaining"]) != 0.0:
		return false
	if int(data["winner_slot"]) > 0 and int(data["cycle_wins"][int(data["winner_slot"]) - 1]) < 1:
		return false
	for index: int in range(2):
		if not state["runners"][index] is Dictionary:
			return false
		var runner: Dictionary = state["runners"][index] as Dictionary
		if not _integer(runner.get("candidate_id"), index + 1, index + 1) or not _vector_array(runner.get("start_position")):
			return false
		for field_value: Variant in RUNNER_FLOATS:
			var field: String = String(field_value)
			var limits: Array = RUNNER_FLOATS[field] as Array
			if not _number(runner.get(field), float(limits[0]), float(limits[1])):
				return false
		for field: String in RUNNER_COUNTERS:
			if not _integer(runner.get(field), 0, MAX_COUNTER):
				return false
		for field: String in RUNNER_BOOLS:
			if typeof(runner.get(field)) != TYPE_BOOL:
				return false
		if bool(runner["is_racing"]) != (int(data["current_state"]) == RaceMain.RaceState.RACING) or bool(runner["is_finished"]) != result_recorded:
			return false
	if result_recorded:
		var difference: float = float(state["runners"][0]["progress_m"]) - float(state["runners"][1]["progress_m"])
		var expected_winner: int = 0 if absf(difference) <= RaceMain.DRAW_DISTANCE_METERS + RaceMain.DISTANCE_COMPARISON_EPSILON else (1 if difference > 0.0 else 2)
		if int(data["winner_slot"]) != expected_winner:
			return false
	var ids: Array = state["bus_event_ids"] as Array
	if ids.size() > LiveEventBusInstance.MAX_DEDUP_CACHE_SIZE:
		return false
	var seen: Dictionary = {}
	for value: Variant in ids:
		if not value is String or String(value).length() < 8 or String(value).length() > 128 or seen.has(value):
			return false
		seen[value] = true
	var obstacles: Array = state["obstacles"] as Array
	if obstacles.size() > MAX_OBSTACLES:
		return false
	for value: Variant in obstacles:
		if not value is Dictionary:
			return false
		var obstacle: Dictionary = value as Dictionary
		if not _integer(obstacle.get("target_slot"), 1, 2) or not _number(obstacle.get("relative_z"), -10000.0, 1.0):
			return false
		if not obstacle.get("obstacle_type") is String or String(obstacle["obstacle_type"]).is_empty() or String(obstacle["obstacle_type"]).length() > 32:
			return false
	var probe: AudienceDirector = AudienceDirector.new()
	var audience_valid: bool = probe.import_state(state["audience"] as Dictionary)
	probe.free()
	return audience_valid


func _apply_snapshot(state: Dictionary) -> void:
	var data: Dictionary = state["match"] as Dictionary
	_race.experience_ended = bool(data.get("experience_ended", false))
	_race.experience_end_reason = String(data.get("experience_end_reason", ""))
	_race.experience_ended_at = float(data.get("experience_ended_at", 0.0))
	_bus.effects_suspended = _race.experience_ended
	if data.has("audio_settings"):
		_race.audio_settings = (data["audio_settings"] as Dictionary).duplicate()
	_race.pending_round_effects = (data.get("pending_round_effects", {}) as Dictionary).duplicate(true)
	if data.has("live_goal"):
		_race.live_goal = {"goal_kind": String(data["live_goal"]["goal_kind"]), "goal_target": int(data["live_goal"]["goal_target"]), "goal_label": String(data["live_goal"]["goal_label"])}
		if data["live_goal"].get("goal_kind") == "gift_specific":
			_race.live_goal["goal_gift_id"] = String(data["live_goal"]["goal_gift_id"])
	if data.has("live_goals"):
		_race.live_goals = (data["live_goals"] as Dictionary).duplicate(true)
	else:
		# Migração do checkpoint de meta única, preservando a configuração do operador.
		_race.live_goals = RaceMain.default_live_goals()
		if data.has("live_goal"):
			var kind: String = String(_race.live_goal["goal_kind"])
			var slot: String = "follows" if kind == "follows" else ("likes" if kind == "likes" else "gifts")
			(_race.live_goals[slot] as Dictionary).merge(_race.live_goal, true)
	for field_value: Variant in MATCH_FLOATS:
		var field: String = String(field_value)
		_race.set(field, float(data[field]))
	_race.current_round = int(data["current_round"])
	_race.cycle_number = int(data["cycle_number"])
	_race.cycle_wins.assign([int(data["cycle_wins"][0]), int(data["cycle_wins"][1])])
	_race.round_history.assign(data.get("round_history", []) as Array)
	_race.current_state = int(data["current_state"]) as RaceMain.RaceState
	_race._round_result_recorded = bool(data["result_recorded"])
	_race._recorded_winner_slot = int(data["recorded_winner_slot"])
	_race.winner = _race.get_runner_by_id(int(data["winner_slot"]))
	_race.auto_loop_after_podium = bool(data["auto_loop_after_podium"])
	_race.obstacles_enabled = bool(data["obstacles_enabled"])
	# This signal may reset round presentation, so restore audience counters afterwards.
	_race._select_round_metadata()
	for index: int in range(2):
		var runner: CandidateRunner = _race.runners[index]
		var saved: Dictionary = state["runners"][index] as Dictionary
		var start: Array = saved["start_position"] as Array
		runner.start_position = Vector3(float(start[0]), float(start[1]), float(start[2]))
		runner.start_z = runner.start_position.z
		runner.track_length = _race.track_length
		for field_value: Variant in RUNNER_FLOATS:
			var field: String = String(field_value)
			runner.set(field, float(saved[field]))
		for field: String in RUNNER_COUNTERS:
			runner.set(field, int(saved[field]))
		for field: String in RUNNER_BOOLS:
			runner.set(field, bool(saved[field]))
		runner.global_position = Vector3(runner.start_position.x, runner.start_position.y, runner.start_z - float(saved["progress_m"]))
		runner.velocity = Vector3(0.0, 0.0, -runner.current_speed * runner.motion_time_scale) if runner.is_racing else Vector3.ZERO
		runner._update_progress()
		runner._triggered_obstacles.clear()
		if runner._boost_ring != null:
			runner._boost_ring.visible = runner.boost_timer > 0.0
		if runner._shield_sphere != null:
			runner._shield_sphere.visible = runner.shield_timer > 0.0
	for child: Node in _race._obstacles_root.get_children():
		_race._obstacles_root.remove_child(child)
		child.free()
	for value: Variant in state["obstacles"] as Array:
		var obstacle: Dictionary = value as Dictionary
		var target: int = int(obstacle["target_slot"])
		var area: Area3D = _race.spawn_political_obstacle(target, String(obstacle["obstacle_type"]), "Recuperação")
		if area != null:
			area.global_position.z = _race.get_runner_by_id(target).global_position.z + float(obstacle["relative_z"])
	_race.match_events_count = int(data["match_events_count"])
	_race.last_live_event_text = String(data["last_live_event_text"])
	_audience.import_state(state["audience"] as Dictionary)
	_bus.import_dedup_state(state["bus_event_ids"] as Array)
	_race._reset_track_chunks()
	# Move directly to the saved neighborhood instead of recycling a distant track for many frames.
	var leader_z: float = minf(_race.runners[0].global_position.z, _race.runners[1].global_position.z)
	for chunk: Node3D in _race._track_chunks:
		chunk.position.z += floorf(leader_z / RaceMain.CHUNK_LENGTH) * RaceMain.CHUNK_LENGTH
	if _race.race_camera != null and _race.race_camera.is_physics_processing():
		_race.race_camera.snap_to_targets()


func _valid_replay_tail(tail: Array[Dictionary]) -> bool:
	var validator: LiveEventBusInstance = LiveEventBusInstance.new()
	validator.auto_connect = false
	validator.runtime_mode = _bus.runtime_mode
	validator.session_platform = _bus.session_platform
	var valid: bool = true
	for gift: Dictionary in tail:
		if gift.has("_reserved_next_round") and typeof(gift["_reserved_next_round"]) != TYPE_BOOL:
			valid = false
			break
		validator.reset_deduplication()
		if not validator.ingest_envelope(gift):
			valid = false
			break
	validator.free()
	return valid


func _valid_runtime() -> bool:
	return is_instance_valid(_race) and is_instance_valid(_audience) and is_instance_valid(_bus) and _race.runners.size() == 2 and is_instance_valid(_race._obstacles_root)


func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum


func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, float(minimum), float(maximum)) and float(value) == floorf(float(value))


func _vector_array(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 3:
		return false
	for coordinate: Variant in value as Array:
		if not _number(coordinate, -1000000000.0, 1000000000.0):
			return false
	return true


func _fail(error: String) -> bool:
	last_error = error
	is_ready = false
	if is_instance_valid(_race):
		_race.set_race_paused(true)
	if is_instance_valid(_bus):
		_bus.gift_commit_hook = _deny_gift
	return false


func _valid_pending_effects(value: Variant) -> bool:
	if not value is Dictionary or (value as Dictionary).size() > 2:
		return false
	var pending: Dictionary = value as Dictionary
	for key: Variant in pending:
		if key not in ["1", "2"] or not pending[key] is Dictionary:
			return false
		var item: Dictionary = pending[key] as Dictionary
		if item.size() != 5 or not _number(item.get("boost_amount"), 0.0, 25.0) or not _number(item.get("boost_duration"), 0.0, 10.0):
			return false
		if not _number(item.get("shield_duration"), 0.0, 15.0) or not _integer(item.get("attacks"), 0, 4) or typeof(item.get("super_turbo")) != TYPE_BOOL:
			return false
	return true


func _valid_live_goals(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var goals: Dictionary = value as Dictionary
	for slot: String in ["likes", "gifts", "follows"]:
		if not goals.get(slot) is Dictionary:
			return false
		var item: Dictionary = goals[slot] as Dictionary
		var kind: String = String(item.get("goal_kind", ""))
		if slot == "likes" and kind != "likes":
			return false
		if slot == "gifts" and not kind in ["gifts", "coins", "gift_specific"]:
			return false
		if slot == "follows" and kind != "follows":
			return false
		if not _integer(item.get("goal_target"), 1, MAX_COUNTER):
			return false
		if not item.get("goal_label") is String or String(item["goal_label"]).is_empty() or String(item["goal_label"]).length() > 40:
			return false
		if kind == "gift_specific" and (not item.get("goal_gift_id") is String or String(item["goal_gift_id"]).is_empty() or String(item["goal_gift_id"]).length() > 64):
			return false
		if slot == "follows" and item.has("follower_baseline") and item["follower_baseline"] != null:
			if not _integer(item["follower_baseline"], 0, MAX_COUNTER):
				return false
	return true
