extends SceneTree

var _clock: int = 10000
var _audience: AudienceDirector = null
var _bus: LiveEventBusInstance = null
var _participations: Array[Dictionary] = []
var _moments: Array[Dictionary] = []
var _rank_changes: int = 0
var _sequence: int = 0
var _ran: bool = false


func _initialize() -> void:
	_bus = LiveEventBusInstance.new()
	_bus.auto_connect = false
	root.add_child(_bus)
	_audience = AudienceDirector.new()
	_audience.time_provider = func() -> int: return _clock
	root.add_child(_audience)
	_audience.setup(_bus)
	_audience.setup(_bus) # Reattaching must not duplicate signal subscriptions.
	_audience.participation_received.connect(func(participant: Dictionary) -> void: _participations.append(participant))
	_audience.moment_requested.connect(func(kind: String, team: int, display_name: String) -> void: _moments.append({"kind": kind, "team": team, "display_name": display_name}))
	_audience.leaderboard_changed.connect(func(_entries: Array[Dictionary]) -> void: _rank_changes += 1)


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var passed: bool = _run_suite()
	root.remove_child(_audience)
	_audience.free()
	_audience = null
	root.remove_child(_bus)
	_bus.free()
	_bus = null
	print("TEST_AUDIENCE_DIRECTOR_PASSED" if passed else "TEST_AUDIENCE_DIRECTOR_FAILED")
	quit(0 if passed else 1)
	return true


func _check(condition: bool, explanation: String) -> bool:
	if not condition:
		printerr("FAIL: ", explanation)
	return condition


func _event(kind: String, user_id: String, team: int = 0, amount: int = 1, display_name: String = "Pessoa") -> Dictionary:
	_sequence += 1
	var payload: Dictionary = {"action_id": "vote_impulse"}
	if team > 0:
		payload["candidate_slot"] = team
	if kind == "gift":
		payload["gift_tier"] = "T1"
		payload["gift_name"] = "Presente real"
		payload["coin_value"] = amount
		payload["repeat_count"] = 1
	elif kind == "like_batch":
		payload["like_count"] = amount
	return {
		"schema_version": "1.0", "event_id": "audience_event_%08d" % _sequence,
		"source": "simulator", "event_type": kind, "timestamp_ms": _clock,
		"priority": "P0" if kind == "gift" else "P1",
		"user": {"user_id": user_id, "display_name": display_name}, "payload": payload
	}


