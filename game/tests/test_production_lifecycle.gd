extends SceneTree

var race: RaceMain = null
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _command(bus: LiveEventBusInstance, id: String, command: String, extra: Dictionary = {}) -> void:
	var payload: Dictionary = extra.duplicate()
	payload["command"] = command
	bus.ingest_envelope({"schema_version": "1.0", "source": "admin", "event_type": "admin_command", "event_id": id,
		"user": {"user_id": "operator_test", "display_name": "Operador"}, "payload": payload})


func _new_race() -> RaceMain:
	var instance: RaceMain = (load("res://scenes/main/race_main.tscn") as PackedScene).instantiate() as RaceMain
	root.add_child(instance)
	instance.set_physics_process(false)
	return instance


func _run() -> void:
	_expect(RaceMain.parse_end_datetime("2026-10-26T07:00:00-03:00") == RaceMain.parse_end_datetime("2026-10-26T10:00:00Z"), "Timezone conversion")
	_expect(RaceMain.parse_end_datetime("2026-10-26T07:00:00") < 0.0, "Naive datetime rejected")
	_expect(RaceMain.parse_end_datetime("2026-10-26T07:00:00+14:01") < 0.0, "Invalid offset rejected")
	race = _new_race()
	var bus: LiveEventBusInstance = race.event_bus
	bus.reset_deduplication()
	bus.runtime_mode = "production"
	var simulator: Dictionary = {"schema_version": "1.0", "source": "simulator", "event_id": "production-fake-001", "event_type": "vote",
		"user": {"user_id": "fake", "display_name": "Fake"}, "payload": {"candidate_slot": 1}}
	_expect(not bus.ingest_envelope(simulator), "Production cannot ingest simulator")
	_expect(race.runners[0].lobby_votes == 0, "Rejected simulator does not alter counters")
	bus.session_platform = "tiktok"
	var wrong_platform: Dictionary = simulator.duplicate(true)
	wrong_platform["source"] = "kwai"
	wrong_platform["event_id"] = "wrong-platform-001"
	_expect(not bus.ingest_envelope(wrong_platform), "One platform cannot inject events into the other")
	bus.session_platform = ""
	_command(bus, "production-start-001", "start_race")
	_expect(race.current_state == RaceMain.RaceState.RACING and bus.last_command_result.get("status") == "applied", "Start acknowledged only after state changed")
	_command(bus, "production-attack-001", "attack", {"candidate_slot": 1, "target_slot": 2})
	_expect(race._obstacles_root.get_child_count() == 1, "One admin attack creates exactly one obstacle")
	_command(bus, "production-pause-001", "pause_race")
	_expect(race.race_paused and bus.last_command_result.get("status") == "applied", "Pause acknowledged")
	_command(bus, "production-blocked-boost", "boost", {"candidate_slot": 1})
	_expect(bus.last_command_result.get("status") == "rejected", "Paused boost is not reported applied")
	_command(bus, "production-resume-001", "resume_race")
	_expect(not race.race_paused, "Resume executes")
	var audience: AudienceDirector = AudienceDirector.new()
	race.add_child(audience)
	audience.setup(bus)
	var store: RaceSessionStore = RaceSessionStore.new("local", "user://session-store-tests/production_lifecycle_" + str(Time.get_ticks_usec()))
	var persistence: RacePersistence = RacePersistence.new()
	race.add_child(persistence)
	_expect(persistence.setup(race, audience, bus, "local", store), "Isolated persistence setup")
	race.experience_end_at = 2000.0
	_expect(not race.check_experience_deadline(1999.0), "Before deadline stays running")
	_expect(race.check_experience_deadline(2000.0), "At deadline ends without wall-clock wait")
	_expect(race.experience_ended and race.race_paused and not race.auto_loop_after_podium, "Terminal lifecycle state")
	_expect(persistence.flush_snapshot(), "Terminal checkpoint saved")
	var round_before: int = race.current_round
	_command(bus, "production-restart-after", "restart_race")
	_expect(bus.last_command_result.get("status") == "rejected" and race.current_round == round_before and race.experience_ended, "Restart rejected after close")
	_command(bus, "production-start-after", "start_race")
	_expect(bus.last_command_result.get("status") == "rejected", "Start rejected after close")
	root.remove_child(race)
	race.free()
	race = _new_race()
	var recovered_audience: AudienceDirector = AudienceDirector.new()
	race.add_child(recovered_audience)
	recovered_audience.setup(race.event_bus)
	var recovered: RacePersistence = RacePersistence.new()
	race.add_child(recovered)
	_expect(recovered.setup(race, recovered_audience, race.event_bus, "local", store), "Terminal checkpoint restored")
	_expect(race.experience_ended and race.race_paused and race.get_telemetry_snapshot().get("state_name") == "ENDED", "Process restart remains closed")
	race.restart_race()
	race.start_race_immediately()
	race.set_race_paused(false)
	_expect(race.experience_ended and race.race_paused, "Direct calls cannot reopen terminal checkpoint")
	root.remove_child(race)
	race.free()
	race = null
	await create_timer(.1).timeout
	for failure: String in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("TEST_PRODUCTION_LIFECYCLE_PASSED")
	quit(0 if failures.is_empty() else 1)
