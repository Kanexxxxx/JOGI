# Painel administrativo — contrato operacional atual

O painel existente em `admin/` controla **somente a instância da sua origem HTTP**. Em operação normal, TikTok usa `127.0.0.1:8765` e Kwai `127.0.0.1:8766`. Testes usam portas efêmeras e diretórios temporários. O HTML não contém tokens e não recebe dados de outra plataforma.

## Estado e autenticação

- `GET /api/state` retorna o snapshot verdadeiro da ponte e a última telemetria do Godot. A interface distingue `godot_connected`, `telemetry_fresh`, `telemetry_stale` e `telemetry_age_seconds`.
- `GET /api/admin/session` com `X-JOGI-Token` autentica o operador e emite cookie HttpOnly/SameSite=Strict com nome próprio por plataforma/porta. O campo de senha é limpo logo após a tentativa e o token não é armazenado em JavaScript persistente.
- `/ws/admin` transmite `state_update`, `command_ack` e `command_result`. O painel usa HTTP autenticado para obter o ID inequívoco de cada comando e acompanha seus recibos pelo WebSocket e pelo polling de estado.
- Quando a autenticação, a ponte ou a telemetria atual do jogo estiverem indisponíveis, os botões de execução ficam bloqueados. Não se inventam posições, velocidade, FPS ou estado da corrida antes da primeira telemetria.
- Host/Origin, tokens e canais são validados pelo servidor; não há CORS curinga autorizado por este contrato.

## Produção e desenvolvimento

`runtime_mode` é `production` por padrão ou `development` mediante configuração explícita. `simulation_allowed` determina a disponibilidade do simulador. No modo de produção, o painel oculta a seção de simulação e o servidor rejeita a ingestão sintética pelas rotas administrativas. Uma conexão de webhook não equivale a uma sala real conectada: `platform_events_status` informa o estado do coletor separadamente.

## Comandos e confirmação real

Os controles usam `/api/admin/command?command=<nome>&...`, dentro do contrato local existente. Valores estruturados, como `live_goals`, são JSON. Nenhum token é colocado na URL.

Comandos existentes: `start_race`, `skip_lobby`, `pause_race`, `resume_race`, `restart_race`, `reset_dedup`, `boost`, `shield`, `attack`, `set_live_goal`, `set_live_goals`, `set_audio_settings` e `end_experience`. As ações de candidato usam `candidate_slot` **1 para Lula/13 ou 2 para Flávio/22**.

1. A ponte valida e responde `{type: 'command_ack', event_id, command, status: 'queued'}`. **Isso não significa que o jogo executou.**
2. O Godot executa ou rejeita e retorna `{type: 'command_result', event_id, command, status: 'applied'|'rejected', message?}` pelo canal autenticado do motor.
3. A ponte confirma somente um ID/comando pendente correspondente e atualiza `recent_commands` (limite 100). A UI só apresenta execução confirmada para `applied`.
4. Os estados `timeout` e `disconnected` significam ausência de confirmação. O painel mantém o aviso e não exibe sucesso.

Os recibos podem chegar antes da resposta HTTP; a UI nunca rebaixa `applied`/`rejected` para `queued`. Um comando ainda pendente não pode ser repetido pelo mesmo botão. A pausa é apresentada a partir de `telemetry.race_paused`; o estado terminal usa `telemetry.experience_ended`/`ENDED`.

Reiniciar rodada, limpar deduplicação e encerrar exigem um diálogo com consequências, foco inicial no cancelamento, suporte a Escape e ciclo de foco por teclado. Limpar deduplicação não significa limpar o histórico durável de presentes.

## Configuração e eventos

- Três metas independentes: `live_goals.likes`, `.gifts`, `.follows`. A meta de seguidores tem alvo padrão 10.000. Sem total confirmado da plataforma, a UI mostra novos seguidores da sessão ou uma base **manual** identificada somada aos novos seguidores. Campos em edição não são sobrescritos pelo polling.
- `set_audio_settings` recebe os booleanos `voices_enabled`, `sfx_enabled`, `crowd_enabled`, `memes_enabled`. A edição só é considerada concluída após recibo real do jogo; os campos refletem a telemetria confirmada.
- `GET /api/gifts` lista somente presentes observados nesta instância. `/api/admin/gift` salva uma regra por `source`+`gift_id`; a confirmação diz que a regra foi salva **na ponte para os próximos presentes**, sem fingir que um efeito já foi executado. Valores e quantidades originais não são modificados.
- `recent_events` contém eventos sanitizados e limitados. A interface mostra nome/identificador fornecido, fonte, tipo, nome/ID do presente, quantidade, moedas quando conhecidas e `processing_status` (`queued`, `dispatched`, `confirmed`, `rejected`, `duplicate`, `after_close_pending`). `confirmed` corresponde ao ACK durável de presente; eventos sem ACK não são anunciados como confirmados.
- Imagens são aceitas pela UI somente nas rotas opacas locais `/viewer-avatars/<sha256>` e `/gift-icons/<sha256>`. Na ausência ou falha, a UI mostra inicial/ícone neutro. Textos são inseridos com `textContent`, sem HTML dos espectadores.
- Ranking Top 5 mantém a métrica de moedas do jogo; quantidade de presentes e valor de moedas são exibidos separadamente nos totais. Não há usuários fictícios de preenchimento no modo de produção.

## Encerramento

`operational_shutdown` contém `end_at` ISO com offset, `ended`, `reason`, `ended_at` e `pending_gifts`. O painel apresenta o horário em `America/Sao_Paulo`. Padrão operacional: **26/10/2026 às 07h**.

`end_experience` encerra definitivamente a experiência; o servidor persiste a decisão e o Godot confirma o estado terminal. Os botões de largada, retomada e ações dos candidatos ficam bloqueados. Metas/áudio podem permanecer configuráveis. Presentes pendentes continuam visíveis e presentes preservados após o limite são identificados, sem descarte silencioso. A ação não encerra OBS, live externa ou computador.

## QA reproduzível

`node tools/qa_admin_panel.cjs` inicia dois servidores efêmeros com credenciais sintéticas geradas em memória e dois Godot headless reais usando `game/tests/admin_qa_runtime.gd`, com APPDATA temporário. Testa painel → ponte → WebSocket → jogo → confirmação → painel, configuração, falhas, produção, autenticação, isolamento e telas de 375/768/1440 px. Não usa as portas do operador nem uma sala real.

As capturas e o relatório ficam em `docs/evidencias/admin-production/`. É necessário inspecionar as imagens para concluir a revisão visual. Eventos sintéticos são permitidos somente na instância de desenvolvimento usada pelo teste. As capturas de produção são feitas na outra instância, sem eventos sintéticos.
