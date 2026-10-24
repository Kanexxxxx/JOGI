class_name RaceMain
extends Node3D

signal state_changed(new_state: int)
signal race_finished(winner: CandidateRunner)
signal round_changed(round_id: int, cycle_id: int, metadata: Dictionary)

enum RaceState {
	LOBBY_VOTACAO = 0,
	COUNTDOWN = 1,
	RACING = 2,
	PHOTO_FINISH = 3,
	PODIO = 4
}

# Elenco da sátira; os obstáculos representam mecânicas fictícias.
const CANDIDATE_DEFS: Array[Dictionary] = [
	{"id": 1, "name": "LULA", "color": "#FF3B5C", "text": "#FFFFFF", "speed": 12.0},
	{"id": 2, "name": "FLÁVIO BOLSONARO", "color": "#FACC15", "text": "#052E16", "speed": 12.0}
]

const TELEMETRY_INTERVAL: float = 0.10
const CHUNK_LENGTH: float = 40.0
const CHUNK_COUNT: int = 8
const TRACK_WIDTH: float = 6.4
const ROUNDS_PER_CYCLE: int = 50
const ROUND_CATALOG_PATH: String = "res://resources/rounds_brasilia.json"
const DRAW_DISTANCE_METERS: float = 0.01
const DISTANCE_COMPARISON_EPSILON: float = 0.000000001

@export var match_duration: float = 600.0 # Dez minutos por rodada; configurável no Inspector.
@export var track_length: float = 100.0
@export var lane_width: float = 2.4
@export var lobby_duration: float = 6.0
@export var countdown_duration: float = 3.0
@export var photo_finish_duration: float = 3.0
@export var podium_duration: float = 24.0 # 3 s chegada + 24 s pódio + 3 s contagem = 30 s.
@export var obstacles_enabled: bool = true
@export var auto_loop_after_podium: bool = true

var current_state: RaceState = RaceState.LOBBY_VOTACAO
var state_timer: float = 6.0
var countdown_remaining: float = 3.0
var match_time_remaining: float = 600.0
var race_elapsed_time: float = 0.0
var current_round: int = 1
var cycle_number: int = 1
var cycle_wins: Array[int] = [0, 0]
var race_paused: bool = false
var round_metadata: Dictionary = {}
var live_goal: Dictionary = {"goal_kind": "likes", "goal_target": 1000, "goal_label": "Meta de curtidas"}
var live_goals: Dictionary = default_live_goals()
var audio_settings: Dictionary = {"voices_enabled": true, "sfx_enabled": true, "crowd_enabled": true, "memes_enabled": true}


static func default_live_goals() -> Dictionary:
	return {
		"likes": {"goal_kind": "likes", "goal_target": 1000, "goal_label": "Meta de curtidas"},
		"gifts": {"goal_kind": "gifts", "goal_target": 500, "goal_label": "Meta de presentes"},
		"follows": {
			"goal_kind": "follows",
			"goal_target": 10000,
			"goal_label": "Meta de seguidores",
			"follower_baseline": null,
			"baseline_updated_at": null
		}
	}
## At most two bounded aggregates; accounting stays in AudienceDirector.
var pending_round_effects: Dictionary = {}
var _round_catalog: Array[Dictionary] = []
var _round_result_recorded: bool = false
var _recorded_winner_slot: int = 0

var runners: Array[CandidateRunner] = []
var rankings: Array[CandidateRunner] = []
var winner: CandidateRunner = null
var event_bus: LiveEventBusInstance = null
var match_events_count: int = 0
var last_live_event_text: String = "Aguardando eventos da live..."
var _telemetry_timer: float = 0.0

# Nós da cena
var _world_env: WorldEnvironment = null
var _sun_light: DirectionalLight3D = null
var _track_root: Node3D = null
var _track_chunks: Array[Node3D] = []
var _obstacles_root: Node3D = null
var _runners_root: Node3D = null
var race_camera: RaceCamera = null
var _hud_layer: CanvasLayer = null

# Elementos do HUD 2D
var _match_timer_label: Label = null
var _state_badge_label: Label = null
var _ws_status_label: Label = null
var _tug_of_war_bar: ProgressBar = null
var _advantage_label: Label = null

# Cards dos 2 candidatos no HUD
var _card_lula_dist: Label = null
var _card_lula_speed: Label = null
var _card_lula_badges: Label = null
var _card_bolso_dist: Label = null
var _card_bolso_speed: Label = null
var _card_bolso_badges: Label = null

var _live_event_banner_label: Label = null
var _center_banner_panel: PanelContainer = null
var _center_banner_title: Label = null
var _center_banner_subtitle: Label = null
var _toast_label: Label = null
var _toast_timer: float = 0.0
var _shared_geometries_built: bool = false


func _ready() -> void:
	_load_round_catalog()
	_select_round_metadata()
	match_time_remaining = match_duration
	_setup_environment_and_lights()
	_setup_track_geometry()
	_setup_obstacles()
	_setup_runners()
	_setup_camera()
	_setup_hud()
	_connect_live_event_bus()
	restart_race(false)


func _exit_tree() -> void:
	runners.clear()
	rankings.clear()
	_track_chunks.clear()
	winner = null
	event_bus = null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		match key_event.keycode:
			KEY_R, KEY_SPACE:
				restart_race(false)
			KEY_1, KEY_KP_1:
				trigger_candidate_boost(1)
			KEY_2, KEY_KP_2:
				trigger_candidate_boost(2)
			KEY_3, KEY_KP_3:
				# Tecla 3: Atacar Bolsonaro com Processos
				spawn_political_obstacle(2, "pilha_documentos", "Teclado")
			KEY_4, KEY_KP_4:
				# Tecla 4: Atacar Lula com Processos
				spawn_political_obstacle(1, "pilha_documentos", "Teclado")


func _physics_process(delta: float) -> void:
	if race_paused:
		return
	if _toast_timer > 0.0:
		_toast_timer = maxf(0.0, _toast_timer - delta)
		if _toast_timer <= 0.0 and _toast_label != null:
			_toast_label.text = "Digite #1 (Lula) ou #2 (Flávio Bolsonaro) para acelerar!"

	match current_state:
		RaceState.LOBBY_VOTACAO:
			state_timer = maxf(0.0, state_timer - delta)
			if state_timer <= 0.0:
				start_countdown()

		RaceState.COUNTDOWN:
			state_timer = maxf(0.0, state_timer - delta)
			countdown_remaining = state_timer
			if state_timer <= 0.0:
				start_racing()

		RaceState.RACING:
			race_elapsed_time += minf(delta, match_time_remaining)
			match_time_remaining = maxf(0.0, match_time_remaining - delta)

			# Atualiza reciclagem contínua da pista infinita
			_recycle_track_chunks()

			# Condição de encerramento: cronômetro zerou! Vence a maior distância acumulada
			if match_time_remaining <= 0.0:
				_finish_match_by_timer()

		RaceState.PHOTO_FINISH:
			state_timer = maxf(0.0, state_timer - delta)
			if state_timer <= 0.0:
				_transition_to_state(RaceState.PODIO)

		RaceState.PODIO:
			state_timer = maxf(0.0, state_timer - delta)
			if state_timer <= 0.0 and auto_loop_after_podium:
				_advance_round()

	_update_rankings()
	_update_hud()
	_prune_obstacles()

	# Telemetria periódica (10 Hz)
	_telemetry_timer += delta
	if _telemetry_timer >= TELEMETRY_INTERVAL:
		_telemetry_timer = 0.0
		send_telemetry_now()


