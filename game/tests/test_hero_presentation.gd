extends SceneTree

var _runner: HeroRunner = null
var _fallback: HeroRunner = null
var _ran_suite: bool = false


func _initialize() -> void:
	_runner = HeroRunner.new()
	# Reproduz uma parte procedural sem nome semântico, antes da troca pelo GLB.
	_runner._build_visuals_and_collision()
	_runner._visual_root.get_node("LulaMustache").name = &"MeshInstance3D"
	_runner.hero_scene = _make_hero_scene()
	root.add_child(_runner)
	_fallback = HeroRunner.new()
	root.add_child(_fallback)


func _make_hero_scene() -> PackedScene:
	var hero: Node3D = Node3D.new()
	hero.name = "FakeHero"
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "HeroMesh"
	mesh.mesh = BoxMesh.new()
	mesh.position.y = 0.5
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("223366")
	mesh.material_override = material
	hero.add_child(mesh)
	mesh.owner = hero
	var skeleton: Skeleton3D = Skeleton3D.new()
	skeleton.name = "Skeleton"
	skeleton.add_bone("Hips")
	skeleton.set_bone_rest(0, Transform3D.IDENTITY)
	hero.add_child(skeleton)
	skeleton.owner = hero
	var player: AnimationPlayer = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	hero.add_child(player)
	player.owner = hero
	var library: AnimationLibrary = AnimationLibrary.new()
	var run: Animation = Animation.new()
	run.length = 1.0
	run.loop_mode = Animation.LOOP_LINEAR
	var track: int = run.add_track(Animation.TYPE_POSITION_3D)
	run.track_set_path(track, NodePath("Skeleton:Hips"))
	run.position_track_insert_key(track, 0.0, Vector3.ZERO)
	run.position_track_insert_key(track, 0.5, Vector3(0.0, 0.01, 0.0))
	library.add_animation(&"run", run)
	library.add_animation(&"RESET", Animation.new())
	player.add_animation_library(&"", library)
	var packed: PackedScene = PackedScene.new()
	packed.pack(hero)
	hero.free()
	return packed


func _process(_delta: float) -> bool:
	if _ran_suite:
		return true
	_ran_suite = true
	var passed: bool = _execute_test_suite()
	root.remove_child(_runner)
	_runner.free()
	root.remove_child(_fallback)
	_fallback.free()
	if passed:
		print("TEST_HERO_PRESENTATION_PASSED")
	else:
		printerr("TEST_HERO_PRESENTATION_FAILED")
	quit(0 if passed else 1)
	return true


func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("FAIL: ", message)
	return condition


