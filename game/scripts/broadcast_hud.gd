class_name BroadcastHUD
extends CanvasLayer
## Placar de transmissão reutilizável. Dados de corrida são fornecidos pelo coordenador.

const FONT_BOLD: Font = preload("res://assets/fonts/barlow-condensed/BarlowCondensed-Bold.ttf")
const FONT_MEDIUM: Font = preload("res://assets/fonts/barlow-condensed/BarlowCondensed-Medium.ttf")
const INK: Color = Color("102c3d")
const RED: Color = Color("ee334c")
const YELLOW: Color = Color("ffcd32")
var timer_label: Label = null
var round_label: Label = null
var location_label: Label = null
var lula_distance: Label = null
var flavio_distance: Label = null
var advantage_label: Label = null
var preview_badge: Label = null
var red_fill: ColorRect = null
var yellow_fill: ColorRect = null
var frame: Control = null
var cycle_label: Label = null


func _ready() -> void:
	_build()
	apply_state({"round": 1, "round_name": "Primeiro Sol", "remaining": 600.0, "lula_m": 0.0, "flavio_m": 0.0})


func _panel(rect: Rect2, color: Color, radius: int = 10) -> Panel:
	var panel: Panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	panel.add_theme_stylebox_override("panel", style)
	frame.add_child(panel)
	return panel


func _label(text: String, position: Vector2, size: Vector2, font_size: int, color: Color = Color.WHITE, bold: bool = false) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.position = position
	label.size = size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT_BOLD if bold else FONT_MEDIUM)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	frame.add_child(label)
	return label


func _build() -> void:
	frame = Control.new()
	frame.name = "BroadcastSafeFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	# Toda informação essencial fica fora das regiões reservadas das lives.
	_panel(Rect2(48, 258, 852, 52), Color(INK, .95), 7)
	_label("CORRIDA DOS CANDIDATOS", Vector2(66, 260), Vector2(550, 46), 33, Color.WHITE, true)
	round_label = _label("RODADA 01 / 50", Vector2(650, 263), Vector2(232, 42), 29, Color("c8d5dc"), true)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_panel(Rect2(48, 319, 852, 126), Color(INK, .97), 12)
	_panel(Rect2(48, 319, 6, 126), RED, 3)
	_panel(Rect2(894, 319, 6, 126), YELLOW, 3)
	_label("LULA", Vector2(75, 328), Vector2(260, 53), 48, Color.WHITE, true)
	_label("FLÁVIO", Vector2(645, 328), Vector2(230, 53), 48, YELLOW, true)
	lula_distance = _label("0 m", Vector2(76, 381), Vector2(260, 48), 36, Color("c8d5dc"))
	flavio_distance = _label("0 m", Vector2(645, 381), Vector2(230, 48), 36, Color("c8d5dc"))
	_panel(Rect2(377, 326, 188, 108), Color("f4f5ed"), 8)
	timer_label = _label("10:00", Vector2(383, 325), Vector2(176, 79), 76, INK, true)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var clock_caption: Label = _label("TEMPO RESTANTE", Vector2(383, 399), Vector2(176, 25), 23, Color("56717d"), true)
	clock_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	red_fill = ColorRect.new()
	red_fill.color = RED
	red_fill.position = Vector2(48, 455)
	red_fill.size = Vector2(426, 6)
	frame.add_child(red_fill)
	yellow_fill = ColorRect.new()
	yellow_fill.color = YELLOW
	yellow_fill.position = Vector2(474, 455)
	yellow_fill.size = Vector2(426, 6)
	frame.add_child(yellow_fill)
	_panel(Rect2(48, 471, 852, 45), Color("e9f0eb", .9), 7)
	location_label = _label("BRASÍLIA · PRIMEIRO SOL", Vector2(61, 473), Vector2(580, 43), 28, INK, true)
	preview_badge = _label("PRÉVIA VISUAL", Vector2(668, 477), Vector2(230, 36), 25, INK, true)
	preview_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_panel(Rect2(48, 527, 852, 48), Color(INK, .89), 8)
	advantage_label = _label("DUAS EQUIPES. UMA CORRIDA.", Vector2(68, 529), Vector2(812, 42), 30, Color.WHITE, true)
	advantage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel(Rect2(48, 1223, 852, 105), Color(INK, .96), 12)
	_label("JOGO SATÍRICO · ESCOLHA SUA EQUIPE", Vector2(70, 1229), Vector2(800, 32), 25, Color("b8cbd4"), true)
	_label("#1  LULA", Vector2(70, 1262), Vector2(360, 54), 40, Color("ff7082"), true)
	var team_two: Label = _label("#2  FLÁVIO", Vector2(502, 1262), Vector2(375, 54), 40, YELLOW, true)
	team_two.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_panel(Rect2(48, 1337, 852, 38), Color(INK, .9), 7)
	cycle_label = _label("CICLO 01 · VITÓRIAS  0 × 0", Vector2(50, 1337), Vector2(850, 38), 27, Color("d8e4df"), true)
	cycle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func apply_state(state: Dictionary) -> void:
	if timer_label == null:
		return
	var remaining: int = maxi(0, int(ceilf(float(state.get("remaining", 600.0)))))
	timer_label.text = "%02d:%02d" % [remaining / 60, remaining % 60]
	round_label.text = "RODADA %02d / 50" % int(state.get("round", 1))
	location_label.text = "BRASÍLIA · " + str(state.get("round_name", "Primeiro Sol")).to_upper()
	var left_m: float = float(state.get("lula_m", 0.0))
	var right_m: float = float(state.get("flavio_m", 0.0))
	lula_distance.text = "%s m" % _distance(left_m)
	flavio_distance.text = "%s m" % _distance(right_m)
	var advantage: float = left_m - right_m
	advantage_label.text = "DISPUTA EQUILIBRADA" if absf(advantage) < .5 else "%s  +%s m" % ["LULA" if advantage > 0 else "FLÁVIO", _distance(absf(advantage))]
	var left_width: float = 852.0 * clampf(.5 + advantage / 200.0, .15, .85)
	red_fill.size.x = left_width
	yellow_fill.position.x = 48.0 + left_width
	yellow_fill.size.x = 852.0 - left_width
	var phase: String = String(state.get("phase", ""))
	if not phase.is_empty():
		advantage_label.text = phase
	preview_badge.text = "PRÉVIA VISUAL" if bool(state.get("preview", false)) else String(state.get("mode", ""))
	preview_badge.visible = not preview_badge.text.is_empty()
	var wins: Array = state.get("wins", [0, 0])
	cycle_label.text = "CICLO %02d · VITÓRIAS  %d × %d" % [int(state.get("cycle", 1)), int(wins[0]), int(wins[1])]


func _distance(value: float) -> String:
	return ("%.0f" % value).replace(".", ",")
