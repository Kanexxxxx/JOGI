# CONTRACT.md — Interface e Contrato entre Painel Web Admin e Backend LiveBridge

Este documento estabelece o contrato estrito de comunicação entre o **Painel Administrativo Web** (`services/live_bridge/admin/`) e o **Servidor Backend LiveBridge** (`services/live_bridge/server.py`).

O painel foi desenhado para operar com **duas vias redundantes de transporte**:
1. **Canal Primário (Tempo Real)**: WebSocket em `ws://127.0.0.1:8765/ws/admin`.
2. **Canal Secundário (Fallback / Polling)**: HTTP REST em `http://127.0.0.1:8765/api/*` (polling suave de estado e comandos via POST).

---

## 1. Conexão e Segurança

- **Bind Host**: Exclusivamente em loopback `127.0.0.1` ou `localhost`.
- **CORS / Headers**: Respostas HTTP devem incluir headers para acesso local:
  ```http
  Access-Control-Allow-Origin: *
  Access-Control-Allow-Methods: GET, POST, OPTIONS
  Access-Control-Allow-Headers: Content-Type, Authorization
  ```
- **Encoding**: Todas as mensagens devem ser transmitidas em UTF-8 com Content-Type `application/json; charset=utf-8`.
- **Sanitização**: Strings geradas ou exibidas devem ser tratadas de forma segura (sem injeção de tags HTML).

---

## 2. Canal WebSocket (`ws://127.0.0.1:8765/ws/admin`)

Ao conectar em `ws://127.0.0.1:8765/ws/admin`, o servidor envia imediatamente o estado atual e transmite atualizações de eventos e telemetria.

### 2.1 Mensagens Enviadas pelo Painel (Admin -> Servidor)

#### A. Comandos de Controle da Partida (`admin_command`)
```json
{
  "type": "admin_command",
  "command": "start_race" | "skip_lobby" | "restart_race" | "reset_dedup",
  "params": {}
}
```
* **`start_race`**: Força o início da corrida (sai de `LOBBY_VOTACAO` para `COUNTDOWN`).
* **`skip_lobby`**: Pula o tempo restante do lobby e inicia a largada imediatamente.
* **`restart_race`**: Ação crítica/destrutiva. Reinicia a partida para o lobby inicial, zerando posições e metros.
* **`reset_dedup`**: Limpa o cache LRU de 10.000 chaves de deduplicação e contadores de descarte.

#### B. Ações Rápidas por Candidato (`candidate_action`)
```json
{
  "type": "candidate_action",
  "action": "turbo" | "shield",
  "candidate_slot": 1
}
```
* **`candidate_slot`**: Inteiro entre `1` e `6`.
* **`action = "turbo"`**: Dispara um impulso imediato de velocidade (+5.0 m/s por 3.5s).
* **`action = "shield"`**: Concede um escudo protetor contra tropeços por 5s.

#### C. Simulação de Eventos da Live (`simulate_event`)
Dispara injeção sintética no pipeline do LiveBridge:

* **Voto**:
```json
{
  "type": "simulate_event",
  "event_type": "vote",
  "data": {
    "candidate_slot": 2,
    "count": 5,
    "user_id": "sim_user_123",
    "display_name": "Torcedor Elétrico"
  }
}
```

* **Curtidas (Likes)**:
```json
{
  "type": "simulate_event",
  "event_type": "like",
  "data": {
    "candidate_slot": 1,
    "count": 50,
    "user_id": "sim_liker",
    "display_name": "Super Fan"
  }
}
```

* **Compartilhamento (Share)**:
```json
{
  "type": "simulate_event",
  "event_type": "share",
  "data": {
    "candidate_slot": 4,
    "user_id": "sim_sharer",
    "display_name": "Divulgador"
  }
}
```

* **Presente (Gift)**:
```json
{
  "type": "simulate_event",
  "event_type": "gift",
  "data": {
    "candidate_slot": 3,
    "gift_tier": "T1" | "T2" | "T3" | "T4",
    "gift_name": "Rosa Turbo" | "Rosquinha Blindada" | "Super Jato" | "Meteoro do Caos",
    "repeat_count": 1,
    "user_id": "sim_gifter",
    "display_name": "Doador Ouro"
  }
}
```

* **Rajada de Estresse (Burst)**:
```json
{
  "type": "simulate_event",
  "event_type": "burst",
  "data": {
    "count": 40
  }
}
```

#### D. Solicitação de Estado & Heartbeat
```json
{ "type": "get_state" }
{ "type": "ping" }
```

---

### 2.2 Mensagens Enviadas pelo Servidor (Servidor -> Admin)

