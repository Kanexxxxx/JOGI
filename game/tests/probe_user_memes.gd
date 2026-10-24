extends SceneTree


func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RaceMemeBoard.MANIFEST_PATH)) as Dictionary
	var result: Array[Dictionary] = []
	for clip: Dictionary in data["clips"]:
		var stream: AudioStreamMP3 = AudioStreamMP3.new()
		stream.data = FileAccess.get_file_as_bytes(String(clip["clip_path"]))
		result.append({"id": clip["id"], "source_names": clip["source_names"], "seconds": stream.get_length()})
	print("USER_MEME_DURATIONS ", JSON.stringify(result))
	quit(0)
