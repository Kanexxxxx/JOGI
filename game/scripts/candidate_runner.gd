class_name CandidateRunner
extends CharacterBody3D

signal runner_finished(runner: CandidateRunner)
signal boost_activated(runner: CandidateRunner, amount: float, duration: float)
signal runner_stumbled(runner: CandidateRunner, duration: float)
signal shield_absorbed_hit(runner: CandidateRunner)

@export var candidate_id: int = 1
@export var candidate_name: String = "LULA"
@export var signature_color: Color = Color("#FF3B5C")
@export var text_color: Color = Color("#FFFFFF")
@export var base_speed: float = 12.0
@export var track_length: float = 100.0

var start_position: Vector3 = Vector3.ZERO
var start_z: float = 0.0
var progress_m: float = 0.0
var progress_ratio: float = 0.0
var current_speed: float = 0.0
var is_racing: bool = false
var is_finished: bool = false
var finish_time: float = 0.0

var lobby_votes: int = 0
var boost_amount: float = 0.0
var boost_timer: float = 0.0
var boost_count: int = 0

var shield_timer: float = 0.0
var shield_absorbed_count: int = 0

var stumble_timer: float = 0.0
var stumble_penalty_factor: float = 0.38
var grace_timer: float = 0.0
var stumble_count: int = 0

var stride_phase: float = 0.0
var stride_freq: float = 6.8
var stride_amp: float = 0.85
var rubber_band_bonus: float = 0.0
var motion_time_scale: float = 1.0

var _triggered_obstacles: Dictionary = {}
var _collision_shape: CollisionShape3D = null
var _visual_root: Node3D = null

# Partes do modelo caricato procedural 3D
var _body_mesh: MeshInstance3D = null
var _head_mesh: MeshInstance3D = null
var _hair_mesh: MeshInstance3D = null
var _beard_mesh: MeshInstance3D = null
var _sash_mesh: MeshInstance3D = null
var _boost_ring: MeshInstance3D = null
var _shield_sphere: MeshInstance3D = null

var _body_material: StandardMaterial3D = null
var _head_material: StandardMaterial3D = null
var _boost_material: StandardMaterial3D = null
var _shield_material: StandardMaterial3D = null


func _ready() -> void:
	_build_visuals_and_collision()
	_apply_candidate_theme()
	_update_progress()


func _exit_tree() -> void:
	_triggered_obstacles.clear()


func configure(
	p_id: int,
	p_name: String,
	p_color: Color,
	p_text_color: Color,
	p_start_pos: Vector3,
	p_track_length: float
) -> void:
	candidate_id = p_id
	candidate_name = p_name
	signature_color = p_color
	text_color = p_text_color
	track_length = maxf(p_track_length, 1.0)
	stride_phase = float(p_id) * 1.57
	stride_freq = 6.5 + float(p_id % 2) * 0.4
	reset_runner(p_start_pos)
	if is_node_ready():
		_apply_candidate_theme()


func reset_runner(p_start_pos: Vector3) -> void:
	start_position = p_start_pos
	start_z = p_start_pos.z
	global_position = p_start_pos
	velocity = Vector3.ZERO
	current_speed = 0.0
	progress_m = 0.0
	progress_ratio = 0.0
	is_racing = false
	is_finished = false
	finish_time = 0.0
	lobby_votes = 0
	boost_amount = 0.0
	boost_timer = 0.0
	boost_count = 0
	shield_timer = 0.0
	shield_absorbed_count = 0
	stumble_timer = 0.0
	stumble_penalty_factor = 0.38
	grace_timer = 0.0
	stumble_count = 0
	rubber_band_bonus = 0.0
	motion_time_scale = 1.0
	_triggered_obstacles.clear()

	if _visual_root != null:
		_visual_root.position = Vector3.ZERO
		_visual_root.rotation = Vector3.ZERO
	if _boost_ring != null:
		_boost_ring.visible = false
	if _shield_sphere != null:
		_shield_sphere.visible = false
	if _body_material != null:
		_body_material.emission_enabled = false


func register_lobby_vote(weight: int = 1) -> void:
	lobby_votes += maxi(weight, 1)


func start_running() -> void:
	if is_finished:
		return
	is_racing = true
	if lobby_votes > 0:
		var start_bonus: float = minf(float(lobby_votes) * 0.9, 5.5)
		apply_boost(start_bonus, 2.5)
	else:
		current_speed = base_speed


func stop_running() -> void:
	is_racing = false
	velocity = Vector3.ZERO
	current_speed = 0.0


