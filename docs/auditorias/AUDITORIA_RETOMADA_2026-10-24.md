# Auditoria Não Destrutiva de Retomada — JOGI (24/10/2026)

- **Repositório:** `https://github.com/Kanexxxxx/JOGI.git` (PÚBLICO — branch `master`)
- **Linhagem de commits verificada:**
  - `e22a3fa584ccf4375aaf0eeb33c6304fe854d46e` (`tag: checkpoint-ia-anterior`) — Estado base deixado pela IA #1 (`24/10/2026 12:50:05`).
  - `9fc7e5a0de01340e59b1719e82ea1794be78a8a2` — Inclusão dos ativos LFS + ligação `GiftVisualCache` ↔ `StadiumHUD.set_gift_legend()` e telemetria `performance`.
  - `989fd0e`, `b7ac747`, `3be76ed` — Documentos de referência visual e prompt mestre de retomada publicados na `master`.
  - `1be84b1`, `fba109a`, `4682263` — Receptor local Kwai + coletor local Playwright isolado, responsividade/telemetria do painel Admin e correções P1 da revisão independente/segurança.
  - `25d5c3ba443b51ec30bc742c3532d14e0a14dda6` — Publicação intacta via Git LFS do PNG conceitual oficial [hud-conceito-chatgpt-2026-10-24.png](../referencias/hud-conceito-chatgpt-2026-10-24.png) (`2.370.882` bytes, SHA-256 `3859DF3DB23DEEAD064A8C75E83F86055ECFE47FE63602423916C4E186CD01D8`).
- **Captura real de baseline (ANTES do redesign do HUD):** [antes-redesign-hud-2026-10-24.png](../evidencias/estadio/antes-redesign-hud-2026-10-24.png) (`1080×1920`, `59,99 FPS`, `p95 = 16,67 ms`, Vulkan 1.4.357 em RTX 4060).

---

## 1. Ambiente e Hardware Verificados no PC

| Item | Valor medido localmente |
|---|---|
| CPU | AMD Ryzen 7 5700X 8-Core Processor |
| GPU | NVIDIA GeForce RTX 4060 (`8.188 MB` VRAM total · `804 MB` em repouso · `46 °C`) |
| RAM | `16.293,1 MB` total (`7.623,2 MB` livres em repouso) |
| Godot Engine | `v4.7.2.stable.official.ed1daf0bf` (`Godot_v4.7.2-stable_win64.exe` e `_console.exe`) |
| Godot Agent (`gda`) | `0.24.1` (`C:\Users\Kanex\.local\bin\gda.exe`) |
| Python (`.venv`) | `services/live_bridge/.venv/Scripts/python.exe` (`pytest`: `104 passed, 48 subtests passed` em `50,88 s`) |
| OBS (`obs64.exe`) | Instalado, **não em execução** no início da sessão |

---

## 2. Classificação por Subsistema (`EXISTE / VALIDADO / NÃO TESTADO / PARCIAL / BLOQUEADO / REGRESSÃO`)

