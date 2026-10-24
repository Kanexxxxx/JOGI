# Estrutura observada — 23/10/2026

## 1) Mapa principal

| Caminho | Responsabilidade | Evidência |
|---|---|---|
| `game/` | Jogo Godot | `project.godot` |
| `game/scripts/` | Quatro scripts de produto | race_main, candidate_runner, race_camera, live_event_bus |
| `game/scenes/main/` | Cena principal | `race_main.tscn` |
| `game/tests/` | Quatro scripts headless | `test_*.gd` |
| `services/live_bridge/` | Backend, protocolo, simulador e testes | `server.py`, `protocol.py`, `simulator.py` |
| `services/live_bridge/adapters/` | Interfaces e fontes de eventos | base, simulator_adapter, tiktok_adapter, kwai_adapter |
| `services/live_bridge/admin/` | Painel estático e contrato | index.html, styles.css, app.js, CONTRACT.md |
| `.agents/` | Infraestrutura de agentes para desenvolvimento | agents, skills, rules, workflows, plugins, reports |
| Documentos da raiz | Especificação e histórico | GAME_DESIGN, ARCHITECTURE, DESIGN, ART_DIRECTION, INTEGRATIONS, TESTING, SECURITY, CONTINUIDADE |
| `docs/codebase/` | Mapa técnico gerado nesta inspeção | Sete documentos e inventário do scanner |

## 2) Entradas

O Godot abre `res://scenes/main/race_main.tscn`, definido em `game/project.godot`, com LiveEventBus autoload. Python inicia em `server.py:main`; `simulator.py` é um cliente CLI separado. O browser recebe `/admin/` do mesmo servidor em 127.0.0.1:8765. O runner E2E inicia e encerra seu próprio servidor.

## 3) Fronteiras

| Módulo | Conteúdo observado | Limite de responsabilidade |
|---|---|---|
| Godot | Simulação, visualização, estado e sinais | Não captura diretamente as plataformas |
| LiveBridge | Validação, filas, transporte e telemetria | Não renderiza o jogo |
| Adaptadores | Convertem eventos brutos em envelopes | Não são iniciados pela CLI atual do servidor |
| Admin | Interface, comandos, apresentação e simulação local | A simulação visual atual não comprova estado do Godot |
| `.agents/` | Instruções e automação de desenvolvimento | Não é dependência de runtime do jogo |

## 4) Organização e Git

Arquivos seguem snake_case em Python/GDScript; documentos principais são UPPERCASE.md. Godot usa `res://` relativo a **game/**, e não à raiz JOGI. `.godot`, `.venv`, caches e `.uid` são artefatos/identificadores de ferramenta, não novas funcionalidades.

Git: raiz local JOGI; branch master sem commits e sem remotes. Muitos documentos/ferramentas já staged; game/ e services/ não rastreados no estado encontrado. Não foi feito add, commit, reset ou mudança de branch. [TODO] Localizar eventual cópia histórica fora desta pasta, se existir; não há endereço recuperável pelo Git local.

O scanner genérico inclui muitas ferramentas de `.agents/` e não reconhece bem a stack aninhada; suas métricas não representam apenas código do jogo. A leitura manual dos dois módulos corrige essa limitação.

## 5) Evidências

`game/project.godot`; `game/scenes/main/race_main.tscn`; `services/live_bridge/server.py`; `.gitignore`; `.codebase-scan.txt`; comandos `git status --short`, `git remote`, `git log`, `git rev-parse --show-toplevel`.
