class_name StadiumHUD
extends CanvasLayer
## Placar esportivo simétrico 1080 × 1920 para TikTok Live e Kwai.
## Protagonismo para pista cobalto, corredores 13/22 e Palácio do Planalto (2027),
## com três metas independentes no topo, cards sociais enxutos e zonas seguras livres.

const ROUNDED_FONT: Font = preload("res://assets/fonts/nunito/Nunito-Variable.ttf")
const PORTRAITS: Array[Texture2D] = [preload("res://assets/portraits/lula.png"), preload("res://assets/portraits/flavio.png")]
const BLUE: Color = Color("005bff")
const NAVY: Color = Color("08246e")
const RED: Color = Color("ff244a")
const GREEN: Color = Color("00bd62")
const GOLD: Color = Color("ffdf00")
const WHITE: Color = Color("f9fcff")
const INK: Color = Color("041137")

const SAFE_LEFT: float = 42.0
const SAFE_RIGHT: float = 1038.0
const SAFE_WIDTH: float = 996.0
const INTERACTION_TTL_SECONDS: float = 6.4
const INTERACTION_FADE_SECONDS: float = 0.3
const MAX_INTERACTION_QUEUE: int = 64
const CHAT_TTL_SECONDS: float = 6.5

var _showcase_entries: Array[Dictionary] = []
var _showcase_textures: Dictionary = {}
var _showcase_panels: Array[Panel] = []
var _showcase_details: Array[Label] = []

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
var _experience_ended: bool = false
var _lula_badge: Control = null
var _flavio_badge: Control = null
var _lula_screen: Vector2 = Vector2(-1000.0, -1000.0)
var _flavio_screen: Vector2 = Vector2(-1000.0, -1000.0)
var _target_lula_ratio: float = 0.0
var _target_flavio_ratio: float = 0.0
var _elapsed: float = 0.0

var _ranking_panel: Panel = null
var _ranking_empty_label: Label = null
var _ranking_avatars: Array[TextureRect] = []
var _ranking_dots: Array[Panel] = []
var _ranking_names: Array[Label] = []
var _ranking_values: Array[Label] = []
var _audience_pill: Panel = null
var _audience_label: Label = null
var _audience_tween: Tween = null
var _rank_title: Label = null
var _podium_mode: bool = false
var _latest_ranking: Array[Dictionary] = []

# Contrato legado da meta primária + três metas independentes simultâneas
var _goal_label: Label = null
var _goal_value: Label = null
var _followers_label: Label = null
var _goal_progress: ColorRect = null
var _goal_fill: ColorRect = null
var _gifts_goal_title: Label = null
var _gifts_goal_value: Label = null
var _gifts_goal_progress: ColorRect = null
var _gifts_goal_fill: ColorRect = null
var _follows_goal_title: Label = null
var _follows_source_badge: Label = null
var _follows_goal_progress: ColorRect = null
var _follows_goal_fill: ColorRect = null

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
var _gift_subtitles: Array[Label] = []
var _header_match: Label = null
var _chat_panel: Panel = null

var _avatar_cache: AvatarVisualCache = null
var _gift_cache: GiftVisualCache = null
var _circle_shader: Shader = null
var _interaction_slots: Array[Dictionary] = []
var _interaction_entries: Array[Dictionary] = []
var _interaction_pending: Array[Dictionary] = []
var _interaction_overflow: int = 0


class StadiumArtwork:
	extends Control
	var lula_ratio: float = 0.0
	var flavio_ratio: float = 0.0
	var lula_active: bool = false
	var flavio_active: bool = false
	var pulse: float = 0.0
	var lula_y: float = 348.0
	var flavio_y: float = 442.0
	var leader_slot: int = 0
	var _styles: Dictionary = {}
	var gift_image_active: Array[bool] = [false, false, false, false]
	var abilities_visible: bool = true

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		# Três cards superiores independentes (Curtidas, Presentes, Seguidores 10K)
		var goal_borders: Array[Color] = [Color("ff4d79", 0.72), Color("b36bff", 0.72), Color("27ccff", 0.72)]
		for g_idx: int in range(3):
			var gx: float = 42.0 + float(g_idx) * 336.0
			_card(Rect2(gx, 108.0, 324.0, 76.0), Color("05143d", 0.90), goal_borders[g_idx], 18, 2)
		_draw_heart_icon(Vector2(68.0, 146.0))
		_draw_gift_icon(Vector2(404.0, 146.0))
		_draw_followers_icon(Vector2(740.0, 146.0))

		# Cabeçalho principal simétrico + cápsula do cronômetro + barra de metadados
		_card(Rect2(42.0, 192.0, 996.0, 102.0), Color("053cc2", 0.94), Color("4698ff", 0.75), 24, 2)
		_card(Rect2(786.0, 201.0, 238.0, 84.0), Color("041137", 0.96), Color("2a5fb8", 0.65), 16, 1)
		_card(Rect2(42.0, 300.0, 996.0, 40.0), Color("061c56", 0.94), Color("1e4fa3", 0.55), 14, 1)

		# Linhas reordenáveis dos dois candidatos
		_team_row(lula_y, Color("ff244a"), Color("650e2b", 0.95), lula_ratio, lula_active, leader_slot == 1)
		_team_row(flavio_y, Color("00bd62"), Color("044d3e", 0.95), flavio_ratio, flavio_active, leader_slot == 2)

		# Faixa enxuta de vantagem relativa
		_card(Rect2(42.0, 536.0, 996.0, 38.0), Color("041137", 0.90), Color("2457a7", 0.60), 16, 1)

		# Quatro cards inferiores arredondados de habilidades (zona 1720..1920 livre para TikTok/Kwai)
		var ability_borders: Array[Color] = [
			Color("ffd426", 0.75),
			Color("27ccff", 0.75),
			Color("ff4b7d", 0.75),
			Color("38bdf8", 0.80)
		]
		for index: int in range(4):
			if not abilities_visible:
				break
			var card_x: float = 42.0 + float(index) * 252.0
			_card(Rect2(card_x, 1606.0, 240.0, 112.0), Color("051338", 0.92), ability_borders[index], 20, 2)
			var icon_center: Vector2 = Vector2(card_x + 120.0, 1636.0)
			if not gift_image_active[index]:
				_ability_icon(index, icon_center)

	func _card(rect: Rect2, bg: Color, border: Color, radius: int, border_w: int) -> void:
		var key: String = "%s-%s-%d-%d" % [bg.to_html(), border.to_html(), radius, border_w]
		if not _styles.has(key):
			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.bg_color = bg
			style.border_color = border
			style.set_border_width_all(border_w)
			style.set_corner_radius_all(radius)
			style.anti_aliasing = true
			_styles[key] = style
		draw_style_box(_styles[key] as StyleBoxFlat, rect)

	func _ribbon(rect: Rect2, color: Color, cut: float) -> void:
		_card(rect, color, Color.TRANSPARENT, int(cut), 0)

	func _team_row(y: float, accent: Color, identity_bg: Color, ratio: float, active: bool, is_leader: bool) -> void:
		_card(Rect2(42.0, y, 996.0, 86.0), Color("071f5e", 0.95), accent if is_leader else Color("24529e", 0.70), 20, 2)
		_ribbon(Rect2(46.0, y + 4.0, 418.0, 78.0), identity_bg, 16.0)
		_ribbon(Rect2(114.0, y + 19.0, 54.0, 46.0), accent, 12.0)
		draw_line(Vector2(470.0, y + 14.0), Vector2(470.0, y + 72.0), Color("2e59a8", 0.8), 2.0)
		draw_line(Vector2(808.0, y + 14.0), Vector2(808.0, y + 72.0), Color("2e59a8", 0.8), 2.0)
		_ribbon(Rect2(496.0, y + 60.0, 288.0, 11.0), Color("041137", 0.95), 5.0)
		if ratio > 0.0:
			var fill_w: float = maxf(10.0, 288.0 * clampf(ratio, 0.0, 1.0))
			_ribbon(Rect2(496.0, y + 60.0, fill_w, 11.0), accent, 5.0)
		if is_leader:
			var cx: float = 80.0
			var cy: float = y + 14.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx - 11.0, cy + 5.0),
				Vector2(cx - 13.0, cy - 5.0),
				Vector2(cx - 5.0, cy - 1.0),
				Vector2(cx, cy - 8.0),
				Vector2(cx + 5.0, cy - 1.0),
				Vector2(cx + 13.0, cy - 5.0),
				Vector2(cx + 11.0, cy + 5.0)
			]), Color("ffdf00"))
		if active:
			var alpha: float = 0.45 + 0.30 * sin(pulse * 5.0)
			draw_line(Vector2(496.0, y + 76.0), Vector2(784.0, y + 76.0), Color("ffdf00", alpha), 3.0)

	func _draw_heart_icon(c: Vector2) -> void:
		draw_circle(c + Vector2(-7.0, -5.0), 8.5, Color("ff4d79"))
		draw_circle(c + Vector2(7.0, -5.0), 8.5, Color("ff4d79"))
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-15.0, -2.0),
			c + Vector2(15.0, -2.0),
			c + Vector2(0.0, 15.0)
		]), Color("ff4d79"))

	func _draw_gift_icon(c: Vector2) -> void:
		_ribbon(Rect2(c.x - 14.0, c.y - 5.0, 28.0, 20.0), Color("a855f7"), 5.0)
		_ribbon(Rect2(c.x - 16.0, c.y - 12.0, 32.0, 8.0), Color("c084fc"), 4.0)
		draw_rect(Rect2(c.x - 3.0, c.y - 12.0, 6.0, 27.0), Color("ffdf00"))
		draw_circle(c + Vector2(-5.0, -15.0), 4.5, Color("ffdf00"))
		draw_circle(c + Vector2(5.0, -15.0), 4.5, Color("ffdf00"))

	func _draw_followers_icon(c: Vector2) -> void:
		draw_circle(c + Vector2(-4.0, -8.0), 7.5, Color("27ccff"))
		_ribbon(Rect2(c.x - 16.0, c.y + 1.0, 24.0, 13.0), Color("27ccff"), 6.0)
		draw_line(c + Vector2(12.0, -5.0), c + Vector2(12.0, 5.0), Color("7ef3ff"), 3.0)
		draw_line(c + Vector2(7.0, 0.0), c + Vector2(17.0, 0.0), Color("7ef3ff"), 3.0)

	func _ability_icon(index: int, center: Vector2) -> void:
		match index:
			0:
				draw_colored_polygon(PackedVector2Array([
					center + Vector2(2.0, -19.0), center + Vector2(-14.0, 2.0),
					center + Vector2(-2.0, 2.0), center + Vector2(-6.0, 19.0),
					center + Vector2(16.0, -5.0), center + Vector2(3.0, -5.0)
				]), Color("ffdf00"))
			1:
				var shield: PackedVector2Array = PackedVector2Array([
					center + Vector2(0.0, -18.0), center + Vector2(17.0, -10.0),
					center + Vector2(14.0, 8.0), center + Vector2(0.0, 20.0),
					center + Vector2(-14.0, 8.0), center + Vector2(-17.0, -10.0)
				])
				draw_colored_polygon(shield, Color("27ccff"))
				draw_line(center + Vector2(0.0, -10.0), center + Vector2(0.0, 10.0), Color("041137"), 4.0)
			2:
				draw_colored_polygon(PackedVector2Array([
					center + Vector2(-17.0, 10.0), center + Vector2(11.0, -18.0),
					center + Vector2(19.0, -10.0), center + Vector2(-9.0, 18.0)
				]), Color("ff4b7d"))
				draw_line(center + Vector2(-15.0, -8.0), center + Vector2(-5.0, 2.0), Color("ffdf00"), 4.0)
			3:
				var star: PackedVector2Array = PackedVector2Array()
				for point_index: int in range(10):
					var angle: float = -PI * 0.5 + float(point_index) * PI / 5.0
					var radius: float = 19.5 if point_index % 2 == 0 else 8.5
					star.append(center + Vector2(cos(angle), sin(angle)) * radius)
				draw_colored_polygon(star, Color("ffdf00"))


