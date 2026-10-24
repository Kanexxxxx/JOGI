# Persistência local da corrida

`AudienceDirector` exporta e importa estado validado; `RaceSessionStore` grava apenas dados locais. A integração com a corrida e o ACK pertence ao coordenador da cena. Estes módulos não abrem lives nem conectam plataformas.

## Contrato de armazenamento

```gdscript
var store: RaceSessionStore = RaceSessionStore.new("tiktok")
var committed: bool = store.append_gift(clean_envelope)
# Enviar ACK somente quando committed for true e o evento tiver sido aplicado.
var cursor: int = store.get_journal_cursor()
var saved: bool = store.save_snapshot({
    "journal_cursor": cursor,
    "audience": audience.export_state(),
    # O coordenador acrescenta rodada, relógio, metros, vitórias e demais campos necessários.
})
```

Os únicos canais aceitos são `local`, `tiktok` e `kwai`. Cada canal tem arquivos próprios em `user://sessions/<canal>/`. É necessário um único escritor por canal. Caminhos arbitrários e segmentos `..` são recusados. Os testes usam exclusivamente `user://session-store-tests/<identificador>/` e removem somente seus próprios arquivos conhecidos.

`save_snapshot(state)` devolve `bool`. O arquivo contém `schema_version: 1`, `channel`, `saved_at_unix_ms` e `state`. Primeiro é escrito e descarregado `snapshot.json.tmp`; o snapshot anterior válido vira `snapshot.json.bak` mediante temporário; depois o novo temporário substitui `snapshot.json`. Um arquivo principal corrompido não sobrescreve um backup válido. Temporários abandonados não são importados.

`load_snapshot()` devolve o dicionário `state`. Erros devolvem `{}` e preenchem `last_error`; um estado vazio válido pode igualmente devolver `{}`, portanto o chamador deve consultar `last_error`. Se o principal for ilegível e o backup válido, `loaded_from_backup` é `true` e `last_error` permanece vazio. A validação específica da corrida cabe ao coordenador; o armazenamento valida o wrapper e os tipos JSON.

## Presentes, cursor e reinício

`append_gift(envelope)` aceita apenas envelopes normalizados de presente, inclusive `coin_value: 0` para preço desconhecido. Acrescenta um registro JSON com quebra de linha em `gifts.jsonl`, chama `FileAccess.flush()` e verifica o resultado antes de devolver `true`. Ele não aplica o efeito nem envia ACK.

`get_journal_cursor()` devolve o comprimento do journal em **bytes**, não em caracteres. Um arquivo ausente tem cursor zero. Erros devolvem `-1`. O checkpoint deve guardar o cursor somente após todos os presentes até esse ponto terem sido aplicados ao estado que está sendo salvo.

No reinício:

1. Carregar e validar o snapshot da corrida.
2. Importar `snapshot.audience` por `AudienceDirector.import_state()`.
3. Ler `load_gifts_since(snapshot.journal_cursor)` e verificar imediatamente `last_error`.
4. Reaplicar os envelopes retornados; salvar o novo checkpoint com `last_replay_cursor` somente depois da aplicação completa.

`load_gifts_since()` devolve `Array[Dictionary]` com envelopes, preserva a ordem e não altera arquivos. Cursor no meio de um registro, JSON inválido, presente inválido, última linha incompleta ou limite excedido fazem a leitura inteira devolver array vazio com `last_error`. `last_replay_cursor` permanece no cursor solicitado. Um erro de recuperação não autoriza avançar o checkpoint ou ACKs como se a cauda tivesse sido aplicada. Uma cauda incompleta também bloqueia novos appends; o módulo não a apaga automaticamente.

Cada chamada pública limpa `last_error` no início; consulte-o antes de chamar outra operação. `FileAccess.flush()` protege contra perda do buffer do processo; durabilidade física perante corte de energia ou falha do disco não foi comprovada.

## Limites

| Dado | Limite | Comportamento ao exceder |
|---|---:|---|
| Snapshot JSON | 64 MiB | Falha sem substituir o principal válido |
| Journal por canal | 2 GiB | Append falha e não deve receber ACK |
| Registro de presente | 16 KiB | Registro recusado |
| Uma leitura de cauda | 32 MiB / 20.000 registros | Erro sem replay parcial |
| Profundidade JSON | 32 | Estado recusado |
| Entradas em um container JSON | 150.000 | Estado recusado |
| Inteiro JSON exato | `±9.007.199.254.740.991` | Estado recusado para evitar arredondamento |
| Escolhas de torcida | 5.000 usuários | Cache FIFO dos usuários rastreados |
| IDs de eventos | 5.000 | Janela limitada de deduplicação |
| Ledger de doadores | 100.000 | `ranking_limited` passa a `true`; totais existentes são preservados |

