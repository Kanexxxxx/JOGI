# JOGI — Corrida Presidencial 3D (TikTok Live & Kwai)

**Corrida dos Candidatos (JOGI)** é um jogo 3D interativo para transmissões ao vivo contínuas (lives) no **TikTok Live** e no **Kwai**, renderizado no formato vertical **9:16 (1080×1920)** a **60 FPS** utilizando **Godot Engine 4.7.2** e orquestrado por um backend Python assíncrono (`LiveBridge`).

O jogo apresenta uma disputa satírica entre **Lula (13)** e **Flávio Bolsonaro (22)** em uma arena monumental em Brasília com destino ao Palácio do Planalto (2027). A plateia da transmissão controla a corrida em tempo real através de curtidas, comentários de torcida, novos seguidores e presentes virtuais que acionam turbos de velocidade, escudos de proteção, ataques com obstáculos físicos 3D (pilhas de processos judiciais) e super turbos cinematográficos.

---

## 🛠️ Tecnologias Utilizadas

- **Engine de Jogo:** [Godot Engine 4.7.2](https://godotengine.org) (GDScript 2.0 100% estaticamente tipado, renderizador compatível com Direct3D 12/Vulkan, shaders espaciais e canvas_item customizados).
- **Backend & Ponte de Eventos:** Python 3.14 (asyncio, WebSockets, aiohttp, SQLite outbox durável, gerenciador de pacotes `uv`).
- **Painel Administrativo Web:** HTML5, CSS3 moderno (dark theme, grid responsivo, `tabular-nums`), JavaScript ES2022 nativo (sem dependência de frameworks ou build steps pesados).
- **Automação & Testes:** `gda` (Godot Agent CLI), `pytest`, Playwright (E2E headless de interface).
- **Modelagem & Arte 3D:** Modelos 3D estilizados com rigging de 65 ossos (`api-cape-v13`), física visual de tecido para capas (`cape-motion-v1`), pista azul-cobalto e arquitetura estilizada do Palácio do Planalto (`planalto_v2.glb`).
- **Áudio:** Síntese e mixagem local com barramentos dedicados, ducking inteligente para narração e sonoplastia para eventos da corrida.

---

## 📁 Estrutura de Pastas do Projeto

```
JOGI/
├── ABRIR_PREVIA_JOGO.cmd         # Execução rápida do jogo local sem conectar em contas
├── ABRIR_TIKTOK.cmd              # Inicia backend TikTok (porta 8765) + janela Godot
├── ABRIR_KWAI.cmd                # Inicia backend Kwai (porta 8766) + janela Godot
├── ABRIR_DUAS_LIVES.cmd          # Inicia ambas as instâncias isoladas simultaneamente
├── INICIAR_JOGO.md               # Instruções detalhadas de operação das lives
├── CONTINUIDADE.md               # Guia vivo de estado e regras de transição entre IAs
├── SECURITY.md                   # Diretrizes de segurança, anti-SSRF e privacidade
│
├── game/                         # Projeto Godot 4.7.2
│   ├── project.godot             # Configuração da engine (1080x1920 vertical, viewport)
│   ├── assets/                   # Modelos 3D (.glb), texturas, retratos, fontes Nunito
│   ├── scenes/main/              # Cena principal: stadium_race.tscn
│   ├── scripts/                  # Código GDScript da arena, HUD, corredores e barramento
│   │   ├── stadium_race.gd       # Coordenador da corrida e do ciclo de rodadas
│   │   ├── stadium_hud.gd        # HUD de transmissão 9:16 simétrico e desacoplado
│   │   ├── stadium_world.gd      # Arena 3D em profundidade, iluminação e Planalto 2027
│   │   ├── audience_director.gd  # Gestão de participantes, rankings e contadores
│   │   ├── live_event_bus.gd     # Cliente WebSocket bidirecional para o LiveBridge
│   │   ├── gift_visual_cache.gd  # Cache seguro de ícones de presentes observados
│   │   └── avatar_visual_cache.gd# Cache local de fotos de perfil de espectadores
│   └── tests/                    # Suíte de testes unitários e de integração do Godot
│
├── services/live_bridge/         # Backend Python e servidores locais
│   ├── server.py                 # Servidor HTTP/WS (portas 8765/8766) em 127.0.0.1
│   ├── protocol.py               # Validação de envelopes de eventos e schemas JSON
│   ├── live_goal.py              # Gestão persistente de metas (curtidas, presentes, 10k seguidores)
│   ├── gift_images.py            # Download e cache anti-SSRF com DNS pinning para presentes
│   ├── avatar_images.py          # Download e cache anti-SSRF com DNS pinning para avatares
│   ├── adapters/                 # Conectores de live (TikTokLiveAdapter, KwaiLiveAdapter, Simulador)
│   └── admin/                    # Painel web de controle da transmissão (/admin)
│
├── tools/                        # Ferramentas de suporte, supervisores e testes de QA
│   ├── run_live_instances.py     # Supervisor de instâncias isoladas com health check
│   ├── live_supervisor.py        # Supervisor com reinício automático de processos
│   └── qa_admin_panel.cjs        # Suíte de testes Playwright para o painel web
│
└── docs/                         # Documentação viva e auditorias do projeto
    ├── AGENT_HANDOFF.md          # Registro cronológico detalhado de handoff entre IAs
    ├── AGENTE_RETOMADA_PROMPT_MESTRE_2026-10-24.md # Prompt mestre de requisitos
    ├── ESTADO_ATUAL.md           # Resumo factual do estado atual
    ├── referencias/              # PNG de referência visual do HUD e especificações
    └── evidencias/               # Capturas de tela e evidências de testes
```

---

## ⚡ Funcionalidades Já Implementadas

1. **Ciclo de Corrida e Rodadas Automáticas**:
   - 50 rodadas de 600 segundos (10 minutos) por ciclo.
   - Apuração do vencedor por maior distância acumulada ao zerar o cronômetro.
   - Intervalo de 30 segundos (3s chegada/comemoração + 24s pódio + 3s contagem).
   - Acúmulo de vitórias do ciclo (`C01 · VITÓRIAS X×Y`) e reinício automático de ciclo após a 50ª rodada.
2. **Mecânica de Participação e Efeitos**:
   - Votos por comentário (`13` para Lula, `22` para Flávio) com cooldown por usuário.
   - Presentes categorizados em 4 ações: Impulso (Turbo), Escudo (bloqueia ataques), Ataque (gera pilhas de processos judiciais na raia do rival) e Super Turbo cinematográfico.
   - Reserva de efeitos: presentes doados durante pódio/chegada somam ao ranking na hora e têm o efeito mecânico reservado para a largada seguinte.
3. **Redesign do HUD de Transmissão (9:16)**:
   - Layout simétrico centralizado (`x = 42..1038`), preservando a faixa central para a pista 3D e desimpedindo a faixa inferior (`y = 1720..1920`) para a interface nativa dos aplicativos de live.
   - Três metas independentes no topo: **Curtidas**, **Presentes** (unidades ou moedas) e **Seguidores** (meta de 10.000 com fonte honesta: sessão vs. baseline manual).
   - Cards transitórios de espectador com avatar circular, `@handle` com truncamento UTF-8 seguro para emojis ZWJ e chip de equipe apenas quando há escolha real.
   - Painel `TOP 5 · MOEDAS` compacto que colapsa quando vazio e destaca os 3 maiores apoiadores no pódio.
4. **Palácio do Planalto e Identificação de 2027**:
   - Brasão arquitetônico de alto contraste com iluminação integrada, tornando o ano "2027" claramente legível acima da cobertura do palácio, tanto nas rodadas diurnas quanto noturnas.
5. **Segurança e Isolamento**:
   - Servidores fixados em `127.0.0.1` com autenticação local (`LIVE_BRIDGE_LOCAL_TOKEN`), cookies HttpOnly `SameSite=Strict` e proteção de produtor (`LIVE_BRIDGE_PRODUCER_TOKEN`).
   - Download de imagens com DNS pinning anti-SSRF, bloqueio de loopback/IPs privados e validação estrita de MIME.
   - Recuperação durável de estado após crash via outbox SQLite e checkpoints periódicos.

---

## 🚀 Como Instalar Dependências e Executar

### Pré-requisitos
- **Windows 10/11**
- **Godot Engine 4.7.2** instalado (executáveis em `C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\`)
- **Python 3.14** e ferramenta `uv` instalada em `C:\Users\Kanex\.local\bin\uv.exe`
- **Node.js** (para scripts de teste Playwright)

### 1. Prévia Local do Jogo (Sem Conexões Externas)
Para visualizar o jogo, HUD, pista e movimentação sem conectar a lives:
- Execute com duplo clique no arquivo **`ABRIR_PREVIA_JOGO.cmd`**
- Ou via PowerShell:
```powershell
& "C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\Kanex\OneDrive\Desktop\JOGI\game"
```

### 2. Iniciar Sessão TikTok Live
Inicia o backend dedicado do TikTok na porta `8765` e abre a janela do Godot conectada:
- Execute com duplo clique no arquivo **`ABRIR_TIKTOK.cmd`**
- Painel Administrativo Web: `http://127.0.0.1:8765/admin`

### 3. Iniciar Sessão Kwai Live
Inicia o backend dedicado do Kwai na porta `8766` e abre a janela do Godot conectada:
- Execute com duplo clique no arquivo **`ABRIR_KWAI.cmd`**
- Painel Administrativo Web: `http://127.0.0.1:8766/admin`
- *Nota:* O coletor de eventos reais do Kwai está em fase de homologação local (ver detalhes em [services/live_bridge/KWAI_EVENTOS_PENDENTES.md](services/live_bridge/KWAI_EVENTOS_PENDENTES.md)).

### 4. Iniciar Ambas as Instâncias Simultaneamente
Para executar as transmissões de TikTok e Kwai simultaneamente com supervisão:
- Execute com duplo clique no arquivo **`ABRIR_DUAS_LIVES.cmd`**
- Ou via script Python:
```powershell
& "services\live_bridge\.venv\Scripts\python.exe" tools/run_live_instances.py --both
```

---

## 🧪 Como Executar os Testes Automatizados

### Testes do Backend Python (pytest)
```powershell
& "services\live_bridge\.venv\Scripts\python.exe" -m pytest services/live_bridge tools -q -p no:cacheprovider
```

### Verificação de Integridade das Instâncias
```powershell
& "services\live_bridge\.venv\Scripts\python.exe" tools/run_live_instances.py --both --check
```

### Testes de Interface do Painel Web (Playwright)
```powershell
node tools/qa_admin_panel.cjs
```

### Validação de Scripts e Cenas no Godot (via GDA CLI)
```powershell
$env:GDA_GODOT = "C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
& "C:\Users\Kanex\.local\bin\gda.exe" project scan --project game --json
& "C:\Users\Kanex\.local\bin\gda.exe" scene validate res://scenes/main/stadium_race.tscn --project game --json
& "C:\Users\Kanex\.local\bin\gda.exe" scene preflight res://scenes/main/stadium_race.tscn --project game --json
```

### Executar Testes Headless do Godot
```powershell
$godot = "C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path game --script res://tests/test_hud_redesign_goals_avatars.gd
& $godot --headless --path game --script res://tests/test_rounded_hud.gd
& $godot --headless --path game --script res://tests/test_stadium_hud.gd
& $godot --headless --path game --script res://tests/test_stadium_art_revision.gd
& $godot --headless --path game --script res://tests/test_audience_director.gd
& $godot --headless --path game --script res://tests/test_gift_visual_cache.gd
& $godot --headless --path game --script res://tests/test_round_cycle.gd
& $godot --headless --path game --script res://tests/test_paid_round_boundary.gd
& $godot --headless --path game --script res://tests/test_race_persistence.gd
& $godot --headless --path game --script res://tests/test_race_audio.gd
```

---

## 📌 Documentação de Continuidade e Arquitetura

Para detalhes aprofundados sobre regras de negócio, contratos de dados e histórico de desenvolvimento:

- [CONTINUIDADE.md](CONTINUIDADE.md) — Guia mestre de continuidade e transição entre agentes.
- [docs/AGENT_HANDOFF.md](docs/AGENT_HANDOFF.md) — Tabela cronológica de entregas e tarefas pendentes.
- [docs/ESTADO_ATUAL.md](docs/ESTADO_ATUAL.md) — Diagnóstico factual detalhado do projeto.
- [docs/AGENTE_RETOMADA_PROMPT_MESTRE_2026-10-24.md](docs/AGENTE_RETOMADA_PROMPT_MESTRE_2026-10-24.md) — Requisitos originais do prompt mestre.
- [docs/referencias/HUD_REFERENCIA.md](docs/referencias/HUD_REFERENCIA.md) — Referência visual conceitual do HUD e diretrizes de design.

---

## ⚠️ Pendências Conhecidas e Próximos Passos

1. **Coletor Oficial Kwai Live:** O adaptador passivo local funciona por webhook, mas depende de um coletor autorizado de live room para Kwai Brasil (ver [KWAI_EVENTOS_PENDENTES.md](services/live_bridge/KWAI_EVENTOS_PENDENTES.md)).
2. **Validação em Live Pública Real:** O TikTok Live está preparado via SDK oficial com testes locais aprovados, pendente de teste em sala de live pública real.
3. **Benchmark Prolongado de 10 Minutos e Captura OBS:** Executar o ensaio contínuo de 10 minutos com ambas as instâncias 1080×1920 ativas simultaneamente com medição de hardware e teste de gravação de áudio/vídeo no OBS.
4. **Finalização da Suíte de Integração Godot:** Ajustar o caso de teste `test_stadium_integration.gd` com o payload de `set_live_goals`.
