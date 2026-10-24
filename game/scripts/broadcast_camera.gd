extends RaceCamera
## Acompanha o avanço sem atraso longitudinal que altere o tamanho dos rostos.

var view_target_x: float = -0.25
var desired_target_y: float = 1.1
var _orbit_angle: float = 0.0
var _orbit_radius: float = 6.2


func _ready() -> void:
	super._ready()
	fov = 45.0
	far = 300.0


func _physics_process(delta: float) -> void:
	if tracked_runners.is_empty():
		return
	focus_point = _compute_focus_point()
	# Suaviza a troca de plano, mantendo a velocidade da corrida na câmera.
	var weight: float = 1.0 - exp(-6.0 * delta)
	_orbit_angle = lerp_angle(_orbit_angle, atan2(follow_offset.x, follow_offset.z), weight)
	_orbit_radius = lerpf(_orbit_radius, Vector2(follow_offset.x, follow_offset.z).length(), weight)
	offset = Vector3(sin(_orbit_angle) * _orbit_radius, lerpf(offset.y, follow_offset.y, weight), cos(_orbit_angle) * _orbit_radius)
	look_target_y = lerpf(look_target_y, desired_target_y, weight)
	global_position = Vector3(0.0, focus_point.y, focus_point.z) + offset
	look_at(Vector3(view_target_x, look_target_y, focus_point.z), Vector3.UP)


func snap_to_targets() -> void:
	focus_point = _compute_focus_point()
	offset = follow_offset
	_orbit_angle = atan2(follow_offset.x, follow_offset.z)
	_orbit_radius = Vector2(follow_offset.x, follow_offset.z).length()
	global_position = Vector3(0.0, focus_point.y, focus_point.z) + offset
	look_at(Vector3(view_target_x, desired_target_y, focus_point.z), Vector3.UP)


func set_view(view: String) -> void:
	match view:
		"verso":
			follow_offset = Vector3(-.6, 2.0, 6.2)
		"perfil":
			follow_offset = Vector3(6.4, 2.1, -2.5)
		_:
			follow_offset = Vector3(.35, 2.0, -6.2)
