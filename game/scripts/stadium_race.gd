class_name StadiumRace
extends RaceMain
## Transmissão em profundidade: dois personagens correm +X em raias distintas.

const HEROES: Array[PackedScene] = [
	preload("res://assets/characters/api-cape-v13/lula_run.glb"),
	preload("res://assets/characters/api-cape-v13/flavio_run.glb")
]
const IDLES: Array[PackedScene] = [
	preload("res://assets/characters/idle-clips/lula_idle.glb"),
	preload("res://assets/characters/idle-clips/flavio_idle.glb")
]
const HURTS: Array[PackedScene] = [preload("res://assets/characters/hurt-clips/lula_hurt.glb"), preload("res://assets/characters/hurt-clips/flavio_hurt.glb")]
const VISUAL_METERS: float = .18
var world_visual: StadiumWorld = null
var stadium_hud: StadiumHUD = null
var audience: AudienceDirector = null
var audio: RaceAudio = null
var effects: StadiumEffects = null
var persistence: RacePersistence = null
var sound_effects: RaceSoundEffects = null
var ambience: RaceAmbience = null
var memes: RaceMemeBoard = null
var gift_visuals: GiftVisualCache = null
var avatar_visuals: AvatarVisualCache = null
var _observed_gift_actions: Dictionary = {}
var _stage_shadows: Array[MeshInstance3D] = []
var _attack_visuals: Array[Area3D] = []
var _attack_slots: Array[int] = []
var _capture_path: String = ""
var _test_elapsed: float = 0.0
var _test_duration: float = 0.0
var _frame_times_ms: Array[float] = []
var _capture_started: bool = false
var _cinematic_team: int = 0
var _cinematic_time: float = 0.0
var _cinematic_cooldown: float = 0.0
var _finish_elapsed: float = -1.0
var _finish_positions: Array[Vector3] = []
var _finish_line: MeshInstance3D = null
var _last_leader_slot: int = 0
var _leader_candidate: int = 0
var _leader_confirm_seconds: float = 0.0
var _overtake_cooldown: float = 0.0
var _final_stretch_announced: bool = false


func _ready() -> void:
	Engine.max_fps = 60
	var window_platform: String = OS.get_environment("LIVE_PLATFORM").to_lower()
	DisplayServer.window_set_title("Corrida Presidencial - " + (window_platform.capitalize() if window_platform in ["tiktok", "kwai"] else "Previa local"))
	super._ready()
	audience = AudienceDirector.new()
	add_child(audience)
	audience.setup(event_bus)
	audience.participation_received.connect(stadium_hud.show_participation)
	audience.leaderboard_changed.connect(stadium_hud.update_leaderboard)
	audience.moment_requested.connect(_on_audience_moment)
	audio = RaceAudio.new()
	add_child(audio)
	effects = StadiumEffects.new()
	add_child(effects)
	sound_effects = RaceSoundEffects.new()
	add_child(sound_effects)
	ambience = RaceAmbience.new()
	add_child(ambience)
	memes = RaceMemeBoard.new()
	add_child(memes)
	gift_visuals = GiftVisualCache.new()
	gift_visuals.name = "CacheDeIconesPresentes"
	add_child(gift_visuals)
	gift_visuals.icon_ready.connect(_on_gift_icon_ready)
	avatar_visuals = AvatarVisualCache.new()
	avatar_visuals.name = "CacheDeAvataresDaLive"
	add_child(avatar_visuals)
	avatar_visuals.avatar_ready.connect(_on_avatar_icon_ready)
	if stadium_hud != null:
		stadium_hud.set_gift_cache(gift_visuals)
		stadium_hud.set_avatar_cache(avatar_visuals)
	_setup_finish_line()
	for runner: CandidateRunner in runners:
		runner.runner_stumbled.connect(_on_runner_stumbled)
		runner.shield_absorbed_hit.connect(_on_shield_absorbed)
	if event_bus != null:
		event_bus.live_event_accepted.connect(_on_show_event)
	state_changed.connect(_on_audio_state_changed)
	race_finished.connect(_on_audio_race_finished)
	world_visual.set_round_metadata(round_metadata)
	round_changed.connect(_on_visual_round_changed)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			_capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--measure-seconds="):
			_test_duration = clampf(argument.trim_prefix("--measure-seconds=").to_float(), 3.0, 660.0)
		elif argument.begins_with("--preview-round=") and "--asset-preview" in OS.get_cmdline_user_args():
			current_round = clampi(argument.trim_prefix("--preview-round=").to_int(), 1, 50)
			_select_round_metadata()
			world_visual.set_round_metadata(round_metadata)
	if not _capture_path.is_empty() and not _safe_capture(_capture_path):
		push_error("Captura exige PNG novo em docs/evidencias/estadio")
		get_tree().quit(1)
		return
	if "--idle-preview" in OS.get_cmdline_user_args():
		state_timer = 300.0
	elif "--asset-preview" in OS.get_cmdline_user_args():
		start_race_immediately()
	if not _capture_path.is_empty() and _test_duration <= 0.0:
		_test_duration = 5.0
	if "--asset-preview" in OS.get_cmdline_user_args() and "--showcase-events" in OS.get_cmdline_user_args():
		get_tree().create_timer(.8).timeout.connect(_run_interaction_showcase)
	_update_stage(0.0, true)
	if not "--asset-preview" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		var channel: String = OS.get_environment("LIVE_PLATFORM").strip_edges().to_lower()
		if not channel in ["tiktok", "kwai"]:
			channel = "local"
		persistence = RacePersistence.new()
		add_child(persistence)
		if not persistence.setup(self, audience, event_bus, channel):
			stadium_hud.show_event("RECUPERAÇÃO LOCAL PRECISA DE ATENÇÃO", 0)
		else:
			stadium_hud.update_leaderboard(audience.get_top_supporters())
			_update_stage(0.0, true)


