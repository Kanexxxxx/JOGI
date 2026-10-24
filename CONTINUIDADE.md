# CONTINUIDADE.md — Estado Atual do Projeto e Guia de Retomada

**Última atualização**: 2026-10-24 — checkpoints contínuos de segurança, painel 3 metas e redesign do HUD 9:16 (ver [docs/AGENT_HANDOFF.md](docs/AGENT_HANDOFF.md)).

## Estado vigente

Leia primeiro [RETOMADA_IA_2026-10-24.md](RETOMADA_IA_2026-10-24.md), [docs/AGENT_HANDOFF.md](docs/AGENT_HANDOFF.md), [docs/AGENTE_RETOMADA_PROMPT_MESTRE_2026-10-24.md](docs/AGENTE_RETOMADA_PROMPT_MESTRE_2026-10-24.md), [docs/referencias/HUD_REFERENCIA.md](docs/referencias/HUD_REFERENCIA.md) (PNG conceitual oficial: [docs/referencias/hud-conceito-chatgpt-2026-10-24.png](docs/referencias/hud-conceito-chatgpt-2026-10-24.png)), [docs/ESTADO_ATUAL.md](docs/ESTADO_ATUAL.md) e [INICIAR_JOGO.md](INICIAR_JOGO.md). Esses arquivos prevalecem sobre todo o histórico abaixo.

- A cena principal agora é `game/scenes/main/stadium_race.tscn`: câmera atrás dos dois corredores, pista azul-cobalto solicitada pelo usuário, arquibancadas nos dois lados e Palácio do Planalto local em 3D.
- Capas têm ondulação limitada ao tecido, sincronizada com velocidade/turbo/reação e congelada na pausa; derivações locais preservam os modelos aprovados. Testes e revisão independente passaram. Ver `docs/CAPAS_MOVIMENTO.md`.
- Corrida real com 50 rodadas de 600 segundos, chegada/comemoração, reação de impacto, comentários 13/22, Top 5 de presentes, Top 3 no intervalo e meta configurável. Modelos aprovados preservados.
- Presentes recebidos após o fim têm ranking imediato e efeitos reservados para a próxima largada, incluindo recuperação pelo journal/checkpoint. Contrato: `docs/PRESENTES_ENTRE_RODADAS.md`.
- Painel validado em 375/768/1440 px; API/backend e watchdog têm testes. Sessões TikTok/Kwai usam portas e armazenamento separados. Atalhos locais disponíveis na raiz.
- **Pendências reais**: coletor de eventos Kwai, prova de presentes reais no TikTok, imagem/áudio no OBS, escuta humana das vozes e ensaio contínuo de 32 horas. O usuário confirmou que ambas as contas permitem live/presentes; não perguntar isso novamente.
- Controle de janelas nativas indisponível no último teste desta sessão. Nenhuma transmissão foi iniciada.

## Histórico anterior à arena atual — não usar como estado vigente

### Retomada histórica da bancada

- **Direção de qualidade posterior à bancada**: usuário rejeitou a adaptação dos bonecos e escolheu Brasília estilizada/arena brasileira. CLI0.7.3 e API1.000cr verificados; Lula e Flávio receberam rigv3.0/65ossos e corrida sobre os GLBs originais,70cr no total, **saldo930/frozen0 confirmado**. Mapas4K preservados; nenhuma regeneração de rosto. Capa precisa de correção local de pesos; Lula candidato `tripo-cape-fixed-v13`, Flávio em ajuste. Fonte exata/IDs/pendências em `docs/RETOMADA_QUALIDADE_API.md`.
- Arena Blender e novo HUD/câmera existem em `game/scenes/characters/brasilia_showcase.tscn`; é prévia visual, ainda sem resultados/eventos reais. Ciclo50x600s implementado no RaceMain e aprovado em revisão independente após correção da fronteira de empate. A integração da nova apresentação à corrida continua em execução.
- A intenção vigente está em `BRIEFING_RETOMADA.md`: Lula vs **Flávio Bolsonaro**, rodadas por tempo (inicialmente dez minutos), 50 por ciclo, duas sessões isoladas TikTok/Kwai. Prazo informado: 24/10 às 09h.
- Os GLBs exportados foram preservados; cópias locais agora têm rig experimental de 19 ossos e clipes espera/corrida/turbo. A bancada abre por `ABRIR_BANCADA_PERSONAGENS.cmd`. Relatório e evidências: `docs/BANCADA_PERSONAGENS.md`.
- Versão atual de bancada: `rig-preview-v7` / `game/assets/characters/preview-v7`. Testes GDA/importação/contrato passaram. Ensaio isolado de 10 segundos em 1080×1920: média 60,01 FPS; não é teste com duas lives, pista ou OBS.
- A bancada inicial local não consumiu créditos; a prova API posterior consumiu70 conforme atualização acima. Studio580 informado é reserva separada da API. Derivados são experimentais e não alteram os originais.
- Próximo passo: integrar apresentação e animações ao runner, acertar escala/orientação/solo e testar na câmera da pista. **A corrida principal ainda usa os visuais procedurais do histórico.** Quedas, ataques e transformações não estão animados.
- Conexão real de presentes TikTok/Kwai, isolamento, ciclo de 50, persistência/recuperação e ensaio prolongado continuam pendentes. O histórico de testes abaixo não comprova esses requisitos.

