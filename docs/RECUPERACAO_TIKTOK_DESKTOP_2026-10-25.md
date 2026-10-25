# Recuperação TikTok — 25/10/2026

## Causa comprovada

O Godot PID 28396 e o supervisor real PID 49440 estavam na sessão Windows 1, mas no desktop privado `exebox-TZU76GAHXRORYP3XAUKM5SL7SS`. A leitura dos parâmetros dos processos confirmou esse desktop. `EnumWindows`, `EnumThreadWindows` e a ferramenta de janelas do desktop do operador não encontravam a janela. O motor, entretanto, renderizava em D3D12, atualizava a corrida e tinha uma sessão de áudio Windows ativa. Não era execução headless nem ausência de conexão WebSocket.

O PID 11752 era o wrapper da venv que iniciou o interpretador real 49440. O backend tinha estrutura equivalente 58972 → 49812. Eram wrappers Windows, e não dois supervisores independentes. A árvore foi identificada novamente antes da manutenção.

## Correção no projeto

- `tools/windows_visible_game.py`: inicia exclusivamente o renderizador TikTok com `CreateProcessW`, desktop explícito `winsta0\\default`, `SW_SHOWNORMAL`, ambiente Unicode e argumentos sem shell. Mantém a interface usada pelo supervisor; falha sem recorrer a um jogo oculto. Aceita caminhos `Path`.
- `tools/run_live_instances.py`: usa esse início gráfico apenas para TikTok, força `--display-driver windows --windowed` e grava o log do Godot no diretório da própria conta. O ramo Kwai foi preservado.
- `tools/backup_tiktok_session.py`: backup por API SQLite, com inclusão dos dados comprometidos no WAL e `PRAGMA integrity_check`; preserva os demais arquivos, confere checkpoint, cursor em bytes/fronteira de registros, journal completo e estabilidade entre arquivos. Não imprime credenciais e não restaura WAL antigo sobre o banco consolidado.
- Conta operacional configurada: `@xinka_`. Outras contas mantêm seus próprios diretórios.
- Também foram testadas e carregadas as melhorias TikTok já existentes na árvore local: espera pela tarefa de vida do WebSocket, fechamento assíncrono explícito do HTTP do SDK, reconexão à sala previamente confirmada com verificação de disponibilidade, invalidação da sala encerrada e cooldown persistente. O SDK instalado confirma os parâmetros usados.

## Auditoria dos scripts baixados — somente leitura

Nenhum dos seis scripts foi executado nesta tarefa.

| Script | Problema encontrado |
|---|---|
| RECUPERAR_JOGI_TIKTOK.ps1 | Faz diagnóstico/backup; a opção de diagnóstico ainda cria arquivos. Não encerra processos. |
| APLICAR_CORRECOES_TIKTOK_JOGI.ps1 | Exige pai imediato igual para jogo/backend; ignora o wrapper intermediário da venv. |
| APLICAR_CORRECOES_TIKTOK_JOGI_V2.ps1 | Ainda exige que o pai imediato do listener seja o launcher, apesar do wrapper de `server.py`. |
| REINICIAR_SOMENTE_TIKTOK_COM_BACKUP.ps1 | Conta wrappers como supervisores distintos; encerra todos os descendentes, sem restringir cada papel. |
| REINICIAR_TIKTOK_V3.ps1 | Recusa `conhost.exe`, auxiliar legítimo do Windows. |
| REINICIAR_TIKTOK_V4.ps1 | Melhora o tratamento de conhost, mas mantém Python `-c` com aspas frágeis, seleção ampla de launchers e conclusão sem comprovação de janela. |

Os scripts que passam `execute("pragma integrity_check")` e `=="ok"` dentro de `python -c` ficam sujeitos à remoção de aspas pelo marshaling legado do Windows PowerShell 5.1. Isso é coerente com o SyntaxError relatado; não foi necessário executar o script defeituoso para repetir o problema. A solução usa um arquivo Python real.

## Proteção e recuperação aplicada

Backup privado íntegro:

`C:\Users\Kanex\AppData\Local\JOGI\backups\tiktok-interactive-desktop-20261025-132058\consistent`

Os dois SQLite tiveram `integrity_check=ok`. Foram preservados token administrativo, equipes, checkpoint, journal e histórico. Antes do encerramento, o comando autenticado `pause_race` recebeu resultado `applied`, e o checkpoint pausado foi conferido contra a telemetria.

Estado preservado: rodada **5/50**, ciclo **2**, **550,8167 s** restantes, votos de sessão **13: 7 / 22: 8**, cursor do journal **4244**, presentes pendentes **0**. Histórico e vitórias foram comparados após a recuperação, sem reset ou limpeza de deduplicação.