func _run_interaction_showcase() -> void:
	# Somente bancada explícita: nunca simular público em uma transmissão.
	if not "--asset-preview" in OS.get_cmdline_user_args():
		return
	var names: Array[String] = ["Ana · teste", "Bia · teste", "Caio · teste", "Davi · teste"]
	for index: int in range(4):
		var user_data: Dictionary = {"user_id": "demo_user_%d" % index, "display_name": names[index]}
		event_bus.ingest_envelope({"schema_version": "1.0", "source": "simulator", "event_id": "demo-vote-%d" % index, "event_type": "vote", "user": user_data, "payload": {"candidate_slot": index % 2 + 1}})
		event_bus.ingest_envelope({"schema_version": "1.0", "source": "simulator", "event_id": "demo-gift-%d" % index, "event_type": "gift", "user": user_data, "payload": {"candidate_slot": index % 2 + 1, "coin_value": (4 - index) * 20, "repeat_count": 1, "gift_tier": "T2", "gift_name": "Teste de escudo"}})
	get_tree().create_timer(4.5).timeout.connect(_showcase_turbo)


func _showcase_turbo() -> void:
	trigger_candidate_boost(1, 9.0, 8.0, "Ana · teste")
	trigger_candidate_boost(2, 9.0, 8.0, "Bia · teste")
	if "--showcase-cutscene" in OS.get_cmdline_user_args():
		_begin_super_turbo(2)
	if "--showcase-finish" in OS.get_cmdline_user_args():
		runners[0].progress_m += 1.0
		match_time_remaining = 0.0
		_finish_match_by_timer()
	if "--showcase-impact" in OS.get_cmdline_user_args():
		for runner: CandidateRunner in runners:
			runner.shield_timer = 0.0
			runner.apply_stumble(1.2)


func _setup_finish_line() -> void:
	_finish_line = MeshInstance3D.new()
	_finish_line.name = "FaixaDaChegadaDaRodada"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(.65, 9.1)
	_finish_line.mesh = plane
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded;
void fragment() {
    float checker = mod(floor(UV.x * 2.0) + floor(UV.y * 24.0), 2.0);
    ALBEDO = mix(vec3(.018, .025, .05), vec3(.99), checker);
}
"""
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	_finish_line.material_override = material
	_finish_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_finish_line.visible = false
	add_child(_finish_line)


func _on_runner_stumbled(runner: CandidateRunner, _duration: float) -> void:
	if stadium_hud != null:
		stadium_hud.show_event("%s TROPEÇOU!" % ("13 · LULA" if runner.candidate_id == 1 else "22 · FLÁVIO"), runner.candidate_id, "attack")
	if sound_effects != null:
		sound_effects.play_event("impact", runner.candidate_id)
	if effects != null:
		effects.trigger_moment("impact", runner.candidate_id)
	if memes != null:
		memes.play_event("impact", runner.candidate_id)


func _on_shield_absorbed(runner: CandidateRunner) -> void:
	if stadium_hud != null:
		stadium_hud.show_event("ESCUDO BLOQUEOU O ATAQUE", runner.candidate_id, "shield")
	if sound_effects != null:
		sound_effects.play_event("shield", runner.candidate_id)
	if memes != null:
		memes.play_event("shield", runner.candidate_id)


func _setup_environment_and_lights() -> void:
	world_visual = StadiumWorld.new()
	world_visual.grandstand_scene = preload("res://assets/environments/stadium/grandstand_100k_v2.glb")
	world_visual.crowd_count = 768
	add_child(world_visual)


func _setup_track_geometry() -> void:
	super._setup_track_geometry()
	for chunk: Node3D in _track_chunks:
		chunk.visible = false


func _setup_runners() -> void:
	_runners_root = Node3D.new()
	_runners_root.name = "SimulacaoDosCorredores"
	add_child(_runners_root)
	for index: int in range(CANDIDATE_DEFS.size()):
		var definition: Dictionary = CANDIDATE_DEFS[index]
		var runner: StadiumRunner = StadiumRunner.new()
		runner.name = "CandidateRunner_%d" % int(definition["id"])
		runner.hero_scene = HEROES[index]
		runner.idle_scene = IDLES[index]
		runner.hurt_scene = HURTS[index]
		runner.stage_position = Vector3(-.35, 0.0, -1.45 if index == 0 else 1.45)
		runner.base_speed = float(definition["speed"])
		_runners_root.add_child(runner)
		runner.configure(int(definition["id"]), String(definition["name"]), Color(String(definition["color"])), Color(String(definition["text"])), Vector3(_get_lane_x(index), 0, 0), track_length)
		runners.append(runner)
		_stage_shadows.append(_make_contact_shadow())


func _make_contact_shadow() -> MeshInstance3D:
	var shadow: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(1.8, 1.1)
	shadow.mesh = plane
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void fragment() {
    float radius = length((UV - .5) * 2.0);
    ALBEDO = vec3(.018, .008, .025);
    ALPHA = pow(max(0.0, 1.0 - radius), 1.6) * .5;
}
"""
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	shadow.material_override = material
	add_child(shadow)
	return shadow


