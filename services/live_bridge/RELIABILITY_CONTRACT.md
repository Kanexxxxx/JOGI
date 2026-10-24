# Isolamento e entrega local — plano de implementação 24/10/2026

## Contrato aceito antes da alteração

1. Uma instância `--platform tiktok` em 127.0.0.1:8765 e outra
   `--platform kwai` em 127.0.0.1:8766. Painel, filas, telemetria, dedup e banco
   separados. Cada instância rejeita eventos da outra plataforma; `admin` e
   `simulator` continuam permitidos como teste/controle local identificado.
2. Um consumidor Godot por instância, impedindo dois jogos de receber o mesmo
   presente pelo mesmo servidor. O jogo recebe `LIVE_BRIDGE_WS_URL` e
   `LIVE_PLATFORM` pelo launcher, sem alterar configuração global.
3. Presentes são gravados em uma outbox SQLite antes de responder `accepted`.
   Sem consumidor, permanecem pendentes. Capacidade finita retorna `busy`, sem
   apagar um presente anterior. O produtor deve conservar e repetir o mesmo ID
   quando recebe `busy`; nenhum conector real está conectado nesta fase.
4. Godot confirma presentes com `{ "type": "event_ack", "event_id": "..." }`
   após seu processamento síncrono; confirma também replay já aceito. Sem ACK,
   o bridge repete depois de timeout ou reconexão. Isso é entrega **ao menos uma
   vez**: uma falha entre aplicar e confirmar ainda pode causar reaplicação se o
   consumidor perder sua memória/checkpoint. Não há promessa de exatamente uma vez.
5. O journal guarda somente envelopes validados/sanitizados, IDs, contadores e
   horários públicos. Chaves, cookies, credenciais, texto livre e configurações de
   voz não fazem parte da persistência. Banco fora do OneDrive por padrão.
6. Votos/curtidas/compartilhamentos continuam em filas finitas em memória; shedding
   é contabilizado. Comandos admin ficam em RAM e não são reexecutados após reboot.
7. Estado/health distinguem backend ativo, consumidor conectado e telemetria
   recente. Telemetria antiga não é apresentada como corrida atual após desconexão.
8. Validar com dois servidores/consumidores locais, pausa/reconexão/reinício,
   fila cheia, replay/ACK e isolamento. Isso não substitui teste contínuo de 32h
   nem valida TikTok/Kwai reais, elegibilidade a presentes ou captura de OBS.

## Execução implementada

Use o Python já instalado no ambiente do bridge, a partir da raiz do projeto:

```powershell
services\live_bridge\.venv\Scripts\python.exe tools\run_live_instances.py --both --check
services\live_bridge\.venv\Scripts\python.exe tools\run_live_instances.py --both
```

`--check` somente valida os caminhos e mostra o plano. `--both` abre dois bridges
ocultos e duas janelas visíveis do jogo para captura. `--platform tiktok` ou
`--platform kwai` abre uma única sessão. `--bridge-only` abre somente as pontes.
`--scene res://scenes/main/stadium_race.tscn` é o padrão. Nenhuma transmissão de
TikTok/Kwai é iniciada, nem conta autenticada, por esse launcher.
Atualização: o launcher habilita a leitura pública TikTok por `--listen-live`;
`--offline` a desativa. Ler eventos de uma sala existente não inicia broadcast.

Cada jogo recebe variáveis exclusivas no próprio processo:

| Plataforma | `LIVE_PLATFORM` | `LIVE_BRIDGE_WS_URL` | Painel |
|---|---|---|---|
| TikTok | `tiktok` | `ws://127.0.0.1:8765/ws/godot` | `http://127.0.0.1:8765/admin` |
| Kwai | `kwai` | `ws://127.0.0.1:8766/ws/godot` | `http://127.0.0.1:8766/admin` |