| Subsistema | Arquivos principais | Classificação | Evidência verificada |
|---|---|---|---|
| Cena principal 3D + ciclo 50×600 s + intervalo 30 s | `game/scenes/main/stadium_race.tscn`, `game/scripts/stadium_race.gd`, `game/scripts/race_main.gd` | **VALIDADO** | Cena ativa em `project.godot`; `gda scene validate` / `scene preflight` aprovados; captura real `antes-redesign-hud-2026-10-24.png` a 60 FPS. |
| Personagens 3D 65 ossos, rostos 4K e capas `cape-motion-v1` | `game/assets/characters/api-cape-v13/*.glb`, `cape-motion-v1/`, `candidate_cape_motion.gd` | **VALIDADO** | Mantidos intactos; `test_cape_motion.gd` e `test_hero_presentation.gd` aprovados. |
| Palácio do Planalto v2 e sinalização `2027` | `game/assets/environments/planalto/planalto_v2.glb`, `game/scripts/stadium_world.gd` | **PARCIAL** | Modelo 3D validado, mas na captura `antes-redesign-hud-2026-10-24.png` o `Label3D` `AnoCenografico2027` aparece pequeno e com baixo contraste contra o céu claro. |
| Marcadores de 50 m e áudio de ultrapassagem (antigos P2) | `game/scripts/stadium_world.gd`, `game/scripts/race_audio.gd` | **PARCIAL** | Código já vincula lateral a `(mark / 50) % 2` e atualiza `set_current_leader` antes do cooldown, mas `test_stadium_art_revision.gd` ainda não exercita explicitamente a fronteira `49,9 m → 50,0 m` e falta teste integrado de reversão rápida `1 → 2 → 1` no `StadiumRace`. |
| `GiftVisualCache` e faixa de 4 habilidades | `game/scripts/gift_visual_cache.gd`, `game/scripts/stadium_race.gd`, `game/scripts/stadium_hud.gd` | **VALIDADO (COM POLIMENTO VISUAL PENDENTE)** | Ligação `gift_visuals` → `_refresh_gift_legend()` → `set_gift_legend()` já ativa e testada (`test_estreia_revision.gd`), faltando legendas de ação em português nos 4 cards individuais e validação visual completa. |
| HUD de transmissão (`StadiumHUD`) e alinhamento 9:16 | `game/scripts/stadium_hud.gd` | **PARCIAL** | Captura `antes-redesign-hud-2026-10-24.png` mostra desalinhamento horizontal (`x = 48..930` em tela `1080`, sobrando `150 px` à direita), apenas 1 meta ativa no topo e caixa larga (`882×258`) cobrindo a pista inferior. |
| Três metas simultâneas (Curtidas, Presentes, Seguidores 10.000) | `services/live_bridge/live_goal.py`, `protocol.py`, `stadium_hud.gd`, `admin/` | **PARCIAL** | Hoje há 1 meta configurável (`set_live_goal`) + rótulo fixo `SEGUIDORES +N`. Falta extensão retrocompatível para 3 metas simultâneas independentes com fonte honesta para 10k seguidores. |
| Cards transitórios com foto real do espectador e truncamento Unicode 1 linha | `services/live_bridge/protocol.py`, `stadium_hud.gd` | **NÃO TESTADO / PENDENTE** | Contrato atual não transporta `avatar_url`/`avatar_icon_path`; HUD atual usa linhas textuais sem cache anti-SSRF de avatares. |
| Segurança local (`LIVE_BRIDGE_LOCAL_TOKEN` e anti-SSRF DNS rebinding) | `services/live_bridge/server.py`, `gift_images.py`, `.env.example` | **PARCIAL** | Loopback `Host`/`Origin`/`Sec-Fetch-Site` e CSP ativos, porém `LIVE_BRIDGE_LOCAL_TOKEN` listado em `.env.example` ainda não era imposto em `server.py`, e `gift_images.download_image()` fazia resolução DNS separada da conexão (`opener.open`), permitindo janela teórica de DNS rebinding. |
| Conector TikTok Live (`@nostalgiia.br`, `:8765`) | `services/live_bridge/adapters/tiktok_adapter.py` | **PARCIAL (NÃO TESTADO EM SALA REAL)** | SDK `TikTokLive` instalado e validado em suíte simulada (`waiting_room` fora do ar); falta validação com eventos reais em live aberta autorizada. |
| Conector Kwai (`@mentalista..`, `:8766` / `:8786`) | `services/live_bridge/adapters/kwai_adapter.py`, `tools/kwai_live_collector.cjs` | **BLOQUEADO EM NUVEM OFICIAL / COLETOR LOCAL NÃO TESTADO EM LIVE REAL** | Não há API cloud oficial autorizada para Kwai Brasil (`kwai_requires_collector`). Foi adicionado coletor local Playwright isolado apontando para `127.0.0.1:8786/webhook/kwai`, mas **não foi validado em transmissão real do Kwai** (`platform_events_connected = False` até detectar sala ativa). |
| Persistência SQLite Outbox + Checkpoint Godot | `services/live_bridge/outbox.py`, `game/scripts/race_persistence.gd` | **VALIDADO** | Testes de ACK, replay pós-crash e reserva entre rodadas aprovados (`test_live_reliability.py`, `test_race_persistence.gd`, `test_paid_round_boundary.gd`). |
| Painel Administrativo Web (`/admin`) | `services/live_bridge/admin/{index.html,app.js,styles.css}` | **VALIDADO (FALTA UI DE 3 METAS + AUTH COOKIE)** | `qa_admin_panel.cjs` aprovado em `375 / 768 / 1440 px` com `0` erros de console e zero overflow horizontal. |
| Duas instâncias simultâneas (`TikTok + Kwai`) por 10 min | `tools/run_live_instances.py`, `ABRIR_DUAS_LIVES.cmd` | **NÃO TESTADO POR 10 MIN NESTA SESSÃO** | Plano `--both --check` válido; benchmark real contínuo de 10 minutos + gravação curta será executado na Fase 6 desta sessão. |

