extends SceneTree
## Pools fixos, direção dos rastros, pausa e rejeição de entrada inválida.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var passed: bool = true
	var effects: StadiumEffects = StadiumEffects.new()
	root.add_child(effects)
	effects.set_process(false)
	var budget: Dictionary = effects.get_effect_budget()
	passed = _check(int(budget["particle_capacity"]) == 368 and int(budget["emitter_count"]) == 7 and int(budget["maximum_draw_passes"]) == 7, "Orçamento fixo: 368 partículas, sete emissores e sete passes máximos") and passed
	passed = _check(not effects._party.emitting and not effects._boosts[0].emitting and not effects._boosts[1].emitting, "Sem eventos não deve existir chuva ou rastro contínuo") and passed
	var stage: Vector3 = Vector3(1.0, .05, 1.45)
	effects.set_runner_state(1, stage, true, true, true)
	passed = _check(effects._boosts[0].emitting and not effects._boosts[1].emitting, "Turbo deve acender somente a equipe correta") and passed
	passed = _check(effects._boosts[0].global_position.x < stage.x and is_equal_approx(effects._boosts[0].global_position.z, stage.z), "Rastro deve ficar atrás em -X, sem atravessar a raia") and passed
	var process_material: ParticleProcessMaterial = effects._boosts[0].process_material as ParticleProcessMaterial
	passed = _check(process_material.direction.x < -.9 and process_material.gravity.y < 0.0, "Movimento das partículas deve seguir para trás e cair suavemente") and passed
	var before_position: Vector3 = effects._positions[0]
	effects.set_runner_state(0, Vector3.ZERO, true, true, true)
	effects.set_runner_state(1, Vector3(INF, 0, 0), true, true, true)
	passed = _check(effects._positions[0] == before_position, "Equipe inválida e posição não finita devem ser rejeitadas") and passed
	var resources: Array[int] = []
	for emitter: GPUParticles3D in effects._all_emitters():
		resources.append(emitter.get_instance_id())
	var before_nodes: int = effects.get_child_count()
	for iteration: int in range(1000):
		var slot: int = iteration % 2 + 1
		effects.set_runner_state(slot, Vector3(0, 0, 1.45 if slot == 1 else -1.45), iteration % 3 == 0, iteration % 5 == 0, iteration % 7 == 0)
		effects.trigger_moment("impact", slot)
		effects.trigger_moment("super_turbo", slot)
		effects.trigger_moment("podium", slot)
		effects._process(.016)
	passed = _check(effects.get_child_count() == before_nodes and int(effects.get_effect_budget()["particle_capacity"]) == 368, "Mil eventos devem reutilizar os mesmos pools sem criar nós ou aumentar capacidade") and passed
	var after_resources: Array[int] = []
	for emitter: GPUParticles3D in effects._all_emitters():
		after_resources.append(emitter.get_instance_id())
	passed = _check(resources == after_resources, "Emissores devem conservar identidade durante rajadas") and passed
	effects.set_paused(true)
	var clock_before: float = effects._clock
	var gates_before: Dictionary = effects._next_moment.duplicate()
	effects.trigger_moment("shield", 1)
	effects._process(10.0)
	passed = _check(is_equal_approx(effects._clock, clock_before) and effects._next_moment == gates_before, "Pausa deve congelar o relógio e rejeitar novas rajadas") and passed
	for emitter: GPUParticles3D in effects._all_emitters():
		passed = _check(is_zero_approx(emitter.speed_scale), "Cada emissor deve congelar em pausa") and passed
	effects.set_paused(false)
	effects.set_render_layer(4)
	for emitter: GPUParticles3D in effects._all_emitters():
		passed = _check(is_equal_approx(emitter.speed_scale, 1.0) and emitter.layers == 4, "Retomada e camada de câmera devem alcançar todos os emissores") and passed
	effects.clear_effects()
	for emitter: GPUParticles3D in effects._all_emitters():
		passed = _check(not emitter.emitting, "Reinício deve parar todas as emissões") and passed
	root.remove_child(effects)
	effects.free()
	await process_frame
	print("TEST_STADIUM_EFFECTS_PASSED" if passed else "TEST_STADIUM_EFFECTS_FAILED")
	quit(0 if passed else 1)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("FAIL: ", message)
	return condition
