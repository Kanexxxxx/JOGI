class_name CandidatePresentation
extends Node3D
## Apresentação com clips privados e capa derivada; originais importados intactos.

@export var hero_scene: PackedScene = null
@export var idle_scene: PackedScene = null
@export var hurt_scene: PackedScene = null
@export var target_height: float = 2.35
@export var evaluation_lod_bias: float = 128.0
@export var transition_seconds: float = 0.22
@export var finish_arrival_seconds: float = 0.85
@export var finish_duration_seconds: float = 9.0

var model: Node3D = null
var animation_player: AnimationPlayer = null
var run_clip: StringName = &""
var idle_clip: StringName = &""
var hurt_clip: StringName = &""
var last_animation_error: String = ""
var _paused: bool = false
var _running: bool = false
var _stumbling: bool = false
var _impact_elapsed: float = 0.0
var target_animation_speed: float = 1.0
var _private_library: AnimationLibrary = null
var _skeleton: Skeleton3D = null
var _winner_clip: StringName = &""
var _loser_clip: StringName = &""
var _finish_active: bool = false
var _finish_completed: bool = false
var _finish_winner: bool = false
var _finish_elapsed: float = 0.0
var _finish_phase: String = "inactive"
var _finish_run_speed: float = 1.0
var _finish_clip_complete: bool = false
var _hurt_active: bool = false
var _hurt_requested: bool = false
var _hurt_elapsed: float = 0.0
var _last_speed: float = 12.0
var _last_base_speed: float = 12.0
var _last_boost: bool = false
var _last_motion_scale: float = 1.0
var _cape_motion: CandidateCapeMotion = CandidateCapeMotion.new()
var _fall_elapsed: float = -1.0
const IMPACT_DURATION: float = 0.28


func _ready() -> void:
	if hero_scene == null:
		return
	var presentation_scene: PackedScene = CandidateCapeMotion.resolve_scene(hero_scene)
	model = presentation_scene.instantiate() as Node3D
	if model == null:
		return
	add_child(model)
	var bounds: AABB = _model_bounds(model)
	var factor: float = target_height / maxf(bounds.size.y, 0.001)
	model.scale = Vector3.ONE * factor
	model.rotation.y = PI
	model.position.y = -bounds.position.y * factor + 0.015
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).lod_bias = evaluation_lod_bias
	if model is MeshInstance3D:
		(model as MeshInstance3D).lod_bias = evaluation_lod_bias
	_cape_motion.setup(model)
	for node: Node in model.find_children("*", "AnimationPlayer", true, false):
		animation_player = node as AnimationPlayer
		break
	if animation_player == null:
		return
	animation_player.animation_finished.connect(_on_animation_finished)
	_find_clips()
	_prepare_private_clips()
	_install_idle_clip()
	hurt_clip = _install_external_clip(hurt_scene, "hurt", &"hurt", Animation.LOOP_NONE)
	_prepare_finish_clips()
	if not run_clip.is_empty():
		animation_player.play(run_clip)
		animation_player.seek(0.0, true)
		animation_player.pause()
		_correct_root_pose_offset()
	update_motion(false, 0.0, 12.0, false, false, false, 1.0)


func _prepare_private_clips() -> void:
	_private_library = AnimationLibrary.new()
	animation_player.add_animation_library(&"presentation", _private_library)
	if not run_clip.is_empty():
		# Loop contínuo em cópia local: o recurso compartilhado do GLB fica intacto.
		var run: Animation = _continuous_run_loop(animation_player.get_animation(run_clip))
		_private_library.add_animation(&"run", run)
		run_clip = &"presentation/run"


