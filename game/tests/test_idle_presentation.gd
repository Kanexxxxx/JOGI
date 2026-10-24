extends SceneTree
## Integração com GLBs reais: ossos, origem, loop, pausa e recursos imutáveis.


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("FAIL: ", message)
	return condition


func _run() -> void:
	var passed: bool = true
	for slug: String in ["lula", "flavio"]:
		var presentation: CandidatePresentation = CandidatePresentation.new()
		presentation.hero_scene = load("res://assets/characters/api-cape-v13/%s_run.glb" % slug) as PackedScene
		presentation.idle_scene = load("res://assets/characters/idle-clips/%s_idle.glb" % slug) as PackedScene
		root.add_child(presentation)
		passed = _check_presentation(presentation, slug) and passed
		root.remove_child(presentation)
		presentation.free()
		await process_frame
	print("TEST_IDLE_PRESENTATION_PASSED" if passed else "TEST_IDLE_PRESENTATION_FAILED")
	quit(0 if passed else 1)


func _check_presentation(presentation: CandidatePresentation, slug: String) -> bool:
	if not _check(presentation.idle_clip == &"presentation/idle" and presentation.run_clip == &"presentation/run", slug + ": espera e corrida devem estar conectadas"):
		return false
	var player: AnimationPlayer = presentation.animation_player
	var idle: Animation = player.get_animation(presentation.idle_clip)
	var run: Animation = player.get_animation(presentation.run_clip)
	if not _check(idle.length > 15.0 and idle.get_track_count() == 53 and idle.loop_mode == Animation.LOOP_LINEAR and run.loop_mode == Animation.LOOP_LINEAR, slug + ": clipes reais completos devem repetir sem congelar"):
		return false
	for track: int in range(run.get_track_count()):
		var last_key: int = run.track_get_key_count(track) - 1
		if run.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			var first: Quaternion = run.track_get_key_value(track, 0)
			var last: Quaternion = run.track_get_key_value(track, last_key)
			if not _check(first.angle_to(last) < .001, slug + ": volta da corrida não deve conter salto angular"):
				return false
	var original_player_node: Node = presentation.idle_scene.instantiate()
	var original_player: AnimationPlayer = original_player_node.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var original_idle: Animation = original_player.get_animation(&"idle")
	var source_root_key: Vector3 = original_idle.track_get_key_value(0, 0)
	var skeleton: Skeleton3D = presentation.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for track: int in range(idle.get_track_count()):
		var path: NodePath = idle.track_get_path(track)
		var bone: int = skeleton.find_bone(String(path.get_subname(0)))
		if not _check(bone >= 0, slug + ": todo track deve apontar para osso real"):
			return false
		if skeleton.get_bone_parent(bone) == -1 and idle.track_get_type(track) == Animation.TYPE_POSITION_3D:
			var key: Vector3 = idle.track_get_key_value(track, 0)
			var rest: Vector3 = skeleton.get_bone_rest(bone).origin
			if not _check(Vector2(key.x - rest.x, key.z - rest.z).length() < 0.00001 and is_equal_approx(key.y, source_root_key.y), slug + ": origem XZ deve ser normalizada sem alterar altura Y"):
				original_player_node.free()
				return false
	if not _check(original_idle.track_get_key_value(0, 0) == source_root_key, slug + ": normalização não deve alterar recurso original"):
		original_player_node.free()
		return false
	original_player_node.free()
	presentation.reset_motion()
	player.advance(0.5)
	if not _check(player.is_playing() and player.current_animation == String(presentation.idle_clip), slug + ": lobby deve ter movimento de espera real"):
		return false
	var before: float = player.current_animation_position
	presentation.update_motion(false, 0.0, 12.0, false, false, true, 1.0)
	if not _check(not player.is_playing() and is_equal_approx(before, player.current_animation_position), slug + ": pausa deve congelar espera"):
		return false
	presentation.update_motion(true, 12.0, 12.0, false, false, false, 1.0)
	player.advance(presentation.transition_seconds + .01)
	if not _check(player.is_playing() and player.current_animation == String(presentation.run_clip), slug + ": largada deve transicionar para corrida"):
		return false
	player.seek(run.length - .01, true)
	player.advance(.1)
	if not _check(player.is_playing() and player.current_animation_position < .2, slug + ": volta de corrida deve ser contínua"):
		return false
	return true
