extends Node
class_name GiftVisualCache
## Optional observed gift art. Downloads only the local bridge, never CDN URLs.
## Failed artwork leaves the existing generic mechanic icon in place.

signal icon_ready(gift_id: String, texture: Texture2D)

const MAX_BYTES: int = 1048576
const MAX_TEXTURES: int = 64
const MAX_GIFT_IDS: int = 256
const MAX_PENDING: int = 64
const MAX_ATTEMPTS: int = 5
const MAX_SOURCE_DIMENSION: int = 4096
const MAX_TEXTURE_DIMENSION: int = 512

var _origin: String = ""
var _http: HTTPRequest = null
var _gift_paths: Dictionary = {}
var _gift_order: Array[String] = []
var _textures: Dictionary = {}
var _texture_order: Array[String] = []
var _pending: Array[Dictionary] = []
var _active: Dictionary = {}
var _clock: float = 0.0


func _ready() -> void:
	_origin = _local_origin(OS.get_environment("LIVE_BRIDGE_WS_URL"))
	_http = HTTPRequest.new()
	_http.timeout = 3.0
	_http.body_size_limit = MAX_BYTES
	_http.max_redirects = 0
	_http.accept_gzip = false
	_http.use_threads = true
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)


func _exit_tree() -> void:
	_pending.clear()
	_active.clear()
	if _http != null:
		_http.cancel_request()


func register_event(envelope: Dictionary) -> void:
	if str(envelope.get("event_type", "")) != "gift":
		return
	var payload: Dictionary = envelope.get("payload", {}) as Dictionary
	var gift_id: String = str(payload.get("gift_id", ""))
	var path: String = str(payload.get("gift_icon_path", ""))
	if gift_id.is_empty() or gift_id.length() > 64 or not _is_safe_path(path):
		return
	if not _gift_paths.has(gift_id):
		_gift_order.append(gift_id)
	_gift_paths[gift_id] = path
	while _gift_order.size() > MAX_GIFT_IDS:
		_gift_paths.erase(_gift_order.pop_front())
	var texture: Texture2D = get_icon(gift_id)
	if texture != null:
		icon_ready.emit(gift_id, texture)
		return
	if _origin.is_empty() or str(_active.get("path", "")) == path:
		return
	for request: Dictionary in _pending:
		if str(request.get("path", "")) == path:
			return
	if _pending.size() < MAX_PENDING:
		_pending.append({"path": path, "attempt": 0, "due": _clock})


func get_icon(gift_id: String) -> Texture2D:
	var path: String = str(_gift_paths.get(gift_id, ""))
	var texture: Texture2D = _textures.get(path) as Texture2D
	if texture != null:
		_texture_order.erase(path)
		_texture_order.append(path)
	return texture


func get_cache_stats() -> Dictionary:
	return {"textures": _textures.size(), "gift_ids": _gift_paths.size(),
		"pending": _pending.size(), "active": not _active.is_empty(), "origin": _origin}


func _process(delta: float) -> void:
	_clock += maxf(0.0, delta)
	if _http == null or not _active.is_empty() or _origin.is_empty():
		return
	for index: int in range(_pending.size()):
		if float(_pending[index].get("due", 0.0)) > _clock:
			continue
		_active = _pending[index]
		_pending.remove_at(index)
		_active["attempt"] = int(_active.get("attempt", 0)) + 1
		var error: Error = _http.request(_origin + str(_active["path"]), _request_headers())
		if error != OK:
			_retry_active()
		break


func _request_headers() -> PackedStringArray:
	var token: String = OS.get_environment("LIVE_BRIDGE_ENGINE_TOKEN").strip_edges()
	if token.is_empty() or token == "change_me_local_random_token":
		token = OS.get_environment("LIVE_BRIDGE_PRODUCER_TOKEN").strip_edges()
	if token.is_empty() or token == "change_me_local_random_token":
		token = OS.get_environment("LIVE_BRIDGE_LOCAL_TOKEN").strip_edges()
	if token.is_empty() or token == "change_me_local_random_token":
		return PackedStringArray()
	return PackedStringArray(["X-JOGI-Token: " + token])


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _active.is_empty():
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_retry_active()
		return
	var texture: Texture2D = _decode_image(body)
	if texture == null:
		_active.clear()
		return
	var path: String = str(_active["path"])
	_store_texture(path, texture)
	_active.clear()
	for gift_id: String in _gift_order:
		if str(_gift_paths.get(gift_id, "")) == path:
			icon_ready.emit(gift_id, texture)


func _retry_active() -> void:
	var attempts: int = int(_active.get("attempt", 0))
	if attempts < MAX_ATTEMPTS and _pending.size() < MAX_PENDING:
		_active["due"] = _clock + pow(2.0, float(attempts - 1)) * 0.5
		_pending.append(_active.duplicate())
	_active.clear()


func _store_texture(path: String, texture: Texture2D) -> void:
	_textures[path] = texture
	_texture_order.erase(path)
	_texture_order.append(path)
	while _texture_order.size() > MAX_TEXTURES:
		_textures.erase(_texture_order.pop_front())


func _decode_image(body: PackedByteArray) -> Texture2D:
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
	elif body.slice(8, 12).get_string_from_ascii() == "WEBP":
		error = decoded.load_webp_from_buffer(body)
	if error != OK or decoded.is_empty():
		return null
	var largest: int = maxi(decoded.get_width(), decoded.get_height())
	if largest > MAX_TEXTURE_DIMENSION:
		var scale_factor: float = float(MAX_TEXTURE_DIMENSION) / float(largest)
		decoded.resize(maxi(1, roundi(decoded.get_width() * scale_factor)), maxi(1, roundi(decoded.get_height() * scale_factor)), Image.INTERPOLATE_LANCZOS)
	decoded.generate_mipmaps()
	return ImageTexture.create_from_image(decoded)


func _image_dimensions(data: PackedByteArray) -> Vector2i:
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


func _big_endian(data: PackedByteArray, offset: int, count: int) -> int:
	var result: int = 0
	for index: int in range(offset, offset + count):
		result = (result << 8) + data[index]
	return result


func _is_safe_path(path: String) -> bool:
	if not path.begins_with("/gift-icons/") or path.length() != 76:
		return false
	for character: String in path.substr(12):
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _local_origin(websocket_url: String) -> String:
	var expression: RegEx = RegEx.new()
	expression.compile("^ws://(127\\.0\\.0\\.1|localhost):([0-9]{1,5})/ws/godot$")
	var match_result: RegExMatch = expression.search(websocket_url)
	if match_result == null:
		return ""
	var port: int = match_result.get_string(2).to_int()
	return "http://127.0.0.1:%d" % port if port >= 1 and port <= 65535 else ""
