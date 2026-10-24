extends SceneTree
## Bounded real-game backend/UI QA. Requires an isolated user-data root and test port.

var race: StadiumRace = null
var elapsed: float = 0.0
var limit: float = 180.0
var stop_file: String = ""
var stopping: bool = false


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	var url: String = OS.get_environment("LIVE_BRIDGE_WS_URL")
	var isolated_root: String = OS.get_environment("GDA_USER_DATA_ROOT").replace("\\", "/").simplify_path().to_lower()
	var actual_root: String = ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().to_lower()
	if isolated_root.is_empty() or not actual_root.begins_with(isolated_root + "/"):
		printerr("QA_RUNTIME_REQUIRES_ISOLATED_USER_DATA")
		quit(1)
		return
	if OS.get_environment("GDA_USER_DATA_ROOT").is_empty() or url.is_empty() or url.contains(":8765/") or url.contains(":8766/"):
		printerr("QA_RUNTIME_REQUIRES_ISOLATION")
		quit(1)
		return
	limit = clampf(OS.get_environment("JOGI_QA_SECONDS").to_float(), 30.0, 600.0)
	stop_file = OS.get_environment("JOGI_QA_STOP_FILE")
	race = (load("res://scenes/main/stadium_race.tscn") as PackedScene).instantiate() as StadiumRace
	root.add_child(race)
	if race.event_bus == null or not race.event_bus.is_loopback_ws_url(url):
		printerr("QA_RUNTIME_INVALID_BRIDGE")
		quit(1)
		return
	race.event_bus.connect_to_local_bridge(url)
	print("ADMIN_QA_RUNTIME_READY")


func _process(delta: float) -> bool:
	if race == null or stopping:
		return false
	elapsed += delta
	if elapsed >= limit or (not stop_file.is_empty() and FileAccess.file_exists(stop_file)):
		stopping = true
		_finish.call_deferred()
	return false


func _finish() -> void:
	if race.persistence != null and race.persistence.is_ready:
		race.persistence.flush_snapshot()
	root.remove_child(race)
	race.free()
	race = null
	await create_timer(.1).timeout
	print("ADMIN_QA_RUNTIME_STOPPED")
	quit(0)
