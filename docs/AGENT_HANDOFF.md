# AGENT_HANDOFF.md — Registro Cronológico de Transferência entre Agentes

> **Propósito:** permitir que qualquer agente (ChatGPT / Antigravity / Claude / Codex) assuma o projeto **imediatamente** a partir do último commit publicado em `origin/master`, sabendo exatamente o que já foi validado, o que está em andamento (WIP) e qual é a próxima ação exata, sem perder progresso nem refazer trabalho.

---

## Sequência obrigatória de leitura ao assumir

1. [AGENTS.md](../AGENTS.md)
2. [RETOMADA_IA_2026-10-24.md](../RETOMADA_IA_2026-10-24.md)
3. [CONTINUIDADE.md](../CONTINUIDADE.md)
4. [docs/ESTADO_ATUAL.md](ESTADO_ATUAL.md)
5. **Este arquivo (`docs/AGENT_HANDOFF.md`)**
6. [docs/AGENTE_RETOMADA_PROMPT_MESTRE_2026-10-24.md](AGENTE_RETOMADA_PROMPT_MESTRE_2026-10-24.md)
7. [docs/referencias/HUD_REFERENCIA.md](referencias/HUD_REFERENCIA.md) e [docs/referencias/hud-conceito-chatgpt-2026-10-24.png](referencias/hud-conceito-chatgpt-2026-10-24.png)

---

## Histórico Cronológico de Sessões

### 1. Histórico Base (IA anterior — até `9fc7e5a0de01340e59b1719e82ea1794be78a8a2`)
- **Commits de referência:** `e22a3fa584ccf4375aaf0eeb33c6304fe854d46e` e `9fc7e5a0de01340e59b1719e82ea1794be78a8a2`
- **Entregas preservadas:**
  - Cena principal `game/scenes/main/stadium_race.tscn` (`1080x1920`, 60 FPS), pista azul-cobalto, arquibancadas e `planalto_v2.glb`.
  - Personagens aprovados `game/assets/characters/api-cape-v13/{lula_run,flavio_run}.glb` (65 ossos) + capas `cape-motion-v1`.
  - Ciclo de 50 rodadas × 600 s + intervalo de 30 s (3 s chegada + 24 s pódio + 3 s contagem), outbox SQLite durável e `RacePersistence` com journal de presentes.
  - `GiftVisualCache` conectado ao `StadiumRace` e vozes/SFX locais já gerados.

---

### 2. Sessão Antigravity (24/10/2026 — Checkpoints Incrementais Contínuos)
- **Recebido em:** `master@9fc7e5a` (com commits locais intermediários consolidados e tag `checkpoint-ia-anterior`)
- **Referência visual oficial publicada:** `master@25d5c3ba443b51ec30bc742c3532d14e0a14dda6` (`docs/referencias/hud-conceito-chatgpt-2026-10-24.png` intacto via Git LFS, `2.370.882` bytes, SHA-256 `3859DF3DB23DEEAD064A8C75E83F86055ECFE47FE63602423916C4E186CD01D8`).

#### Entregas CONCLUÍDAS e VALIDADAS até este checkpoint:
1. **Auditoria Inicial e Captura Baseline (`63032dd`)**:
   - [docs/auditorias/AUDITORIA_RETOMADA_2026-10-24.md](auditorias/AUDITORIA_RETOMADA_2026-10-24.md)
   - Captura real ANTES do redesign: [docs/evidencias/estadio/antes-redesign-hud-2026-10-24.png](evidencias/estadio/antes-redesign-hud-2026-10-24.png) (`1080x1920`, `60.0 FPS`).
2. **Segurança Local, Anti-SSRF com IP Fixado, Cache de Avatares e Metas Triplas no Backend (`061be77`)**:
   - Arquivos: `services/live_bridge/{gift_images.py,avatar_images.py,protocol.py,live_goal.py,server.py,adapters/tiktok_adapter.py,adapters/kwai_adapter.py}`, `tools/{kwai_live_collector.cjs,run_live_instances.py}`, `services/live_bridge/test_multi_goals_security_avatars.py`.
   - `LIVE_BRIDGE_LOCAL_TOKEN` e `LIVE_BRIDGE_PRODUCER_TOKEN` impostos em `/api/admin/*`, `/ws/admin`, `/ws/godot`, `/ws/ingest`, `/webhook/kwai`, `/gift-icons/<sha256>` e `/viewer-avatars/<sha256>`, com cookie HttpOnly `SameSite=Strict` para `/admin/`.
   - Proteção anti-SSRF com DNS pinning (conexão TLS ao IP público validado, SNI/Host originais, bloqueio de IPs privados/loopback e redirects inseguros) em `gift_images.py` e `avatar_images.py`.
   - Três metas simultâneas persistidas por plataforma (`likes`, `gifts`/`coins`/`gift_specific`, `follows` alvo `10.000` com distinção honesta `session_only` vs `manual_baseline`), mantendo `set_live_goal` 100% retrocompatível.
   - **Testes executados:**
     - `services\live_bridge\.venv\Scripts\python.exe -m pytest services/live_bridge tools -q -p no:cacheprovider` → **`110 passed, 2 warnings, 48 subtests passed`** (`exit 0`).
     - `services\live_bridge\.venv\Scripts\python.exe tools/run_live_instances.py --both --check` → **`"valid": true`** (`exit 0`).
