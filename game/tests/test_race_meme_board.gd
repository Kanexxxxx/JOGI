extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var board: RaceMemeBoard = RaceMemeBoard.new()
	root.add_child(board)
	board.set_process(false)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RaceMemeBoard.MANIFEST_PATH)) as Dictionary
	# Isolar o modo desligado da seleção real configurada pelo operador.
	# As fixtures abaixo só mudam cópias em memória, nunca o manifesto em disco.
	data["enabled"] = false
	for clip: Dictionary in data["clips"]:
		clip["enabled"] = false
	board.configure_manifest(data)
	var passed: bool = not board.enabled and board._clips.is_empty() and not board.play_event("reaction", 0)
	data["enabled"] = true
	for clip: Dictionary in data["clips"]:
		clip["enabled"] = true
		clip["kind"] = "reaction"
		clip["team"] = 0
		clip["review_status"] = "pending"
	board.configure_manifest(data)
	passed = board._clips.is_empty() and passed
	for clip: Dictionary in data["clips"]:
		clip["review_status"] = "approved"
	board.configure_manifest(data)
	passed = board._clips.size() > 0 and board._clips.size() < (data["clips"] as Array).size() and passed
	for stream: AudioStream in board._streams.values():
		passed = stream.get_length() <= 5.0 and passed
	board.set_ducked(true)
	passed = board.play_event("reaction", 1) and passed
	board._process(.1)
	passed = not board._player.playing and passed
	board._process(3.0)
	passed = board._pending.is_empty() and passed
	board.set_ducked(false)
	passed = board.play_event("reaction", 1) and passed
	board._process(.1)
	passed = board._player.playing and not board.play_event("reaction", 2) and passed
	board.set_ducked(true)
	passed = not board._player.playing and passed
	board.stop_all()
	passed = not board.play_event("reaction", 1) and passed
	board.set_paused(true)
	var clock: float = board._clock
	board._process(120.0)
	passed = is_equal_approx(clock, board._clock) and passed
	passed = not board._safe_path("res://assets/audio/user-memes/../outside.mp3") and passed
	print("MEME_BOARD ", JSON.stringify(board.get_status()))
	root.remove_child(board)
	board.free()
	await create_timer(.2).timeout
	print("TEST_RACE_MEME_BOARD_PASSED" if passed else "TEST_RACE_MEME_BOARD_FAILED")
	quit(0 if passed else 1)