func _get_lane_x(index: int, _total: int = 2) -> float:
	# Raia 1 (Lula): x = -1.4 | Raia 2 (Bolsonaro): x = +1.4
	return -1.4 if index == 0 else 1.4


func get_runner_by_id(id: int) -> CandidateRunner:
	for r: CandidateRunner in runners:
		if r.candidate_id == id:
			return r
	return null


func _finish_match_by_timer() -> void:
	if current_state != RaceState.RACING or _round_result_recorded:
		return
	for r: CandidateRunner in runners:
		r.stop_running()
		r.is_finished = true

	_update_rankings()
	if not rankings.is_empty():
		# Distâncias iguais encerram em empate; não privilegia a ordem dos slots.
		if rankings.size() == 1 or absf(rankings[0].progress_m - rankings[1].progress_m) > DRAW_DISTANCE_METERS + DISTANCE_COMPARISON_EPSILON:
			winner = rankings[0]
			_recorded_winner_slot = winner.candidate_id
			cycle_wins[_recorded_winner_slot - 1] += 1
	_round_result_recorded = true
	_transition_to_state(RaceState.PHOTO_FINISH)
	race_finished.emit(winner)


func _update_rankings() -> void:
	rankings = runners.duplicate()
	rankings.sort_custom(func(a: CandidateRunner, b: CandidateRunner) -> bool:
		return a.progress_m > b.progress_m
	)


func start_race_immediately() -> void:
	if current_state == RaceState.RACING:
		return
	start_racing()


func start_countdown() -> void:
	if current_state != RaceState.LOBBY_VOTACAO and current_state != RaceState.COUNTDOWN:
		return
	state_timer = countdown_duration
	countdown_remaining = countdown_duration
	_transition_to_state(RaceState.COUNTDOWN)


func start_racing() -> void:
	if current_state == RaceState.RACING or _round_result_recorded:
		return
	_transition_to_state(RaceState.RACING)
	for r: CandidateRunner in runners:
		r.start_running()
	_apply_reserved_round_effects()


func restart_race(p_skip_lobby: bool = false) -> void:
	# Reinício administrativo repete a rodada; não conta uma tentativa cancelada.
	if _round_result_recorded and _recorded_winner_slot in [1, 2]:
		cycle_wins[_recorded_winner_slot - 1] = maxi(0, cycle_wins[_recorded_winner_slot - 1] - 1)
	_round_result_recorded = false
	_recorded_winner_slot = 0
	set_race_paused(false)
	match_time_remaining = match_duration
	race_elapsed_time = 0.0
	match_events_count = 0
	last_live_event_text = "Rodada %d/50 · %s" % [current_round, String(round_metadata.get("name", "Brasília"))]
	_set_live_banner(last_live_event_text)
	winner = null
	_telemetry_timer = 0.0

	var total_candidates: int = CANDIDATE_DEFS.size()
	for i: int in range(runners.size()):
		var r: CandidateRunner = runners[i]
		var lx: float = _get_lane_x(i, total_candidates)
		r.reset_runner(Vector3(lx, 0.0, 0.0))

	_reset_track_chunks()
	_clear_dynamic_obstacles()
	_update_rankings()

	if p_skip_lobby:
		state_timer = countdown_duration
		countdown_remaining = countdown_duration
		_transition_to_state(RaceState.COUNTDOWN)
	else:
		state_timer = lobby_duration
		countdown_remaining = countdown_duration
		_transition_to_state(RaceState.LOBBY_VOTACAO)

	send_telemetry_now()


func _load_round_catalog() -> void:
	_round_catalog.clear()
	if not FileAccess.file_exists(ROUND_CATALOG_PATH):
		push_error("Catálogo de rodadas ausente: " + ROUND_CATALOG_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUND_CATALOG_PATH))
	if not parsed is Dictionary:
		push_error("Catálogo de rodadas inválido")
		return
	var entries: Variant = (parsed as Dictionary).get("rounds", [])
	if not entries is Array or (entries as Array).size() != ROUNDS_PER_CYCLE:
		push_error("Catálogo deve conter exatamente 50 rodadas")
		return
	for index: int in range(ROUNDS_PER_CYCLE):
		var entry: Variant = entries[index]
		if not entry is Dictionary or int(entry.get("id", 0)) != index + 1:
			_round_catalog.clear()
			push_error("IDs do catálogo devem seguir a sequência de 1 a 50")
			return
		_round_catalog.append((entry as Dictionary).duplicate(true))


func _select_round_metadata() -> void:
	round_metadata = {"id": current_round, "name": "Rodada %d" % current_round, "duration_seconds": match_duration}
	if _round_catalog.size() == ROUNDS_PER_CYCLE:
		round_metadata = _round_catalog[current_round - 1].duplicate(true)
	# O catálogo descreve o padrão; o Inspector conserva a duração configurável.
	round_metadata["duration_seconds"] = match_duration
	round_changed.emit(current_round, cycle_number, round_metadata.duplicate(true))


func _advance_round() -> void:
	if current_state != RaceState.PODIO or not _round_result_recorded:
		return
	# Preserva o resultado encerrado; restart só desfaz tentativas manuais.
	_round_result_recorded = false
	_recorded_winner_slot = 0
	if current_round >= ROUNDS_PER_CYCLE:
		cycle_number += 1
		current_round = 1
		cycle_wins.assign([0, 0])
	else:
		current_round += 1
	_select_round_metadata()
	restart_race(true)


func set_race_paused(paused: bool) -> void:
	race_paused = paused
	for runner: CandidateRunner in runners:
		runner.set_physics_process(not paused)
	send_telemetry_now()


func _clear_dynamic_obstacles() -> void:
	if _obstacles_root != null:
		for child: Node in _obstacles_root.get_children():
			child.queue_free()


func _prune_obstacles() -> void:
	if _obstacles_root == null:
		return
	var now_ms: int = Time.get_ticks_msec()
	for child: Node in _obstacles_root.get_children():
		var area: Area3D = child as Area3D
		if area == null or area.is_queued_for_deletion():
			continue
		var target: CandidateRunner = get_runner_by_id(int(area.get_meta("target_slot", 0)))
		if target == null or area.global_position.z > target.global_position.z + 2.0 or now_ms - int(area.get_meta("created_ms", now_ms)) > 20000:
			area.queue_free()


