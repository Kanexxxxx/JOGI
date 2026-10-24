# LiveBridge (`services/live_bridge/`) — Corrida dos Candidatos (JOGI)

Ponte WebSocket local (`127.0.0.1:8765`), sanitizador *Zero-Trust*, deduplicador LRU (`10.000` chaves), limitador *Token Bucket* (`40 msg/s`) e simulador determinístico de eventos (`MockLiveEventSimulator`) para o jogo 3D **Corrida dos Candidatos** (Godot 4.7.2).

---

## 1. Arquitetura e Segurança

- **Isolamento Estrito de Rede (Loopback Only)**: O servidor vincula-se exclusivamente a `127.0.0.1:8765`. Qualquer tentativa de bind em `0.0.0.0` ou interface externa levanta `SecurityBindError`.
- **Rotas WebSocket**:
  - `ws://127.0.0.1:8765/ws/godot` — Rota consumida pelo singleton `LiveEventBus` no Godot 4.7.2.
  - `ws://127.0.0.1:8765/ws/ingest` — Rota de ingestão local usada pelo `MockLiveEventSimulator` (e futuros adaptadores TikTok LIVE / Kwai LIVE).
- **Defesa em Profundidade (`protocol.py`)**:
  - Validação estrita do contrato `LiveEventEnvelope` (`schema_version = "1.0"`, limite de `8192 bytes` por frame).
  - Sanitização *Zero-Trust* de `display_name`: normalização `NFKC`, remoção de tags BBCode/colchetes (`[`, `]`), caracteres de controle C0/C1, invisíveis (`Zero-Width`) e overrides bidirecionais (`RTL`), truncado em `24` caracteres.
  - Deduplicação idempotente LRU (`10.000` chaves, TTL `15m`) por `event_id`.
  - Filas prioritárias `P0` (presentes/admin), `P1` (votos/shares) e `P2` (lotes de curtidas) drenadas por um *Token Bucket* de `40 msg/s`.

---

## 2. Instalação e Dependências

Utilize o `uv` instalado localmente (`C:\Users\Kanex\.local\bin\uv.exe`):

```powershell
C:\Users\Kanex\.local\bin\uv.exe sync --extra tiktok --project C:\Users\Kanex\OneDrive\Desktop\JOGI\services\live_bridge
```

---

## 3. Como Executar o Servidor e o Simulador com o Jogo Godot

### Passo 1: Iniciar o Servidor WebSocket Local (`LiveBridgeServer`)
```powershell
C:\Users\Kanex\.local\bin\uv.exe run --extra tiktok --project C:\Users\Kanex\OneDrive\Desktop\JOGI\services\live_bridge python C:\Users\Kanex\OneDrive\Desktop\JOGI\services\live_bridge\server.py
```

### Passo 2: Iniciar o Jogo no Godot 4.7.2
Em outro terminal:
```powershell
& "C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\Kanex\OneDrive\Desktop\JOGI\game"
```
O `LiveEventBus` do Godot conectará automaticamente em `ws://127.0.0.1:8765/ws/godot`.

### Passo 3: Disparar Eventos com o Simulador (`MockLiveEventSimulator`)
```powershell
# Fluxo normal determinístico (25 eventos/s)
C:\Users\Kanex\.local\bin\uv.exe run --extra tiktok --project C:\Users\Kanex\OneDrive\Desktop\JOGI\services\live_bridge python C:\Users\Kanex\OneDrive\Desktop\JOGI\services\live_bridge\simulator.py --mode normal --count 30 --seed 42

# Impulsionar especificamente o Candidato #1 (CORAL)
C:\Users\Kanex\.local\bin\uv.exe run --extra tiktok --project C:\Users\Kanex\OneDrive\Desktop\JOGI\services\live_bridge python C:\Users\Kanex\OneDrive\Desktop\JOGI\services\live_bridge\simulator.py --mode viral --candidate 1 --count 20
```

---

## 4. Executar a Suíte de Testes Automatizados do `live_bridge`

```powershell
C:\Users\Kanex\.local\bin\uv.exe run --extra tiktok --project C:\Users\Kanex\OneDrive\Desktop\JOGI\services\live_bridge python -m unittest discover -s C:\Users\Kanex\OneDrive\Desktop\JOGI\services\live_bridge -v
```
# Atualização de interações em 24/10/2026

O contrato atual de torcida 13/22, eventos neutros, nomes e contagem de presentes
está em [AUDIENCE_CONTRACT.md](AUDIENCE_CONTRACT.md). Esse contrato prevalece sobre
exemplos antigos de seis candidatos ou de preços ilustrativos do catálogo.

As duas sessões isoladas, outbox de presentes com ACK, recuperação e launcher
estão em [RELIABILITY_CONTRACT.md](RELIABILITY_CONTRACT.md). Para conferir o plano
sem abrir processos: `services\live_bridge\.venv\Scripts\python.exe tools\run_live_instances.py --both --check`
(executado a partir da raiz do projeto).

Follow, meta, balanceamento e controles atuais:
[LIVE_CONTROLS_CONTRACT.md](LIVE_CONTROLS_CONTRACT.md). SDK TikTokLive 7.0.1 instalado
no extra local `tiktok`; `--both` escuta a live pública TikTok quando existir,
sem iniciar transmissão; `--offline` desativa essa escuta. O coletor Kwai continua
pendente, detalhado em [KWAI_EVENTOS_PENDENTES.md](KWAI_EVENTOS_PENDENTES.md).