## Histórico de 18/10 — implementação anterior

---

## 1. Resumo Executivo: Redirecionamento Definitivo do JOGI

O projeto foi corrigido em conformidade com a visão original do produto:
1. **Disputa Política Satírica (2 Competidores)**:
   - **Slot #1**: **Lula** (`#FF3B5C`, Vermelho Coral), cabeça arredondada, cabelo grisalho ondulado e **barba cheia branca procedural**.
   - **Slot #2**: **Bolsonaro** (`#00A8FF`, Azul Elétrico), cabelo partido de lado, sem barba, terno escuro e **faixa presidencial verde-amarela diagonal**.
   - Eliminados todos os corredores genéricos/abstratos residuais.
2. **Pista Infinita com Reciclagem Procedural (Chunk Recycling)**:
   - Eliminado o pórtico fixo de 100m.
   - Pista infinita modular composta por 8 chunks de 40m (`total_span = 320m`). Conforme os corredores avançam em `-Z`, chunks que ficam 50m atrás do líder são reposicionados 320m à frente, permitindo corrida ininterrupta.
3. **Cronômetro da Partida de 5 Minutos (300 segundos)**:
   - A partida possui duração contínua de 5 minutos configurável.
   - Ao término do cronômetro, a corrida transiciona para a apuração final e vence quem tiver percorrido a **maior distância acumulada**.
4. **Mecânica de Presentes Satíricos & Ataques Cruzados**:
   - **Tier 1 (Rosa Impulso)**: Turbo de velocidade (`+3.5 m/s`).
   - **Tier 2 (Rosquinha Blindada)**: Escudo protetor azul/dourado por 5s.
   - **Tier 3 (Pilha de Processos)**: **Ataque Político**: Gera obstáculos físicos 3D (pilha de documentos judiciais) na raia do oponente. Se o adversário não tiver escudo ativo, sofre tropeço e perde velocidade; se tiver escudo, o impacto é absorvido sem perda de rendimento.
   - **Tier 4 (Super Comício)**: Super Turbo (`+8.0 m/s`) + Escudo Completo.
5. **HUD 2D Limpo e Vertical 9:16 (`CanvasLayer`)**:
   - **Remoção física de 100% dos `Label3D`** dos personagens, eliminando a poluição visual no centro da pista 3D.
   - Placar 2D com cronômetro, telemetria individual, botões interativos e **Barra Central Tug-of-War** com exibição dinâmica de vantagem (`🚩 +35.4m LULA NA FRENTE` ou `🚩 +22.1m BOLSONARO NA FRENTE`).
6. **Painel Administrativo Broadcast Control Room (`admin/`)**:
   - Interface web dark theme (`index.html`, `styles.css`, `app.js`) com controle da partida, monitoramento dos 2 competidores, botões de ação rápida (Turbo, Escudo e Atacar com Processo), simulador de eventos da live e feed de eventos em tempo real.

---

## 2. Mapa de Arquivos do Projeto

