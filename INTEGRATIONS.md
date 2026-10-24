# INTEGRATIONS.md — Integração com TikTok Live, Kwai e Simulador Local

---

## 1. Princípio Arquitetural: Conector Desacoplado (`LiveBridge`)

Conforme a auditoria de MCPs da Fase Zero, **não existem MCPs oficiais ou confiáveis para TikTok Live ou Kwai**, e os protocolos de captura de eventos ao vivo exigem reconexão assíncrona contínua, filas de prioridade e deduplicação em tempo real (incompatíveis com o modelo request/response de ferramentas MCP).

Por isso, a integração segue o padrão **Adapter -> Normalizer -> Deduplicator -> Priority Queue -> Local WebSocket (`ws://127.0.0.1:8765`)**.

---

## 2. Adaptadores Suportados (`services/live_bridge/adapters/`)

### 2.1 `MockLiveEventSimulator` (Prioridade 1 — Desenvolvimento e Testes 100% Offline)
- Gera eventos sintéticos determinísticos ou estocásticos (`vote_comment`, `like_batch`, `gift_action`, `share_boost`) no mesmo formato `LiveEventEnvelope` dos adaptadores reais.
- Suporta perfis de carga pré-configurados:
  - `calm`: 2 comentários/s, 1 presente a cada 10s.
  - `typical_live`: 15 comentários/s, 80 curtidas/s, 1 presente a cada 3s.
  - `viral_storm` (Stress Test): 250 comentários/s, 1.500 curtidas/s, 20 presentes simultâneos/s.

### 2.2 `TikTokLiveAdapter` (Produção TikTok Live)
- Baseado na biblioteca Python open-source `TikTokLive` (gerenciada em ambiente isolado via `uv`), conectando-se pelo `@unique_id` da transmissão pública sem exigir credenciais privadas da conta nos modos de leitura de eventos públicos.
- Eventos capturados: `CommentEvent`, `LikeEvent`, `GiftEvent` (respeitando `gift.streaking` para só disparar o combo final ou incrementar combos sem duplicar), `ShareEvent`, `FollowEvent`.

### 2.3 `KwaiLiveAdapter` (Produção Kwai Live)
- Estrutura modular pronta para conexão via WebSocket/Webhook de eventos de chat e presentes do Kwai Live, normalizando IDs de presentes e palavras-chave de voto para o contrato único `LiveEventEnvelope`.

---

## 3. Pipeline de Resiliência, Deduplicação e Rate Limiting

1. **Deduplicação Idempotente (LRU Cache)**:
   - Mantém os últimos `10.000` `event_id`s em memória por até `15 minutos`.
   - Caso uma reconexão de WebSocket reenvie os últimos pacotes do buffer da plataforma, eventos já processados são descartados silenciosamente (`duplicate_dropped`).
2. **Coalescing (Agregação em Janela de Tempo)**:
   - Curtidas (`like_batch`) e votos idênticos são agregados em janelas de `200ms` antes do envio ao Godot, reduzindo o tráfego de mensagens em até 95% durante picos.
3. **Fila de Prioridade por Tier**:
   - **Fila P0 (Imediata)**: Comandos administrativos do painel (`pause`, `force_reset`, `mute`) e Presentes Tier 3–5.
   - **Fila P1 (Alta)**: Presentes Tier 1–2.
   - **Fila P2 (Agregada)**: Comentários de voto, compartilhamentos e curtidas.
4. **Reconexão Automática (`Exponential Backoff + Full Jitter`)**:
   - Em caso de queda da conexão com a live: `delay = min(30.0, base_1s * (2 ** attempt)) + random(0, 0.5)`.
   - O Godot exibe um indicador discreto no canto técnico (`RECONECTANDO LIVE...`) mas **jamais interrompe ou trava a corrida em andamento**.
