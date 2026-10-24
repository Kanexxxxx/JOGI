extends SceneTree

var _runner: HeroRunner = null
var _ran: bool = false
var _source_run: Animation = null
var _source_idle: Animation = null
var _source_hurt: Animation = null
var _source_material: StandardMaterial3D = null


func _initialize() -> void:
	_runner = HeroRunner.new()
	_runner.hero_scene = _make_scene("run", true)
	_runner.idle_scene = _make_scene("idle", false)
	_runner.hurt_scene = _make_scene("hurt", false)
	root.add_child(_runner)
	_runner.set_process(false)
	_runner.set_physics_process(false)


func _make_scene(kind: String, with_mesh: bool) -> PackedScene:
	var model: Node3D = Node3D.new()
	model.name = "HeroReference" if with_mesh else "AnimationOnlyReference"
	if with_mesh:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.name = "ApprovedMesh"
		mesh.mesh = BoxMesh.new()
		mesh.position.y = .5
		_source_material = StandardMaterial3D.new()
		_source_material.albedo_color = Color("123456")
		mesh.material_override = _source_material
		model.add_child(mesh)
		mesh.owner = model
	var skeleton: Skeleton3D = Skeleton3D.new()
	skeleton.name = "Skeleton"
	model.add_child(skeleton)
	skeleton.owner = model
	var bone_names: Array[String] = ["mixamorig_Hips", "mixamorig_Spine2", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_Head"]
	for index: int in range(bone_names.size()):
		skeleton.add_bone(bone_names[index])
		skeleton.set_bone_parent(index, -1 if index == 0 else (2 if index == 3 else (4 if index == 5 else 0)))
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, Vector3.ZERO if index == 0 else Vector3(0.0, .1, 0.0)))
	var player: AnimationPlayer = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	model.add_child(player)
	player.owner = model
	var clip: Animation = Animation.new()
	clip.length = .6 if kind == "hurt" else 1.0
	clip.loop_mode = Animation.LOOP_NONE
	for index: int in range(bone_names.size()):
		var track: int = clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath("Skeleton:" + bone_names[index]))
		clip.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
		clip.rotation_track_insert_key(track, clip.length, Quaternion(Vector3.UP, .4 if kind == "run" else 0.0))
	var hips: int = clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(hips, NodePath("Skeleton:mixamorig_Hips"))
	var offset: Vector3 = Vector3(-2.0, .0, 3.0) if kind == "hurt" else Vector3.ZERO
	clip.position_track_insert_key(hips, 0.0, offset)
	clip.position_track_insert_key(hips, clip.length, offset + Vector3(0.0, .01, 0.0))
	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation(StringName(kind), clip)
	player.add_animation_library(&"", library)
	if kind == "run":
		_source_run = clip
	elif kind == "idle":
		_source_idle = clip
	else:
		_source_hurt = clip
	var scene: PackedScene = PackedScene.new()
	scene.pack(model)
	model.free()
	return scene


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_runner.presentation.set_process(false)
	_runner.presentation.animation_player.set_process(false)
	var passed: bool = _run_suite()
	root.remove_child(_runner)
	_runner.free()
	_runner = null
	_source_run = null
	_source_idle = null
	_source_hurt = null
	_source_material = null
	print("TEST_ROUND_FINISH_PRESENTATION_PASSED" if passed else "TEST_ROUND_FINISH_PRESENTATION_FAILED")
	quit(0 if passed else 1)
	return true


func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("FAIL: ", message)
	return condition