func _continuous_run_loop(source: Animation) -> Animation:
	# O retarget fecha com até 28° de diferença entre último e primeiro quadro.
	# Sobrepõe fim/início em uma cópia reamostrada: a pose e sua velocidade
	# atravessam a volta continuamente, sem alterar o GLB ou congelar o passo.
	var overlap: float = minf(.12, source.length * .15)
	var duration: float = source.length - overlap
	var result: Animation = Animation.new()
	result.length = duration
	result.loop_mode = Animation.LOOP_LINEAR
	var sample_count: int = maxi(2, ceili(duration * 60.0))
	for track: int in range(source.get_track_count()):
		var type: Animation.TrackType = source.track_get_type(track)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var target: int = result.add_track(type)
		result.track_set_path(target, source.track_get_path(track))
		for sample: int in range(sample_count + 1):
			var time: float = duration * float(sample) / float(sample_count)
			var first_time: float = minf(time + overlap, source.length)
			var second_time: float = maxf(0.0, time - (duration - overlap))
			var mix_amount: float = smoothstep(duration - overlap, duration, time)
			match type:
				Animation.TYPE_POSITION_3D:
					var a: Vector3 = source.position_track_interpolate(track, first_time)
					var b: Vector3 = source.position_track_interpolate(track, second_time)
					result.position_track_insert_key(target, time, a.lerp(b, mix_amount))
				Animation.TYPE_ROTATION_3D:
					var a: Quaternion = source.rotation_track_interpolate(track, first_time)
					var b: Quaternion = source.rotation_track_interpolate(track, second_time)
					result.rotation_track_insert_key(target, time, a.slerp(b, mix_amount).normalized())
				Animation.TYPE_SCALE_3D:
					var a: Vector3 = source.scale_track_interpolate(track, first_time)
					var b: Vector3 = source.scale_track_interpolate(track, second_time)
					result.scale_track_insert_key(target, time, a.lerp(b, mix_amount))
	return result


func _install_idle_clip() -> void:
	var installed: StringName = _install_external_clip(idle_scene, "idle", &"idle", Animation.LOOP_LINEAR)
	if not installed.is_empty():
		idle_clip = installed


func _install_external_clip(scene: PackedScene, name_fragment: String, private_name: StringName, loop_mode: Animation.LoopMode) -> StringName:
	if scene == null:
		return &""
	var source: Node = scene.instantiate()
	var source_player: AnimationPlayer = source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton_nodes: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	if source_player == null or skeleton_nodes.is_empty():
		source.free()
		last_animation_error = "external_clip_missing_player_or_skeleton"
		return &""
	var skeleton: Skeleton3D = skeleton_nodes[0] as Skeleton3D
	_skeleton = skeleton
	var player_root: Node = animation_player.get_node(animation_player.root_node)
	var target_path: String = String(player_root.get_path_to(skeleton))
	for clip_name: StringName in source_player.get_animation_list():
		if not String(clip_name).to_lower().contains(name_fragment):
			continue
		var clip: Animation = source_player.get_animation(clip_name).duplicate(true) as Animation
		clip.loop_mode = loop_mode
		# Animation-only GLBs provide transform tracks; do not import executable method tracks.
		for track: int in range(clip.get_track_count() - 1, -1, -1):
			if clip.track_get_type(track) not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
				clip.remove_track(track)
		for track: int in range(clip.get_track_count()):
			var path: NodePath = clip.track_get_path(track)
			var bone_name: String = String(path.get_subname(0)) if path.get_subname_count() > 0 else ""
			var bone: int = skeleton.find_bone(bone_name)
			if bone < 0:
				source.free()
				last_animation_error = "external_clip_incompatible_bone:" + bone_name
				return &""
			clip.track_set_path(track, NodePath(target_path + ":" + bone_name))
			if skeleton.get_bone_parent(bone) == -1 and clip.track_get_type(track) == Animation.TYPE_POSITION_3D and clip.track_get_key_count(track) > 0:
				var first: Vector3 = clip.track_get_key_value(track, 0)
				var offset: Vector3 = first - skeleton.get_bone_rest(bone).origin
				offset.y = 0.0
				for key: int in range(clip.track_get_key_count(track)):
					var value: Vector3 = clip.track_get_key_value(track, key)
					clip.track_set_key_value(track, key, value - offset)
		_private_library.add_animation(private_name, clip)
		source.free()
		return StringName("presentation/" + String(private_name))
	source.free()
	last_animation_error = "external_clip_not_found:" + name_fragment
	return &""


func _prepare_finish_clips() -> void:
	if animation_player == null or _private_library == null:
		return
	if _skeleton == null:
		var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			_skeleton = skeletons[0] as Skeleton3D
	if _skeleton == null:
		return
	var base_clip: StringName = idle_clip if not idle_clip.is_empty() else run_clip
	if base_clip.is_empty():
		return
	var source: Animation = animation_player.get_animation(base_clip)
	var winner: Animation = _make_finish_animation(source, true, not idle_clip.is_empty())
	var loser: Animation = _make_finish_animation(source, false, not idle_clip.is_empty())
	_private_library.add_animation(&"round_winner", winner)
	_private_library.add_animation(&"round_loser", loser)
	_winner_clip = &"presentation/round_winner"
	_loser_clip = &"presentation/round_loser"


