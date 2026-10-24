extends SceneTree
## Decodificação real e relógio acelerado não substituem ensaio contínuo com OBS.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ambience: RaceAmbience = RaceAmbience.new()
	root.add_child(ambience)
	ambience.set_process(false)
	var audio: RaceAudio = RaceAudio.new()
	root.add_child(audio)
	audio.set_process(false)
	var passed: bool = ambience.ambience_ready and audio.voices_ready and audio._clips.size() == 38
	var durations: Dictionary = {}
	for clip: Dictionary in audio._clips:
		if String(clip["kind"]) in ["overtake", "final_stretch", "next_round", "podium"]:
			var stream: AudioStream = audio._streams.get(String(clip["id"])) as AudioStream
			passed = stream != null and passed
			if stream != null:
				durations[String(clip["id"])] = stream.get_length()
				passed = stream.get_length() > 0.5 and stream.get_length() < 8.0 and passed
	ambience.update_state(true, 1.0)
	var nodes_before: int = get_node_count()
	for index: int in range(16000):
		ambience._process(10.0)
	passed = get_node_count() == nodes_before and ambience._players.size() == 2 and passed
	ambience.set_paused(true)
	var elapsed: float = ambience._elapsed
	ambience._process(20.0)
	passed = is_equal_approx(ambience._elapsed, elapsed) and ambience._players[ambience._current].stream_paused and passed
	ambience.set_paused(false)
	ambience.set_ducked(true)
	ambience._process(1.0)
	passed = ambience._players[ambience._current].volume_db <= -30.0 and passed
	ambience.enabled = false
	ambience._process(1.0)
	passed = not ambience._players[0].playing and not ambience._players[1].playing and passed
	passed = not ambience._safe_path("res://assets/audio/elevenlabs-sfx/../outside.mp3") and passed
	print("AUDIO_REVISION ", JSON.stringify({"voices_ready": audio.voices_ready, "voice_count": audio._clips.size(), "durations": durations, "ambience": ambience.get_status(), "simulated_seconds": 160000, "fixed_node_count": get_node_count() == nodes_before}))
	root.remove_child(ambience)
	ambience.free()
	root.remove_child(audio)
	audio.free()
	await create_timer(.2).timeout
	print("TEST_RACE_AMBIENCE_PASSED" if passed else "TEST_RACE_AMBIENCE_FAILED")
	quit(0 if passed else 1)
