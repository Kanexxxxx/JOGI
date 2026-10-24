extends SceneTree
## Isolated GPU test harness. Loaded against the real scene; no paid API or public live.

var race: StadiumRace = null
var output_dir: String = ""
var channel: String = ""
var started_us: int = 0
var started_unix: float = 0.0
var last_frame_us: int = 0
var duration_seconds: float = 620.0
var frame_ms: Array[float] = []
var samples: Array[Dictionary] = []
var last_sample: float = -10.0
var finishing: bool = false
var persistence: RacePersistence = null
var store: RaceSessionStore = null


func _initialize() -> void:
	call_deferred("_setup")


func _setup() -> void:
	output_dir = OS.get_environment("JOGI_BENCH_OUTPUT").replace("\\", "/")
	channel = OS.get_environment("LIVE_PLATFORM")
	duration_seconds = clampf(OS.get_environment("JOGI_BENCH_SECONDS").to_float(), 5.0, 660.0)
	var allowed: String = ProjectSettings.globalize_path("res://../docs/evidencias/benchmark/").simplify_path()
	if not output_dir.is_absolute_path() or not output_dir.simplify_path().begins_with(allowed) or channel not in ["tiktok", "kwai"]:
		printerr("BENCHMARK_INVALID_OUTPUT")
		quit(1)
		return
	race = (load("res://scenes/main/stadium_race.tscn") as PackedScene).instantiate() as StadiumRace
	root.add_child(race)
	race.set_race_paused(true)
	store = RaceSessionStore.new(channel, "user://session-store-tests/dual_benchmark_" + OS.get_environment("JOGI_BENCH_ID"))
	persistence = RacePersistence.new()
	race.add_child(persistence)
	race.persistence = persistence
	if not persistence.setup(race, race.audience, race.event_bus, channel, store):
		printerr("BENCHMARK_PERSISTENCE_SETUP_FAILED ", persistence.last_error)
		quit(1)
		return
	race.event_bus.connect_to_local_bridge(OS.get_environment("LIVE_BRIDGE_WS_URL"))
	await RenderingServer.frame_post_draw
	var ready: FileAccess = FileAccess.open(output_dir.path_join(channel + "-ready.json"), FileAccess.WRITE)
	ready.store_string(JSON.stringify({"channel": channel, "pid": OS.get_process_id(), "window_size": get_root().size,
		"render_size": get_root().get_visible_rect().size, "ready_unix": Time.get_unix_time_from_system()}))
	ready.close()
	print("BENCHMARK_READY ", channel)


func _process(delta: float) -> bool:
	if race == null or finishing:
		return false
	if started_us == 0:
		if FileAccess.file_exists(output_dir.path_join("start.signal")):
			started_us = Time.get_ticks_usec()
			last_frame_us = started_us
			started_unix = Time.get_unix_time_from_system()
			race.set_race_paused(false)
		return false
	var now_us: int = Time.get_ticks_usec()
	var elapsed: float = float(now_us - started_us) / 1000000.0
	# Raw monotonic wall time, not Godot's potentially smoothed process delta.
	var wall_frame_ms: float = float(now_us - last_frame_us) / 1000.0
	last_frame_us = now_us
	if elapsed > 2.0:
		frame_ms.append(wall_frame_ms)
	if elapsed - last_sample >= 5.0:
		last_sample = elapsed
		samples.append({"elapsed": elapsed, "fps": Performance.get_monitor(Performance.TIME_FPS),
			"frame_ms": wall_frame_ms, "engine_delta_ms": delta * 1000.0,
			"static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
			"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			"renderer_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"persistence_ready": persistence.is_ready, "persistence_error": persistence.last_error,
			"gift_journal_bytes": store.get_journal_cursor(),
			"state": race._get_state_name(race.current_state), "round": race.current_round})
	if elapsed >= duration_seconds:
		finishing = true
		_finish.call_deferred(elapsed)
	return false


func _finish(elapsed: float) -> void:
	await RenderingServer.frame_post_draw
	var snapshot_saved: bool = persistence.flush_snapshot()
	var capture_error: Error = root.get_texture().get_image().save_png(output_dir.path_join(channel + "-final.png"))
	frame_ms.sort()
	var total_ms: float = 0.0
	var over_33: int = 0
	for value: float in frame_ms:
		total_ms += value
		over_33 += 1 if value > 33.333333 else 0
	var count: int = frame_ms.size()
	var mean: float = total_ms / maxf(1.0, float(count))
	var result: Dictionary = {"channel": channel, "duration_seconds": elapsed, "started_unix": started_unix,
		"frame_measurement": "raw Time.get_ticks_usec intervals after 2s warmup; unsmoothed",
		"finished_unix": Time.get_unix_time_from_system(), "frames": count,
		"fps_mean": 1000.0 / maxf(mean, .001), "mean_frame_ms": mean,
		"p95_frame_ms": _percentile(.95), "p99_frame_ms": _percentile(.99),
		"one_percent_low_fps": 1000.0 / maxf(_percentile(.99), .001),
		"worst_frame_ms": frame_ms.back() if count > 0 else .0,
		"frames_over_33ms": over_33, "viewport_width": root.get_visible_rect().size.x,
		"viewport_height": root.get_visible_rect().size.y, "samples": samples,
		"capture_error": capture_error, "accepted_events": race.event_bus.accepted_count,
		"final_snapshot_saved": snapshot_saved, "persistence_error": persistence.last_error,
		"gift_journal_bytes": store.get_journal_cursor(),
		"duplicate_events": race.event_bus.duplicate_count, "rejected_events": race.event_bus.rejected_count,
		"lula_m": race.runners[0].progress_m, "flavio_m": race.runners[1].progress_m}
	var file: FileAccess = FileAccess.open(output_dir.path_join(channel + "-engine.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("BENCHMARK_FINISHED ", JSON.stringify({"channel": channel, "fps_mean": result["fps_mean"], "duration": elapsed, "frames": count}))
	root.remove_child(race)
	race.free()
	race = null
	await create_timer(.5).timeout
	quit(0 if capture_error == OK else 1)


func _percentile(fraction: float) -> float:
	return frame_ms[mini(frame_ms.size() - 1, int(float(frame_ms.size()) * fraction))] if not frame_ms.is_empty() else 0.0
