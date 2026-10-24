# Plano Técnico de Integração Live — Corrida dos Candidatos (JOGI)

**Autor**: Agente 3 (`live-integration-engineer`)  
**Status**: Especificação Técnica para Implementação na Fase 2  
**Escopo**: TikTok LIVE, Kwai LIVE, `MockLiveEventSimulator`, `LiveEventEnvelope`, Deduplicação LRU, Rate Limiting e Matriz de Riscos.  
**Restrições**: Nenhuma credencial real utilizada; arquitetura 100% *Zero-Trust* com isolamento por WebSocket local (`ws://127.0.0.1:8765/ws/godot`).

---

## 1. Visão Geral da Arquitetura de Ingestão

O motor **Godot 4.7.2** nunca se conecta diretamente às redes externas do TikTok ou Kwai. Toda ingestão ocorre no serviço intermediário local em Python (`live-connector`, gerenciado via `uv` / `FastAPI` + `asyncio`), que atua como firewall de aplicação, sanitizador, deduplicador e agregador (*coalescer*) antes de emitir envelopes JSON padronizados para o `LiveEventBus` no Godot.

```
[TikTok LIVE] ──(Adapter A1/A2)──┐
[Kwai LIVE]   ──(Adapter B1/B2)──┼──► [Sanitizador Zero-Trust] ──► [Deduplicador LRU 10k]
[Simulador]   ──(Adapter C1)─────┘                                        │
                                                                          ▼
[Godot 4.7.2: LiveEventBus] ◄──(ws://127.0.0.1:8765)── [Token Bucket 40/s + Coalescer 200ms]
```

---

## 2. Integração TikTok LIVE: Mecanismos Reais e Requisitos

### 2.1 Comparativo de Mecanismos de Acesso

| Critério | Opção A1: `TikTokLive` (Python / WebCast Protobuf) | Opção A2: TikTok Developer / Live API Oficial |
|---|---|---|
| **Como funciona** | Conecta-se à sala pública usando apenas o `@unique_id` do criador via WebSocket/HTTP polling decodificando mensagens Protobuf do WebCast (`WebcastChatMessage`, `WebcastGiftMessage`, `WebcastLikeMessage`, `WebcastSocialMessage`). | Requer aprovação formal como *TikTok Live Partner / Developer App*, fluxo OAuth2 do criador e webhooks assinados. |
| **Disponibilidade real** | **Imediata** para qualquer conta capaz de abrir live. | **Restrita** (aprovação demorada e fechada para desenvolvedores independentes fora de agências parceiras). |
| **Dependência de Sign Server** | Sim. O handshake WebCast exige assinatura dinâmica (`X-Bogus` / `_signature`) gerada por provedor de assinatura (ex.: EulerStream Sign Server embutido no `TikTokLive` v6+). | Não utiliza WebCast scraping. |
| **Eventos Suportados** | `CommentEvent`, `GiftEvent` (com `streaking`), `LikeEvent` (lote e total), `ShareEvent`, `FollowEvent`, `JoinEvent`. | Limitado ao escopo aprovado da Partner API. |
| **Recomendação JOGI** | **Conector Primário da Fase 2**, encapsulado atrás da interface `BaseLiveAdapter`. | **Conector Secundário / Futuro**, caso o canal obtenha credenciamento de parceiro oficial. |

### 2.2 Tratamento Crítico de Presentes em Combo (`GiftEvent.streaking`)

No protocolo WebCast do TikTok, presentes que permitem combo (`streakable = True`, como Rosa/Café) disparam múltiplos pacotes `WebcastGiftMessage` enquanto o usuário clica repetidamente, e um pacote final quando o combo termina (`streaking = False`):

1. **Presentes não-combo (`gift.streakable == False`)**:
   - Processar imediatamente na chegada com `gift_count = event.repeat_count` (geralmente `1`).
