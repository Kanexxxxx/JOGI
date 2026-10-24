extends SceneTree
## Importação real do GLB, dimensões, materiais e contrato de orientação.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://assets/environments/planalto/planalto_v1.glb") as PackedScene
	var passed: bool = _check(scene != null, "GLB do Planalto deve importar")
	if scene == null:
		quit(1)
		return
	var model: Node3D = scene.instantiate() as Node3D
	root.add_child(model)
	model.position = Vector3(48, 0, 0)
	var bounds: AABB = AABB()
	var has_bounds: bool = false
	var triangles: int = 0
	var surfaces: int = 0
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = node as MeshInstance3D
		var current: AABB = instance.global_transform * instance.get_aabb()
		bounds = bounds.merge(current) if has_bounds else current
		has_bounds = true
		for surface: int in range(instance.mesh.get_surface_count()):
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			surfaces += 1
	passed = _check(has_bounds and absf(bounds.position.y) < .001 and absf(bounds.size.y - 8.17) < .01, "Origem deve ficar no chão e altura em Y deve ser 8,17 m") and passed
	passed = _check(absf(bounds.size.z - 39.4) < .01 and absf(bounds.size.x - 21.725) < .01, "Largura Z e profundidade X com rampa devem corresponder ao manifesto") and passed
	passed = _check(absf(bounds.position.x - 32.025) < .01 and absf(bounds.end.x - 53.75) < .01, "Fachada e rampa devem ficar voltadas a -X ao instalar em X48") and passed
	passed = _check(triangles == 42752 and surfaces == 12, "Ativo deve manter 42.752 triângulos e doze superfícies") and passed
	print("PLANALTO_ASSET ", JSON.stringify({"triangles":triangles,"surfaces":surfaces,"minimum":bounds.position,"size":bounds.size}))
	if OS.get_cmdline_user_args().has("--planalto-capture"):
		await _capture(model)
	root.remove_child(model)
	model.free()
	await process_frame
	print("TEST_PLANALTO_ASSET_PASSED" if passed else "TEST_PLANALTO_ASSET_FAILED")
	quit(0 if passed else 1)


func _capture(model: Node3D) -> void:
	root.size = Vector2i(1600, 1000)
	model.position = Vector3.ZERO
	var environment: WorldEnvironment = WorldEnvironment.new()
	var settings: Environment = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("65b9f0")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("dcefff")
	settings.ambient_light_energy = .25
	settings.tonemap_mode = Environment.TONE_MAPPER_ACES
	settings.tonemap_exposure = .85
	environment.environment = settings
	root.add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -45, 0)
	sun.light_energy = .9
	root.add_child(sun)
	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(-43, 14, 29)
	camera.look_at(Vector3(-2, 2.5, 0))
	camera.fov = 48
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.current = true
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	var output: String = ProjectSettings.globalize_path("res://../assets/environments/planalto/v1/planalto-godot-overview.png")
	if FileAccess.file_exists(output):
		printerr("Preview anterior preservado: ", output)
	else:
		var result: Error = root.get_texture().get_image().save_png(output)
		print("PLANALTO_CAPTURE ", result)
	for node: Node in [environment, sun, camera]:
		root.remove_child(node)
		node.free()


func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("FAIL: ", message)
	return condition