### 2.1 Backend e Conectores (`services/live_bridge/`)
- `protocol.py`: Contrato formal de envelopes, validação de schema, aliases de votos para Lula (#1, lula, 13) e Bolsonaro (#2, bolsonaro, 22), tracker de presentes e envelope de ataque `build_attack_envelope`.
- `server.py`: Servidor unificado assíncrono (WebSocket nas rotas `/ws/godot`, `/ws/admin`, `/ws/ingest` e HTTP REST nas rotas `/api/state`, `/api/admin/command`, `/api/admin/simulate`, `/admin/`), bind exclusivo em `127.0.0.1:8765`, token bucket e broadcast de telemetria.
- `simulator.py`: `MockLiveEventSimulator` determinístico com torcedores temáticos de Lula e Bolsonaro, suportando modos `calm`, `normal`, `viral`, `burst` e `chaos_fuzz`.
- `test_e2e_runner.py`: Script de teste automatizado ponta a ponta que sobe o servidor, executa o Godot headless via GDA e injeta eventos simulados.
- `adapters/base.py`: Classe abstrata `BaseLiveAdapter` para conectores de plataforma.
- `adapters/simulator_adapter.py`: Adaptador do simulador integrado para operação offline.
- `adapters/tiktok_adapter.py`: Conector para TikTok LIVE (via `TikTokLive`), com fallback gracioso quando desativado.
- `adapters/kwai_adapter.py`: Conector seguro para Kwai LIVE (passivo em loopback).
- `adapters/test_adapters.py`: 15 testes unitários cobrindo todos os adaptadores.
- `test_live_bridge.py`: 12 testes cobrindo rotas HTTP, WebSockets, deduplicação LRU e segurança Zero-Trust.

### 2.2 Godot Engine 4.7 (`game/`)
- `project.godot`: Resolução vertical `1080x1920` (9:16), stretch mode `canvas_items`, autoload `LiveEventBus` (`res://scripts/live_event_bus.gd`).
- `scripts/candidate_runner.gd`: Controlador 3D dos corredores com silhuetas caricatas procedurais distintas (barba cheia de Lula, faixa presidencial de Bolsonaro), acumulação contínua de distância, boost, escudo, tropeço e zero `Label3D`.
- `scripts/race_main.gd`: Gerenciador da corrida, 2 raias (`x = -1.4` e `x = +1.4`), reciclagem de 8 chunks de pista modular, spawn dinâmico de pilhas de documentos 3D, cronômetro de 5 minutos, apuração de vencedor por distância acumulada e HUD 2D Tug-of-War.
- `scripts/race_camera.gd`: Câmera vertical 9:16 suave centralizada nos competidores.
- `scripts/live_event_bus.gd`: Barramento com deduplicação LRU (2000 eventos), reconexão exponencial, sinal de ataque `candidate_attack_requested` e envio de telemetria bidirecional via WebSocket.
- `scenes/main/race_main.tscn`: Cena principal 3D da corrida.
- `tests/test_lula_vs_bolsonaro.gd`: Teste automatizado headless validando o elenco de 2 corredores, ausência de Label3D, corrida contínua, boost de Lula, ataque de processos a Bolsonaro, defesa com escudo e término por tempo.
- `tests/test_fase3_admin_telemetry.gd`: Teste dos comandos administrativos e telemetria.
- `tests/test_race_prototype.gd`: Teste da mecânica central e reinício.
- `tests/test_live_bridge_e2e.gd`: Teste de integração Godot + LiveBridge via WebSocket.

### 2.3 Painel Administrativo Web (`services/live_bridge/admin/`)
- `index.html`: Layout Broadcast Control Room com cartões de Lula e Bolsonaro, botões de ação rápida (Turbo, Escudo, Atacar), simulador completo e telemetria.
- `styles.css`: Estilização dark theme (#0B0E17, #111625, #1E293B) com `tabular-nums` e design responsivo.
- `app.js`: Conexão WebSocket com fallback HTTP, sincronização do Tug-of-War, despacho de ataques e simulação local de 5 minutos.
- `CONTRACT.md`: Especificação dos contratos REST e WebSocket do painel.

---

## 3. Matriz de Qualidade e Testes Automatizados

| Camada de Validação | Comando / Ferramenta | Resultado | Status |
|---|---|---|---|
| **Python Unit & Integration** | `uv run pytest services/live_bridge` | 27 testes aprovados em 21.71s | ✅ **100% PASSED** |
| **GDA Script Validate** | `gda script validate --all` | 8/8 scripts `.gd` válidos, zero diagnósticos | ✅ **100% PASSED** |
| **GDA Scene Validate** | `gda scene validate race_main.tscn` | Cena 100% íntegra, referências `res://` válidas | ✅ **100% PASSED** |
| **GDA Scene Preflight** | `gda scene preflight race_main.tscn` | Inicialização limpa de nós e dependências | ✅ **100% PASSED** |
| **GDA Headless Suite (Lula vs Bolsonaro)** | `gda script run test_lula_vs_bolsonaro.gd --strict` | Todos os asserts satíricos e de corrida infinita passaram | ✅ **100% PASSED** |
| **GDA Headless Suite (Telemetria)** | `gda script run test_fase3_admin_telemetry.gd --strict` | Comandos administrativos e telemetria validados | ✅ **100% PASSED** |
| **GDA Headless Suite (Protótipo)** | `gda script run test_race_prototype.gd --strict` | Regressão de física e movimentação aprovada | ✅ **100% PASSED** |
| **Integração E2E (Godot + Python)** | `uv run python services/live_bridge/test_e2e_runner.py` | Conexão WebSocket, telemetria e aplicação de eventos confirmados | ✅ **100% PASSED** |

---

## 4. Como Executar o Projeto Localmente

### 4.1 Iniciar o Servidor Backend (Live Bridge & Painel Admin)
No PowerShell:
```powershell
cd C:\Users\Kanex\OneDrive\Desktop\JOGI\services\live_bridge
C:\Users\Kanex\.local\bin\uv.exe run python server.py
```
- Painel Administrativo disponível em: `http://127.0.0.1:8765/admin/`
- WebSocket do Godot: `ws://127.0.0.1:8765/ws/godot`
- WebSocket de Ingestão: `ws://127.0.0.1:8765/ws/ingest`

### 4.2 Executar o Jogo no Godot 4.7.2
No PowerShell:
```powershell
& "C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path "C:\Users\Kanex\OneDrive\Desktop\JOGI\game"
```
O jogo abrirá na resolução vertical 9:16 (`1080x1920`, com janela de pré-visualização dimensionada), conectará automaticamente ao LiveBridge local e iniciará a contagem regressiva da corrida Lula vs. Bolsonaro.

### 4.3 Disparar o Simulador de Eventos da Live (Opcional)
Em outro terminal:
```powershell
C:\Users\Kanex\.local\bin\uv.exe run --project C:\Users\Kanex\OneDrive\Desktop\JOGI\services\live_bridge python simulator.py --mode normal --count 50
```
