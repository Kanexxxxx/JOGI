extends Node3D
## Cena isolada para avaliação de cenário. Não participa da corrida real.

var world: StadiumWorld = null
var elapsed: float = 0.0
var capture_mode: String = ""


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--stadium-capture="):
			capture_mode = argument.trim_prefix("--stadium-capture=")
	if not capture_mode.is_empty() and capture_mode not in ["dia-v1", "tarde-v1", "noite-v1", "dia-v2", "dia-v3", "dia-v4"]:
		get_tree().quit(2)
		return
	world = StadiumWorld.new()
	add_child(world)
	world.set_round_metadata({"preset_id": 9 if capture_mode == "noite-v1" else (6 if capture_mode == "tarde-v1" else 2)})
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 11.0
	camera.position = Vector3(0, 6.8, 12)
	add_child(camera)
	camera.look_at(Vector3(0, 1, 0))
	camera.current = true
	print("STADIUM_BUDGET ", JSON.stringify(world.get_visual_budget()))
	if not capture_mode.is_empty():
		_capture.call_deferred()


func _process(delta: float) -> void:
	elapsed += delta
	if world != null:
		world.set_travel_distance(elapsed * 5.0)


func _capture() -> void:
	var path: String = ProjectSettings.globalize_path("res://").path_join("../docs/evidencias/estadio").simplify_path()
	DirAccess.make_dir_recursive_absolute(path)
	path = path.path_join("arena-%s.png" % capture_mode)
	if FileAccess.file_exists(path):
		push_error("A captura existente foi preservada: " + path)
		get_tree().quit(2)
		return
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	var result: Error = get_viewport().get_texture().get_image().save_png(path)
	print("STADIUM_CAPTURE ", result, " ", path)
	get_tree().quit(0 if result == OK else 1)