func _run_suite() -> bool:
	for command: String in ["13", "#13", "1", "#1", "Lula"]:
		if not _check(_audience.parse_vote_team_comment(command) == 1, "13 e legado #1 devem escolher Lula"):
			return false
	for command: String in ["22", "#22", "2", "#2", "Flávio Bolsonaro"]:
		if not _check(_audience.parse_vote_team_comment(command) == 2, "22 e legado #2 devem escolher Flávio"):
			return false
	for command: String in ["130", "2022", "113", "22,5", "13 22", "#3", "telefone 13999992222", "", "-13"]:
		if not _check(_audience.parse_vote_team_comment(command) == 0, "Números fora do comando não devem votar: " + command):
			return false
	var first_vote: Dictionary = _event("vote", "u1", 1, 1, "[b]Ana[/b]\n\u202eSilva")
	if not _check(_bus.ingest_envelope(first_vote), "Voto normalizado deve entrar pelo bus"):
		return false
	if not _check(_participations.size() == 1 and _moments.size() == 1 and _participations[0]["display_name"] == "Ana Silva", "Nome deve aparecer uma vez e sem tags/controles"):
		return false
	if not _check(_participations[0]["joined"] and int(_participations[0]["team"]) == 1, "Primeira escolha deve entrar na torcida"):
		return false
	if not _check(not _bus.ingest_envelope(first_vote) and not _audience.ingest_event(first_vote), "Deduplicação deve cobrir bus e reenvio direto"):
		return false
	_clock += 100
	if not _check(_audience.ingest_event(_event("vote", "u1", 2)), "Trocar equipe deve ser aceito durante cooldown"):
		return false
	var snapshot: Dictionary = _audience.get_snapshot()
	if not _check(_participations.size() == 2 and _moments.size() == 1 and snapshot["participants"] == 1 and snapshot["participants_by_team"] == [0, 0, 1], "Troca atualiza escolha e avisa HUD sem duplicar participante ou momento"):
		return false
	_clock += 1900
	_audience.ingest_event(_event("vote", "u1", 2))
	if not _check(_participations.size() == 3 and _moments.size() == 2 and not _participations[2]["joined"], "Todos os votos chegam ao HUD; limite de dois segundos permite novo momento sem nova adesão"):
		return false
	var combo1: Dictionary = _event("gift", "donor_a", 1, 7, "Ana")
	combo1["payload"]["repeat_count"] = 1
	var combo2: Dictionary = _event("gift", "donor_a", 1, 14, "Ana")
	combo2["payload"]["repeat_count"] = 2
	_audience.ingest_event(combo1)
	_audience.ingest_event(combo2)
	_audience.ingest_event(combo2)
	var ranked: Array[Dictionary] = _audience.get_top_supporters()
	if not _check(ranked.size() == 1 and int(ranked[0]["coins"]) == 21, "Coin_value já é delta total: 7+14, sem multiplicar repeat_count nem duplicar pacote"):
		return false
	if not _check(_audience.get_snapshot()["session"]["gifts"] == [0, 3, 0], "Quantidade de presentes deve somar os deltas1+2, separada das21moedas"):
		return false
	_audience.ingest_event(_event("like_batch", "donor_a", 1, 250))
	_audience.ingest_event(_event("share", "donor_a", 1))
	if not _check(int(_audience.get_top_supporters()[0]["coins"]) == 21, "Curtidas e compartilhamentos não geram moedas"):
		return false
	snapshot = _audience.get_snapshot()
	if not _check(snapshot["round"]["likes"] == [0, 250, 0] and snapshot["round"]["shares"] == [0, 1, 0], "Contagens de likes/shares devem permanecer separadas"):
		return false
	var unknown_gift: Dictionary = _event("gift", "unknown_price", 0, 0, "Sem preço")
	var cards_before_unknown: int = _participations.size()
	if not _check(_audience.ingest_event(unknown_gift) and _participations.size() == cards_before_unknown + 1 and _participations[-1]["amount"] == 0, "Presente sem preço conhecido deve receber agradecimento"):
		return false
	if not _check(_audience.get_top_supporters().size() == 1 and not _audience.ingest_event(unknown_gift), "Preço desconhecido não cria moedas, não entra ranking e mantém deduplicação"):
		return false
	# Neutral donors are counted globally without assigning them to Lula.
	_audience.ingest_event(_event("gift", "neutral", 0, 35, "Sem torcida"))
	_audience.ingest_event(_event("vote", "neutral", 2))
	ranked = _audience.get_top_supporters()
	if not _check(int(ranked[0]["team"]) == 0 and int(ranked[0]["coins"]) == 35, "Voto posterior não deve reatribuir moedas neutras"):
		return false
	_audience.ingest_event(_event("gift", "z", 2, 50, "Igual"))
	_audience.ingest_event(_event("gift", "b", 1, 50, "Igual"))
	_audience.ingest_event(_event("gift", "c", 2, 45, "Terceiro"))
	_audience.ingest_event(_event("gift", "d", 1, 40, "Quarto"))
	ranked = _audience.get_top_supporters()
	if not _check(ranked.size() == 5 and ranked[0]["team"] == 1 and ranked[1]["team"] == 2 and ranked[2]["coins"] == 45 and ranked[3]["coins"] == 40 and ranked[4]["coins"] == 35, "Top5 deve ordenar moedas e desempatar por identidade estável"):
		return false
	_audience.ingest_event(_event("gift", "e", 2, 36, "Novo quinto"))
	ranked = _audience.get_top_supporters()
	if not _check(ranked.size() == 5 and ranked[4]["coins"] == 36 and ranked[4]["display_name"] == "Novo quinto", "Outro doador deve ocupar quinto lugar e retirar o menor do Top5"):
		return false
	var coins_before_follow: Array = (_audience.get_snapshot()["session"]["coins"] as Array).duplicate()
	var follow: Dictionary = _event("follow", "new_follower", 0, 1, "Nova seguidora")
	if not _check(_audience.ingest_event(follow) and _participations[-1]["kind"] == "follow" and _participations[-1]["display_name"] == "Nova seguidora" and _moments[-1]["kind"] == "follow", "Novo seguidor deve receber mensagem e sinal próprio"):
		return false
	if not _check(_audience.get_snapshot()["session"]["follows"] == [1, 0, 0] and _audience.get_snapshot()["session"]["coins"] == coins_before_follow and not _audience.ingest_event(follow), "Seguidor não deve gerar moedas nem duplicar contagem em reenvio"):
		return false
	var original_coins: int = int(ranked[0]["coins"])
	ranked[0]["coins"] = 999999
	if not _check(int(_audience.get_top_supporters()[0]["coins"]) == original_coins, "Retorno deve ser cópia e impedir alteração externa do ranking"):
		return false
	var bad_gift: Dictionary = _event("gift", "invalid", 1, 5)
	bad_gift["payload"]["coin_value"] = -10
	if not _check(not _audience.ingest_event(bad_gift), "Moedas negativas devem ser ignoradas"):
		return false
	bad_gift["payload"]["coin_value"] = "500"
	if not _check(not _audience.ingest_event(bad_gift), "Moedas em texto não devem virar valor real"):
		return false
	bad_gift["payload"]["coin_value"] = 1.25
	if not _check(not _audience.ingest_event(bad_gift), "Moedas fracionárias devem ser ignoradas"):
		return false
	bad_gift["payload"]["coin_value"] = true
	if not _check(not _audience.ingest_event(bad_gift), "Booleano não deve virar moeda"):
		return false
	var wrong_slot: Dictionary = _event("vote", "invalid", 13)
	if not _check(not _audience.ingest_event(wrong_slot), "Número eleitoral não deve escapar para slot interno13"):
		return false
	if not _check(_audience.sanitize_name("A".repeat(60)).length() == 24 and _audience.sanitize_name("\u0001\u200b") == "Espectador", "Nomes devem ter teto24 e fallback sanitizado"):
		return false
	var previous_session: Dictionary = _audience.get_snapshot()["session"].duplicate(true)
	_audience.reset_round()
	snapshot = _audience.get_snapshot()
	if not _check(snapshot["round"]["coins"] == [0, 0, 0] and snapshot["session"] == previous_session and _audience.get_top_supporters().size() == 5, "Nova rodada limpa contagens locais e preserva ranking/sessão"):
		return false
	if not _check(not _audience.ingest_event(combo1), "Nova rodada não deve liberar recontagem de presente antigo"):
		return false
	_audience.reset_session()
	for index: int in range(AudienceDirector.MAX_TRACKED_USERS + 20):
		_audience.ingest_event(_event("vote", "capacity_%d" % index, 1))
	snapshot = _audience.get_snapshot()
	if not _check(int(snapshot["participants"]) == 5000 and int(snapshot["retained_event_ids"]) == 5000, "Escolhas e IDs devem ter memória limitada a5000"):
		return false
	_audience.reset_session()
	snapshot = _audience.get_snapshot()
	if not _check(snapshot["participants"] == 0 and snapshot["session"]["coins"] == [0, 0, 0] and _audience.get_top_supporters().is_empty() and int(snapshot["retained_event_ids"]) == 0, "Reset de sessão deve limpar todo estado"):
		return false
	if not _check(_rank_changes > 0, "Mudanças monetárias devem emitir atualização de ranking"):
		return false
	return _check_donor_capacity()


