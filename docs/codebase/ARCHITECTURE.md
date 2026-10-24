# Arquitetura observada — 23/10/2026

## 1) Estilo e restrições

Sistema orientado a eventos, em processos locais separados: backend Python, jogo Godot e browser administrativo. O cliente Godot conecta ao WebSocket local; o backend valida e limita envelopes antes de encaminhá-los. Restrição de rede: loopback. Saída de vídeo: 9:16. As bibliotecas de plataforma ficam no lado Python.

## 2) Fluxo

```text
simulator.py ou admin → LiveBridgeServer → protocol.py → LRU/filas/token bucket
 → /ws/godot → LiveEventBus → sinais → RaceMain/CandidateRunner
 → telemetria → LiveBridgeServer → /ws/admin ou /api/state → app.js
```

1. Ingestão recebe envelopes na rota `/ws/ingest`, ou comandos/simulações nas rotas admin.
2. Protocolo valida campos, origens e tipos; nomes passam por sanitização.
3. Backend deduplica IDs, distribui prioridades e limita despacho, por padrão a 40 eventos/s.
4. LiveEventBus valida/deduplica novamente e emite sinais tipados.
5. RaceMain aplica regras e CandidateRunner atualiza movimento/efeitos; câmera e HUD apresentam a corrida.
6. Telemetria retorna a 10 Hz no código do jogo; painel recebe estado por WebSocket ou HTTP.

## 3) Responsabilidades

| Módulo | Controla | Não executa | Evidência |
|---|---|---|---|
| protocol.py | Contrato, sanitização, builders, LRU, token bucket | Renderização | `services/live_bridge/protocol.py` |
| server.py | HTTP/WS, filas, comandos e clientes | Captura TikTok/Kwai no inicializador atual | `services/live_bridge/server.py` |
| LiveEventBus | Transporte e tradução para sinais | Geometria | `game/scripts/live_event_bus.gd` |
| RaceMain | Estados, arena procedural, HUD, ataques e telemetria | SDK de live | `game/scripts/race_main.gd` |
| CandidateRunner | Movimento, corpo procedural e efeitos | HTTP | `game/scripts/candidate_runner.gd` |
| Admin | Comandos, visualização e simulação própria | Física real da cena | `services/live_bridge/admin/app.js` |

## 4) Padrões reutilizados

Autoload/singleton para LiveEventBus; sinais Godot para comandos/eventos; interface BaseLiveAdapter para fontes; deduplicação LRU nas duas pontas; filas prioritárias e token bucket no servidor; geometria procedural e reciclagem de pista. A pista tem oito chunks de 40 m.

## 5) Riscos arquiteturais

RaceMain concentra arena, HUD e regras num arquivo grande. Backend e painel também concentram responsabilidades. Não há persistência de estado identificada. O painel tem uma simulação adicional que altera fases e distâncias independentemente da fonte real. O reinício de partida não está habilitado por padrão. Pooling de obstáculos prometido em ARCHITECTURE não equivale à implementação encontrada: spawn cria nós e usa queue_free.

O contrato JSON ilustrativo e a árvore de módulos de `../../ARCHITECTURE.md` descrevem intenção histórica. Para execução, seguir `protocol.py` e `live_event_bus.gd`. [TODO] Unificar a especificação e o contrato em uma próxima implementação.

## 6) Evidências

`game/project.godot`; `game/scripts/*.gd`; `services/live_bridge/{protocol,server}.py`; `services/live_bridge/adapters/base.py`; `services/live_bridge/admin/app.js`; `ARCHITECTURE.md` da raiz.