O journal não é compactado ou rotacionado automaticamente. A garantia de deduplicação do `AudienceDirector` é limitada aos IDs retidos; não se deve descrevê-la como histórico ilimitado.

## Estado de audiência

`export_state()` contém versão, usuários, ordem de retenção, doadores, IDs de eventos, contagens da rodada/sessão e indicador de limite. O Top 5 é reconstruído a partir do ledger validado. O cooldown é salvo como duração restante; timestamps monotônicos do processo anterior não são reutilizados.

`import_state(state)` valida campos, tamanhos, nomes, slots internos `0/1/2`, moedas, contagens e IDs em estruturas temporárias. Um erro devolve `false` sem alterar a sessão atual. O sucesso não emite cartões, sons, agradecimentos ou atualização de ranking. A cena pode atualizar o HUD explicitamente após a recuperação.

`reset_round()` preserva escolhas, ledger e deduplicação. `reset_session()` limpa todos esses dados. Preços desconhecidos continuam sendo zero; curtidas e compartilhamentos não viram moedas.

As contagens incluem `votes`, `coins`, `likes`, `shares`, `gifts` e `follows`, sempre em arrays `[neutro, Lula, Flávio]`. `gifts` soma a quantidade incremental de presentes (`repeat_count` já normalizado pelo bridge); `coins` soma o valor total desse delta uma única vez. Um novo seguidor emite participação e `moment_requested("follow", team, display_name)` sem criar moedas. O schema continua na versão 1: checkpoints antigos sem `gifts`/`follows` importam esses campos como zero, pois a quantidade histórica ausente não deve ser inventada.

## Coordenador da corrida

`RacePersistence` é um Node isolado, ligado pela cena principal após criar corrida, audiência e bus:

```gdscript
var persistence: RacePersistence = RacePersistence.new()
add_child(persistence)
var ok: bool = persistence.setup(race, audience, bus, "tiktok")
```

`setup()` é síncrono: valida todo o snapshot e toda a cauda antes da mutação, pausa a simulação durante a restauração e conserva a pausa que havia sido salva. Não calcula tempo transcorrido fora do programa. Depois restaura fase, rodada/ciclo, vitórias, relógios, metros, velocidades, bônus/escudos/tropeços, votos/contadores e até 200 obstáculos pendentes. Os obstáculos mantêm seu deslocamento Z em relação ao alvo; áreas mais de um metro atrás do alvo já foram ultrapassadas e não voltam ao checkpoint.

A metadata `race.restoring_session` fica `true` durante a restauração/replay. Os consumidores de áudio, cartões e cutscenes devem consultá-la para suprimir reações históricas. O catálogo de rodada é selecionado antes de importar a audiência para que `round_changed` não apague contagens recuperadas.

`is_ready`, `recovered` e `last_error` informam o resultado. `flush_snapshot()` grava sob demanda; `_process` tenta gravar a cada 30 segundos, inclusive com a corrida pausada. A primeira inicialização e a recuperação gravam um checkpoint imediatamente. Cada presente novo passa pelo `bus.gift_commit_hook` antes da aplicação e do ACK. O hook persiste o envelope já sanitizado e pausa a corrida se a gravação falhar.

O checkpoint inclui IDs recentes do bus além do estado da audiência e do cursor. O replay também deduplica IDs repetidos dentro da própria cauda. A restauração não chama `start_running()` e, portanto, não relança o bônus dos votos do lobby.

Snapshot corrompido, cauda ilegível ou estado semanticamente inválido fazem `setup()` devolver `false`, pausar a corrida e manter um hook que recusa presentes. O arquivo corrompido não é sobrescrito. Journal não vazio com todos os checkpoints ausentes também falha: como o baseline é gravado antes de aceitar presentes, não é seguro tratar esse histórico como uma partida nova. O operador deve resolver a recuperação antes de liberar ACKs.

Este coordenador mantém um único escritor por canal. A serialização e a gravação ainda são síncronas; impacto no frame time deve ser medido com o volume real de público antes de declarar 60 FPS contínuos.

## Verificação

`game/tests/test_session_persistence.gd` testa transporte JSON, importação silenciosa, relógio monotônico reiniciado, estado corrompido sem mutação parcial, replay de cauda uma vez, recuperação de backup, temporário abandonado, journal incompleto, path traversal e limites de leitura. `game/tests/test_race_persistence.gd` testa recuperação da corrida, pausa, efeito de presente exatamente uma vez, ataque pendente, intervalo de 30 segundos, corrupção e falha de gravação antes da aplicação. `game/tests/test_audience_director.gd` cobre interação e o ledger com 100.002 presentes. São testes locais acelerados; não comprovam uma live real de 32 horas ou FPS durante gravação.

Referências técnicas: [FileAccess.flush](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html#class-fileaccess-method-flush), [DirAccess.rename](https://docs.godotengine.org/en/stable/classes/class_diraccess.html#class-diraccess-method-rename).