func _setup_camera() -> void:
	race_camera = RaceCamera.new()
	race_camera.name = "CameraDaTransmissao"
	add_child(race_camera)
	race_camera.set_physics_process(false)
	race_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	race_camera.keep_aspect = Camera3D.KEEP_WIDTH
	race_camera.fov = 66.0
	race_camera.near = .1
	race_camera.far = 120.0
	race_camera.position = Vector3(-5.2, 3.0, 0.0)
	race_camera.look_at(Vector3(8.0, .4, 0.0))
	race_camera.current = true


func _setup_hud() -> void:
	stadium_hud = StadiumHUD.new()
	stadium_hud.name = "PlacarDaArena"
	add_child(stadium_hud)
	_hud_layer = stadium_hud


func _on_visual_round_changed(_round_id: int, _cycle_id: int, metadata: Dictionary) -> void:
	_last_leader_slot = 0
	_leader_candidate = 0
	_final_stretch_announced = false
	world_visual.set_round_metadata(metadata)
	if audience != null:
		audience.reset_round()
	if avatar_visuals != null:
		avatar_visuals.cancel_pending_requests()
	_update_stage(0.0, true)


func _on_audience_moment(kind: String, team: int, _display_name: String) -> void:
	if bool(get_meta("restoring_session", false)):
		return
	if audio != null and kind == "join" and team > 0:
		audio.play_event("vote", team)


func _on_show_event(envelope: Dictionary) -> void:
	if avatar_visuals != null:
		avatar_visuals.register_event(envelope)
	if str(envelope.get("event_type", "")) != "gift":
		return
	_observe_gift_visual(envelope)
	if current_state in [RaceState.PHOTO_FINISH, RaceState.PODIO]:
		return
	if bool(get_meta("restoring_session", false)):
		return
	var payload: Dictionary = envelope.get("payload", {}) as Dictionary
	if payload.has("coin_value") and float(payload["coin_value"]) <= 0.0:
		return
	if str(payload.get("gift_tier", "")) == "T4":
		var team: int = int(payload.get("candidate_slot", 0))
		if team in [1, 2]:
			_begin_super_turbo.call_deferred(team)


func _observe_gift_visual(envelope: Dictionary) -> void:
	if gift_visuals == null:
		return
	var payload: Dictionary = envelope.get("payload", {}) as Dictionary
	if payload.has("coin_value") and float(payload["coin_value"]) <= 0.0:
		return
	var gift_id: String = str(payload.get("gift_id", "")).strip_edges()
	var action: String = _resolve_gift_legend_action(payload)
	if not gift_id.is_empty() and not action.is_empty():
		for existing_action: String in ["boost", "shield", "attack", "super_turbo"]:
			if existing_action != action and str(_observed_gift_actions.get(existing_action, "")) == gift_id:
				_observed_gift_actions.erase(existing_action)
		_observed_gift_actions[action] = gift_id
	gift_visuals.register_event(envelope)
	_refresh_gift_legend()


func _resolve_gift_legend_action(payload: Dictionary) -> String:
	var action_id: String = str(payload.get("action_id", "")).strip_edges()
	match action_id:
		"gift_t1_turbo", "boost":
			return "boost"
		"gift_t2_shield_or_obstacle", "gift_t2_shield", "shield":
			return "shield"
		"gift_t3_attack", "attack":
			return "attack"
		"gift_t4_super_rally", "super_turbo":
			return "super_turbo"
	match str(payload.get("gift_tier", "")).strip_edges().to_upper():
		"T1":
			return "boost"
		"T2":
			return "shield"
		"T3":
			return "attack"
		"T4":
			return "super_turbo"
	return ""


func _on_gift_icon_ready(gift_id: String, texture: Texture2D) -> void:
	_refresh_gift_legend()
	if stadium_hud != null:
		stadium_hud.on_gift_icon_ready(gift_id, texture)


func _on_avatar_icon_ready(avatar_path: String, texture: Texture2D) -> void:
	if stadium_hud != null:
		stadium_hud.on_avatar_ready(avatar_path, texture)


func _refresh_gift_legend() -> void:
	if stadium_hud == null or gift_visuals == null:
		return
	var entries: Array[Dictionary] = []
	for action: String in ["boost", "shield", "attack", "super_turbo"]:
		var gift_id: String = str(_observed_gift_actions.get(action, ""))
		if gift_id.is_empty():
			continue
		var icon: Texture2D = gift_visuals.get_icon(gift_id)
		if icon != null:
			entries.append({"action": action, "texture": icon})
	stadium_hud.set_gift_legend(entries)