func _ready() -> void:
	_build()
	apply_state({})


func set_avatar_cache(cache: AvatarVisualCache) -> void:
	_avatar_cache = cache
	_refresh_interaction_cards()
	update_leaderboard(_latest_ranking)


func set_gift_cache(cache: GiftVisualCache) -> void:
	_gift_cache = cache
	_refresh_interaction_cards()


func on_avatar_ready(_avatar_path: String, _texture: Texture2D) -> void:
	_refresh_interaction_cards()
	update_leaderboard(_latest_ranking)


func on_gift_icon_ready(_gift_id: String, _texture: Texture2D) -> void:
	_refresh_interaction_cards()


func _build() -> void:
	_headline_font = FontVariation.new()
	_headline_font.base_font = ROUNDED_FONT
	var weight_axis: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	_headline_font.variation_opentype = {weight_axis: 900.0}
	_numeric_font = FontVariation.new()
	_numeric_font.base_font = ROUNDED_FONT
	_numeric_font.variation_opentype = {weight_axis: 800.0}

	_circle_shader = Shader.new()
	_circle_shader.code = """shader_type canvas_item;
uniform vec4 ring_color : source_color = vec4(1.0, 0.87, 0.0, 1.0);
uniform float ring_width : hint_range(0.0, 0.2) = 0.075;
uniform vec4 circle_uv_region = vec4(0.0, 0.0, 1.0, 1.0);
void fragment() {
	// AtlasTexture supplies UV in the full source image, not the cropped face.
	vec2 local_uv = (UV - circle_uv_region.xy) / circle_uv_region.zw;
	vec2 p = local_uv - vec2(0.5);
	float dist = length(p) * 2.0;
	float outer_alpha = 1.0 - smoothstep(0.95, 1.0, dist);
	float inner_mix = smoothstep(1.0 - ring_width * 2.0 - 0.03, 1.0 - ring_width * 2.0, dist);
	vec4 tex = texture(TEXTURE, UV);
	vec3 rgb = mix(tex.rgb, ring_color.rgb, inner_mix);
	COLOR = vec4(rgb, outer_alpha * mix(tex.a, ring_color.a, inner_mix));
}
"""

	frame = Control.new()
	frame.name = "StadiumSafeFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(frame)

	_artwork = StadiumArtwork.new()
	_artwork.name = "ScoreboardArtwork"
	_artwork.size = Vector2(1080.0, 1920.0)
	frame.add_child(_artwork)

	_build_goal_panel()

	var main_title: Label = _label("CORRIDA PRESIDENCIAL", Rect2(64.0, 198.0, 704.0, 42.0), 35, WHITE, true)
	main_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_match = _label("LULA 13  vs  FLÁVIO 22", Rect2(64.0, 238.0, 704.0, 50.0), 42, GOLD, true)
	_header_match.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	timer_label = _label("10:00", Rect2(792.0, 203.0, 226.0, 54.0), 52, GOLD)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var timer_sub: Label = _label("RESTANTE", Rect2(792.0, 256.0, 226.0, 24.0), 18, WHITE)
	timer_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	round_label = _label("RODADA 01 / 50", Rect2(60.0, 303.0, 290.0, 34.0), 23, WHITE)
	mode_label = _label("JOGO FICTÍCIO · IA", Rect2(358.0, 303.0, 320.0, 34.0), 21, Color("7ce7ff"))
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cycle_label = _label("C01 · VITÓRIAS 0×0", Rect2(686.0, 303.0, 336.0, 34.0), 22, GOLD)
	cycle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_build_team(1, 348.0)
	_build_team(2, 442.0)

	advantage_label = _label("DISPUTA EQUILIBRADA", Rect2(60.0, 538.0, 960.0, 34.0), 25, WHITE)
	advantage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label = _label("BRASÍLIA · ARENA NACIONAL", Rect2(60.0, 575.0, 960.0, 30.0), 21, WHITE)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var mechanics: Array[String] = ["IMPULSO", "ESCUDO", "ATAQUE", "SUPER TURBO"]
	var subtitles: Array[String] = ["+ VELOCIDADE", "BLOQUEIA ATAQUE", "ATRAPALHA RIVAL", "MÁX. VELOCIDADE"]
	var sub_colors: Array[Color] = [Color("ffe57f"), Color("8be9ff"), Color("ff94b2"), Color("93e6ff")]
	for index: int in range(mechanics.size()):
		var card_x: float = 42.0 + float(index) * 252.0
		var showcase_panel: Panel = Panel.new()
		showcase_panel.name = "GiftShowcase%d" % index
		showcase_panel.position = Vector2(card_x, 1607.0)
		showcase_panel.size = Vector2(240.0, 112.0)
		showcase_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var showcase_style: StyleBoxFlat = StyleBoxFlat.new()
		showcase_style.bg_color = Color("061332", .97)
		showcase_style.border_color = sub_colors[index]
		showcase_style.set_border_width_all(2)
		showcase_style.set_corner_radius_all(20)
		showcase_panel.add_theme_stylebox_override("panel", showcase_style)
		frame.add_child(showcase_panel)
		_showcase_panels.append(showcase_panel)
		var caption: Label = _label(mechanics[index], Rect2(card_x + 8.0, 1654.0, 224.0, 24.0), 23, WHITE, true)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_fit_line(caption, 15)
		_gift_captions.append(caption)
		var sub_lbl: Label = _label(subtitles[index], Rect2(card_x + 8.0, 1677.0, 224.0, 20.0), 15, sub_colors[index])
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_fit_line(sub_lbl, 11)
		_gift_subtitles.append(sub_lbl)
		var gift_image: TextureRect = TextureRect.new()
		gift_image.position = Vector2(card_x + 98.0, 1610.0)
		gift_image.size = Vector2(44.0, 44.0)
		gift_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gift_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gift_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gift_image.visible = false
		frame.add_child(gift_image)
		_gift_images.append(gift_image)
		var metadata_label: Label = _label("CATÁLOGO NÃO CONFIRMADO", Rect2(card_x + 8.0, 1697.0, 224.0, 20.0), 14, sub_colors[index])
		metadata_label.size = Vector2(224.0, 20.0)
		metadata_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_fit_line(metadata_label, 11)
		_showcase_details.append(metadata_label)
	var team_instruction: Label = _label("COMENTE 13 OU 22 ANTES DE ENVIAR PRESENTES", Rect2(SAFE_LEFT, 1570.0, 484.0, 30.0), 17, WHITE, true)
	team_instruction.name = "GiftTeamInstruction"
	team_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fit_line(team_instruction, 13)

	_lula_badge = _make_runner_badge("13  LULA", RED, WHITE)
	_flavio_badge = _make_runner_badge("22  FLÁVIO", GOLD, INK)
	_build_social_and_ranking_panels()
	_build_chat_panel()
	_build_event_ribbon()


