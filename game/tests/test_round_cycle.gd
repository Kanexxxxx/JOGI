extends SceneTree

var _race: RaceMain = null
var _ran_suite: bool = false
var _finish_signals: int = 0


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main/race_main.tscn") as PackedScene
	if packed != null:
		_race = packed.instantiate() as RaceMain
		if _race != null:
			root.add_child(_race)
			_race.race_finished.connect(func(_winner: CandidateRunner) -> void: _finish_signals += 1)


func _process(_delta: float) -> bool:
	if _ran_suite:
		return true
	_ran_suite = true
	var passed: bool = _execute_test_suite()
	if _race != null:
		root.remove_child(_race)
		_race.free()
		_race = null
	if passed:
		print("TEST_ROUND_CYCLE_PASSED: 50 rodadas, ciclo, empate, pausa, replay e reinício")
	else:
		printerr("TEST_ROUND_CYCLE_FAILED")
	quit(0 if passed else 1)
	return true


func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("FAIL: ", message)
	return condition


func _execute_test_suite() -> bool:
	if not _check(_race != null, "Cena deve instanciar"):
		return false
	if not _check(_race.match_duration == 600.0 and _race.auto_loop_after_podium, "Padrão deve ser 10 minutos e avanço automático"):
		return false
	if not _check(_race.current_round == 1 and _race.cycle_number == 1 and _race.cycle_wins == [0, 0], "Ciclo deve começar limpo"):
		return false
	if not _check(_race.runners[1].candidate_name == "FLÁVIO BOLSONARO", "Elenco deve identificar Flávio"):
		return false
	# Pausar qualquer fase congela timers e física dos corredores.
	var before_pause: float = _race.state_timer
	_race._on_bus_admin_command("pause")
	_race._physics_process(50.0)
	if not _check(_race.state_timer == before_pause and not _race.runners[0].is_physics_processing(), "Pausa de lobby deve congelar relógio e corredores"):
		return false
	_race._on_bus_admin_command("resume")
	if not _check(_race.runners[0].is_physics_processing(), "Retomar deve reativar física"):
		return false
	var expected_wins: Array[int] = [0, 0]
	for round_id: int in range(1, 51):
		if not _check(_race.current_round == round_id and _race.cycle_number == 1, "Rodadas devem avançar uma a uma"):
			return false
		if not _check(int(_race.round_metadata.get("id", 0)) == round_id and not String(_race.round_metadata.get("name", "")).is_empty(), "Nome e ID devem vir do catálogo"):
			return false
		_race._physics_process(_race.lobby_duration)
		_race._physics_process(_race.countdown_duration)
		if not _check(_race.current_state == RaceMain.RaceState.RACING, "Próxima rodada deve largar sozinha"):
			return false
		var slot: int = 1 if round_id % 2 == 1 else 2
		_race.runners[slot - 1].progress_m = 900.0
		_race.runners[2 - slot].progress_m = 800.0
		_race._physics_process(600.0)
		expected_wins[slot - 1] += 1
		if not _check(_race.current_state == RaceMain.RaceState.PHOTO_FINISH and _race.winner.candidate_id == slot, "Fim deve escolher a maior distância"):
			return false
		if not _check(_race.state_timer == _race.photo_finish_duration, "Foto deve durar o tempo configurado"):
			return false
		_race._finish_match_by_timer()
		if not _check(_race.round_history.size() == round_id and int(_race.round_history.back()["winner_slot"]) == slot, "Histórico deve registrar cada resultado uma vez"):
			return false
		if not _check(_race.cycle_wins == expected_wins and _finish_signals == round_id, "Repetir finalização não pode duplicar resultado nem sinal"):
			return false
		_race._physics_process(_race.photo_finish_duration)
		if not _check(_race.current_state == RaceMain.RaceState.PODIO and _race.state_timer == _race.podium_duration, "Pódio deve durar o tempo configurado"):
			return false
		if round_id == 50:
			if not _check(_race.cycle_wins == [25, 25] and _race.current_round == 50, "Placar da final deve permanecer durante pódio"):
				return false
			_race.set_race_paused(true)
			_race._physics_process(1000.0)
			if not _check(_race.current_round == 50 and _race.cycle_number == 1, "Pausa não pode avançar o ciclo"):
				return false
			_race.set_race_paused(false)
		_race._physics_process(_race.podium_duration)
	if not _check(_race.current_round == 1 and _race.cycle_number == 2 and _race.cycle_wins == [0, 0], "Após a final deve zerar placar e começar ciclo 2"):
		return false
	for runner: CandidateRunner in _race.runners:
		if not _check(is_zero_approx(runner.progress_m) and runner.lobby_votes == 0 and runner.boost_timer == 0.0 and not runner.is_finished, "Novo ciclo deve limpar estado de jogo dos corredores"):
			return false
	# Reiniciar em andamento conserva rodada/ciclo e não soma vitória.
	_race.start_racing()
	_race.runners[0].apply_boost(3.0, 3.0)
	var boost_before_pause: float = _race.runners[0].boost_timer
	_race.set_race_paused(true)
	_race._physics_process(1000.0)
	if not _check(_race.match_time_remaining == 600.0 and _race.runners[0].boost_timer == boost_before_pause, "Pausa de corrida deve manter tempo e efeitos"):
		return false
	_race._on_bus_admin_command("restart_race")
	if not _check(not _race.race_paused and _race.current_round == 1 and _race.cycle_wins == [0, 0], "Restart deve limpar pausa sem avançar rodada"):
		return false
	# Reiniciar uma tentativa encerrada desfaz somente o ponto dessa tentativa.
	_race.start_racing()
	_race.runners[0].progress_m = 100.0
	_race.match_time_remaining = 0.01
	_race._physics_process(0.02)
	if not _check(_race.cycle_wins == [1, 0], "Tentativa deve somar uma vitória"):
		return false
	_race.restart_race(true)
	_race.restart_race(true)
	if not _check(_race.current_round == 1 and _race.cycle_wins == [0, 0], "Repetir restart não pode subtrair outros pontos"):
		return false
	# Empate com tolerância de um centímetro não soma ponto a nenhum lado.
	_race.start_racing()
	_race.runners[0].progress_m = 100.0
	_race.runners[1].progress_m = 100.005
	_race.match_time_remaining = 0.01
	_race._physics_process(0.02)
	if not _check(_race.winner == null and _race.cycle_wins == [0, 0], "Distâncias empatadas devem terminar sem vencedor"):
		return false
	_race._physics_process(_race.photo_finish_duration)
	if not _check(_race._center_banner_title.text.contains("EMPATE"), "Pódio deve anunciar empate"):
		return false
	_race.auto_loop_after_podium = false
	_race._physics_process(_race.podium_duration + 1.0)
	if not _check(_race.current_state == RaceMain.RaceState.PODIO and _race.current_round == 1, "Operador pode desativar avanço automático"):
		return false
	var snapshot: Dictionary = _race.get_telemetry_snapshot()
	if not _check(_race.round_history.size() <= 50 and (snapshot.get("round_history", []) as Array).size() <= 10, "Histórico deve ser limitado e a telemetria compacta"):
		return false
	if not _check(snapshot.get("round_id") == 1 and snapshot.get("cycle_number") == 2 and snapshot.get("winner_id") == 0 and snapshot.get("cycle_wins") == [0, 0], "Telemetria deve incluir rodada, ciclo, placar e empate"):
		return false
	# O centímetro exato não pode mudar o resultado por arredondamento binário.
	for leading_slot: int in [1, 2]:
		_race.restart_race(false)
		_race.start_racing()
		_race.runners[leading_slot - 1].progress_m = 100.01
		_race.runners[2 - leading_slot].progress_m = 100.0
		_race.match_time_remaining = 0.01
		_race._physics_process(0.02)
		if not _check(_race.winner == null and _race.cycle_wins == [0, 0], "100 m e 100,01 m devem empatar nas duas ordens"):
			return false
		_race.restart_race(false)
		_race.start_racing()
		_race.runners[leading_slot - 1].progress_m = 100.01001
		_race.runners[2 - leading_slot].progress_m = 100.0
		_race.match_time_remaining = 0.01
		_race._physics_process(0.02)
		if not _check(_race.winner != null and _race.winner.candidate_id == leading_slot and _race.cycle_wins[leading_slot - 1] == 1, "Vantagem de 0,01001 m deve vencer nas duas ordens"):
			return false
		_race.restart_race(false)
	return true