func _make_finish_animation(source: Animation, is_winner: bool, has_idle: bool) -> Animation:
	var duration: float = maxf(0.5, finish_duration_seconds - finish_arrival_seconds)
	var result: Animation = Animation.new()
	result.length = duration
	result.loop_mode = Animation.LOOP_NONE
	var samples: int = maxi(2, ceili(duration * 30.0))
	for track: int in range(source.get_track_count()):
		var type: Animation.TrackType = source.track_get_type(track)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D] or source.track_get_key_count(track) == 0:
			continue
		var path: NodePath = source.track_get_path(track)
		var bone_name: String = String(path.get_subname(0)) if path.get_subname_count() > 0 else ""
		var bone: int = _skeleton.find_bone(bone_name)
		var kind: String = bone_name.to_lower().replace("mixamorig", "").replace(":", "").replace("_", "")
		var target: int = result.add_track(type)
		result.track_set_path(target, path)
		for sample: int in range(samples + 1):
			var time: float = duration * float(sample) / float(samples)
			var base_time: float = fposmod(time, maxf(source.length, .001)) if has_idle else minf(.2, source.length)
			var envelope: float = smoothstep(0.0, .6, time) * (1.0 - smoothstep(duration - 1.1, duration, time))
			match type:
				Animation.TYPE_POSITION_3D:
					var value: Vector3 = source.position_track_interpolate(track, base_time)
					if is_winner and bone >= 0 and _skeleton.get_bone_parent(bone) == -1:
						var hop_envelope: float = smoothstep(.3, .6, time) * (1.0 - smoothstep(3.6, 4.2, time))
						var hop: float = pow(maxf(0.0, sin((time - .45) * TAU / .95)), 2.0) * .14 * hop_envelope
						value.y += hop / maxf(model.scale.y, .001)
					result.position_track_insert_key(target, time, value)
				Animation.TYPE_ROTATION_3D:
					var base: Quaternion = source.rotation_track_interpolate(track, base_time).normalized()
					var angle: float = 0.0
					var axis: Vector3 = Vector3.BACK
					var side: float = -1.0 if kind.begins_with("right") else 1.0
					if is_winner:
						if kind in ["leftarm", "rightarm"]:
							angle = side * (2.35 + .10 * sin(time * 5.0 + side)) * envelope
						elif kind in ["leftforearm", "rightforearm"]:
							angle = side * (.35 + .18 * sin(time * 6.0 + side)) * envelope
						elif kind == "spine2":
							axis = Vector3.UP
							angle = .06 * sin(time * 3.0) * envelope
					else:
						var disappointment: float = smoothstep(0.0, .55, time) * (1.0 - smoothstep(1.8, 3.0, time))
						if kind in ["head", "spine2"]:
							axis = Vector3.RIGHT
							angle = (.12 if kind == "head" else .08) * disappointment
					if bone >= 0 and not is_zero_approx(angle):
						var local_axis: Vector3 = (_skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse() * axis).normalized()
						base = (base * Quaternion(local_axis, angle)).normalized()
					result.rotation_track_insert_key(target, time, base)
				Animation.TYPE_SCALE_3D:
					result.scale_track_insert_key(target, time, source.scale_track_interpolate(track, base_time))
	return result


func play_round_finish(is_winner: bool) -> void:
	if _finish_active and _finish_winner == is_winner:
		return
	_finish_active = true
	_finish_completed = false
	_finish_winner = is_winner
	_finish_elapsed = 0.0
	_finish_phase = "arrival"
	_finish_clip_complete = false
	_finish_run_speed = clampf(target_animation_speed, .7, 2.5)
	_hurt_active = false
	_hurt_requested = false
	_hurt_elapsed = 0.0
	_impact_elapsed = 0.0
	rotation = Vector3.ZERO
	if animation_player != null and not run_clip.is_empty():
		_play_clip(run_clip)
		target_animation_speed = _finish_run_speed
		if _paused:
			animation_player.pause()


func end_round_finish() -> void:
	_finish_active = false
	_finish_completed = true
	_finish_phase = "settled"
	_impact_elapsed = 0.0
	rotation = Vector3.ZERO
	_restore_movement_clip()


