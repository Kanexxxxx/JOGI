# Narração, torcida e soundboard local

O runtime Godot não faz chamadas à ElevenLabs nem recebe sua chave. Todos os áudios são arquivos locais; nenhum gasto ocorre durante as 42 horas previstas de jogo.

## Pacote de locução

`game/resources/audio/voice_manifest.json` contém 38 falas ativas: 26 reaproveitadas e 12 geradas nesta revisão. Quatro falas de pódio foram substituídas para anunciar explicitamente **13/Lula** e **22/Flávio**. Foram adicionadas quatro variantes de ultrapassagem, duas de últimos 30 segundos e duas de preparação da próxima rodada.

As vozes são de locutores genéricos da conta, sem imitar os candidatos. Daniel continua como narrador. Lair pt-BR foi consultado, mas não selecionado: o detalhamento atual indica `enabled_in_library=false`, sem evidência suficiente nesta revisão para trocar a voz. Os clipes antigos e o diário de geração foram preservados; o manifesto anterior também está em `docs/evidencias/audio/voice_manifest-before-race-commentary.json`.

Novos comandos:

```gdscript
audio.set_current_leader(team)  # Toda troca confirmada, antes de qualquer throttle.
audio.play_event("overtake", 1)  # 1 = 13/Lula; 2 = 22/Flávio
audio.play_event("final_stretch")
audio.play_event("next_round")
audio.set_paused(paused)
var speaking: bool = audio.is_voice_playing()
```

Uma ultrapassagem mais recente substitui outra ainda enfileirada, e expira em 2,5 segundos se não puder ser narrada. `set_current_leader()` cancela anúncios contrários enfileirados ou em reprodução sem criar nova fala nem ampliar cooldown; zero representa empate. `play_event("overtake", team)` faz essa invalidação antes de testar o próprio cooldown, cobrindo a sequência rápida 1 → 2 → 1. A vitória limpa alertas de corrida atrasados e interrompe uma fala de prioridade inferior. A fila permanece limitada a oito; há um único player de locução. Desabilitar `enabled` interrompe a reprodução no próximo frame.

## Torcida

`game/resources/audio/ambience_manifest.json` referencia uma atmosfera original de estádio com 10 segundos, solicitada com `loop=true`, sem música, letras, cantos reconhecíveis, transmissão ou comentário de terceiros. `RaceAmbience` usa dois players fixos e transição de 0,7 segundo para suavizar as voltas do loop. A torcida fica abaixo da voz, com redução adicional de 9 dB durante a locução. O volume padrão é -27 dB; fora da corrida há redução de mais 5 dB. A pausa congela os dois players.

```gdscript
var ambience: RaceAmbience = RaceAmbience.new()
add_child(ambience)
ambience.update_state(current_state == RaceState.RACING, speed_ratio)
ambience.set_ducked(audio.is_voice_playing())
ambience.set_paused(paused)
```

O bus de torcida tem limiter; `RaceAudio` também garante limiter de -1 dB no Master para conter a soma de locução, efeitos e torcida. Isso não substitui verificar os medidores do OBS com captura real.

## Arquivos enviados pelo usuário

Os 16 arquivos MP3 indicados em Downloads foram copiados por SHA256 para `game/assets/audio/user-memes/`, sem alterar as fontes. Existem 15 conteúdos únicos: as duas versões de “setembro-vai-entrar-o-grosso-lula” são idênticas. Durações reais e nomes estão em `docs/evidencias/audio/user-memes-import-probe.json`.

`RaceMemeBoard` depende de manifesto global habilitado **e** clipe habilitado, `review_status=approved`, tipo atribuído e duração máxima de cinco segundos. A importação inicial deixa todos pendentes/desabilitados. Nomes de arquivos não aprovam conteúdo. Não há upload automático ou análise remota nesta importação.

```gdscript
memes.play_event("reaction", team)
memes.set_ducked(audio.is_voice_playing())
memes.set_paused(paused)
```

Há um único player, intervalo global de 45 segundos e intervalo mínimo de 45 segundos por clipe (padrão 60). Um meme aguarda a locução por até dois segundos; depois é descartado. Uma locução que começa interrompe o meme. `stop_all()` limpa o alerta pendente. O runtime não escolhe músicas, palavrões ou gritos pelo nome do arquivo; depende de revisão de conteúdo antes da ativação.

## Consumo confirmado e limites

Plano offline antes de gerar: 508 caracteres novos TTS e um loop SFX de 10 segundos; teto conservador combinado de 908 créditos, abaixo dos 1.500 autorizados para esta revisão. Foram efetuados 12 POST TTS e um POST SFX, sem repetição automática. A assinatura passou de 434 para 737 créditos utilizados: **303 novos**, saldo confirmado **39.263 de 40.000**. O header do SFX informou 100 créditos; a diferença de assinatura na chamada SFX inclui atualização atrasada do consumo TTS. Não foi contratada compra, upgrade ou cobrança excedente.

A obtenção de vozes e o planejamento são GET/local. Cada geração escreve diário antes do POST; respostas interrompidas ficam incertas e não são repetidas. Os caches concluídos são validados por hash.

Fontes oficiais consultadas: [Voice Library](https://elevenlabs.io/docs/eleven-creative/voices/voice-library), [plano Starter/licença](https://elevenlabs.io/pricing), [geração de SFX e loop](https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert). A origem solicitada dos novos efeitos reduz dependência de gravações externas; nenhuma garantia de ausência de remoção por plataformas foi prometida.

## Verificação

20 testes Python passam (`tools.test_elevenlabs_audio`, `tools.test_elevenlabs_sfx`, `tools.test_import_user_memes`). GDA valida os três scripts de áudio alterados/adicionados. Os testes `test_race_audio`, `test_race_ambience`, `test_sfx_cached` e `test_race_meme_board` passam com exit_status 0 e diagnostics vazios.

O teste de torcida avança 160.000 segundos de relógio lógico, sem crescimento de Nodes, com dois players, pausa/mute/ducking verificados. Isso verifica limites internos e **não equivale a um ensaio real de 42 horas**. MP3 de voz, torcida e efeitos foram decodificados pelo Godot com duração válida. Escuta humana, revisão dos memes e medição de áudio capturado pelo OBS continuam distintas destas validações automatizadas.
