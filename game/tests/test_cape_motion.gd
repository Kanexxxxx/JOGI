extends SceneTree

var _presentations: Array[CandidatePresentation] = []
var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("CAPE_FAIL: ", message)


func _run() -> void:
	for character: String in ["lula", "flavio"]:
		var source: PackedScene = load("res://assets/characters/api-cape-v13/" + character + "_run.glb") as PackedScene
		var presentation: CandidatePresentation = CandidatePresentation.new()
		presentation.hero_scene = source
		root.add_child(presentation)
		presentation.set_process(false)
		_presentations.append(presentation)
		_check(presentation.get_cape_motion_state().get("enabled", false), character + " capa com máscara ativa")
		_check(presentation.model.scene_file_path.contains("cape-motion-v1"), character + " derivado separado do original")
		for node: Node in presentation.model.find_children("*", "MeshInstance3D", true, false):
			var instance: MeshInstance3D = node as MeshInstance3D
			if instance.mesh.get_surface_count() != 2:
				continue
			_check(instance.get_surface_override_material(0) == null, character + " corpo/rosto mantém material original")
			var cape: ShaderMaterial = instance.get_surface_override_material(1) as ShaderMaterial
			var original: StandardMaterial3D = instance.mesh.surface_get_material(1) as StandardMaterial3D
			_check(cape != null, character + " shader somente superfície capa")
			_check(cape.get_shader_parameter("albedo_texture") == original.albedo_texture, character + " mesma textura albedo")
			_check(cape.get_shader_parameter("normal_texture") == original.normal_texture, character + " mesmo normal map")
			var arrays: Array = instance.mesh.surface_get_arrays(1)
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
			_check(not colors.is_empty(), character + " máscara presente nos vértices")
			var pinned: int = 0
			var free: int = 0
			for color: Color in colors:
				pinned += 1 if is_zero_approx(color.r) else 0
				free += 1 if color.r > .8 else 0
			_check(pinned > 1000 and free > 1000, character + " ombros presos e barra móvel")
		presentation.update_motion(true, 12.0, 12.0, false, false, false, 1.0)
		for step: int in range(60):
			presentation._process(1.0 / 60.0)
		var run: Dictionary = presentation.get_cape_motion_state()
		_check(float(run.amplitude) > .07, character + " ondulação corrida perceptível")
		presentation.update_motion(true, 24.0, 12.0, true, false, false, 1.0)
		for step: int in range(60):
			presentation._process(1.0 / 60.0)
		var boost: Dictionary = presentation.get_cape_motion_state()
		_check(float(boost.amplitude) > float(run.amplitude) * 1.4 and float(boost.frequency) > float(run.frequency), character + " turbo aumenta amplitude e frequência suavemente")
		presentation.update_motion(true, 24.0, 12.0, true, false, true, 1.0)
		presentation._process(5.0)
		var paused: Dictionary = presentation.get_cape_motion_state()
		_check(is_equal_approx(float(paused.phase), float(boost.phase)) and is_equal_approx(float(paused.amplitude), float(boost.amplitude)) and paused.paused, character + " pausa congela fase/amplitude")
		presentation.update_motion(true, .0, 12.0, false, true, false, 1.0)
		for step: int in range(60):
			presentation._process(1.0 / 60.0)
		var hurt: Dictionary = presentation.get_cape_motion_state()
		_check(float(hurt.amplitude) < .03 and hurt.mode == "hurt", character + " tropeço desacelera pano")
		presentation.reset_motion()
		var reset: Dictionary = presentation.get_cape_motion_state()
		_check(is_zero_approx(float(reset.phase)) and reset.mode == "idle", character + " reinício restaura pano")
		print("CAPE_STATE ", character, " run=", run, " boost=", boost, " hurt=", hurt)
	for presentation: CandidatePresentation in _presentations:
		root.remove_child(presentation)
		presentation.free()
	_presentations.clear()
	await process_frame
	print("TEST_CAPE_MOTION_PASSED" if not _failed else "TEST_CAPE_MOTION_FAILED")
	quit(1 if _failed else 0)