3. **Painel Admin Responsivo com 3 Metas Simultâneas e QA Playwright (`65fc665`)**:
   - Arquivos: `services/live_bridge/admin/{index.html,app.js,styles.css}`, `tools/qa_admin_panel.cjs`, `services/live_bridge/qa-panel/{admin-375.png,admin-768.png,admin-1440.png,report.json}`.
   - **Teste executado:** `node tools/qa_admin_panel.cjs` → **`FUNCTIONAL_PASS`**, zero erros de console/rede, **`overflow: false` em `375px`, `768px` e `1440px`**.

#### Entregas IMPLEMENTADAS e EM VALIDAÇÃO (WIP neste checkpoint):
4. **Redesign Simétrico do HUD 9:16 + Cache de Avatares Godot + `2027` Legível no Planalto**:
   - Arquivos alterados/criados:
     - `game/scripts/avatar_visual_cache.gd` (novo cache não bloqueante `/viewer-avatars/<sha256>`, limite `512 KiB`, downscale `96 px`, LRU 64, cancelamento na troca de rodada e suporte a `LIVE_AVATARS_ENABLED`).
     - `game/scripts/gift_visual_cache.gd` e `game/scripts/live_event_bus.gd` (token local `X-JOGI-Token`, suporte a `set_live_goals` e eventos neutros `candidate_slot == 0`).
     - `game/scripts/audience_director.gd` (encaminhamento sanitizado de `avatar_icon_path`, `gift_icon_path`, `gift_id`, `gift_name` e mapa transitório limitado em RAM sem persistir PII no checkpoint).
     - `game/scripts/race_main.gd` e `game/scripts/race_persistence.gd` (persistência retrocompatível de `live_goals`).
     - `game/scripts/stadium_world.gd` (brasão arquitetônico escuro/dourado acima do Planalto com `AnoCenografico2027` nítido dia/noite sem cobrir colunas/rampa).
     - `game/scripts/stadium_race.gd` e `game/scripts/stadium_hud.gd` (layout simétrico `x=42..1038`, 3 metas no topo, placar reordenável com retratos circulares, até 2 cards transitórios de interação com avatar circular/monograma e truncamento UTF-8 por grapheme cluster, `TOP 5 · MOEDAS` compacto que colapsa quando vazio, 4 cards arredondados de habilidades e faixa `y=1720..1920` livre).

#### Pendências Restantes (em execução imediata após este push):
- [ ] Rodar suíte completa de testes Godot (`test_rounded_hud.gd`, `test_stadium_hud.gd`, `test_stadium_integration.gd`, `test_stadium_art_revision.gd`, `test_audience_director.gd`, `test_gift_visual_cache.gd`, `test_round_cycle.gd`, `test_paid_round_boundary.gd`, `test_race_persistence.gd`, `test_race_audio.gd`, `test_live_bridge_e2e.gd`).
- [ ] Adicionar regressões explícitas dos dois P2 históricos (`49.9m -> 50.0m` em `test_stadium_art_revision.gd` e reversão rápida `1 -> 2 -> 1` sob cooldown em `test_stadium_integration.gd`) + suíte `game/tests/test_hud_redesign_goals_avatars.gd`.
- [ ] Capturar screenshots reais DEPOIS em múltiplas resoluções (`1080x1920`, `720x1280`, `540x960`, `360x640`) e cenários (dia, noite, empate, ultrapassagem, Top 5, meta 10k, pódio) em `docs/evidencias/estadio/`.
- [ ] Executar benchmark simultâneo de **10 minutos contínuos** das duas instâncias `1080x1920` (`TikTok :8765` + `Kwai :8766`) + gravação curta de áudio/vídeo local + teste de falha/recuperação isolada.
- [ ] Executar revisão `security-reviewer` e `independent-reviewer`, abrir as duas janelas visíveis no desktop do usuário (`ABRIR_DUAS_LIVES.cmd`) e atualizar `docs/CHECKLIST_ENTREGA.md` e `docs/TESTES_FINAIS.md`.

#### Próxima ação exata se outro agente assumir a partir deste commit:
1. Definir `$env:GDA_GODOT = 'C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'`.
2. Executar `gda.exe scene validate res://scenes/main/stadium_race.tscn --project game --json` e os scripts em `game/tests/test_*.gd`.
3. Adicionar `game/tests/test_hud_redesign_goals_avatars.gd` e as duas regressões P2, capturar screenshots DEPOIS e prosseguir para o benchmark de 10 minutos das duas instâncias.
