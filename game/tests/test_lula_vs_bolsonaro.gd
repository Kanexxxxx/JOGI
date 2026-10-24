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
		print("TEST_LULA_VS_BOLSONARO_PASSED")
		quit(0)
	else:
		printerr("TEST_LULA_VS_BOLSONARO_FAILED")
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

	# 1. Validação de elenco exclusivo: Lula e Bolsonaro (2 corredores)
	if _race.runners.size() != 2:
		printerr("FAIL: Esperado exatamente 2 corredores (Lula e Bolsonaro), obtido: ", _race.runners.size())
		return false

	var lula: CandidateRunner = _race.runners[0]
	var bolso: CandidateRunner = _race.runners[1]

	if lula.candidate_id != 1 or lula.candidate_name != "LULA":
		printerr("FAIL: Corredor 1 deve ser LULA, obtido: ", lula.candidate_name)
		return false

	if bolso.candidate_id != 2 or bolso.candidate_name != "FLÁVIO BOLSONARO":
		printerr("FAIL: Corredor 2 deve ser FLÁVIO BOLSONARO, obtido: ", bolso.candidate_name)
		return false

	# 2. Verificação de remoção de Label3D nos corredores (zero poluição na pista)
	for r: CandidateRunner in _race.runners:
		for child: Node in r.find_children("*", "Label3D", true, false):
			printerr("FAIL: Encontrado Label3D indevido no corredor: ", child.name)
			return false

	# 3. Largada e movimentação contínua
	_race.start_racing()
	if _race.current_state != RaceMain.RaceState.RACING:
		printerr("FAIL: Estado da corrida deveria ser RACING (2)")
		return false

	# Simula 60 frames (~1.0s de corrida)
	for _i: int in range(60):
		_race._physics_process(0.0166)
		lula._physics_process(0.0166)
		bolso._physics_process(0.0166)

	if lula.progress_m <= 0.0 or bolso.progress_m <= 0.0:
		printerr("FAIL: Ambos os candidatos devem acumular progresso em metros")
		return false

	# 4. Aplicação de Turbo para Lula
	var prev_lula_speed: float = lula.current_speed
	_race.trigger_candidate_boost(1, 6.0, 3.0, "Militancia_Lula")
	if lula.boost_timer <= 0.0 or lula.current_speed <= prev_lula_speed:
		printerr("FAIL: Turbo deve acelerar Lula")
		return false

	# Simula mais 60 frames com Lula acelerado
	for _i: int in range(60):
		_race._physics_process(0.0166)
		lula._physics_process(0.0166)
		bolso._physics_process(0.0166)

	if lula.progress_m <= bolso.progress_m:
		printerr("FAIL: Lula acelerado deve estar à frente de Bolsonaro")
		return false

	# 5. Ataque político: spawn de processos na raia de Bolsonaro causando tropeço
	var obs: Area3D = _race.spawn_political_obstacle(2, "pilha_documentos", "Torcida_Lula")
	if obs == null:
		printerr("FAIL: spawn_political_obstacle retornou null")
		return false

	# Posiciona Bolsonaro sobre o obstáculo e dispara colisão
	bolso.global_position = obs.global_position
	var stumbled: bool = bolso.apply_stumble(1.2, 0.38)
	if not stumbled or bolso.stumble_timer <= 0.0:
		printerr("FAIL: Bolsonaro sem escudo deve tropeçar na pilha de processos")
		return false

	# 6. Teste de defesa: Escudo absorve ataque político
	_race.trigger_candidate_shield(2, 5.0, "Patriotas")
	if bolso.shield_timer <= 0.0:
		printerr("FAIL: Escudo de Bolsonaro deve estar ativo")
		return false

	# Novo obstáculo com escudo ativo
	var obs_shield: Area3D = _race.spawn_political_obstacle(2, "pilha_documentos", "Adversario")
	bolso.global_position = obs_shield.global_position
	var stumbled_with_shield: bool = bolso.apply_stumble(1.2, 0.38)
	if stumbled_with_shield:
		printerr("FAIL: Escudo deveria ter absorvido o impacto do obstáculo")
		return false

	# 7. Telemetria com Vantagem Relativa (Tug-of-War)
	var snap: Dictionary = _race.get_telemetry_snapshot()
	if snap.get("advantage_leader") != "lula":
		printerr("FAIL: Telemetria deve indicar lula na liderança, obtido: ", snap.get("advantage_leader"))
		return false

	if float(snap.get("advantage_meters", 0.0)) <= 0.0:
		printerr("FAIL: Vantagem em metros deve ser positiva")
		return false

	# 8. Término por cronômetro e apuração do vencedor
	_race.match_time_remaining = 0.01
	_race._physics_process(0.02)

	if _race.current_state != RaceMain.RaceState.PHOTO_FINISH:
		printerr("FAIL: Corrida deve transicionar para PHOTO_FINISH ao zerar o tempo")
		return false

	if _race.winner == null or _race.winner.candidate_id != 1:
		printerr("FAIL: Vencedor por maior distância percorrida deveria ser Lula")
		return false

	print("ASSERT_OK: Todos os testes de Lula vs Bolsonaro (sátira 2 corredores, pista infinita, ataques, escudos e vitória por tempo) passaram!")
	return true


func _cleanup() -> void:
	if _race != null:
		_race.queue_free()
		_race = null

