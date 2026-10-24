extends SceneTree

var _ran: bool = false
var _clock: int = 10000
var _notice_count: int = 0
var _test_base: String = ""


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_test_base = "user://session-store-tests/session_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var passed: bool = _test_audience_roundtrip() and _test_store_roundtrip() and _test_limits()
	_cleanup_test_files()
	print("TEST_SESSION_PERSISTENCE_PASSED" if passed else "TEST_SESSION_PERSISTENCE_FAILED")
	quit(0 if passed else 1)
	return true


func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("FAIL: ", message)
	return condition


func _gift(event_id: String, coins: int = 14, team: int = 1) -> Dictionary:
	var payload: Dictionary = {"coin_value": coins, "repeat_count": 2, "gift_tier": "T1", "gift_name": "Presente", "action_id": "gift_t1_turbo"}
	if team > 0:
		payload["candidate_slot"] = team
	return {
		"schema_version": "1.0", "event_id": event_id, "source": "simulator",
		"event_type": "gift", "timestamp_ms": _clock, "priority": "P0",
		"user": {"user_id": "ana", "display_name": "Ana"}, "payload": payload
	}


func _vote(event_id: String, team: int = 1) -> Dictionary:
	var event: Dictionary = _gift(event_id)
	event["event_type"] = "vote"
	event["payload"] = {"candidate_slot": team, "action_id": "vote_impulse", "repeat_count": 1}
	return event


func _test_audience_roundtrip() -> bool:
	var original: AudienceDirector = AudienceDirector.new()
	original.time_provider = func() -> int: return _clock
	original.ingest_event(_vote("persist_vote_0001"))
	original.ingest_event(_gift("persist_gift_0001"))
	original.reset_round()
	original.ingest_event(_gift("persist_gift_0002", 21, 0))
	var exported: Dictionary = original.export_state()
	var transported: Variant = JSON.parse_string(JSON.stringify(exported))
	var restored: AudienceDirector = AudienceDirector.new()
	_clock = 100
	restored.time_provider = func() -> int: return _clock
	restored.participation_received.connect(func(_participant: Dictionary) -> void: _notice_count += 1)
	restored.leaderboard_changed.connect(func(_entries: Array[Dictionary]) -> void: _notice_count += 1)
	restored.moment_requested.connect(func(_kind: String, _team: int, _name: String) -> void: _notice_count += 1)
	var imported: bool = transported is Dictionary and restored.import_state(transported as Dictionary)
	var same_snapshot: bool = restored.get_snapshot() == original.get_snapshot()
	var no_replay: bool = not restored.ingest_event(_gift("persist_gift_0002", 21, 0))
	var silent: bool = _notice_count == 0
	restored.ingest_event(_vote("persist_vote_0002", 2))
	var cooldown_survived: bool = _notice_count == 0 and restored.get_snapshot()["participants_by_team"] == [0, 0, 1]
	_clock += AudienceDirector.NAME_COOLDOWN_MS
	restored.ingest_event(_vote("persist_vote_0003", 2))
	var resumed_notices: bool = _notice_count == 2
	var before_corrupt: Dictionary = restored.export_state()
	var corruptions: Array[Dictionary] = []
	var broken: Dictionary = exported.duplicate(true)
	broken["schema_version"] = 2
	corruptions.append(broken)
	broken = exported.duplicate(true)
	broken["session"]["coins"][0] = -1
	corruptions.append(broken)
	broken = exported.duplicate(true)
	broken["users"]["simulator:ana"]["team"] = 13
	corruptions.append(broken)
	broken = exported.duplicate(true)
	broken["users"]["simulator:ana"]["display_name"] = "[b]Ana[/b]"
	corruptions.append(broken)
	broken = exported.duplicate(true)
	broken["supporters"]["simulator:ana"]["coins"] = 999999
	corruptions.append(broken)
	broken = exported.duplicate(true)
	broken["event_ids"].append(broken["event_ids"][0])
	corruptions.append(broken)
	broken = exported.duplicate(true)
	broken["user_order"].clear()
	corruptions.append(broken)
	broken = exported.duplicate(true)
	broken["round"]["coins"][1] = 1000
	corruptions.append(broken)
	broken = exported.duplicate(true)
	broken["ranking_limited"] = "false"
	corruptions.append(broken)
	var rejected_safely: bool = true
	for corruption: Dictionary in corruptions:
		if restored.import_state(corruption) or restored.export_state() != before_corrupt:
			rejected_safely = false
	var export_is_copy: Dictionary = restored.export_state()
	export_is_copy["supporters"]["simulator:ana"]["coins"] = 1
	var protected_copy: bool = restored.export_state() == before_corrupt
	var legacy_state: Dictionary = exported.duplicate(true)
	for scope: String in ["round", "session"]:
		legacy_state[scope].erase("gifts")
		legacy_state[scope].erase("follows")
	var legacy: AudienceDirector = AudienceDirector.new()
	var legacy_imported: bool = legacy.import_state(legacy_state)
	var legacy_compatible: bool = legacy_imported and legacy.get_snapshot()["session"]["gifts"] == [0, 0, 0] and legacy.get_snapshot()["session"]["follows"] == [0, 0, 0] and int(legacy.get_top_supporters()[0]["coins"]) == 35
	legacy.free()
	original.free()
	restored.free()
	return _check(imported and same_snapshot, "Estado deve sobreviverJSON e restaurar usuários/torcidas/ranking/contagens") and _check(no_replay and silent, "Importação silenciosa deve preservar dedup sem agradecer presentes antigos") and _check(cooldown_survived and resumed_notices, "Cooldown deve sobreviver à troca de relógio monotônico") and _check(rejected_safely and protected_copy, "Estado inválido ou alterações na cópia não podem alterar sessão atual") and _check(legacy_compatible, "Checkpoint schema1 antigo deve preservar moedas e preencher novos contadoresgifts/follows comzero")


