extends SceneTree
## Suite dedicada ao redesign simetrico 9:16, 3 metas simultaneas (10k seguidores honestos),
## truncamento UTF-8 por grapheme clusters, neutralidade de cards, Top 5 moedas e AvatarVisualCache.

var _passed: bool = true
var _ran: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_passed = false
		printerr("HUD_REDESIGN_TEST_FAIL: ", message)


func _run() -> void:
	var hud: StadiumHUD = StadiumHUD.new()
	root.add_child(hud)
	var avatar_cache: AvatarVisualCache = AvatarVisualCache.new()
	avatar_cache.set_process(false)
	root.add_child(avatar_cache)
	var gift_cache: GiftVisualCache = GiftVisualCache.new()
	gift_cache.set_process(false)
	root.add_child(gift_cache)
	hud.set_avatar_cache(avatar_cache)
	hud.set_gift_cache(gift_cache)

	await process_frame

	# 1. Simetria horizontal 1080x1920 e zona inferior nativa livre (y <= 1722)
	_check_bounds_and_text(hud.frame)
	var top_panel: Panel = hud.frame.get_node("TopSupportersPanel") as Panel
	_check(top_panel != null and top_panel.size.y <= 80.0, "Top 5 vazio colapsa sem cinco travessoes fixos")
	for r_lbl: Label in hud._ranking_names:
		_check(not r_lbl.visible, "Linhas de ranking ficam ocultas quando nao ha doadores")

	# 2. Tres metas independentes simultaneas + honestidade de seguidores 10k
	hud.update_live_goals({
		"likes": {"goal_kind": "likes", "goal_label": "Meta de curtidas", "value": 420, "goal_target": 1000, "progress": 0.42},
		"gifts": {"goal_kind": "gifts", "goal_label": "Meta de presentes", "value": 85, "goal_target": 500, "progress": 0.17},
		"follows": {
			"goal_kind": "follows",
			"goal_label": "Meta 10K Seguidores",
			"value": 12,
			"session_follows": 12,
			"goal_target": 10000,
			"follower_baseline": null,
			"source_mode": "session_only",
			"progress": 0.0012
		}
	}, 12)
	_check(hud._goal_value.text == "420 / 1.000", "Meta 1 exibe curtidas formatadas em pt-BR")
	_check(hud._gifts_goal_value.text == "85 / 500 un.", "Meta 2 distingue unidades de presentes (un.)")
	_check(hud._followers_label.text == "SEGUIDORES +12", "Seguidores da sessao permanecem explicitos (+12)")
	_check(hud._follows_source_badge.text == "ALVO 10,0 MIL" and not hud._follows_source_badge.text.begins_with("0 /"), "Sem total verificado da API, nao finge 0 / 10.000")

	# Com baseline manual rotulado pelo operador + modo moedas na meta 2
	hud.update_live_goals({
		"likes": {"goal_kind": "likes", "goal_label": "Meta de curtidas", "value": 1000, "goal_target": 1000, "progress": 1.0},
		"gifts": {"goal_kind": "coins", "goal_label": "Meta de moedas", "value": 2500, "goal_target": 5000, "progress": 0.5},
		"follows": {
			"goal_kind": "follows",
			"goal_label": "Rumo a 10K",
			"value": 8412,
			"session_follows": 12,
			"goal_target": 10000,
			"follower_baseline": 8400,
			"source_mode": "manual_baseline",
			"progress": 0.8412
		}
	}, 12)
	_check(hud._gifts_goal_value.text == "2.500 / 5.000 ◇", "Meta 2 em moedas rotula simbolo de moedas explicitamente")
	_check(hud._follows_source_badge.text == "8.412 / 10,0 mil", "Com baseline manual auditavel exibe progresso composto")
	_check_bounds_and_text(hud.frame)

	# 3. Truncamento UTF-8 por grapheme clusters (emojis compostos ZWJ, bandeira, acentos, nomes longos)
	var complex_name: String = "Mariana_Oliveira_👩‍🚀🇧🇷👍🏽_SuperTorcedora_2027_ExtraLongo"
	var truncated: String = hud.ellipsize_utf8(complex_name, hud._headline_font, 19, 180.0)
	_check(truncated.ends_with("…"), "Nome longo recebe reticencias por largura visual")
	_check(hud._headline_font.get_string_size(truncated, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x <= 180.0, "Texto truncado respeita largura maxima em pixels")
	_check(not truncated.ends_with("\u200d…"), "Truncamento jamais corta ZWJ no meio de emoji composto")

	# 4. Neutralidade de follow/gift neutro vs equipe explicita + combos ×1, ×10, ×999, ×10.000
	var baseline_children: int = hud.frame.get_child_count()
	hud.show_participation({
		"identity": "tiktok:u_follow",
		"display_name": "viih_souza.ofc",
		"team": 0,
		"kind": "follow",
		"amount": 1
	})
	var slot0: Dictionary = hud._interaction_slots[0]
	_check((slot0["panel"] as Panel).visible, "Card transitorio aparece para novo seguidor")
	_check(not (slot0["team_chip"] as Panel).visible, "Follow neutro NAO recebe chip 13 nem 22")
	_check((slot0["name_label"] as Label).text == "@viih_souza.ofc", "Handle ganha prefixo @ sem duplicar")

	# Combo pago grande (×10.000) com avatar real em cache local e miniatura de presente
	var avatar_hash: String = "b".repeat(64)
	var avatar_path: String = "/viewer-avatars/" + avatar_hash
	var av_img: Image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	av_img.fill(Color("2288ff"))
	var av_tex: Texture2D = avatar_cache._decode_avatar(av_img.save_png_to_buffer())
	_check(av_tex != null and av_tex.get_width() == 96 and av_tex.get_height() == 96, "Avatar 256px reduzido com seguranca para 96x96")
	avatar_cache._store_texture(avatar_path, av_tex)

	var gift_hash: String = "c".repeat(64)
	var gift_path: String = "/gift-icons/" + gift_hash
	gift_cache._origin = "http://127.0.0.1:8765"
	gift_cache.register_event({"event_type": "gift", "payload": {"gift_id": "rose_01", "gift_icon_path": gift_path}})
	gift_cache._store_texture(gift_path, av_tex)

	hud._elapsed += 0.5
	hud.show_participation({
		"identity": "tiktok:u_donor",
		"display_name": "@mariana_oliveira_👩‍🚀_muito_longo_mesmo",
		"team": 1,
		"kind": "gift",
		"gift_id": "rose_01",
		"gift_name": "Rosa",
		"gift_quantity": 9999,
		"amount": 9999,
		"avatar_icon_path": avatar_path
	})
	# Segundo delta do mesmo combo soma para ×10,0 mil no mesmo card
	hud.show_participation({
		"identity": "tiktok:u_donor",
		"display_name": "@mariana_oliveira_👩‍🚀_muito_longo_mesmo",
		"team": 1,
		"kind": "gift",
		"gift_id": "rose_01",
		"gift_name": "Rosa",
		"gift_quantity": 1,
		"amount": 1,
		"avatar_icon_path": avatar_path
	})
	_check(hud._interaction_entries.size() == 2, "Ate dois cards transitorios simultaneos, sem empilhar cinco")
	_check((slot0["avatar"] as TextureRect).visible and not (slot0["mono_panel"] as Panel).visible, "Avatar real substitui monograma quando disponivel no cache local")
	_check((slot0["gift_thumb"] as TextureRect).visible, "Miniatura do presente aparece no card")
	_check((slot0["team_chip"] as Panel).visible and (slot0["chip_label"] as Label).text == "13", "Presente com escolha real exibe chip 13")
	_check((slot0["action_label"] as Label).text.contains("×10,0 mil"), "Combo de 10.000 unidades formata sem estourar largura")
	_check_bounds_and_text(hud.frame)

	# Rajada > 50 eventos/s nao cria nodes dinamicos nem vaza memoria
	for burst_i: int in range(120):
		hud._elapsed += 0.01
		hud.show_participation({
			"identity": "tiktok:burst_%d" % burst_i,
			"display_name": "Torcedor_%d_🇧🇷" % burst_i,
			"team": (burst_i % 2) + 1,
			"kind": "vote",
			"amount": 1
		})
	_check(hud.frame.get_child_count() == baseline_children, "Rajada de >50 eventos/s mantem arvore de nodes fixa")
	_check(hud._interaction_entries.size() <= 2, "Coluna esquerda nunca excede 2 cards")

	# Expiracao limpa cards transitorios
	hud._elapsed += 10.0
	hud._expire_interactions()
	hud._expire_chat()
	_check(hud._interaction_entries.is_empty() and not (slot0["panel"] as Panel).visible, "Cards transitorios expiram e liberam a pista")

	# 5. Top 5 · MOEDAS com homonimos, neutros, avatares e modo Podio Top 3
	hud.update_leaderboard([
		{"display_name": "Carlos Silva", "team": 1, "coins": 1500, "avatar_icon_path": avatar_path},
		{"display_name": "Carlos Silva", "team": 0, "coins": 1200},
		{"display_name": "Pedro Gomes", "team": 2, "coins": 950},
		{"display_name": "Ana Clara", "team": 1, "coins": 800},
		{"display_name": "Gui Oliveira", "team": 2, "coins": 700}
	])
	_check(hud._rank_title.text == "TOP 5 · MOEDAS", "Titulo rotula metrica honesta em moedas")
	_check(hud._ranking_names[0].visible and hud._ranking_names[4].visible, "Cinco doadores ficam visiveis na corrida")
	_check(hud._ranking_avatars[0].visible and not hud._ranking_avatars[1].visible and hud._ranking_dots[1].visible, "Doador com foto usa avatar circular; sem foto usa indicador limpo")
	hud.set_podium_mode(true)
	_check(hud._rank_title.text == "PÓDIO · TOP 3 MOEDAS" and hud._ranking_names[2].visible and not hud._ranking_names[3].visible, "Podio mantem contrato Top 3")
	_check_bounds_and_text(hud.frame)

	# 6. Seguranca do AvatarVisualCache (anti-SSRF loopback-only, rejeicao de SVG/HTML, LRU 64)
	_check(avatar_cache._local_origin("ws://localhost:8766/ws/godot") == "http://127.0.0.1:8766", "AvatarCache preserva porta local Kwai")
	for bad_origin: String in ["wss://evil.example/ws/godot", "ws://10.0.0.5:8765/ws/godot", "http://evil.com/avatar.png"]:
		_check(avatar_cache._local_origin(bad_origin).is_empty(), "AvatarCache rejeita origem externa: " + bad_origin)
	for bad_path: String in ["/viewer-avatars/../secret", "https://p16-sign-va.tiktokcdn.com/img.png", "/gift-icons/" + avatar_hash]:
		_check(not AvatarVisualCache.is_safe_avatar_path(bad_path), "AvatarCache aceita apenas rota opaca /viewer-avatars/<sha256>")
	for bad_bytes: PackedByteArray in [PackedByteArray(), "<svg></svg>".to_utf8_buffer(), "<html></html>".to_utf8_buffer()]:
		_check(avatar_cache._decode_avatar(bad_bytes) == null, "AvatarCache rejeita payload nao binario/SVG/HTML")

	avatar_cache._origin = "http://127.0.0.1:8765"
	for idx: int in range(120):
		var p: String = "/viewer-avatars/%064x" % idx
		avatar_cache._store_texture(p, av_tex)
	_check(int(avatar_cache.get_cache_stats()["textures"]) == 64, "AvatarCache respeita teto LRU de 64 texturas")
	avatar_cache.cancel_pending_requests()

	root.remove_child(hud)
	hud.free()
	root.remove_child(avatar_cache)
	avatar_cache.free()
	root.remove_child(gift_cache)
	gift_cache.free()
	av_tex = null
	av_img = null
	await process_frame

	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans == 0, "Zero orphan nodes apos suite completa do HUD (atual=%d)" % orphans)

	print("TEST_HUD_REDESIGN_GOALS_AVATARS_PASSED" if _passed else "TEST_HUD_REDESIGN_GOALS_AVATARS_FAILED")
	quit(0 if _passed else 1)


func _check_bounds_and_text(frame_root: Control) -> void:
	for child: Node in frame_root.get_children():
		if child is Control and child.name != "ScoreboardArtwork":
			var ctrl: Control = child as Control
			if ctrl.visible and ctrl.size.x > 0.0 and ctrl.size.y > 0.0:
				_check(ctrl.position.x >= 36.0 and ctrl.position.x + ctrl.size.x <= 1044.0, "Elemento respeita margens horizontais simetricas: " + ctrl.name)
				_check(ctrl.position.y + ctrl.size.y <= 1724.0, "Elemento preserva zona inferior nativa livre: " + ctrl.name)
	_walk_labels(frame_root)


func _walk_labels(node: Node) -> void:
	if node is Label:
		var lbl: Label = node as Label
		if lbl.visible and not lbl.text.is_empty() and lbl.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var font: Font = lbl.get_theme_font("font")
			var sz: int = lbl.get_theme_font_size("font_size")
			var rendered_w: float = font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
			_check(rendered_w <= lbl.size.x + 0.5, "Label sem estouro (%s: %.1f <= %.1f)" % [lbl.text, rendered_w, lbl.size.x])
	for child: Node in node.get_children():
		_walk_labels(child)