func _begin_super_turbo(team: int) -> void:
	if current_state != RaceState.RACING or race_paused or _cinematic_cooldown > 0.0 or bool(get_meta("restoring_session", false)):
		return
	_cinematic_team = team
	_cinematic_time = 0.0
	_cinematic_cooldown = 8.0
	stadium_hud.show_event("SUPER TURBO · " + ("LULA" if team == 1 else "FLÁVIO"), team)
	audio.play_event("super_turbo", team)
	effects.trigger_moment("super_turbo", team)


func _update_broadcast_camera(delta: float) -> void:
	if race_paused:
		return
	if _finish_elapsed >= 0.0:
		_finish_elapsed += delta
		if _finish_elapsed >= .85 and winner != null:
			var champion: StadiumRunner = winner as StadiumRunner
			var orbit: float = sin(minf(_finish_elapsed - .85, 6.0) * .22) * .24
			race_camera.position = champion.stage_position + Vector3(4.6, 2.6, orbit * 4.6)
			race_camera.look_at(champion.stage_position + Vector3(0, 1.45, 0))
			race_camera.fov = 60.0
		return
	_cinematic_cooldown = maxf(0.0, _cinematic_cooldown - delta)
	if _cinematic_team == 0:
		return
	_cinematic_time += delta
	if _cinematic_time >= 3.0:
		_cinematic_team = 0
		_restore_camera()
		return
	var hero: StadiumRunner = runners[_cinematic_team - 1] as StadiumRunner
	var angle: float = lerpf(-.24, .24, smoothstep(0.0, 1.0, _cinematic_time / 3.0))
	race_camera.position = hero.stage_position + Vector3(cos(angle) * 3.6, 1.9, sin(angle) * 3.6)
	race_camera.look_at(hero.stage_position + Vector3(0, 1.3, 0))
	race_camera.fov = 57.0


func _restore_camera() -> void:
	race_camera.position = Vector3(-5.2, 3.0, 0.0)
	race_camera.look_at(Vector3(8.0, .4, 0.0))
	race_camera.fov = 66.0


func _on_audio_state_changed(state: int) -> void:
	if bool(get_meta("restoring_session", false)):
		return
	if audio != null and state == RaceState.RACING:
		audio.play_event("start")
	if effects != null and state == RaceState.RACING:
		effects.trigger_moment("start")
	if audio != null and state == RaceState.COUNTDOWN:
		audio.play_event("next_round")


func _on_audio_race_finished(result: CandidateRunner) -> void:
	if bool(get_meta("restoring_session", false)):
		return
	_cinematic_team = 0
	_finish_elapsed = 0.0
	_finish_positions.clear()
	var farthest: float = -1000.0
	for runner: CandidateRunner in runners:
		var hero: StadiumRunner = runner as StadiumRunner
		_finish_positions.append(hero.stage_position)
		hero.play_round_finish(hero == result)
		farthest = maxf(farthest, hero.stage_position.x)
	_finish_line.position = Vector3(farthest + 1.7, .025, 0)
	_finish_line.visible = true
	stadium_hud.show_event("EMPATE NA RODADA" if result == null else ("13 VENCEU · LULA" if result.candidate_id == 1 else "22 VENCEU · FLÁVIO"), 0 if result == null else result.candidate_id)
	if audio != null:
		audio.play_event("tie" if result == null else "podium", 0 if result == null else result.candidate_id)
	if effects != null:
		effects.trigger_moment("tie" if result == null else "podium", 0 if result == null else result.candidate_id)
	if sound_effects != null:
		sound_effects.play_event("victory")


func restart_race(p_skip_lobby: bool = false) -> void:
	super.restart_race(p_skip_lobby)
	_cinematic_team = 0
	_cinematic_cooldown = 0.0
	_finish_elapsed = -1.0
	_finish_positions.clear()
	_last_leader_slot = 0
	_leader_candidate = 0
	_leader_confirm_seconds = 0.0
	_overtake_cooldown = 0.0
	_final_stretch_announced = false
	if _finish_line != null:
		_finish_line.visible = false
	if race_camera != null:
		_restore_camera()
	if audio != null:
		audio.clear_pending()
	if effects != null:
		effects.clear_effects()
	if sound_effects != null:
		sound_effects.stop_all()
	if memes != null:
		memes.stop_all()
	_attack_visuals.clear()
	_attack_slots.clear()
	if avatar_visuals != null:
		avatar_visuals.cancel_pending_requests()
	if runners.size() == 2:
		_update_stage(0.0, true)


func set_race_paused(paused: bool) -> void:
	super.set_race_paused(paused)
	if effects != null:
		effects.set_paused(paused)
	if sound_effects != null:
		sound_effects.set_paused(paused)
	if audio != null:
		audio.set_paused(paused)
	if ambience != null:
		ambience.set_paused(paused)
	if memes != null:
		memes.set_paused(paused)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo:
			match key.keycode:
				KEY_P:
					set_race_paused(not race_paused)
				KEY_5:
					trigger_candidate_shield(1)
				KEY_6:
					trigger_candidate_shield(2)
				KEY_7:
					_begin_super_turbo(1)
				KEY_8:
					_begin_super_turbo(2)
	super._unhandled_input(event)


