class_name CandidateCapeMotion
extends RefCounted
## Ondulação visual limitada à superfície da capa; não altera esqueleto ou física.

const SHADER: Shader = preload("res://shaders/candidate_cape_motion.gdshader")
const SOURCE_ROOT: String = "res://assets/characters/api-cape-v13/"
const DERIVED_ROOT: String = "res://assets/characters/cape-motion-v1/"

var _materials: Array[ShaderMaterial] = []
var _phase: float = 0.0
var _amplitude: float = 0.012
var _frequency: float = 1.0
var _paused: bool = false
var _mode: String = "idle"


static func resolve_scene(source: PackedScene) -> PackedScene:
	if source == null or not source.resource_path.begins_with(SOURCE_ROOT):
		return source
	var file_name: String = source.resource_path.get_file()
	if file_name not in ["lula_run.glb", "flavio_run.glb"]:
		return source
	var derived: String = DERIVED_ROOT + file_name
	if ResourceLoader.exists(derived):
		return load(derived) as PackedScene
	return source


func setup(model: Node3D) -> void:
	_materials.clear()
	if model == null or not model.scene_file_path.begins_with(DERIVED_ROOT):
		return
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh == null or instance.mesh.get_surface_count() != 2:
			continue
		var source: StandardMaterial3D = instance.mesh.surface_get_material(1) as StandardMaterial3D
		if source == null:
			continue
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = SHADER
		# The body keeps its original imported material. Cape uses the same maps,
		# color and PBR strengths; COLOR_0 only controls cloth, never albedo.
		material.set_shader_parameter("albedo_texture", source.albedo_texture)
		material.set_shader_parameter("normal_texture", source.normal_texture)
		material.set_shader_parameter("orm_texture", source.roughness_texture)
		material.set_shader_parameter("albedo_tint", source.albedo_color)
		material.set_shader_parameter("normal_strength", source.normal_scale)
		material.set_shader_parameter("roughness_strength", source.roughness)
		material.set_shader_parameter("metallic_strength", source.metallic)
		material.set_shader_parameter("specular_strength", source.metallic_specular)
		instance.set_surface_override_material(1, material)
		# The imported AABB must include the farthest trailing cloth vertices.
		instance.extra_cull_margin = maxf(instance.extra_cull_margin, 0.7)
		_materials.append(material)
	_write_uniforms()


func step(delta: float, running: bool, speed_ratio: float, boost: bool, hurt: bool, paused: bool, arrival: bool, celebrating: bool, motion_scale: float) -> void:
	_paused = paused or motion_scale <= 0.0
	if _paused or _materials.is_empty():
		return
	var ratio: float = clampf(speed_ratio, .0, 2.5)
	var target_amplitude: float = .012
	var target_frequency: float = .65
	_mode = "idle"
	if (running or arrival) and not celebrating:
		_mode = "boost" if boost else "run"
		# Travelling folds and hem lift; the baked collar mask remains zero.
		target_amplitude = clampf(.080 + .070 * ratio + (.030 if boost else .0), .080, .245)
		target_frequency = 1.45 * clampf(ratio, .65, 1.8)
	if hurt:
		_mode = "hurt"
		target_amplitude = .024
		target_frequency = .8
	elif celebrating:
		_mode = "celebration"
		target_amplitude = .022
		target_frequency = 1.15
	var scaled_delta: float = maxf(delta, .0) * clampf(motion_scale, .0, 2.5)
	var blend: float = 1.0 - exp(-6.0 * scaled_delta)
	_amplitude = lerpf(_amplitude, target_amplitude, blend)
	_frequency = lerpf(_frequency, target_frequency, blend)
	_phase = fposmod(_phase + TAU * _frequency * scaled_delta, TAU)
	_write_uniforms()


func reset() -> void:
	_phase = .0
	_amplitude = .012
	_frequency = 1.0
	_paused = false
	_mode = "idle"
	_write_uniforms()


func get_state() -> Dictionary:
	return {"enabled": not _materials.is_empty(), "surfaces": _materials.size(), "phase": _phase,
		"amplitude": _amplitude, "frequency": _frequency, "paused": _paused, "mode": _mode}


func _write_uniforms() -> void:
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("cloth_phase", _phase)
		material.set_shader_parameter("cloth_amplitude", _amplitude)
