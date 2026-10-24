extends SceneTree

var _hud: StadiumHUD = null
var _tested: bool = false


func _initialize() -> void:
	_hud = StadiumHUD.new()
	root.add_child(_hud)


func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true
	_run_suite.call_deferred()
	return false


func _run_suite() -> void:
	var passed: bool = true
	passed = _check(_hud.timer_label.text == "10:00" and _hud.mode_label.text == "JOGO FICTÍCIO · IA", "Padrão público preserva transparência sem marcador de desenvolvimento") and passed
	_hud.apply_state({"mode": "TESTE LOCAL"})
	passed = _check(_hud.mode_label.text == "TESTE LOCAL", "Bancada explicitamente identificada continua disponível") and passed
	_hud.apply_state({"remaining": 121.2, "round": 8, "wins": [2, 1], "lula_m": 100.0, "flavio_m": 73.0, "lula_speed": 5.0, "flavio_speed": 4.0, "lula_boost": true})
	passed = _check(_hud.timer_label.text == "02:02", "Cronômetro deve arredondar o restante para cima") and passed
	passed = _check(_hud.advantage_label.text == "LULA NA FRENTE  +27 m", "Vantagem deve vir dos metros reais") and passed
	passed = _check(_hud.lula_speed.text == "18,0" and _hud.flavio_speed.text == "14,4", "Velocidade deve converter m/s para km/h") and passed
	passed = _check(_hud.cycle_label.text == "C01 · VITÓRIAS 2×1" and _hud.lula_status.text == "TURBO ATIVO", "Vitórias e efeitos devem refletir o contrato") and passed
	_hud.apply_state({"remaining": NAN, "wins": [], "lula_m": INF, "flavio_speed": "inválido", "lula_screen": "inválido"})
	passed = _check(_hud.timer_label.text == "10:00" and _hud.lula_distance.text == "0 m" and _hud.flavio_speed.text == "0,0", "Números não finitos e estados incompletos devem ser seguros") and passed
	_hud.show_event("[b]Nome externo[/b]\n" + "A".repeat(80), 1, "boost")
	passed = _check(_hud._event_text.text.length() == 64 and _hud._event_text.text.begins_with("[b]Nome externo[/b] "), "Evento usa Label literal, remove quebras e limita tamanho") and passed
	_hud.show_event("ESCUDO ATIVADO", 2, "shield")
	passed = _check(_hud._event_text.text == "ESCUDO ATIVADO", "Um evento novo deve substituir o anterior") and passed
	if OS.get_cmdline_user_args().has("--hud-capture"):
		await _capture_preview()
	# Encerrar durante uma vitória e um aviso de participação deve cancelar os
	# avisos transitórios, inclusive callbacks que restaurariam o convite de voto.
	_hud.show_participation({"display_name": "Torcedor", "team": 1, "kind": "vote"})
	_hud.show_event("13 VENCEU · LULA", 1, "victory")
	_hud.apply_state({"experience_ended": true, "round_finished": true, "winner_id": 1, "next_round_in": 30, "lula_speed": 20.0, "flavio_speed": 15.0, "lula_boost": true, "flavio_shield": true})
	passed = _check(_hud.timer_label.text == "--:--" and _hud.advantage_label.text == "EXPERIÊNCIA ENCERRADA" and not _hud.phase_label.text.contains("NOVA RODADA"), "Fim da experiência prevalece sobre vitória e contagem da rodada") and passed
	passed = _check(_hud.lula_speed.text == "0,0" and _hud.flavio_speed.text == "0,0" and _hud.lula_status.text == "ENCERRADO" and _hud.flavio_status.text == "ENCERRADO", "Encerramento zera velocidades e remove status de efeitos ativos") and passed
	passed = _check(not _hud._artwork.abilities_visible and not _hud._artwork.lula_active and not _hud._artwork.flavio_active, "Encerramento remove desenho das habilidades e brilho de turbo") and passed
	for index: int in range(4):
		passed = _check(not _hud._gift_images[index].visible and not _hud._gift_captions[index].visible and not _hud._gift_subtitles[index].visible, "Todas as camadas da habilidade ficam ocultas no fim") and passed
	passed = _check(not _hud._event_root.visible and _hud._event_text.text.is_empty() and not _hud._event_tween.is_running() and not _hud._audience_tween.is_running(), "Fim cancela eventos e tweens anteriores") and passed
	_hud.show_event("TURBO ATRASADO", 2)
	_hud.show_participation({"display_name": "Evento atrasado", "team": 2, "kind": "gift"})
	var late_icon: ImageTexture = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	_hud.set_gift_legend([{"action": "boost", "texture": late_icon, "label": "Rosa"}])
	_hud.update_leaderboard([])
	# Um snapshot atrasado sem a flag final não pode reabrir uma sessão encerrada.
	_hud.apply_state({"lula_speed": 10.0, "lula_boost": true})
	await create_timer(0.05).timeout
	passed = _check(not _hud._event_root.visible and _hud._interaction_entries.is_empty() and _hud._chat_entries.is_empty() and not _hud._gift_images[0].visible, "Eventos e ícones atrasados não reaparecem após fim") and passed
	passed = _check(_hud._audience_pill.visible and _hud._audience_label.text == "OBRIGADO PELA PARTICIPAÇÃO" and _hud._ranking_empty_label.text == "Sem presentes registrados nesta sessão" and _hud.lula_status.text == "ENCERRADO", "Fim mantém agradecimento e ranking neutro sem convite para presentes ou votos") and passed
	root.remove_child(_hud)
	_hud.free()
	print("TEST_STADIUM_HUD_PASSED" if passed else "TEST_STADIUM_HUD_FAILED")
	quit(0 if passed else 1)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		printerr("FAIL: ", message)
	return condition


func _capture_preview() -> void:
	# Estado fictício explícito apenas no teste visual; não altera o jogo.
	_hud.apply_state({"remaining": 124.0, "round": 13, "cycle": 1, "wins": [2, 1], "lula_m": 1012.0, "flavio_m": 982.0, "lula_speed": 18.0, "flavio_speed": 16.9, "lula_boost": true, "mode": "TESTE LOCAL", "phase": "BRASÍLIA · ARENA NACIONAL"})
	_hud._event_root.hide()
	await create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	_save_capture("hud-standalone-v3.png")
	_hud.apply_state({"remaining": 124.0, "round": 13, "cycle": 1, "wins": [2, 1], "lula_m": 1012.0, "flavio_m": 982.0, "lula_speed": 18.0, "flavio_speed": 16.9, "lula_boost": true, "lula_screen": Vector2(290.0, 1040.0), "flavio_screen": Vector2(710.0, 1220.0)})
	_hud.show_event("EQUIPE LULA ATIVOU SUPER TURBO!", 1)
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	_save_capture("hud-event-v3.png")


func _save_capture(filename: String) -> void:
	var image: Image = root.get_texture().get_image()
	var output: String = ProjectSettings.globalize_path("res://../docs/evidencias/stadium/") + filename
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	if FileAccess.file_exists(output):
		printerr("Captura anterior preservada: ", output)
		return
	var result: Error = image.save_png(output)
	print("HUD_CAPTURE ", result, " ", image.get_size())
