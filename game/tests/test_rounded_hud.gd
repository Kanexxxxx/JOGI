extends SceneTree

var _hud: StadiumHUD = null
var _ran: bool = false
var _passed: bool = true


func _initialize() -> void:
	_hud = StadiumHUD.new()
	root.add_child(_hud)


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run.call_deferred()
	return false


func _run() -> void:
	_hud.apply_state({"lula_m": 130.0, "flavio_m": 129.0, "lula_speed": 10.0, "flavio_speed": 12.0})
	_check_visible_text(_hud.frame)
	_check(_hud.get_display_order() == [1, 2], "Lula lider aparece primeiro")
	_hud.apply_state({"lula_m": 130.0, "flavio_m": 145.0, "lula_speed": 10.0, "flavio_speed": 12.0})
	_check(_hud.get_display_order() == [2, 1], "Ultrapassagem reordena as linhas")
	_check(_hud._team_roots[1].position.y < _hud._team_roots[0].position.y, "Ordem real de Controls acompanha o lider")
	_check(_hud.lula_distance.text == "130 m" and _hud.flavio_distance.text == "145 m", "Metros preservam identidade depois da troca")
	_check(_hud.lula_speed.text == "36,0" and _hud.flavio_speed.text == "43,2", "Velocidade continua m/s convertida para km/h")
	_check(_hud._place_labels[0].text == "2º" and _hud._place_labels[1].text == "1º", "Posicao nao substitui numero do candidato")
	_hud.apply_state({"lula_m": 200.0, "flavio_m": 200.0})
	_check(_hud.get_display_order() == [2, 1] and _hud.advantage_label.text == "DISPUTA EQUILIBRADA", "Empate mantem ordem sem piscar")
	_hud.apply_state({"round_finished": true, "winner_id": 1, "next_round_in": 29.1})
	_check(_hud.advantage_label.text == "13 VENCEU · LULA" and _hud.phase_label.text == "NOVA RODADA EM 30 s", "Vitoria e intervalo usam estado do coordenador")
	_hud.apply_state({"round_finished": true, "winner_id": 2, "next_round_in": 0.0})
	_check(_hud.advantage_label.text == "22 VENCEU · FLÁVIO", "Vitoria Flavio preserva numero 22")
	_hud.apply_state({"round_finished": true, "winner_id": 0})
	_check(_hud.advantage_label.text == "EMPATE NA RODADA", "Empate nao inventa vencedor")
	_check(_hud._headline_font.has_char(0xE1) and _hud._headline_font.has_char(0xBA), "Fonte Nunito inclui acentos e ordinal")
	var weight_tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	_check(float(_hud._headline_font.variation_opentype.get(weight_tag, 0)) == 900.0, "Peso usa tag numerica real em vez de alias ignorado pelo engine")
	_check(_hud._event_style.corner_radius_top_left >= 16, "Aviso usa cantos arredondados")
	var badge_style: StyleBoxFlat = (_hud._lula_badge as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	_check(badge_style.corner_radius_top_left >= 16, "Badge usa cantos arredondados")
	var baseline_nodes: int = _hud.get_child_count()
	for index: int in range(1000):
		_hud.show_participation({"kind": "vote", "team": 1 if index % 2 == 0 else 2, "display_name": "Pessoa %d" % index})
	_check(_hud._chat_entries.size() == 1 and _hud._chat_lines.size() == 3, "Mil comentarios simultaneos nao enfileiram nodes nem inundam feed")
	for index: int in range(6):
		_hud._elapsed += 0.7
		_hud.show_participation({"kind": "vote", "team": 2, "display_name": "Ana %d" % index})
	_check(_hud._chat_entries.size() == 3 and _hud.get_child_count() == baseline_nodes, "Feed limitado a tres entradas em nodes fixos")
	_hud._elapsed += 1.0
	_hud.show_participation({"kind": "vote", "team": 1, "display_name": "Bia\u202e\n[13]"})
	_check(_hud._chat_lines[0].text.contains("Bia [13]") and not _hud._chat_lines[0].text.contains("\u202e"), "Nomes permanecem literais e sem controle bidi")
	_hud._elapsed += 10.0
	_hud._expire_chat()
	_check(_hud._chat_entries.is_empty() and not _hud._chat_panel.visible, "Feed expira e oculta painel vazio")
	_hud.update_live_goal({"value": 1000000000, "goal_target": 1000000000, "progress": 1.0}, 1000000000)
	_check_visible_text(_hud.frame)
	_hud.update_live_goal({"value": 1200, "goal_target": 5000, "progress": 0.24}, 17)
	_check_visible_text(_hud.frame)
	var legend: Array[Dictionary] = [{"action": "boost", "texture": StadiumHUD.PORTRAITS[0], "label": "Teste local"}]
	_hud.set_gift_legend(legend)
	_check(_hud._gift_images[0].visible and _hud._gift_captions[0].text == "Teste local" and _hud._artwork.gift_image_active[0], "Imagem local recebida pelo contrato substitui icone")
	_hud.set_gift_legend([])
	_check(not _hud._gift_images[0].visible and _hud._gift_captions[0].text == "IMPULSO", "Sem imagem real mantem legenda de mecanica")
	_check_visible_text(_hud.frame)
	if OS.get_cmdline_user_args().has("--rounded-hud-capture"):
		await _capture()
	root.remove_child(_hud)
	_hud.free()
	print("TEST_ROUNDED_HUD_PASSED" if _passed else "TEST_ROUNDED_HUD_FAILED")
	quit(0 if _passed else 1)


func _capture() -> void:
	_hud.update_live_goal({"value": 1200, "goal_target": 5000, "goal_label": "Meta de curtidas", "progress": 0.24}, 17)
	_check_visible_text(_hud.frame)
	_hud.apply_state({"mode": "TESTE LOCAL", "remaining": 477.0, "round": 3, "lula_m": 440.0, "flavio_m": 461.0, "lula_speed": 12.4, "flavio_speed": 15.8})
	var top: Array[Dictionary] = [{"display_name": "Ana (teste)", "team": 1, "coins": 2400}, {"display_name": "Bia (teste)", "team": 2, "coins": 800}]
	_hud.update_leaderboard(top)
	for index: int in range(3):
		_hud._elapsed += 2.1
		_hud.show_participation({"kind": "vote", "team": 1 if index % 2 == 0 else 2, "display_name": ["Joana (teste)", "Marcos (teste)", "Rafa (teste)"][index]})
	_hud._event_root.hide()
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var output: String = ProjectSettings.globalize_path("res://../docs/evidencias/estadio/hud-arredondado-v3.png")
	if not FileAccess.file_exists(output):
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		print("ROUNDED_HUD_CAPTURE ", root.get_texture().get_image().save_png(output))


func _check_visible_text(node: Node) -> void:
	if node is Label:
		var label: Label = node as Label
		if label.visible and not label.text.is_empty() and label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var font: Font = label.get_theme_font("font")
			var size: int = label.get_theme_font_size("font_size")
			_check(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= label.size.x, "Texto cabe na largura: " + label.text)
	for child: Node in node.get_children():
		_check_visible_text(child)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_passed = false
		printerr("FAIL: ", message)
