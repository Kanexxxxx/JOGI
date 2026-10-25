extends SceneTree

var race: StadiumRace = null
var passed: bool = true


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		passed = false
		printerr("REVISION_FAIL: ", message)


func _event(id: String, kind: String, payload: Dictionary, source: String = "simulator") -> Dictionary:
	return {"schema_version": "1.0", "source": source, "event_id": id, "event_type": kind,
		"user": {"user_id": "review_user", "display_name": "Torcida teste"}, "payload": payload}


func _run() -> void:
	race = (load("res://scenes/main/stadium_race.tscn") as PackedScene).instantiate() as StadiumRace
	root.add_child(race)
	race.set_process(false)
	race.set_physics_process(false)
	race.start_race_immediately()
	for runner: CandidateRunner in race.runners:
		runner.set_physics_process(false)
	var lula: StadiumRunner = race.runners[0] as StadiumRunner
	var flavio: StadiumRunner = race.runners[1] as StadiumRunner
	lula.progress_m = 80.0
	flavio.progress_m = 10.0
	race._update_stage(0.0, true)
	race._update_hud()
	_check(lula.stage_position.x > flavio.stage_position.x + 4.0, "vantagem real aparece em profundidade")
	_check(race.stadium_hud.get_display_order() == [1, 2], "Lula em primeiro sem trocar identidade")
	race._update_race_moments(.4)
	lula.progress_m = 10.0
	flavio.progress_m = 25.0
	race._update_stage(0.0, true)
	race._update_hud()
	race._update_race_moments(.4)
	_check(flavio.stage_position.x > lula.stage_position.x + 3.0, "ultrapassagem inverte apenas avanço, não raias")
	_check(lula.stage_position.z < flavio.stage_position.z and race.stadium_hud.get_display_order() == [2, 1], "placar segue novo líder, raias preservadas")
	_check(race._last_leader_slot == 2, "mudança de líder confirmada para locução")
	lula.progress_m = 26.0
	race._update_race_moments(.4)
	for item: Dictionary in race.audio._queue:
		var clip: Dictionary = item["clip"] as Dictionary
		_check(not (clip["kind"] == "overtake" and int(clip["team"]) == 2), "reversão invalida locução antiga mesmo no cooldown")
	var bus: LiveEventBusInstance = race.event_bus
	_check(bus.ingest_envelope(_event("goal-specific-review", "admin_command", {"command": "set_live_goal", "goal_kind": "gift_specific", "goal_gift_id": "rose_123", "goal_target": 10, "goal_label": "Meta de rosas"}, "admin")), "meta por ID validada")
	var gift: Dictionary = _event("rose-quantity-review", "gift", {"gift_id": "rose_123", "coin_value": 3, "repeat_count": 3, "candidate_slot": 1, "gift_tier": "T1", "boost_amount": .6, "boost_duration": 3.0})
	bus.ingest_envelope(gift)
	bus.ingest_envelope(gift)
	bus.ingest_envelope(_event("other-gift-review", "gift", {"gift_id": "other_123", "coin_value": 2, "repeat_count": 2}))
	_check(race._get_live_summary()["goal"]["value"] == 3, "meta conta apenas rosas e não duplica combo")
	var icon_path: String = "/gift-icons/" + "b".repeat(64)
	var sample_img: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	sample_img.fill(Color.GOLD)
	var sample_tex: Texture2D = ImageTexture.create_from_image(sample_img)
	race.gift_visuals.set_process(false)
	bus.ingest_envelope(_event("gift-visual-pending-01", "gift", {"gift_id": "gift_5655", "gift_icon_path": icon_path, "coin_value": 5, "repeat_count": 1, "candidate_slot": 1, "gift_tier": "T1", "action_id": "gift_t1_turbo"}))
	_check(race.stadium_hud._artwork.gift_image_active[0] and race.stadium_hud._gift_images[0].visible, "catálogo permanente permanece visível enquanto imagem observada aguarda")
	race.gift_visuals._store_texture(icon_path, sample_tex)
	race.gift_visuals.icon_ready.emit("gift_5655", sample_tex)
	_check(race.stadium_hud._artwork.gift_image_active[0] and race.stadium_hud._gift_images[0].visible and race.gift_visuals.get_icon("gift_5655") == sample_tex, "cache recebe imagem real sem esconder catálogo permanente")
	bus.ingest_envelope(_event("gift-visual-override-02", "gift", {"gift_id": "gift_5655", "gift_icon_path": icon_path, "coin_value": 5, "repeat_count": 1, "candidate_slot": 1, "gift_tier": "T3", "action_id": "gift_t3_attack"}))
	_check(race.stadium_hud._artwork.gift_image_active[0] and race.stadium_hud._artwork.gift_image_active[2] and race._observed_gift_actions.get("attack") == "gift_5655" and not race._observed_gift_actions.has("boost"), "override atualiza ação observada e preserva quatro presentes permanentes")
	var snap: Dictionary = race.get_telemetry_snapshot()
	_check(snap.has("performance") and (snap["performance"] as Dictionary).has("fps") and (snap["performance"] as Dictionary).has("orphan_nodes") and snap.has("gift_visuals"), "telemetria exporta performance do motor e cache de ícones")
	sample_tex = null
	sample_img = null
	var exported: Dictionary = race.audience.export_state()
	var restored: AudienceDirector = AudienceDirector.new()
	_check(restored.import_state(exported) and restored.get_gift_count("rose_123") == 3, "contador por ID persiste")
	exported["gift_id_counts"]["simulator:rose_123"] = 999999
	_check(not restored.import_state(exported) and restored.get_gift_count("rose_123") == 3, "contador corrompido é rejeitado antes de mutar")
	restored.free()
	lula.progress_m = 30.0
	flavio.progress_m = 20.0
	race.match_time_remaining = 0.0
	race._finish_match_by_timer()
	_check(is_equal_approx(race.get_next_round_in(), 30.0), "intervalo total é30s")
	race._update_hud()
	_check(race.stadium_hud.advantage_label.text.contains("13 VENCEU"), "vitória identifica13")
	race._physics_process(3.0)
	race._physics_process(24.0)
	_check(race.current_state == RaceMain.RaceState.COUNTDOWN and race.current_round == 2, "após27s próxima contagem3s")
	race._physics_process(3.0)
	_check(race.current_state == RaceMain.RaceState.RACING, "nova largada aos30s")
	# Colisão real no motor, sem chamar apply_stumble diretamente.
	flavio.set_physics_process(false)
	lula.set_physics_process(true)
	race.spawn_political_obstacle(1)
	for frame: int in range(150):
		await physics_frame
		if lula.stumble_count > 0:
			break
	_check(lula.stumble_count == 1, "obstáculo físico provoca queda")
	for frame: int in range(12):
		await physics_frame
	_check(lula.presentation._fall_elapsed >= 0.0 and absf(lula.presentation.rotation.x) > .1, "impacto produz reação corporal visível")
	lula.set_physics_process(false)
	race._clear_dynamic_obstacles()
	await process_frame
	lula.reset_runner(Vector3(-1.4, 0.0, 0.0))
	lula.start_running()
	lula.apply_shield(5.0)
	lula.set_physics_process(true)
	race.spawn_political_obstacle(1)
	for frame: int in range(150):
		await physics_frame
		if lula.shield_absorbed_count > 0:
			break
	_check(lula.shield_absorbed_count == 1 and lula.stumble_count == 0, "escudo absorve sem queda")
	lula.set_physics_process(false)
	for event: int in range(90):
		race.spawn_political_obstacle(1)
	_check(race._obstacles_root.get_child_count() <= 65, "rajada usa no máximo64 pilhas ativas")
	for area: Node in race._obstacles_root.get_children():
		(area as Area3D).global_position.z = lula.global_position.z + 5.0
	race._prune_obstacles()
	await process_frame
	race._update_stage(0.0)
	_check(race._obstacles_root.get_child_count() == 0 and race._attack_visuals.is_empty(), "pilhas passadas são liberadas")
	root.remove_child(race)
	race.free()
	await create_timer(.5).timeout
	print("TEST_ESTREIA_REVISION_PASSED" if passed else "TEST_ESTREIA_REVISION_FAILED")
	quit(0 if passed else 1)
