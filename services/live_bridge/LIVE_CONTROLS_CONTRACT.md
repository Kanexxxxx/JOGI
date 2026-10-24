# Interações, meta e controles — 24/10/2026

## Eventos e balanceamento

- `follow`: `action_id: audience_follow`, `repeat_count: 1`, usuário sanitizado;
  equipe opcional e nenhum boost. O TikTok registra `FollowEvent`, sem também
  registrar `SocialEvent` para evitar a duplicação do mesmo evento.
- Comentários 13/22 continuam gerando participação/voto, inclusive no cooldown.
  O bônus elegível é 1,1 m/s durante um segundo, no máximo uma vez a cada dois
  segundos por usuário. Durante o cooldown o envelope mantém `boost_amount: 0`;
  o consumidor deve contar a participação e não acelerar. O protocolo limita
  bônus de comentário a 1,5 m/s e sua duração a um segundo.
- Um presente sem mecânica conhecida é classificado pelo preço unitário recebido:
  T1=1..9, T2=10..99, T3=100..999, T4=1.000+. Zero significa preço desconhecido.
  Mecânicas conhecidas/explicitamente configuradas podem conservar seu tier.
- O total real permanece `coin_value = preço unitário × delta`, sem outra
  multiplicação e sem truncar a contabilidade quando o efeito atinge o teto.
  Bônus calculado: `min(20, 2.5 + 2*log2(1 + coin_value))` m/s;
  duração: `min(12, 3 + 0.65*log2(1 + coin_value))` segundos. São regras do jogo,
  não preços oficiais de presentes. A física/efeito final é responsabilidade do Godot.

## Meta configurável

Comando admin: `set_live_goal`; ação: `admin_set_live_goal`; payload:

```json
{"command":"set_live_goal","action_id":"admin_set_live_goal","goal_kind":"follows","goal_target":250,"goal_label":"Torcida Brasil"}
```

`goal_kind`: `likes|follows|gifts|coins`; `goal_target`: inteiro 1..1.000.000.000;
`goal_label`: texto sanitizado até 40 caracteres. O comando só é admitido pela
rota admin; o ingresso de eventos externos não pode alegar origem `admin`.

A configuração é persistida atomicamente em `live_goal.json`, junto à outbox
exclusiva da plataforma. Após reconectar o Godot, somente a configuração mais
recente é reenviada; configurações antigas que ficaram na fila são descartadas.

O snapshot `/api/state` contém a configuração em `live_goal`, mais
`live_goal_applied`. Valor/progresso recebido do jogo só é mostrado como aplicado
se a telemetria estiver recente e a configuração corresponder à selecionada.

## Painel

O painel usa sua própria porta e rotas `/admin/app.js` e `/admin/styles.css`.
Comandos por WebSocket possuem fallback HTTP em query string, compatível com
o servidor. O frontend não simula placar, velocidade, escudo ou partida iniciada
apenas porque um botão foi clicado; exibe recibos e telemetria recebidos.

Controles exercitados: iniciar, pular lobby, pausar/continuar, confirmação de
reinício, turbo/escudo/ataque, votos, likes, share, follow, meta e presente com
valor unitário e quantidade. Top 5, totais e voz são leitura da telemetria do jogo.

Contadores são distintos: `session.gifts` conta presentes e `session.coins` conta
moedas. Arrays com três posições são somados para o total (neutro/Lula/Flávio).
O painel não converte moedas em reais nem trata dados do simulador como receita.

## SDK e execução

SDK opcional instalado localmente: TikTokLive **7.0.1**, via
`uv sync --extra tiktok --project services/live_bridge`. Imports, configuração
`nostalgiia.br`, eventos e ciclo de conexão foram verificados sem consultar live real.

`server.py --platform tiktok --account nostalgiia.br --listen-live` lê a sala
pública quando a transmissão existir; não abre uma transmissão. O launcher
`tools/run_live_instances.py --both` habilita isso para o TikTok. `--offline`
mantém somente eventos locais. Kwai continua sem coletor integrado.

O estado diferencia `not_started`, `connecting`, `waiting_room`, `connected`,
`account_not_found`, `reconnecting` e `kwai_requires_collector`. O SDK tem
reconexão com backoff; a tarefa retornada por `start()` também é aguardada para
não criar vários clientes simultâneos. Se a outbox lotar, o callback aguarda
capacidade; existe métrica de backpressure. O buffer SDK anterior ao commit não
é uma garantia de recuperação de dados após crash.

Referências primárias do SDK: [eventos](https://ttl.docs.isaackogan.com/events/chat-and-audience/),
[combos](https://ttl.docs.isaackogan.com/guides/gifts/). TikTokLive é uma biblioteca
de terceiros; instalação/configuração não comprova a coleta de uma live real.

## Evidências

- `qa-panel/report.json` e três screenshots: Playwright/Chromium reais, bridge
  efêmero e consumidor/telemetria de teste identificados. Nenhuma live real.
- `test_follow_goal_balance.py`, `test_tiktok_listener.py` e demais testes Python.
- `e2e-reliability-validation.json`: Godot/GDA real, ACK de presente simulado.

Sem baseline visual aprovado, regressão visual permanece INCONCLUSIVA. Auditoria
de labels/nomes passou; WCAG completo/axe e INP não foram certificados.
