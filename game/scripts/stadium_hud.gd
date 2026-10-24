class_name StadiumHUD
extends CanvasLayer
## Placar esportivo 1080 × 1920. O coordenador fornece todos os dados de corrida.
## As barras comparam metros percorridos ao líder; não representam chegada ou votos.

const ROUNDED_FONT: Font = preload("res://assets/fonts/nunito/Nunito-Variable.ttf")
const PORTRAITS: Array[Texture2D] = [preload("res://assets/portraits/lula.png"), preload("res://assets/portraits/flavio.png")]
const BLUE: Color = Color("005bff")
const NAVY: Color = Color("08246e")
const RED: Color = Color("ff244a")
const GREEN: Color = Color("00bd62")
const GOLD: Color = Color("ffdf00")
const WHITE: Color = Color("f9fcff")
const INK: Color = Color("041137")

var timer_label: Label = null
var round_label: Label = null
var cycle_label: Label = null
var mode_label: Label = null
var advantage_label: Label = null
var phase_label: Label = null
var lula_distance: Label = null
var flavio_distance: Label = null
var lula_speed: Label = null
var flavio_speed: Label = null
var lula_status: Label = null
var flavio_status: Label = null
var frame: Control = null
var _artwork: StadiumArtwork = null
var _event_root: Control = null
var _event_text: Label = null
var _event_style: StyleBoxFlat = null
var _event_tween: Tween = null
var _lula_badge: Control = null
var _flavio_badge: Control = null
var _lula_screen: Vector2 = Vector2(-1000.0, -1000.0)
var _flavio_screen: Vector2 = Vector2(-1000.0, -1000.0)
var _target_lula_ratio: float = 0.0
var _target_flavio_ratio: float = 0.0
var _elapsed: float = 0.0
var _ranking_names: Array[Label] = []
var _ranking_values: Array[Label] = []
var _audience_label: Label = null
var _audience_tween: Tween = null
var _rank_title: Label = null
var _podium_mode: bool = false
var _latest_ranking: Array[Dictionary] = []
var _goal_label: Label = null
var _goal_value: Label = null
var _followers_label: Label = null
var _goal_progress: ColorRect = null
var _goal_fill: ColorRect = null
var _headline_font: FontVariation = null
var _numeric_font: FontVariation = null
var _team_roots: Array[Control] = []
var _place_labels: Array[Label] = []
var _row_order: Array[int] = [1, 2]
var _chat_lines: Array[Label] = []
var _chat_entries: Array[Dictionary] = []
var _chat_last_time: float = -10.0
var _chat_names: Dictionary = {}
var _gift_images: Array[TextureRect] = []
var _gift_captions: Array[Label] = []
var _header_match: Label = null
var _chat_panel: Panel = null


