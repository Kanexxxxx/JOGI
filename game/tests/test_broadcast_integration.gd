extends SceneTree

var _race: RaceMain = null


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("FAIL: ", message)
	return condition


func _run() -> void:
	_race = (load("res://scenes/main/broadcast_race.tscn") as PackedScene).instantiate() as RaceMain
	root.add_child(_race)
	var passed: bool = _suite()
	root.remove_child(_race)
	_race.free()
	_race = null
	print("TEST_BROADCAST_INTEGRATION_PASSED" if passed else "TEST_BROADCAST_INTEGRATION_FAILED")
	quit(0 if passed else 1)


func _suite() -> bool:
	var hud: BroadcastHUD = _race.get("broadcast_hud") as BroadcastHUD
	var director: BroadcastDirector = _race.get("broadcast_director") as BroadcastDirector
	var world: BrasiliaWorld = _race.get("world_visual") as BrasiliaWorld
	if not _check(_race.runners.size() == 2 and _race.runners[0] is HeroRunner and _race.runners[1] is HeroRunner and hud.layer == 1, "Corrida real deve conectar heróis e HUD por cima das vistas"):
		return false
	for runner: CandidateRunner in _race.runners:
		var hero: HeroRunner = runner as HeroRunner
		if not _check(hero.presentation.idle_clip == &"presentation/idle" and hero.presentation.run_clip == &"presentation/run", "Ambos devem ter espera e corrida reais"):
			return false
	_race.set_race_paused(true)
	if not _check(hud.advantage_label.text == "CORRIDA PAUSADA" and not _race.runners[0].is_physics_processing(), "Pausa deve informar imediatamente no HUD e parar física"):
		return false
	_race.set_race_paused(false)
	if not _check(not hud.advantage_label.text.contains("PAUSADA"), "Retomada deve remover aviso de pausa"):
		return false
	_race.runners[0].global_position.z = -10000.0
	_race.runners[0]._update_progress()
	director.snap_to_runners()
	if not _check(director.is_split and not world.sun.visible and not world.fill_light.visible, "Split deve isolar luzes e sombras do mundo principal"):
		return false
	var keys: Array = _race.get("_split_keys")
	for index: int in range(keys.size()):
		var key: DirectionalLight3D = keys[index] as DirectionalLight3D
		if not _check(key.visible and key.shadow_caster_mask == BroadcastDirector.SPLIT_CULL_MASKS[index] and key.light_cull_mask == BroadcastDirector.SPLIT_CULL_MASKS[index] and (key.layers & BroadcastDirector.SPLIT_CULL_MASKS[index]) != 0, "Luz deve ser visível na câmera, com iluminação e sombras isoladas por raia"):
			return false
	var obstacle: Area3D = _race.spawn_political_obstacle(1, "pilha_documentos", "Teste local")
	if not _check(obstacle != null and (obstacle.get_node("DocumentStackMesh") as MeshInstance3D).layers == 32, "Obstáculo deve aparecer na vista de seu alvo"):
		return false
	_race.race_camera.position.z = -9990.0
	_race.restart_race(false)
	if not _check(not director.is_split and absf(_race.race_camera.position.z) < 10.0 and world.sun.visible and not (keys[0] as DirectionalLight3D).visible, "Reinício deve reposicionar câmera e restaurar luzes no mesmo instante"):
		return false
	var first_color: Color = world.sky_material.sky_top_color
	_race.start_race_immediately()
	_race.runners[0].progress_m = 200.0
	_race.runners[1].progress_m = 100.0
	_race._physics_process(600.0)
	_race._physics_process(_race.photo_finish_duration)
	if not _check(hud.advantage_label.text == "VITÓRIA DE LULA" and _race.cycle_wins == [1, 0], "Pódio deve exibir o resultado real"):
		return false
	_race._physics_process(_race.podium_duration)
	if not _check(_race.current_round == 2 and world.sky_material.sky_top_color != first_color and absf(_race.race_camera.position.z) < 10.0, "Próxima rodada deve trocar atmosfera e reposicionar câmera"):
		return false
	if not _check(_race.find_children("*", "WorldEnvironment", true, false).size() == 1, "Vistas divididas não podem criar ambientes globais concorrentes"):
		return false
	return true
