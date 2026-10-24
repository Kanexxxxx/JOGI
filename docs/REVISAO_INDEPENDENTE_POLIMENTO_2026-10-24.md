# Revisão independente do polimento — 24/10/2026

Revisão somente de leitura da implementação; nenhum modelo, voz ou shader foi alterado por este revisor. Escopo: HUD arredondado, identidade/ordem do placar, capas, Planalto, marcadores de metros e componentes locais de áudio. O controlador da corrida estava recebendo integração em paralelo; portanto a revisão completa da integração depende do checkpoint final.

## Achados para corrigir

- **P2 — marcações de metros saltam de lateral ao reciclar.** Em `game/scripts/stadium_world.gd:65-72`, a quilometragem de cada índice muda a cada 50 m, enquanto o lado de cada índice fica fixo em `:89-100`. Em 49,9 m, a marca de 100 m é o índice 2, à esquerda; em 50 m, vira o índice 1, à direita. Ela continua visível a aproximadamente 8,65 unidades à frente e troca de lado de forma instantânea. Vincular o lado à quilometragem, preservando o pool de seis nós, evita esse salto. O teste atual de arte verifica projeção e quantidade de nós, mas não continuidade lateral na fronteira de 50 m.
- **P2 — ultrapassagem antiga pode ser anunciada após nova troca de líder.** `game/scripts/race_audio.gd:130-132` retorna por cooldown antes de retirar a ultrapassagem anterior da fila (`:149-152`). A sequência de pedidos 1 → 2 → 1 em menos de oito segundos deixa o pedido do time 2 enfileirado quando o último do time 1 é rejeitado. O cooldown global de seis segundos em `game/scripts/stadium_race.gd:645-649` também impede atualizar/cancelar uma fala pendente em uma reversão rápida. Toda mudança real de liderança deve invalidar ultrapassagens pendentes, mesmo que um novo anúncio seja suprimido. O placar pode estar correto enquanto a narração diz o líder anterior.

## Evidências reproduzidas

`gda project scan --project game --json`: sem erros de engine. Estes seis testes passaram novamente com `--strict`, `exit_status=0`, `stderr` vazio e `diagnostics=[]`:

- `res://tests/test_rounded_hud.gd`
- `res://tests/test_stadium_art_revision.gd`
- `res://tests/test_cape_motion.gd`
- `res://tests/test_race_audio.gd`
- `res://tests/test_race_ambience.gd`
- `res://tests/test_race_meme_board.gd`

O teste de capas exercitou os dois modelos reais: amplitude estabilizada de corrida ~0,1497; turbo ~0,2448; impacto ~0,0245; pausa congelada; materiais do corpo preservados. O teste de torcida decodificou o MP3 local de dez segundos e as 38 falas, conservou dois players e o número de nós após 160.000 segundos de relógio lógico. Isso não é um ensaio real de 42 horas.

## Inspeção de segurança e limites

HUD usa Labels literais, sanitiza controles/bidi, limita nomes e mantém três linhas fixas com TTL; não interpreta BBCode nem baixa imagens remotas. A reordenação move a linha inteira, preservando candidato, número, retrato, metros e km/h. A fonte Nunito local inclui licença e caracteres portugueses.

Áudio usa arquivos locais com caminhos restritos a diretórios de cache e nomes SHA256; não consulta ElevenLabs nem recebe chave em runtime. Locução tem um player e fila máxima oito; torcida dois players; memes um player, seleção duplamente habilitada, status aprovado e limite real de cinco segundos. Os memes importados estavam globalmente desabilitados e pendentes na revisão, portanto não foram tratados como seleção de conteúdo aprovada. A escuta humana e os medidores de áudio no OBS continuam sendo verificações distintas.

Não houve evidência de inversão das identidades 13/Lula e 22/Flávio nos componentes inspecionados. A v2 do Planalto preserva a anterior, corrige as normais da rampa e identifica a segunda escadaria como cenografia, sem afirmar reprodução medida do prédio.

## Limites do parecer

Os dois achados acima precisam de correção e regressão antes de considerar este conjunto concluído. Esta revisão não certifica captura/áudio do OBS, eventos reais do Kwai, teste simultâneo de duas instâncias por dez minutos, nem operação real contínua por 42 horas. A integração das falas, memes, marcadores, meta de presentes e efeitos pagos entre rodadas deve passar por revisão no checkpoint do coordenador.