2. **Presentes em combo (`gift.streakable == True`)**:
   - **Modo Conservador (Livre de Duplicação)**: Processar apenas quando `event.streaking == False`, aplicando `event.repeat_count` total acumulado.
   - **Modo Tempo Real com Delta Tracker (Recomendado para resposta imediata na pista)**: Manter um dicionário em memória `active_streaks[(user_id, gift_id, streak_id)] = last_repeat_count`. A cada pacote recebido com `repeat_count > last_repeat_count`, emitir apenas a diferença `delta = repeat_count - last_repeat_count` e atualizar o estado; ao receber `streaking == False`, emitir eventual resíduo e limpar a chave após `60s`.

### 2.3 Limites de Conexão e Proteção contra Bloqueio / Rate-Limit

- **Proibição de Polling Agressivo**: Nunca reconectar em loop fechado se a live estiver offline. Verificar estado via `client.is_live()` no máximo 1 vez a cada `30s` antes de iniciar a conexão WebSocket.
- **Sign Server Rate Limit (`HTTP 429`)**: A camada gratuita do EulerStream possui limite de assinaturas por minuto/hora por IP. O conector deve manter 1 única conexão persistente por live e aplicar *Exponential Backoff + Full Jitter* (`1s`, `2s`, `4s`, `8s`, `16s`, teto `30s`).
- **Isolamento de Sessão**: Não usar cookies de conta principal (`sessionid`) a menos que estritamente necessário, operando preferencialmente em modo *anonymous room observer* pelo `@unique_id`.

---

## 3. Integração Kwai LIVE: Fatos Confirmados e Alternativas Seguras

### 3.1 Fato Confirmado sobre API Pública

- **Ausência de API Pública Oficial Self-Service para Chat/Gifts de Live**: Diferente de plataformas como Twitch ou YouTube, o Kwai (`kwai.com` / Kuaishou internacional) **não disponibiliza uma API pública aberta e documentada** para leitura direta de eventos de chat, curtidas e presentes de lives por desenvolvedores independentes sem contrato comercial fechado.
- Além disso, bibliotecas comunitárias de scraping direto do protocolo binário do Kwai sofrem quebras frequentes de assinatura (`__NS_sig3`) e risco de bloqueio de IP/conta.

### 3.2 Arquitetura de Adaptadores Pluggable para Kwai LIVE

Para garantir operação 100% segura, auditável e sem violação de credenciais, o JOGI implementará três modos intercambiáveis sob a mesma interface `KwaiLiveAdapter`:

1. **Modo B1 — `KwaiDomBridgeAdapter` (Leitor Passivo via Página Web / Kwai Live Studio)**:
   - Um script cliente leve conectado a uma aba autenticada/pública da transmissão web do Kwai (via contexto Playwright controlado localmente ou UserScript/Bridge local) observa mutações somente-leitura na árvore DOM da lista de chat/presentes (`MutationObserver`) e encaminha os eventos via WebSocket local (`ws://127.0.0.1:8765/ws/ingest/kwai`) autenticado com `ADMIN_PANEL_TOKEN`.
   - **Vantagens**: Zero engenharia reversa de criptografia proprietária, zero exposição de senhas/tokens do Kwai ao backend, baixíssimo risco de bloqueio.
2. **Modo B2 — `KwaiWebhookAdapter` (Integração com Ferramentas de Terceiros / Parceiros)**:
   - Endpoint local `POST http://127.0.0.1:8765/api/v1/webhook/kwai` capaz de receber webhooks locais de softwares de transmissão (ex.: plugins de OBS/Live Studio ou conectores homologados) e convertê-los para `LiveEventEnvelope`.
3. **Modo B3 — Operação Assistida via Painel Admin + `MockLiveEventSimulator`**:
   - Permite que o operador da live dispare eventos espelhados ou acione ondas de interação com 1 clique no Painel Admin (`http://127.0.0.1:8765/admin`) caso a plataforma Kwai altere o layout da página web durante uma transmissão ao vivo.

---

## 4. Contrato de Eventos (`LiveEventEnvelope`) e Sanitização