func trigger_candidate_boost(
	candidate_id: int,
	amount: float = 5.0,
	duration: float = 3.5,
	voter_name: String = "Local",
	source_label: String = "TURBO"
) -> void:
	match_events_count += 1
	var runner: CandidateRunner = get_runner_by_id(candidate_id)
	if runner == null:
		return

	if current_state == RaceState.LOBBY_VOTACAO:
		runner.register_lobby_vote(1)
		var msg: String = "🗳️ @%s votou em #%d %s!" % [voter_name, runner.candidate_id, runner.candidate_name]
		_set_live_banner(msg)
		_show_toast(msg)
	else:
		runner.apply_boost(amount, duration)
		var msg: String = "⚡ @%s deu TURBO em #%d %s (+%.1f m/s)!" % [
			voter_name,
			runner.candidate_id,
			runner.candidate_name,
			amount
		]
		_set_live_banner(msg)
		_show_toast(msg)

	_update_hud()
	send_telemetry_now()


func trigger_candidate_shield(candidate_id: int, duration: float = 5.0, voter_name: String = "Local") -> void:
	if should_reserve_paid_effect():
		_reserve_round_effect(candidate_id, "shield", duration)
		return
	match_events_count += 1
	var runner: CandidateRunner = get_runner_by_id(candidate_id)
	if runner == null:
		return
	runner.apply_shield(duration)
	var msg: String = "🛡️ @%s ativou ESCUDO em #%d %s!" % [voter_name, runner.candidate_id, runner.candidate_name]
	_set_live_banner(msg)
	_show_toast(msg)
	_update_hud()
	send_telemetry_now()


# Sistema dinâmico de ataques políticos (pilhas de documentos na raia do oponente)
func spawn_political_obstacle(
	target_slot: int,
	_obstacle_type: String = "pilha_documentos",
	voter_name: String = "Oponente"
) -> Area3D:
	if should_reserve_paid_effect():
		_reserve_round_effect(target_slot, "attack", 1.0)
		return null
	match_events_count += 1
	var target_runner: CandidateRunner = get_runner_by_id(target_slot)
	if target_runner == null or _obstacles_root == null:
		return null
	_prune_obstacles()
	var active: Array[Area3D] = []
	for child: Node in _obstacles_root.get_children():
		if child is Area3D and not child.is_queued_for_deletion():
			active.append(child as Area3D)
	if active.size() >= 64:
		# Rajadas pagas continuam no ranking; ataques sobrepostos compartilham a pilha.
		for existing: Area3D in active:
			if int(existing.get_meta("target_slot", 0)) == target_slot:
				return existing
		return null

	var lane_x: float = _get_lane_x(target_slot - 1, 2)
	# Spawna 16 metros à frente da posição Z atual do corredor alvo
	var spawn_z: float = target_runner.global_position.z - 16.0

	var obs_area: Area3D = Area3D.new()
	obs_area.name = "DocAttack_%d_%d" % [target_slot, int(Time.get_ticks_msec())]
	obs_area.set_meta("target_slot", target_slot)
	obs_area.set_meta("obstacle_type", _obstacle_type)
	obs_area.set_meta("created_ms", Time.get_ticks_msec())
	obs_area.position = Vector3(lane_x, 0.45, spawn_z)
	_obstacles_root.add_child(obs_area)

	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(lane_width * 0.75, 0.9, 0.8)
	col_shape.shape = box_shape
	obs_area.add_child(col_shape)

	# Visual caricato 3D: Pilha de Processos / Caixas de Documentos Judiciais
	var papers_mesh: MeshInstance3D = MeshInstance3D.new()
	papers_mesh.name = "DocumentStackMesh"
	var p_box: BoxMesh = BoxMesh.new()
	p_box.size = Vector3(1.1, 0.7, 0.6)
	papers_mesh.mesh = p_box
	var doc_mat: StandardMaterial3D = StandardMaterial3D.new()
	doc_mat.albedo_color = Color("#FEF3C7") # Tom de papel/pastas de arquivo
	doc_mat.roughness = 0.8
	doc_mat.emission_enabled = true
	doc_mat.emission = Color("#EF4444") # Carimbo vermelho de processo
	doc_mat.emission_energy_multiplier = 0.4
	papers_mesh.material_override = doc_mat
	obs_area.add_child(papers_mesh)

	var msg_spawn: String = "📁 @%s jogou PROCESSOS na raia de %s!" % [voter_name, target_runner.candidate_name]
	_set_live_banner(msg_spawn)
	_show_toast(msg_spawn)

	var captured_target: CandidateRunner = target_runner
	var captured_area: Area3D = obs_area
	var captured_voter: String = voter_name

	obs_area.body_entered.connect(func(body: Node3D) -> void:
		if body == captured_target:
			var stumbled: bool = captured_target.apply_stumble(1.2, 0.38)
			if stumbled:
				var hit_msg: String = "💥 %s TROPEÇOU NA PILHA DE PROCESSOS DE @%s!" % [
					captured_target.candidate_name,
					captured_voter
				]
				_set_live_banner(hit_msg)
				_show_toast(hit_msg)
			else:
				var shield_msg: String = "🛡️ %s USOU O ESCUDO E DESTRUIU OS PROCESSOS!" % captured_target.candidate_name
				_set_live_banner(shield_msg)
				_show_toast(shield_msg)
			captured_area.queue_free()
	)

	return obs_area


func _set_live_banner(text: String) -> void:
	last_live_event_text = text
	if _live_event_banner_label != null:
		_live_event_banner_label.text = text


func _show_toast(msg: String) -> void:
	if _toast_label != null:
		_toast_label.text = msg
	_toast_timer = 3.0


func _transition_to_state(new_state: RaceState) -> void:
	current_state = new_state
	if new_state == RaceState.PHOTO_FINISH:
		state_timer = photo_finish_duration
	elif new_state == RaceState.PODIO:
		state_timer = podium_duration
	state_changed.emit(int(new_state))

	if _center_banner_panel == null or _center_banner_title == null or _center_banner_subtitle == null:
		return

	match new_state:
		RaceState.LOBBY_VOTACAO:
			_center_banner_panel.visible = true
			_center_banner_title.text = "🗳️ LOBBY DE VOTAÇÃO"
			_center_banner_subtitle.text = "Comente #1 para Lula ou #2 para Flávio Bolsonaro!"
		RaceState.COUNTDOWN:
			_center_banner_panel.visible = true
			_center_banner_title.text = "⏱️ PREPARAR... LARGADA!"
			_center_banner_subtitle.text = "A corrida vai começar!"
		RaceState.RACING:
			_center_banner_panel.visible = false
		RaceState.PHOTO_FINISH:
			_center_banner_panel.visible = true
			_center_banner_title.text = "🏁 TEMPO ESGOTADO!"
			_center_banner_subtitle.text = "Apurando o vencedor por maior distância..."
		RaceState.PODIO:
			_center_banner_panel.visible = true
			if winner != null:
				_center_banner_title.text = "🏆 VITÓRIA DE %s! 🏆" % winner.candidate_name
				_center_banner_subtitle.text = "Distância final: %.1f metros percorridos!" % winner.progress_m
			else:
				_center_banner_title.text = "🏁 EMPATE NA RODADA!"
				_center_banner_subtitle.text = "Mesma distância percorrida. Nenhuma vitória somada."