O launcher recusa porta já em uso, preservando o processo e o arquivo de status
do supervisor existente. Cada bridge e jogo tem supervisão independente: uma
falha reinicia somente aquele processo, com espera progressiva de 1 a 30 segundos.
Após seis reinícios em dez minutos, o processo fica em `needs_attention` e os
demais continuam. O jogo só inicia depois de sua ponte responder corretamente.
Ctrl+C encerra somente os processos criados por esse launcher. A solicitação
temporária ao Windows para manter o computador acordado é restaurada ao sair;
nenhuma configuração global é alterada. Reinícios reutilizam a mesma outbox e
o checkpoint do jogo. Isso não constitui um ensaio de estabilidade de 32 horas.

Para rodar um bridge manualmente:

```powershell
services\live_bridge\.venv\Scripts\python.exe services\live_bridge\server.py --platform tiktok --account nostalgiia.br
services\live_bridge\.venv\Scripts\python.exe services\live_bridge\server.py --platform kwai --account mentalista..
```

`--account` identifica a conta pública; `--listen-live` habilita seu coletor TikTok.
O usuário confirmou aptidão a live/presentes; a coleta real continua por testar. `--port` permite
outra porta local e `--state-dir` outra pasta exclusiva. O modo legado
`--platform local` aceita fontes das duas plataformas para desenvolvimento;
**não usar esse modo para duas transmissões independentes**.

## Persistência e limites

O padrão é `%LOCALAPPDATA%\JOGI\live_bridge\<plataforma>\gifts.sqlite3`, fora da
pasta sincronizada do OneDrive. Cada arquivo possui metadado de plataforma e lock
de processo: outra plataforma ou outro processo não pode reutilizar o mesmo banco.
SQLite usa WAL e `synchronous=FULL`; `accepted` significa commit local concluído.

Capacidade: 5.000 presentes pendentes. Pendentes nunca são removidos por idade ou
para aceitar outros. O recibo `busy` exige retry do produtor com o MESMO `event_id`.
Não inventar ID novo em retry. Presentes confirmados permanecem para dedup até
36 horas ou 50.000 registros recentes (mais no máximo 99 antes da limpeza),
o limite que for alcançado primeiro. O journal não é extrato financeiro.

Presentes aguardam ACK com timeout de cinco segundos. A transmissão/retransmissão
respeita o limitador compartilhado de 40 mensagens/s. `dispatched_to_godot` conta
envios WebSocket, inclusive retries; `gift_acks_total` conta confirmações nesta
execução; `pending_gifts` inclui pendências de execuções anteriores.

Votos/compartilhamentos e curtidas continuam em RAM (1.000 envelopes por fila).
Se essas filas enchem, o mais antigo é substituído e o descarte aparece nas
métricas. Comandos admin têm fila própria de 500; cheia responde `busy`, sem
deslocar presente. Eles não são restaurados após reiniciar o bridge.

O servidor admite somente um consumidor Godot. Painéis acompanham telemetria pela
rota administrativa. O painel usa a própria porta, distingue telemetria recente
(até cinco segundos) e não apresenta uma medição inexistente de FPS/live real.

## Superfície local

Bind continua estrito em 127.0.0.1. WebSockets e HTTP validam Host/Origin antes de
aceitar comandos ou fazer upgrade: Origin ausente é permitido para coletores
nativos; navegador precisa usar HTTP em localhost/127.0.0.1 na porta do painel
correspondente. Origem remota, `null`, outra porta e requisições `cross-site` são
negadas. Não é autenticação de outros programas locais confiáveis.

O webhook passivo independente do Kwai passou de **8766 para 8786**, evitando
colisão com o bridge principal do Kwai. Continua desabilitado por padrão e sem
coletor validado. Ele também rejeita Host/Origin externos e limita leitura HTTP.

## Evidências e pendências

`test_live_reliability.py` cobre banco cheio, dedup após reinício, saída abrupta
de processo, integridade SQLite, ACK/reconexão, consumidor único, duas plataformas
sem cruzamento de eventos e política de Origin com WebSockets reais em loopback.
`--both --check` valida o contrato do launcher sem abrir janelas. A suíte inteira
e os tempos reais estão registrados em `reliability-validation.json`.

Continuam pendentes: coleta real verificada, integrador Kwai, estabilidade com
dois jogos/OBS no PC, recuperação conjunta do estado Godot e teste contínuo de
32 horas. O journal sozinho não torna uma sessão de 32 horas validada.
