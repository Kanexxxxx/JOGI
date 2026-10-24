extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _run() -> void:
	var isolated: String = OS.get_environment("GDA_USER_DATA_ROOT").replace("\\", "/").simplify_path().to_lower()
	var actual: String = ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().to_lower()
	if isolated.is_empty() or not actual.begins_with(isolated + "/"):
		printerr("TEST_REQUIRES_PRIVATE_USER_DATA")
		quit(1)
		return
	OS.set_environment("JOGI_MODE", "production")
	OS.set_environment("LIVE_PLATFORM", "local")
	var store: RaceSessionStore = RaceSessionStore.new("local")
	var path: String = store.get_storage_directory().path_join("snapshot.json")
	DirAccess.make_dir_recursive_absolute(store.get_storage_directory())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken checkpoint")
	file.close()
	var race: StadiumRace = (load("res://scenes/main/stadium_race.tscn") as PackedScene).instantiate() as StadiumRace
	root.add_child(race)
	_check(race.persistence != null and not race.persistence.is_ready and race.race_paused, "Corrupt checkpoint must pause production")
	for command: String in ["start_race", "resume_race", "restart_race", "boost", "shield", "attack"]:
		var result: Dictionary = race._execute_admin_command(command, {"candidate_slot": 1})
		_check(not bool(result["applied"]) and race.race_paused, "Storage failure blocks " + command)
	_check(not bool(race.get_telemetry_snapshot()["persistence"]["ready"]), "Operator receives true persistence failure")
	root.remove_child(race)
	race.free()
	DirAccess.remove_absolute(path)
	var legacy_dir: String = "user://sessions/local"
	DirAccess.make_dir_recursive_absolute(legacy_dir)
	file = FileAccess.open(legacy_dir.path_join("gifts.jsonl"), FileAccess.WRITE)
	file.store_string("legacy paid journal awaiting classification")
	file.close()
	var blocked: RaceSessionStore = RaceSessionStore.new("local")
	_check(blocked.last_error == "legacy_session_requires_review", "Legacy journal must not be silently abandoned by mode migration")
	_check(FileAccess.get_file_as_string(legacy_dir.path_join("gifts.jsonl")) == "legacy paid journal awaiting classification", "Legacy bytes preserved")
	DirAccess.remove_absolute(legacy_dir.path_join("gifts.jsonl"))
	OS.set_environment("LIVE_ACCOUNT", "@xinka_")
	var account_store: RaceSessionStore = RaceSessionStore.new("tiktok")
	_check(account_store.get_storage_directory().contains("/accounts/" + "xinka_".sha256_text().substr(0, 16) + "/tiktok"), "New account has isolated storage")
	OS.set_environment("LIVE_ACCOUNT", "nostalgiia.br")
	var old_account_store: RaceSessionStore = RaceSessionStore.new("tiktok")
	_check(old_account_store.get_storage_directory() != account_store.get_storage_directory(), "Different accounts never share checkpoints")
	OS.set_environment("LIVE_ACCOUNT", "@xinka_")
	var prior_mode: String = "user://sessions/production/tiktok"
	DirAccess.make_dir_recursive_absolute(prior_mode)
	file = FileAccess.open(prior_mode.path_join("gifts.jsonl"), FileAccess.WRITE)
	file.store_string("unclassified prior account gifts")
	file.close()
	var blocked_account: RaceSessionStore = RaceSessionStore.new("tiktok")
	_check(blocked_account.last_error == "legacy_session_requires_review", "Prior unscoped mode journal blocks silent account migration")
	_check(FileAccess.get_file_as_string(prior_mode.path_join("gifts.jsonl")) == "unclassified prior account gifts", "Prior account bytes preserved")
	OS.set_environment("LIVE_ACCOUNT", "")
	await create_timer(.1).timeout
	for failure: String in failures:
		printerr("FAIL: ", failure)
	print("TEST_PRODUCTION_STORAGE_GUARD_PASSED" if failures.is_empty() else "TEST_PRODUCTION_STORAGE_GUARD_FAILED")
	quit(0 if failures.is_empty() else 1)
