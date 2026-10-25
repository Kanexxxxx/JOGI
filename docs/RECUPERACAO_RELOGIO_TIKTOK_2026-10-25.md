# Recuperação do Godot TikTok — 25/10/2026

Causa reproduzida em cópia isolada do checkpoint: a soma incremental do tempo chega a600.00000000000034, excedendo a duração600.0. O validador rigoroso rejeita o snapshot e RacePersistence entra em pausa de proteção (invalid_runtime_checkpoint). O early-return da física pausada também impedia telemetria periódica, e o painel bloqueava resume quando a telemetria envelhecia.

Uma única tentativa autenticada de resume recebeu ACK real rejected; o processo estava responsivo, não congelado. A proteção de persistência não foi removida. O relógio agora é calculado como complemento da duração menos o tempo restante, limitado ao intervalo legítimo, encerrando exatamente em600.0. A pausa mantém heartbeat. O painel permite apenas pause/resume sem telemetria recente quando o socket está conectado e a sessão está autenticada; demais operações continuam bloqueadas, assim como resume com persistência sabidamente inválida. Diagnósticos do validador não contêm dados de espectadores.

O operador autorizou interrupção breve da imagem se necessária. O Studio foi consultado e mostrava resumo de LIVE encerrada (56s). Não foram iniciadas/encerradas transmissões nem alteradas cenas.

Backup íntegro local: LOCALAPPDATA/JOGI/backups/tiktok-clock-recovery-20261025-004831. Snapshot principal/backup e SQLite foram copiados e verificados. Não existiam presentes pendentes ou journal pago nesta sessão. O último checkpoint válido parava17,75s antes da chegada. Ele foi conciliado com a última telemetria autenticada: mesma rodada17, resultado e vitórias12x5,17 registros de histórico, distâncias finais7200.181640625/7199.80517578125m,15 IDs deduplicados. O estado integral da audiência no checkpoint correspondia ao runtime. Campos não expostos continuaram com seus valores do último checkpoint válido. O novo checkpoint foi validado pelo próprio RacePersistence em processo isolado antes de substituição atômica. Originais preservados, sem limpar deduplicação ou reiniciar a partida do zero.

Somente Godot TikTok56244 foi fechado normalmente. Supervisor existente reabriu41908; backend35692 continuou ativo, sem reinício do coletor. Kwai não sofreu intervenção. A recuperação carregou o resultado da rodada17 e seguiu normalmente para18.

Medição real de30s: cronômetro584.95→554.85s; Lula180.41→541.77m; Flávio180.83→542.19m;60FPS; telemetria com idade0.03–0.10s; persistence.ready=true; checkpoint_recovered=true; zero presentes pendentes. Ver clock-recovery-motion-20261025.json.

Regressões isoladas verificam valores de ponto flutuante do incidente, checkpoint após chegada, passagem do pódio à próxima rodada, heartbeat com pausa, restauração de sessão e cards. Teste SDKCommentEvent→backend→Godot/HUD permanece isolado, sem consultas externas ou espectadores fictícios em produção. Um novo comentário real em captura pública continua dependente de sala e autorização; não foi usado como condição para recuperar o relógio.

As alterações da vitrine/equipes de presentes ficaram preservadas em trabalho separado e não foram misturadas ao carregamento de emergência.