func _test_store_roundtrip() -> bool:
	var store: RaceSessionStore = RaceSessionStore.new("tiktok", _test_base)
	var initial_missing: bool = store.load_snapshot().is_empty() and store.last_error == "snapshot_missing"
	var first: Dictionary = _gift("journal_gift_0001", 14)
	var second: Dictionary = _gift("journal_gift_0002", 21, 2)
	var appended: bool = store.append_gift(first)
	var cursor: int = store.get_journal_cursor()
	var first_read: Array[Dictionary] = store.load_gifts_since(0)
	var cursor_correct: bool = cursor > 0 and first_read.size() == 1 and store.last_replay_cursor == cursor
	var audience: AudienceDirector = AudienceDirector.new()
	audience.ingest_event(first)
	var checkpoint: Dictionary = {"round": 12, "remaining": 347.5, "meters": [168.1, 171.2], "wins": [4, 3], "journal_cursor": cursor, "audience": audience.export_state()}
	var saved: bool = store.save_snapshot(checkpoint)
	var loaded: Dictionary = store.load_snapshot()
	var saved_and_read: bool = saved and _json_equal(loaded, checkpoint) and not store.loaded_from_backup and store.last_error.is_empty()
	appended = appended and store.append_gift(second)
	var restored: AudienceDirector = AudienceDirector.new()
	var restored_ok: bool = restored.import_state(loaded.get("audience", {}) as Dictionary)
	var tail: Array[Dictionary] = store.load_gifts_since(int(loaded.get("journal_cursor", -1)))
	for gift: Dictionary in tail:
		restored.ingest_event(gift)
	var exactly_once: bool = tail.size() == 1 and int(restored.get_top_supporters()[0]["coins"]) == 35 and not restored.ingest_event(second)
	var no_tail: bool = store.load_gifts_since(store.get_journal_cursor()).is_empty() and store.last_error.is_empty()
	var middle_rejected: bool = store.load_gifts_since(1).is_empty() and store.last_error == "journal_cursor_not_record_boundary"
	var changed: Dictionary = checkpoint.duplicate(true)
	changed["round"] = 13
	var backup_saved: bool = store.save_snapshot(changed)
	var snapshot_path: String = store.get_storage_directory().path_join("snapshot.json")
	_write_isolated(snapshot_path, "{broken")
	var recovered: Dictionary = store.load_snapshot()
	var backup_works: bool = backup_saved and _json_equal(recovered, checkpoint) and store.loaded_from_backup and store.last_error.is_empty()
	# An abandoned temporary file is never mistaken for a committed snapshot.
	_write_isolated(snapshot_path + ".tmp", "{\"state\":\"uncommitted\"}")
	var stale_temp_ignored: bool = _json_equal(store.load_snapshot(), checkpoint)
	var new_good: bool = store.save_snapshot(changed)
	_write_isolated(snapshot_path, "{broken_again")
	var valid_backup_preserved: bool = new_good and _json_equal(store.load_snapshot(), checkpoint) and store.loaded_from_backup
	var journal_path: String = store.get_storage_directory().path_join("gifts.jsonl")
	var original_bytes: PackedByteArray = FileAccess.get_file_as_bytes(journal_path)
	var file: FileAccess = FileAccess.open(journal_path, FileAccess.READ_WRITE)
	file.seek_end()
	file.store_string("{\"unfinished\":")
	file.flush()
	file.close()
	var damaged_bytes: PackedByteArray = FileAccess.get_file_as_bytes(journal_path)
	var incomplete_rejected: bool = store.load_gifts_since(0).is_empty() and store.last_error == "journal_incomplete_tail" and store.last_replay_cursor == 0
	var append_protected: bool = not store.append_gift(first) and store.last_error == "journal_incomplete_tail" and FileAccess.get_file_as_bytes(journal_path) == damaged_bytes
	_write_isolated_bytes(journal_path, original_bytes)
	var invalid_gift: Dictionary = first.duplicate(true)
	invalid_gift["payload"]["coin_value"] = -1
	var invalid_append_rejected: bool = not store.append_gift(invalid_gift) and FileAccess.get_file_as_bytes(journal_path) == original_bytes
	audience.free()
	restored.free()
	return _check(initial_missing and appended and cursor_correct and saved_and_read, "Journal/cursor e snapshot devem gravar/reabrir dados reais em diretório isolado") and _check(restored_ok and exactly_once and no_tail and middle_rejected, "Reinício deve restaurar checkpoint e reaplicar somente a cauda ainda não aplicada") and _check(backup_works and stale_temp_ignored and valid_backup_preserved, "Backup válido deve resistir a main corrompido e temporário abandonado") and _check(incomplete_rejected and append_protected and invalid_append_rejected, "Journal parcial/inválido deve retornar erro sem alterar arquivos nem replay parcial")


