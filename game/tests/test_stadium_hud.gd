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
	passed = _check(_hud.timer_label.text == "10:00" and _hud.mode_label.text == "TESTE LOCAL", "Padrão deve identificar teste local") and passed
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
