extends SceneTree
## Regression cases reproduced independently during the 24/10 return audit.

var _passed: bool = true


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_passed = false
		printerr("HUD_INTERACTION_FAIL: ", message)


func _gift(team: int) -> Dictionary:
	return {"identity": "simulator:donor_a", "display_name": "Pessoa A", "kind": "gift",
		"gift_id": "rose", "gift_quantity": 1, "amount": 1, "team": team}


func _run() -> void:
	var hud: StadiumHUD = StadiumHUD.new()
	root.add_child(hud)
	hud.set_process(false)
	hud.show_participation(_gift(1))
	hud._elapsed = 1.0
	hud.show_participation({"identity": "simulator:follower_b", "display_name": "Pessoa B", "kind": "follow", "team": 0, "amount": 1})
	hud._elapsed = 3.0
	hud.show_participation(_gift(1))
	hud._elapsed = 1.0 + StadiumHUD.INTERACTION_TTL_SECONDS + .1
	hud._expire_interactions()
	_check(hud._interaction_entries.size() == 1, "renovar combo antigo não impede expiração independente do novo seguidor")
	_check(str(hud._interaction_entries[0]["identity"]) == "simulator:donor_a", "só o card do combo renovado permanece")
	hud._interaction_entries.clear()
	hud._elapsed = 10.0
	hud.show_participation(_gift(1))
	hud._elapsed = 11.0
	hud.show_participation(_gift(2))
	_check(hud._interaction_entries.size() == 2, "mesmo doador/presente para equipes diferentes gera cards distintos")
	_check(int(hud._interaction_entries[0]["team"]) == 2 and int(hud._interaction_entries[0]["gift_quantity"]) == 1, "presente mais recente mantém equipe22 e quantidade própria")
	_check(int(hud._interaction_entries[1]["team"]) == 1 and int(hud._interaction_entries[1]["gift_quantity"]) == 1, "presente anterior conserva equipe13 sem reatribuição")
	var latest_slot: Dictionary = hud._interaction_slots[0]
	_check((latest_slot["chip_label"] as Label).text == "22", "chip renderizado acompanha equipe22 do evento recente")
	hud._elapsed = 11.1
	hud.show_participation(_gift(2))
	_check(hud._interaction_entries.size() == 2 and int(hud._interaction_entries[0]["gift_quantity"]) == 2, "deltas da mesma equipe continuam combinados")
	hud._elapsed = 10.0 + StadiumHUD.INTERACTION_TTL_SECONDS + .1
	hud._expire_interactions()
	_check(hud._interaction_entries.size() == 1 and int(hud._interaction_entries[0]["team"]) == 2, "expiração da contribuição13 não apaga a contribuição22 ainda válida")
	var atlas_portraits: int = 0
	for node: Node in hud.frame.find_children("*", "TextureRect", true, false):
		var portrait: TextureRect = node as TextureRect
		if portrait.texture is AtlasTexture:
			atlas_portraits += 1
			var material: ShaderMaterial = portrait.material as ShaderMaterial
			var region: Vector4 = material.get_shader_parameter("circle_uv_region")
			_check(region.z > .0 and region.z < 1.0 and region.w > .0 and region.w < 1.0, "máscara circular usa UV local do rosto recortado no atlas")
	_check(atlas_portraits == 2, "os dois retratos aprovados usam a máscara corrigida")
	hud.show_event("ULTRAPASSAGEM · 22 FLÁVIO ASSUME A PONTA", 2)
	for entry: Dictionary in hud._interaction_slots:
		var panel: Control = entry["panel"] as Control
		if panel.visible:
			_check(not panel.get_rect().intersects(hud._event_root.get_rect()), "aviso mecânico não cobre cards de espectadores")
	_check(hud._event_root.position.y > 1320.0, "aviso preserva a faixa dos pés dos corredores")
	hud._finish_event_notice()
	_check(is_equal_approx((hud._interaction_slots[0]["panel"] as Control).position.y, 1352.0), "cards retornam à posição regular ao terminar aviso")
	root.remove_child(hud)
	hud.free()
	await process_frame
	print("TEST_HUD_INTERACTION_REGRESSIONS_PASSED" if _passed else "TEST_HUD_INTERACTION_REGRESSIONS_FAILED")
	quit(0 if _passed else 1)