func apply_boost(amount: float, duration: float = 3.5) -> void:
	if is_finished:
		return
	stumble_timer = 0.0
	boost_amount = maxf(boost_amount, amount)
	boost_timer = clampf(boost_timer + duration, 0.0, 10.0)
	boost_count += 1
	current_speed = maxf(current_speed, base_speed + boost_amount)
	if _boost_ring != null:
		_boost_ring.visible = true
	if _body_material != null:
		_body_material.emission_enabled = true
		_body_material.emission = signature_color
		_body_material.emission_energy_multiplier = 0.75
	boost_activated.emit(self, amount, duration)


func apply_shield(duration: float = 5.0) -> void:
	if is_finished:
		return
	shield_timer = clampf(maxf(shield_timer, duration), 0.5, 15.0)
	stumble_timer = 0.0
	if _shield_sphere != null:
		_shield_sphere.visible = true


func apply_stumble(duration: float = 1.2, penalty_factor: float = 0.38) -> bool:
	if is_finished:
		return false

	# 1. Escudo ativo absorve o impacto do obstáculo político
	if shield_timer > 0.0:
		shield_absorbed_count += 1
		shield_timer = 0.0
		grace_timer = maxf(grace_timer, 1.2)
		if _shield_sphere != null:
			_shield_sphere.visible = false
		shield_absorbed_hit.emit(self)
		return false

	# 2. Imunidade pós-queda (grace period)
	if grace_timer > 0.0:
		return false

	# 3. Penalidade de tropeço com inclinação visual
	stumble_timer = maxf(duration, 0.2)
	stumble_penalty_factor = clampf(penalty_factor, 0.15, 0.85)
	grace_timer = 1.8
	stumble_count += 1
	boost_amount = 0.0
	boost_timer = 0.0
	current_speed = base_speed * stumble_penalty_factor

	if _boost_ring != null:
		_boost_ring.visible = false
	if _body_material != null:
		_body_material.emission_enabled = true
		_body_material.emission = Color("#FF2A85")
		_body_material.emission_energy_multiplier = 0.85
	if _visual_root != null:
		_visual_root.rotation.x = 0.45
		_visual_root.rotation.z = 0.25

	runner_stumbled.emit(self, stumble_timer)
	return true


func has_triggered_obstacle(obstacle_key: String) -> bool:
	return _triggered_obstacles.has(obstacle_key)


func mark_obstacle_triggered(obstacle_key: String) -> void:
	_triggered_obstacles[obstacle_key] = true


func _physics_process(delta: float) -> void:
	var scaled_delta: float = delta * motion_time_scale

	if grace_timer > 0.0:
		grace_timer = maxf(0.0, grace_timer - scaled_delta)

	if shield_timer > 0.0:
		shield_timer = maxf(0.0, shield_timer - scaled_delta)
		if shield_timer <= 0.0:
			if _shield_sphere != null:
				_shield_sphere.visible = false

	if stumble_timer > 0.0:
		stumble_timer = maxf(0.0, stumble_timer - scaled_delta)
		if stumble_timer <= 0.0:
			if _body_material != null and boost_timer <= 0.0:
				_body_material.emission_enabled = false

	if not is_racing or is_finished:
		velocity = Vector3.ZERO
		if _visual_root != null:
			_visual_root.position.y = lerpf(_visual_root.position.y, 0.0, minf(delta * 10.0, 1.0))
			_visual_root.rotation.x = lerpf(_visual_root.rotation.x, 0.0, minf(delta * 10.0, 1.0))
			_visual_root.rotation.z = lerpf(_visual_root.rotation.z, 0.0, minf(delta * 10.0, 1.0))
		return

	if boost_timer > 0.0:
		boost_timer = maxf(0.0, boost_timer - scaled_delta)
		if boost_timer <= 0.0:
			boost_amount = 0.0
			if _boost_ring != null:
				_boost_ring.visible = false
			if _body_material != null:
				_body_material.emission_enabled = false

	stride_phase += scaled_delta * stride_freq
	var organic_variation: float = (
		sin(stride_phase) * stride_amp
		+ cos(stride_phase * 0.65 + float(candidate_id)) * 0.45
	)

	var target_speed: float = maxf(
		3.0,
		base_speed + organic_variation + rubber_band_bonus + boost_amount
	)
	if stumble_timer > 0.0:
		target_speed = base_speed * stumble_penalty_factor

	current_speed = lerpf(current_speed, target_speed, minf(scaled_delta * 12.0, 1.0))

	velocity = Vector3(0.0, 0.0, -current_speed * motion_time_scale)
	var prev_z: float = global_position.z
	if Engine.is_in_physics_frame() and is_equal_approx(motion_time_scale, 1.0):
		move_and_slide()
	if is_equal_approx(global_position.z, prev_z):
		global_position.z -= current_speed * scaled_delta
	global_position.x = start_position.x
	global_position.y = start_position.y

	_animate_procedural_stride(scaled_delta)
	_update_progress()


