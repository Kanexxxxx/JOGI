# Entrega de interações e persistência — 24/10/2026

Verificação local renovada aproximadamente às 06:32 BRT. Integração final da cena e das plataformas pertence ao coordenador principal.

## Arquivos

| Arquivo | Responsabilidade |
|---|---|
| `game/scripts/audience_director.gd` | Participação, torcida, seguidores, quantidades de presentes, moedas e Top 5 |
| `game/scripts/race_session_store.gd` | Snapshot JSON, backup, journal de presentes e cursor em bytes |
| `game/scripts/race_persistence.gd` | Restauração da corrida, replay e checkpoint periódico de 30 segundos |
| `game/tests/test_audience_director.gd` | Interações, nomes, dedup, cooldown, Top 5, seguidores e capacidade |
| `game/tests/test_session_persistence.gd` | Transporte JSON, migração, corrupção, backup e limites do armazenamento |
| `game/tests/test_race_persistence.gd` | Restauração de fase/relógio/efeitos/obstáculos e falha de gravação antes de ACK |
| `docs/PERSISTENCIA_LOCAL.md` | Contrato completo, sequência de recuperação e limites operacionais |

## Contratos finais

`AudienceDirector.setup(bus)` conecta ao sinal `live_event_accepted`. `ingest_event(envelope)` aceita eventos normalizados `vote`, `gift`, `like_batch`, `share` e `follow`.

- `participation_received(Dictionary)`: `display_name`, `team`, `kind`, `amount`, `gift_quantity`, `joined`, `switched_team`, `source`.
- `leaderboard_changed(Array[Dictionary])`: até cinco entradas com `display_name`, `team`, `coins`; desempate por identidade estável.
- `moment_requested(kind, team, display_name)`: `join`, `gift`, `like_batch`, `share` ou `follow`.
- Slots internos: `0` neutro, `1` Lula, `2` Flávio. Comandos públicos `13`/`22` devem ser convertidos pelo bridge. O helper local também preserva `#1`/`#2`.

`get_snapshot()` expõe `participants`, `participants_by_team`, `round`, `session`, `top_supporters`, `ranking_limited` e capacidades. Cada escopo de contagens possui `votes`, `coins`, `likes`, `shares`, `gifts`, `follows`, sempre em arrays `[neutro, Lula, Flávio]`.

`coin_value` já contém o valor total do delta de presentes e é somado uma vez. `gifts` soma separadamente `repeat_count`, que já deve ser incremental no envelope. Preço desconhecido (`coin_value: 0`) recebe agradecimento sem criar moedas. Curtidas, comentários, compartilhamentos e seguidores nunca geram moedas no ranking.

`export_state()` e `import_state(Dictionary)` conservam escolhas, doadores, contagens, IDs e cooldown restante. A importação é silenciosa, validada e transacional. O schema permanece na versão 1: checkpoints anteriores sem `gifts` e `follows` importam esses campos como zero.

`RaceSessionStore.new(channel)` aceita apenas `local`, `tiktok` e `kwai`. Métodos: `save_snapshot`, `load_snapshot`, `append_gift`, `get_journal_cursor`, `load_gifts_since`. Consultar `last_error` imediatamente depois da operação. O journal é descarregado por `flush()` antes de devolver sucesso.

`RacePersistence.setup(race, audience, bus, channel, store_override)` devolve sucesso; `is_ready`, `recovered` e `last_error` informam o estado. `flush_snapshot()` grava sob demanda. O componente não avança relógio durante o período em que o programa estava fechado. Falhas de recuperação/gravação pausam e bloqueiam presentes pelo hook. Durante a recuperação, a metadata `restoring_session` permite que a cena suprima reações históricas.

## Resultado dos testes

As três suítes foram executadas novamente com `gda script run ... --strict --json`: `exit_status: 0`, `stderr: ""`, `diagnostics: []` para todas.

- `TEST_AUDIENCE_DIRECTOR_PASSED`: Top 5 e troca do último colocado, seguidores sem moedas, deltas de combo, preço desconhecido, troca de equipe, sanitização, duplicatas e 100.002 eventos de presente no teste de capacidade.
- `TEST_SESSION_PERSISTENCE_PASSED`: importação silenciosa, migração do schema 1 antigo, novo relógio monotônico, corrupção sem mutação parcial, recuperação do backup, temporário abandonado, proteção de caminhos e limites.
- `TEST_RACE_PERSISTENCE_PASSED`: interrupção após checkpoint e replay de cauda uma vez, rodada/ciclo/pausa/relógio/metros/efeitos preservados, obstáculo pendente com Z relativo, checkpoint de 30 segundos e recusa de aplicação quando a gravação falha.

Os testes usam diretórios exclusivos em `user://session-store-tests/`. Nenhum teste remove sessões reais em `user://sessions/`.

Esses resultados comprovam as rotinas locais testadas. Não comprovam elegibilidade das contas, recebimento de eventos reais, FPS com público real nem transmissão contínua de 32 horas.