func _make_circle_material(ring_color: Color, ring_width: float = 0.075) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _circle_shader
	mat.set_shader_parameter("ring_color", ring_color)
	mat.set_shader_parameter("ring_width", ring_width)
	return mat


func _build_team(team: int, y: float) -> void:
	var first_child: int = frame.get_child_count()
	var is_lula: bool = team == 1
	var place: Label = _label("1º" if is_lula else "2º", Rect2(50.0, y + 18.0, 60.0, 52.0), 34, WHITE)
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place_labels.append(place)
	var number: Label = _label("13" if is_lula else "22", Rect2(114.0, y + 19.0, 54.0, 46.0), 26, WHITE if is_lula else INK, true)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = PORTRAITS[team - 1]
	atlas.region = Rect2(397, 12, 394, 394) if is_lula else Rect2(394, 20, 370, 370)
	var portrait: TextureRect = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.texture = atlas
	portrait.position = Vector2(176.0, y + 9.0)
	portrait.size = Vector2(68.0, 68.0)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var portrait_material: ShaderMaterial = _make_circle_material(RED if is_lula else GOLD, 0.08)
	var atlas_size: Vector2 = atlas.atlas.get_size()
	portrait_material.set_shader_parameter("circle_uv_region", Vector4(
		atlas.region.position.x / atlas_size.x, atlas.region.position.y / atlas_size.y,
		atlas.region.size.x / atlas_size.x, atlas.region.size.y / atlas_size.y))
	portrait.material = portrait_material
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(portrait)
	var cand_name: Label = _label("LULA" if is_lula else "FLÁVIO", Rect2(254.0, y + 8.0, 204.0, 42.0), 33, WHITE if is_lula else GOLD, true)
	_fit_line(cand_name, 22)
	var status: Label = _label("TIME VERMELHO" if is_lula else "TIME BRASIL", Rect2(254.0, y + 46.0, 208.0, 28.0), 17, Color("d2e9ff"))
	_fit_line(status, 13)
	var distance: Label = _label("0 m", Rect2(482.0, y + 6.0, 316.0, 50.0), 40, WHITE)
	distance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var speed: Label = _label("0,0", Rect2(816.0, y + 6.0, 208.0, 44.0), 36, WHITE)
	speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var kmh: Label = _label("KM/H", Rect2(816.0, y + 47.0, 208.0, 26.0), 20, Color("a9d5ff"))
	kmh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_lula:
		lula_distance = distance
		lula_speed = speed
		lula_status = status
	else:
		flavio_distance = distance
		flavio_speed = speed
		flavio_status = status
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


func _label(text: String, rect: Rect2, font_size: int, color: Color, headline: bool = false, parent: Control = null) -> Label:
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
	label.add_theme_color_override("font_outline_color", Color("041137", 0.88))
	label.add_theme_constant_override("outline_size", 4 if headline else 2)
	label.add_theme_color_override("font_shadow_color", Color("041137", 0.60))
	label.add_theme_constant_override("shadow_offset_y", 2)
	var host: Control = parent if parent != null else frame
	host.add_child(label)
	return label


func _build_goal_panel() -> void:
	# Card 1: Curtidas (também expõe _goal_label, _goal_value, _goal_progress, _goal_fill para testes legados)
	_goal_label = _label("META DE CURTIDAS", Rect2(92.0, 113.0, 262.0, 26.0), 17, WHITE, true)
	_fit_line(_goal_label, 12)
	_goal_progress = ColorRect.new()
	_goal_progress.position = Vector2(92.0, 141.0)
	_goal_progress.size = Vector2(260.0, 8.0)
	_goal_progress.color = Color("223d72")
	_goal_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_goal_progress)
	_goal_fill = ColorRect.new()
	_goal_fill.color = Color("ff4d79")
	_goal_fill.size = Vector2(0.0, 8.0)
	_goal_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goal_progress.add_child(_goal_fill)
	_goal_value = _label("0 / 1.000", Rect2(92.0, 151.0, 260.0, 26.0), 18, GOLD)
	_goal_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fit_line(_goal_value, 12)

	# Card 2: Presentes / Moedas / Presente específico
	_gifts_goal_title = _label("META DE PRESENTES", Rect2(428.0, 113.0, 262.0, 26.0), 17, WHITE, true)
	_fit_line(_gifts_goal_title, 12)
	_gifts_goal_progress = ColorRect.new()
	_gifts_goal_progress.position = Vector2(428.0, 141.0)
	_gifts_goal_progress.size = Vector2(260.0, 8.0)
	_gifts_goal_progress.color = Color("282566")
	_gifts_goal_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_gifts_goal_progress)
	_gifts_goal_fill = ColorRect.new()
	_gifts_goal_fill.color = Color("b36bff")
	_gifts_goal_fill.size = Vector2(0.0, 8.0)
	_gifts_goal_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gifts_goal_progress.add_child(_gifts_goal_fill)
	_gifts_goal_value = _label("0 / 500 un.", Rect2(428.0, 151.0, 260.0, 26.0), 18, GOLD)
	_gifts_goal_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fit_line(_gifts_goal_value, 12)

	# Card 3: Seguidores (alvo 10.000 com fonte honesta: sessão vs baseline manual)
	_follows_goal_title = _label("META 10K SEGUIDORES", Rect2(764.0, 113.0, 262.0, 26.0), 17, WHITE, true)
	_fit_line(_follows_goal_title, 12)
	_follows_goal_progress = ColorRect.new()
	_follows_goal_progress.position = Vector2(764.0, 141.0)
	_follows_goal_progress.size = Vector2(260.0, 8.0)
	_follows_goal_progress.color = Color("16406f")
	_follows_goal_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_follows_goal_progress)
	_follows_goal_fill = ColorRect.new()
	_follows_goal_fill.color = Color("27ccff")
	_follows_goal_fill.size = Vector2(0.0, 8.0)
	_follows_goal_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_follows_goal_progress.add_child(_follows_goal_fill)
	_followers_label = _label("SEGUIDORES +0", Rect2(764.0, 151.0, 154.0, 26.0), 14, Color("7ef3ff"))
	_fit_line(_followers_label, 10)
	_follows_source_badge = _label("ALVO 10 MIL", Rect2(920.0, 151.0, 106.0, 26.0), 14, GOLD)
	_follows_source_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fit_line(_follows_source_badge, 10)


