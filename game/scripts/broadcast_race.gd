extends RaceMain
## Direção de transmissão sobre a simulação real de dez minutos.

const LULA_HERO: PackedScene = preload("res://assets/characters/api-cape-v13/lula_run.glb")
const FLAVIO_HERO: PackedScene = preload("res://assets/characters/api-cape-v13/flavio_run.glb")
const LULA_IDLE: PackedScene = preload("res://assets/characters/idle-clips/lula_idle.glb")
const FLAVIO_IDLE: PackedScene = preload("res://assets/characters/idle-clips/flavio_idle.glb")
const CAMERA_SCRIPT: Script = preload("res://scripts/broadcast_camera.gd")
var world_visual: BrasiliaWorld = null
var broadcast_hud: BroadcastHUD = null
var broadcast_director: BroadcastDirector = null
var _capture_path: String = ""
var _test_elapsed: float = 0.0
var _test_duration: float = 0.0
var _frame_times_ms: Array[float] = []
var _capture_started: bool = false
var _split_keys: Array[DirectionalLight3D] = []
var _split_fills: Array[DirectionalLight3D] = []


func _ready() -> void:
	Engine.max_fps = 60
	super._ready()
	broadcast_director = BroadcastDirector.new()
	broadcast_director.name = "BroadcastDirector"
	add_child(broadcast_director)
	broadcast_director.setup(race_camera, runners)
	_build_split_lights()
	broadcast_director.split_changed.connect(_set_split_lighting)
	world_visual.set_round_metadata(round_metadata)
	_sync_split_lights()
	round_changed.connect(_on_visual_round_changed)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			_capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--measure-seconds="):
			_test_duration = clampf(argument.trim_prefix("--measure-seconds=").to_float(), 3.0, 60.0)
		elif argument.begins_with("--preview-round=") and "--asset-preview" in OS.get_cmdline_user_args():
			current_round = clampi(argument.trim_prefix("--preview-round=").to_int(), 1, 50)
			_select_round_metadata()
			world_visual.set_round_metadata(round_metadata)
			_sync_split_lights()
	if not _capture_path.is_empty() and not _safe_capture(_capture_path):
		push_error("Captura exige PNG novo na pasta de evidências de Brasília")
		get_tree().quit(1)
		return
	if "--idle-preview" in OS.get_cmdline_user_args():
		state_timer = 300.0
	elif "--asset-preview" in OS.get_cmdline_user_args():
		start_race_immediately()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--gap-preview=") and "--asset-preview" in OS.get_cmdline_user_args():
			var gap: float = clampf(argument.trim_prefix("--gap-preview=").to_float(), 0.0, 2000.0)
			runners[0].global_position.z -= gap
			runners[0]._update_progress()
			broadcast_director.snap_to_runners()
	if not _capture_path.is_empty() and _test_duration <= 0.0:
		_test_duration = 4.0


func _on_visual_round_changed(_round_id: int, _cycle_id: int, metadata: Dictionary) -> void:
	world_visual.set_round_metadata(metadata)
	_sync_split_lights()


func _build_split_lights() -> void:
	# Cada vista tem seus próprios emissores e sombras. Máscaras impedem que as
	# cópias da arena projetem sombras sobre o atleta da outra câmera.
	for index: int in range(2):
		var mask: int = BroadcastDirector.SPLIT_CULL_MASKS[index]
		var key: DirectionalLight3D = DirectionalLight3D.new()
		key.name = "SplitKey_%d" % index
		key.light_cull_mask = mask
		key.shadow_caster_mask = mask
		key.layers = BroadcastDirector.WORLD_COPY_MASKS[index]
		key.shadow_enabled = true
		key.directional_shadow_max_distance = 100.0
		add_child(key)
		_split_keys.append(key)
		var fill: DirectionalLight3D = DirectionalLight3D.new()
		fill.name = "SplitFill_%d" % index
		fill.light_cull_mask = mask
		fill.shadow_caster_mask = mask
		fill.layers = BroadcastDirector.WORLD_COPY_MASKS[index]
		add_child(fill)
		_split_fills.append(fill)
	_set_split_lighting(false)


func _sync_split_lights() -> void:
	for index: int in range(_split_keys.size()):
		_split_keys[index].rotation = world_visual.sun.rotation
		_split_keys[index].light_color = world_visual.sun.light_color
		_split_keys[index].light_energy = world_visual.sun.light_energy
		_split_fills[index].rotation = world_visual.fill_light.rotation
		_split_fills[index].light_color = world_visual.fill_light.light_color
		_split_fills[index].light_energy = world_visual.fill_light.light_energy


func _set_split_lighting(active: bool) -> void:
	world_visual.sun.visible = not active
	world_visual.fill_light.visible = not active
	for index: int in range(_split_keys.size()):
		_split_keys[index].visible = active
		_split_fills[index].visible = active


func _setup_environment_and_lights() -> void:
	world_visual = BrasiliaWorld.new()
	world_visual.name = "BrasiliaWorld"
	add_child(world_visual)


func _setup_track_geometry() -> void:
	super._setup_track_geometry()
	# Preserva colisões e reciclagem. A superfície visível pertence à arena.
	for chunk: Node3D in _track_chunks:
		chunk.visible = false


func _get_lane_x(index: int, _total: int = 2) -> float:
	return 1.25 if index == 0 else -1.25


