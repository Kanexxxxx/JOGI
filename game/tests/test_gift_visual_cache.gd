extends SceneTree
## Local-only image origin, guarded decode, identity and texture budgets.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cache: GiftVisualCache = GiftVisualCache.new()
	root.add_child(cache)
	cache.set_process(false)
	var passed: bool = true
	passed = _check(cache._local_origin("ws://localhost:8766/ws/godot") == "http://127.0.0.1:8766", "Kwai local port preserved") and passed
	for url: String in ["wss://example.com/ws/godot", "ws://192.168.1.2:8765/ws/godot", "ws://127.0.0.1:8765/ws/godot?url=evil", "ws://127.0.0.1:0/ws/godot"]:
		passed = _check(cache._local_origin(url).is_empty(), "Reject non-local and invalid origin") and passed
	var path: String = "/gift-icons/" + "a".repeat(64)
	passed = _check(cache._is_safe_path(path) and not cache._is_safe_path("/gift-icons/../file") and not cache._is_safe_path("http://127.0.0.1:8765" + path), "Only exact opaque local image route accepted") and passed
	var image: Image = Image.create(1024, 512, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var texture: Texture2D = cache._decode_image(image.save_png_to_buffer())
	passed = _check(texture != null and texture.get_width() == 512 and texture.get_height() == 256, "Large valid PNG fits 512 pixels with preserved aspect") and passed
	for invalid: PackedByteArray in [PackedByteArray(), "<svg>fake</svg>".to_utf8_buffer(), "<html>fake</html>".to_utf8_buffer()]:
		passed = _check(cache._decode_image(invalid) == null, "Invalid and HTML/SVG payloads cannot become textures") and passed
	var huge_header: PackedByteArray = image.save_png_to_buffer()
	huge_header[16] = 127
	passed = _check(cache._decode_image(huge_header) == null, "Dimensions rejected before image allocation") and passed
	cache._origin = "http://127.0.0.1:8765"
	for index: int in range(1000):
		var key: String = ("%064x" % index)
		cache.register_event({"event_type": "gift", "payload": {"gift_id": str(index), "gift_icon_path": "/gift-icons/" + key}})
		cache._store_texture("/gift-icons/" + key, texture)
	var stats: Dictionary = cache.get_cache_stats()
	passed = _check(int(stats["textures"]) == 64 and int(stats["gift_ids"]) == 256 and int(stats["pending"]) == 64, "Thousand gifts keep all three cache budgets bounded") and passed
	passed = _check(cache.get_icon("999") == texture and cache.get_icon("0") == null, "Recent gift resolves and evicted identity has no retained texture") and passed
	root.remove_child(cache)
	cache.free()
	texture = null
	image = null
	await process_frame
	print("TEST_GIFT_VISUAL_CACHE_PASSED" if passed else "TEST_GIFT_VISUAL_CACHE_FAILED")
	quit(0 if passed else 1)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("FAIL: ", message)
	return condition
