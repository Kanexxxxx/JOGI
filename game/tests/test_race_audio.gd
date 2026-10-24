extends SceneTree
## Fila/cooldown/expiração/fallback reais, sem HTTP ou voz remota.

var _audio: RaceAudio = null
var _events: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var passed: bool = true
	_audio = RaceAudio.new()
	root.add_child(_audio)
	_audio.set_process(false)
	_audio.cue_started.connect(_record_event)
	# O fallback é testado com um manifesto deliberadamente sem arquivos,
	# independentemente de o pacote real já ter sido gerado nesta máquina.
	var fallback: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RaceAudio.MANIFEST_PATH)) as Dictionary
	for clip: Dictionary in fallback["clips"]:
		clip.erase("clip_path")
	_audio.configure_manifest(fallback)
	passed = _check(_audio._clips.size() >= 30 and not _audio.voices_ready and _audio.voice_status == "vozes_pendentes", "Manifesto sem arquivos deve manter falas explicitamente pendentes") and passed
	passed = _check(not _audio.play_event("comentario livre", 1) and not _audio.play_event("boost", 13), "Entrada externa não deve escolher arquivo ou equipe inválidos") and passed
	passed = _check(_audio.play_event("boost", 1) and not _audio.play_event("boost", 1) and _audio.play_event("boost", 2), "Cooldown por evento/equipe deve conter spam sem bloquear a outra equipe") and passed
	_audio.clear_pending()
	for team: int in [1, 2]:
		for kind: String in ["vote", "boost", "shield", "attack"]:
			passed = _check(_audio.play_event(kind, team), "Eventos distintos devem entrar na fila") and passed
	passed = _check(_audio._queue.size() == 8, "Fila deve ter no máximo oito alertas") and passed
	passed = _check(_audio.play_event("podium", 1) and _audio._queue.size() == 1 and int(_audio._queue[0]["priority"]) == 100, "Pódio deve cancelar alertas antigos de corrida") and passed
	_audio._clock += .5
	_audio._process(0.0)
	passed = _check(_events.size() == 1 and _events[0]["kind"] == "podium" and not bool(_events[0]["has_voice"]), "Fallback deve tocar um som local e identificar ausência de voz") and passed
	passed = _check(_audio._player.stream is AudioStreamWAV and _audio._player.volume_db <= -14.0, "Fallback deve ser PCM local discreto") and passed
	var queued: int = _audio._queue.size()
	_audio._process(.01)
	passed = _check(_audio._queue.size() == queued, "Um único player impede falas sobrepostas") and passed
	_audio.clear_pending()
	_audio.play_event("vote", 1)
	_audio._clock += 7.0
	_audio._process(0.0)
	passed = _check(_audio._queue.is_empty() and _events.size() == 1, "Alerta antigo deve expirar sem tocar atrasado") and passed
	passed = _check(not _audio._safe_clip_path("https://example.invalid/a.mp3") and not _audio._safe_clip_path("res://assets/audio/elevenlabs/../a.mp3"), "Somente cache local SHA é aceito") and passed
	passed = _check(_audio._safe_clip_path("res://assets/audio/elevenlabs/" + "a".repeat(64) + ".mp3"), "Caminho válido de cache deve ser aceito") and passed
	_audio.local_cues_enabled = false
	_audio.clear_pending()
	_audio.play_event("start")
	_audio._clock += 1.0
	_audio._process(0.0)
	passed = _check(not _audio._player.playing and _events.size() == 1, "Sem voz e sem fallback, o runtime deve permanecer silencioso") and passed
	_audio.clear_pending()
	passed = _check(_audio.play_event("overtake", 1) and _audio.play_event("overtake", 2) and _audio._queue.size() == 1 and int((_audio._queue[0]["clip"] as Dictionary)["team"]) == 2, "Ultrapassagem mais recente substitui líder antigo ainda na fila") and passed
	_audio._clock += 3.0
	_audio._process(0.0)
	passed = _check(_audio._queue.is_empty(), "Ultrapassagem expira após dois segundos e meio") and passed
	_audio.clear_pending()
	passed = _check(_audio.play_event("overtake", 1) and _audio.play_event("overtake", 2), "Duas trocas rápidas de liderança devem ser aceitas inicialmente") and passed
	var cooldown_1: float = float(_audio._cooldowns["overtake:1"])
	var cooldown_2: float = float(_audio._cooldowns["overtake:2"])
	passed = _check(not _audio.play_event("overtake", 1) and _audio._queue.is_empty(), "Retorno 1 -> 2 -> 1 durante cooldown cancela fala pendente de líder errado") and passed
	passed = _check(is_equal_approx(float(_audio._cooldowns["overtake:1"]), cooldown_1) and is_equal_approx(float(_audio._cooldowns["overtake:2"]), cooldown_2), "Invalidar liderança não prolonga cooldowns") and passed
	_audio.clear_pending()
	_audio.local_cues_enabled = true
	_audio.play_event("overtake", 2)
	_audio._clock += .5
	_audio._process(0.0)
	passed = _check(_audio._player.playing and _audio._active_kind == "overtake" and _audio._active_team == 2, "Identidade da fala em reprodução deve registrar liderança anunciada") and passed
	var playing_cooldown: float = float(_audio._cooldowns["overtake:2"])
	_audio.set_current_leader(1)
	passed = _check(not _audio._player.playing and _audio._active_kind.is_empty() and _audio._queue.is_empty(), "Novo líder cancela fala contrária já tocando sem exigir outro anúncio") and passed
	passed = _check(is_equal_approx(float(_audio._cooldowns["overtake:2"]), playing_cooldown), "Cancelar fala em reprodução preserva cooldown existente") and passed
	_audio.clear_pending()
	_audio.play_event("overtake", 1)
	_audio.set_current_leader(0)
	passed = _check(_audio._queue.is_empty(), "Empate confirmado cancela anúncio de liderança pendente") and passed
	_audio.clear_pending()
	_audio.set_paused(true)
	var before_pause: float = _audio._clock
	_audio._process(90.0)
	passed = _check(not _audio.play_event("boost", 1) and is_equal_approx(_audio._clock, before_pause), "Pausa congela relógio e não acumula falas") and passed
	_audio.set_paused(false)
	root.remove_child(_audio)
	_audio.free()
	await create_timer(.5).timeout  # O mixer libera os últimos playbacks antes de encerrar o processo.
	print("TEST_RACE_AUDIO_PASSED" if passed else "TEST_RACE_AUDIO_FAILED")
	quit(0 if passed else 1)


func _record_event(kind: String, team: int, has_voice: bool) -> void:
	_events.append({"kind": kind, "team": team, "has_voice": has_voice})


func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("FAIL: ", message)
	return condition