func _setup_runners() -> void:
	_runners_root = Node3D.new()
	_runners_root.name = "RunnersRoot"
	add_child(_runners_root)
	for index: int in range(CANDIDATE_DEFS.size()):
		var definition: Dictionary = CANDIDATE_DEFS[index]
		var runner: HeroRunner = HeroRunner.new()
		runner.name = "CandidateRunner_%d" % int(definition["id"])
		runner.hero_scene = LULA_HERO if index == 0 else FLAVIO_HERO
		runner.idle_scene = LULA_IDLE if index == 0 else FLAVIO_IDLE
		runner.base_speed = float(definition["speed"])
		_runners_root.add_child(runner)
		runner.configure(int(definition["id"]), String(definition["name"]), Color(String(definition["color"])), Color(String(definition["text"])), Vector3(_get_lane_x(index), 0, 0), track_length)
		runners.append(runner)
		_set_mesh_layers(runner, 2 if index == 0 else 4)


func _set_mesh_layers(root_node: Node, mask: int) -> void:
	for child: Node in root_node.find_children("*", "VisualInstance3D", true, false):
		(child as VisualInstance3D).layers = mask


func spawn_political_obstacle(target_slot: int, obstacle_type: String = "pilha_documentos", voter_name: String = "Oponente") -> Area3D:
	var obstacle: Area3D = super.spawn_political_obstacle(target_slot, obstacle_type, voter_name)
	if obstacle != null:
		_set_mesh_layers(obstacle, 32 if target_slot == 1 else 64)
	return obstacle


func _setup_camera() -> void:
	race_camera = CAMERA_SCRIPT.new() as RaceCamera
	race_camera.name = "RaceCamera"
	race_camera.follow_offset = Vector3(.35, 2.0, -6.2)
	race_camera.look_target_y = 1.1
	add_child(race_camera)
	race_camera.fov = 45.0
	race_camera.set_runners(runners)


func _setup_hud() -> void:
	broadcast_hud = BroadcastHUD.new()
	broadcast_hud.name = "BroadcastHUD"
	add_child(broadcast_hud)
	_hud_layer = broadcast_hud
	broadcast_hud.layer = 1


func restart_race(p_skip_lobby: bool = false) -> void:
	super.restart_race(p_skip_lobby)
	if race_camera != null:
		race_camera.snap_to_targets()
	if broadcast_director != null:
		broadcast_director.snap_to_runners()


func set_race_paused(paused: bool) -> void:
	super.set_race_paused(paused)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo:
			match key.keycode:
				KEY_F1:
					race_camera.call("set_view", "frente")
				KEY_F2:
					race_camera.call("set_view", "verso")
				KEY_F3:
					race_camera.call("set_view", "perfil")
				KEY_P:
					set_race_paused(not race_paused)
	super._unhandled_input(event)


func _update_hud() -> void:
	if broadcast_hud == null or runners.size() < 2:
		return
	var phase: String = ""
	match current_state:
		RaceState.LOBBY_VOTACAO:
			phase = "ESCOLHA SUA EQUIPE · LARGADA EM %d" % ceili(state_timer)
		RaceState.COUNTDOWN:
			phase = "PREPARAR · %d" % maxi(1, ceili(countdown_remaining))
		RaceState.PHOTO_FINISH:
			phase = "TEMPO ESGOTADO · RESULTADO DA RODADA"
		RaceState.PODIO:
			phase = "EMPATE NA RODADA" if winner == null else "VITÓRIA DE " + winner.candidate_name
	if race_paused:
		phase = "CORRIDA PAUSADA"
	broadcast_hud.apply_state({
		"round": current_round, "cycle": cycle_number,
		"round_name": round_metadata.get("name", "Brasília"),
		"remaining": match_time_remaining, "lula_m": runners[0].progress_m,
		"flavio_m": runners[1].progress_m, "wins": cycle_wins,
		"phase": phase, "mode": "TESTE LOCAL"
	})


func _process(delta: float) -> void:
	if world_visual != null and race_camera != null:
		world_visual.position.z = race_camera.focus_point.z
	if _test_duration <= 0.0:
		return
	_test_elapsed += delta
	# Descarta aquecimento para não misturar importação/carregamento e medição.
	if _test_elapsed > 2.0:
		_frame_times_ms.append(delta * 1000.0)
	if _test_elapsed >= _test_duration and not _capture_started:
		_capture_started = true
		_finish_measurement.call_deferred()


func _safe_capture(path: String) -> bool:
	var base: String = ProjectSettings.globalize_path("res://").path_join("../docs/evidencias/brasilia").simplify_path()
	var normalized: String = path.replace("\\", "/").simplify_path()
	var filename: RegEx = RegEx.new()
	filename.compile("^[A-Za-z0-9][A-Za-z0-9_-]*\\.png$")
	return path.is_absolute_path() and normalized.get_base_dir().to_lower() == base.to_lower() and filename.search(normalized.get_file()) != null and not FileAccess.file_exists(normalized)


func _finish_measurement() -> void:
	await RenderingServer.frame_post_draw
	var result: Error = OK
	if not _capture_path.is_empty():
		result = get_viewport().get_texture().get_image().save_png(_capture_path)
	_frame_times_ms.sort()
	var mean: float = 0.0
	for frame_ms: float in _frame_times_ms:
		mean += frame_ms
	mean /= maxf(1.0, float(_frame_times_ms.size()))
	var p95: float = _frame_times_ms[mini(_frame_times_ms.size() - 1, int(float(_frame_times_ms.size()) * .95))] if not _frame_times_ms.is_empty() else 0.0
	print("BROADCAST_MEASUREMENT ", JSON.stringify({"frames": _frame_times_ms.size(), "mean_ms": mean, "p95_ms": p95, "fps_mean": 1000.0 / maxf(mean, .001), "viewport": {"width": get_viewport().get_visible_rect().size.x, "height": get_viewport().get_visible_rect().size.y}, "split": broadcast_director.is_split, "lula_m": runners[0].progress_m, "flavio_m": runners[1].progress_m, "remaining": match_time_remaining, "capture_error": result}))
	get_tree().quit(0 if result == OK else 1)