func _execute_test_suite() -> bool:
	var presentation: CandidatePresentation = _runner.presentation
	if not _check(presentation != null and presentation.model != null, "GLB configurado deve ser instanciado"):
		return false
	var player: AnimationPlayer = presentation.animation_player
	if not _check(player != null and presentation.run_clip == &"presentation/run" and presentation.idle_clip.is_empty(), "Driver deve descobrir corrida sem inventar idle"):
		return false
	if not _check(is_equal_approx(presentation.model.scale.y, 2.35) and is_equal_approx(presentation.model.position.y, 0.015), "Altura e solo devem vir dos limites, sem offset antigo"):
		return false
	if not _check(is_equal_approx(absf(presentation.model.rotation.y), PI), "Frente deve ser orientada para -Z"):
		return false
	if not _check(not _runner._body_mesh.visible and not _runner._head_mesh.visible and _runner._visual_root.get_node("BoostRing") != null and _runner._visual_root.get_node("ShieldAura") != null, "Troca visual deve ocultar placeholders e preservar efeitos"):
		return false
	# Inclui bigode com nome automático do Godot: não depender de nome de cada parte.
	var placeholder_meshes: int = 0
	for child: Node in _runner._visual_root.get_children():
		if child is MeshInstance3D and child.name != &"BoostRing" and child.name != &"ShieldAura":
			placeholder_meshes += 1
			if not _check(not (child as MeshInstance3D).visible, "Todo mesh procedural deve ficar oculto, inclusive bigode anônimo"):
				return false
	if not _check(placeholder_meshes >= 6 and not _runner._boost_ring.visible and not _runner._shield_sphere.visible, "Substituição deve ocultar todas as partes sem ativar efeitos"):
		return false
	if not _check(_fallback.presentation == null and _fallback._body_mesh.visible, "Sem GLB deve manter fallback"):
		return false
	var hero_mesh: MeshInstance3D = presentation.model.get_node("HeroMesh") as MeshInstance3D
	var material: StandardMaterial3D = hero_mesh.material_override as StandardMaterial3D
	if not _check(hero_mesh.lod_bias == 128.0, "Preset HQ deve preservar LOD de avaliação"):
		return false
	presentation.update_motion(true, 12.0, 12.0, false, false, false, 1.0)
	if not _check(player.is_playing() and player.speed_scale == 1.0, "Corrida deve tocar na velocidade base"):
		return false
	presentation.update_motion(true, 120.0, 12.0, true, false, false, 1.0)
	if not _check(presentation.target_animation_speed == 3.0, "Turbo de até +200% respeita teto de animação3x"):
		return false
	presentation._process(0.1)
	if not _check(player.speed_scale > 1.0 and player.speed_scale < 3.0, "Turbo deve acelerar animação suavemente"):
		return false
	presentation.update_motion(true, 0.0, 12.0, false, false, false, 1.0)
	if not _check(is_equal_approx(presentation.target_animation_speed, 0.7), "Velocidade baixa deve respeitar piso de animação"):
		return false
	presentation.update_motion(true, 12.0, 12.0, false, false, true, 1.0)
	if not _check(not player.is_playing(), "Pause deve congelar clip"):
		return false
	presentation.update_motion(true, 12.0, 12.0, false, false, false, 0.0)
	if not _check(not player.is_playing(), "Escala temporal zero deve congelar clip"):
		return false
	presentation.update_motion(false, 0.0, 12.0, false, false, false, 1.0)
	if not _check(not player.is_playing() and is_equal_approx(player.current_animation_position, 0.2), "Sem idle deve manter pose de corrida congelada"):
		return false
	presentation.update_motion(true, 12.0, 12.0, false, true, false, 1.0)
	presentation._process(0.10)
	if not _check(presentation.rotation.x < 0.0 and presentation.rotation.x >= -.73, "Queda inclina para frente com amplitude limitada"):
		return false
	presentation._process(0.30)
	var fallen_rotation: Vector3 = presentation.rotation
	presentation.update_motion(true, 12.0, 12.0, false, true, true, 1.0)
	presentation._process(2.0)
	if not _check(presentation.rotation == fallen_rotation, "Pausa congela a reação de queda"):
		return false
	presentation.update_motion(true, 12.0, 12.0, false, false, false, 1.0)
	presentation._process(.9)
	if not _check(presentation.rotation == Vector3.ZERO and is_zero_approx(presentation.position.y), "Recuperação1,2s elimina inclinação e deslocamento residuais"):
		return false
	_runner.start_running()
	_runner.apply_boost(8.0, 3.0)
	_runner.apply_shield(3.0)
	_runner._process(0.01)
	if not _check(_runner._boost_ring.visible and _runner._shield_sphere.visible, "Efeitos devem continuar reagindo ao estado do corredor"):
		return false
	if not _check(not material.emission_enabled and material.albedo_color == Color("223366"), "Turbo não deve alterar material original"):
		return false
	_runner.shield_timer = 0.0
	_runner.apply_stumble()
	_runner._process(0.01)
	if not _check(_runner._visual_root.rotation == Vector3.ZERO, "Hero não deve herdar deformação procedural de impacto"):
		return false
	_runner._animate_procedural_stride(0.1)
	if not _check(_runner._visual_root.position == Vector3.ZERO, "Hero não deve receber bob procedural"):
		return false
	_runner.reset_runner(Vector3.ZERO)
	if not _check(presentation.rotation == Vector3.ZERO and presentation._impact_elapsed == 0.0, "Restart deve limpar inclinação e impacto imediatamente"):
		return false
	_fallback.start_running()
	_fallback.stride_phase = 0.4
	_fallback._animate_procedural_stride(0.1)
	if not _check(_fallback._visual_root.position.y > 0.0, "Fallback deve conservar animação procedural"):
		return false
	return true
