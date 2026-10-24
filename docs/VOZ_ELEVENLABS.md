# Voz e efeitos da corrida

O runtime `RaceAudio` reproduz alertas locais, com fila limitada e sem chamadas de API. A chave foi configurada localmente e as **30 falas do pacote inicial foram geradas em cache**, com 931 caracteres de texto. A escuta final e a captura no programa de transmissão ainda precisam ser conferidas. A API confirmou plano Starter com limite de 40.000 e saldo de 39.566 após o lote complementar de quatro SFX, que custou 60 créditos. O contador de uso total retornou 434. A implementação e os testes simulados não consomem créditos.

O manifesto configura três perfis de vozes originais: narrador esportivo, equipe vermelha e equipe Brasil. Não clonamos nem imitamos Lula ou Flávio Bolsonaro. As frases descrevem apenas ações da partida, com quantidade de variantes, prioridade e intervalo iguais para as duas equipes. Os SFX e seu pool separado estão documentados em [SFX_ELEVENLABS.md](SFX_ELEVENLABS.md).

## Configurar sem enviar a chave ao chat

1. Abra `CONFIGURAR_VOZ.cmd` por duplo clique nesta pasta.
2. Cole a chave na janela de terminal e pressione Enter. A entrada fica oculta. Ela é gravada em `.env.local`, que já está ignorado pelo Git; as demais variáveis do arquivo são preservadas.
3. O configurador consulta a assinatura via GET e mostra somente plano, uso e saldo disponível. Não gera fala, não compra créditos e não altera a assinatura.
4. Informe no chat apenas que terminou. A chave permanece local; não envie o conteúdo de `.env.local`.

É possível fornecer `ELEVENLABS_API_KEY` no ambiente do processo em vez do arquivo. A variável do ambiente tem prioridade. Não existe argumento `--api-key`, log de chave ou chave incorporada ao jogo.

## Consultas e preparação

Na raiz do projeto:

```powershell
py tools/elevenlabs_audio.py status
py tools/elevenlabs_audio.py voices
py tools/elevenlabs_audio.py plan
```

`status` usa `GET /v1/user/subscription`; `voices` usa `GET /v2/voices` com paginação limitada. O programa não imprime faturas ou dados do titular. Esses comandos não geram áudio. `plan` é inteiramente offline, mostra as 30 frases e conta caracteres sem exigir chave.

Depois de ouvir as prévias disponíveis no site e escolher três vozes originais, use os **IDs públicos das vozes**, não a chave:

```powershell
py tools/elevenlabs_audio.py select-voices --narrator ID_NARRADOR --team1 ID_EQUIPE_1 --team2 ID_EQUIPE_2 --confirm-original-voices
py tools/elevenlabs_audio.py plan
```

A seleção verifica se os IDs estão disponíveis, exige vozes distintas para as equipes e aceita apenas categorias `premade` ou `generated`. Ela bloqueia categorias clonadas e nomes/descrições de imitação de figuras políticas. Essa filtragem complementa a escolha humana de uma voz original; ela não prova identidade ou direitos de terceiros.

O manifesto é `game/resources/audio/voice_manifest.json`. Em uma configuração nova, as vozes começam com IDs vazios e `original_synthetic: false`; nesta máquina elas já foram selecionadas e o pacote já foi gerado. O pacote inicial tem menos de 1.000 caracteres e um limite rígido de **2.000 caracteres**, usando `eleven_multilingual_v2`. Não há geração por nome de espectador nem por comentário livre.

## Geração explícita e cache

```powershell
# Sem --execute: apenas o plano, sem rede.
py tools/elevenlabs_audio.py generate

# Envia os textos e consome os créditos incluídos, após vozes configuradas.
py tools/elevenlabs_audio.py generate --execute
```

O gerador confirma modelo disponível e saldo incluído suficiente antes do primeiro POST. O formato é MP3 44,1 kHz / 128 kbps. O custo efetivo deve ser conferido na conta; o limite local controla caracteres, e o programa não habilita cobrança excedente.

Cada arquivo fica em `game/assets/audio/elevenlabs/<sha256>.mp3`. O hash inclui texto, voz, modelo, configurações, formato e seed. Um arquivo existente nunca é sobrescrito. O diário registra estado antes do POST e hash do áudio concluído; execuções posteriores reutilizam somente arquivos confirmados e íntegros. Textos/vozes diferentes criam outros arquivos, preservando os anteriores.

