class_name HeroRunner
extends CandidateRunner
## Conserva a simulação e os efeitos do corredor; troca somente a apresentação.

@export var hero_scene: PackedScene = null
@export var idle_scene: PackedScene = null
@export var hurt_scene: PackedScene = null
var presentation: CandidatePresentation = null


func _build_visuals_and_collision() -> void:
	super._build_visuals_and_collision()
	if hero_scene == null or presentation != null:
		return
	for child: Node in _visual_root.get_children():
		if child is MeshInstance3D and child.name != &"BoostRing" and child.name != &"ShieldAura":
			(child as MeshInstance3D).visible = false
	presentation = CandidatePresentation.new()
	presentation.name = "CandidatePresentation"
	presentation.hero_scene = hero_scene
	presentation.idle_scene = idle_scene
	presentation.hurt_scene = hurt_scene
	_visual_root.add_child(presentation)


func reset_runner(p_start_pos: Vector3) -> void:
	super.reset_runner(p_start_pos)
	if presentation != null:
		presentation.reset_motion()


func play_round_finish(is_winner: bool) -> void:
	if presentation != null:
		presentation.play_round_finish(is_winner)


func end_round_finish() -> void:
	if presentation != null:
		presentation.end_round_finish()


func get_round_finish_state() -> Dictionary:
	return presentation.get_round_finish_state() if presentation != null else {"active": false, "phase": "inactive"}


func _animate_procedural_stride(delta: float) -> void:
	if hero_scene == null:
		super._animate_procedural_stride(delta)
		return
	_reset_procedural_transform()


func _reset_procedural_transform() -> void:
	if _visual_root != null:
		_visual_root.position = Vector3.ZERO
		_visual_root.rotation = Vector3.ZERO


func _process(_delta: float) -> void:
	if presentation == null:
		return
	_reset_procedural_transform()
	presentation.update_motion(
		is_racing and not is_finished,
		current_speed,
		base_speed,
		boost_timer > 0.0,
		stumble_timer > 0.0,
		not is_physics_processing() or get_tree().paused,
		motion_time_scale
	)
