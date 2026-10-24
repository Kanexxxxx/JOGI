extends SceneTree

class FailingJournalStore:
	extends RaceSessionStore
	func append_gift(_envelope: Dictionary) -> bool:
		last_error = "test_write_failure"
		return false

var _ran: bool = false
var _test_bases: Array[String] = []
var _run_id: String = ""


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run_id = "race_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var passed: bool = _test_restore_and_replay() and _test_bad_checkpoint() and _test_commit_failure() and _test_goal_legacy()
	_cleanup()
	print("TEST_RACE_PERSISTENCE_PASSED" if passed else "TEST_RACE_PERSISTENCE_FAILED")
	quit(0 if passed else 1)
	return true


func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("FAIL: ", message)
	return condition


func _base(label: String) -> String:
	var path: String = RaceSessionStore.TEST_DIRECTORY_PREFIX + _run_id + "_" + label
	_test_bases.append(path)
	return path


func _new_context(store: RaceSessionStore) -> Dictionary:
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
	var initialized: bool = persistence.setup(race, audience, bus, "local", store)
	return {"bus": bus, "race": race, "audience": audience, "persistence": persistence, "initialized": initialized}


func _destroy(context: Dictionary) -> void:
	# Simulate a process interruption: suppress the graceful shutdown checkpoint.
	var persistence: RacePersistence = context["persistence"] as RacePersistence
	persistence.is_ready = false
	(context["bus"] as LiveEventBusInstance).gift_commit_hook = Callable()
	for key: String in ["persistence", "audience", "race", "bus"]:
		var node: Node = context[key] as Node
		root.remove_child(node)
		node.free()


func _gift(event_id: String, coins: int = 14, team: int = 1) -> Dictionary:
	return {"schema_version": "1.0", "event_id": event_id, "source": "simulator",
		"event_type": "gift", "timestamp_ms": 1000, "priority": "P0",
		"user": {"user_id": "ana", "display_name": "Ana"},
		"payload": {"candidate_slot": team, "coin_value": coins, "repeat_count": 2,
			"gift_tier": "T1", "gift_name": "Presente", "action_id": "gift_t1_turbo",
			"boost_amount": 4.0, "boost_duration": 3.0}}