func _setup_environment_and_lights() -> void:
	_world_env = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if _world_env == null:
		_world_env = WorldEnvironment.new()
		_world_env.name = "WorldEnvironment"
		add_child(_world_env)

	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0B0E17")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#E2E8F0")
	env.ambient_light_energy = 0.90
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.10
	_world_env.environment = env

	_sun_light = get_node_or_null("SunLight") as DirectionalLight3D
	if _sun_light == null:
		_sun_light = DirectionalLight3D.new()
		_sun_light.name = "SunLight"
		add_child(_sun_light)

	_sun_light.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	_sun_light.light_color = Color("#FFFBEB")
	_sun_light.light_energy = 1.50
	_sun_light.shadow_enabled = true


# Pista infinita modular com 8 chunks reciclados dinamicamente
func _setup_track_geometry() -> void:
	_track_root = get_node_or_null("TrackRoot") as Node3D
	if _track_root == null:
		_track_root = Node3D.new()
		_track_root.name = "TrackRoot"
		add_child(_track_root)

	if _shared_geometries_built:
		return
	_shared_geometries_built = true

	var floor_mat: StandardMaterial3D = StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#111827") # Asfalto escuro
	floor_mat.roughness = 0.75

	var lula_mat: StandardMaterial3D = StandardMaterial3D.new()
	lula_mat.albedo_color = Color("#DC2626") # Faixa vermelha da raia 1

	var bolso_mat: StandardMaterial3D = StandardMaterial3D.new()
	bolso_mat.albedo_color = Color("#0284C7") # Faixa azul da raia 2

	var center_line_mat: StandardMaterial3D = StandardMaterial3D.new()
	center_line_mat.albedo_color = Color("#F8FAFC")
	center_line_mat.emission_enabled = true
	center_line_mat.emission = Color("#F8FAFC")
	center_line_mat.emission_energy_multiplier = 0.4

	_track_chunks.clear()

	for i: int in range(CHUNK_COUNT):
		var chunk: Node3D = Node3D.new()
		chunk.name = "TrackChunk_%d" % i
		# Posiciona chunks sequencialmente ao longo de -Z
		chunk.position = Vector3(0.0, 0.0, -float(i) * CHUNK_LENGTH + 20.0)
		_track_root.add_child(chunk)
		_track_chunks.append(chunk)

		# 1. Asfalto do chunk
		var floor_body: StaticBody3D = StaticBody3D.new()
		floor_body.name = "Floor"
		chunk.add_child(floor_body)

		var floor_col: CollisionShape3D = CollisionShape3D.new()
		var floor_shape: BoxShape3D = BoxShape3D.new()
		floor_shape.size = Vector3(TRACK_WIDTH, 0.5, CHUNK_LENGTH)
		floor_col.shape = floor_shape
		floor_col.position = Vector3(0.0, -0.25, -CHUNK_LENGTH * 0.5)
		floor_body.add_child(floor_col)

		var floor_mesh: MeshInstance3D = MeshInstance3D.new()
		var floor_box: BoxMesh = BoxMesh.new()
		floor_box.size = Vector3(TRACK_WIDTH, 0.5, CHUNK_LENGTH)
		floor_mesh.mesh = floor_box
		floor_mesh.position = Vector3(0.0, -0.25, -CHUNK_LENGTH * 0.5)
		floor_mesh.material_override = floor_mat
		chunk.add_child(floor_mesh)

		# 2. Divisória central tracejada
		var center_line: MeshInstance3D = MeshInstance3D.new()
		var center_box: BoxMesh = BoxMesh.new()
		center_box.size = Vector3(0.08, 0.02, CHUNK_LENGTH)
		center_line.mesh = center_box
		center_line.position = Vector3(0.0, 0.01, -CHUNK_LENGTH * 0.5)
		center_line.material_override = center_line_mat
		chunk.add_child(center_line)

		# 3. Faixas coloridas nas bordas das raias
		var lula_edge: MeshInstance3D = MeshInstance3D.new()
		var edge_box: BoxMesh = BoxMesh.new()
		edge_box.size = Vector3(0.18, 0.02, CHUNK_LENGTH)
		lula_edge.mesh = edge_box
		lula_edge.position = Vector3(-TRACK_WIDTH * 0.5 + 0.1, 0.015, -CHUNK_LENGTH * 0.5)
		lula_edge.material_override = lula_mat
		chunk.add_child(lula_edge)

		var bolso_edge: MeshInstance3D = MeshInstance3D.new()
		bolso_edge.mesh = edge_box
		bolso_edge.position = Vector3(TRACK_WIDTH * 0.5 - 0.1, 0.015, -CHUNK_LENGTH * 0.5)
		bolso_edge.material_override = bolso_mat
		chunk.add_child(bolso_edge)


func _reset_track_chunks() -> void:
	for i: int in range(_track_chunks.size()):
		var chunk: Node3D = _track_chunks[i]
		chunk.position = Vector3(0.0, 0.0, -float(i) * CHUNK_LENGTH + 20.0)


# Reciclagem procedural: move chunks que ficaram para trás para a frente do líder
func _recycle_track_chunks() -> void:
	if _track_chunks.is_empty() or runners.is_empty():
		return

	var leader_z: float = runners[0].global_position.z
	for r: CandidateRunner in runners:
		if r.global_position.z < leader_z:
			leader_z = r.global_position.z

	var total_span: float = float(CHUNK_COUNT) * CHUNK_LENGTH
	for chunk: Node3D in _track_chunks:
		# Se o chunk ficou mais de 50 metros atrás do corredor líder, move para a frente
		if chunk.position.z > leader_z + 50.0:
			chunk.position.z -= total_span


func _setup_obstacles() -> void:
	_obstacles_root = _track_root.get_node_or_null("ObstaclesRoot") as Node3D
	if _obstacles_root == null:
		_obstacles_root = Node3D.new()
		_obstacles_root.name = "ObstaclesRoot"
		_track_root.add_child(_obstacles_root)


func _setup_runners() -> void:
	_runners_root = get_node_or_null("RunnersRoot") as Node3D
	if _runners_root == null:
		_runners_root = Node3D.new()
		_runners_root.name = "RunnersRoot"
		add_child(_runners_root)

	if not runners.is_empty():
		return

	for i: int in range(CANDIDATE_DEFS.size()):
		var def_dict: Dictionary = CANDIDATE_DEFS[i]
		var cid: int = int(def_dict["id"])
		var cname: String = String(def_dict["name"])
		var ccolor: Color = Color(String(def_dict["color"]))
		var ctext: Color = Color(String(def_dict["text"]))
		var cspeed: float = float(def_dict["speed"])

		var runner_name: String = "CandidateRunner_%d" % cid
		var runner: CandidateRunner = _runners_root.get_node_or_null(runner_name) as CandidateRunner
		if runner == null:
			runner = CandidateRunner.new()
			runner.name = runner_name
			_runners_root.add_child(runner)

		runner.base_speed = cspeed
		var lx: float = _get_lane_x(i, 2)
		runner.configure(cid, cname, ccolor, ctext, Vector3(lx, 0.0, 0.0), track_length)
		runners.append(runner)