---

## 3. Achados Priorizados (P0–P3) para Execução Imediata

- **P1-SEC-01 (`LIVE_BRIDGE_LOCAL_TOKEN` não imposto):** Implementar autenticação local compatível em `server.py` (cookie `HttpOnly; SameSite=Strict` emitido em `/admin` + cabeçalho `X-JOGI-Token` / `Authorization: Bearer` para Godot, ingest e coletor Kwai quando `LIVE_BRIDGE_LOCAL_TOKEN` estiver definido, gerado automaticamente em `run_live_instances.py`).
- **P1-SEC-02 (Janela de DNS Rebinding em `gift_images.py`):** Fixar o IP público validado diretamente no socket TLS (`_PinnedHTTPSConnection` com `server_hostname` preservado para SNI e verificação de certificado) tanto em `gift_images.py` quanto no novo cache efêmero de avatares (`avatar_images.py`).
- **P1-HUD-01 (Desalinhamento horizontal, meta única e poluição inferior em `StadiumHUD`):** Centralizar o sistema de layout em `1080×1920` com margens seguras simétricas, implementar as **3 metas simultâneas independentes** (Curtidas, Presentes, Seguidores 10.000 com distinção honesta entre `+N na live` e baseline manual rotulada), cards transitórios de interação (máx. 2 simultâneos, 1 linha com reticências Unicode, avatar seguro ou iniciais), `TOP 5 · MOEDAS` compacto à direita e 4 cards de habilidades legíveis na base.
- **P2-ART-01 (`2027` pouco legível no Planalto):** Substituir o texto solto pequeno por pórtico/placa arquitetônica discreta e de alto contraste (`BRASÍLIA · PLANALTO` / `2027`) acima da linha de cobertura sem encobrir colunas ou rampa, legível de dia e à noite.
- **P2-REG-01 / P2-REG-02 (Regressões explícitas dos dois P2 anteriores):** Adicionar asserções automatizadas para continuidade lateral na fronteira `49,9 m → 50,0 m` (`test_stadium_art_revision.gd`) e reversão rápida `1 → 2 → 1` sob cooldown (`test_stadium_integration.gd` / `test_race_audio.gd`).
- **P3-DOC-01 (Documentos históricos com dados de fases antigas):** Sinalizar precedência documental e consolidar `docs/AGENT_HANDOFF.md`, `docs/CHECKLIST_ENTREGA.md` e `docs/TESTES_FINAIS.md`.

---

## 4. Varredura de Segredos na Árvore e Histórico

- Varredura executada sobre `HEAD` e commits recentes (`e22a3fa..25d5c3b`): **nenhuma chave privada, token de API (`TRIPO_API_KEY`, `ELEVENLABS_API_KEY`), cookie de sessão ou banco `.sqlite3` encontrado no repositório**.
- Diretórios operacionais em `%LOCALAPPDATA%\JOGI\live_bridge\{tiktok,kwai}` permanecem estritamente fora do repositório e do OneDrive.