func _animate_procedural_stride(delta: float) -> void:
	if _visual_root == null:
		return
	if stumble_timer > 0.0:
		_visual_root.position.y = absf(sin(stride_phase * 3.0)) * 0.08
		_visual_root.rotation.x = lerpf(_visual_root.rotation.x, 0.45, minf(delta * 10.0, 1.0))
		_visual_root.rotation.z = sin(stride_phase * 4.0) * 0.28
		return

	var speed_factor: float = clampf(current_speed / maxf(base_speed, 1.0), 0.5, 2.2)
	var bob: float = absf(sin(stride_phase * 2.0)) * 0.15 * speed_factor
	var sway: float = cos(stride_phase) * 0.09 * speed_factor
	var forward_lean: float = -0.15 * speed_factor
	_visual_root.position.y = bob
	_visual_root.rotation.z = sway
	_visual_root.rotation.x = lerpf(_visual_root.rotation.x, forward_lean, minf(delta * 10.0, 1.0))


func _update_progress() -> void:
	# Acúmulo infinito de distância em metros percorridos a partir da largada
	progress_m = maxf(0.0, start_z - global_position.z)
	progress_ratio = clampf(progress_m / maxf(track_length, 1.0), 0.0, 1.0)


func _build_visuals_and_collision() -> void:
	if _collision_shape != null:
		return

	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "CollisionShape3D"
	var capsule_shape: CapsuleShape3D = CapsuleShape3D.new()
	capsule_shape.radius = 0.45
	capsule_shape.height = 1.85
	_collision_shape.shape = capsule_shape
	_collision_shape.position = Vector3(0.0, 0.92, 0.0)
	add_child(_collision_shape)

	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	# Materiais base
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = signature_color
	_body_material.roughness = 0.45
	_body_material.metallic = 0.05

	_head_material = StandardMaterial3D.new()
	_head_material.albedo_color = Color("#E0AC69") # Tom de pele natural caricato
	_head_material.roughness = 0.55

	_boost_material = StandardMaterial3D.new()
	_boost_material.albedo_color = Color("#00F5D4")
	_boost_material.emission_enabled = true
	_boost_material.emission = Color("#00F5D4")
	_boost_material.emission_energy_multiplier = 2.2

	_shield_material = StandardMaterial3D.new()
	_shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_material.albedo_color = Color(0.2, 0.75, 1.0, 0.35)
	_shield_material.emission_enabled = true
	_shield_material.emission = Color("#38BDF8")
	_shield_material.emission_energy_multiplier = 1.6

	# 1. Corpo/Torso
	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "BodyMesh"
	var body_capsule: CapsuleMesh = CapsuleMesh.new()
	body_capsule.radius = 0.42
	body_capsule.height = 1.30
	_body_mesh.mesh = body_capsule
	_body_mesh.position = Vector3(0.0, 0.70, 0.0)
	_body_mesh.material_override = _body_material
	_visual_root.add_child(_body_mesh)

	# 2. Cabeça Caricata Avantajada (1.4x)
	_head_mesh = MeshInstance3D.new()
	_head_mesh.name = "HeadMesh"
	var head_sphere: SphereMesh = SphereMesh.new()
	head_sphere.radius = 0.52
	head_sphere.height = 1.04
	_head_mesh.mesh = head_sphere
	_head_mesh.position = Vector3(0.0, 1.70, 0.0)
	_head_mesh.material_override = _head_material
	_visual_root.add_child(_head_mesh)

	# 3. Nariz Caricato
	var nose_mesh: MeshInstance3D = MeshInstance3D.new()
	nose_mesh.name = "NoseMesh"
	var nose_box: BoxMesh = BoxMesh.new()
	nose_box.size = Vector3(0.14, 0.16, 0.20)
	nose_mesh.mesh = nose_box
	nose_mesh.position = Vector3(0.0, 1.68, -0.48)
	nose_mesh.material_override = _head_material
	_visual_root.add_child(nose_mesh)

	# 4. Detalhes Específicos de Lula vs Bolsonaro
	_build_caricature_features()

	# 5. Anel de Turbo no Chão
	_boost_ring = MeshInstance3D.new()
	_boost_ring.name = "BoostRing"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.50
	torus.outer_radius = 0.72
	_boost_ring.mesh = torus
	_boost_ring.position = Vector3(0.0, 0.12, 0.0)
	_boost_ring.material_override = _boost_material
	_boost_ring.visible = false
	_visual_root.add_child(_boost_ring)

	# 6. Esfera de Escudo Protetor
	_shield_sphere = MeshInstance3D.new()
	_shield_sphere.name = "ShieldAura"
	var s_sphere: SphereMesh = SphereMesh.new()
	s_sphere.radius = 0.98
	s_sphere.height = 2.25
	_shield_sphere.mesh = s_sphere
	_shield_sphere.position = Vector3(0.0, 1.15, 0.0)
	_shield_sphere.material_override = _shield_material
	_shield_sphere.visible = false
	_visual_root.add_child(_shield_sphere)

	# NOTA: O nó Label3D foi 100% ELIMINADO para evitar poluição visual sobreposta na pista.