func _setup_camera() -> void:
	race_camera = get_node_or_null("RaceCamera") as RaceCamera
	if race_camera == null:
		race_camera = RaceCamera.new()
		race_camera.name = "RaceCamera"
		add_child(race_camera)
	race_camera.set_runners(runners)


func _setup_hud() -> void:
	_hud_layer = get_node_or_null("BroadcastHUD") as CanvasLayer
	if _hud_layer == null:
		_hud_layer = CanvasLayer.new()
		_hud_layer.name = "BroadcastHUD"
		add_child(_hud_layer)

	if _hud_layer.get_node_or_null("SafeRoot") != null:
		return

	var safe_root: Control = Control.new()
	safe_root.name = "SafeRoot"
	safe_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	safe_root.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud_layer.add_child(safe_root)

	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.07, 0.12, 0.92)
	panel_style.border_color = Color("#1E293B")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(16)
	panel_style.content_margin_left = 20.0
	panel_style.content_margin_right = 20.0
	panel_style.content_margin_top = 14.0
	panel_style.content_margin_bottom = 14.0

	# 1. Painel Superior: Título, Cronômetro e Barra de Vantagem Relativa (Tug-of-War)
	var top_panel: PanelContainer = PanelContainer.new()
	top_panel.name = "TopHeaderPanel"
	top_panel.position = Vector2(30.0, 60.0)
	top_panel.size = Vector2(1020.0, 180.0)
	top_panel.add_theme_stylebox_override("panel", panel_style)
	safe_root.add_child(top_panel)

	var top_vbox: VBoxContainer = VBoxContainer.new()
	top_vbox.add_theme_constant_override("separation", 8)
	top_panel.add_child(top_vbox)

	var title_hbox: HBoxContainer = HBoxContainer.new()
	top_vbox.add_child(title_hbox)

	var title_lbl: Label = Label.new()
	title_lbl.text = "⚔️ LULA vs. BOLSONARO"
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.modulate = Color("#F8FAFC")
	title_hbox.add_child(title_lbl)

	_ws_status_label = Label.new()
	_ws_status_label.text = "WS: LOCAL"
	_ws_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ws_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ws_status_label.add_theme_font_size_override("font_size", 20)
	_ws_status_label.modulate = Color("#64748B")
	title_hbox.add_child(_ws_status_label)

	_match_timer_label = Label.new()
	_match_timer_label.text = "⏱ 10:00"
	_match_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_match_timer_label.add_theme_font_size_override("font_size", 34)
	_match_timer_label.modulate = Color("#38BDF8")
	title_hbox.add_child(_match_timer_label)

	# Barra de Vantagem Relativa (Tug-of-War)
	_advantage_label = Label.new()
	_advantage_label.name = "AdvantageLabel"
	_advantage_label.text = "⚔️ EMPATADOS NA LARGADA"
	_advantage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_advantage_label.add_theme_font_size_override("font_size", 26)
	_advantage_label.modulate = Color("#FBBF24")
	top_vbox.add_child(_advantage_label)

	_tug_of_war_bar = ProgressBar.new()
	_tug_of_war_bar.name = "TugOfWarBar"
	_tug_of_war_bar.min_value = 0.0
	_tug_of_war_bar.max_value = 100.0
	_tug_of_war_bar.value = 50.0 # 50% = equilibrado no centro
	_tug_of_war_bar.show_percentage = false
	_tug_of_war_bar.custom_minimum_size = Vector2(0.0, 18.0)
	top_vbox.add_child(_tug_of_war_bar)

	# 2. Banner de Notificações de Eventos ao Vivo
	var banner_panel: PanelContainer = PanelContainer.new()
	banner_panel.name = "LiveBannerPanel"
	banner_panel.position = Vector2(40.0, 255.0)
	banner_panel.size = Vector2(1000.0, 52.0)
	banner_panel.add_theme_stylebox_override("panel", panel_style)
	safe_root.add_child(banner_panel)

	_live_event_banner_label = Label.new()
	_live_event_banner_label.text = last_live_event_text
	_live_event_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_live_event_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_live_event_banner_label.add_theme_font_size_override("font_size", 22)
	_live_event_banner_label.modulate = Color("#FDE047")
	banner_panel.add_child(_live_event_banner_label)

	# 3. Banner Central para Contagem e Pódio
	_center_banner_panel = PanelContainer.new()
	_center_banner_panel.name = "CenterBannerPanel"
	_center_banner_panel.position = Vector2(90.0, 520.0)
	_center_banner_panel.size = Vector2(900.0, 160.0)
	var center_style: StyleBoxFlat = StyleBoxFlat.new()
	center_style.bg_color = Color(0.03, 0.04, 0.08, 0.95)
	center_style.border_color = Color("#38BDF8")
	center_style.set_border_width_all(3)
	center_style.set_corner_radius_all(20)
	center_style.content_margin_left = 24.0
	center_style.content_margin_right = 24.0
	center_style.content_margin_top = 20.0
	center_style.content_margin_bottom = 20.0
	_center_banner_panel.add_theme_stylebox_override("panel", center_style)
	safe_root.add_child(_center_banner_panel)

	var center_vbox: VBoxContainer = VBoxContainer.new()
	center_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_center_banner_panel.add_child(center_vbox)

	_center_banner_title = Label.new()
	_center_banner_title.text = "🗳️ LOBBY DE VOTAÇÃO"
	_center_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_banner_title.add_theme_font_size_override("font_size", 42)
	_center_banner_title.modulate = Color("#38BDF8")
	center_vbox.add_child(_center_banner_title)

	_center_banner_subtitle = Label.new()
	_center_banner_subtitle.text = "Comente #1 para Lula ou #2 para Flávio Bolsonaro!"
	_center_banner_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_banner_subtitle.add_theme_font_size_override("font_size", 26)
	_center_banner_subtitle.modulate = Color("#E2E8F0")
	center_vbox.add_child(_center_banner_subtitle)

	# 4. Painel Inferior (Safe Zone y = 1420px a 1880px): Cards dos Candidatos e Controles
	var bottom_panel: PanelContainer = PanelContainer.new()
	bottom_panel.name = "BottomControlPanel"
	bottom_panel.position = Vector2(30.0, 1420.0)
	bottom_panel.size = Vector2(1020.0, 460.0)
	bottom_panel.add_theme_stylebox_override("panel", panel_style)
	safe_root.add_child(bottom_panel)

	var bottom_vbox: VBoxContainer = VBoxContainer.new()
	bottom_vbox.add_theme_constant_override("separation", 14)
	bottom_panel.add_child(bottom_vbox)

	# Grade com os Cards Comparativos dos 2 Competidores
	var cards_hbox: HBoxContainer = HBoxContainer.new()
	cards_hbox.add_theme_constant_override("separation", 20)
	bottom_vbox.add_child(cards_hbox)

	# Card Lula
	var card_lula: PanelContainer = PanelContainer.new()
	card_lula.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lula_style: StyleBoxFlat = StyleBoxFlat.new()
	lula_style.bg_color = Color(0.18, 0.04, 0.06, 0.88)
	lula_style.border_color = Color("#FF3B5C")
	lula_style.set_border_width_all(2)
	lula_style.set_corner_radius_all(12)
	lula_style.content_margin_left = 16.0
	lula_style.content_margin_right = 16.0
	lula_style.content_margin_top = 10.0
	lula_style.content_margin_bottom = 10.0
	card_lula.add_theme_stylebox_override("panel", lula_style)
	cards_hbox.add_child(card_lula)

	var lula_vbox: VBoxContainer = VBoxContainer.new()
	card_lula.add_child(lula_vbox)

	var lula_title: Label = Label.new()
	lula_title.text = "🔴 #1 LULA"
	lula_title.add_theme_font_size_override("font_size", 28)
	lula_title.modulate = Color("#FF3B5C")
	lula_vbox.add_child(lula_title)

	_card_lula_dist = Label.new()
	_card_lula_dist.text = "Distância: 0.0 m"
	_card_lula_dist.add_theme_font_size_override("font_size", 24)
	lula_vbox.add_child(_card_lula_dist)

	_card_lula_speed = Label.new()
	_card_lula_speed.text = "Velocidade: 12.0 m/s"
	_card_lula_speed.add_theme_font_size_override("font_size", 22)
	_card_lula_speed.modulate = Color("#94A3B8")
	lula_vbox.add_child(_card_lula_speed)

	_card_lula_badges = Label.new()
	_card_lula_badges.text = "Status: Normal"
	_card_lula_badges.add_theme_font_size_override("font_size", 22)
	_card_lula_badges.modulate = Color("#10B981")
	lula_vbox.add_child(_card_lula_badges)

	# Card Bolsonaro
	var card_bolso: PanelContainer = PanelContainer.new()
	card_bolso.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bolso_style: StyleBoxFlat = StyleBoxFlat.new()
	bolso_style.bg_color = Color(0.02, 0.14, 0.07, 0.88)
	bolso_style.border_color = Color("#FACC15")
	bolso_style.set_border_width_all(2)
	bolso_style.set_corner_radius_all(12)
	bolso_style.content_margin_left = 16.0
	bolso_style.content_margin_right = 16.0
	bolso_style.content_margin_top = 10.0
	bolso_style.content_margin_bottom = 10.0
	card_bolso.add_theme_stylebox_override("panel", bolso_style)
	cards_hbox.add_child(card_bolso)

	var bolso_vbox: VBoxContainer = VBoxContainer.new()
	card_bolso.add_child(bolso_vbox)

	var bolso_title: Label = Label.new()
	bolso_title.text = "🟡 #2 FLÁVIO BOLSONARO"
	bolso_title.add_theme_font_size_override("font_size", 28)
	bolso_title.modulate = Color("#FACC15")
	bolso_vbox.add_child(bolso_title)

	_card_bolso_dist = Label.new()
	_card_bolso_dist.text = "Distância: 0.0 m"
	_card_bolso_dist.add_theme_font_size_override("font_size", 24)
	bolso_vbox.add_child(_card_bolso_dist)

	_card_bolso_speed = Label.new()
	_card_bolso_speed.text = "Velocidade: 12.0 m/s"
	_card_bolso_speed.add_theme_font_size_override("font_size", 22)
	_card_bolso_speed.modulate = Color("#94A3B8")
	bolso_vbox.add_child(_card_bolso_speed)

	_card_bolso_badges = Label.new()
	_card_bolso_badges.text = "Status: Normal"
	_card_bolso_badges.add_theme_font_size_override("font_size", 22)
	_card_bolso_badges.modulate = Color("#10B981")
	bolso_vbox.add_child(_card_bolso_badges)

	# Linha de Ações Rápidas: Turbo, Escudo e Ataque Político (Pilha de Processos)
	var actions_lula_hbox: HBoxContainer = HBoxContainer.new()
	actions_lula_hbox.add_theme_constant_override("separation", 10)
	bottom_vbox.add_child(actions_lula_hbox)

	var btn_turbo_lula: Button = Button.new()
	btn_turbo_lula.text = "⚡ Turbo Lula [1]"
	btn_turbo_lula.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_turbo_lula.custom_minimum_size = Vector2(0.0, 52.0)
	btn_turbo_lula.add_theme_font_size_override("font_size", 22)
	btn_turbo_lula.modulate = Color("#FF3B5C")
	btn_turbo_lula.pressed.connect(func() -> void: trigger_candidate_boost(1))
	actions_lula_hbox.add_child(btn_turbo_lula)

	var btn_shield_lula: Button = Button.new()
	btn_shield_lula.text = "🛡️ Escudo Lula"
	btn_shield_lula.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_shield_lula.custom_minimum_size = Vector2(0.0, 52.0)
	btn_shield_lula.add_theme_font_size_override("font_size", 22)
	btn_shield_lula.pressed.connect(func() -> void: trigger_candidate_shield(1))
	actions_lula_hbox.add_child(btn_shield_lula)

	var btn_attack_bolso: Button = Button.new()
	btn_attack_bolso.text = "📁 Documentos no Flávio [3]"
	btn_attack_bolso.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_attack_bolso.custom_minimum_size = Vector2(0.0, 52.0)
	btn_attack_bolso.add_theme_font_size_override("font_size", 22)
	btn_attack_bolso.modulate = Color("#F59E0B")
	btn_attack_bolso.pressed.connect(func() -> void: spawn_political_obstacle(2, "pilha_documentos", "Torcida_Lula"))
	actions_lula_hbox.add_child(btn_attack_bolso)

	var actions_bolso_hbox: HBoxContainer = HBoxContainer.new()
	actions_bolso_hbox.add_theme_constant_override("separation", 10)
	bottom_vbox.add_child(actions_bolso_hbox)

	var btn_turbo_bolso: Button = Button.new()
	btn_turbo_bolso.text = "⚡ Turbo Flávio [2]"
	btn_turbo_bolso.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_turbo_bolso.custom_minimum_size = Vector2(0.0, 52.0)
	btn_turbo_bolso.add_theme_font_size_override("font_size", 22)
	btn_turbo_bolso.modulate = Color("#FACC15")
	btn_turbo_bolso.pressed.connect(func() -> void: trigger_candidate_boost(2))
	actions_bolso_hbox.add_child(btn_turbo_bolso)

	var btn_shield_bolso: Button = Button.new()
	btn_shield_bolso.text = "🛡️ Escudo Flávio"
	btn_shield_bolso.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_shield_bolso.custom_minimum_size = Vector2(0.0, 52.0)
	btn_shield_bolso.add_theme_font_size_override("font_size", 22)
	btn_shield_bolso.pressed.connect(func() -> void: trigger_candidate_shield(2))
	actions_bolso_hbox.add_child(btn_shield_bolso)

	var btn_attack_lula: Button = Button.new()
	btn_attack_lula.text = "📁 Documentos no Lula [4]"
	btn_attack_lula.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_attack_lula.custom_minimum_size = Vector2(0.0, 52.0)
	btn_attack_lula.add_theme_font_size_override("font_size", 22)
	btn_attack_lula.modulate = Color("#F59E0B")
	btn_attack_lula.pressed.connect(func() -> void: spawn_political_obstacle(1, "pilha_documentos", "Torcida_Bolsonaro"))
	actions_bolso_hbox.add_child(btn_attack_lula)

	# Linha de Controle Geral
	var restart_btn: Button = Button.new()
	restart_btn.name = "RestartRaceButton"
	restart_btn.text = "🔄 Iniciar / Reiniciar Partida [R / Espaço]"
	restart_btn.custom_minimum_size = Vector2(0.0, 54.0)
	restart_btn.add_theme_font_size_override("font_size", 24)
	restart_btn.pressed.connect(func() -> void: restart_race(false))
	bottom_vbox.add_child(restart_btn)


