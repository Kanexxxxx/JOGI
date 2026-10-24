class_name StadiumEffects
extends Node3D
## Efeitos de apresentação em pools fixos. Corrida +X; partículas seguem para -X.
## Não altera velocidade, colisões, materiais dos personagens ou estado de presentes.

const MAX_PARTICLES: int = 400
const BOOST_AMOUNT: int = 64
const IMPACT_AMOUNT: int = 32
const SHIELD_AMOUNT: int = 8
const PARTY_AMOUNT: int = 160
const VALID_MOMENTS: Array[String] = ["boost", "super_turbo", "shield", "impact", "attack", "stumble", "podium", "tie", "start"]

var _boosts: Array[GPUParticles3D] = []
var _impacts: Array[GPUParticles3D] = []
var _glints: Array[GPUParticles3D] = []
var _party: GPUParticles3D = null
var _positions: Array[Vector3] = [Vector3(0.0, 0.0, 1.45), Vector3(0.0, 0.0, -1.45)]
var _boost_active: Array[bool] = [false, false]
var _shield_active: Array[bool] = [false, false]
var _stumble_active: Array[bool] = [false, false]
var _boost_flash_remaining: Array[float] = [0.0, 0.0]
var _next_moment: Dictionary = {}
var _paused: bool = false
var _clock: float = 0.0
var _render_layer: int = 1


func _ready() -> void:
	name = "EfeitosDaArena"
	_build_pool()
	for index: int in range(2):
		_update_emitters(index)


func _process(delta: float) -> void:
	if _paused:
		return
	var elapsed: float = clampf(delta, 0.0, .25)
	_clock += elapsed
	for index: int in range(2):
		_boost_flash_remaining[index] = maxf(0.0, _boost_flash_remaining[index] - elapsed)
		_update_boost(index)


func set_runner_state(slot: int, runner_position: Vector3, boost: bool, shield: bool, stumbling: bool) -> void:
	if slot < 1 or slot > 2 or not runner_position.is_finite():
		return
	var index: int = slot - 1
	_positions[index] = runner_position
	_boost_active[index] = boost
	var new_shield: bool = shield and not _shield_active[index]
	var new_stumble: bool = stumbling and not _stumble_active[index]
	_shield_active[index] = shield
	_stumble_active[index] = stumbling
	if _boosts.is_empty():
		return
	_update_emitters(index)
	_update_boost(index)
	if new_shield:
		trigger_moment("shield", slot)
	if new_stumble:
		trigger_moment("impact", slot)


func trigger_moment(kind: String, slot: int = 0) -> void:
	if _paused or _party == null:
		return
	var canonical: String = kind.to_lower()
	if not VALID_MOMENTS.has(canonical):
		return
	var global_moment: bool = canonical == "podium" or canonical == "tie" or canonical == "start"
	if not global_moment and (slot < 1 or slot > 2):
		return
	if global_moment and (slot < 0 or slot > 2):
		return
	var key: String = "%s:%d" % [canonical, slot]
	if _clock < float(_next_moment.get(key, -1.0)):
		return
	_next_moment[key] = _clock + (3.0 if global_moment else .45)
	if global_moment:
		# A mesma salva atende as duas equipes; não existe chuva permanente.
		var center: Vector3 = (_positions[0] + _positions[1]) * .5
		_party.global_position = center + Vector3(.7, .9, 0.0)
		_party.restart()
		return
	var index: int = slot - 1
	match canonical:
		"boost", "super_turbo":
			_boost_flash_remaining[index] = .7 if canonical == "boost" else 1.4
			_update_boost(index)
		"shield":
			_glints[index].restart()
		"impact", "attack", "stumble":
			_impacts[index].restart()


func set_paused(value: bool) -> void:
	_paused = value
	for emitter: GPUParticles3D in _all_emitters():
		emitter.speed_scale = 0.0 if value else 1.0


func set_render_layer(mask: int) -> void:
	_render_layer = maxi(1, mask)
	for emitter: GPUParticles3D in _all_emitters():
		emitter.layers = _render_layer


func clear_effects() -> void:
	# Reinício de rodada: cessa emissões e elimina partículas anteriores sem novos nós.
	_next_moment.clear()
	for index: int in range(2):
		_boost_active[index] = false
		_shield_active[index] = false
		_stumble_active[index] = false
		_boost_flash_remaining[index] = 0.0
	for emitter: GPUParticles3D in _all_emitters():
		emitter.emitting = false
		emitter.restart()
		emitter.emitting = false


func get_effect_budget() -> Dictionary:
	var capacity: int = 0
	var draw_passes: int = 0
	for emitter: GPUParticles3D in _all_emitters():
		capacity += emitter.amount
		draw_passes += emitter.draw_passes
	return {"particle_capacity": capacity, "particle_limit": MAX_PARTICLES, "emitter_count": _all_emitters().size(),
		"maximum_draw_passes": draw_passes, "node_count": get_child_count() + 1, "paused": _paused}


func _all_emitters() -> Array[GPUParticles3D]:
	var all: Array[GPUParticles3D] = []
	all.append_array(_boosts)
	all.append_array(_impacts)
	all.append_array(_glints)
	if _party != null:
		all.append(_party)
	return all


