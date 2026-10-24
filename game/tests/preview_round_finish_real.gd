extends SceneTree
## Local visual proof of private celebration clips, using the approved GLBs unchanged.

var _actors: Array[HeroRunner] = []
var _world: Node3D = null
var _camera: Camera3D = null
var _started: bool = false
var _built: bool = false
var _proof_tag: String = ""
var _is_winner: bool = true


func _initialize() -> void:
	root.size = Vector2i(1200, 900)
	root.content_scale_size = Vector2i(1200, 900)
	root.title = "Prova local de comemoração — modelos originais"
	_proof_tag = "finish-real-%d" % Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--loser":
			_is_winner = false
		elif argument.begins_with("--proof-tag="):
			_proof_tag = argument.trim_prefix("--proof-tag=")
	var tag_regex: RegEx = RegEx.new()
	tag_regex.compile("^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")
	if tag_regex.search(_proof_tag) == null:
		quit(1)
		return
	_build.call_deferred()


func _build() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("234a77")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d8eaff")
	environment.environment.ambient_light_energy = .65
	_world.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, 155, 0)
	light.light_energy = 1.15
	_world.add_child(light)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 1.4, -5.7)
	_camera.fov = 40.0
	_world.add_child(_camera)
	_camera.look_at(Vector3(0, 1.35, 0))
	_camera.current = true
	for index: int in range(2):
		var actor: HeroRunner = HeroRunner.new()
		actor.hero_scene = load("res://assets/characters/api-cape-v13/%s_run.glb" % ("lula" if index == 0 else "flavio")) as PackedScene
		actor.idle_scene = load("res://assets/characters/idle-clips/%s_idle.glb" % ("lula" if index == 0 else "flavio")) as PackedScene
		_world.add_child(actor)
		actor.configure(index + 1, "Lula" if index == 0 else "Flávio", Color.RED, Color.WHITE, Vector3(1.2 if index == 0 else -1.2, 0, 0), 100.0)
		actor.set_process(false)
		actor.set_physics_process(false)
		_actors.append(actor)
	_built = true


func _process(_delta: float) -> bool:
	if not _started and _built:
		_started = true
		_capture.call_deferred()
	return false


func _capture() -> void:
	for actor: HeroRunner in _actors:
		actor.presentation.set_process(false)
		actor.presentation.update_motion(true, 12, 12, false, false, false, 1.0)
		actor.play_round_finish(_is_winner)
		actor.presentation._process(.86)
		actor.presentation.animation_player.advance(.3)
	var output: String = ProjectSettings.globalize_path("res://").path_join("../docs/evidencias/personagens").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	for index: int in range(3):
		var time: float = [.7, 1.4, 3.4][index]
		for actor: HeroRunner in _actors:
			var player: AnimationPlayer = actor.presentation.animation_player
			player.seek(time, true)
			player.pause()
		await RenderingServer.frame_post_draw
		var path: String = output.path_join("%s-front-%d.png" % [_proof_tag, index])
		if FileAccess.file_exists(path):
			printerr("Prova exige arquivo novo: ", path)
			quit(1)
			return
		root.get_texture().get_image().save_png(path)
	_camera.position = Vector3(0, 1.4, 5.7)
	_camera.look_at(Vector3(0, 1.35, 0))
	await RenderingServer.frame_post_draw
	var back: String = output.path_join("%s-back.png" % _proof_tag)
	if FileAccess.file_exists(back):
		quit(1)
		return
	root.get_texture().get_image().save_png(back)
	for actor: HeroRunner in _actors:
		actor.queue_free()
	_actors.clear()
	_world.queue_free()
	await process_frame
	print("ROUND_FINISH_REAL_VISUAL_CAPTURED")
	quit(0)
