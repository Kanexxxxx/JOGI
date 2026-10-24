class_name RaceCamera
extends Camera3D

@export var follow_offset: Vector3 = Vector3(0.0, 7.0, 11.0)
@export var smooth_speed: float = 6.5
@export var leader_weight: float = 0.65
@export var pack_weight: float = 0.35
@export var look_ahead_z: float = 0.0
@export var look_target_y: float = 0.25
@export var safe_window_top_px: float = 440.0
@export var safe_window_bottom_px: float = 1220.0

var offset: Vector3 = Vector3(0.0, 7.0, 11.0)
var tracked_runners: Array[CandidateRunner] = []
var focus_point: Vector3 = Vector3.ZERO


func _ready() -> void:
	fov = 55.0
	keep_aspect = Camera3D.KEEP_WIDTH
	current = true
	offset = follow_offset


func _exit_tree() -> void:
	tracked_runners.clear()


func set_runners(runners: Array[CandidateRunner]) -> void:
	tracked_runners = runners
	snap_to_targets()


func snap_to_targets() -> void:
	focus_point = _compute_focus_point()
	global_position = Vector3(0.0, focus_point.y, focus_point.z) + offset
	var look_target: Vector3 = Vector3(0.0, look_target_y, focus_point.z + look_ahead_z)
	if not global_position.is_equal_approx(look_target):
		look_at(look_target, Vector3.UP)


func _physics_process(delta: float) -> void:
	if tracked_runners.is_empty():
		return
	offset = follow_offset
	focus_point = _compute_focus_point()
	var desired_pos: Vector3 = Vector3(0.0, focus_point.y, focus_point.z) + offset
	var weight: float = clampf(delta * smooth_speed, 0.0, 1.0)
	global_position = global_position.lerp(desired_pos, weight)

	var look_target: Vector3 = Vector3(0.0, look_target_y, focus_point.z + look_ahead_z)
	if not global_position.is_equal_approx(look_target):
		look_at(look_target, Vector3.UP)


func _compute_focus_point() -> Vector3:
	if tracked_runners.is_empty():
		return Vector3.ZERO

	var leader_z: float = INF
	var sum_z: float = 0.0
	var count: int = 0

	for runner: CandidateRunner in tracked_runners:
		if runner == null or not is_instance_valid(runner):
			continue
		var rz: float = runner.global_position.z
		if rz < leader_z:
			leader_z = rz
		sum_z += rz
		count += 1

	if count == 0:
		return Vector3.ZERO

	var pack_center_z: float = sum_z / float(count)
	var weighted_z: float = (leader_z * leader_weight) + (pack_center_z * pack_weight)
	return Vector3(0.0, 0.0, weighted_z)


func get_runner_screen_y(runner: CandidateRunner) -> float:
	if runner == null or not is_instance_valid(runner):
		return 830.0
	return unproject_position(runner.global_position + Vector3(0.0, 1.1, 0.0)).y


func is_runner_in_safe_window(runner: CandidateRunner) -> bool:
	var screen_y: float = get_runner_screen_y(runner)
	return screen_y >= safe_window_top_px and screen_y <= safe_window_bottom_px
