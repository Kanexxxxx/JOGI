extends SceneTree
## Full real scene, development-only deterministic interaction chain.
var _passed: bool = true
var _capture_dir: String = ""
var _race: StadiumRace = null

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_passed = false
		printerr("INTERACTION_CHAIN_FAIL: ", description)

func _event(index: int, team: int, kind: String = "vote") -> Dictionary:
	var payload: Dictionary = {"candidate_slot": team, "action_id": "vote_impulse"}
	if kind == "gift":
		payload = {"candidate_slot": team, "gift_tier": "T1", "coin_value": 1, "repeat_count": 1}
	return {"schema_version": "1.0", "source": "simulator", "event_id": "interaction_chain_%08d" % index,
		"event_type": kind, "user": {"user_id": "viewer_%d" % index, "display_name": "Pessoa teste %d" % index}, "payload": payload}

func _capture(label: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(_capture_dir.path_join(label + ".png"))

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--interaction-captures="):
			_capture_dir = argument.trim_prefix("--interaction-captures=")
	if not _capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture_dir)
	OS.set_environment("JOGI_MODE", "development")
	OS.set_environment("LIVE_BRIDGE_WS_URL", "ws://127.0.0.1:9/ws/godot")
	_race = (load("res://scenes/main/stadium_race.tscn") as PackedScene).instantiate() as StadiumRace
	root.add_child(_race)
	await process_frame
	_race.start_race_immediately()
	var hud: StadiumHUD = _race.stadium_hud
	hud.set_process(false)
	await _capture("00-before")
	_check(_race.event_bus.ingest_envelope(_event(1, 1)), "13 accepted by real bus")
	_check(_race.event_bus.ingest_envelope(_event(2, 2)), "22 accepted in same frame")
	_check(hud._interaction_entries.size() == 2, "both same-frame comments reach HUD")
	_check(int(_race.audience.get_session_counts()["votes"][1]) == 1 and int(_race.audience.get_session_counts()["votes"][2]) == 1, "audience ledger counts both votes")
	var start: float = hud._elapsed
	hud._elapsed = start + 0.15
	hud._animate_interaction_cards()
	_check((hud._interaction_slots[0]["panel"] as Control).modulate.a > 0.0 and (hud._interaction_slots[0]["panel"] as Control).modulate.a < 1.0, "animated entrance")
	await _capture("01-entering")
	hud._elapsed = start + 1.0
	hud._animate_interaction_cards()
	for slot: Dictionary in hud._interaction_slots:
		_check((slot["panel"] as Control).is_visible_in_tree(), "card exists in rendered canvas")
		_check((slot["mono_panel"] as Control).visible, "missing avatar uses generic fallback")
		_check(not (slot["name_label"] as Label).text.is_empty(), "viewer name rendered")
	await _capture("02-readable-13-22")
	_check(_race.event_bus.ingest_envelope(_event(3, 1)), "third valid vote accepted while cards visible")
	_check(hud._interaction_pending.size() == 1, "burst retained in visual queue")
	hud._elapsed = start + 5.5
	hud._expire_interactions()
	_check(hud._interaction_entries.size() == 2, "still readable beyond five seconds")
	await _capture("03-still-readable-5s")
	hud._elapsed = start + StadiumHUD.INTERACTION_TTL_SECONDS - 0.15
	hud._animate_interaction_cards()
	_check((hud._interaction_slots[0]["panel"] as Control).modulate.a < 1.0, "animated exit")
	await _capture("04-exiting")
	hud._elapsed = start + StadiumHUD.INTERACTION_TTL_SECONDS + 0.1
	hud._expire_interactions()
	_check(hud._interaction_entries.size() == 1 and hud._interaction_pending.is_empty(), "queued comment admitted after visible cards expire")
	hud._elapsed += 1.0
	hud._animate_interaction_cards()
	await _capture("05-queued-vote")
	# Replay never affects either the race/audience ledger or the visual queue.
	var counts_before: Dictionary = _race.audience.get_session_counts()
	var visible_before: int = hud._interaction_entries.size()
	_check(not _race.event_bus.ingest_envelope(_event(3, 1)), "duplicate event rejected")
	_check(_race.audience.get_session_counts() == counts_before and hud._interaction_entries.size() == visible_before, "duplicate never increases votes or cards")
	var repeated: Dictionary = _event(4, 1)
	repeated["user"] = _event(3, 1)["user"].duplicate(true)
	_check(_race.event_bus.ingest_envelope(repeated), "same viewer new event accepted")
	_check(hud._interaction_entries.size() == visible_before and int(hud._interaction_entries[0].get("repetitions", 1)) == 2, "same viewer coalesces visual card")
	_check(int(_race.audience.get_session_counts()["votes"][1]) == int(counts_before["votes"][1]) + 1, "coalescing preserves real vote count")
	# Seed a genuine local cache texture, without requesting an external avatar.
	var avatar_path: String = "/viewer-avatars/" + "a".repeat(64)
	var avatar_image: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	avatar_image.fill(Color("55bbff"))
	_race.avatar_visuals.enabled = true
	_race.avatar_visuals._textures[avatar_path] = ImageTexture.create_from_image(avatar_image)
	var avatar_event: Dictionary = _event(5, 2)
	avatar_event["user"]["avatar_icon_path"] = avatar_path
	_check(_race.event_bus.ingest_envelope(avatar_event), "event with safe local avatar accepted")
	var avatar_slot: Dictionary = hud._interaction_slots[0]
	_check((avatar_slot["avatar"] as TextureRect).visible and (avatar_slot["avatar"] as TextureRect).texture != null and not (avatar_slot["mono_panel"] as Control).visible, "valid local cached avatar replaces fallback")
	# Round transitions do not sever the participation signal.
	_race._advance_round()
	_race.start_race_immediately()
	var queued_before_round_vote: int = hud._interaction_pending.size()
	_check(_race.event_bus.ingest_envelope(_event(6, 1)), "vote accepted after round transition")
	_check(hud._interaction_pending.size() == queued_before_round_vote + 1, "new-round vote still reaches HUD")
	# Stress only the visual queue: paid acknowledgements take precedence.
	for index: int in range(StadiumHUD.MAX_INTERACTION_QUEUE + 2):
		hud.show_participation({"identity": "queue_fixture_%d" % index, "display_name": "Fila teste", "kind": "vote", "team": 1})
	_check(hud._interaction_pending.size() == StadiumHUD.MAX_INTERACTION_QUEUE, "visual queue stays bounded")
	var ledger_before_priority: Dictionary = _race.audience.get_session_counts()
	hud.show_participation({"identity": "priority_paid_fixture", "display_name": "Presente teste", "kind": "gift", "team": 2, "gift_id": "test_gift", "gift_quantity": 1})
	_check(hud._interaction_pending.size() == StadiumHUD.MAX_INTERACTION_QUEUE and str(hud._interaction_pending[0]["kind"]) == "gift", "new gift replaces free queued notification when queue is full")
	_check(_race.audience.get_session_counts() == ledger_before_priority, "visual priority never mutates the event ledger")
	_race.queue_free()
	await process_frame
	print("TEST_INTERACTION_CARDS_CHAIN_PASSED" if _passed else "TEST_INTERACTION_CARDS_CHAIN_FAILED")
	quit(0 if _passed else 1)