#### A. Atualização Integral de Estado (`state_update`)
Enviado periodicamente (ou após alterações de fase e comandos):
```json
{
  "type": "state_update",
  "timestamp_ms": 1729267200000,
  "state": {
    "race_state": "LOBBY_VOTACAO",
    "phase_timer_seconds": 15.2,
    "race_timer_seconds": 0.0,
    "backend_online": true,
    "godot_connected": true,
    "godot_client_count": 1,
    "metrics": {
      "received_total": 450,
      "accepted_total": 435,
      "duplicates_dropped": 12,
      "invalid_rejected": 3,
      "p2_shed_dropped": 0,
      "dispatched_to_godot": 435
    },
    "candidates": [
      {
        "slot": 1,
        "name": "Coral",
        "color": "#FF3B5C",
        "position": 1,
        "distance_meters": 54.2,
        "progress_pct": 45.2,
        "speed_mps": 12.5,
        "votes": 128,
        "status": {
          "turbo": true,
          "shield": false,
          "stumble": false
        }
      },
      {
        "slot": 2,
        "name": "Elétrico",
        "color": "#00A8FF",
        "position": 2,
        "distance_meters": 51.0,
        "progress_pct": 42.5,
        "speed_mps": 11.8,
        "votes": 95,
        "status": {
          "turbo": false,
          "shield": true,
          "stumble": false
        }
      },
      {
        "slot": 3,
        "name": "Ouro",
        "color": "#FFC800",
        "position": 3,
        "distance_meters": 49.3,
        "progress_pct": 41.1,
        "speed_mps": 11.2,
        "votes": 82,
        "status": {
          "turbo": false,
          "shield": false,
          "stumble": false
        }
      },
      {
        "slot": 4,
        "name": "Esmeralda",
        "color": "#00E676",
        "position": 4,
        "distance_meters": 47.8,
        "progress_pct": 39.8,
        "speed_mps": 10.9,
        "votes": 74,
        "status": {
          "turbo": false,
          "shield": false,
          "stumble": false
        }
      },
      {
        "slot": 5,
        "name": "Neon",
        "color": "#B347FF",
        "position": 5,
        "distance_meters": 46.1,
        "progress_pct": 38.4,
        "speed_mps": 10.5,
        "votes": 61,
        "status": {
          "turbo": false,
          "shield": false,
          "stumble": true
        }
      },
      {
        "slot": 6,
        "name": "Solar",
        "color": "#FF7A00",
        "position": 6,
        "distance_meters": 44.0,
        "progress_pct": 36.7,
        "speed_mps": 10.0,
        "votes": 49,
        "status": {
          "turbo": false,
          "shield": false,
          "stumble": false
        }
      }
    ]
  }
}
```

#### B. Evento de Telemetria / Feed de Live (`telemetry_event`)
Enviado sempre que um evento de live ou comando é aceito e processado:
```json
{
  "type": "telemetry_event",
  "event_id": "evt_sim_1729267200123_45",
  "timestamp_ms": 1729267200123,
  "source": "tiktok" | "kwai" | "simulator" | "admin",
  "event_type": "vote" | "like" | "share" | "gift" | "command",
  "user": {
    "user_id": "u_9921",
    "display_name": "Maria Silva"
  },
  "candidate_slot": 1,
  "action": "+1 Voto (#1 Coral)",
  "priority": "P0" | "P1" | "P2"
}
```

#### C. Confirmação de Comando (`command_ack`)
```json
{
  "type": "command_ack",
  "command": "start_race",
  "status": "ok" | "error",
  "message": "Corrida iniciada com sucesso."
}
```

#### D. Resposta de Ping (`pong`)
```json
{
  "type": "pong",
  "timestamp_ms": 1729267200456,
  "metrics": { ... }
}
```

---

## 3. Endpoints HTTP REST (Fallback & Polling)

### 3.1 `GET /api/state`
* **Descrição**: Obtém o snapshot mais recente do estado do jogo, conexões, métricas e corredores.
* **Status**: `200 OK`
* **Response Body**:
```json
{
  "status": "ok",
  "timestamp_ms": 1729267200000,
  "race_state": "LOBBY_VOTACAO",
  "phase_timer_seconds": 12.4,
  "race_timer_seconds": 0.0,
  "backend_online": true,
  "godot_connected": true,
  "godot_client_count": 1,
  "metrics": {
    "received_total": 450,
    "accepted_total": 435,
    "duplicates_dropped": 12,
    "invalid_rejected": 3,
    "p2_shed_dropped": 0,
    "dispatched_to_godot": 435
  },
  "candidates": [ ... ]
}
```

### 3.2 `POST /api/admin/command`
* **Descrição**: Executa comandos de controle de partida ou ações rápidas.
* **Content-Type**: `application/json`
* **Request Body**:
```json
{
  "command": "start_race" | "skip_lobby" | "restart_race" | "reset_dedup" | "candidate_turbo" | "candidate_shield",
  "params": {
    "candidate_slot": 1
  }
}
```
* **Status**: `200 OK` (ou `400 Bad Request` em caso de comando inválido)
* **Response Body**:
```json
{
  "status": "ok",
  "command": "start_race",
  "message": "Comando executado com sucesso."
}
```

### 3.3 `POST /api/admin/simulate`
* **Descrição**: Injeta eventos sintéticos para simulação ou teste de estresse.
* **Content-Type**: `application/json`
* **Request Body**:
```json
{
  "event_type": "vote" | "like" | "share" | "gift" | "burst",
  "candidate_slot": 1,
  "count": 5,
  "gift_tier": "T1",
  "gift_name": "Rosa Turbo",
  "repeat_count": 1,
  "user_id": "sim_user",
  "display_name": "Testador"
}
```
* **Status**: `200 OK`
* **Response Body**:
```json
{
  "status": "accepted",
  "event_id": "evt_sim_9912",
  "dispatched_count": 1
}
```