func _update_hud() -> void:
	# 1. Cronômetro da partida
	if _match_timer_label != null:
		var mins: int = int(match_time_remaining) / 60
		var secs: int = int(match_time_remaining) % 60
		_match_timer_label.text = "⏱ %02d:%02d" % [mins, secs]
		if match_time_remaining < 30.0:
			_match_timer_label.modulate = Color("#EF4444")
		else:
			_match_timer_label.modulate = Color("#38BDF8")

	# 2. Vantagem Relativa (Tug-of-War)
	if runners.size() >= 2:
		var r_lula: CandidateRunner = runners[0]
		var r_bolso: CandidateRunner = runners[1]
		var diff: float = r_lula.progress_m - r_bolso.progress_m

		if _advantage_label != null:
			if absf(diff) < 1.0:
				_advantage_label.text = "⚔️ EMPATADOS NA DISPUTA!"
				_advantage_label.modulate = Color("#FBBF24")
			elif diff > 0.0:
				_advantage_label.text = "🔥 +%.1fm LULA NA FRENTE!" % diff
				_advantage_label.modulate = Color("#FF3B5C")
			else:
				_advantage_label.text = "🔥 +%.1fm FLÁVIO BOLSONARO NA FRENTE!" % (-diff)
				_advantage_label.modulate = Color("#FACC15")

		if _tug_of_war_bar != null:
			# Escala de ±50m de diferença mapeada em 0..100% (50% = empate)
			var bar_pct: float = clampf(50.0 + (diff / 50.0) * 50.0, 5.0, 95.0)
			_tug_of_war_bar.value = bar_pct

		# Atualiza Cards individuais
		if _card_lula_dist != null:
			_card_lula_dist.text = "Distância: %.1f m" % r_lula.progress_m
		if _card_lula_speed != null:
			_card_lula_speed.text = "Velocidade: %.1f m/s" % r_lula.current_speed
		if _card_lula_badges != null:
			_card_lula_badges.text = _get_runner_badge_text(r_lula)

		if _card_bolso_dist != null:
			_card_bolso_dist.text = "Distância: %.1f m" % r_bolso.progress_m
		if _card_bolso_speed != null:
			_card_bolso_speed.text = "Velocidade: %.1f m/s" % r_bolso.current_speed
		if _card_bolso_badges != null:
			_card_bolso_badges.text = _get_runner_badge_text(r_bolso)