func _build_pool() -> void:
	if not _boosts.is_empty():
		return
	var streak_mesh: BoxMesh = BoxMesh.new()
	streak_mesh.size = Vector3(.44, .025, .035)
	streak_mesh.material = _particle_material(false)
	var puff_mesh: SphereMesh = SphereMesh.new()
	puff_mesh.radius = .09
	puff_mesh.height = .18
	puff_mesh.radial_segments = 8
	puff_mesh.rings = 4
	puff_mesh.material = _particle_material(false)
	var glint_mesh: BoxMesh = BoxMesh.new()
	glint_mesh.size = Vector3(.035, .15, .035)
	glint_mesh.material = _particle_material(true)
	var paper_mesh: BoxMesh = BoxMesh.new()
	paper_mesh.size = Vector3(.065, .009, .10)
	paper_mesh.material = _particle_material(false)
	for index: int in range(2):
		var color: Color = Color("ffe057") if index == 0 else Color("5eeeff")
		var boost_material: ParticleProcessMaterial = _process_material(color, Vector3(-1.0, .08, 0.0), Vector3(0, -.8, 0))
		boost_material.emission_box_extents = Vector3(.1, .12, .32)
		boost_material.spread = 10.0
		boost_material.initial_velocity_min = 4.0
		boost_material.initial_velocity_max = 7.0
		boost_material.scale_min = .65
		boost_material.scale_max = 1.2
		var boost: GPUParticles3D = _emitter("RastroTurbo%d" % (index + 1), BOOST_AMOUNT, .40, false, streak_mesh, boost_material)
		boost.visibility_aabb = AABB(Vector3(-4.5, -1.0, -1.0), Vector3(5.5, 3.0, 2.0))
		_boosts.append(boost)
		var impact_material: ParticleProcessMaterial = _process_material(Color("ffe8b3"), Vector3(-.6, .8, 0.0), Vector3(0, -3.2, 0))
		impact_material.emission_box_extents = Vector3(.35, .03, .30)
		impact_material.spread = 70.0
		impact_material.initial_velocity_min = .8
		impact_material.initial_velocity_max = 2.8
		impact_material.scale_min = .4
		impact_material.scale_max = 1.4
		impact_material.damping_min = .6
		impact_material.damping_max = 1.2
		_impacts.append(_emitter("PoeiraImpacto%d" % (index + 1), IMPACT_AMOUNT, .55, true, puff_mesh, impact_material))
		var shield_material: ParticleProcessMaterial = _process_material(Color("9ff4ff"), Vector3(0, 1.0, 0), Vector3.ZERO)
		shield_material.emission_box_extents = Vector3(.38, .65, .38)
		shield_material.spread = 20.0
		shield_material.initial_velocity_min = .2
		shield_material.initial_velocity_max = .5
		shield_material.scale_min = .6
		shield_material.scale_max = 1.0
		_glints.append(_emitter("BrilhoEscudo%d" % (index + 1), SHIELD_AMOUNT, .5, true, glint_mesh, shield_material))
	var party_material: ParticleProcessMaterial = _process_material(Color.WHITE, Vector3(0, 1, 0), Vector3(0, -4.5, 0))
	party_material.emission_box_extents = Vector3(.8, .2, 2.8)
	party_material.spread = 42.0
	party_material.initial_velocity_min = 3.5
	party_material.initial_velocity_max = 5.5
	party_material.scale_min = .7
	party_material.scale_max = 1.3
	party_material.rotation_velocity_3d_min = Vector3(-180, -240, -120)
	party_material.rotation_velocity_3d_max = Vector3(180, 240, 120)
	var palette: Gradient = Gradient.new()
	palette.offsets = PackedFloat32Array([0.0, .25, .50, .75, 1.0])
	palette.colors = PackedColorArray([Color("ffda2f"), Color("16db69"), Color("33b8ff"), Color("ffffff"), Color("ff4771")])
	palette.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var palette_texture: GradientTexture1D = GradientTexture1D.new()
	palette_texture.gradient = palette
	party_material.color_initial_ramp = palette_texture
	_party = _emitter("ConfeteDeCelebracao", PARTY_AMOUNT, 2.4, true, paper_mesh, party_material)
	_party.explosiveness = .85
	_party.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 9, 12))
	set_paused(_paused)
	assert(int(get_effect_budget()["particle_capacity"]) <= MAX_PARTICLES)


func _process_material(color: Color, direction: Vector3, gravity: Vector3) -> ParticleProcessMaterial:
	var material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	material.color = color
	material.direction = direction.normalized()
	material.gravity = gravity
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.lifetime_randomness = .25
	var fade: Gradient = Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, .10, .65, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color(1, 1, 1, .8), Color(1, 1, 1, 0)])
	var fade_texture: GradientTexture1D = GradientTexture1D.new()
	fade_texture.gradient = fade
	material.color_ramp = fade_texture
	return material


func _particle_material(additive: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	return material


func _emitter(node_name: String, amount: int, lifetime: float, one_shot: bool, mesh: Mesh, material: ParticleProcessMaterial) -> GPUParticles3D:
	var emitter: GPUParticles3D = GPUParticles3D.new()
	emitter.name = node_name
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.one_shot = one_shot
	emitter.explosiveness = 1.0 if one_shot else 0.0
	emitter.emitting = false
	emitter.local_coords = false
	emitter.fixed_fps = 60
	emitter.interpolate = true
	emitter.draw_passes = 1
	emitter.draw_pass_1 = mesh
	emitter.process_material = material
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 5, 6))
	emitter.layers = _render_layer
	add_child(emitter)
	return emitter


func _update_emitters(index: int) -> void:
	_boosts[index].global_position = _positions[index] + Vector3(-.55, .32, 0.0)
	_impacts[index].global_position = _positions[index] + Vector3(-.10, .16, 0.0)
	_glints[index].global_position = _positions[index] + Vector3(0.0, 1.1, 0.0)


func _update_boost(index: int) -> void:
	if not _boosts.is_empty():
		_boosts[index].emitting = _boost_active[index] or _boost_flash_remaining[index] > 0.0
