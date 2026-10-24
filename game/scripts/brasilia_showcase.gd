extends Node3D
## Direção visual da arena. Não simula presentes nem resultados de uma live.

@export var lula_model: PackedScene = preload("res://assets/characters/api-cape-v13/lula_run.glb")
@export var flavio_model: PackedScene = preload("res://assets/characters/api-cape-v13/flavio_run.glb")
const WORLD_SCRIPT: Script = preload("res://scripts/brasilia_world.gd")
const HUD_SCRIPT: Script = preload("res://scripts/broadcast_hud.gd")
var camera: Camera3D = null
var hud: BroadcastHUD = null
var world_visual: BrasiliaWorld = null
var actors: Array[Node3D] = []
var players: Array[AnimationPlayer] = []
var elapsed: float = 0.0
var capture_path: String = ""
var selected_view: String = "frente"


func _ready() -> void:
	Engine.max_fps = 60
	LiveEventBus.auto_connect = false
	LiveEventBus.set_process(false)
	LiveEventBus.queue_free()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--view="):
			selected_view = argument.trim_prefix("--view=")
	if not capture_path.is_empty() and not _safe_capture(capture_path):
		push_error("Captura exige arquivo PNG novo na pasta de evidências de Brasília")
		get_tree().quit(1)
		return
	world_visual = WORLD_SCRIPT.new() as BrasiliaWorld
	add_child(world_visual)
	# A câmera frontal olha para +Z: +X ocupa a esquerda da transmissão.
	_add_actor(lula_model, 1.4)
	_add_actor(flavio_model, -1.4)
	_build_camera()
	# Instancia o script como nó, mantendo o componente reutilizável na corrida.
	hud = HUD_SCRIPT.new() as BroadcastHUD
	add_child(hud)
	hud.apply_state({"round": 1, "round_name": "Primeiro Sol", "remaining": 600.0, "preview": true})
	_set_view(selected_view)
	if not capture_path.is_empty():
		_capture.call_deferred()


func _safe_capture(path: String) -> bool:
	var base: String = ProjectSettings.globalize_path("res://").path_join("../docs/evidencias/brasilia").simplify_path()
	var normalized: String = path.replace("\\", "/").simplify_path()
	var filename: RegEx = RegEx.new()
	filename.compile("^[A-Za-z0-9][A-Za-z0-9_-]*\\.png$")
	return path.is_absolute_path() and normalized.get_base_dir().to_lower() == base.to_lower() and filename.search(normalized.get_file()) != null and not FileAccess.file_exists(normalized)


func _add_actor(packed: PackedScene, lane_x: float) -> void:
	if packed == null:
		return
	var model: Node3D = packed.instantiate() as Node3D
	add_child(model)
	var bounds: AABB = _bounds(model)
	var scale_factor: float = 2.35 / maxf(bounds.size.y, .001)
	model.scale = Vector3.ONE * scale_factor
	model.position = Vector3(lane_x, -bounds.position.y * scale_factor + .015, 0)
	model.rotation.y = PI
	actors.append(model)
	for child: Node in model.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).lod_bias = 128.0
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		for animation: StringName in player.get_animation_list():
			if animation != &"RESET":
				player.get_animation(animation).loop_mode = Animation.LOOP_LINEAR
				player.play(animation)
				player.seek(0.0, true)
				players.append(player)
				break
	# Certos retargets mantêm a corrida parada com um deslocamento constante da raiz.
	# Corrige a origem horizontal pela pose inicial, sem alterar rosto, malha ou clip.
	if player != null:
		for node: Node in model.find_children("*", "Skeleton3D", true, false):
			var skeleton: Skeleton3D = node as Skeleton3D
			for bone: int in range(skeleton.get_bone_count()):
				if skeleton.get_bone_parent(bone) == -1:
					var offset: Vector3 = skeleton.get_bone_global_pose(bone).origin - skeleton.get_bone_global_rest(bone).origin
					offset.y = 0.0
					var relative: Transform3D = model.global_transform.affine_inverse() * skeleton.global_transform
					model.position -= model.basis * (relative.basis * offset)
					break


func _bounds(root_node: Node3D) -> AABB:
	var result: AABB = AABB()
	var initialized: bool = false
	for child: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = child as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var relative: Transform3D = root_node.global_transform.affine_inverse() * mesh_node.global_transform
		var box: AABB = relative * mesh_node.mesh.get_aabb()
		result = result.merge(box) if initialized else box
		initialized = true
	return result


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 45.0
	camera.near = .1
	camera.far = 300.0
	add_child(camera)
	camera.current = true


func _set_view(view: String) -> void:
	if view == "verso":
		camera.position = Vector3(-.6, 2.0, 7.3)
	elif view == "perfil":
		camera.position = Vector3(7.3, 2.1, -2.5)
	else:
		camera.position = Vector3(.6, 2.0, -7.3)
	camera.look_at(Vector3(0.0, 1.1, 0.0))


func _process(delta: float) -> void:
	elapsed += delta
	if world_visual != null:
		world_visual.set_travel_distance(elapsed * 12.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo:
			match key.keycode:
				KEY_F1:
					_set_view("frente")
				KEY_F2:
					_set_view("verso")
				KEY_F3:
					_set_view("perfil")


func _capture() -> void:
	await get_tree().create_timer(2.0).timeout
	for player: AnimationPlayer in players:
		player.pause()
		player.seek(.2, true)
	for frame_index: int in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result: Error = get_viewport().get_texture().get_image().save_png(capture_path)
	print("BRASILIA_CAPTURE ", result, " ", capture_path)
	get_tree().quit(0 if result == OK else 1)