func _build_caricature_features() -> void:
	if candidate_id == 1:
		# === LULA (#1 - Vermelho) ===
		# Cabelo grisalho volumoso
		_hair_mesh = MeshInstance3D.new()
		_hair_mesh.name = "LulaHair"
		var hair_sphere: SphereMesh = SphereMesh.new()
		hair_sphere.radius = 0.53
		hair_sphere.height = 0.70
		_hair_mesh.mesh = hair_sphere
		_hair_mesh.position = Vector3(0.0, 1.96, 0.04)
		var hair_mat: StandardMaterial3D = StandardMaterial3D.new()
		hair_mat.albedo_color = Color("#D1D5DB") # Cinza claro grisalho
		hair_mat.roughness = 0.85
		_hair_mesh.material_override = hair_mat
		_visual_root.add_child(_hair_mesh)

		# BARBA BRANCA/GRISALHA CHEIA PROCEDURAL (Identidade icônica de Lula)
		_beard_mesh = MeshInstance3D.new()
		_beard_mesh.name = "LulaBeard"
		var beard_mesh_res: BoxMesh = BoxMesh.new()
		beard_mesh_res.size = Vector3(0.66, 0.42, 0.42)
		_beard_mesh.mesh = beard_mesh_res
		_beard_mesh.position = Vector3(0.0, 1.44, -0.30)
		var beard_mat: StandardMaterial3D = StandardMaterial3D.new()
		beard_mat.albedo_color = Color("#E5E7EB") # Barba branca/grisalha
		beard_mat.roughness = 0.90
		_beard_mesh.material_override = beard_mat
		_visual_root.add_child(_beard_mesh)

		# Bigode sob o nariz
		var mustache: MeshInstance3D = MeshInstance3D.new()
		mustache.name = "LulaMustache"
		var must_box: BoxMesh = BoxMesh.new()
		must_box.size = Vector3(0.44, 0.12, 0.18)
		mustache.mesh = must_box
		mustache.position = Vector3(0.0, 1.58, -0.44)
		mustache.material_override = beard_mat
		_visual_root.add_child(mustache)

	else:
		# === BOLSONARO (#2 - Azul / Amarelo / Verde) ===
		# Cabelo escuro/grisalho dividido lateral
		_hair_mesh = MeshInstance3D.new()
		_hair_mesh.name = "BolsonaroHair"
		var hair_box: BoxMesh = BoxMesh.new()
		hair_box.size = Vector3(0.96, 0.28, 0.88)
		_hair_mesh.mesh = hair_box
		_hair_mesh.position = Vector3(0.0, 2.05, 0.0)
		var hair_mat: StandardMaterial3D = StandardMaterial3D.new()
		hair_mat.albedo_color = Color("#374151") # Castanho escuro com entradas grisalhas
		hair_mat.roughness = 0.70
		_hair_mesh.material_override = hair_mat
		_visual_root.add_child(_hair_mesh)

		# FAIXA PRESIDENCIAL VERDE-AMARELA DIAGONAL NO PEITO
		_sash_mesh = MeshInstance3D.new()
		_sash_mesh.name = "PresidentialSash"
		var sash_box: BoxMesh = BoxMesh.new()
		sash_box.size = Vector3(0.24, 0.95, 0.75)
		_sash_mesh.mesh = sash_box
		_sash_mesh.position = Vector3(0.08, 0.82, 0.0)
		_sash_mesh.rotation = Vector3(0.0, 0.0, 0.58) # Inclinada diagonalmente no peito
		var sash_mat: StandardMaterial3D = StandardMaterial3D.new()
		sash_mat.albedo_color = Color("#10B981") # Verde bandeira vibrante
		sash_mat.roughness = 0.40
		sash_mat.emission_enabled = true
		sash_mat.emission = Color("#FBBF24") # Detalhe amarelo ouro
		sash_mat.emission_energy_multiplier = 0.35
		_sash_mesh.material_override = sash_mat
		_visual_root.add_child(_sash_mesh)


func _apply_candidate_theme() -> void:
	if _body_material != null:
		_body_material.albedo_color = signature_color
