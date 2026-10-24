extends SceneTree
## Decodifica os quatro MP3 já gerados, sem rede ou reprodução nos alto-falantes.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var effects: RaceSoundEffects = RaceSoundEffects.new()
	root.add_child(effects)
	var passed: bool = effects.sfx_ready and effects._streams.size() == 4
	var lengths: Dictionary = {}
	var total: float = 0.0
	for kind: String in RaceSoundEffects.KINDS:
		var stream: AudioStream = effects._streams.get(kind) as AudioStream
		if stream == null:
			passed = false
			continue
		var seconds: float = stream.get_length()
		passed = seconds >= .5 and seconds <= 3.2 and passed
		total += seconds
		lengths[kind] = seconds
	passed = total <= 8.0 and passed
	print("SFX_CACHED ", JSON.stringify({"durations":lengths,"total_seconds":total,"ready":effects.sfx_ready}))
	root.remove_child(effects)
	effects.free()
	await process_frame
	print("TEST_SFX_CACHED_PASSED" if passed else "TEST_SFX_CACHED_FAILED")
	quit(0 if passed else 1)