func _update_stage(delta: float, snap: bool = false) -> void:
	if runners.size() != 2:
		return
	var difference: float = runners[0].progress_m - runners[1].progress_m
	# O líder avança em profundidade; o último mantém a referência no primeiro plano.
	# A compressão logarítmica evita perder um personagem com grandes diferenças reais.
	var displacement: float = minf(7.0, 1.25 * log(1.0 + absf(difference)))
	for index: int in range(2):
		var runner: StadiumRunner = runners[index] as StadiumRunner
		var leads: bool = difference > 0.0 if index == 0 else difference < 0.0
		var target: Vector3 = Vector3(-.35 + (displacement if leads else 0.0), 0.0, -1.45 if index == 0 else 1.45)
		if _finish_elapsed >= 0.0 and _finish_positions.size() == 2:
			var advance: float = smoothstep(0.0, .85, _finish_elapsed) * (2.0 if winner == runner else 1.0)
			target = _finish_positions[index] + Vector3(advance, 0, 0)
		runner.stage_position = target if snap else runner.stage_position.lerp(target, 1.0 - exp(-5.0 * delta))
		runner._reset_procedural_transform()
		_stage_shadows[index].position = runner.stage_position + Vector3(0.0, .012, 0.0)
		if effects != null:
			effects.set_runner_state(index + 1, runner.stage_position, runner.boost_timer > 0.0 and current_state == RaceState.RACING, runner.shield_timer > 0.0 and current_state == RaceState.RACING, runner.stumble_timer > 0.0 and current_state == RaceState.RACING)
	world_visual.set_travel_distance((runners[0].progress_m + runners[1].progress_m) * .5 * VISUAL_METERS)
	world_visual.set_race_progress((runners[0].progress_m + runners[1].progress_m) * .5)
	if current_state == RaceState.RACING and match_time_remaining <= 5.0 and _finish_line != null:
		_finish_line.visible = true
		_finish_line.position = Vector3(maxf((runners[0] as StadiumRunner).stage_position.x, (runners[1] as StadiumRunner).stage_position.x) + 1.7 + match_time_remaining * 1.6, .025, 0.0)
	for index: int in range(_attack_visuals.size() - 1, -1, -1):
		if not is_instance_valid(_attack_visuals[index]) or _attack_visuals[index].is_queued_for_deletion():
			_attack_visuals.remove_at(index)
			_attack_slots.remove_at(index)
			continue
		var area: Area3D = _attack_visuals[index]
		var runner: StadiumRunner = runners[_attack_slots[index] - 1] as StadiumRunner
		var ahead: float = runner.global_position.z - area.global_position.z
		for child: Node in area.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = child as MeshInstance3D
			mesh.top_level = true
			mesh.global_position = runner.stage_position + Vector3(ahead * VISUAL_METERS, .35, 0.0)


func _update_hud() -> void:
	if stadium_hud == null or runners.size() < 2 or race_camera == null:
		return
	var phase: String = ""
	match current_state:
		RaceState.LOBBY_VOTACAO:
			phase = "ESCOLHA SUA EQUIPE · LARGADA EM %d" % ceili(state_timer)
		RaceState.COUNTDOWN:
			phase = "PREPARAR · %d" % maxi(1, ceili(countdown_remaining))
		RaceState.PHOTO_FINISH:
			phase = "TEMPO ESGOTADO · RESULTADO DA RODADA"
		RaceState.PODIO:
			phase = "EMPATE NA RODADA" if winner == null else ("13 VENCEU · LULA" if winner.candidate_id == 1 else "22 VENCEU · FLÁVIO")
	if race_paused:
		phase = "CORRIDA PAUSADA"
	var lula: StadiumRunner = runners[0] as StadiumRunner
	var flavio: StadiumRunner = runners[1] as StadiumRunner
	var live: Dictionary = _get_live_summary()
	stadium_hud.update_live_goal(live["goal"] as Dictionary, int(live["followers"]))
	stadium_hud.update_live_goals(live["goals"] as Dictionary, int(live["followers"]))
	stadium_hud.set_podium_mode(current_state == RaceState.PODIO)
	stadium_hud.apply_state({"round": current_round, "cycle": cycle_number, "wins": cycle_wins,
		"winner_id": winner.candidate_id if winner != null else 0, "state_name": _get_state_name(current_state), "next_round_in": get_next_round_in(),
		"round_name": round_metadata.get("name", "Arena Nacional"), "remaining": match_time_remaining,
		"round_finished": current_state == RaceState.PHOTO_FINISH or current_state == RaceState.PODIO,
		"lula_m": lula.progress_m, "flavio_m": flavio.progress_m,
		"lula_speed": lula.current_speed, "flavio_speed": flavio.current_speed,
		"lula_boost": lula.boost_timer > 0.0, "flavio_boost": flavio.boost_timer > 0.0,
		"lula_shield": lula.shield_timer > 0.0, "flavio_shield": flavio.shield_timer > 0.0,
		"lula_stumble": lula.stumble_timer > 0.0, "flavio_stumble": flavio.stumble_timer > 0.0,
		"lula_screen": race_camera.unproject_position(lula.stage_position + Vector3(0.0, 2.05, 0.0)) if _cinematic_team == 0 and _finish_elapsed < .85 else Vector2(-1000, -1000),
		"flavio_screen": race_camera.unproject_position(flavio.stage_position + Vector3(0.0, 2.05, 0.0)) if _cinematic_team == 0 and _finish_elapsed < .85 else Vector2(-1000, -1000),
		"phase": phase, "mode": _session_caption()})