Todo evento proveniente de TikTok, Kwai ou do Simulador é normalizado no schema JSON abaixo antes de entrar na fila prioritária:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "LiveEventEnvelope",
  "type": "object",
  "required": [
    "schema_version",
    "event_id",
    "source",
    "event_type",
    "timestamp_ms",
    "priority",
    "user",
    "payload"
  ],
  "properties": {
    "schema_version": { "type": "string", "const": "1.0" },
    "event_id": { "type": "string", "minLength": 8, "maxLength": 128 },
    "source": { "type": "string", "enum": ["tiktok", "kwai", "simulator", "admin"] },
    "event_type": {
      "type": "string",
      "enum": ["gift", "vote", "like_batch", "share", "admin_command", "system_status"]
    },
    "timestamp_ms": { "type": "integer", "minimum": 0 },
    "priority": { "type": "string", "enum": ["P0", "P1", "P2"] },
    "user": {
      "type": "object",
      "required": ["user_id", "display_name"],
      "properties": {
        "user_id": { "type": "string", "maxLength": 64 },
        "display_name": { "type": "string", "maxLength": 24 }
      },
      "additionalProperties": false
    },
    "payload": {
      "type": "object",
      "properties": {
        "candidate_slot": { "type": "integer", "minimum": 1, "maximum": 6 },
        "gift_tier": { "type": "string", "enum": ["T1", "T2", "T3", "T4"] },
        "gift_name": { "type": "string", "maxLength": 32 },
        "coin_value": { "type": "integer", "minimum": 1, "maximum": 100000 },
        "repeat_count": { "type": "integer", "minimum": 1, "maximum": 1000 },
        "like_count": { "type": "integer", "minimum": 1, "maximum": 50000 },
        "action_id": {
          "type": "string",
          "enum": [
            "micro_boost",
            "vote_impulse",
            "share_frenzy",
            "gift_t1_turbo",
            "gift_t2_shield_or_obstacle",
            "gift_t3_super_jato",
            "gift_t4_chaos_meteor"
          ]
        }
      },
      "additionalProperties": false
    }
  },
  "additionalProperties": false
}
```

### Regras de Sanitização Zero-Trust (em conformidade com `SECURITY.md`)

1. **`display_name`**:
   - Normalização Unicode `NFKC`.
   - Remoção de caracteres de controle (`\u0000`–`\u001F`, `\u007F`–`\u009F`), invisíveis/zero-width (`\u200B`–`\u200F`, `\uFEFF`) e overrides bidirecionais (`\u202A`–`\u202E`, `\u2066`–`\u2069`).
   - Escape/remoção de colchetes `[` e `]` para impedir injeção de BBCode no Godot.
   - Truncamento rígido em **24 caracteres**.
2. **Comentários de Voto**:
   - O texto bruto do chat **nunca é enviado ao Godot**.
   - O parser regex no Python extrai exclusivamente o slot numérico (`#1`..`#6`, `1`..`6` ou alias configurado do candidato) e descarta o restante da string.

---

## 5. Deduplicação, Coalescing, Rate Limiting e Reconexão

### 5.1 Deduplicação LRU com TTL
- **Estrutura**: `OrderedDict` em memória limitado a `10.000` chaves com TTL de `15 minutos` (`900s`).
- **Chave primária**: `f"{source}:{msg_id}"` quando o id único da plataforma estiver presente.
- **Chave determinística de fallback**: `sha256(f"{source}:{user_id}:{event_type}:{candidate_slot}:{timestamp_ms // 1000}")`.

### 5.2 Janela de Coalescing (`200ms`)
- **Curtidas (`like_batch`)**: Acumula todas as curtidas recebidas em janelas de `200ms` por candidato/global e emite no máximo `5 pacotes/s`.
- **Votos (`vote`)**: Agrupa votos por `candidate_slot` (`1..6`) a cada `200ms`, preservando na amostra de exibição os 3 últimos `display_name` sanitizados para o ticker visual.
- **Presentes (`gift`)**: Presentes `T2`, `T3` e `T4` têm prioridade `P0` e **bypassam o coalescing**, indo direto para a fila `P0` para feedback instantâneo (< 150ms).

### 5.3 Filas Prioritárias e Token Bucket (`40 msg/s`)
- **Três filas `asyncio.Queue` com capacidade limitada (Backpressure)**:
  - `P0_Queue` (`maxsize=500`): Presentes (`T1`–`T4`) e comandos administrativos (`admin_command`). Nunca descartados.
  - `P1_Queue` (`maxsize=1000`): Pacotes agregados de votos e compartilhamentos.
  - `P2_Queue` (`maxsize=1000`): Pacotes agregados de curtidas. Sob sobrecarga (>80% de ocupação), pacotes `P2` excedentes são fundidos no contador acumulado sem gerar novos eventos individuais.
