extends SceneTree

var _scene: Node3D = null
var _camera: RaceCamera = null
var _director: BroadcastDirector = null
var _runners: Array[CandidateRunner] = []
var _ran_suite: bool = false


func _initialize() -> void:
	_scene = Node3D.new()
	root.add_child(_scene)
	for index: int in range(2):
		var runner: CandidateRunner = CandidateRunner.new()
		_scene.add_child(runner)
		runner.position = Vector3(1.4 if index == 0 else -1.4, 0.0, 0.0)
		runner.set_physics_process(false)
		_runners.append(runner)
	_camera = RaceCamera.new()
	_camera.follow_offset = Vector3(0.6, 2.0, -7.3)
	_scene.add_child(_camera)
	_director = BroadcastDirector.new()
	_scene.add_child(_director)


func _process(_delta: float) -> bool:
	if _ran_suite:
		return true
	_ran_suite = true
	_camera.fov = 45.0
	_camera.set_runners(_runners)
	_camera.set_physics_process(false)
	_director.setup(_camera, _runners)
	_director.set_physics_process(false)
	var passed: bool = _execute_test_suite()
	root.remove_child(_scene)
	_scene.free()
	_scene = null
	_runners.clear()
	print("TEST_BROADCAST_DIRECTOR_PASSED" if passed else "TEST_BROADCAST_DIRECTOR_FAILED")
	quit(0 if passed else 1)
	return true


func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("FAIL: ", message)
	return condition


func _move_gap(gap: float) -> void:
	_runners[0].global_position.z = -gap
	_runners[0].progress_m = gap
	_director._physics_process(1.0 / 60.0)


func _execute_test_suite() -> bool:
	if not _check(not _director.is_split and _camera.current and _camera.cull_mask == BroadcastDirector.MAIN_CULL_MASK, "Vista inicial deve preservar câmera principal"):
		return false
	if not _check(_director.split_viewports.size() == 2 and _director.split_cameras.size() == 2 and _director.world_copies.size() == 2, "Split deve ter duas câmeras e duas cópias somente do cenário"):
		return false
	for index: int in range(2):
		var viewport: SubViewport = _director.split_viewports[index]
		var world_copy: BrasiliaWorld = _director.world_copies[index]
		if not _check(viewport.world_3d == root.find_world_3d() and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not world_copy.visible, "Split inativo deve compartilhar World3D e suspender renderização"):
			return false
		if not _check(world_copy.find_children("*", "WorldEnvironment", true, false).is_empty() and world_copy.find_children("*", "Light3D", true, false).is_empty(), "Cópias não podem duplicar luzes ou ambiente"):
			return false
		if not _check(_director.split_cameras[index].cull_mask == BroadcastDirector.SPLIT_CULL_MASKS[index], "Câmera deve enxergar só seu atleta, cenário e obstáculos"):
			return false
	_move_gap(5.0)
	if not _check(not _director.is_split, "Distância de entrada é estritamente maior que 5m"):
		return false
	_move_gap(5.01)
	if not _check(_director.is_split and _camera.current and _camera.cull_mask == 0 and _director._panel_root.visible, "Abrir split deve manter maincam e ocultar a passagem 3D principal"):
		return false
	for index: int in range(2):
		if not _check(_director.split_viewports[index].render_target_update_mode == SubViewport.UPDATE_ALWAYS and _director.world_copies[index].visible, "Split ativo deve renderizar os dois painéis"):
			return false
	_move_gap(3.0)
	if not _check(_director.is_split, "Histerese deve impedir oscilação em 3m"):
		return false
	_move_gap(2.0)
	if not _check(_director.is_split, "Distância de saída é estritamente menor que 2m"):
		return false
	_move_gap(1.99)
	if not _check(not _director.is_split and _camera.current and _camera.cull_mask == BroadcastDirector.MAIN_CULL_MASK, "Reunião deve restaurar vista única"):
		return false
	_move_gap(10000.0)
	if not _check(_director.is_split, "Diferença enorme deve continuar legível em split"):
		return false
	for index: int in range(2):
		var runner: CandidateRunner = _runners[index]
		var camera: Camera3D = _director.split_cameras[index]
		var expected_position: Vector3 = runner.global_position + _director.split_follow_offset
		if not _check(camera.global_position.is_equal_approx(expected_position) and is_equal_approx(_director.world_copies[index].global_position.z, runner.global_position.z), "Teleporte deve reposicionar câmera e cenário imediatamente"):
			return false
		var feet: Vector2 = camera.unproject_position(runner.global_position)
		var head: Vector2 = camera.unproject_position(runner.global_position + Vector3(0.0, 2.35, 0.0))
		var viewport_size: Vector2i = _director.split_viewports[index].size
		var silhouette_ratio: float = absf(feet.y - head.y) / float(viewport_size.y)
		if not _check(silhouette_ratio > 0.24 and silhouette_ratio < 0.44 and head.y > 0.0 and feet.y < float(viewport_size.y), "Atleta deve ocupar altura legível e permanecer inteiro"):
			return false
		if not _check(head.x > 0.0 and head.x < float(viewport_size.x), "Atleta deve ficar centralizado no próprio painel"):
			return false
	# A velocidade longitudinal não deve alterar a distância de enquadramento.
	_runners[0].current_speed = 120.0
	_runners[0].global_position.z -= 2.0
	_runners[0].progress_m += 2.0
	_director._physics_process(1.0 / 60.0)
	if not _check(absf((_director.split_cameras[0].global_position.z - _runners[0].global_position.z) - _director.split_follow_offset.z) < 0.002, "Turbo deve preservar distância da câmera"):
		return false
	# Um novo ciclo volta ao zero sem uma viagem visual de dez quilômetros.
	_runners[0].reset_runner(Vector3(1.4, 0.0, 0.0))
	_runners[1].reset_runner(Vector3(-1.4, 0.0, 0.0))
	_director._physics_process(1.0 / 60.0)
	if not _check(not _director.is_split and absf(_camera.global_position.z) < 10.0, "Reset deve voltar à vista única sem interpolar distância antiga"):
		return false
	if not _check(_scene.find_children("*", "CharacterBody3D", true, false).size() == 2, "Diretor não pode clonar personagens nem sua física"):
		return false
	return true