func get_round_finish_state() -> Dictionary:
	return {
		"active": _finish_active, "phase": _finish_phase, "is_winner": _finish_winner,
		"elapsed": _finish_elapsed, "duration": finish_duration_seconds,
		"arrival_seconds": finish_arrival_seconds,
		"progress": clampf(_finish_elapsed / maxf(finish_duration_seconds, .001), 0.0, 1.0),
		"completed": _finish_completed, "hurt_active": _hurt_active, "paused": _paused
	}


func _begin_finish_reaction() -> void:
	_finish_phase = "celebration"
	_finish_clip_complete = false
	var clip: StringName = _winner_clip if _finish_winner else _loser_clip
	if animation_player == null:
		return
	animation_player.speed_scale = 1.0
	target_animation_speed = 1.0
	if not clip.is_empty():
		animation_player.play(clip, transition_seconds)
	elif not idle_clip.is_empty():
		_play_clip(idle_clip)


func _restore_movement_clip() -> void:
	update_motion(_running, _last_speed, _last_base_speed, _last_boost, _stumbling, _paused, _last_motion_scale)


func reset_motion() -> void:
	_cape_motion.reset()
	_fall_elapsed = -1.0
	position.y = 0.0
	_impact_elapsed = 0.0
	_stumbling = false
	_running = false
	_paused = false
	_finish_active = false
	_finish_completed = false
	_finish_winner = false
	_finish_elapsed = 0.0
	_finish_phase = "inactive"
	_hurt_active = false
	_hurt_requested = false
	_hurt_elapsed = 0.0
	_finish_clip_complete = false
	rotation = Vector3.ZERO
	target_animation_speed = 1.0
	if animation_player != null and not idle_clip.is_empty():
		animation_player.speed_scale = 1.0
		animation_player.play(idle_clip, 0.0)
		animation_player.seek(0.0, true)
	elif animation_player != null:
		update_motion(false, 0.0, 12.0, false, false, false, 1.0)


func _find_clips() -> void:
	for clip: StringName in animation_player.get_animation_list():
		var label: String = String(clip).to_lower().get_file()
		if label == "reset":
			continue
		if run_clip.is_empty():
			run_clip = clip
		if label.contains("run") or label.contains("running"):
			run_clip = clip
		if label.contains("idle"):
			idle_clip = clip