A tentativa única de interrupção por console foi recusada porque havia membros de outras aplicações naquele console. Nenhum sinal foi enviado. Para impedir respawn, foi suspenso somente o supervisor TikTok verificado; após backup e checkpoint, foram encerrados exatamente o jogo 28396, o backend real 49812 e o supervisor real 49440. Os wrappers encerraram junto com seus filhos. Conhost e aplicações alheias foram preservados. A porta 8765 ficou livre antes da nova inicialização.

Novo supervisor real: 45100 (wrapper 28196). Novo Godot: **37936**, janela **591204**, título `Corrida Presidencial - Tiktok (DEBUG)`. Janela confirmada pela API nativa e por captura visual; não apenas pelo WebSocket. O comando autenticado de retomada teve ACK `applied`.

## Validações

- **103 testes Python e 3 subtestes aprovados** na execução final. Uma execução anterior falhou somente na remoção de uma pasta temporária com WinError 145; o caso isolado e a suíte final passaram. Há duas advertências de depreciação do SDK/websockets.
- GDA: project scan, script validate, scene validate e scene preflight aprovados. Três regressões estritas passaram com diagnósticos vazios: relógio/checkpoint/próxima rodada, cards de interações e habilidades T1–T4 para ambas as equipes.
- E2E isolado com classe real `CommentEvent` do SDK, backend temporário e Godot: votos 13/22, dois cards, três presentes com ACK único, destinos `[1,2,0]`, neutro contabilizado e replay sem reaplicação. Nenhuma requisição ao TikTok nesse teste.
- Teste gráfico isolado e silencioso (`AudioDriver=Dummy`): entrada, permanência, saída, fila, identidade/avatar alternativo e cards 13/22 aprovados. As seis imagens são de teste, não de espectadores reais. O ensaio gráfico gerou uma advertência de seis objetos na saída do fixture; as regressões estritas headless e a instância real tiveram zero orphan nodes. Não foi apresentado como prova de estabilidade prolongada.
- Produção: cinco amostras durante 80 s, telemetria de 0,04–0,11 s, 60 FPS, cronômetro de **550,68 → 470,65 s**, Lula **591,95 → 1552,29 m**, Flávio **591,85 → 1552,13 m**, pendências **0**. Relatório JSON registra cada amostra.
- Acompanhada também a transição natural: rodada 5 `RACING → PHOTO_FINISH → PODIO`, rodada 6 `COUNTDOWN → RACING`, com **597,78 s** na primeira amostra da nova corrida e 60 FPS. Nenhuma rodada foi forçada ou reiniciada para esse teste.
- Painel Chrome existente autenticado, identificado como `TIKTOK · @xinka_ · Online local`, com telemetria ao vivo e continuidade do cookie administrativo.
- Áudio: o Godot antigo 28396 tinha sessão ativa; depois da recuperação, a sessão pertence somente ao Godot visível 37936. A sessão `MediaSDK_Server.exe` 59964 pertence ao LIVE Studio, não a outro jogo. Não foi silenciada nem alterada. Captura/monitoramento final no Studio depende da seleção da origem.
- Kwai: backend real 54476, wrapper 29864 e coletor 59760 conservaram PIDs e horários de criação. Nenhum processo, cookie, banco, configuração ou comando Kwai foi alterado por esta recuperação.
- Revisão independente encontrou e validou a correção de dois problemas antes da entrega: conversão Path→str no CreateProcess e validação da fronteira do cursor no backup. Varredura dos padrões conhecidos de credenciais sem candidatos.

## Limites reais e operação

O coletor TikTok continua sujeito a **HTTP 429 na descoberta da sala**, com espera mínima de 900 s ou Retry-After maior e preservação do prazo após reinício. Não é bloqueio de porta: o backend local e o Godot estão conectados. Não foram feitas consultas externas manuais/repetitivas nem tentativas de contornar restrições.

Não houve LIVE pública nem comentários/presentes reais novos nesta recuperação. Recebimento na sala autorizada, catálogo real de IDs e entrega de eventos da plataforma ainda precisam ser comprovados quando o TikTok permitir a conexão. Testes locais não substituem essa comprovação.

O LIVE Studio está aberto e mostra `Iniciar LIVE`. Sua cena atual está sem origem, com a caixa `Adicionar captura de jogo` aberta. Uma tentativa de clique automático não alterou a seleção. Foi solicitado ao operador apenas selecionar `JOGI-TikTok.exe / Corrida Presidencial - Tiktok` e adicionar a origem; não iniciar transmissão. Não declarar captura pronta sem ver a prévia.

O jogo e o painel ficam abertos. Não executar novamente os scripts baixados; o atalho do projeto é `ABRIR_TIKTOK.cmd` (uma segunda execução protege a instância existente por lock/porta). O encerramento programado permanece em 26/10/2026 às 07h de Brasília, sem encerrar automaticamente o Studio.

A Arena não foi investigada nem alterada. A prontidão local não concede permissão eleitoral ou de plataforma para transmissão pública.