func _run_suite() -> bool:
	var presentation: CandidatePresentation = _runner.presentation
	var player: AnimationPlayer = presentation.animation_player
	if not _check(presentation.idle_clip == &"presentation/idle" and presentation.hurt_clip == &"presentation/hurt", "Idle e hurt devem remapear para cópias privadas"):
		return false
	var run: Animation = player.get_animation(presentation.run_clip)
	if not _check(run.loop_mode == Animation.LOOP_LINEAR and _source_run.loop_mode == Animation.LOOP_NONE, "Corrida deve fechar loop sem alterar Animation compartilhada"):
		return false
	for track: int in range(run.get_track_count()):
		if run.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			var a: Quaternion = run.rotation_track_interpolate(track, 0.0)
			var b: Quaternion = run.rotation_track_interpolate(track, run.length)
			if not _check(a.angle_to(b) < .001, "Loop de corrida deve manter continuidade na volta"):
				return false
	presentation.update_motion(true, 18.0, 12.0, true, false, false, 1.0)
	_runner.play_round_finish(true)
	presentation.update_motion(false, 0.0, 12.0, false, false, false, 1.0)
	presentation._process(.84)
	if not _check(_runner.get_round_finish_state()["phase"] == "arrival" and player.current_animation == String(presentation.run_clip), "Primeiros.85s devem preservar corrida depois do cronômetrozero"):
		return false
	_runner.play_round_finish(true)
	if not _check(is_equal_approx(float(presentation.get_round_finish_state()["elapsed"]), .84), "Aviso repetido do mesmo resultado não pode reiniciar a sequência"):
		return false
	presentation._process(.02)
	if not _check(presentation.get_round_finish_state()["phase"] == "celebration" and player.current_animation == "presentation/round_winner", "Após chegada vencedor deve usar clip próprio"):
		return false
	presentation.update_motion(false, 0.0, 12.0, false, true, false, 1.0)
	if not _check(player.current_animation == "presentation/round_winner" and not presentation.get_round_finish_state()["hurt_active"], "update_motion e tropeço não podem interromper comemoração"):
		return false
	var winner: Animation = player.get_animation(&"presentation/round_winner")
	var loser: Animation = player.get_animation(&"presentation/round_loser")
	var arm_changed: bool = false
	var max_hop: float = 0.0
	for track: int in range(winner.get_track_count()):
		for key: int in range(winner.track_get_key_count(track)):
			if winner.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				var rotation: Quaternion = winner.track_get_key_value(track, key)
				if not _check(rotation.is_finite() and absf(rotation.length() - 1.0) < .0001, "Quaternions de gesto devem ser finitos e normalizados"):
					return false
				if String(winner.track_get_path(track)).contains("LeftArm") and rotation.angle_to(Quaternion.IDENTITY) > 1.0:
					arm_changed = true
			elif winner.track_get_type(track) == Animation.TYPE_POSITION_3D:
				var position: Vector3 = winner.track_get_key_value(track, key)
				max_hop = maxf(max_hop, position.y * presentation.model.scale.y)
	if not _check(arm_changed and max_hop > .08 and max_hop < .18 and winner.loop_mode == Animation.LOOP_NONE and loser.loop_mode == Animation.LOOP_NONE, "Comemoração deve levantar braços e dar salto leve; clips não podem repetir"):
		return false
	var frozen: float = float(presentation.get_round_finish_state()["elapsed"])
	presentation.update_motion(false, 0.0, 12.0, false, false, true, 1.0)
	presentation._process(5.0)
	if not _check(not player.is_playing() and presentation.get_round_finish_state()["elapsed"] == frozen, "Pausa deve congelar clip e relógio da comemoração"):
		return false
	presentation.update_motion(false, 0.0, 12.0, false, false, false, 1.0)
	if not _check(player.is_playing() and player.current_animation == "presentation/round_winner", "Retomar deve continuar o mesmo clip"):
		return false
	presentation._process(9.0)
	if not _check(not presentation.get_round_finish_state()["active"] and presentation.get_round_finish_state()["completed"] and player.current_animation == String(presentation.idle_clip), "Após9s deve voltar ao idle sem reiniciar corrida"):
		return false
	_runner.play_round_finish(false)
	presentation.update_motion(false, 0.0, 12.0, false, false, false, 1.0)
	presentation._process(.9)
	if not _check(player.current_animation == "presentation/round_loser" and not presentation.get_round_finish_state()["is_winner"], "Perdedor deve ter reação própria de repouso/desapontamento"):
		return false
	_runner.end_round_finish()
	if not _check(player.current_animation == String(presentation.idle_clip), "Encerrar momento porAPI deve retornar ao idle"):
		return false
	presentation.reset_motion()
	presentation.update_motion(true, 12.0, 12.0, false, true, false, 1.0)
	if not _check(presentation.get_round_finish_state()["hurt_active"] and player.current_animation == String(presentation.hurt_clip), "Tropeço com asset compatível deve tocar hurt nonloop"):
		return false
	presentation.update_motion(true, 12.0, 12.0, false, false, false, 1.0)
	if not _check(player.current_animation == String(presentation.hurt_clip), "Fim do estado físico não deve cortar hurt pela metade"):
		return false
	presentation._process(.7)
	if not _check(not presentation.get_round_finish_state()["hurt_active"] and player.current_animation == String(presentation.run_clip), "Hurt deve fazer blend de volta ao movimento"):
		return false
	var hurt: Animation = player.get_animation(presentation.hurt_clip)
	var last_track: int = hurt.get_track_count() - 1
	var normalized: Vector3 = hurt.track_get_key_value(last_track, 0)
	var original_offset: Vector3 = _source_hurt.track_get_key_value(_source_hurt.get_track_count() - 1, 0)
	if not _check(is_zero_approx(normalized.x) and is_zero_approx(normalized.z) and original_offset == Vector3(-2, 0, 3), "Remap hurt deve corrigir apenas cópia local de deslocamentoXZ"):
		return false
	_runner.play_round_finish(true)
	_runner.reset_runner(Vector3.ZERO)
	if not _check(presentation.get_round_finish_state()["phase"] == "inactive" and not presentation.get_round_finish_state()["active"] and not presentation.get_round_finish_state()["hurt_active"] and presentation.rotation == Vector3.ZERO, "Reset deve limpar todas as reações e estados de fim"):
		return false
	return _check(_source_idle.loop_mode == Animation.LOOP_NONE and _source_run.get_track_count() == 8 and _source_hurt.loop_mode == Animation.LOOP_NONE and _source_material.albedo_color == Color("123456"), "Fontes compartilhadas e material aprovado devem permanecer intactos")
