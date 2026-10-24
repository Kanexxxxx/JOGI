extends Node
class_name AvatarVisualCache
## Ephemeral viewer avatar cache for transient HUD cards.
## Downloads ONLY opaque `/viewer-avatars/<sha256>` paths from the local 127.0.0.1 bridge,
## never external CDN URLs. Bounded LRU (64 textures, downscaled to <= 96px) with disable flag.

signal avatar_ready(avatar_path: String, texture: Texture2D)

const MAX_BYTES: int = 524288
const MAX_TEXTURES: int = 64
const MAX_PENDING: int = 32
const MAX_ATTEMPTS: int = 2
const MAX_SOURCE_DIMENSION: int = 2048
const MAX_TEXTURE_DIMENSION: int = 96

var enabled: bool = true
var _origin: String = ""
var _http: HTTPRequest = null
var _textures: Dictionary = {}
var _texture_order: Array[String] = []
var _pending: Array[Dictionary] = []
var _failed: Dictionary = {}
var _active: Dictionary = {}
var _clock: float = 0.0


func _ready() -> void:
	var raw_flag: String = OS.get_environment("LIVE_AVATARS_ENABLED").strip_edges().to_lower()
	enabled = not (raw_flag in ["0", "false", "no", "off"])
	_origin = _local_origin(OS.get_environment("LIVE_BRIDGE_WS_URL"))
	_http = HTTPRequest.new()
	_http.name = "AvatarLoopbackHttp"
	_http.timeout = 2.5
	_http.body_size_limit = MAX_BYTES
	_http.max_redirects = 0
	_http.accept_gzip = false
	_http.use_threads = true
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)


func _exit_tree() -> void:
	cancel_pending()
	_textures.clear()
	_texture_order.clear()
	_failed.clear()


func cancel_pending() -> void:
	_pending.clear()
	_active.clear()
	if _http != null:
		_http.cancel_request()


func get_avatar(avatar_path: String) -> Texture2D:
	if not enabled or not is_safe_avatar_path(avatar_path):
		return null
	var texture: Texture2D = _textures.get(avatar_path) as Texture2D
	if texture != null:
		_texture_order.erase(avatar_path)
		_texture_order.append(avatar_path)
	return texture


func request_avatar(avatar_path: String) -> Texture2D:
	if not enabled or not is_safe_avatar_path(avatar_path):
		return null
	var cached: Texture2D = get_avatar(avatar_path)
	if cached != null:
		return cached
	if _origin.is_empty():
		return null
	var retry_after: float = float(_failed.get(avatar_path, -1.0))
	if retry_after > _clock:
		return null
	if str(_active.get("path", "")) == avatar_path:
		return null
	for item: Dictionary in _pending:
		if str(item.get("path", "")) == avatar_path:
			return null
	if _pending.size() < MAX_PENDING:
		_pending.append({"path": avatar_path, "attempt": 0, "due": _clock})
	return null


func get_cache_stats() -> Dictionary:
	return {
		"enabled": enabled,
		"textures": _textures.size(),
		"pending": _pending.size(),
		"active": not _active.is_empty(),
		"origin": _origin
	}


func _process(delta: float) -> void:
	_clock += maxf(0.0, delta)
	if not enabled or _http == null or not _active.is_empty() or _origin.is_empty():
		return
	for index: int in range(_pending.size()):
		if float(_pending[index].get("due", 0.0)) > _clock:
			continue
		_active = _pending[index]
		_pending.remove_at(index)
		_active["attempt"] = int(_active.get("attempt", 0)) + 1
		var error: Error = _http.request(_origin + str(_active["path"]), _request_headers())
		if error != OK:
			_retry_or_fail_active()
		break


func _request_headers() -> PackedStringArray:
	var token: String = OS.get_environment("LIVE_BRIDGE_PRODUCER_TOKEN").strip_edges()
	if token.is_empty() or token == "change_me_local_random_token":
		token = OS.get_environment("LIVE_BRIDGE_LOCAL_TOKEN").strip_edges()
	if token.is_empty() or token == "change_me_local_random_token":
		return PackedStringArray()
	return PackedStringArray(["X-JOGI-Token: " + token])


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _active.is_empty():
		return
	var path: String = str(_active.get("path", ""))
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_retry_or_fail_active()
		return
	var texture: Texture2D = decode_avatar_buffer(body)
	if texture == null:
		_failed[path] = _clock + 60.0
		_prune_failed()
		_active.clear()
		return
	_store_texture(path, texture)
	_failed.erase(path)
	_active.clear()
	avatar_ready.emit(path, texture)


func _retry_or_fail_active() -> void:
	var path: String = str(_active.get("path", ""))
	var attempts: int = int(_active.get("attempt", 0))
	if attempts < MAX_ATTEMPTS and _pending.size() < MAX_PENDING:
		_active["due"] = _clock + 0.6 * float(attempts)
		_pending.append(_active.duplicate())
	else:
		_failed[path] = _clock + 45.0
		_prune_failed()
	_active.clear()