func update_live_goal(goal: Dictionary, followers: int) -> void:
	_goal_label.text = ellipsize_utf8(str(goal.get("goal_label", "Meta de curtidas")).to_upper(), _headline_font, 17, _goal_label.size.x - 4.0)
	_goal_value.text = "%s / %s" % [_count_text(maxi(0, int(goal.get("value", 0)))), _count_text(maxi(1, int(goal.get("goal_target", 1000))))]
	_goal_fill.size.x = 260.0 * clampf(float(goal.get("progress", 0.0)), 0.0, 1.0)
	_followers_label.text = "SEGUIDORES +" + _count_text(maxi(0, followers))
	_fit_line(_goal_label, 12)
	_fit_line(_goal_value, 12)
	_fit_line(_followers_label, 10)


func update_live_goals(goals: Dictionary, followers: int = 0) -> void:
	if goals.get("likes") is Dictionary:
		var likes_goal: Dictionary = goals["likes"] as Dictionary
		_goal_label.text = ellipsize_utf8(str(likes_goal.get("goal_label", "Meta de curtidas")).to_upper(), _headline_font, 17, _goal_label.size.x - 4.0)
		_goal_value.text = "%s / %s" % [_count_text(maxi(0, int(likes_goal.get("value", 0)))), _count_text(maxi(1, int(likes_goal.get("goal_target", 1000))))]
		_goal_fill.size.x = 260.0 * clampf(float(likes_goal.get("progress", 0.0)), 0.0, 1.0)
		_fit_line(_goal_label, 12)
		_fit_line(_goal_value, 12)

	if goals.get("gifts") is Dictionary:
		var gifts_goal: Dictionary = goals["gifts"] as Dictionary
		var g_kind: String = str(gifts_goal.get("goal_kind", "gifts"))
		var suffix: String = " ◇" if g_kind == "coins" else " un."
		_gifts_goal_title.text = ellipsize_utf8(str(gifts_goal.get("goal_label", "Meta de presentes")).to_upper(), _headline_font, 17, _gifts_goal_title.size.x - 4.0)
		_gifts_goal_value.text = "%s / %s%s" % [
			_count_text(maxi(0, int(gifts_goal.get("value", 0)))),
			_count_text(maxi(1, int(gifts_goal.get("goal_target", 500)))),
			suffix
		]
		_gifts_goal_fill.size.x = 260.0 * clampf(float(gifts_goal.get("progress", 0.0)), 0.0, 1.0)
		_fit_line(_gifts_goal_title, 12)
		_fit_line(_gifts_goal_value, 12)

	var session_follows: int = maxi(0, followers)
	if goals.get("follows") is Dictionary:
		var follows_goal: Dictionary = goals["follows"] as Dictionary
		session_follows = maxi(session_follows, int(follows_goal.get("session_follows", session_follows)))
		var target_f: int = maxi(1, int(follows_goal.get("goal_target", 10000)))
		var source_mode: String = str(follows_goal.get("source_mode", "session_only"))
		_follows_goal_title.text = ellipsize_utf8(str(follows_goal.get("goal_label", "Meta de seguidores")).to_upper(), _headline_font, 17, _follows_goal_title.size.x - 4.0)
		_follows_goal_fill.size.x = 260.0 * clampf(float(follows_goal.get("progress", 0.0)), 0.0, 1.0)
		_followers_label.text = "SEGUIDORES +" + _count_text(session_follows)
		if source_mode == "manual_baseline" and follows_goal.get("follower_baseline", null) != null:
			_follows_source_badge.text = "%s / %s" % [_count_text(maxi(0, int(follows_goal.get("value", 0)))), _count_text(target_f)]
		else:
			# Sem total verificado do perfil pela plataforma, jamais exibir "0 / 10.000" como total real.
			_follows_source_badge.text = "ALVO " + _count_text(target_f).to_upper()
		_fit_line(_follows_goal_title, 12)
		_fit_line(_followers_label, 10)
		_fit_line(_follows_source_badge, 10)