func _test_restore_and_replay() -> bool:
	var base: String = _base("restore")
	var store: RaceSessionStore = RaceSessionStore.new("local", base)
	var context: Dictionary = _new_context(store)
	if not bool(context["initialized"]):
		printerr("SETUP_ERROR: ", (context["persistence"] as RacePersistence).last_error)
		_destroy(context)
		return _check(false, "Primeiro setup deve gravar checkpoint inicial")
	var race: RaceMain = context["race"] as RaceMain
	var bus: LiveEventBusInstance = context["bus"] as LiveEventBusInstance
	var persistence: RacePersistence = context["persistence"] as RacePersistence
	race.current_round = 7
	race.cycle_number = 2
	race.cycle_wins.assign([3, 2])
	race.live_goal = {"goal_kind": "follows", "goal_target": 1234, "goal_label": "Novos seguidores"}
	race.start_race_immediately()
	race.match_time_remaining = 345.0
	race.race_elapsed_time = 255.0
	race.runners[0].global_position.z = -168.0
	race.runners[1].global_position.z = -171.0
	for runner: CandidateRunner in race.runners:
		runner._update_progress()
	race.runners[0].lobby_votes = 3
	race.runners[1].apply_shield(8.0)
	var first: Dictionary = _gift("recovery_gift_0001")
	var second: Dictionary = _gift("recovery_gift_0002", 21, 2)
	var first_accepted: bool = bus.ingest_envelope(first)
	var obstacle: Area3D = race.spawn_political_obstacle(2, "pilha_documentos", "Ana")
	obstacle.global_position.z = race.runners[1].global_position.z - 9.0
	race.set_race_paused(true)
	var saved: bool = persistence.flush_snapshot()
	var saved_cursor: int = int(store.load_snapshot().get("journal_cursor", -1))
	var second_accepted: bool = bus.ingest_envelope(second)
	_destroy(context)
	context = _new_context(RaceSessionStore.new("local", base))
	race = context["race"] as RaceMain
	bus = context["bus"] as LiveEventBusInstance
	persistence = context["persistence"] as RacePersistence
	var audience: AudienceDirector = context["audience"] as AudienceDirector
	var bootstrap_ok: bool = bool(context["initialized"]) and persistence.is_ready and persistence.recovered
	var timers_ok: bool = race.current_round == 7 and race.cycle_number == 2 and race.cycle_wins == [3, 2] and race.match_time_remaining == 345.0 and race.race_elapsed_time == 255.0 and race.race_paused
	var goal_ok: bool = race.live_goal == {"goal_kind": "follows", "goal_target": 1234, "goal_label": "Novos seguidores"}
	var runner_state_ok: bool = race.runners[0].progress_m == 168.0 and race.runners[1].progress_m == 171.0 and race.runners[0].boost_count == 1 and race.runners[0].lobby_votes == 3 and race.runners[1].boost_count == 1 and race.runners[1].shield_timer == 8.0
	var money_ok: bool = audience.get_top_supporters().size() == 1 and int(audience.get_top_supporters()[0]["coins"]) == 35
	var count_before_retry: int = race.runners[1].boost_count
	var retry_rejected: bool = not bus.ingest_envelope(second) and race.runners[1].boost_count == count_before_retry and int(audience.get_top_supporters()[0]["coins"]) == 35
	var pending: Array[Node] = race._obstacles_root.get_children()
	var obstacle_ok: bool = pending.size() == 1 and int(pending[0].get_meta("target_slot", 0)) == 2 and is_equal_approx((pending[0] as Area3D).global_position.z - race.runners[1].global_position.z, -9.0)
	var next_store: RaceSessionStore = RaceSessionStore.new("local", base)
	var tail_committed: bool = int(next_store.load_snapshot().get("journal_cursor", -1)) > saved_cursor
	race.match_time_remaining = 340.0
	race.race_elapsed_time = 260.0
	persistence._process(29.9)
	var before_interval: Dictionary = next_store.load_snapshot()
	persistence._process(0.2)
	var after_interval: Dictionary = next_store.load_snapshot()
	var periodic_ok: bool = float(before_interval["match"]["match_time_remaining"]) == 345.0 and float(after_interval["match"]["match_time_remaining"]) == 340.0
	if not bootstrap_ok:
		printerr("RESTORE_ERROR: ", persistence.last_error)
	_destroy(context)
	return _check(first_accepted and saved and second_accepted and bootstrap_ok, "Checkpoint e cauda de presentes devem recuperar após interrupção") and _check(timers_ok and runner_state_ok and goal_ok, "Relógio, pausa, metros, votos, meta e efeitos devem restaurar sem avançar tempooffline ou relançar bônus") and _check(money_ok and retry_rejected and tail_committed, "Presente após checkpoint deve entrar uma vez, guardar novo cursor e recusar reenvio") and _check(obstacle_ok and periodic_ok, "Ataque pendente deve conservar Z relativo e snapshot periódico deve respeitar30segundos")


func _test_goal_legacy() -> bool:
	var base: String = _base("legacygoal")
	var store: RaceSessionStore = RaceSessionStore.new("local", base)
	var context: Dictionary = _new_context(store)
	var state: Dictionary = store.load_snapshot()
	_destroy(context)
	(state["match"] as Dictionary).erase("live_goal")
	store.save_snapshot(state)
	context = _new_context(RaceSessionStore.new("local", base))
	var legacy_ok: bool = bool(context["initialized"]) and (context["race"] as RaceMain).live_goal["goal_target"] == 1000
	_destroy(context)
	state = store.load_snapshot()
	(state["match"] as Dictionary).erase("live_goals")
	state["match"]["live_goal"] = {"goal_kind": "gift_specific", "goal_target": 4321, "goal_label": "Rosas da sessão", "goal_gift_id": "rose_123"}
	store.save_snapshot(state)
	context = _new_context(RaceSessionStore.new("local", base))
	var migrated: RaceMain = context["race"] as RaceMain
	var migration_ok: bool = bool(context["initialized"]) and migrated.live_goals["gifts"]["goal_target"] == 4321 and migrated.live_goals["gifts"]["goal_gift_id"] == "rose_123" and migrated.live_goals["follows"]["goal_target"] == 10000
	_destroy(context)
	state = store.load_snapshot()
	state["match"]["live_goal"]["goal_target"] = 0
	store.save_snapshot(state)
	context = _new_context(RaceSessionStore.new("local", base))
	var invalid_rejected: bool = not bool(context["initialized"]) and (context["race"] as RaceMain).race_paused
	_destroy(context)
	return _check(legacy_ok and migration_ok and invalid_rejected, "Checkpoint legado migra a meta ao slot correto; meta inválida bloqueia recuperação")