- **Token Bucket de Saída**: Limita o envio ao Godot em **40 mensagens/segundo** (`capacity = 40`, `refill_rate = 40.0/s`), garantindo que o `LiveEventBus` no Godot mantenha 60 FPS estáveis mesmo em lives com milhares de espectadores simultâneos.

---

## 6. Especificação do `MockLiveEventSimulator`

O `MockLiveEventSimulator` é um componente de primeira classe (não apenas um script de teste descartável), essencial para:
1. Desenvolvimento e balanceamento offline da corrida sem depender de live aberta.
2. Testes automatizados de carga e regressão (QA).
3. Contingência operacional durante transmissões reais.

### Modos de Operação do Simulador
- **`calm` (`5 ev/s`)**: Fluxo leve de curtidas e votos distribuídos com presentes `T1` ocasionais a cada 15s.
- **`normal` (`25 ev/s`)**: Disputa equilibrada entre 2 ou 3 candidatos líderes, rajadas de votos no minuto final e presentes `T1`/`T2`.
- **`viral` (`100 ev/s` brutos -> coalescidos para `<= 40 msg/s`)**: Chuva intensa de votos, curtidas e combos de presentes `T1`–`T4` para validar a ausência de *frame drops* no Godot.
- **`chaos_fuzz` (Segurança + Estresse)**: Injeta nomes de usuários com emojis complexos, strings longas, tentativas de BBCode (`[wave][color=red]`), caracteres RTL e pacotes duplicados para validar o sanitizador e o deduplicador LRU.
- **`seed` Determinístico**: Aceita `--seed <int>` para reproduzir exatamente a mesma sequência de eventos em testes de regressão.

---

## 7. Matriz de Riscos e Mitigações

| ID | Risco Técnico / Operacional | Probabilidade | Impacto | Mitigação Arquitetural no JOGI |
|---|---|---|---|---|
| **R1** | Quebra do protocolo WebCast do TikTok ou atualização de schema Protobuf | Média | Alto | Isolamento em `TikTokWebcastAdapter`; atualização pontual do pacote `TikTokLive` via `uv` sem tocar no código Godot; fallback imediato para Painel Admin / Simulador. |
| **R2** | Rate-limit (`HTTP 429`) no servidor de assinatura do `TikTokLive` | Média | Médio | Manter sessão única persistente, *Exponential Backoff + Full Jitter* (`1s` -> `30s`) e verificação espaçada de `is_live()`. |
| **R3** | Ausência de API oficial aberta no Kwai LIVE | Confirmado (Fato) | Médio | Arquitetura plugável com `KwaiDomBridgeAdapter` (observador DOM passivo no navegador/studio) + `KwaiWebhookAdapter` + controle híbrido no Painel Admin. |
| **R4** | Enxurrada de eventos (*Chat/Like Flood*) travando o loop de física 3D do Godot | Alta em lives virais | Crítico | Coalescing de `200ms` no Python + Token Bucket rígido de `40 msg/s` + filas `P0/P1/P2` com descarte gracioso de `P2`. |
| **R5** | Contabilização duplicada de presentes em combo (`streaking`) no TikTok | Alta se não tratado | Alto | *Streak Delta Tracker* por `(user_id, gift_id, streak_id)` emitindo apenas incrementos reais ou fechamento do combo (`streaking == False`). |
| **R6** | Injeção de BBCode, caracteres RTL ou nomes maliciosos poluindo o HUD 9:16 | Alta | Alto | Sanitizador Zero-Trust no Python (`NFKC`, strip de controle/bidi, escape de `[]`, limite de 24 chars) + `bbcode_enabled = false` em todos os nós de texto de usuário no Godot. |
| **R7** | Queda temporária do processo Python durante a transmissão | Baixa | Médio | Cliente `WebSocketPeer` no Godot com reconexão automática exponencial; a corrida 3D continua funcionando autonomamente com IA local mesmo sem conexão WebSocket. |