Um lock exclusivo também impede duas gerações simultâneas em terminais diferentes. Se o processo for encerrado à força, confira o processo e o histórico antes de remover o arquivo `.generation.lock` deixado no cache.

Não há repetição automática de POST, inclusive em timeout. Uma operação interrompida fica `pending` ou `uncertain` no `generation_journal.json` e bloqueia nova cobrança daquele clipe. Antes de recuperar esse caso, confira o histórico ElevenLabs e recupere o áudio já gerado, se existir. Não apague o diário para tentar novamente sem conferir o consumo.

As requisições têm timeout de 45 segundos, respostas limitadas e redirecionamentos desativados para não encaminhar o header de autenticação. Erros retornam apenas mensagens sanitizadas, sem headers/corpos remotos.

Após a geração, ouça os clipes para verificar pronúncia, volume e começo/fim. O estado `generated_pending_listening_review` registra que essa escuta ainda é necessária. Os mesmos arquivos podem ser reutilizados durante as 32 horas: reproduzi-los localmente não aciona a API.

## Integração Godot

```gdscript
var audio: RaceAudio = RaceAudio.new()
add_child(audio)
audio.play_event("start")
audio.play_event("boost", 1)
audio.play_event("shield", 2)
audio.play_event("attack", 1) # Equipe que recebe o obstáculo.
audio.play_event("podium", 2)
audio.play_event("tie")
```

Eventos aceitos: `start`, `tie`, `boost`, `shield`, `attack`, `super_turbo`, `podium`, `vote`. `team` é 0 para eventos neutros, 1 para equipe vermelha e 2 para equipe Brasil. Os aliases `round_start` e `turbo` são aceitos. `clear_pending()` limpa fila e cooldowns ao reiniciar a rodada. `enabled` e `local_cues_enabled` permitem silenciar o módulo ou apenas o fallback.

A fila tem no máximo oito itens, preserva a ordem em prioridades iguais e troca um alerta de menor prioridade por um novo mais importante. Cada evento/equipe tem cooldown próprio, os alertas expiram após seis segundos e só um clipe toca por vez, com intervalo mínimo de 0,45 segundo. As variantes alternam sem sortear vantagem entre equipes. O barramento `RaceAnnouncer` tem limiter em -1 dB, e os tons de fallback tocam com volume reduzido.

`voices_ready` e `voice_status` identificam se os arquivos locais estão completos. Sem arquivos, o sistema mantém `vozes_pendentes` e pode tocar pequenos tons de evento. Os tons não são apresentados como vozes ElevenLabs. `cue_started(kind, team, has_voice)` diferencia fala real em cache de tom local.

O runtime só aceita caminhos diretos `res://assets/audio/elevenlabs/<64 dígitos hexadecimais>.mp3`, lê os bytes locais e não contém cliente HTTP ou acesso a `.env.local`.

## Verificação

```powershell
py -m unittest tools.test_elevenlabs_audio -v
$env:GDA_GODOT = 'C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
& 'C:\Users\Kanex\.local\bin\gda.exe' project scan --project game --json
& 'C:\Users\Kanex\.local\bin\gda.exe' script validate res://scripts/race_audio.gd --project game --json
& 'C:\Users\Kanex\.local\bin\gda.exe' script run res://tests/test_race_audio.gd --project game --strict --timeout 25 --json
```

Os testes Python simulam o transporte e o armazenamento em diretórios temporários: orçamento, simetria, segredo oculto, host/timeout, paginação, recusa de vozes clonadas, cache íntegro, saldo insuficiente e bloqueio após cobrança incerta. O teste Godot verifica fila, prioridade, cooldown separado por equipe, expiração, caminhos locais, reprodução sem sobreposição e fallback honesto. Eles não comprovam qualidade de uma voz ainda não gerada nem a captura de áudio no OBS/TikTok Studio.

## Fontes oficiais consultadas

- [Assinatura e consumo](https://elevenlabs.io/docs/api-reference/user/subscription/get): campos de uso e limite retornados pelo GET.
- [Catálogo de vozes](https://elevenlabs.io/docs/api-reference/voices/search): listagem v2, IDs, categorias e paginação.
- [Text to Speech](https://elevenlabs.io/docs/api-reference/text-to-speech/convert): POST, `model_id`, seed, configurações e formatos MP3.
- [Modelos](https://elevenlabs.io/docs/overview/models): suporte a português do Multilingual v2.