func _get_runner_badge_text(runner: CandidateRunner) -> String:
	if runner.stumble_timer > 0.0:
		return "💥 TROPEÇO (-62%)"
	elif runner.shield_timer > 0.0 and runner.boost_timer > 0.0:
		return "⚡ TURBO + 🛡️ ESCUDO"
	elif runner.boost_timer > 0.0:
		return "⚡ TURBO (+%.1fm/s)" % runner.boost_amount
	elif runner.shield_timer > 0.0:
		return "🛡️ ESCUDO ATIVO"
	return "Normal (%.1f m/s)" % runner.base_speed


func _connect_live_event_bus() -> void:
	event_bus = get_node_or_null("/root/LiveEventBus") as LiveEventBusInstance
	if event_bus == null:
		return
	bind_event_bus(event_bus)


func bind_event_bus(p_bus: LiveEventBusInstance) -> void:
	event_bus = p_bus
	if event_bus == null:
		return

	if not event_bus.candidate_vote_registered.is_connected(_on_bus_vote_registered):
		event_bus.candidate_vote_registered.connect(_on_bus_vote_registered)
	if not event_bus.candidate_boost_requested.is_connected(_on_bus_boost_requested):
		event_bus.candidate_boost_requested.connect(_on_bus_boost_requested)
	if not event_bus.candidate_shield_requested.is_connected(_on_bus_shield_requested):
		event_bus.candidate_shield_requested.connect(_on_bus_shield_requested)
	if not event_bus.candidate_attack_requested.is_connected(_on_bus_attack_requested):
		event_bus.candidate_attack_requested.connect(_on_bus_attack_requested)
	if not event_bus.admin_command_requested.is_connected(_on_bus_admin_command):
		event_bus.admin_command_requested.connect(_on_bus_admin_command)
	if not event_bus.connection_state_changed.is_connected(_on_bus_connection_changed):
		event_bus.connection_state_changed.connect(_on_bus_connection_changed)


func _on_bus_vote_registered(candidate_slot: int, vote_weight: int, voter_name: String) -> void:
	match_events_count += 1
	var runner: CandidateRunner = get_runner_by_id(candidate_slot)
	if runner != null:
		runner.register_lobby_vote(vote_weight)
		_set_live_banner("🗳️ @%s votou #%d %s (+%d)!" % [voter_name, runner.candidate_id, runner.candidate_name, vote_weight])
		_update_hud()


func _on_bus_boost_requested(
	candidate_slot: int,
	boost_amount: float,
	duration: float,
	voter_name: String,
	label: String
) -> void:
	if should_reserve_paid_effect():
		_reserve_round_effect(candidate_slot, "boost", boost_amount, duration)
		return
	match_events_count += 1
	var runner: CandidateRunner = get_runner_by_id(candidate_slot)
	if runner != null:
		runner.apply_boost(boost_amount, duration)
		_set_live_banner("⚡ @%s: %s -> #%d %s!" % [voter_name, label, runner.candidate_id, runner.candidate_name])
		_show_toast("⚡ TURBO em %s!" % runner.candidate_name)
		_update_hud()


func _on_bus_shield_requested(candidate_slot: int, duration: float, voter_name: String) -> void:
	trigger_candidate_shield(candidate_slot, duration, voter_name)


func _on_bus_attack_requested(target_slot: int, obstacle_type: String, voter_name: String) -> void:
	spawn_political_obstacle(target_slot, obstacle_type, voter_name)


