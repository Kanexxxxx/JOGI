extends SceneTree

var _race: StadiumRace = null
var _tested: bool = false
var _passed: bool = true


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main/stadium_race.tscn") as PackedScene
	_race = packed.instantiate() as StadiumRace
	root.add_child(_race)


func _process(_delta: float) -> bool:
	if not _tested:
		_tested = true
		_run_suite.call_deferred()
	return false


func _run_suite() -> void:
	_race.set_physics_process(false)
	_race.set_process(false)
	_race.obstacles_enabled = false
	_race.start_race_immediately()
	for runner: CandidateRunner in _race.runners:
		runner.set_physics_process(false)
	var bus: LiveEventBusInstance = _race.event_bus
	bus.reset_deduplication()
	_check(_race.runners.size() == 2 and _race.match_duration == 600.0, "Dois corredores e rodada de dez minutos")
	var lula: StadiumRunner = _race.runners[0] as StadiumRunner
	var flavio: StadiumRunner = _race.runners[1] as StadiumRunner
	_check(lula.stage_position.z < flavio.stage_position.z, "Lula na esquerda e Flávio na direita da transmissão")
	_check(lula.stage_facing_y == -PI * .5 and flavio.stage_facing_y == -PI * .5, "Corredores seguem na mesma direção da pista")
	_check(bus.ingest_envelope(_event("neutral-gift-0001", "gift", {"coin_value": 100, "repeat_count": 10})), "Presente neutro aceito")
	_check(lula.boost_timer == 0.0 and flavio.boost_timer == 0.0, "Presente neutro não escolhe equipe")
	_check(bus.ingest_envelope(_event("vote-flavio-0002", "vote", {"candidate_slot": 2})), "Torcida aceita")
	_check(flavio.boost_timer > 0.0 and lula.boost_timer == 0.0, "Torcida impulsiona apenas sua equipe")
	var gift: Dictionary = _event("gift-flavio-0003", "gift", {"candidate_slot": 2, "coin_value": 120, "repeat_count": 3, "gift_tier": "T2", "gift_name": "Presente teste"})
	_check(bus.ingest_envelope(gift), "Presente direcionado aceito")
	_check(_race.stadium_hud._audience_label.text.contains("Joana"), "Nome permanece após boost e escudo no mesmo frame")
	_check(_race.stadium_hud._event_text.text.contains("ESCUDO"), "Mecânica tem faixa própria")
	_check(not bus.ingest_envelope(gift), "Replay ignorado")
	var top: Array[Dictionary] = _race.audience.get_top_supporters()
	_check(top.size() == 1 and top[0]["coins"] == 220, "Top soma total do delta uma vez, preservando moedas neutras anteriores")
	_check(bus.ingest_envelope(_event("unknown-gift-0004", "gift", {"coin_value": 0})), "Preço desconhecido é agradecido")
	_check(_race.audience.get_top_supporters()[0]["coins"] == 220, "Preço desconhecido não inventa moedas")
	_check(bus.ingest_envelope(_event("follow-joana-0005", "follow", {"repeat_count": 1})), "Novo seguidor aceito")
	var goal_event: Dictionary = {"schema_version": "1.0", "source": "admin", "event_id": "admin-goal-follows-0006", "event_type": "admin_command", "user": {"user_id": "admin", "display_name": "Painel"}, "payload": {"command": "set_live_goal", "goal_kind": "follows", "goal_target": 10, "goal_label": "Novos seguidores"}}
	_check(bus.ingest_envelope(goal_event), "Painel altera meta por contrato validado")
	var telemetry: Dictionary = _race.get_telemetry_snapshot()
	_check(telemetry["live_goal"]["value"] == 1 and is_equal_approx(float(telemetry["live_goal"]["progress"]), .1), "Meta usa eventos reais de seguidores e progride10%")
	_check(_race.stadium_hud._followers_label.text == "SEGUIDORES +1", "Seguidores aparecem na tela")
	_check(_race.stadium_hud._ranking_names.size() == 5, "Top5 está disponível sem inventar doadores")
	var malformed_goal: Dictionary = goal_event.duplicate(true)
	malformed_goal["event_id"] = "admin-invalid-goal-0007"
	malformed_goal["payload"]["goal_target"] = 0
	_check(not bus.ingest_envelope(malformed_goal), "Meta inválida não altera estado")
	lula.progress_m = 100000.0
	flavio.progress_m = 10.0
	_race._update_stage(0.0, true)
	_check(lula.stage_position.x > flavio.stage_position.x and absf(lula.stage_position.x - flavio.stage_position.x) <= 7.001, "Líder aparece à frente com limite para manter ambos em quadro")
	_check(lula.progress_m == 100000.0 and flavio.progress_m == 10.0, "Apresentação não modifica placar físico")
	_race.set_race_paused(true)
	var remaining: float = _race.match_time_remaining
	_race._physics_process(3.0)
	_check(_race.match_time_remaining == remaining and _race.stadium_hud.phase_label.text == "CORRIDA PAUSADA", "Pausa congela cronômetro e atualiza tela")
	_race.restart_race()
	_check(lula.progress_m == 0.0 and flavio.progress_m == 0.0, "Reinício zera metros")
	_check(_race.audience.get_top_supporters()[0]["coins"] == 220, "Reinício de tentativa conserva apoiadores da live")
	_race.start_race_immediately()
	lula.progress_m = 30.0
	flavio.progress_m = 20.0
	_race.match_time_remaining = 0.0
	_race._finish_match_by_timer()
	_check(_race.winner == lula and _race._finish_line.visible and _race.cycle_wins == [1, 0], "Tempo esgotado apresenta chegada do vencedor correto")
	_check(bool(lula.get_round_finish_state()["active"]) and bool(lula.get_round_finish_state()["is_winner"]), "Vencedor inicia animação da rodada")
	_race._physics_process(3.1)
	_check(_race.current_state == RaceMain.RaceState.PODIO and _race.stadium_hud._podium_mode, "Pódio destaca três apoiadores durante intervalo")
	_check(not _race.stadium_hud._ranking_names[3].visible and not _race.stadium_hud._ranking_names[4].visible, "Pódio não duplica Top5")
	# Regressão explícita P2 #2: reversão rápida 1 -> 2 -> 1 durante cooldown cancela fala obsoleta de ultrapassagem de 2.
	_race.restart_race(true)
	_race.start_race_immediately()
	_race.audio.configure_manifest({
		"schema_version": 1,
		"clips": [
			{"id": "ov1", "kind": "overtake", "team": 1, "priority": 60, "cooldown_seconds": 8.0, "clip_path": ""},
			{"id": "ov2", "kind": "overtake", "team": 2, "priority": 60, "cooldown_seconds": 8.0, "clip_path": ""}
		]
	})
	_race.audio.enabled = true
	lula.progress_m = 20.0
	flavio.progress_m = 10.0
	_race._update_race_moments(0.45)
	_check(_race._last_leader_slot == 1, "Lula confirma liderança inicial")
	flavio.progress_m = 23.0
	_race._update_race_moments(0.45)
	_check(_race._last_leader_slot == 2 and _race._overtake_cooldown > 5.0, "Flávio ultrapassa e ativa cooldown de ultrapassagem")
	lula.progress_m = 26.0
	_race._update_race_moments(0.45)
	_check(_race._last_leader_slot == 1 and _race.audio._current_leader == 1, "Reversão rápida 1->2->1 atualiza líder real mesmo em cooldown")
	var stale_team2_queued: bool = false
	for q_item: Dictionary in _race.audio._queue:
		var q_clip: Dictionary = q_item.get("clip", {}) as Dictionary
		if String(q_clip.get("kind", "")) == "overtake" and int(q_clip.get("team", 0)) == 2:
			stale_team2_queued = true
	_check(not stale_team2_queued and _race.audio._active_team != 2, "Nenhuma fala obsoleta de ultrapassagem do time 2 permanece ativa ou na fila")
	# Três metas simultâneas independentes via comando administrativo set_live_goals
	var multi_goals_cmd: Dictionary = {
		"schema_version": "1.0",
		"source": "admin",
		"event_id": "admin-multi-goals-0008",
		"event_type": "admin_command",
		"user": {"user_id": "admin", "display_name": "Painel"},
		"payload": {
			"command": "set_live_goals",
			"goals": {
				"likes": {"goal_kind": "likes", "goal_target": 1500, "goal_label": "Meta Curtidas"},
				"gifts": {"goal_kind": "gifts", "goal_target": 300, "goal_label": "Meta Presentes"},
				"follows": {"goal_kind": "follows", "goal_target": 10000, "goal_label": "Meta 10K", "follower_baseline": 8400, "baseline_updated_at": "2026-10-24T15:00:00Z"}
			}
		}
	}
	_check(bus.ingest_envelope(multi_goals_cmd), "Comando set_live_goals aceito no barramento")
	var snap_multi: Dictionary = _race.get_telemetry_snapshot()
	var lg: Dictionary = snap_multi.get("live_goals", {}) as Dictionary
	_check(int((lg.get("follows", {}) as Dictionary).get("value", 0)) == 8401, "Meta 10K soma baseline manual auditado + follows da sessão")
	root.remove_child(_race)
	_race.free()
	_race = null
	await process_frame
	print("TEST_STADIUM_INTEGRATION_PASSED" if _passed else "TEST_STADIUM_INTEGRATION_FAILED")
	quit(0 if _passed else 1)


func _event(id: String, kind: String, payload: Dictionary) -> Dictionary:
	return {"schema_version": "1.0", "source": "simulator", "event_id": id, "event_type": kind,
		"user": {"user_id": "joana_teste", "display_name": "Joana"}, "payload": payload}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_passed = false
		printerr("FAIL: ", message)
