extends SceneTree

var _race: RaceMain = null
var _ran_suite: bool = false


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main/race_main.tscn") as PackedScene
	if packed != null:
		_race = packed.instantiate() as RaceMain
		if _race != null:
			root.add_child(_race)


func _process(_delta: float) -> bool:
	if _ran_suite:
		return true
	_ran_suite = true

	var passed: bool = _execute_test_suite()
	_cleanup_race()

	if passed:
		print("TEST_RACE_PROTOTYPE_PASSED")
		quit(0)
	else:
		printerr("TEST_RACE_PROTOTYPE_FAILED")
		quit(1)
	return true


func _execute_test_suite() -> bool:
	if _race == null:
		printerr("Failed to instantiate RaceMain")
		return false

	var bus: LiveEventBusInstance = root.get_node_or_null("LiveEventBus") as LiveEventBusInstance
	if bus == null:
		printerr("LiveEventBus autoload not found at /root/LiveEventBus")
		return false

	bus.reset_deduplication()

	# 1. Verify initial state is LOBBY_VOTACAO and 6 candidates exist
	if _race.current_state != RaceMain.RaceState.LOBBY_VOTACAO:
		printerr("Expected initial state LOBBY_VOTACAO, got: ", _race.current_state)
		return false

	if _race.runners.size() != 2:
		printerr("Expected 2 runners, got: ", _race.runners.size())
		return false

	# 2. Test LiveEventBus validation, sanitization, and deduplication in LOBBY_VOTACAO
	var raw_vote_json: String = JSON.stringify({
		"schema_version": "1.0",
		"event_id": "evt_vote_lobby_001",
		"source": "tiktok",
		"event_type": "vote",
		"user": {
			"user_id": "u_100",
			"display_name": "[b][color=red]SuperTorcedorMuitoLongo123456[/color][/b]"
		},
		"payload": {
			"candidate_slot": 2,
			"vote_weight": 3
		}
	})
	var ok_first: bool = bus.ingest_raw_json(raw_vote_json)
	if not ok_first or bus.accepted_count != 1:
		printerr("First valid vote event should be accepted")
		return false

	var runner_two: CandidateRunner = _race.runners[1]
	if runner_two.lobby_votes != 3:
		printerr("Expected runner #2 lobby_votes == 3, got: ", runner_two.lobby_votes)
		return false

	# Check sanitization of display_name (no '[' or ']', no RTL/zero-width, and max 24 chars)
	var sanitized_check: String = bus.sanitize_display_name("[b]Nome\u202e\u200b\u0007ComBBCodeMuitoLongoDemais12345[/b]")
	if sanitized_check.contains("[") or sanitized_check.contains("]") or sanitized_check.contains("\u202e") or sanitized_check.contains("\u200b") or sanitized_check.length() > 24:
		printerr("Display name sanitization failed: ", sanitized_check)
		return false

	# Duplicate event_id must be ignored idempotently
	var ok_dup: bool = bus.ingest_raw_json(raw_vote_json)
	if ok_dup or bus.duplicate_count != 1 or runner_two.lobby_votes != 3:
		printerr("Duplicate event_id was not properly deduplicated")
		return false

	# Malformed JSON, invalid schema/slot, and spoofed admin_command must be safely rejected
	var ok_bad_json: bool = bus.ingest_raw_json("{malformed_json")
	var ok_bad_slot: bool = bus.ingest_envelope({
		"schema_version": "1.0",
		"event_id": "evt_bad_slot_002",
		"source": "kwai",
		"event_type": "gift",
		"user": {"user_id": "u_2", "display_name": "Tester"},
		"payload": {"candidate_slot": 99}
	})
	var ok_spoof_admin: bool = bus.ingest_envelope({
		"schema_version": "1.0",
		"event_id": "evt_spoof_admin_003",
		"source": "tiktok",
		"event_type": "admin_command",
		"user": {"user_id": "u_3", "display_name": "Spoofer"},
		"payload": {"command": "restart_race"}
	})
	if ok_bad_json or ok_bad_slot or ok_spoof_admin or bus.rejected_count != 3:
		printerr("Malformed JSON, invalid slot, or spoofed admin was not rejected properly, rejected_count=", bus.rejected_count)
		return false

	# 3. Transition LOBBY_VOTACAO -> COUNTDOWN -> RACING
	var step_delta: float = 0.2
	for _i: int in range(35):
		_step_simulation(_race, step_delta)
		if _race.current_state == RaceMain.RaceState.COUNTDOWN:
			break

	if _race.current_state != RaceMain.RaceState.COUNTDOWN:
		printerr("Did not transition from LOBBY_VOTACAO to COUNTDOWN")
		return false

	for _i: int in range(20):
		_step_simulation(_race, step_delta)
		if _race.current_state == RaceMain.RaceState.RACING:
			break

	if _race.current_state != RaceMain.RaceState.RACING:
		printerr("Did not transition from COUNTDOWN to RACING")
		return false

	# 4. Test LiveEventBus gift turbo during RACING and verify speed & progress advantage
	_race.obstacles_enabled = false
	for _i: int in range(5):
		_step_simulation(_race, 0.1)

	var runner_one: CandidateRunner = _race.runners[0]
	runner_two = _race.runners[1]
	var speed_before_gift: float = runner_one.current_speed

	var gift_ok: bool = bus.ingest_envelope({
		"schema_version": "1.0",
		"event_id": "evt_gift_racing_001",
		"source": "tiktok",
		"event_type": "gift",
		"user": {"user_id": "u_vip", "display_name": "DoadorVIP"},
		"payload": {
			"candidate_slot": 1,
			"gift_name": "Foguete",
			"tier": 4,
			"boost_amount": 9.5,
			"duration": 8.0,
			"shield_duration": 8.0
		}
	})
	if not gift_ok or runner_one.current_speed <= speed_before_gift:
		printerr("Gift event did not immediately increase runner #1 speed")
		return false

	for _i: int in range(35):
		_step_simulation(_race, 0.1)

	if runner_one.progress_m <= runner_two.progress_m:
		printerr("Boosted runner #1 did not gain measurable lead over runner #2")
		return false

	# 5. Test Political Obstacle impact: Shield absorption, Stumble speed reduction, and Grace Period immunity
	# Runner #1 has shield from Tier 4 gift -> hitting obstacle or apply_stumble must be absorbed
	var stumbled_with_shield: bool = runner_one.apply_stumble(1.2, 0.38)
	if stumbled_with_shield or runner_one.shield_absorbed_count < 1:
		printerr("Shield did not absorb stumble impact on Runner #1")
		return false

	# Runner #2 has no shield -> spawn political obstacle and verify stumble
	runner_two.shield_timer = 0.0
	runner_two.grace_timer = 0.0
	var obs: Area3D = _race.spawn_political_obstacle(2, "pilha_documentos", "Oponente")
	if obs == null:
		printerr("Failed to spawn political obstacle")
		return false
	runner_two.global_position = obs.global_position
	var stumbled_runner_two: bool = runner_two.apply_stumble(1.2, 0.38)
	if not stumbled_runner_two or runner_two.stumble_timer <= 0.0 or runner_two.grace_timer <= 0.0:
		printerr("Runner #2 did not stumble when hitting obstacle")
		return false
	if runner_two.current_speed >= runner_two.base_speed * 0.65:
		printerr("Runner #2 speed was not reduced during stumble: ", runner_two.current_speed)
		return false

	# Verify post-fall immunity (grace_timer prevents consecutive stumble / stunlock)
	var prev_stumble_count: int = runner_two.stumble_count
	var second_stumble: bool = runner_two.apply_stumble(1.2, 0.38)
	if second_stumble or runner_two.stumble_count != prev_stumble_count:
		printerr("Post-fall grace_timer did not protect Runner #2 from stunlock")
		return false

	# 6. Simulate match timer expiry and verify RACING -> PHOTO_FINISH -> PODIO
	_race.match_time_remaining = 0.02
	_step_simulation(_race, 0.05)

	if _race.current_state != RaceMain.RaceState.PHOTO_FINISH or _race.winner == null:
		printerr("Race did not enter PHOTO_FINISH when timer expired")
		return false

	for _i: int in range(35):
		_step_simulation(_race, 0.1)
		if _race.current_state == RaceMain.RaceState.PODIO:
			break

	if _race.current_state != RaceMain.RaceState.PODIO:
		printerr("Race did not transition from PHOTO_FINISH to PODIO")
		return false

	# 7. Test restart_race(false) -> LOBBY_VOTACAO and restart_race(true) -> COUNTDOWN
	_race.restart_race(false)
	if _race.current_state != RaceMain.RaceState.LOBBY_VOTACAO or _race.winner != null:
		printerr("restart_race(false) did not reset to LOBBY_VOTACAO")
		return false

	for runner: CandidateRunner in _race.runners:
		if not is_zero_approx(runner.progress_m) or runner.is_finished or runner.stumble_count != 0:
			printerr("Runner #%d state not clean after restart_race()" % runner.candidate_id)
			return false

	_race.restart_race(true)
	if _race.current_state != RaceMain.RaceState.COUNTDOWN:
		printerr("restart_race(true) did not reset to COUNTDOWN")
		return false

	return true


func _step_simulation(race: RaceMain, delta: float) -> void:
	race._physics_process(delta)
	for runner: CandidateRunner in race.runners:
		runner._physics_process(delta)
	if race.race_camera != null:
		race.race_camera._physics_process(delta)


func _cleanup_race() -> void:
	if _race != null and is_instance_valid(_race):
		if _race.get_parent() != null:
			_race.get_parent().remove_child(_race)
		_race.free()
		_race = null