func _model_bounds(root_node: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	if root_node is MeshInstance3D:
		meshes.append(root_node as MeshInstance3D)
	for node: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	var result: AABB = AABB()
	var initialized: bool = false
	for mesh_node: MeshInstance3D in meshes:
		if mesh_node.mesh == null:
			continue
		var relative: Transform3D = root_node.global_transform.affine_inverse() * mesh_node.global_transform
		var box: AABB = relative * mesh_node.mesh.get_aabb()
		result = result.merge(box) if initialized else box
		initialized = true
	return result


func _correct_root_pose_offset() -> void:
	# Apenas offsets presentes no retarget: versões já normalizadas ficam intactas.
	for node: Node in model.find_children("*", "Skeleton3D", true, false):
		var skeleton: Skeleton3D = node as Skeleton3D
		for bone: int in range(skeleton.get_bone_count()):
			if skeleton.get_bone_parent(bone) != -1:
				continue
			var offset: Vector3 = skeleton.get_bone_global_pose(bone).origin - skeleton.get_bone_global_rest(bone).origin
			offset.y = 0.0
			if offset.length_squared() > 0.000000000001:
				var relative: Transform3D = model.global_transform.affine_inverse() * skeleton.global_transform
				model.position -= model.basis * (relative.basis * offset)
			break


func update_motion(
	is_racing: bool,
	current_speed: float,
	base_speed: float,
	boost: bool,
	stumble: bool,
	is_paused: bool,
	motion_time_scale: float
) -> void:
	_paused = is_paused or motion_time_scale <= 0.0
	_running = is_racing
	_last_speed = current_speed
	_last_base_speed = base_speed
	_last_boost = boost
	_last_motion_scale = motion_time_scale
	var new_stumble: bool = stumble and not _stumbling
	if new_stumble and not _finish_active:
		_fall_elapsed = 0.0
		_impact_elapsed = IMPACT_DURATION
		_hurt_requested = not hurt_clip.is_empty()
	if not stumble:
		_hurt_requested = false
	_stumbling = stumble
	if animation_player == null:
		return
	if _paused:
		animation_player.pause()
		return
	if _finish_active:
		if _finish_clip_complete and _finish_phase != "arrival":
			animation_player.pause()
			return
		var finish_clip: StringName = run_clip if _finish_phase == "arrival" else (_winner_clip if _finish_winner else _loser_clip)
		if not finish_clip.is_empty():
			_play_clip(finish_clip)
		return
	if _hurt_requested and not hurt_clip.is_empty():
		_hurt_requested = false
		_hurt_active = true
		_hurt_elapsed = 0.0
		_impact_elapsed = 0.0
		animation_player.speed_scale = 1.0
		target_animation_speed = 1.0
		animation_player.play(hurt_clip, minf(transition_seconds, .12))
	if _hurt_active:
		_play_clip(hurt_clip)
		return
	if is_racing and not run_clip.is_empty():
		_play_clip(run_clip)
		var speed_ratio: float = current_speed / maxf(base_speed, 0.001)
		if boost:
			speed_ratio = maxf(speed_ratio, 1.15)
		target_animation_speed = clampf(speed_ratio * motion_time_scale, 0.7, 3.0)
	elif not idle_clip.is_empty():
		_play_clip(idle_clip)
		target_animation_speed = 1.0
	elif not run_clip.is_empty():
		# Não há clip idle no pacote atual: mantém uma pose da corrida, sem inventá-lo.
		if animation_player.current_animation != String(run_clip):
			animation_player.play(run_clip)
		var clip: Animation = animation_player.get_animation(run_clip)
		animation_player.seek(minf(0.2, clip.length), true)
		animation_player.pause()


func _play_clip(clip: StringName) -> void:
	if animation_player.current_animation != String(clip):
		animation_player.play(clip, transition_seconds)
	elif not animation_player.is_playing():
		animation_player.play()


func _on_animation_finished(clip: StringName) -> void:
	if _hurt_active and clip == hurt_clip:
		_hurt_active = false
		_restore_movement_clip()
		return
	if _finish_active and clip in [_winner_clip, _loser_clip]:
		# Hold the last idle pose until the wall-clock finish moment is complete.
		_finish_clip_complete = true
		animation_player.pause()
		return
	# Alguns GLBs não marcam loop; repete sem editar a Animation importada.
	if _running and not _paused and clip == run_clip:
		animation_player.play(run_clip)


func _process(delta: float) -> void:
	var cape_speed_ratio: float = _finish_run_speed if _finish_active and _finish_phase == "arrival" else _last_speed / maxf(_last_base_speed, .001)
	_cape_motion.step(delta, _running, cape_speed_ratio, _last_boost,
		_hurt_active or _stumbling, _paused, _finish_active and _finish_phase == "arrival",
		_finish_active and _finish_phase != "arrival", _last_motion_scale)
	if _paused:
		return
	if _finish_active:
		_finish_elapsed = minf(finish_duration_seconds, _finish_elapsed + maxf(delta, 0.0))
		if _finish_phase == "arrival" and _finish_elapsed >= finish_arrival_seconds:
			_begin_finish_reaction()
		if _finish_elapsed >= finish_duration_seconds:
			end_round_finish()
	if _hurt_active:
		_hurt_elapsed += maxf(delta, 0.0)
		var duration: float = animation_player.get_animation(hurt_clip).length
		if _hurt_elapsed >= minf(duration, 3.0):
			_hurt_active = false
			_restore_movement_clip()
	if animation_player != null:
		animation_player.speed_scale = lerpf(animation_player.speed_scale, target_animation_speed, 1.0 - exp(-12.0 * delta))
	_impact_elapsed = maxf(0.0, _impact_elapsed - delta)
	var amount: float = sin((_impact_elapsed / IMPACT_DURATION) * PI) if _impact_elapsed > 0.0 else 0.0
	rotation.x = amount * 0.12
	rotation.z = amount * 0.08
	if _fall_elapsed >= 0.0:
		_fall_elapsed += maxf(delta, 0.0)
		var fall: float = smoothstep(0.0, .22, _fall_elapsed) * (1.0 - smoothstep(.6, 1.2, _fall_elapsed))
		rotation.x -= fall * .72
		rotation.z += fall * .13
		position.y = -fall * .08
		if _fall_elapsed >= 1.2:
			_fall_elapsed = -1.0
			position.y = 0.0


func get_cape_motion_state() -> Dictionary:
	return _cape_motion.get_state()
