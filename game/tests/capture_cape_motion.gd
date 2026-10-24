extends SceneTree
## GPU comparison: exactly the same skeleton pose, two explicit cape phases.

func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1024, 1024)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("165299")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = .7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	viewport.add_child(environment_node)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, .0)
	light.light_energy = 2.0
	viewport.add_child(light)
	var camera: Camera3D = Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(.0, 2.0, 6.5)
	camera.look_at(Vector3(.0, 1.2, .0))
	camera.fov = 40
	var presentations: Array[CandidatePresentation] = []
	for slot: int in range(2):
		var character: String = "lula" if slot == 0 else "flavio"
		var presentation: CandidatePresentation = CandidatePresentation.new()
		presentation.hero_scene = load("res://assets/characters/api-cape-v13/" + character + "_run.glb") as PackedScene
		presentation.target_height = 2.35
		presentation.position.x = -1.2 if slot == 0 else 1.2
		viewport.add_child(presentation)
		presentation.set_process(false)
		presentation.animation_player.active = false
		presentation.animation_player.seek(.25, true)
		presentation._cape_motion._amplitude = .150
		presentations.append(presentation)
	var output: String = ProjectSettings.globalize_path("res://../docs/evidencias/estadio/")
	for frame: int in range(3):
		for presentation: CandidatePresentation in presentations:
			presentation._cape_motion._phase = .0 if frame == 0 else PI
			presentation._cape_motion._write_uniforms()
			if frame == 2:
				presentation._cape_motion.step(3.0, true, 2.0, true, false, true, false, false, 1.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image()
		var path: String = output.path_join("capas-ondas-v2-mesma-pose-" + str(frame) + ".png")
		var result: Error = image.save_png(path)
		print("CAPE_GPU_CAPTURE ", path, " ", result)
	root.remove_child(viewport)
	viewport.free()
	await process_frame
	quit()
