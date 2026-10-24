extends SceneTree
## Testa o pool por PCM local simulado; sem API ou dependência de geração paga.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var passed: bool = true
	var effects: RaceSoundEffects = RaceSoundEffects.new()
	root.add_child(effects)
	effects.set_process(false)
	passed = _check(effects._players.size() == 4 and effects.get_child_count() == 4, "Pool fixo deve ter quatro players") and passed
	var pcm: AudioStreamWAV = AudioStreamWAV.new()
	pcm.mix_rate = 22050
	pcm.format = AudioStreamWAV.FORMAT_16_BITS
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(22050 * 2)
	pcm.data = bytes
	for kind: String in RaceSoundEffects.KINDS:
		effects._streams[kind] = pcm
	passed = _check(effects.play_event("boost",1) and not effects.play_event("boost",2), "Sons idênticos devem ser agrupados por cooldown") and passed
	effects._clock += .31
	passed = _check(effects.play_event("boost",2), "A outra equipe deve usar o mesmo som após o intervalo") and passed
	passed = _check(effects.play_event("shield") and effects.play_event("impact"), "Eventos distintos podem ocupar canais livres") and passed
	passed = _check(effects.play_event("victory"), "Fanfare deve substituir som menos prioritário no pool cheio") and passed
	effects._clock += 5.0
	passed = _check(not effects.play_event("boost"), "Som fraco não deve interromper canais de prioridade igual ou maior") and passed
	effects.set_ducked(true)
	for player: AudioStreamPlayer in effects._players:
		passed = _check(is_equal_approx(player.volume_db,effects.volume_db - 6.0), "Ducking deve baixar seis dB durante locução") and passed
	effects.set_paused(true)
	var before: float = effects._clock
	effects._process(3.0)
	passed = _check(is_equal_approx(before,effects._clock) and not effects.play_event("impact"), "Pausa congela cooldowns e bloqueia novos sons") and passed
	for player: AudioStreamPlayer in effects._players:
		passed = _check(player.stream_paused, "Pausa deve alcançar todos os players") and passed
	effects.set_paused(false)
	effects.stop_all()
	for iteration: int in range(1000):
		effects._clock += .31
		effects.play_event("boost",iteration % 2 + 1)
	passed = _check(effects.get_child_count() == 4 and effects._players.size() == 4, "Mil eventos não devem criar players novos") and passed
	passed = _check(not effects._safe_path("https://example.invalid/clip.mp3") and not effects._safe_path("res://assets/audio/elevenlabs-sfx/../a.mp3"), "Arquivo remoto ou fora do cache deve ser rejeitado") and passed
	root.remove_child(effects)
	effects.free()
	await create_timer(.12).timeout
	print("TEST_RACE_SOUND_EFFECTS_PASSED" if passed else "TEST_RACE_SOUND_EFFECTS_FAILED")
	quit(0 if passed else 1)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("FAIL: ", message)
	return condition
