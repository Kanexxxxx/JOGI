class_name BroadcastDirector
extends Node3D
## Mantém cada atleta legível sem duplicar personagens, animações ou física.
##
## Contrato: setup() após câmera e corredores estarem na árvore. O HUD deve usar
## CanvasLayer.layer >= 1; os painéis usam layer 0. Os meshes externos recebem
## as máscaras abaixo na integração. As duas câmeras compartilham o World3D.
## Cada cópia visual de Brasília possui somente cenário, sem luz ou ambiente.

signal split_changed(active: bool)

const MAIN_CULL_MASK: int = 1 | 2 | 4 | 32 | 64
const SPLIT_CULL_MASKS: Array[int] = [2 | 8 | 32, 4 | 16 | 64]
const WORLD_COPY_MASKS: Array[int] = [8, 16]

@export var split_enter_distance: float = 5.0
@export var split_leave_distance: float = 2.0
@export var split_follow_offset: Vector3 = Vector3(0.3, 1.8, -5.2)
@export var split_look_height: float = 0.65
@export var split_horizontal_fov: float = 24.0
@export var camera_smoothing: float = 10.0

var is_split: bool = false
var main_camera: RaceCamera = null
var tracked_runners: Array[CandidateRunner] = []
var split_cameras: Array[Camera3D] = []
var split_viewports: Array[SubViewport] = []
var world_copies: Array[BrasiliaWorld] = []

var _split_layer: CanvasLayer = null
var _panel_root: Control = null
var _panels: Array[SubViewportContainer] = []
var _divider: ColorRect = null
var _last_positions: Array[Vector3] = []
var _last_progress: Array[float] = []
var _configured: bool = false


func _ready() -> void:
	# Lê posições após a física dos corredores e o enquadramento principal.
	process_physics_priority = 50
	set_physics_process(false)


func _exit_tree() -> void:
	if main_camera != null and is_instance_valid(main_camera):
		main_camera.cull_mask = MAIN_CULL_MASK
	tracked_runners.clear()
	_last_positions.clear()
	_last_progress.clear()


func setup(camera: RaceCamera, runners: Array[CandidateRunner]) -> void:
	if _configured:
		push_error("BroadcastDirector.setup deve ser chamado uma única vez")
		return
	if camera == null or not is_instance_valid(camera) or runners.size() != 2:
		push_error("BroadcastDirector exige uma RaceCamera e dois corredores")
		return
	for runner: CandidateRunner in runners:
		if runner == null or not is_instance_valid(runner) or not runner.is_inside_tree():
			push_error("BroadcastDirector exige corredores ativos na árvore")
			return
	if not is_inside_tree() or not camera.is_inside_tree():
		push_error("BroadcastDirector.setup deve ocorrer após add_child")
		return
	main_camera = camera
	tracked_runners.assign(runners)
	main_camera.cull_mask = MAIN_CULL_MASK
	_build_split_views()
	_configured = true
	get_viewport().size_changed.connect(resize_split_viewports)
	resize_split_viewports()
	snap_to_runners()
	set_physics_process(true)


func resize_split_viewports() -> void:
	if _panel_root == null:
		return
	var display_size: Vector2 = get_viewport().get_visible_rect().size
	_panel_root.position = Vector2.ZERO
	_panel_root.size = display_size
	var left_width: float = floorf(display_size.x * 0.5)
	for index: int in range(_panels.size()):
		var panel: SubViewportContainer = _panels[index]
		panel.position = Vector2(0.0 if index == 0 else left_width, 0.0)
		panel.size = Vector2(left_width if index == 0 else display_size.x - left_width, display_size.y)
		# Na resolução de transmissão 1080x1920, cada vista tem 540x1920.
		# stretch mantém o SubViewport no tamanho do painel automaticamente.
	_divider.position = Vector2(left_width - 1.0, display_size.y * .30)
	_divider.size = Vector2(2.0, display_size.y * .335)


func snap_to_runners() -> void:
	if not _configured:
		return
	_last_positions.clear()
	_last_progress.clear()
	for index: int in range(tracked_runners.size()):
		var runner: CandidateRunner = tracked_runners[index]
		_last_positions.append(runner.global_position)
		_last_progress.append(runner.progress_m)
		_update_split_camera(index, 0.0, true)
	main_camera.snap_to_targets()
	_apply_distance_mode()