class StadiumArtwork:
	extends Control
	var lula_ratio: float = 0.0
	var flavio_ratio: float = 0.0
	var lula_active: bool = false
	var flavio_active: bool = false
	var pulse: float = 0.0
	var lula_y: float = 370.0
	var flavio_y: float = 476.0
	var _styles: Dictionary = {}
	var gift_image_active: Array[bool] = [false, false, false, false]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE


	func _draw() -> void:
		# Cantos suaves e contraste uniforme, sem recortes angulares.
		_ribbon(Rect2(48.0, 180.0, 882.0, 124.0), Color("005bff"), 24.0)
		_ribbon(Rect2(707.0, 191.0, 209.0, 102.0), Color("041137"), 14.0)
		_ribbon(Rect2(48.0, 311.0, 882.0, 46.0), Color("08246e", 0.97), 14.0)
		_team_row(lula_y, Color("ff244a"), Color("700f2e"), lula_ratio, lula_active)
		_team_row(flavio_y, Color("00bd62"), Color("005c49"), flavio_ratio, flavio_active)
		_ribbon(Rect2(48.0, 584.0, 882.0, 48.0), Color("041137", 0.94), 18.0)
		# A base é contínua: quatro ações, sem moedas ou presentes presumidos.
		_ribbon(Rect2(48.0, 1610.0, 882.0, 102.0), Color("041137", 0.95), 22.0)
		for index: int in range(4):
			var center: Vector2 = Vector2(158.25 + float(index) * 220.5, 1642.0)
			if index > 0:
				draw_line(Vector2(center.x - 110.25, 1628.0), Vector2(center.x - 110.25, 1696.0), Color("254b8c"), 2.0)
			if not gift_image_active[index]:
				_icon(index, center)


	func _ribbon(rect: Rect2, color: Color, cut: float) -> void:
		var key: String = color.to_html() + "-" + str(cut)
		if not _styles.has(key):
			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.bg_color = color
			style.set_corner_radius_all(int(cut))
			style.anti_aliasing = true
			_styles[key] = style
		draw_style_box(_styles[key] as StyleBoxFlat, rect)


	func _team_row(y: float, color: Color, dark: Color, ratio: float, active: bool) -> void:
		_ribbon(Rect2(48.0, y, 882.0, 96.0), Color("08246e", 0.98), 20.0)
		_ribbon(Rect2(48.0, y, 351.0, 78.0), dark, 18.0)
		_ribbon(Rect2(53.0, y + 5.0, 59.0, 68.0), color, 16.0)
		draw_line(Vector2(400.0, y + 14.0), Vector2(400.0, y + 67.0), Color("315cb0"), 2.0)
		draw_line(Vector2(706.0, y + 14.0), Vector2(706.0, y + 67.0), Color("315cb0"), 2.0)
		draw_rect(Rect2(61.0, y + 83.0, 854.0, 6.0), Color("041137"))
		if ratio > 0.0:
			draw_rect(Rect2(61.0, y + 83.0, 854.0 * clampf(ratio, 0.0, 1.0), 6.0), color)
		if active:
			var alpha: float = 0.45 + 0.25 * sin(pulse * 5.0)
			draw_line(Vector2(412.0, y + 77.0), Vector2(905.0, y + 77.0), Color("ffdf00", alpha), 3.0)


	func _icon(index: int, center: Vector2) -> void:
		match index:
			0:
				draw_colored_polygon(PackedVector2Array([
					center + Vector2(1.0, -22.0), center + Vector2(-17.0, 3.0),
					center + Vector2(-2.0, 3.0), center + Vector2(-7.0, 22.0),
					center + Vector2(19.0, -7.0), center + Vector2(4.0, -7.0)
				]), Color("ffdf00"))
			1:
				var shield: PackedVector2Array = PackedVector2Array([
					center + Vector2(0.0, -21.0), center + Vector2(20.0, -12.0),
					center + Vector2(16.0, 9.0), center + Vector2(0.0, 23.0),
					center + Vector2(-16.0, 9.0), center + Vector2(-20.0, -12.0)
				])
				draw_colored_polygon(shield, Color("27ccff"))
				draw_line(center + Vector2(0.0, -12.0), center + Vector2(0.0, 12.0), Color("08246e"), 5.0)
			2:
				draw_colored_polygon(PackedVector2Array([
					center + Vector2(-21.0, 11.0), center + Vector2(13.0, -22.0),
					center + Vector2(23.0, -12.0), center + Vector2(-11.0, 21.0)
				]), Color("ff4b93"))
				draw_line(center + Vector2(-18.0, -10.0), center + Vector2(-7.0, 1.0), Color("ffdf00"), 5.0)
			3:
				var star: PackedVector2Array = PackedVector2Array()
				for point_index: int in range(10):
					var angle: float = -PI * 0.5 + float(point_index) * PI / 5.0
					var radius: float = 23.0 if point_index % 2 == 0 else 10.0
					star.append(center + Vector2(cos(angle), sin(angle)) * radius)
				draw_colored_polygon(star, Color("ffdf00"))
				draw_line(center + Vector2(-43.0, -7.0), center + Vector2(-29.0, -7.0), Color("ffdf00"), 3.0)
				draw_line(center + Vector2(-47.0, 5.0), center + Vector2(-29.0, 5.0), Color("ffdf00"), 3.0)


func _ready() -> void:
	_build()
	apply_state({})