func _build_social_and_ranking_panels() -> void:
	# Coluna esquerda (x=42..526): 2 cards transitórios de interação com avatar circular + pílula discreta de chamada
	_audience_pill = Panel.new()
	_audience_pill.name = "AudienceCalloutPill"
	_audience_pill.position = Vector2(42.0, 1448.0)
	_audience_pill.size = Vector2(484.0, 42.0)
	_audience_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_style: StyleBoxFlat = StyleBoxFlat.new()
	pill_style.bg_color = Color("041137", 0.84)
	pill_style.border_color = Color("1f5db8", 0.72)
	pill_style.set_border_width_all(1)
	pill_style.set_corner_radius_all(16)
	_audience_pill.add_theme_stylebox_override("panel", pill_style)
	frame.add_child(_audience_pill)
	_audience_label = _label("COMENTE 13 OU 22 · ENTRE NA TORCIDA", Rect2(14.0, 4.0, 456.0, 34.0), 19, GOLD, false, _audience_pill)
	_audience_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fit_line(_audience_label, 13)

	for slot_idx: int in range(2):
		var card: Panel = Panel.new()
		card.name = "ViewerInteractionCard%d" % slot_idx
		card.position = Vector2(42.0, 1352.0 + float(slot_idx) * 70.0)
		card.size = Vector2(484.0, 64.0)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.z_index = 12
		card.visible = false
		var c_style: StyleBoxFlat = StyleBoxFlat.new()
		c_style.bg_color = Color("051338", 0.92)
		c_style.border_color = Color("2c6be0", 0.78)
		c_style.set_border_width_all(2)
		c_style.set_corner_radius_all(18)
		card.add_theme_stylebox_override("panel", c_style)
		frame.add_child(card)

		var mono_panel: Panel = Panel.new()
		mono_panel.position = Vector2(10.0, 9.0)
		mono_panel.size = Vector2(46.0, 46.0)
		mono_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mono_style: StyleBoxFlat = StyleBoxFlat.new()
		mono_style.bg_color = Color("0c2d73")
		mono_style.border_color = Color("38bdf8")
		mono_style.set_border_width_all(2)
		mono_style.set_corner_radius_all(23)
		mono_panel.add_theme_stylebox_override("panel", mono_style)
		card.add_child(mono_panel)
		var mono_lbl: Label = _label("", Rect2(0.0, 0.0, 46.0, 46.0), 21, WHITE, true, mono_panel)
		mono_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		var avatar_rect: TextureRect = TextureRect.new()
		avatar_rect.position = Vector2(10.0, 9.0)
		avatar_rect.size = Vector2(46.0, 46.0)
		avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		avatar_rect.material = _make_circle_material(Color("38bdf8"), 0.08)
		avatar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avatar_rect.visible = false
		card.add_child(avatar_rect)

		var name_lbl: Label = _label("", Rect2(66.0, 7.0, 306.0, 26.0), 19, WHITE, true, card)
		var action_lbl: Label = _label("", Rect2(66.0, 32.0, 306.0, 24.0), 16, Color("b8dcff"), false, card)

		var gift_thumb: TextureRect = TextureRect.new()
		gift_thumb.position = Vector2(378.0, 13.0)
		gift_thumb.size = Vector2(38.0, 38.0)
		gift_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gift_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gift_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gift_thumb.visible = false
		card.add_child(gift_thumb)

		var team_chip: Panel = Panel.new()
		team_chip.position = Vector2(424.0, 17.0)
		team_chip.size = Vector2(48.0, 30.0)
		team_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		team_chip.visible = false
		var chip_style: StyleBoxFlat = StyleBoxFlat.new()
		chip_style.bg_color = RED
		chip_style.set_corner_radius_all(10)
		team_chip.add_theme_stylebox_override("panel", chip_style)
		card.add_child(team_chip)
		var chip_lbl: Label = _label("", Rect2(0.0, 0.0, 48.0, 30.0), 18, WHITE, true, team_chip)
		chip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		_interaction_slots.append({
			"panel": card,
			"style": c_style,
			"mono_panel": mono_panel,
			"mono_style": mono_style,
			"mono_label": mono_lbl,
			"avatar": avatar_rect,
			"name_label": name_lbl,
			"action_label": action_lbl,
			"gift_thumb": gift_thumb,
			"team_chip": team_chip,
			"chip_style": chip_style,
			"chip_label": chip_lbl
		})

	# Coluna direita (x=546..1038): TOP 5 · MOEDAS compacto (colapsa quando vazio, sem 5 travessões fixos)
	_ranking_panel = Panel.new()
	_ranking_panel.name = "TopSupportersPanel"
	_ranking_panel.position = Vector2(546.0, 1522.0)
	_ranking_panel.size = Vector2(492.0, 72.0)
	_ranking_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r_style: StyleBoxFlat = StyleBoxFlat.new()
	r_style.bg_color = Color("041137", 0.92)
	r_style.border_color = Color("ffcf26", 0.68)
	r_style.set_border_width_all(2)
	r_style.set_corner_radius_all(20)
	_ranking_panel.add_theme_stylebox_override("panel", r_style)
	frame.add_child(_ranking_panel)

	_rank_title = _label("TOP 5 · MOEDAS", Rect2(18.0, 8.0, 456.0, 28.0), 20, GOLD, true, _ranking_panel)
	_rank_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ranking_empty_label = _label("Presentes com moedas entram no ranking", Rect2(18.0, 36.0, 456.0, 26.0), 16, Color("99c4ff"), false, _ranking_panel)
	_ranking_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fit_line(_ranking_empty_label, 12)

	for index: int in range(5):
		var row_y: float = 40.0 + float(index) * 36.0
		var dot: Panel = Panel.new()
		dot.position = Vector2(18.0, row_y + 5.0)
		dot.size = Vector2(26.0, 26.0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.visible = false
		var dot_style: StyleBoxFlat = StyleBoxFlat.new()
		dot_style.bg_color = Color("173a7a")
		dot_style.set_corner_radius_all(13)
		dot.add_theme_stylebox_override("panel", dot_style)
		_ranking_panel.add_child(dot)
		_ranking_dots.append(dot)

		var sup_avatar: TextureRect = TextureRect.new()
		sup_avatar.position = Vector2(18.0, row_y + 5.0)
		sup_avatar.size = Vector2(26.0, 26.0)
		sup_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sup_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		sup_avatar.material = _make_circle_material(GOLD, 0.09)
		sup_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sup_avatar.visible = false
		_ranking_panel.add_child(sup_avatar)
		_ranking_avatars.append(sup_avatar)

		var r_name: Label = _label("", Rect2(52.0, row_y, 286.0, 34.0), 20, WHITE, false, _ranking_panel)
		r_name.visible = false
		_ranking_names.append(r_name)

		var r_value: Label = _label("", Rect2(342.0, row_y, 134.0, 34.0), 20, GOLD, false, _ranking_panel)
		r_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r_value.visible = false
		_ranking_values.append(r_value)

	update_leaderboard([])


func update_leaderboard(entries: Array[Dictionary]) -> void:
	_ranking_empty_label.text = "Sem presentes registrados nesta sessão" if _experience_ended else "Presentes com moedas entram no ranking"
	_latest_ranking = entries.duplicate(true)
	var max_rows: int = 3 if _podium_mode else 5
	var visible_rows: int = mini(entries.size(), max_rows)
	if visible_rows == 0:
		_ranking_panel.size = Vector2(492.0, 72.0)
		_ranking_panel.position = Vector2(546.0, 1522.0)
		_ranking_empty_label.visible = true
	else:
		var panel_h: float = 48.0 + float(visible_rows) * 36.0
		_ranking_panel.size = Vector2(492.0, panel_h)
		_ranking_panel.position = Vector2(546.0, 1594.0 - panel_h)
		_ranking_empty_label.visible = false

	for index: int in range(_ranking_names.size()):
		var show_row: bool = index < visible_rows
		_ranking_names[index].visible = show_row
		_ranking_values[index].visible = show_row
		_ranking_dots[index].visible = false
		_ranking_avatars[index].visible = false
		if not show_row:
			_ranking_names[index].text = ""
			_ranking_values[index].text = ""
			continue
		var entry: Dictionary = entries[index]
		var team: int = int(entry.get("team", 0))
		var raw_name: String = str(entry.get("display_name", "Apoiador"))
		var team_tag: String = " · 13" if team == 1 else (" · 22" if team == 2 else "")
		var prefix: String = "%d. " % (index + 1)
		var fitted_name: String = ellipsize_utf8(prefix + raw_name + team_tag, _numeric_font, 20, _ranking_names[index].size.x - 4.0)
		_ranking_names[index].text = fitted_name
		_ranking_names[index].add_theme_color_override("font_color", Color("ff8aa3") if team == 1 else (Color("7ef5b5") if team == 2 else WHITE))
		_ranking_values[index].text = _count_text(maxi(0, int(entry.get("coins", 0)))) + " ◇"
		_fit_line(_ranking_values[index], 14)

		var avatar_path: String = str(entry.get("avatar_icon_path", ""))
		var tex: Texture2D = _avatar_cache.get_avatar_by_path(avatar_path) if (_avatar_cache != null and not avatar_path.is_empty()) else null
		if tex != null:
			_ranking_avatars[index].texture = tex
			_ranking_avatars[index].visible = true
		else:
			var dot_style: StyleBoxFlat = _ranking_dots[index].get_theme_stylebox("panel") as StyleBoxFlat
			dot_style.bg_color = RED if team == 1 else (GREEN if team == 2 else Color("275399"))
			_ranking_dots[index].visible = true


func set_podium_mode(active: bool) -> void:
	if active == _podium_mode:
		return
	_podium_mode = active
	_rank_title.text = "PÓDIO · TOP 3 MOEDAS" if active else "TOP 5 · MOEDAS"
	_fit_line(_rank_title, 15)
	update_leaderboard(_latest_ranking)


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


func _fit_line(label: Label, minimum_size: int = 16) -> void:
	var font: Font = label.get_theme_font("font")
	var font_size: int = int(label.get_meta("maximum_font_size", 24))
	var max_w: float = maxf(24.0, label.size.x - 6.0)
	while font_size > minimum_size and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_w:
		font_size -= 1
	if label.get_theme_font_size("font_size") != font_size:
		label.add_theme_font_size_override("font_size", font_size)


func show_participation(participant: Dictionary) -> void:
	if _experience_ended:
		return
	var team: int = int(participant.get("team", 0))
	var raw_display_name: String = _sanitize_single_line(str(participant.get("display_name", "Espectador")))
	if raw_display_name.is_empty():
		raw_display_name = "Espectador"
	var name_plain: String = _plain(raw_display_name, 24)
	var kind: String = str(participant.get("kind", "join"))
	if kind in ["join", "vote"]:
		_add_chat_entry(name_plain, team)

	var action: String = "entrou na torcida" if bool(participant.get("joined", false)) else "apoiou na torcida"
	if kind == "vote":
		action = "comentou %s" % ("13" if team == 1 else ("22" if team == 2 else "voto"))
	elif kind == "share":
		action = "compartilhou a live"
	elif kind == "like_batch":
		var likes_amt: int = maxi(1, int(participant.get("amount", 1)))
		action = "mandou +%s curtidas" % _count_text(likes_amt)
	elif kind == "gift":
		var g_qty: int = maxi(1, int(participant.get("gift_quantity", 1)))
		var g_name: String = _sanitize_single_line(str(participant.get("gift_name", "")))
		if g_name.is_empty():
			g_name = "Presente"
		action = "%s ×%s" % [g_name, _count_text(g_qty)]
		var status: String = str(participant.get("effect_status", "unconfirmed"))
		var abilities: Dictionary = {"gift_t1_turbo":"IMPULSO", "gift_t2_shield_or_obstacle":"ESCUDO", "gift_t2_shield":"ESCUDO", "gift_t3_attack":"ATAQUE", "gift_t4_super_rally":"SUPER TURBO"}
		var action_id: String = str(participant.get("action_id", ""))
		if status == "applied":
			action += " · " + str(abilities.get(action_id, "EFEITO")) + " " + ("13" if team == 1 else "22")
			if action_id == "gift_t3_attack":
				action += " → " + ("22" if team == 1 else "13")
			_highlight_showcase(action_id)
		elif status == "reserved":
			action += " · PRÓXIMA RODADA"
		elif team == 0 or status == "neutral":
			action += " · SEM EQUIPE: 13 OU 22"
		elif status == "unknown_value":
			action += " · VALOR NÃO INFORMADO"
		else:
			action += " · RECEBIDO, SEM EFEITO CONFIRMADO"
	elif kind == "follow":
		action = "começou a seguir"

	_push_interaction_card(participant, raw_display_name, kind, team, action)

	if _audience_tween != null and _audience_tween.is_valid():
		_audience_tween.kill()
	var banner_line: String = "%s · %s%s" % [
		name_plain,
		action.to_upper(),
		(" · 13" if team == 1 else " · 22") if team in [1, 2] else ""
	]
	_audience_label.text = ellipsize_utf8(banner_line, _numeric_font, 19, _audience_label.size.x - 6.0)
	_fit_line(_audience_label, 13)
	_audience_label.add_theme_color_override("font_color", Color("ff8daa") if team == 1 else (Color("7dffb3") if team == 2 else GOLD))
	_audience_tween = create_tween()
	_audience_tween.tween_interval(3.0)
	_audience_tween.tween_callback(_restore_audience_prompt)


func _push_interaction_card(participant: Dictionary, clean_name: String, kind: String, team: int, action: String) -> void:
	var identity: String = str(participant.get("identity", ""))
	var gift_id: String = str(participant.get("gift_id", ""))
	var avatar_path: String = str(participant.get("avatar_icon_path", ""))
	var qty: int = maxi(1, int(participant.get("gift_quantity", 1)))
	# Combina deltas sucessivos do mesmo combo pago na mesma identidade sem duplicar cards.
	if kind == "gift" and not identity.is_empty():
		for existing: Dictionary in _interaction_entries + _interaction_pending:
			if str(existing.get("identity", "")) == identity and str(existing.get("kind", "")) == "gift" and str(existing.get("gift_id", "")) == gift_id and int(existing.get("team", 0)) == team:
				var total_qty: int = int(existing.get("gift_quantity", 1)) + qty
				existing["gift_quantity"] = total_qty
				var g_name: String = _sanitize_single_line(str(participant.get("gift_name", "")))
				if g_name.is_empty():
					g_name = "Presente"
				var previous_action: String = str(existing.get("action", ""))
				var effect_at: int = previous_action.find(" · ")
				var effect_note: String = previous_action.substr(effect_at) if effect_at >= 0 else ""
				existing["action"] = "%s ×%s" % [g_name, _count_text(total_qty)] + effect_note
				existing["display_name"] = clean_name
				existing["expires"] = _elapsed + INTERACTION_TTL_SECONDS
				if not avatar_path.is_empty():
					existing["avatar_icon_path"] = avatar_path
				_refresh_interaction_cards()
				return

	# Keep the two readable cards stable; a burst waits instead of replacing them.
	# Repeated choices aggregate only presentation, never game votes or effects.
	for existing: Dictionary in _interaction_entries + _interaction_pending:
		if kind != "gift" and not identity.is_empty() and str(existing.get("identity", "")) == identity and str(existing.get("kind", "")) == kind and int(existing.get("team", 0)) == team:
			var repetitions: int = int(existing.get("repetitions", 1)) + 1
			existing["repetitions"] = repetitions
			existing["action"] = action + " ×" + str(repetitions)
			_refresh_interaction_cards()
			return
	var entry: Dictionary = {
		"identity": identity, "display_name": clean_name, "kind": kind,
		"team": team if team in [1, 2] else 0, "action": action,
		"gift_id": gift_id, "gift_quantity": qty, "avatar_icon_path": avatar_path,
		"created": _elapsed, "expires": _elapsed + INTERACTION_TTL_SECONDS
	}
	if _interaction_entries.size() < 2:
		_interaction_entries.push_front(entry)
	else:
		if _interaction_pending.size() >= MAX_INTERACTION_QUEUE:
			# A new paid acknowledgement can displace a free visual notification.
			# Neither path alters the accepted-event ledger or race effects.
			var displaced: bool = false
			if kind == "gift":
				for pending_index: int in range(_interaction_pending.size() - 1, -1, -1):
					if str(_interaction_pending[pending_index].get("kind", "")) != "gift":
						_interaction_pending.remove_at(pending_index)
						displaced = true
						break
			_interaction_overflow += 1
			if not displaced:
				return
		if kind == "gift":
			_interaction_pending.push_front(entry)
		else:
			_interaction_pending.append(entry)
	_refresh_interaction_cards()


func _expire_interactions() -> void:
	var changed: bool = false
	# Combo updates can extend an older card without moving its position. Expiry
	# is therefore independent of insertion order; inspect both fixed slots.
	for index: int in range(_interaction_entries.size() - 1, -1, -1):
		if float(_interaction_entries[index]["expires"]) <= _elapsed:
			_interaction_entries.remove_at(index)
			changed = true
	while _interaction_entries.size() < 2 and not _interaction_pending.is_empty():
		var next_entry: Dictionary = _interaction_pending.pop_front()
		next_entry["created"] = _elapsed
		next_entry["expires"] = _elapsed + INTERACTION_TTL_SECONDS
		_interaction_entries.append(next_entry)
		changed = true
	if changed:
		_refresh_interaction_cards()
	_animate_interaction_cards()


func _animate_interaction_cards() -> void:
	for index: int in range(mini(_interaction_entries.size(), _interaction_slots.size())):
		var entry: Dictionary = _interaction_entries[index]
		var panel: Control = _interaction_slots[index]["panel"] as Control
		var age: float = maxf(0.0, _elapsed - float(entry["created"]))
		var remaining: float = maxf(0.0, float(entry["expires"]) - _elapsed)
		var fade: float = minf(clampf(age / INTERACTION_FADE_SECONDS, 0.0, 1.0), clampf(remaining / INTERACTION_FADE_SECONDS, 0.0, 1.0))
		panel.modulate.a = fade
		panel.position.x = SAFE_LEFT + 22.0 * (1.0 - fade)


func _refresh_interaction_cards() -> void:
	if _audience_pill != null:
		_audience_pill.visible = _interaction_entries.is_empty()
	for idx: int in range(_interaction_slots.size()):
		var slot: Dictionary = _interaction_slots[idx]
		(slot["panel"] as Control).position.y = (1430.0 if _event_root != null and _event_root.visible else 1352.0) + float(idx) * 70.0
		var panel: Panel = slot["panel"] as Panel
		var name_lbl: Label = slot["name_label"] as Label
		var action_lbl: Label = slot["action_label"] as Label
		var mono_lbl: Label = slot["mono_label"] as Label
		var chip_lbl: Label = slot["chip_label"] as Label
		var avatar_rect: TextureRect = slot["avatar"] as TextureRect
		var mono_panel: Panel = slot["mono_panel"] as Panel
		var gift_thumb: TextureRect = slot["gift_thumb"] as TextureRect
		var team_chip: Panel = slot["team_chip"] as Panel
		if idx >= _interaction_entries.size():
			panel.visible = false
			name_lbl.text = ""
			action_lbl.text = ""
			mono_lbl.text = ""
			chip_lbl.text = ""
			avatar_rect.visible = false
			gift_thumb.visible = false
			team_chip.visible = false
			continue

		var entry: Dictionary = _interaction_entries[idx]
		var team: int = int(entry.get("team", 0))
		var style: StyleBoxFlat = slot["style"] as StyleBoxFlat
		style.border_color = Color("ff4d6d", 0.82) if team == 1 else (Color("2ae88a", 0.82) if team == 2 else Color("38bdf8", 0.78))

		var has_gift_thumb: bool = false
		var gift_id: String = str(entry.get("gift_id", ""))
		if str(entry.get("kind", "")) == "gift" and _gift_cache != null and not gift_id.is_empty():
			var g_tex: Texture2D = _gift_cache.get_icon(gift_id)
			if g_tex != null:
				gift_thumb.texture = g_tex
				gift_thumb.visible = true
				has_gift_thumb = true
		if not has_gift_thumb:
			gift_thumb.texture = null
			gift_thumb.visible = false

		# Chip de equipe APENAS quando há escolha explícita (13 ou 22). Follow/gift neutro fica sem time.
		if team in [1, 2]:
			var chip_style: StyleBoxFlat = slot["chip_style"] as StyleBoxFlat
			chip_style.bg_color = RED if team == 1 else GOLD
			chip_lbl.text = "13" if team == 1 else "22"
			chip_lbl.add_theme_color_override("font_color", WHITE if team == 1 else INK)
			team_chip.visible = true
		else:
			chip_lbl.text = ""
			team_chip.visible = false

		var text_right_edge: float = 372.0 if has_gift_thumb else (416.0 if team in [1, 2] else 468.0)
		var avail_w: float = maxf(140.0, text_right_edge - 66.0)
		name_lbl.size.x = avail_w
		action_lbl.size.x = avail_w

		var handle_raw: String = str(entry.get("display_name", "Espectador"))
		if not handle_raw.begins_with("@"):
			handle_raw = "@" + handle_raw
		name_lbl.text = ellipsize_utf8(handle_raw, _headline_font, 19, avail_w - 4.0)
		action_lbl.text = ellipsize_utf8(str(entry.get("action", "")), _numeric_font, 16, avail_w - 4.0)

		var avatar_path: String = str(entry.get("avatar_icon_path", ""))
		var av_tex: Texture2D = _avatar_cache.get_avatar_by_path(avatar_path) if (_avatar_cache != null and not avatar_path.is_empty()) else null
		if av_tex != null:
			avatar_rect.texture = av_tex
			(avatar_rect.material as ShaderMaterial).set_shader_parameter(
				"ring_color",
				RED if team == 1 else (GOLD if team == 2 else Color("38bdf8"))
			)
			avatar_rect.visible = true
			mono_panel.visible = false
			mono_lbl.text = ""
		else:
			avatar_rect.texture = null
			avatar_rect.visible = false
			var mono_style: StyleBoxFlat = slot["mono_style"] as StyleBoxFlat
			mono_style.border_color = RED if team == 1 else (GOLD if team == 2 else Color("38bdf8"))
			mono_lbl.text = _initial_grapheme(str(entry.get("display_name", "E")))
			mono_panel.visible = true

		panel.visible = true
	if _chat_panel != null:
		_refresh_chat()


func get_interaction_diagnostics() -> Dictionary:
	return {"visible": _interaction_entries.size(), "queued": _interaction_pending.size(),
		"overflow_visual_only": _interaction_overflow, "ttl_seconds": INTERACTION_TTL_SECONDS}


func _restore_audience_prompt() -> void:
	_audience_label.text = "OBRIGADO PELA PARTICIPAÇÃO" if _experience_ended else "COMENTE 13 OU 22 · ENTRE NA TORCIDA"
	_fit_line(_audience_label, 13)
	_audience_label.add_theme_color_override("font_color", GOLD)


func _build_chat_panel() -> void:
	var panel: Panel = Panel.new()
	panel.name = "RecentSupporters"
	_chat_panel = panel
	panel.position = Vector2(42.0, 1496.0)
	panel.size = Vector2(484.0, 98.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("041137", 0.88)
	style.border_color = Color("1f4f9c", 0.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	panel.add_theme_stylebox_override("panel", style)
	frame.add_child(panel)
	for index: int in range(3):
		var line: Label = _label("", Rect2(58.0, 1502.0 + float(index) * 28.0, 452.0, 28.0), 18, WHITE)
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
	_chat_entries.push_front({"name": display_name, "team": team, "expires": _elapsed + CHAT_TTL_SECONDS})
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
	_chat_panel.visible = not _chat_entries.is_empty() and _interaction_entries.is_empty() and (_event_root == null or not _event_root.visible)
	for index: int in range(_chat_lines.size()):
		var line: Label = _chat_lines[index]
		line.text = ""
		if index >= _chat_entries.size():
			continue
		var entry: Dictionary = _chat_entries[index]
		var team: int = int(entry["team"])
		var raw_line: String = "%s  ›  %s · %s" % ["13" if team == 1 else "22", str(entry["name"]), "LULA" if team == 1 else "FLÁVIO"]
		line.text = ellipsize_utf8(raw_line, _numeric_font, 18, line.size.x - 4.0)
		line.add_theme_color_override("font_color", Color("ff9caf") if team == 1 else Color("9affe1"))


func set_gift_showcase(entries: Array[Dictionary]) -> void:
	_showcase_entries = entries.duplicate(true)
	_apply_gift_showcase()


func _apply_gift_showcase() -> void:
	var actions: Array[String] = ["boost", "shield", "attack", "super_turbo"]
	for entry: Dictionary in _showcase_entries:
		var index: int = actions.find(str(entry.get("action", "")))
		if index < 0 or index >= _gift_images.size():
			continue
		var name_text: String = _plain(str(entry.get("gift_name", "Presente")), 24)
		var verified: bool = bool(entry.get("verified", false))
		var coins: int = int(entry.get("unit_coin_value", 0)) if entry.get("unit_coin_value") != null else 0
		_gift_subtitles[index].text = name_text
		_fit_line(_gift_subtitles[index], 12)
		_showcase_details[index].text = ("%s %s" % [_count_text(coins), "moeda" if coins == 1 else "moedas"]) if verified and coins > 0 else "VALOR NÃO CONFIRMADO"
		var resource_path: String = str(entry.get("image_resource", ""))
		if not resource_path.begins_with("res://assets/gifts/tiktok/"):
			continue
		var cache_key: String = resource_path + str(entry.get("image_region", []))
		if _showcase_textures.has(cache_key):
			_gift_images[index].texture = _showcase_textures[cache_key] as Texture2D
			_gift_images[index].visible = true
			_artwork.gift_image_active[index] = true
			continue
		var source: Image = Image.load_from_file(ProjectSettings.globalize_path(resource_path))
		if source == null or source.is_empty():
			continue
		var texture: Texture2D = ImageTexture.create_from_image(source)
		var region: Array = entry.get("image_region", []) as Array
		if region.size() == 4:
			var atlas: AtlasTexture = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
			texture = atlas
		_showcase_textures[cache_key] = texture
		_gift_images[index].texture = texture
		_gift_images[index].visible = true
		_artwork.gift_image_active[index] = true


func _highlight_showcase(action_id: String) -> void:
	var index: int = ["gift_t1_turbo", "gift_t2_shield_or_obstacle", "gift_t3_attack", "gift_t4_super_rally"].find(action_id)
	if index < 0 or index >= _showcase_panels.size():
		return
	var panel: Panel = _showcase_panels[index]
	panel.modulate = Color(1.8, 1.8, 1.2)
	var flash: Tween = create_tween()
	flash.tween_property(panel, "modulate", Color.WHITE, 1.2)


func set_gift_legend(entries: Array[Dictionary]) -> void:
	if _experience_ended:
		return
	var actions: Array[String] = ["boost", "shield", "attack", "super_turbo"]
	var defaults: Array[String] = ["IMPULSO", "ESCUDO", "ATAQUE", "SUPER TURBO"]
	for index: int in range(4):
		_gift_images[index].texture = null
		_gift_images[index].visible = false
		_gift_captions[index].text = defaults[index]
		_fit_line(_gift_captions[index], 15)
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
			_gift_captions[index].text = ellipsize_utf8(title, _headline_font, 23, _gift_captions[index].size.x - 4.0)
			_fit_line(_gift_captions[index], 15)
	_apply_gift_showcase()
	if _artwork != null:
		_artwork.queue_redraw()


func get_display_order() -> Array[int]:
	return _row_order.duplicate()


func _update_row_order(lead: float) -> void:
	if not is_zero_approx(lead):
		_row_order.assign([1, 2] if lead > 0.0 else [2, 1])
	_artwork.leader_slot = 0 if absf(lead) < 0.5 else (1 if lead > 0.0 else 2)
	for index: int in range(_row_order.size()):
		var candidate_index: int = _row_order[index] - 1
		var y: float = 348.0 + float(index) * 94.0
		_team_roots[candidate_index].position.y = y
		_place_labels[candidate_index].text = "%dº" % (index + 1)
		if candidate_index == 0:
			_artwork.lula_y = y
		else:
			_artwork.flavio_y = y


func _make_runner_badge(text: String, color: Color, text_color: Color) -> Control:
	var panel: Panel = Panel.new()
	panel.size = Vector2(204.0, 44.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = INK
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	style.shadow_color = Color("041137", 0.45)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0.0, 2.0)
	panel.add_theme_stylebox_override("panel", style)
	frame.add_child(panel)
	var caption: Label = _label(text, Rect2(6.0, 0.0, 192.0, 42.0), 25, text_color, true, panel)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.visible = false
	return panel


func _build_event_ribbon() -> void:
	var panel: Panel = Panel.new()
	panel.position = Vector2(42.0, 1344.0)
	panel.size = Vector2(484.0, 72.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_style = StyleBoxFlat.new()
	_event_style.bg_color = Color("071f5e", 0.94)
	_event_style.border_color = GOLD
	_event_style.set_border_width_all(2)
	_event_style.set_corner_radius_all(20)
	_event_style.shadow_color = Color("041137", 0.45)
	_event_style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", _event_style)
	frame.add_child(panel)
	_event_root = panel
	_event_text = _label("", Rect2(14.0, 4.0, 456.0, 64.0), 21, WHITE, false, _event_root)
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
	_expire_interactions()
	var blend: float = 1.0 - exp(-10.0 * maxf(delta, 0.0))
	_artwork.lula_ratio = lerpf(_artwork.lula_ratio, _target_lula_ratio, blend)
	_artwork.flavio_ratio = lerpf(_artwork.flavio_ratio, _target_flavio_ratio, blend)
	_artwork.pulse = _elapsed
	_artwork.queue_redraw()
	_position_badge(_lula_badge, _lula_screen)
	_position_badge(_flavio_badge, _flavio_screen)


func _position_badge(badge: Control, screen_position: Vector2) -> void:
	badge.visible = screen_position.is_finite() and screen_position.x >= 90.0 and screen_position.x <= 990.0 and screen_position.y >= 720.0 and screen_position.y <= 1340.0
	if badge.visible:
		badge.position = Vector2(clampf(screen_position.x - badge.size.x * 0.5, SAFE_LEFT, SAFE_RIGHT - badge.size.x), screen_position.y - 58.0)


func apply_state(state: Dictionary) -> void:
	if timer_label == null:
		return
	_experience_ended = _experience_ended or bool(state.get("experience_ended", false))
	var remaining: int = int(ceilf(_number(state.get("remaining", 600.0), 600.0, 359999.0)))
	timer_label.text = "%02d:%02d" % [remaining / 60, remaining % 60]
	_fit_line(timer_label, 28)
	round_label.text = "RODADA %02d / 50" % clampi(int(state.get("round", 1)), 1, 50)
	_fit_line(round_label, 15)
	var wins: Array = state.get("wins", [0, 0]) if state.get("wins", [0, 0]) is Array else [0, 0]
	var left_wins: int = maxi(0, int(wins[0])) if wins.size() > 0 else 0
	var right_wins: int = maxi(0, int(wins[1])) if wins.size() > 1 else 0
	cycle_label.text = "C%02d · VITÓRIAS %d×%d" % [maxi(1, int(state.get("cycle", 1))), left_wins, right_wins]
	cycle_label.tooltip_text = "Ciclo %d" % maxi(1, int(state.get("cycle", 1)))
	_fit_line(cycle_label, 14)
	mode_label.text = _plain(str(state.get("mode", "JOGO FICTÍCIO · IA")), 22).to_upper()
	_fit_line(mode_label, 14)

	var left_m: float = _number(state.get("lula_m", 0.0))
	var right_m: float = _number(state.get("flavio_m", 0.0))
	lula_distance.text = "%s m" % _distance(left_m)
	flavio_distance.text = "%s m" % _distance(right_m)
	_fit_line(lula_distance, 20)
	_fit_line(flavio_distance, 20)
	lula_speed.text = ("%.1f" % (_number(state.get("lula_speed", 0.0), 0.0, 1000.0) * 3.6)).replace(".", ",")
	flavio_speed.text = ("%.1f" % (_number(state.get("flavio_speed", 0.0), 0.0, 1000.0) * 3.6)).replace(".", ",")
	_fit_line(lula_speed, 20)
	_fit_line(flavio_speed, 20)

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
	_fit_line(lula_status, 13)
	_fit_line(flavio_status, 13)

	var phase: String = _plain(str(state.get("phase", "")), 52).to_upper()
	var round_name: String = _plain(str(state.get("round_name", "ARENA NACIONAL")), 36).to_upper()
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
	if _experience_ended:
		advantage_label.text = "EXPERIÊNCIA ENCERRADA"
		phase_label.text = "OBRIGADO PELA PARTICIPAÇÃO · RESULTADOS FICTÍCIOS"
		timer_label.text = "--:--"
		lula_speed.text = "0,0"
		flavio_speed.text = "0,0"
		lula_status.text = "ENCERRADO"
		flavio_status.text = "ENCERRADO"
		_artwork.lula_active = false
		_artwork.flavio_active = false
		_artwork.abilities_visible = false
		_artwork.queue_redraw()
		for index: int in range(_gift_images.size()):
			_gift_images[index].hide()
			_gift_captions[index].hide()
			_gift_subtitles[index].hide()
		if _event_tween != null and _event_tween.is_valid():
			_event_tween.kill()
		_event_root.hide()
		_event_text.text = ""
		_interaction_entries.clear()
		_interaction_pending.clear()
		_chat_entries.clear()
		_refresh_interaction_cards()
		_refresh_chat()
		if _audience_tween != null and _audience_tween.is_valid():
			_audience_tween.kill()
		_restore_audience_prompt()
		update_leaderboard(_latest_ranking)
	_fit_line(advantage_label, 15)
	_fit_line(phase_label, 14)

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
	if _event_root == null or _experience_ended:
		return
	if _event_tween != null and _event_tween.is_valid():
		_event_tween.kill()
	_event_text.text = _plain(text, 64)
	_event_style.border_color = RED if team == 1 else (GREEN if team == 2 else GOLD)
	_event_style.bg_color = Color("650d37", 0.94) if kind == "attack" else Color("071f5e", 0.94)
	_event_root.visible = true
	_refresh_interaction_cards()
	_refresh_chat()
	_event_root.position.y = 1334.0
	_event_root.modulate.a = 0.0
	_event_tween = create_tween()
	_event_tween.set_parallel(true)
	_event_tween.tween_property(_event_root, "modulate:a", 1.0, 0.16)
	_event_tween.tween_property(_event_root, "position:y", 1344.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_event_tween.set_parallel(false)
	_event_tween.tween_interval(2.2)
	_event_tween.tween_property(_event_root, "modulate:a", 0.0, 0.30)
	_event_tween.tween_callback(_finish_event_notice)


func _finish_event_notice() -> void:
	_event_root.hide()
	_refresh_interaction_cards()
	_refresh_chat()


func _number(value: Variant, fallback: float = 0.0, maximum: float = 10000000.0) -> float:
	if not (value is float or value is int):
		return fallback
	var number: float = float(value)
	return clampf(number, 0.0, maximum) if is_finite(number) else fallback


func _distance(value: float) -> String:
	return ("%.0f" % value).replace(".", ",")


func _plain(value: String, limit: int) -> String:
	var clean: String = _sanitize_single_line(value)
	if clean.length() <= limit:
		return clean
	var clusters: PackedStringArray = _split_graphemes(clean)
	var acc: String = ""
	for cluster: String in clusters:
		if acc.length() + cluster.length() > limit:
			break
		acc += cluster
	return acc.strip_edges()


func _sanitize_single_line(value: String) -> String:
	var clean: String = ""
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if code in [9, 10, 13]:
			clean += " "
		elif code == 0x200D or (code >= 0xFE00 and code <= 0xFE0F):
			# Preserva ZWJ e seletores de variação para emojis compostos (ex.: 👩‍🚀, ❤️).
			clean += String.chr(code)
		elif code < 32 or (code >= 127 and code <= 159):
			continue
		elif code in [0x061C, 0x200B, 0x200C, 0x200E, 0x200F, 0x2028, 0x2029, 0xFEFF] or (code >= 0x202A and code <= 0x202F) or (code >= 0x2060 and code <= 0x206F):
			continue
		else:
			clean += String.chr(code)
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	return clean.strip_edges()


func _split_graphemes(value: String) -> PackedStringArray:
	var clusters: PackedStringArray = PackedStringArray()
	var prev_code: int = -1
	var prev_is_single_ri: bool = false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		var ch: String = String.chr(code)
		var is_combining: bool = (
			code == 0x200D
			or prev_code == 0x200D
			or (code >= 0x0300 and code <= 0x036F)
			or (code >= 0x1AB0 and code <= 0x1AFF)
			or (code >= 0x20D0 and code <= 0x20FF)
			or (code >= 0xFE00 and code <= 0xFE0F)
			or (code >= 0x1F3FB and code <= 0x1F3FF)
			or (prev_is_single_ri and code >= 0x1F1E6 and code <= 0x1F1FF)
		)
		if not clusters.is_empty() and is_combining:
			clusters[clusters.size() - 1] = clusters[clusters.size() - 1] + ch
			prev_is_single_ri = false
		else:
			clusters.append(ch)
			prev_is_single_ri = code >= 0x1F1E6 and code <= 0x1F1FF
		prev_code = code
	return clusters


func ellipsize_utf8(raw_text: String, font: Font, font_size: int, max_width: float) -> String:
	var clean: String = _sanitize_single_line(raw_text)
	if clean.is_empty() or font == null:
		return clean
	var limit_w: float = maxf(24.0, max_width)
	if font.get_string_size(clean, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= limit_w:
		return clean
	var clusters: PackedStringArray = _split_graphemes(clean)
	var count: int = clusters.size()
	while count > 1:
		count -= 1
		var candidate: String = ""
		for i: int in range(count):
			candidate += clusters[i]
		candidate = candidate.strip_edges() + "…"
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= limit_w:
			return candidate
	return (clusters[0] + "…") if not clusters.is_empty() else "…"


func _initial_grapheme(raw_name: String) -> String:
	var clean: String = _sanitize_single_line(raw_name).trim_prefix("@").strip_edges()
	if clean.is_empty():
		return "?"
	var clusters: PackedStringArray = _split_graphemes(clean)
	return clusters[0].to_upper() if not clusters.is_empty() else "?"
