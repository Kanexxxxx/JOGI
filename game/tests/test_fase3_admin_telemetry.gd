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
	_cleanup()

	if passed:
		print("TEST_FASE3_ADMIN_TELEMETRY_PASSED")
		quit(0)
	else:
		printerr("TEST_FASE3_ADMIN_TELEMETRY_FAILED")
		quit(1)
	return true


func _execute_test_suite() -> bool:
	if _race == null:
		printerr("FAIL: RaceMain instance is null")
		return false

	var bus: LiveEventBusInstance = root.get_node_or_null("LiveEventBus") as LiveEventBusInstance
	if bus == null:
		printerr("FAIL: LiveEventBus autoload not found at /root/LiveEventBus")
		return false

	bus.reset_deduplication()

	# 1. Verify initial telemetry snapshot structure and data
	var snap0: Dictionary = _race.get_telemetry_snapshot()
	if snap0.get("type") != "telemetry":
		printerr("FAIL: Expected snapshot type == 'telemetry', got: ", snap0.get("type"))
		return false

	if int(snap0.get("current_state", -1)) != int(RaceMain.RaceState.LOBBY_VOTACAO):
		printerr("FAIL: Expected initial state LOBBY_VOTACAO (0), got: ", snap0.get("current_state"))
		return false

	if String(snap0.get("state_name", "")) != "LOBBY_VOTACAO":
		printerr("FAIL: Expected state_name 'LOBBY_VOTACAO', got: ", snap0.get("state_name"))
		return false

	var runners_list: Array = snap0.get("runners", [])
	if runners_list.size() != 2:
		printerr("FAIL: Expected 2 runners in telemetry snapshot, got: ", runners_list.size())
		return false

	for i: int in range(runners_list.size()):
		var r_data: Dictionary = runners_list[i] as Dictionary
		if int(r_data.get("candidate_id", 0)) != (i + 1):
			printerr("FAIL: Expected candidate_id ", (i + 1), ", got: ", r_data.get("candidate_id"))
			return false
		if not r_data.has("rank") or not r_data.has("progress_m") or not r_data.has("current_speed") or not r_data.has("base_speed"):
			printerr("FAIL: Missing essential speed/progress fields in runner #", (i + 1))
			return false
		if not r_data.has("boost_timer") or not r_data.has("shield_timer") or not r_data.has("stumble_timer"):
			printerr("FAIL: Missing timer fields in runner #", (i + 1))
			return false
		if not r_data.has("has_shield") or not r_data.has("is_boosted") or not r_data.has("is_stumbled"):
			printerr("FAIL: Missing boolean status flags in runner #", (i + 1))
			return false

	# 2. Test send_telemetry and send_packet in disconnected / headless mode (must safely return false, no crash)
	var sent_disconnected: bool = bus.send_telemetry(snap0)
	if sent_disconnected:
		printerr("FAIL: send_telemetry should return false when WebSocket is disconnected")
		return false

	var packet_disconnected: bool = bus.send_packet({"test": 123})
	if packet_disconnected:
		printerr("FAIL: send_packet should return false when WebSocket is disconnected")
		return false

	var race_sent: bool = _race.send_telemetry_now()
	if race_sent:
		printerr("FAIL: _race.send_telemetry_now() should return false when disconnected")
		return false

	# 3. Test admin command: "skip_lobby" -> advances to COUNTDOWN
	var ok_skip: bool = bus.ingest_envelope({
		"schema_version": "1.0",
		"event_id": "evt_adm_test_001_skip",
		"source": "admin",
		"event_type": "admin_command",
		"user": {"user_id": "admin_tester", "display_name": "AdminHost"},
		"payload": {"command": "skip_lobby"}
	})
	if not ok_skip:
		printerr("FAIL: bus.ingest_envelope for skip_lobby failed")
		return false

	if _race.current_state != RaceMain.RaceState.COUNTDOWN:
		printerr("FAIL: Expected state COUNTDOWN after skip_lobby, got: ", _race.current_state)
		return false

	var snap_count: Dictionary = _race.get_telemetry_snapshot()
	if String(snap_count.get("state_name", "")) != "COUNTDOWN" or int(snap_count.get("current_state", -1)) != 1:
		printerr("FAIL: Snapshot does not reflect COUNTDOWN state: ", snap_count)
		return false

	# 4. Test admin command: "start_race" -> advances to RACING
	var ok_start: bool = bus.ingest_envelope({
		"schema_version": "1.0",
		"event_id": "evt_adm_test_002_start",
		"source": "admin",
		"event_type": "admin_command",
		"user": {"user_id": "admin_tester", "display_name": "AdminHost"},
		"payload": {"command": "start_race"}
	})
	if not ok_start:
		printerr("FAIL: bus.ingest_envelope for start_race failed")
		return false

	if _race.current_state != RaceMain.RaceState.RACING:
		printerr("FAIL: Expected state RACING after start_race, got: ", _race.current_state)
		return false

	var snap_race: Dictionary = _race.get_telemetry_snapshot()
	if String(snap_race.get("state_name", "")) != "RACING" or int(snap_race.get("current_state", -1)) != 2:
		printerr("FAIL: Snapshot does not reflect RACING state: ", snap_race)
		return false

	# 5. Test admin command: boost on candidate #3
	var ok_boost: bool = bus.ingest_envelope({
		"schema_version": "1.0",
		"event_id": "evt_adm_test_003_boost",
		"source": "admin",
		"event_type": "admin_command",
		"user": {"user_id": "admin_tester", "display_name": "AdminHost"},
		"payload": {
			"command": "boost",
			"candidate_slot": 2,
			"boost_amount": 7.5,
			"boost_duration": 4.0
		}
	})
	if not ok_boost:
		printerr("FAIL: bus.ingest_envelope for admin boost failed")
		return false

	var r2: CandidateRunner = _race.runners[1]
	if r2.boost_timer <= 0.0 or r2.boost_amount < 7.0:
		printerr("FAIL: Runner #2 boost not applied, boost_timer=", r2.boost_timer, " boost_amount=", r2.boost_amount)
		return false

	var snap_boost: Dictionary = _race.get_telemetry_snapshot()
	var r2_data: Dictionary = (snap_boost.get("runners", []) as Array)[1] as Dictionary
	if not bool(r2_data.get("is_boosted", false)) or float(r2_data.get("boost_timer", 0.0)) <= 0.0:
		printerr("FAIL: Telemetry snapshot does not reflect boosted status for runner #2: ", r2_data)
		return false

	# 6. Test admin command: shield on candidate #2
	var ok_shield: bool = bus.ingest_envelope({
		"schema_version": "1.0",
		"event_id": "evt_adm_test_004_shield",
		"source": "admin",
		"event_type": "admin_command",
		"user": {"user_id": "admin_tester", "display_name": "AdminHost"},
		"payload": {
			"command": "shield",
			"candidate_slot": 2,
			"shield_duration": 5.5
		}
	})
	if not ok_shield:
		printerr("FAIL: bus.ingest_envelope for admin shield failed")
		return false

	if r2.shield_timer <= 0.0:
		printerr("FAIL: Runner #2 shield not applied, shield_timer=", r2.shield_timer)
		return false

	var snap_shield: Dictionary = _race.get_telemetry_snapshot()
	var r2_shield_data: Dictionary = (snap_shield.get("runners", []) as Array)[1] as Dictionary
	if not bool(r2_shield_data.get("has_shield", false)) or float(r2_shield_data.get("shield_timer", 0.0)) <= 0.0:
		printerr("FAIL: Telemetry snapshot does not reflect shield for runner #2: ", r2_shield_data)
		return false

	# 7. Test direct _on_bus_admin_command invocations with string and payload formats
	_race._on_bus_admin_command("boost_1", {"amount": 8.0, "duration": 3.0, "candidate_slot": 1})
	var r1: CandidateRunner = _race.runners[0]
	if r1.boost_timer <= 0.0:
		printerr("FAIL: Direct _on_bus_admin_command('boost_1') failed to apply boost")
		return false

	_race._on_bus_admin_command("shield_1", {"duration": 4.0, "candidate_slot": 1})
	if r1.shield_timer <= 0.0:
		printerr("FAIL: Direct _on_bus_admin_command('shield_1') failed to apply shield")
		return false

	# 8. Test admin command: "restart_race" (or "restart", "reset") -> returns to LOBBY_VOTACAO
	var ok_restart: bool = bus.ingest_envelope({
		"schema_version": "1.0",
		"event_id": "evt_adm_test_005_restart",
		"source": "admin",
		"event_type": "admin_command",
		"user": {"user_id": "admin_tester", "display_name": "AdminHost"},
		"payload": {"command": "restart_race"}
	})
	if not ok_restart:
		printerr("FAIL: bus.ingest_envelope for restart_race failed")
		return false

	if _race.current_state != RaceMain.RaceState.LOBBY_VOTACAO:
		printerr("FAIL: Expected state LOBBY_VOTACAO after restart_race, got: ", _race.current_state)
		return false

	var snap_reset: Dictionary = _race.get_telemetry_snapshot()
	if int(snap_reset.get("current_state", -1)) != 0 or String(snap_reset.get("state_name", "")) != "LOBBY_VOTACAO":
		printerr("FAIL: Snapshot after restart_race is invalid: ", snap_reset)
		return false

	# 9. Test admin command: "reset_dedup"
	if bus.accepted_count <= 0:
		printerr("FAIL: bus.accepted_count should be > 0 before reset_dedup")
		return false

	var ok_reset_dedup: bool = bus.ingest_envelope({
		"schema_version": "1.0",
		"event_id": "evt_adm_test_006_reset_dedup",
		"source": "admin",
		"event_type": "admin_command",
		"user": {"user_id": "admin_tester", "display_name": "AdminHost"},
		"payload": {"command": "reset_dedup"}
	})
	if not ok_reset_dedup:
		printerr("FAIL: bus.ingest_envelope for reset_dedup failed")
		return false

	if bus.accepted_count != 0 or bus.duplicate_count != 0:
		printerr("FAIL: reset_dedup did not clear bus counters: accepted=", bus.accepted_count)
		return false

	# 10. Test periodic physics tick and telemetry update without crash
	for _i: int in range(12):
		_step_sim(0.016)

	return true


func _step_sim(step_dt: float) -> void:
	if _race == null:
		return
	_race._physics_process(step_dt)
	for runner: CandidateRunner in _race.runners:
		runner._physics_process(step_dt)
	if _race.race_camera != null:
		_race.race_camera._physics_process(step_dt)


func _cleanup() -> void:
	if _race != null and is_instance_valid(_race):
		_race.queue_free()
		_race = null