func _session_caption() -> String:
	var platform: String = OS.get_environment("LIVE_PLATFORM").strip_edges().to_lower()
	if "--asset-preview" in OS.get_cmdline_user_args() or not platform in ["tiktok", "kwai"]:
		return "TESTE LOCAL"
	var ws_live: bool = event_bus != null and event_bus.is_ws_connected
	if platform == "tiktok":
		return "TIKTOK · BRIDGE" if ws_live else "TIKTOK · LOCAL"
	return "KWAI · BRIDGE" if ws_live else "KWAI · LOCAL"


func _sum_session_metric(counts: Dictionary, key: String) -> int:
	var total: int = 0
	for amount: Variant in counts.get(key, [0, 0, 0]) as Array:
		total += int(amount)
	return total


func _evaluate_single_goal(raw_goal: Dictionary, counts: Dictionary) -> Dictionary:
	var goal: Dictionary = raw_goal.duplicate(true)
	var kind: String = String(goal.get("goal_kind", "likes"))
	var target: int = maxi(1, int(goal.get("goal_target", 1000)))
	goal["goal_target"] = target
	var value: int = 0
	if kind == "gift_specific":
		if audience != null:
			var platform: String = OS.get_environment("LIVE_PLATFORM").strip_edges().to_lower()
			value = audience.get_gift_count(String(goal.get("goal_gift_id", "")), platform if platform in ["tiktok", "kwai"] else "")
		goal["unit_kind"] = "gift_specific"
	elif kind == "follows":
		var session_follows: int = _sum_session_metric(counts, "follows")
		goal["session_follows"] = session_follows
		var baseline_raw: Variant = goal.get("follower_baseline", null)
		if baseline_raw is int or baseline_raw is float:
			var baseline: int = maxi(0, int(baseline_raw))
			value = baseline + session_follows
			goal["follower_baseline"] = baseline
			goal["source_mode"] = "manual_baseline"
		else:
			value = session_follows
			goal["follower_baseline"] = null
			goal["source_mode"] = "session_only"
		goal["unit_kind"] = "follows"
	else:
		value = _sum_session_metric(counts, kind)
		goal["unit_kind"] = kind
	goal["value"] = value
	goal["progress"] = clampf(float(value) / float(target), 0.0, 1.0)
	return goal


func _get_live_summary() -> Dictionary:
	var counts: Dictionary = audience.get_session_counts() if audience != null else {}
	var goal: Dictionary = _evaluate_single_goal(live_goal, counts)
	var defaults: Dictionary = RaceMain.default_live_goals()
	var goals_summary: Dictionary = {}
	for slot: String in ["likes", "gifts", "follows"]:
		var slot_cfg: Dictionary = (live_goals.get(slot, defaults[slot]) as Dictionary)
		goals_summary[slot] = _evaluate_single_goal(slot_cfg, counts)
	var followers: int = _sum_session_metric(counts, "follows")
	return {"goal": goal, "goals": goals_summary, "followers": followers, "counts": counts}


func get_telemetry_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_telemetry_snapshot()
	var live: Dictionary = _get_live_summary()
	snapshot["live_goal"] = live["goal"]
	snapshot["live_goals"] = live["goals"]
	snapshot["audience"] = {"session": live["counts"], "top_supporters": audience.get_top_supporters() if audience != null else []}
	snapshot["audio"] = {"voices_ready": audio.voices_ready, "voice_status": audio.voice_status} if audio != null else {"voices_ready": false, "voice_status": "inicializando"}
	(snapshot["audio"] as Dictionary).merge(audio_settings, true)
	snapshot["next_round_in"] = get_next_round_in()
	snapshot["performance"] = {
		"fps": roundf(Performance.get_monitor(Performance.TIME_FPS) * 10.0) / 10.0,
		"frame_ms": roundf(Performance.get_monitor(Performance.TIME_PROCESS) * 100000.0) / 100.0,
		"physics_ms": roundf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 100000.0) / 100.0,
		"static_mem_mb": roundf(Performance.get_monitor(Performance.MEMORY_STATIC) / 10485.76) / 100.0,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	}
	snapshot["gift_visuals"] = gift_visuals.get_cache_stats() if gift_visuals != null else {}
	snapshot["avatar_visuals"] = avatar_visuals.get_cache_stats() if avatar_visuals != null else {}
	var platform: String = OS.get_environment("LIVE_PLATFORM").to_lower()
	snapshot["platform"] = platform if platform in ["tiktok", "kwai"] else "local"
	return snapshot


