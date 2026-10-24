# Presentes recebidos entre rodadas

Contrato implementado em 24/10/2026.

- PHOTO_FINISH e PODIO já possuem resultado fechado. Um presente direcionado recebido nesses estados soma moedas e participação imediatamente no AudienceDirector, sem alterar distância, vencedor ou vitórias.
- Seus efeitos são reservados para a próxima largada RACING, inclusive após reinício administrativo. Comentários, curtidas e ações administrativas continuam com seu contrato anterior; não são convertidos em presentes reservados.
- A reserva possui no máximo dois agregados, um por equipe. Turbo conserva o maior incremento até 25 m/s e soma duração até 10 s (limite real do CandidateRunner); escudo conserva a maior duração até 15 s; ataques são limitados a quatro por raia alvo, espaçados em 5 m; super turbo conserva um marcador por equipe. A agregação limita mecânica, nunca o total financeiro do ranking.
- Na largada os corredores são reiniciados, começam a correr e recebem a reserva uma única vez. A reserva é limpa antes da aplicação. Os ataques usam o obstáculo de documentos existente. Não se cria uma fila ilimitada de nós.
- Gifts sem equipe seguem neutros e agradecidos, sem escolha arbitrária de candidato.

## Durabilidade e segurança

RacePersistence salva `match.pending_round_effects` no checkpoint com validação estrita dos limites. Checkpoints antigos sem o campo continuam válidos e começam com reserva vazia.

Antes de ACK, o journal local acrescenta `_reserved_next_round` a uma cópia do envelope, calculado pelo estado real da corrida. Ao recuperar um journal posterior ao checkpoint, esse contexto permite reservar o gift mesmo que o checkpoint anterior ao encerramento ainda tenha RACING. O marcador externo recebido pela conexão não controla esse comportamento: ele é sobrescrito no journal e só RacePersistence habilita o contexto interno de replay.

LiveEventBus expõe contexto somente durante a entrega síncrona e restaura o contexto anterior ao sair, preservando deduplicação e ACK existentes. Recuperação não dispara novamente agradecimentos, voz ou cutscenes de receipt. Um super turbo reservado pode iniciar sua apresentação quando a próxima rodada começar normalmente.

A câmera possui cooldown global: se as duas equipes tiverem super turbo reservado na mesma largada, os efeitos mecânicos são aplicados às duas, mas apenas uma cutscene é exibida para evitar movimentos de câmera conflitantes. Checkpoints são periódicos (30 s); após falha abrupta pode haver retorno do andamento ao último checkpoint. A reserva do presente permanece no journal, inclusive se esse checkpoint ainda mostrar a rodada anterior em corrida.

## Validação

`res://tests/test_paid_round_boundary.gd` verifica resultado fechado, ranking imediato, deduplicação, contexto limpo, replay após snapshot ainda em RACING, checkpoint no pódio, reinício, limites, aplicação uma vez, rejeição de snapshot fora do limite, compatibilidade antiga e marcador externo sem autoridade.

Regressões: `test_race_persistence.gd` e `test_stadium_integration.gd`. O segundo mantém o aviso já existente de seis objetos no encerramento headless; testes e diagnósticos estruturados passam, mas esse aviso não constitui certificação de operação contínua.
