# Efeitos sonoros da corrida

Quatro SFX curtos complementam a locução, com os mesmos arquivos para as duas equipes:

| Evento | Som | Duração solicitada |
| --- | --- | --- |
| boost | Whoosh de impulso | 1,0 s |
| shield | Brilho sonoro de proteção | 1,2 s |
| impact | Impacto cômico de desenho | 0,8 s |
| victory | Fanfare original curta | 3,0 s |

São seis segundos ao todo, sem voz ou melodia de terceiros. O manifesto é `game/resources/audio/sfx_manifest.json`; os MP3 ficam em `game/assets/audio/elevenlabs-sfx/`. Não existe geração durante a live.

**Lote concluído:** quatro MP3 gerados, decodificados pelo Godot com durações de 1,0 / 1,2 / 0,8 / 3,0 segundos. Os headers da API retornaram **60 créditos** no total; a atualização posterior da assinatura confirmou uso de 434 de 40.000 e saldo de 39.566. A escuta final permanece pendente. Nenhum pedido foi repetido.

## Orçamento e geração

O plano local é executado antes da geração:

```powershell
py tools/elevenlabs_sfx.py plan
py tools/elevenlabs_sfx.py generate --execute
```

Sem `--execute`, o comando não acessa a rede. A documentação de capacidades informa 40 créditos por segundo com duração definida; a página de preços também cita aproximadamente 200 créditos por geração. O plano usa o maior valor de cada descrição, somando um **teto conservador estimado de 800 créditos**, abaixo do limite local de 1.000. São permitidos exatamente quatro arquivos e até oito segundos no pacote inicial.

O gerador usa o mesmo cliente seguro/configuração local do TTS, sem imprimir a chave. Consulta saldo incluído, usa duração explícita e `eleven_text_to_sound_v2`, registra o diário antes de cada POST e nunca repete uma operação automaticamente. Há lock entre processos, cache por hash do pedido e formato, verificação da integridade e preservação dos arquivos existentes. Operações incertas ficam bloqueadas para consulta ao histórico. O custo devolvido no header `character-cost`, quando presente, e a diferença de uso da conta são apresentados no resultado final; outras operações simultâneas também podem afetar essa diferença de conta.

## Runtime Godot

```gdscript
var effects: RaceSoundEffects = RaceSoundEffects.new()
add_child(effects)
effects.play_event("boost", 1)
effects.play_event("shield", 2)
effects.play_event("impact", 1)
effects.play_event("victory")
effects.set_ducked(true) # Baixa seis dB enquanto o narrador fala.
effects.set_paused(true)
effects.stop_all() # Reinício da rodada.
```

`RaceSoundEffects` usa um pool fixo de quatro players no barramento `RaceSFX`, separado do narrador. O volume padrão é -16 dB e há limiter em -1 dB. Cooldowns agrupam rajadas de sons idênticos; uma fanfare pode substituir um som de menor prioridade. Sons comuns não interrompem sons de prioridade igual ou maior. A pausa congela playback e relógio, e o ducking reduz mais seis dB para preservar a inteligibilidade da locução.

Os aliases `turbo` e `super_turbo` usam boost; `attack` e `stumble` usam impact; `podium` e `tie` usam victory. A equipe é aceita para compatibilidade, mas não muda o arquivo nem o volume. Caminhos externos ou fora do cache SHA são rejeitados. Sem MP3 local válido o módulo permanece `efeitos_pendentes`, sem fingir que o serviço está online.

## Testes

`py -m unittest tools.test_elevenlabs_sfx -v` simula todos os POSTs e verifica orçamento, duração, cache, saldo, lock e bloqueio após interrupção. `game/tests/test_race_sound_effects.gd` usa PCM local simulado para verificar pool, cooldown, prioridade, pausa, ducking e mil eventos sem crescimento de players. A escuta dos MP3 gerados e o teste de captura pelo OBS/TikTok Studio continuam necessários.

Fontes oficiais: [Create sound effect](https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert), [capacidades e custo por segundo](https://elevenlabs.io/docs/overview/capabilities/sound-effects), [preços](https://elevenlabs.io/pricing).