func _on_bus_admin_command(command: String, payload: Dictionary = {}) -> void:
	if command == "set_audio_settings":
		for key: String in ["voices_enabled", "sfx_enabled", "crowd_enabled", "memes_enabled"]:
			audio_settings[key] = bool(payload[key])
		_apply_audio_settings()
		send_telemetry_now()
		return
	if command == "set_live_goal":
		live_goal = {"goal_kind": String(payload["goal_kind"]), "goal_target": int(payload["goal_target"]), "goal_label": String(payload["goal_label"]).strip_edges()}
		if live_goal["goal_kind"] == "gift_specific":
			live_goal["goal_gift_id"] = String(payload["goal_gift_id"])
		var mapped_slot: String = "likes"
		if String(live_goal["goal_kind"]) == "follows":
			mapped_slot = "follows"
		elif String(live_goal["goal_kind"]) in ["gifts", "coins", "gift_specific"]:
			mapped_slot = "gifts"
		var updated_slot: Dictionary = (live_goals.get(mapped_slot, {}) as Dictionary).duplicate(true)
		updated_slot["goal_kind"] = live_goal["goal_kind"]
		updated_slot["goal_target"] = live_goal["goal_target"]
		updated_slot["goal_label"] = live_goal["goal_label"]
		if live_goal.has("goal_gift_id"):
			updated_slot["goal_gift_id"] = live_goal["goal_gift_id"]
		else:
			updated_slot.erase("goal_gift_id")
		live_goals[mapped_slot] = updated_slot
		_update_hud()
		send_telemetry_now()
		return
	if command == "set_live_goals":
		var incoming: Dictionary = payload["live_goals"] as Dictionary
		for slot: String in ["likes", "gifts", "follows"]:
			if not incoming.get(slot) is Dictionary:
				continue
			var raw_item: Dictionary = incoming[slot] as Dictionary
			var next_item: Dictionary = {
				"goal_kind": String(raw_item.get("goal_kind", slot)),
				"goal_target": maxi(1, int(raw_item.get("goal_target", 1000))),
				"goal_label": String(raw_item.get("goal_label", "Meta")).substr(0, 40)
			}
			if next_item["goal_kind"] == "gift_specific" and raw_item.get("goal_gift_id") is String:
				next_item["goal_gift_id"] = String(raw_item["goal_gift_id"]).substr(0, 64)
			if slot == "follows":
				var base_val: Variant = raw_item.get("follower_baseline", null)
				next_item["follower_baseline"] = maxi(0, int(base_val)) if (base_val is int or base_val is float) else null
				next_item["baseline_updated_at"] = String(raw_item["baseline_updated_at"]).substr(0, 64) if raw_item.get("baseline_updated_at") is String else null
			live_goals[slot] = next_item
		live_goal = (live_goals["likes"] as Dictionary).duplicate(true)
		_update_hud()
		send_telemetry_now()
		return
	super._on_bus_admin_command(command, payload)


func trigger_candidate_boost(candidate_id: int, amount: float = 5.0, duration: float = 3.5, voter_name: String = "Local", label: String = "TURBO") -> void:
	super.trigger_candidate_boost(candidate_id, amount, duration, voter_name, label)
	if bool(get_meta("restoring_session", false)):
		return
	if stadium_hud != null:
		stadium_hud.show_event("TURBO · " + ("LULA" if candidate_id == 1 else "FLÁVIO"), candidate_id, "boost")
	if audio != null:
		audio.play_event("super_turbo" if amount >= 15.0 else "boost", candidate_id)
	if sound_effects != null:
		sound_effects.play_event("boost", candidate_id)


func _on_bus_boost_requested(candidate_slot: int, amount: float, duration: float, voter_name: String, label: String) -> void:
	var reserved: bool = should_reserve_paid_effect()
	super._on_bus_boost_requested(candidate_slot, amount, duration, voter_name, label)
	if reserved:
		_show_reserved_effect(candidate_slot)
		return
	if bool(get_meta("restoring_session", false)):
		return
	stadium_hud.show_event("%s · %s" % [label, "LULA" if candidate_slot == 1 else "FLÁVIO"], candidate_slot, "boost")
	if audio != null:
		audio.play_event("super_turbo" if amount >= 15.0 else "boost", candidate_slot)
	if sound_effects != null:
		sound_effects.play_event("boost", candidate_slot)
	if memes != null:
		memes.play_event("boost", candidate_slot)


func trigger_candidate_shield(candidate_id: int, duration: float = 5.0, voter_name: String = "Local") -> void:
	var reserved: bool = should_reserve_paid_effect()
	super.trigger_candidate_shield(candidate_id, duration, voter_name)
	if reserved:
		_show_reserved_effect(candidate_id)
		return
	if bool(get_meta("restoring_session", false)):
		return
	if stadium_hud != null:
		stadium_hud.show_event("ESCUDO · " + ("LULA" if candidate_id == 1 else "FLÁVIO"), candidate_id, "shield")
	if audio != null:
		audio.play_event("shield", candidate_id)
	if sound_effects != null:
		sound_effects.play_event("shield", candidate_id)


func spawn_political_obstacle(target_slot: int, obstacle_type: String = "pilha_documentos", voter_name: String = "Oponente") -> Area3D:
	var area: Area3D = super.spawn_political_obstacle(target_slot, obstacle_type, voter_name)
	if area != null:
		if not _attack_visuals.has(area):
			_attack_visuals.append(area)
			_attack_slots.append(target_slot)
		_update_stage(0.0)
		if bool(get_meta("restoring_session", false)):
			return area
		stadium_hud.show_event("OBSTÁCULO NA RAIA DE " + ("LULA" if target_slot == 1 else "FLÁVIO"), target_slot, "attack")
		if audio != null:
			audio.play_event("attack", target_slot)
	return area


