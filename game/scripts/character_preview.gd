extends Node3D
## Bancada local de arte; não recebe presentes nem altera a corrida principal.

const MODELS: Array[PackedScene] = [
	preload("res://assets/characters/preview-v7/lula_rig_preview_v7.glb"),
	preload("res://assets/characters/preview-v7/flavio_rig_preview_v7.glb")
]
const CLIPS: Array[String] = ["espera", "corrida", "turbo"]
var players: Array[AnimationPlayer] = []
var stage: Node3D = null
var status_label: Label = null
var capture_path: String = ""
var capture_time: float = 0.18
var selected_clip: String = "corrida"
var selected_view: String = "frente"
var benchmark_path: String = ""


func _ready() -> void:
	Engine.max_fps = 60
	# Isola esta bancada dos eventos da live.
	LiveEventBus.auto_connect = false
	LiveEventBus.set_process(false)
	LiveEventBus.queue_free()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--clip="):
			selected_clip = argument.trim_prefix("--clip=")
		elif argument.begins_with("--view="):
			selected_view = argument.trim_prefix("--view=")
		elif argument.begins_with("--time="):
			capture_time = argument.trim_prefix("--time=").to_float()
		elif argument.begins_with("--benchmark="):
			benchmark_path = argument.trim_prefix("--benchmark=")
	if (not capture_path.is_empty() and not _safe_output(capture_path, "png")) or (not benchmark_path.is_empty() and not _safe_output(benchmark_path, "json")):
		push_error("Destino deve ser um arquivo novo na pasta docs/evidencias/personagens")
		get_tree().quit(1)
		return
	_build_stage()
	_build_controls()
	_play(selected_clip)
	_view(selected_view)
	if not capture_path.is_empty():
		_capture.call_deferred()
	elif not benchmark_path.is_empty():
		_benchmark.call_deferred()


func _safe_output(path: String, extension: String) -> bool:
	var base: String = ProjectSettings.globalize_path("res://").path_join("../docs/evidencias/personagens").simplify_path()
	var normalized: String = path.replace("\\", "/").simplify_path()
	var filename: RegEx = RegEx.new()
	filename.compile("^[A-Za-z0-9][A-Za-z0-9_-]*\\." + extension + "$")
	return path.is_absolute_path() and normalized.get_base_dir().to_lower() == base.to_lower() and filename.search(normalized.get_file()) != null and not FileAccess.file_exists(normalized)


func _build_stage() -> void:
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101a2a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dbe7ff")
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	add_child(environment_node)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	key.light_energy = 1.1
	add_child(key)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, 150.0, 0.0)
	fill.light_energy = 0.35
	add_child(fill)
	stage = Node3D.new()
	stage.name = "CharacterStage"
	add_child(stage)
	for index: int in range(MODELS.size()):
		var instance: Node3D = MODELS[index].instantiate() as Node3D
		instance.position.x = -0.65 if index == 0 else 0.65
		instance.scale = Vector3.ONE * 1.65
		stage.add_child(instance)
		var player: AnimationPlayer = instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
		assert(player != null, "Modelo sem AnimationPlayer")
		players.append(player)
		for clip: StringName in player.get_animation_list():
			if clip != &"RESET":
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0.0, 1.0, 3.65)
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 45.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.85, 0.0))
	camera.current = true


func _build_controls() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	layout.offset_top = 90.0
	layout.add_theme_constant_override("separation", 18)
	layer.add_child(layout)
	var title: Label = Label.new()
	title.text = "CORRIDA DOS CANDIDATOS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	layout.add_child(title)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 25)
	layout.add_child(status_label)
	var footer: VBoxContainer = VBoxContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -380.0
	footer.offset_bottom = -75.0
	footer.add_theme_constant_override("separation", 20)
	layer.add_child(footer)
	for row_items: Array in [CLIPS, ["frente", "esquerda", "verso", "direita"]]:
		var row: HBoxContainer = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 14)
		footer.add_child(row)
		for item: String in row_items:
			var button: Button = Button.new()
			button.text = item.capitalize()
			button.custom_minimum_size = Vector2(200.0, 70.0)
			button.add_theme_font_size_override("font_size", 25)
			if CLIPS.has(item):
				button.pressed.connect(_play.bind(item))
			else:
				button.pressed.connect(_view.bind(item))
			row.add_child(button)
	var note: Label = Label.new()
	note.text = "BANCADA DE ANIMAÇÃO • VERSÃO EXPERIMENTAL\nLula  /  Flávio Bolsonaro\n60 mil triângulos • texturas 2K • 19 ossos"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 25)
	footer.add_child(note)


func _play(clip: String) -> void:
	if not CLIPS.has(clip):
		push_error("Animação de teste desconhecida")
		return
	selected_clip = clip
	for player: AnimationPlayer in players:
		assert(player.has_animation(clip), "Animação ausente: " + clip)
		player.play(clip)
	status_label.text = "Teste: " + clip.capitalize()


func _view(view: String) -> void:
	var angles: Dictionary[String, float] = {"frente": 0.0, "esquerda": 90.0, "verso": 180.0, "direita": 270.0}
	if not angles.has(view):
		return
	# Gira cada personagem em seu eixo, preservando a posição nas raias.
	for instance: Node in stage.get_children():
		(instance as Node3D).rotation_degrees.y = angles[view]


func _capture() -> void:
	for player: AnimationPlayer in players:
		player.pause()
		player.seek(capture_time, true)
	for frame: int in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result: Error = get_viewport().get_texture().get_image().save_png(capture_path)
	print("CHARACTER_PREVIEW_CAPTURE ", result, " ", capture_path)
	get_tree().quit(0 if result == OK else 1)


func _benchmark() -> void:
	await get_tree().create_timer(2.0).timeout
	var samples: Array[float] = []
	var start_us: int = Time.get_ticks_usec()
	var previous_us: int = start_us
	while Time.get_ticks_usec() - start_us < 10000000:
		await get_tree().process_frame
		var now_us: int = Time.get_ticks_usec()
		samples.append(float(now_us - previous_us) / 1000.0)
		previous_us = now_us
	var elapsed: float = float(previous_us - start_us) / 1000000.0
	samples.sort()
	var report: Dictionary = {
		"scope": "Bancada de dois personagens; sem pista, efeitos, OBS ou segunda sessão",
		"resolution": str(get_viewport().get_visible_rect().size),
		"adapter": RenderingServer.get_video_adapter_name(),
		"seconds": elapsed,
		"frames": samples.size(),
		"average_fps": float(samples.size()) / elapsed,
		"frame_ms_p95": samples[int(float(samples.size() - 1) * .95)],
		"max_fps": Engine.max_fps,
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	}
	var file: FileAccess = FileAccess.open(benchmark_path, FileAccess.WRITE)
	if file == null:
		push_error("Não foi possível salvar medição")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CHARACTER_PREVIEW_BENCHMARK ", JSON.stringify(report))
	get_tree().quit()