func _test_limits() -> bool:
	var invalid_channel: RaceSessionStore = RaceSessionStore.new("../tiktok", _test_base)
	var channel_rejected: bool = not invalid_channel.save_snapshot({"test": true}) and invalid_channel.last_error == "not_configured"
	var invalid_base: RaceSessionStore = RaceSessionStore.new("local", "user://session-store-tests/../sessions")
	var path_rejected: bool = invalid_base.get_storage_directory().is_empty() and not invalid_base.append_gift(_gift("journal_bad_path"))
	var store: RaceSessionStore = RaceSessionStore.new("kwai", _test_base)
	var unsafe_states: bool = not store.save_snapshot({"bad": NAN}) and not store.save_snapshot({"bad": 9007199254740992}) and not store.save_snapshot({"bad": RefCounted.new()})
	var snapshot_path: String = store.get_storage_directory().path_join("snapshot.json")
	var file: FileAccess = FileAccess.open(snapshot_path, FileAccess.WRITE)
	file.seek(RaceSessionStore.MAX_SNAPSHOT_BYTES)
	file.store_8(32)
	file.close()
	var snapshot_bound: bool = store.load_snapshot().is_empty() and store.last_error == "snapshot_size_limit"
	var journal_path: String = store.get_storage_directory().path_join("gifts.jsonl")
	file = FileAccess.open(journal_path, FileAccess.WRITE)
	file.seek(RaceSessionStore.MAX_REPLAY_BYTES)
	file.store_8(10)
	file.close()
	var byte_bound: bool = store.load_gifts_since(0).is_empty() and store.last_error == "journal_replay_byte_limit"
	var wrapper: Dictionary = {"schema_version": 1, "channel": "kwai", "gift": _gift("journal_many_gifts")}
	var record: String = JSON.stringify(wrapper) + "\n"
	_write_isolated(journal_path, record.repeat(RaceSessionStore.MAX_REPLAY_EVENTS + 1))
	var event_bound: bool = store.load_gifts_since(0).is_empty() and store.last_error == "journal_replay_event_limit" and store.last_replay_cursor == 0
	var malicious: Dictionary = _gift("journal_corrupted")
	malicious["payload"]["coin_value"] = -1
	_write_isolated(journal_path, record + JSON.stringify({"schema_version": 1, "channel": "kwai", "gift": malicious}) + "\n")
	var no_partial_replay: bool = store.load_gifts_since(0).is_empty() and store.last_error == "journal_invalid_gift"
	return _check(channel_rejected and path_rejected and unsafe_states, "Canal/path traversal/valoresnãoJSON devem falhar fechados") and _check(snapshot_bound and byte_bound and event_bound and no_partial_replay, "Limites64MB/32MB/20000eventos e corrupção devem impedir leituras sem limites ou replay parcial")


func _write_isolated(path: String, text: String) -> void:
	_write_isolated_bytes(path, text.to_utf8_buffer())


func _json_equal(left: Dictionary, right: Dictionary) -> bool:
	# Godot JSON parses numeric literals as floats. Compare both through the same JSON representation.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func _write_isolated_bytes(path: String, bytes: PackedByteArray) -> void:
	assert(path.begins_with(_test_base + "/"))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_buffer(bytes)
	file.flush()
	file.close()


func _cleanup_test_files() -> void:
	# Remove only explicitly named files underneath this run's unique test directory.
	assert(_test_base.begins_with(RaceSessionStore.TEST_DIRECTORY_PREFIX))
	for channel: String in ["local", "tiktok", "kwai"]:
		var directory: String = _test_base.path_join(channel)
		for filename: String in ["snapshot.json", "snapshot.json.tmp", "snapshot.json.bak", "snapshot.json.bak.tmp", "gifts.jsonl"]:
			var path: String = directory.path_join(filename)
			assert(path.begins_with(_test_base + "/"))
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		if DirAccess.dir_exists_absolute(directory):
			DirAccess.remove_absolute(directory)
	if DirAccess.dir_exists_absolute(_test_base):
		DirAccess.remove_absolute(_test_base)