func _physics_process(delta: float) -> void:
	if not _configured or not _targets_valid():
		return
	var was_teleported: bool = false
	for index: int in range(tracked_runners.size()):
		var runner: CandidateRunner = tracked_runners[index]
		var expected_step: float = maxf(absf(runner.current_speed), runner.velocity.length()) * maxf(delta, 0.0)
		var teleport_threshold: float = maxf(24.0, expected_step * 4.0 + 8.0)
		if runner.progress_m + 2.0 < _last_progress[index] or runner.global_position.distance_to(_last_positions[index]) > teleport_threshold:
			was_teleported = true
		_last_positions[index] = runner.global_position
		_last_progress[index] = runner.progress_m
	if was_teleported:
		snap_to_runners()
		return
	_apply_distance_mode()
	if is_split:
		for index: int in range(tracked_runners.size()):
			_update_split_camera(index, delta, false)


func _targets_valid() -> bool:
	if main_camera == null or not is_instance_valid(main_camera):
		return false
	for runner: CandidateRunner in tracked_runners:
		if runner == null or not is_instance_valid(runner):
			return false
	return true


func _apply_distance_mode() -> void:
	var gap: float = absf(tracked_runners[0].global_position.z - tracked_runners[1].global_position.z)
	var enter_threshold: float = maxf(split_enter_distance, 0.1)
	var leave_threshold: float = clampf(split_leave_distance, 0.0, enter_threshold - 0.01)
	if not is_split and gap > enter_threshold:
		_set_split(true)
	elif is_split and gap < leave_threshold:
		_set_split(false)


func _set_split(active: bool) -> void:
	if is_split == active:
		return
	is_split = active
	if active:
		for index: int in range(split_cameras.size()):
			_update_split_camera(index, 0.0, true)
	else:
		# Ao reunir os corredores, descarta a defasagem da câmera principal.
		main_camera.snap_to_targets()
	main_camera.cull_mask = 0 if active else MAIN_CULL_MASK
	_panel_root.visible = active
	for index: int in range(split_viewports.size()):
		world_copies[index].visible = active
		split_viewports[index].render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	split_changed.emit(active)


func _update_split_camera(index: int, delta: float, snap: bool) -> void:
	var runner: CandidateRunner = tracked_runners[index]
	var camera: Camera3D = split_cameras[index]
	var desired: Vector3 = runner.global_position + split_follow_offset
	var target: Vector3 = runner.global_position + Vector3(-0.25, split_look_height, 0.0)
	if snap:
		camera.global_position = desired
	else:
		var weight: float = 1.0 - exp(-maxf(camera_smoothing, 0.1) * maxf(delta, 0.0))
		var next_position: Vector3 = camera.global_position.lerp(desired, weight)
		# O avanço Z acompanha a simulação sem atraso: a distância focal e o
		# tamanho do boneco não variam quando um presente acelera a corrida.
		next_position.z = desired.z
		camera.global_position = next_position
	if not camera.global_position.is_equal_approx(target):
		var target_basis: Basis = Transform3D.IDENTITY.looking_at(target - camera.global_position, Vector3.UP).basis
		if snap:
			camera.global_basis = target_basis
		else:
			var turn_weight: float = 1.0 - exp(-maxf(camera_smoothing, 0.1) * maxf(delta, 0.0))
			camera.global_basis = camera.global_basis.slerp(target_basis, turn_weight).orthonormalized()
	world_copies[index].global_position = Vector3(0.0, 0.0, runner.global_position.z)
	world_copies[index].set_travel_distance(0.0)


func _build_split_views() -> void:
	_split_layer = CanvasLayer.new()
	_split_layer.name = "BroadcastSplitViews"
	_split_layer.layer = 0
	add_child(_split_layer)
	_panel_root = Control.new()
	_panel_root.name = "SplitPanels"
	_panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.visible = false
	_split_layer.add_child(_panel_root)
	for index: int in range(2):
		var world_copy: BrasiliaWorld = BrasiliaWorld.new()
		world_copy.name = "BrasiliaSplit_%d" % index
		world_copy.build_lighting = false
		world_copy.visible = false
		add_child(world_copy)
		world_copy.set_render_layer(WORLD_COPY_MASKS[index])
		world_copies.append(world_copy)
		var container: SubViewportContainer = SubViewportContainer.new()
		container.name = "CandidatePanel_%d" % index
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.stretch = true
		_panel_root.add_child(container)
		_panels.append(container)
		var viewport: SubViewport = SubViewport.new()
		viewport.name = "CandidateViewport_%d" % index
		viewport.world_3d = get_viewport().find_world_3d()
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.msaa_3d = get_viewport().msaa_3d
		container.add_child(viewport)
		split_viewports.append(viewport)
		var camera: Camera3D = Camera3D.new()
		camera.name = "CandidateCamera_%d" % index
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.fov = split_horizontal_fov
		camera.near = 0.05
		camera.far = 240.0
		camera.cull_mask = SPLIT_CULL_MASKS[index]
		viewport.add_child(camera)
		camera.current = true
		split_cameras.append(camera)
	_divider = ColorRect.new()
	_divider.name = "SplitDivider"
	_divider.color = Color("ead59a")
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(_divider)