func _prune_failed() -> void:
	while _failed.size() > MAX_TEXTURES * 2:
		var first_key: Variant = _failed.keys()[0]
		_failed.erase(first_key)


func _store_texture(path: String, texture: Texture2D) -> void:
	_textures[path] = texture
	_texture_order.erase(path)
	_texture_order.append(path)
	while _texture_order.size() > MAX_TEXTURES:
		_textures.erase(_texture_order.pop_front())


static func decode_avatar_buffer(body: PackedByteArray) -> Texture2D:
	if body.size() < 24 or body.size() > MAX_BYTES:
		return null
	var dimensions: Vector2i = _image_dimensions(body)
	if dimensions.x <= 0 or dimensions.y <= 0 or dimensions.x > MAX_SOURCE_DIMENSION or dimensions.y > MAX_SOURCE_DIMENSION:
		return null
	var decoded: Image = Image.new()
	var error: Error = ERR_FILE_UNRECOGNIZED
	if body[0] == 137 and body[1] == 80:
		error = decoded.load_png_from_buffer(body)
	elif body[0] == 255 and body[1] == 216:
		error = decoded.load_jpg_from_buffer(body)
	elif body.size() >= 12 and body.slice(8, 12).get_string_from_ascii() == "WEBP":
		error = decoded.load_webp_from_buffer(body)
	if error != OK or decoded.is_empty():
		return null
	var largest: int = maxi(decoded.get_width(), decoded.get_height())
	if largest > MAX_TEXTURE_DIMENSION:
		var scale_factor: float = float(MAX_TEXTURE_DIMENSION) / float(largest)
		decoded.resize(
			maxi(1, roundi(float(decoded.get_width()) * scale_factor)),
			maxi(1, roundi(float(decoded.get_height()) * scale_factor)),
			Image.INTERPOLATE_LANCZOS
		)
	return ImageTexture.create_from_image(decoded)


static func _image_dimensions(data: PackedByteArray) -> Vector2i:
	if data.size() < 24:
		return Vector2i.ZERO
	if data.slice(0, 8) == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return Vector2i(_big_endian(data, 16, 4), _big_endian(data, 20, 4))
	if data[0] == 255 and data[1] == 216:
		var cursor: int = 2
		while cursor + 4 < data.size():
			if data[cursor] != 255:
				break
			var marker: int = data[cursor + 1]
			cursor += 2
			while marker == 255 and cursor < data.size():
				marker = data[cursor]
				cursor += 1
			if marker in [216, 217, 1] or (marker >= 208 and marker <= 215):
				continue
			if cursor + 2 > data.size():
				break
			var length: int = _big_endian(data, cursor, 2)
			if length < 2:
				break
			if marker in [192, 193, 194] and cursor + 7 <= data.size():
				return Vector2i(_big_endian(data, cursor + 5, 2), _big_endian(data, cursor + 3, 2))
			cursor += length
	if data.size() >= 30 and data.slice(0, 4).get_string_from_ascii() == "RIFF" and data.slice(8, 12).get_string_from_ascii() == "WEBP":
		var chunk: String = data.slice(12, 16).get_string_from_ascii()
		if chunk == "VP8X":
			return Vector2i(1 + data[24] + (data[25] << 8) + (data[26] << 16), 1 + data[27] + (data[28] << 8) + (data[29] << 16))
		if chunk == "VP8 ":
			return Vector2i((data[26] + (data[27] << 8)) & 16383, (data[28] + (data[29] << 8)) & 16383)
		if chunk == "VP8L" and data[20] == 47:
			var bits: int = data[21] + (data[22] << 8) + (data[23] << 16) + (data[24] << 24)
			return Vector2i(1 + (bits & 16383), 1 + ((bits >> 14) & 16383))
	return Vector2i.ZERO


static func _big_endian(data: PackedByteArray, offset: int, count: int) -> int:
	var result: int = 0
	for index: int in range(offset, offset + count):
		result = (result << 8) + data[index]
	return result


static func is_safe_avatar_path(path: String) -> bool:
	if not path.begins_with("/viewer-avatars/") or path.length() != 80:
		return false
	for character: String in path.substr(16):
		if not "0123456789abcdef".contains(character):
			return false
	return true


static func _local_origin(websocket_url: String) -> String:
	var expression: RegEx = RegEx.new()
	expression.compile("^ws://(127\\.0\\.0\\.1|localhost):([0-9]{1,5})/ws/godot$")
	var match_result: RegExMatch = expression.search(websocket_url)
	if match_result == null:
		return ""
	var port: int = match_result.get_string(2).to_int()
	return "http://127.0.0.1:%d" % port if port >= 1 and port <= 65535 else ""
