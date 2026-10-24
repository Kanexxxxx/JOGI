extends SceneTree
## Bounded distance pool, real metre projection and cloth pin/continuity contract.

var _failed: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("ART_REVISION_FAIL: ", message)


func _run() -> void:
	var world: StadiumWorld = StadiumWorld.new()
	world.build_lighting = false
	world.crowd_count = 0
	root.add_child(world)
	_check(world._distance_markers.size() == 6, "exactly six recycled metre markers")
	_check(world.get_node_or_null("AnoCenografico2027") != null, "discrete 2027 scenic label")
	world.set_race_progress(125.0)
	_check(world._distance_labels[0].text == "100 m" and world._distance_labels[5].text == "350 m", "labels use real simulation metres")
	var old: float = world._distance_markers[2].position.x
	world.set_race_progress(135.0)
	_check(is_equal_approx(old - world._distance_markers[2].position.x, 1.8), "ten physical metres project to 1.8 stage metres")
	var node_ids: Array[int] = []
	for marker: Node3D in world._distance_markers:
		node_ids.append(marker.get_instance_id())
	for step: int in range(10000):
		world.set_race_progress(float(step) * 1000.0)
	for index: int in range(6):
		_check(world._distance_markers[index].get_instance_id() == node_ids[index], "long session never creates marker nodes")
	world.set_race_progress(0.0)
	_check(world._distance_labels[0].text == "0 m", "new round resets measured signs")
	world.set_race_progress(NAN)
	_check(world._race_progress == 0.0, "non-finite metres ignored")
	var cape: CandidateCapeMotion = CandidateCapeMotion.new()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = CandidateCapeMotion.SHADER
	cape._materials.append(material)
	for frame: int in range(120):
		cape.step(1.0 / 60.0, true, 1.0, false, false, false, false, false, 1.0)
	var run: Dictionary = cape.get_state()
	_check(float(run.amplitude) > .14, "running cape has visible free-hem amplitude")
	for frame: int in range(120):
		cape.step(1.0 / 60.0, true, 2.0, true, false, false, false, false, 1.0)
	_check(float(cape.get_state().amplitude) > float(run.amplitude) * 1.5, "turbo visibly increases wind strength")
	var frozen: Dictionary = cape.get_state()
	cape.step(4.0, true, 2.0, true, false, true, false, false, 1.0)
	_check(cape.get_state().phase == frozen.phase, "pause freezes fabric")
	for frame: int in range(120):
		cape.step(1.0 / 60.0, false, .0, false, true, false, false, false, 1.0)
	_check(float(cape.get_state().amplitude) < .03, "impact wind settles smoothly")
	root.remove_child(world)
	world.free()
	cape._materials.clear()
	material = null
	cape = null
	await process_frame
	print("TEST_STADIUM_ART_REVISION_PASSED" if not _failed else "TEST_STADIUM_ART_REVISION_FAILED")
	quit(1 if _failed else 0)
