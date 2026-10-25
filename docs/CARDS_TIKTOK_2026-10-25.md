# TikTok — cards no jogo, 25/10/2026

## Correção aplicada

Os votos reais já haviam sido recebidos antes desta intervenção, conforme confirmação do operador. O caminho LiveEventBus → AudienceDirector → participation_received → StadiumHUD existia. O problema visual era TTL de 3,4 segundos, supressão de eventos próximos, cooldown de nome e substituição dos dois cards sem fila.

Mudanças: duração6,4s; entrada/saída com fade/slide0,3s dentro da área segura; dois slots e fila visual64; repetições agregadas visualmente sem alterar votos; presentes prioritários inclusive com fila cheia; cooldown somente para momentos/áudio. Nomes sanitizados e avatar local ou fallback preservados. Replay de evento permanece deduplicado antes da apresentação. O limite visual não apaga eventos ou registros financeiros.

## Aplicação local e preservação

Somente Godot TikTok foi fechado normalmente e reaberto pelo supervisor existente. Revisão carregada confirmada pela telemetria: cards-20261025-v2; checkpoint_recovered=true; persistence.ready=true;60FPS; zero orphan nodes. Backend TikTok35692, coletor integrado e sessão permanecem no mesmo processo. Kwai, navegador, coletor41480, backend34944 e Godot53616 não foram reiniciados ou alterados em execução. Nenhuma transmissão iniciada.

O operador confirmou que ambas as LIVEs estavam encerradas. A leitura posterior do Studio também mostrou Iniciar LIVE. Backup local verificado do checkpoint, snapshot anterior e SQLite do backend em LOCALAPPDATA/JOGI/backups/tiktok-hud-20261025-001658. Não contém arquivos publicados no Git. Snapshot comparado antes/depois da primeira atualização: mesma rodada17, audience integralmente idêntico e15 IDs no ledger; distâncias continuaram de1839,72/1839,55m para2410,44/2410,27m durante a manutenção. Zero presentes pendentes.

## Evidência visual

As seis PNG em evidencias/estadio/interaction-cards-20261025 foram renderizadas no Godot com a cena real stadium_race.tscn em ambiente de desenvolvimento e APPDATA temporário:

1.00-before.png: antes de receber voto.
2.01-entering.png: entrada parcial.
3.02-readable-13-22.png: dois nomes, fallback e equipes13/22.
4.03-still-readable-5s.png: permanência após5s.
5.04-exiting.png: saída parcial.
6.05-queued-vote.png: comentário aguardando na fila admitido após liberação.

O relógio visual é avançado deterministicamente entre capturas; não é uma gravação contínua. A captura final passou nas mesmas verificações da cena. Uma execução intermediária reutilizou armazenamento de desenvolvimento e rejeitou fixtures já deduplicadas; a execução final usa APPDATA novo e passou. Nenhuma fixture foi injetada em produção.

Testes adicionais comprovam avatar ImageTexture no cache local, repetição do mesmo usuário com novoID, replay com mesmoID, fila limitada, prioridade de presente e funcionamento após mudança de rodada. O avatar externo do espectador depende da imagem legitimamente recebida pelo conector/cache.

## Captura do Studio e limites

A prévia local foi observada usando a origem existente JOGI-TikTok.exe após a recuperação do jogo, sem alterar fontes ou configurações. O HUD geral está no frame capturado. Não havia LIVE ativa nem novos comentários durante essa observação, portanto NÃO há comprovação de um card de comentário real novo na prévia do Studio depois da correção. Isso depende de futura interação legítima em teste autorizado; não é substituído por fixtures.

Não foi reiniciado o backend/coletor TikTok para carregar alterações experimentais de observabilidade. O estado externo observado ao final da manutenção ainda incluía HTTP429/rate_limited. Isso não invalida o recebimento anterior confirmado pelo operador e tampouco comprova conexão atual com sala encerrada.

A estreia pública permanece separada da conclusão técnica e condicionada às permissões e conformidade. Não iniciar LIVE pública automaticamente.

## Testes finais aprovados

-33/33 testes Godot, relatório godot-cards-final-20261025.json. A primeira suíte identificou duas expectativas antigas incompatíveis com a fila/cooldown novos; foram ajustadas para verificar o contrato novo e a suíte inteira foi executada novamente, sem falhas.
-Teste ponta a ponta isolado com classes CommentEvent do SDK instalado:13,22 e replay do primeiro; dois envelopes aceitos; ledger Godot1/1; dois cards visíveis; duplicado sem novo voto; permanência verificada. Sem rede SDK/TikTok. Relatório tiktok-cards-sdk-e2e.json.
-Revisão independente estática dos cards: sem bloqueantes; observação de prioridade de presente com fila cheia foi corrigida e testada.

Código publicado nesta entrega inclui somente apresentação Godot, testes e evidências TikTok. Alterações preliminares de diagnóstico/coletores de outra etapa permanecem separadas, sem reinício ou publicação nesta entrega.