func _test_bad_checkpoint() -> bool:
	var base: String = _base("corrupt")
	var store: RaceSessionStore = RaceSessionStore.new("local", base)
	var context: Dictionary = _new_context(store)
	var state: Dictionary = store.load_snapshot()
	_destroy(context)
	state["runners"][0]["progress_m"] = "invalid"
	var saved_corrupt: bool = store.save_snapshot(state)
	var path: String = store.get_storage_directory().path_join("snapshot.json")
	var before_bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	context = _new_context(RaceSessionStore.new("local", base))
	var race: RaceMain = context["race"] as RaceMain
	var persistence: RacePersistence = context["persistence"] as RacePersistence
	var bad_state_rejected: bool = not bool(context["initialized"]) and not persistence.is_ready and persistence.last_error == "invalid_race_snapshot" and race.race_paused and race.current_round == 1 and race.runners[0].progress_m == 0.0
	var preserved: bool = not persistence.flush_snapshot() and before_bytes == FileAccess.get_file_as_bytes(path)
	var blocked_gift: bool = not (context["bus"] as LiveEventBusInstance).ingest_envelope(_gift("blocked_bad_state"))
	_destroy(context)
	# A malformed primary and backup must fail closed without replacing either file.
	_write_test_file(path, "{invalid")
	_write_test_file(path + ".bak", "{also_invalid")
	context = _new_context(RaceSessionStore.new("local", base))
	persistence = context["persistence"] as RacePersistence
	var bad_json_rejected: bool = not bool(context["initialized"]) and persistence.last_error == "load_snapshot_invalid_json" and (context["race"] as RaceMain).race_paused
	var no_overwrite: bool = FileAccess.get_file_as_string(path) == "{invalid" and FileAccess.get_file_as_string(path + ".bak") == "{also_invalid"
	_destroy(context)
	return _check(saved_corrupt and bad_state_rejected and preserved and blocked_gift, "Checkpoint semanticamente inválido deve pausar e bloquear escrita/ACK sem mutação parcial") and _check(bad_json_rejected and no_overwrite, "JSON corrompido deve permanecer preservado para recuperação")


func _test_commit_failure() -> bool:
	var base: String = _base("writefail")
	var store: FailingJournalStore = FailingJournalStore.new("local", base)
	var context: Dictionary = _new_context(store)
	var bus: LiveEventBusInstance = context["bus"] as LiveEventBusInstance
	var audience: AudienceDirector = context["audience"] as AudienceDirector
	var persistence: RacePersistence = context["persistence"] as RacePersistence
	var accepted: bool = bus.ingest_envelope(_gift("journal_writefail"))
	var failed_closed: bool = bool(context["initialized"]) and not accepted and bus.accepted_count == 0 and audience.get_top_supporters().is_empty() and not persistence.is_ready and persistence.last_error == "commit_test_write_failure" and (context["race"] as RaceMain).race_paused
	_destroy(context)
	return _check(failed_closed, "Falha no flush de presente deve impedir aplicação e deixar ACK pendente")


func _write_test_file(path: String, text: String) -> void:
	assert(path.begins_with(RaceSessionStore.TEST_DIRECTORY_PREFIX + _run_id))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _cleanup() -> void:
	for base: String in _test_bases:
		assert(base.begins_with(RaceSessionStore.TEST_DIRECTORY_PREFIX + _run_id))
		var directory: String = base.path_join("local")
		for filename: String in ["snapshot.json", "snapshot.json.tmp", "snapshot.json.bak", "snapshot.json.bak.tmp", "gifts.jsonl"]:
			var path: String = directory.path_join(filename)
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		if DirAccess.dir_exists_absolute(directory):
			DirAccess.remove_absolute(directory)
		if DirAccess.dir_exists_absolute(base):
			DirAccess.remove_absolute(base)
