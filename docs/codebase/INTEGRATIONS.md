# Integrações observadas — 23/10/2026

## 1) Inventário

| Sistema | Tipo / finalidade | Autenticação / estado | Importância | Evidência |
|---|---|---|---|---|
| Godot ↔ LiveBridge | WS loopback, eventos e telemetria | Sem token verificado no servidor atual; teste E2E passou | Alta | server.py, live_event_bus.gd |
| Painel ↔ LiveBridge | HTTP + WS, controles/estado | Host/Origin restringidos a loopback | Alta | server.py, admin/app.js |
| Simulador | Eventos sintéticos locais | Sem conta externa | Alta para desenvolvimento | simulator.py, adapters/simulator_adapter.py |
| TikTok | Adaptador opcional de biblioteca de terceiros | Import opcional; não iniciado pela CLI | Futuro | adapters/tiktok_adapter.py, pyproject.toml |
| Kwai | Webhook passivo 127.0.0.1:8766 | Desativado por padrão; fonte externa não implementada | Futuro | adapters/kwai_adapter.py |
| Tripo | Pipeline de arte previsto | Não exercitado; não é dependência de runtime | Desenvolvimento | ART_DIRECTION.md |

As alegações antigas sobre disponibilidade de APIs de plataforma não foram tratadas como fatos atuais: este mapa verifica a implementação local. Nenhuma conexão de live real foi testada.

## 2) Dados e armazenamento

LRU, filas, telemetria e contadores permanecem em memória no servidor; cache de IDs também em memória no Godot. Não foi identificada integração de banco/ORM ou armazenamento persistente de rodadas. Risco: reiniciar processos perde o estado; não há recuperação durável demonstrada. Evidência: protocol.py, server.py, live_event_bus.gd e manifesto de dependências.

## 3) Credenciais

`.env.example` contém nomes e exemplos de configuração; `.gitignore` exclui segredos. O servidor atual não carrega nem valida LIVE_BRIDGE_LOCAL_TOKEN, embora SECURITY o exija. Token bucket é controle de taxa, não autenticação. [TODO] Definir ciclo de sessão/autorização local e a forma de configuração antes de conexão real. Nenhuma autenticação Tripo/TikTok/Kwai foi verificada.

## 4) Falhas e reconexão

LiveEventBus tem reconexão exponencial, atraso de 1 a 15 s e máximo de dez pacotes por frame. Servidor tem ping_interval 10 s, ping_timeout 20 s, quadros até 8192 bytes, filas limitadas e token bucket. Painel alterna WS/HTTP; sua simulação própria pode aparentar atividade sem refletir o motor. TikTok tem backoff no adaptador; comportamento real depende da biblioteca e live, não validados.

## 5) Observabilidade

Servidor registra logs e métricas accepted/invalid/duplicates/dispatched; adaptadores fornecem stats; motor envia estado/competidores; painel exibe conexão e contadores. Não foi identificado APM/tracing externo. O painel escreve literalmente `Conectado (60 FPS)` em app.js: isso não é medição de FPS. [TODO] Medir FPS e latência reais.

## 6) Evidências

`services/live_bridge/{server,protocol,simulator}.py`; `services/live_bridge/adapters/*.py`; `services/live_bridge/admin/{app.js,CONTRACT.md}`; `services/live_bridge/pyproject.toml`; `game/scripts/live_event_bus.gd`; `.env.example`; `SECURITY.md`.
