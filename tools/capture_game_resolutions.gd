extends SceneTree
## Native SubViewport renders of the actual game. No resize of an existing PNG.
## Explicit, deterministic TESTE LOCAL fixtures, not platform events.

const SIZES: Array[Vector2i] = [Vector2i(1080, 1920), Vector2i(720, 1280), Vector2i(540, 960), Vector2i(360, 640)]
var viewport: SubViewport = null
var race: StadiumRace = null
var output: String = ""
var captures: Array[Dictionary] = []
var sequence: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var isolated_root: String = OS.get_environment("GDA_USER_DATA_ROOT").replace("\\", "/").simplify_path().to_lower()
	var actual_root: String = ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().to_lower()
	if isolated_root.is_empty() or not actual_root.begins_with(isolated_root + "/"):
		printerr("CAPTURE_REQUIRES_ISOLATED_USER_DATA")
		quit(1)
		return
	output = OS.get_environment("JOGI_CAPTURE_OUTPUT").replace("\\", "/")
	var allowed: String = ProjectSettings.globalize_path("res://../docs/evidencias/estadio/").simplify_path()
	if output.is_empty() or not output.is_absolute_path() or not output.simplify_path().begins_with(allowed):
		printerr("CAPTURE_INVALID_OUTPUT_DIRECTORY")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	viewport = SubViewport.new()
	viewport.size = SIZES[0]
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	race = (load("res://scenes/main/stadium_race.tscn") as PackedScene).instantiate() as StadiumRace
	viewport.add_child(race)
	race.set_process(false)
	race.set_physics_process(false)
	race.stadium_hud.custom_viewport = viewport
	race.audio_settings = {"voices_enabled": false, "sfx_enabled": false, "crowd_enabled": false, "memes_enabled": false}
	race._apply_audio_settings()
	race.stadium_hud.frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
	race.stadium_hud.frame.size = Vector2(1080, 1920)
	await process_frame
	for scenario: String in ["day-empty", "day-overtake", "night-ranking", "podium", "ended"]:
		for dimensions: Vector2i in SIZES:
			viewport.size = dimensions
			var ratio: Vector2 = Vector2(dimensions) / Vector2(1080, 1920)
			race.stadium_hud.scale = ratio
			if not _prepare(scenario):
				printerr("CAPTURE_SCENARIO_FAILED ", scenario)
				quit(1)
				return
			race._update_hud()
			# Projection is physical SubViewport pixels, while HUD layout uses its
			# explicit 1080x1920 logical canvas. Preserve runner badge alignment.
			race.stadium_hud._lula_screen /= ratio
			race.stadium_hud._flavio_screen /= ratio
			race.stadium_hud._process(.016)
			await process_frame
			await RenderingServer.frame_post_draw
			var image: Image = viewport.get_texture().get_image()
			var name: String = "%s-%dx%d.png" % [scenario, dimensions.x, dimensions.y]
			if FileAccess.file_exists(output.path_join(name)):
				printerr("CAPTURE_REFUSES_OVERWRITE ", name)
				quit(1)
				return
			var error: Error = image.save_png(output.path_join(name))
			captures.append({"file": name, "scenario": scenario, "viewport_size": [viewport.size.x, viewport.size.y],
				"png_size": [image.get_width(), image.get_height()], "logical_canvas": [1080, 1920],
				"method": "new GPU render at native SubViewport size, explicit CanvasLayer scale, physical-to-logical badge projection",
				"image_resize_called": false, "error": error, "fixture_label": "isolated synthetic visual scenario",
				"runtime_mode": race.runtime_mode, "simulated_audience": not race.is_production_mode()})
			print("NATIVE_GAME_CAPTURE ", name, " ", image.get_width(), "x", image.get_height(), " ", error)
	var report: FileAccess = FileAccess.open(output.path_join("capture-report.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"captures": captures, "public_live": false, "paid_api_calls": 0}, "  "))
	report.close()
	root.remove_child(viewport)
	viewport.free()
	await create_timer(.5).timeout
	quit(0)


func _prepare(scenario: String) -> bool:
	race.restart_race(true)
	race.start_race_immediately()
	race.audience.reset_session()
	race.stadium_hud.update_leaderboard([])
	var metadata: Dictionary = race.round_metadata.duplicate(true)
	metadata["preset_id"] = 8 if scenario == "night-ranking" else 1
	metadata["name"] = "NOITE EM BRASÍLIA" if scenario == "night-ranking" else "PRIMEIRO SOL"
	race.world_visual.set_round_metadata(metadata)
	race.round_metadata = metadata
	var distances: Array[float] = [450.0, 450.0]
	if scenario != "day-empty":
		distances.assign([450.0, 480.0])
	if race.is_production_mode() and scenario == "day-empty":
		distances.assign([0.0, 0.0])
	for index: int in range(2):
		var runner: StadiumRunner = race.runners[index] as StadiumRunner
		runner.set_physics_process(false)
		runner.global_position.z = runner.start_z - distances[index]
		runner.progress_m = distances[index]
		runner.current_speed = 12.0
		runner.presentation.update_motion(true, 12.0, 12.0, false, false, false, 1.0)
		runner.presentation.animation_player.advance(.25)
	race._update_rankings()
	race._update_stage(0.0, true)
	if scenario != "day-empty" and not race.is_production_mode():
		for index: int in range(5):
			sequence += 1
			var envelope: Dictionary = {"schema_version": "1.0", "source": "simulator", "event_id": "native-capture-%d" % sequence,
				"event_type": "gift", "user": {"user_id": "qa_viewer_%d" % index,
				"display_name": "QA 👩🏽‍🚀 Nome muito comprido" if index == 0 else "QA Pessoa %d" % index},
				"payload": {"coin_value": (5 - index) * 20, "repeat_count": 1, "gift_tier": "T1", "gift_name": "Presente TESTE", "candidate_slot": index % 2 + 1}}
			race.event_bus.ingest_envelope(envelope)
	if scenario == "day-overtake":
		race.stadium_hud.show_event("ULTRAPASSAGEM · 22 FLÁVIO ASSUME A PONTA", 2)
	if scenario == "podium":
		race.match_time_remaining = 0.0
		race._finish_match_by_timer()
		race.current_state = RaceMain.RaceState.PODIO
		race.state_timer = 22.0
		race._finish_elapsed = 1.3
		race._update_stage(0.0, true)
		race._update_broadcast_camera(0.0)
		for runner: CandidateRunner in race.runners:
			var hero: StadiumRunner = runner as StadiumRunner
			hero.presentation._process(1.3)
			hero.presentation.animation_player.advance(.6)
	if scenario == "ended":
		race.end_experience("manual")
	race.set_race_paused(false)
	for runner: CandidateRunner in race.runners:
		runner.set_physics_process(false)
		runner.set_process(false)
		runner.presentation.set_process(false)
	race._update_hud()
	return true
