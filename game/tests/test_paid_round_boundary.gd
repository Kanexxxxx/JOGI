extends SceneTree

var _ran: bool = false
var _passed: bool = true
var _base: String = ""

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_base = RaceSessionStore.TEST_DIRECTORY_PREFIX + "boundary_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var context: Dictionary = _new_context()
	var race: RaceMain = context["race"] as RaceMain
	var bus: LiveEventBusInstance = context["bus"] as LiveEventBusInstance
	var persistence: RacePersistence = context["persistence"] as RacePersistence
	race.start_race_immediately()
	_check(persistence.flush_snapshot(), "Save running snapshot before finish")
	race.runners[0].progress_m = 25.0
	race.runners[1].progress_m = 20.0
	race.match_time_remaining = 0.0
	race.race_elapsed_time = race.match_duration
	race._finish_match_by_timer()
	var gift: Dictionary = _gift("boundary_paid_gift_01", "T4")
	_check(bus.ingest_envelope(gift), "Gift accepted during photo finish")
	_check(race.winner == race.runners[0] and race.cycle_wins == [1, 0] and race.runners[0].progress_m == 25.0, "Closed result unchanged")
	_check(race.runners[0].boost_count == 0 and race.runners[0].shield_timer == 0.0, "No mechanics applied to finished runner")
	_check(race.pending_round_effects["1"]["super_turbo"] and race.pending_round_effects["1"]["shield_duration"] > 0.0, "Boost shield and super reserved")
	_check(not bus.ingest_envelope(gift), "Duplicate rejected")
	_check(bus.current_event_type.is_empty() and bus.current_event_payload.is_empty(), "Dispatch context clears after event")
	_check(int((context["audience"] as AudienceDirector).get_top_supporters()[0]["coins"]) == 1000, "Ranking counts coins immediately once")
	_destroy(context)
	# Journal must retain interval context even when latest snapshot predates finish.
	context = _new_context()
	race = context["race"] as RaceMain
	bus = context["bus"] as LiveEventBusInstance
	persistence = context["persistence"] as RacePersistence
	_check(race.current_state == RaceMain.RaceState.RACING and race.runners[0].boost_count == 0, "Crash restores prior race without applying reserved gift early")
	_check(race.pending_round_effects.has("1") and bool(race.pending_round_effects["1"]["super_turbo"]), "Journal replay conserves reservation")
	_check(not bus.ingest_envelope(gift), "Replay remains deduplicated after recovery")
	race.match_time_remaining = 0.0
	race.race_elapsed_time = race.match_duration
	race._finish_match_by_timer()
	race._transition_to_state(RaceMain.RaceState.PODIO)
	for index: int in range(8):
		bus.ingest_envelope(_gift("boundary_attack_%03d" % index, "T3"))
	_check(int(race.pending_round_effects["2"]["attacks"]) == 4, "Attack aggregate bounded")
	_check(float(race.pending_round_effects["1"]["boost_duration"]) <= 10.0, "Boost duration bounded by runner cap")
	_check(persistence.flush_snapshot(), "Pending aggregates saved in podium checkpoint")
	_destroy(context)
	context = _new_context()
	race = context["race"] as RaceMain
	_check(race.current_state == RaceMain.RaceState.PODIO and int(race.pending_round_effects["2"]["attacks"]) == 4, "Checkpoint restores pending effects")
	var before: Dictionary = race.pending_round_effects.duplicate(true)
	race.restart_race()
	_check(race.pending_round_effects == before, "Administrative restart retains paid reservation")
	race.start_race_immediately()
	_check(race.runners[0].boost_timer > 0.0 and race.runners[0].shield_timer > 0.0, "Reserved boost and shield apply at next start")
	_check(race._obstacles_root.get_child_count() == 4 and race.pending_round_effects.is_empty(), "Reserved attacks apply once and aggregate clears")
	var boosts: int = race.runners[0].boost_count
	race._apply_reserved_round_effects()
	_check(race.runners[0].boost_count == boosts and race._obstacles_root.get_child_count() == 4, "Repeated application cannot duplicate effects")
	var forged: Dictionary = _gift("boundary_external_marker_01", "T1")
	forged["_reserved_next_round"] = true
	_check((context["bus"] as LiveEventBusInstance).ingest_envelope(forged) and race.pending_round_effects.is_empty(), "External envelope cannot force internal replay reservation")
	var checkpoint: Dictionary = (context["persistence"] as RacePersistence)._capture_snapshot(0)
	var legacy: Dictionary = checkpoint.duplicate(true)
	legacy["match"].erase("pending_round_effects")
	_check((context["persistence"] as RacePersistence)._validate_snapshot(legacy), "Legacy checkpoint remains compatible")
	checkpoint["match"]["pending_round_effects"] = {"1": {"boost_amount": 26.0, "boost_duration": 10.0, "shield_duration": 0.0, "attacks": 0, "super_turbo": false}}
	_check(not (context["persistence"] as RacePersistence)._validate_snapshot(checkpoint), "Out of bounds persisted aggregate rejected")
	_destroy(context)
	_cleanup()
	print("TEST_PAID_ROUND_BOUNDARY_PASSED" if _passed else "TEST_PAID_ROUND_BOUNDARY_FAILED")
	quit(0 if _passed else 1)
	return true

func _new_context() -> Dictionary:
	var bus: LiveEventBusInstance = LiveEventBusInstance.new()
	bus.auto_connect = false
	root.add_child(bus)
	var packed: PackedScene = load("res://scenes/main/race_main.tscn") as PackedScene
	var race: RaceMain = packed.instantiate() as RaceMain
	root.add_child(race)
	race.bind_event_bus(bus)
	var audience: AudienceDirector = AudienceDirector.new()
	root.add_child(audience)
	audience.setup(bus)
	var persistence: RacePersistence = RacePersistence.new()
	root.add_child(persistence)
	_check(persistence.setup(race, audience, bus, "local", RaceSessionStore.new("local", _base)), "Persistence setup succeeds")
	return {"race": race, "bus": bus, "audience": audience, "persistence": persistence}

func _destroy(context: Dictionary) -> void:
	(context["persistence"] as RacePersistence).is_ready = false
	(context["bus"] as LiveEventBusInstance).gift_commit_hook = Callable()
	for key: String in ["persistence", "audience", "race", "bus"]:
		var node: Node = context[key] as Node
		root.remove_child(node)
		node.free()

func _gift(event_id: String, tier: String) -> Dictionary:
	return {"schema_version": "1.0", "event_id": event_id, "source": "simulator", "event_type": "gift", "user": {"user_id": "ana", "display_name": "Ana"}, "payload": {"candidate_slot": 1, "gift_tier": tier, "coin_value": 1000, "repeat_count": 1, "boost_amount": 20.0, "boost_duration": 8.0}}

func _check(condition: bool, label: String) -> void:
	if not condition:
		_passed = false
		printerr("FAIL: ", label)

func _cleanup() -> void:
	var directory: String = _base.path_join("local")
	for file: String in ["snapshot.json", "snapshot.json.tmp", "snapshot.json.bak", "gifts.jsonl"]:
		var path: String = directory.path_join(file)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(_base)