func _process(delta: float) -> void:
	_apply_audio_settings()
	_update_stage(delta)
	_update_broadcast_camera(delta)
	_update_race_moments(delta)
	if sound_effects != null and audio != null and audio._player != null:
		sound_effects.set_ducked(audio._player.playing)
	if ambience != null:
		ambience.update_state(current_state == RaceState.RACING, (runners[0].current_speed + runners[1].current_speed) / 24.0)
		ambience.set_ducked(audio.is_voice_playing() if audio != null else false)
	if memes != null:
		memes.set_ducked(audio.is_voice_playing() if audio != null else false)
	if _test_duration <= 0.0:
		return
	_test_elapsed += delta
	if _test_elapsed > 2.0:
		_frame_times_ms.append(delta * 1000.0)
	if _test_elapsed >= _test_duration and not _capture_started:
		_capture_started = true
		_finish_measurement.call_deferred()


func get_next_round_in() -> float:
	match current_state:
		RaceState.PHOTO_FINISH:
			return state_timer + podium_duration + countdown_duration
		RaceState.PODIO:
			return state_timer + countdown_duration
		RaceState.COUNTDOWN:
			return countdown_remaining
		RaceState.LOBBY_VOTACAO:
			return state_timer + countdown_duration
	return 0.0


func _update_race_moments(delta: float) -> void:
	if race_paused or current_state != RaceState.RACING or bool(get_meta("restoring_session", false)):
		return
	_overtake_cooldown = maxf(0.0, _overtake_cooldown - delta)
	if match_time_remaining <= 30.0 and not _final_stretch_announced:
		_final_stretch_announced = true
		if audio != null:
			audio.play_event("final_stretch")
	var difference: float = runners[0].progress_m - runners[1].progress_m
	var leader: int = 1 if difference > .6 else (2 if difference < -.6 else 0)
	if leader == 0:
		_leader_confirm_seconds = 0.0
		if audio != null:
			audio.set_current_leader(0)
		return
	if leader != _leader_candidate:
		_leader_candidate = leader
		_leader_confirm_seconds = 0.0
	_leader_confirm_seconds += delta
	if _leader_confirm_seconds < .35 or leader == _last_leader_slot:
		return
	var overtook: bool = _last_leader_slot > 0
	_last_leader_slot = leader
	if audio != null:
		audio.set_current_leader(leader)
	if overtook and _overtake_cooldown <= 0.0:
		_overtake_cooldown = 6.0
		stadium_hud.show_event("ULTRAPASSAGEM · " + ("13 LULA ASSUME A PONTA" if leader == 1 else "22 FLÁVIO ASSUME A PONTA"), leader)
		if audio != null:
			audio.play_event("overtake", leader)


func _apply_audio_settings() -> void:
	if audio != null:
		audio.enabled = bool(audio_settings["voices_enabled"])
	if sound_effects != null:
		sound_effects.enabled = bool(audio_settings["sfx_enabled"])
	if ambience != null:
		ambience.enabled = bool(audio_settings["crowd_enabled"])
	if memes != null:
		memes.enabled = bool(audio_settings["memes_enabled"])


func _safe_capture(path: String) -> bool:
	var base: String = ProjectSettings.globalize_path("res://").path_join("../docs/evidencias/estadio").simplify_path()
	var normalized: String = path.replace("\\", "/").simplify_path()
	var filename: RegEx = RegEx.new()
	filename.compile("^[A-Za-z0-9][A-Za-z0-9_-]*\\.png$")
	return path.is_absolute_path() and normalized.get_base_dir().to_lower() == base.to_lower() and filename.search(normalized.get_file()) != null and not FileAccess.file_exists(normalized)


func _finish_measurement() -> void:
	await RenderingServer.frame_post_draw
	var result: Error = OK
	if not _capture_path.is_empty():
		result = get_viewport().get_texture().get_image().save_png(_capture_path)
	_frame_times_ms.sort()
	var mean: float = 0.0
	for frame_ms: float in _frame_times_ms:
		mean += frame_ms
	mean /= maxf(1.0, float(_frame_times_ms.size()))
	var p95: float = _frame_times_ms[mini(_frame_times_ms.size() - 1, int(float(_frame_times_ms.size()) * .95))] if not _frame_times_ms.is_empty() else 0.0
	print("STADIUM_MEASUREMENT ", JSON.stringify({"frames": _frame_times_ms.size(), "mean_ms": mean, "p95_ms": p95, "fps_mean": 1000.0 / maxf(mean, .001), "viewport": {"width": get_viewport().get_visible_rect().size.x, "height": get_viewport().get_visible_rect().size.y}, "lula_m": runners[0].progress_m, "flavio_m": runners[1].progress_m, "remaining": match_time_remaining, "capture_error": result}))
	get_tree().quit(0 if result == OK else 1)


func _show_reserved_effect(team: int) -> void:
	if stadium_hud != null and not bool(get_meta("restoring_session", false)):
		stadium_hud.show_event("PRESENTE RESERVADO · PRÓXIMA RODADA", team)


func _on_reserved_super_turbo(team: int) -> void:
	_begin_super_turbo.call_deferred(team)