func _check_donor_capacity() -> bool:
	var capacity_director: AudienceDirector = AudienceDirector.new()
	for index: int in range(AudienceDirector.MAX_TRACKED_SUPPORTERS):
		capacity_director.ingest_event(_event("gift", "donor_capacity_%06d" % index, 1, 1))
	var before_overflow: Dictionary = capacity_director.get_snapshot()
	capacity_director.ingest_event(_event("gift", "donor_overflow", 2, 50))
	# A previous donor must continue accumulating even after the maximum distinct-user count.
	capacity_director.ingest_event(_event("gift", "donor_capacity_000000", 1, 70))
	var after_overflow: Dictionary = capacity_director.get_snapshot()
	capacity_director.free()
	if not _check(before_overflow["tracked_supporters"] == 100000 and not before_overflow["ranking_limited"], "Ledger da sessão deve aceitar100000doadores, separadamente das5000escolhas"):
		return false
	if not _check(after_overflow["tracked_supporters"] == 100000 and after_overflow["ranking_limited"] and after_overflow["top_supporters"][0]["coins"] == 71, "Overflow deve ser explícito e manter totais dos doadores já rastreados"):
		return false
	return _check(after_overflow["session"]["coins"] == [0, 100070, 50], "Contagem de moedas da sessão deve permanecer correta mesmo no limite do ranking")
