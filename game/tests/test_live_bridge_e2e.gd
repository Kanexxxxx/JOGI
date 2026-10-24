extends SceneTree

var _race: RaceMain = null
var _bus: LiveEventBusInstance = null
var _phase: int = 0
var _elapsed: float = 0.0
var _baseline_speed: float = 0.0


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main/stadium_race.tscn") as PackedScene
	if packed != null:
		_race = packed.instantiate() as RaceMain
		if _race != null:
			root.add_child(_race)


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 15.0:
		printerr("E2E_TIMEOUT: Failed at phase ", _phase)
		_cleanup()
		quit(1)
		return true

	if _phase == 0:
		if _race == null:
			printerr("E2E_FAIL: RaceMain is null")
			_cleanup()
			quit(1)
			return true
		_bus = root.get_node_or_null("LiveEventBus") as LiveEventBusInstance
		if _bus == null:
			printerr("E2E_FAIL: LiveEventBus autoload not found")
			_cleanup()
			quit(1)
			return true
		_bus.reset_deduplication()
		if _race.runners.size() != 2:
			printerr("E2E_FAIL: Expected 2 runners (Lula vs Bolsonaro), found ", _race.runners.size())
			_cleanup()
			quit(1)
			return true
		# Start race in RACING state so incoming simulator events immediately boost Candidate #1
		_race.restart_race(true)
		_race.start_race_immediately()
		_race.obstacles_enabled = false
		_step_sim(0.1)
		_baseline_speed = _race.runners[0].current_speed

		var custom_url: String = OS.get_environment("LIVE_BRIDGE_WS_URL")
		if custom_url.strip_edges().is_empty():
			custom_url = "ws://127.0.0.1:8765/ws/godot"
		var err: Error = _bus.connect_to_local_bridge(custom_url)
		if err != OK:
			printerr("E2E_FAIL: connect_to_local_bridge returned error ", err)
			_cleanup()
			quit(1)
			return true
		_phase = 1
		return false

	if _phase == 1:
		_bus.poll_ws(delta)
		if _bus.is_ws_connected:
			print("E2E_WS_CONNECTED: ", _bus.ws_url)
			var tele_ok: bool = _bus.send_telemetry(_race.get_telemetry_snapshot())
			print("E2E_TELEMETRY_SENT: ", tele_ok)
			_phase = 2
		return false

	if _phase == 2:
		_bus.poll_ws(delta)
		_step_sim(delta)
		var r1: CandidateRunner = _race.runners[0]
		# Wait until we have received at least 4 events (welcome + simulator events for Candidate #1)
		var stadium: StadiumRace = _race as StadiumRace
		var goals: Dictionary = stadium.get_telemetry_snapshot().get("live_goals", {}) as Dictionary
		var goals_applied: bool = int((goals.get("likes", {}) as Dictionary).get("goal_target", 0)) == 1500 and String((goals.get("gifts", {}) as Dictionary).get("goal_gift_id", "")) == "rose_e2e" and int((goals.get("follows", {}) as Dictionary).get("value", 0)) == 8401
		if _bus.accepted_count >= 4 and goals_applied and r1.boost_timer > 0.0 and r1.current_speed > _baseline_speed:
			print("E2E_CANONICAL_GOALS_APPLIED: likes=1500 gifts=rose_e2e follows=8401/10000")
			print(
				"E2E_EVENTS_APPLIED: accepted=%d dup=%d r1_speed=%.2f baseline=%.2f progress=%.2fm" % [
					_bus.accepted_count,
					_bus.duplicate_count,
					r1.current_speed,
					_baseline_speed,
					r1.progress_m
				]
			)
			print("TEST_LIVE_BRIDGE_E2E_PASSED")
			_cleanup()
			quit(0)
			return true
		return false

	return false


func _step_sim(step_dt: float) -> void:
	if _race == null:
		return
	_race._physics_process(step_dt)
	for runner: CandidateRunner in _race.runners:
		runner._physics_process(step_dt)
	if _race.race_camera != null:
		_race.race_camera._physics_process(step_dt)


func _cleanup() -> void:
	if _bus != null:
		_bus.auto_connect = false
		_bus.allow_headless_ws = false
	if _race != null and is_instance_valid(_race):
		if _race.get_parent() != null:
			_race.get_parent().remove_child(_race)
		_race.free()
		_race = null