func _on_bus_admin_command(command: String, payload: Dictionary = {}) -> void:
	match_events_count += 1
	var clean_cmd: String = command.strip_edges().to_lower()

	match clean_cmd:
		"start_race":
			start_race_immediately()
			return
		"restart_race", "restart", "reset", "admin_restart":
			restart_race(false)
			return
		"skip_lobby":
			start_countdown()
			return
		"reset_dedup":
			if event_bus != null:
				event_bus.reset_deduplication()
			return
		"pause", "pause_race":
			set_race_paused(true)
			return
		"resume", "resume_race":
			set_race_paused(false)
			return

	var candidate_slot: int = int(payload.get("candidate_slot", payload.get("slot", payload.get("candidate_id", 0))))
	if candidate_slot == 0:
		for i: int in [1, 2]:
			if clean_cmd.contains(str(i)):
				candidate_slot = i
				break

	if candidate_slot in [1, 2]:
		if clean_cmd in ["boost", "turbo", "admin_boost", "candidate_boost"] or clean_cmd.begins_with("boost") or clean_cmd.begins_with("turbo"):
			var boost_amount: float = clampf(float(payload.get("boost_amount", payload.get("amount", 5.0))), 1.0, 20.0)
			var boost_duration: float = clampf(float(payload.get("boost_duration", payload.get("duration", 3.5))), 0.5, 10.0)
			trigger_candidate_boost(candidate_slot, boost_amount, boost_duration, "Admin", "ADMIN TURBO")
			return
		elif clean_cmd in ["shield", "admin_shield", "candidate_shield"] or clean_cmd.begins_with("shield"):
			var shield_dur: float = clampf(float(payload.get("shield_duration", payload.get("duration", 5.0))), 1.0, 15.0)
			trigger_candidate_shield(candidate_slot, shield_dur, "Admin")
			return
		elif clean_cmd in ["attack", "spawn_obstacle", "candidate_attack"] or clean_cmd.begins_with("attack"):
			var target_slot: int = clampi(int(payload.get("target_slot", 2 if candidate_slot == 1 else 1)), 1, 2)
			spawn_political_obstacle(target_slot, "pilha_documentos", "Admin")
			return


func _on_bus_connection_changed(is_connected: bool, status_text: String) -> void:
	if _ws_status_label != null:
		_ws_status_label.text = "WS: %s" % ("ONLINE" if is_connected else "OFFLINE")
		_ws_status_label.modulate = Color("#22C55E") if is_connected else Color("#EF4444")
	_set_live_banner("Ponte Live: %s" % status_text)


# Snapshot completo da corrida para o servidor Python e Painel Web
func get_telemetry_snapshot() -> Dictionary:
	var runners_data: Array = []
	for r: CandidateRunner in runners:
		runners_data.append({
			"candidate_id": r.candidate_id,
			"name": r.candidate_name,
			"rank": (rankings.find(r) + 1) if not rankings.is_empty() else r.candidate_id,
			"progress_m": r.progress_m,
			"progress_ratio": r.progress_ratio,
			"current_speed": r.current_speed,
			"base_speed": r.base_speed,
			"lobby_votes": r.lobby_votes,
			"is_finished": r.is_finished,
			"boost_timer": r.boost_timer,
			"shield_timer": r.shield_timer,
			"stumble_timer": r.stumble_timer,
			"has_shield": r.shield_timer > 0.0,
			"is_boosted": r.boost_timer > 0.0,
			"is_stumbled": r.stumble_timer > 0.0
		})

	var advantage_leader: String = "EMPATADOS"
	var advantage_meters: float = 0.0
	if runners.size() >= 2:
		var diff: float = runners[0].progress_m - runners[1].progress_m
		advantage_meters = absf(diff)
		if diff > 0.5:
			advantage_leader = "lula"
		elif diff < -0.5:
			advantage_leader = "bolsonaro"

	return {
		"type": "telemetry",
		"current_state": int(current_state),
		"state_name": _get_state_name(current_state),
		"race_elapsed_time": race_elapsed_time,
		"match_time_remaining": match_time_remaining,
		"match_duration": match_duration,
		"round_id": current_round,
		"current_round": current_round,
		"rounds_per_cycle": ROUNDS_PER_CYCLE,
		"cycle_number": cycle_number,
		"round_name": String(round_metadata.get("name", "")),
		"round_metadata": round_metadata.duplicate(true),
		"cycle_wins": cycle_wins.duplicate(),
		"race_paused": race_paused,
		"winner_id": winner.candidate_id if winner != null else 0,
		"advantage_leader": advantage_leader,
		"advantage_meters": advantage_meters,
		"match_events_count": match_events_count,
		"runners": runners_data
	}


func send_telemetry_now() -> bool:
	if event_bus == null:
		return false
	return event_bus.send_telemetry(get_telemetry_snapshot())


func _get_state_name(state: RaceState) -> String:
	match state:
		RaceState.LOBBY_VOTACAO: return "LOBBY_VOTACAO"
		RaceState.COUNTDOWN: return "COUNTDOWN"
		RaceState.RACING: return "RACING"
		RaceState.PHOTO_FINISH: return "PHOTO_FINISH"
		RaceState.PODIO: return "PODIO"
		_: return "UNKNOWN"



func should_reserve_paid_effect() -> bool:
	return event_bus != null and event_bus.current_event_type == "gift" and (current_state in [RaceState.PHOTO_FINISH, RaceState.PODIO] or bool(get_meta("replay_reserved_gift", false)))


func _reserve_round_effect(team: int, kind: String, amount: float, duration: float = 0.0) -> void:
	if team not in [1, 2]:
		return
	var key: String = str(team)
	var pending: Dictionary = pending_round_effects.get(key, {"boost_amount": 0.0, "boost_duration": 0.0, "shield_duration": 0.0, "attacks": 0, "super_turbo": false}) as Dictionary
	match kind:
		"boost":
			pending["boost_amount"] = minf(25.0, maxf(float(pending["boost_amount"]), amount))
			pending["boost_duration"] = minf(10.0, float(pending["boost_duration"]) + duration)
			var payload: Dictionary = event_bus.current_event_payload
			if String(payload.get("gift_tier", "")).to_upper() == "T4" or int(payload.get("tier", 1)) == 4 or payload.get("action_id") == "gift_t4_super_rally":
				pending["super_turbo"] = true
		"shield":
			pending["shield_duration"] = minf(15.0, maxf(float(pending["shield_duration"]), amount))
		"attack":
			pending["attacks"] = mini(4, int(pending["attacks"]) + 1)
	pending_round_effects[key] = pending


func _apply_reserved_round_effects() -> void:
	if pending_round_effects.is_empty():
		return
	var reserved: Dictionary = pending_round_effects.duplicate(true)
	pending_round_effects.clear()
	for team_key: String in reserved:
		var team: int = int(team_key)
		var pending: Dictionary = reserved[team_key] as Dictionary
		var runner: CandidateRunner = get_runner_by_id(team)
		if runner == null:
			continue
		if float(pending["boost_duration"]) > 0.0:
			runner.apply_boost(float(pending["boost_amount"]), float(pending["boost_duration"]))
		if float(pending["shield_duration"]) > 0.0:
			runner.apply_shield(float(pending["shield_duration"]))
		for attack: int in range(int(pending["attacks"])):
			var area: Area3D = spawn_political_obstacle(team, "pilha_documentos", "Reserva da rodada")
			if area != null:
				area.position.z -= float(attack) * 5.0
		if bool(pending["super_turbo"]):
			_on_reserved_super_turbo(team)


func _on_reserved_super_turbo(_team: int) -> void:
	pass