func _build() -> void:
	_headline_font = FontVariation.new()
	_headline_font.base_font = ROUNDED_FONT
	var weight_axis: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	_headline_font.variation_opentype = {weight_axis: 900.0}
	_numeric_font = FontVariation.new()
	_numeric_font.base_font = ROUNDED_FONT
	_numeric_font.variation_opentype = {weight_axis: 800.0}
	frame = Control.new()
	frame.name = "StadiumSafeFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	_artwork = StadiumArtwork.new()
	_artwork.name = "ScoreboardArtwork"
	_artwork.size = Vector2(1080.0, 1920.0)
	frame.add_child(_artwork)
	_label("CORRIDA PRESIDENCIAL", Rect2(73.0, 189.0, 622.0, 46.0), 39, WHITE, true)
	_header_match = _label("LULA  vs  FLÁVIO", Rect2(74.0, 235.0, 615.0, 58.0), 48, GOLD, true)
	_header_match.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label = _label("10:00", Rect2(720.0, 196.0, 182.0, 77.0), 64, GOLD)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label("RESTANTE", Rect2(719.0, 267.0, 183.0, 26.0), 24, WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label = _label("RODADA 01 / 50", Rect2(65.0, 315.0, 274.0, 35.0), 27, WHITE)
	mode_label = _label("TESTE LOCAL", Rect2(336.0, 315.0, 231.0, 35.0), 24, Color("7ce7ff"))
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cycle_label = _label("C01 · VITÓRIAS 0×0", Rect2(576.0, 315.0, 334.0, 35.0), 25, GOLD)
	cycle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_build_team(1, 370.0)
	_build_team(2, 476.0)
	advantage_label = _label("DISPUTA EQUILIBRADA", Rect2(64.0, 588.0, 848.0, 38.0), 29, WHITE)
	advantage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label = _label("BRASÍLIA · ARENA NACIONAL", Rect2(65.0, 636.0, 844.0, 35.0), 24, WHITE)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Contornos permitem ler a localização sobre céu claro ou arquibancada.
	var mechanics: Array[String] = ["IMPULSO", "ESCUDO", "ATAQUE", "SUPER TURBO"]
	for index: int in range(mechanics.size()):
		var caption: Label = _label(mechanics[index], Rect2(48.0 + float(index) * 220.5, 1670.0, 220.5, 34.0), 25, WHITE)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_gift_captions.append(caption)
		var gift_image: TextureRect = TextureRect.new()
		gift_image.position = Vector2(131.25 + float(index) * 220.5, 1614.0)
		gift_image.size = Vector2(54.0, 54.0)
		gift_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gift_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gift_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gift_image.visible = false
		frame.add_child(gift_image)
		_gift_images.append(gift_image)
	_lula_badge = _make_runner_badge("13  LULA", RED, WHITE)
	_flavio_badge = _make_runner_badge("22  FLÁVIO", GOLD, INK)
	_build_audience_panel()
	_build_chat_panel()
	_build_goal_panel()
	_build_event_ribbon()


func _build_team(team: int, y: float) -> void:
	var first_child: int = frame.get_child_count()
	var is_lula: bool = team == 1
	var place: Label = _label("1º" if is_lula else "2º", Rect2(54.0, y + 13.0, 56.0, 52.0), 36, WHITE if is_lula else INK)
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place_labels.append(place)
	var number: Label = _label("13" if is_lula else "22", Rect2(114.0, y + 17.0, 49.0, 46.0), 27, WHITE if is_lula else GOLD)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = PORTRAITS[team - 1]
	atlas.region = Rect2(397, 12, 394, 410) if is_lula else Rect2(394, 20, 370, 420)
	var portrait: TextureRect = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.texture = atlas
	portrait.position = Vector2(167.0, y + 2.0)
	portrait.size = Vector2(65.0, 77.0)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(portrait)
	_label("LULA" if is_lula else "FLÁVIO", Rect2(238.0, y + 9.0, 159.0, 49.0), 35, WHITE if is_lula else GOLD, true)
	var status: Label = _label("TIME VERMELHO" if is_lula else "TIME BRASIL", Rect2(238.0, y + 51.0, 159.0, 29.0), 17, Color("d2e9ff"))
	var distance: Label = _label("0 m", Rect2(420.0, y + 10.0, 271.0, 57.0), 43, WHITE)
	distance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var speed: Label = _label("0,0", Rect2(721.0, y + 6.0, 190.0, 48.0), 39, WHITE)
	speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label("KM/H", Rect2(721.0, y + 51.0, 190.0, 28.0), 24, Color("a9d5ff")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_lula:
		lula_distance = distance
		lula_speed = speed
		lula_status = status
	else:
		flavio_distance = distance
		flavio_speed = speed
		flavio_status = status
	# Cada linha guarda a identidade inteira. Reordenar jamais troca os valores.
	var row: Control = Control.new()
	row.name = "Team%dRow" % team
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position.y = y
	var members: Array[Node] = []
	for index: int in range(first_child, frame.get_child_count()):
		members.append(frame.get_child(index))
	frame.add_child(row)
	for member: Node in members:
		var control: Control = member as Control
		control.reparent(row, false)
		control.position.y -= y
	_team_roots.append(row)


func _label(text: String, rect: Rect2, font_size: int, color: Color, headline: bool = false) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_override("font", _headline_font if headline else _numeric_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.set_meta("maximum_font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("041137", 0.86))
	label.add_theme_constant_override("outline_size", 4 if headline else 2)
	label.add_theme_color_override("font_shadow_color", Color("041137", 0.65))
	label.add_theme_constant_override("shadow_offset_y", 3)
	frame.add_child(label)
	return label


func _build_audience_panel() -> void:
	var panel: Panel = Panel.new()
	panel.position = Vector2(48, 1336)
	panel.size = Vector2(882, 258)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("041137", .94)
	style.border_color = Color("148dff")
	style.set_border_width_all(2)
	style.set_corner_radius_all(22)
	panel.add_theme_stylebox_override("panel", style)
	frame.add_child(panel)
	_audience_label = _label("COMENTE 13 OU 22 · ENTRE NA TORCIDA", Rect2(66, 1341, 846, 34), 28, GOLD)
	_audience_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_title = _label("TOP 5 · PRESENTES DA LIVE", Rect2(66, 1377, 846, 28), 22, Color("72d9ff"))
	_rank_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for index: int in range(5):
		var y: float = 1409.0 + float(index) * 35.0
		_ranking_names.append(_label("%d  —" % (index + 1), Rect2(80, y, 600, 34), 28, WHITE))
		var value: Label = _label("", Rect2(685, y, 214, 34), 26, GOLD)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_ranking_values.append(value)


func update_leaderboard(entries: Array[Dictionary]) -> void:
	_latest_ranking = entries.duplicate(true)
	for index: int in range(_ranking_names.size()):
		_ranking_names[index].visible = not _podium_mode or index < 3
		_ranking_values[index].visible = not _podium_mode or index < 3
		if index >= entries.size():
			_ranking_names[index].text = "%d  —" % (index + 1)
			_ranking_values[index].text = ""
			continue
		var entry: Dictionary = entries[index]
		var team: int = int(entry.get("team", 0))
		_ranking_names[index].text = "%d  %s" % [index + 1, _plain(str(entry.get("display_name", "Apoiador")), 20)]
		_ranking_names[index].add_theme_color_override("font_color", Color("ff7191") if team == 1 else (Color("73f6a9") if team == 2 else WHITE))
		_ranking_values[index].text = _count_text(maxi(0, int(entry.get("coins", 0)))) + " ◇"


func set_podium_mode(active: bool) -> void:
	if active == _podium_mode:
		return
	_podium_mode = active
	_rank_title.text = "PÓDIO · 3 MAIORES APOIADORES" if active else "TOP 5 · PRESENTES DA LIVE"
	update_leaderboard(_latest_ranking)


func _build_goal_panel() -> void:
	var background: Panel = Panel.new()
	var background_style: StyleBoxFlat = StyleBoxFlat.new()
	background_style.bg_color = Color("041137", .94)
	background_style.set_corner_radius_all(16)
	background.add_theme_stylebox_override("panel", background_style)
	background.position = Vector2(48, 122)
	background.size = Vector2(882, 53)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(background)
	_goal_label = _label("META DE CURTIDAS", Rect2(65, 125, 465, 40), 25, WHITE)
	_goal_value = _label("0 / 1.000", Rect2(523, 125, 202, 40), 27, GOLD)
	_goal_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_followers_label = _label("SEGUIDORES +0", Rect2(743, 125, 172, 40), 20, Color("72d9ff"))
	_followers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_goal_progress = ColorRect.new()
	_goal_progress.position = Vector2(65, 167)
	_goal_progress.size = Vector2(848, 5)
	_goal_progress.color = Color("24518d")
	_goal_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_goal_progress)
	_goal_fill = ColorRect.new()
	_goal_fill.color = GOLD
	_goal_fill.size = Vector2(0, 5)
	_goal_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goal_progress.add_child(_goal_fill)


func update_live_goal(goal: Dictionary, followers: int) -> void:
	_goal_label.text = _plain(str(goal.get("goal_label", "Meta de curtidas")), 30).to_upper()
	_goal_value.text = "%s / %s" % [_count_text(maxi(0, int(goal.get("value", 0)))), _count_text(maxi(1, int(goal.get("goal_target", 1000))))]
	_goal_fill.size.x = 848.0 * clampf(float(goal.get("progress", 0.0)), 0.0, 1.0)
	_followers_label.text = "SEGUIDORES +" + _count_text(maxi(0, followers))
	_fit_line(_goal_label, 18)
	_fit_line(_goal_value, 18)
	_fit_line(_followers_label, 16)


func _count_text(value: int) -> String:
	if value >= 1000000000:
		return ("%.1f bi" % (float(value) / 1000000000.0)).replace(".", ",")
	if value >= 1000000:
		return ("%.1f mi" % (float(value) / 1000000.0)).replace(".", ",")
	if value >= 10000:
		return ("%.1f mil" % (float(value) / 1000.0)).replace(".", ",")
	if value >= 1000:
		return "%d.%03d" % [value / 1000, value % 1000]
	return str(value)


func _fit_line(label: Label, minimum_size: int = 20) -> void:
	var font: Font = label.get_theme_font("font")
	var font_size: int = int(label.get_meta("maximum_font_size", 26))
	while font_size > minimum_size and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x - 6.0:
		font_size -= 1
	if label.get_theme_font_size("font_size") != font_size:
		label.add_theme_font_size_override("font_size", font_size)


func show_participation(participant: Dictionary) -> void:
	var team: int = int(participant.get("team", 0))
	var name_text: String = _plain(str(participant.get("display_name", "Espectador")), 24)
	var kind: String = str(participant.get("kind", "join"))
	if kind in ["join", "vote"]:
		_add_chat_entry(name_text, team)
	var action: String = "ENTROU NA TORCIDA" if bool(participant.get("joined", false)) else "NA TORCIDA"
	if kind == "share":
		action = "COMPARTILHOU A LIVE"
	elif kind == "like_batch":
		action = "MANDOU CURTIDAS"
	elif kind == "gift":
		action = "ENVIOU UM PRESENTE"
	elif kind == "follow":
		action = "COMEÇOU A SEGUIR"
	if _audience_tween != null and _audience_tween.is_valid():
		_audience_tween.kill()
	_audience_label.text = "%s · %s%s" % [name_text, action, (" · 13" if team == 1 else " · 22") if team > 0 else ""]
	_fit_line(_audience_label, 20)
	_audience_label.add_theme_color_override("font_color", Color("ff8daa") if team == 1 else (Color("7dffb3") if team == 2 else GOLD))
	_audience_tween = create_tween()
	_audience_tween.tween_interval(3.0)
	_audience_tween.tween_callback(_restore_audience_prompt)


func _restore_audience_prompt() -> void:
	_audience_label.text = "COMENTE 13 OU 22 · ENTRE NA TORCIDA"
	_fit_line(_audience_label, 20)
	_audience_label.add_theme_color_override("font_color", GOLD)


func _build_chat_panel() -> void:
	var panel: Panel = Panel.new()
	panel.name = "RecentSupporters"
	_chat_panel = panel
	panel.position = Vector2(48.0, 1727.0)
	panel.size = Vector2(882.0, 116.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("041137", 0.88)
	style.set_corner_radius_all(20)
	panel.add_theme_stylebox_override("panel", style)
	frame.add_child(panel)
	for index: int in range(3):
		var line: Label = _label("", Rect2(71.0, 1734.0 + float(index) * 34.0, 834.0, 34.0), 26, WHITE)
		_chat_lines.append(line)
	_refresh_chat()


func _add_chat_entry(display_name: String, team: int) -> void:
	if team not in [1, 2] or _elapsed - _chat_last_time < 0.65:
		return
	var key: String = display_name.to_lower()
	if _elapsed - float(_chat_names.get(key, -10.0)) < 2.0:
		return
	if _chat_names.size() >= 128 and not _chat_names.has(key):
		_chat_names.erase(_chat_names.keys()[0])
	_chat_names[key] = _elapsed
	_chat_last_time = _elapsed
	_chat_entries.push_front({"name": display_name, "team": team, "expires": _elapsed + 9.0})
	while _chat_entries.size() > 3:
		_chat_entries.pop_back()
	_refresh_chat()


func _expire_chat() -> void:
	var changed: bool = false
	while not _chat_entries.is_empty() and float(_chat_entries.back()["expires"]) <= _elapsed:
		_chat_entries.pop_back()
		changed = true
	if changed:
		_refresh_chat()


func _refresh_chat() -> void:
	_chat_panel.visible = not _chat_entries.is_empty()
	for index: int in range(_chat_lines.size()):
		var line: Label = _chat_lines[index]
		line.text = ""
		if index >= _chat_entries.size():
			continue
		var entry: Dictionary = _chat_entries[index]
		var team: int = int(entry["team"])
		line.text = "%s  ›  %s · %s" % ["13" if team == 1 else "22", str(entry["name"]), "LULA" if team == 1 else "FLÁVIO"]
		line.add_theme_color_override("font_color", Color("ff9caf") if team == 1 else Color("9affe1"))


func set_gift_legend(entries: Array[Dictionary]) -> void:
	var actions: Array[String] = ["boost", "shield", "attack", "super_turbo"]
	var defaults: Array[String] = ["IMPULSO", "ESCUDO", "ATAQUE", "SUPER TURBO"]
	for index: int in range(4):
		_gift_images[index].texture = null
		_gift_images[index].visible = false
		_gift_captions[index].text = defaults[index]
		_artwork.gift_image_active[index] = false
	for entry: Dictionary in entries.slice(0, 4):
		var index: int = actions.find(str(entry.get("action", "")))
		if index < 0:
			continue
		var value: Variant = entry.get("texture", null)
		if value is Texture2D:
			_gift_images[index].texture = value as Texture2D
			_gift_images[index].visible = true
			_artwork.gift_image_active[index] = true
		var title: String = _plain(str(entry.get("label", "")), 18)
		if not title.is_empty():
			_gift_captions[index].text = title
			_fit_line(_gift_captions[index], 18)
	if _artwork != null:
		_artwork.queue_redraw()


func get_display_order() -> Array[int]:
	return _row_order.duplicate()


func _update_row_order(lead: float) -> void:
	if not is_zero_approx(lead):
		_row_order.assign([1, 2] if lead > 0.0 else [2, 1])
	for index: int in range(_row_order.size()):
		var candidate_index: int = _row_order[index] - 1
		var y: float = 370.0 + float(index) * 106.0
		_team_roots[candidate_index].position.y = y
		_place_labels[candidate_index].text = "%dº" % (index + 1)
		if candidate_index == 0:
			_artwork.lula_y = y
		else:
			_artwork.flavio_y = y


func _make_runner_badge(text: String, color: Color, text_color: Color) -> Control:
	var panel: Panel = Panel.new()
	panel.size = Vector2(214.0, 48.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = INK
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	style.shadow_color = Color("041137", 0.5)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0.0, 3.0)
	panel.add_theme_stylebox_override("panel", style)
	frame.add_child(panel)
	var caption: Label = _label(text, Rect2(7.0, 0.0, 200.0, 46.0), 27, text_color)
	frame.remove_child(caption)
	panel.add_child(caption)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.visible = false
	return panel


func _build_event_ribbon() -> void:
	var panel: Panel = Panel.new()
	panel.position = Vector2(94.0, 744.0)
	panel.size = Vector2(790.0, 68.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_style = StyleBoxFlat.new()
	_event_style.bg_color = NAVY
	_event_style.border_color = GOLD
	_event_style.set_border_width_all(3)
	_event_style.set_corner_radius_all(20)
	_event_style.shadow_color = Color("041137", 0.5)
	_event_style.shadow_size = 10
	panel.add_theme_stylebox_override("panel", _event_style)
	frame.add_child(panel)
	_event_root = panel
	_event_text = _label("", Rect2(22.0, 2.0, 746.0, 62.0), 27, WHITE)
	frame.remove_child(_event_text)
	_event_root.add_child(_event_text)
	_event_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_text.max_lines_visible = 2
	_event_root.modulate.a = 0.0
	_event_root.visible = false


func _process(delta: float) -> void:
	if _artwork == null:
		return
	_elapsed += delta
	_expire_chat()
	var blend: float = 1.0 - exp(-10.0 * maxf(delta, 0.0))
	_artwork.lula_ratio = lerpf(_artwork.lula_ratio, _target_lula_ratio, blend)
	_artwork.flavio_ratio = lerpf(_artwork.flavio_ratio, _target_flavio_ratio, blend)
	_artwork.pulse = _elapsed
	_artwork.queue_redraw()
	_position_badge(_lula_badge, _lula_screen)
	_position_badge(_flavio_badge, _flavio_screen)


func _position_badge(badge: Control, screen_position: Vector2) -> void:
	badge.visible = screen_position.is_finite() and screen_position.x >= 100.0 and screen_position.x <= 920.0 and screen_position.y >= 730.0 and screen_position.y <= 1500.0
	if badge.visible:
		badge.position = Vector2(clampf(screen_position.x - badge.size.x * 0.5, 48.0, 930.0 - badge.size.x), screen_position.y - 64.0)


func apply_state(state: Dictionary) -> void:
	if timer_label == null:
		return
	var remaining: int = int(ceilf(_number(state.get("remaining", 600.0), 600.0, 359999.0)))
	timer_label.text = "%02d:%02d" % [remaining / 60, remaining % 60]
	round_label.text = "RODADA %02d / 50" % clampi(int(state.get("round", 1)), 1, 50)
	var wins: Array = state.get("wins", [0, 0]) if state.get("wins", [0, 0]) is Array else [0, 0]
	var left_wins: int = maxi(0, int(wins[0])) if wins.size() > 0 else 0
	var right_wins: int = maxi(0, int(wins[1])) if wins.size() > 1 else 0
	cycle_label.text = "C%02d · VITÓRIAS %d×%d" % [maxi(1, int(state.get("cycle", 1))), left_wins, right_wins]
	cycle_label.tooltip_text = "Ciclo %d" % maxi(1, int(state.get("cycle", 1)))
	mode_label.text = _plain(str(state.get("mode", "TESTE LOCAL")), 18).to_upper()
	var left_m: float = _number(state.get("lula_m", 0.0))
	var right_m: float = _number(state.get("flavio_m", 0.0))
	lula_distance.text = "%s m" % _distance(left_m)
	flavio_distance.text = "%s m" % _distance(right_m)
	# O contrato de velocidade é metros por segundo, como CandidateRunner.
	lula_speed.text = ("%.1f" % (_number(state.get("lula_speed", 0.0), 0.0, 1000.0) * 3.6)).replace(".", ",")
	flavio_speed.text = ("%.1f" % (_number(state.get("flavio_speed", 0.0), 0.0, 1000.0) * 3.6)).replace(".", ",")
	var lead: float = left_m - right_m
	_update_row_order(lead)
	advantage_label.text = "DISPUTA EQUILIBRADA" if absf(lead) < 0.5 else "%s NA FRENTE  +%s m" % ["LULA" if lead > 0.0 else "FLÁVIO", _distance(absf(lead))]
	advantage_label.add_theme_color_override("font_color", WHITE if absf(lead) < 0.5 else (Color("ff7190") if lead > 0.0 else GOLD))
	var reference_distance: float = maxf(maxf(left_m, right_m), 1.0)
	_target_lula_ratio = left_m / reference_distance
	_target_flavio_ratio = right_m / reference_distance
	_artwork.lula_active = bool(state.get("lula_boost", false))
	_artwork.flavio_active = bool(state.get("flavio_boost", false))
	lula_status.text = _status(state, "lula", "TIME VERMELHO")
	flavio_status.text = _status(state, "flavio", "TIME BRASIL")
	var phase: String = _plain(str(state.get("phase", "")), 46).to_upper()
	var round_name: String = _plain(str(state.get("round_name", "ARENA NACIONAL")), 32).to_upper()
	phase_label.text = phase if not phase.is_empty() else "BRASÍLIA · " + round_name
	if bool(state.get("round_finished", false)):
		var winning_slot: int = int(state.get("winner_id", 0))
		if winning_slot in [1, 13]:
			advantage_label.text = "13 VENCEU · LULA"
		elif winning_slot in [2, 22]:
			advantage_label.text = "22 VENCEU · FLÁVIO"
		else:
			advantage_label.text = "EMPATE NA RODADA"
		if state.has("next_round_in"):
			phase_label.text = "NOVA RODADA EM %02d s" % ceili(_number(state["next_round_in"], 0.0, 3600.0))
	var lula_screen_value: Variant = state.get("lula_screen", Vector2(-1000.0, -1000.0))
	var flavio_screen_value: Variant = state.get("flavio_screen", Vector2(-1000.0, -1000.0))
	_lula_screen = lula_screen_value if lula_screen_value is Vector2 else Vector2(-1000.0, -1000.0)
	_flavio_screen = flavio_screen_value if flavio_screen_value is Vector2 else Vector2(-1000.0, -1000.0)


func _status(state: Dictionary, prefix: String, fallback: String) -> String:
	if bool(state.get("round_finished", false)):
		return "FINALIZOU"
	if bool(state.get(prefix + "_stumble", false)):
		return "RECUPERANDO"
	if bool(state.get(prefix + "_shield", false)):
		return "ESCUDO ATIVO"
	if bool(state.get(prefix + "_boost", false)):
		return "TURBO ATIVO"
	return fallback


func show_event(text: String, team: int = 0, kind: String = "boost") -> void:
	if _event_root == null:
		return
	if _event_tween != null and _event_tween.is_valid():
		_event_tween.kill()
	_event_text.text = _plain(text, 64)
	_event_style.border_color = RED if team == 1 else (GREEN if team == 2 else GOLD)
	_event_style.bg_color = Color("650d37") if kind == "attack" else NAVY
	_event_root.visible = true
	_event_root.position.y = 731.0
	_event_root.modulate.a = 0.0
	_event_tween = create_tween()
	_event_tween.set_parallel(true)
	_event_tween.tween_property(_event_root, "modulate:a", 1.0, 0.18)
	_event_tween.tween_property(_event_root, "position:y", 744.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_event_tween.set_parallel(false)
	_event_tween.tween_interval(2.45)
	_event_tween.tween_property(_event_root, "modulate:a", 0.0, 0.35)
	_event_tween.tween_callback(_event_root.hide)


func _number(value: Variant, fallback: float = 0.0, maximum: float = 10000000.0) -> float:
	if not (value is float or value is int):
		return fallback
	var number: float = float(value)
	return clampf(number, 0.0, maximum) if is_finite(number) else fallback


func _distance(value: float) -> String:
	return ("%.0f" % value).replace(".", ",")


func _plain(value: String, limit: int) -> String:
	var clean: String = ""
	for character: String in value:
		var code: int = character.unicode_at(0)
		if code in [9, 10, 13]:
			clean += " "
		elif code >= 32 and not (code >= 127 and code <= 159) and code not in [0x061C, 0x200E, 0x200F, 0x2028, 0x2029, 0xFEFF] and not (code >= 0x202A and code <= 0x202F) and not (code >= 0x2060 and code <= 0x206F):
			clean += character
		if clean.length() >= limit:
			break
	return clean.strip_edges()
