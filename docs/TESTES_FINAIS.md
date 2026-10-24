# Validação final — retorno de 24/10/2026

Este documento registra execução real, não constitui certificação de 42 horas.

## Preparação do benchmark simultâneo

Ferramentas: `tools/benchmark_dual_game.py` e `tools/benchmark_game.gd`.

- Duas instâncias GPU da cena `stadium_race.tscn`, com `LIVE_PLATFORM` separado e `TESTE LOCAL` no vídeo.
- Dois bridges autenticados em portas efêmeras, sem usar 8765/8766 nem os bancos do operador.
- Tokens gerados apenas em memória e ambiente dos processos filhos. Bancos sintéticos ficam em `LOCALAPPDATA/JOGI/benchmarks`.
- A persistência real do jogo é exercitada com `RaceSessionStore` privado em `user://session-store-tests/dual_benchmark_<id>/{tiktok,kwai}`. Não abre os checkpoints das sessões reais; confirma journal antes de ACK e snapshots periódicos/final.
- Barreira comum somente após os dois renderizadores e WebSockets autenticados estarem prontos.
- Duração padrão: **620 segundos reais**; compara início/fim para comprovar intervalo simultâneo de pelo menos 600 segundos.
- Eventos sintéticos durante o teste: comentários, presentes de todos os níveis, super turbo elevado, curtidas e seguidores. Nenhuma API paga ou sala pública.
- Amostras a cada 5 s: CPU/RAM do PID real do renderizador, utilização/VRAM total da GPU, nós/recursos/órfãos, memória do renderizador e filas/ACKs.
- FPS e percentis usam intervalos brutos monotônicos (`Time.get_ticks_usec`) de todos os frames após 2 s de aquecimento, sem depender do delta suavizado pelo Godot. Uso GPU/VRAM do `nvidia-smi` inclui todos os aplicativos, não somente os dois jogos.
- OBS/codificação e fontes reais TikTok/Kwai não entram nesse ensaio; precisam de verificação própria.

Comando reproduzível:

```powershell
services\live_bridge\.venv\Scripts\python.exe tools\benchmark_dual_game.py --seconds 620
```

## Smoke anterior ao ensaio de dez minutos

`docs/evidencias/benchmark/dual-20261024T200941Z/report.json`: dois jogos por aproximadamente 5 s, ambos 1080×1920 e cerca de 60 FPS, um presente sintético confirmado por canal e nenhuma pendência. Isso valida o instrumento, **não** o requisito de dez minutos.

Hardware consultado nesta sessão: AMD Ryzen 7 5700X, 16 processadores lógicos, 17.084.563.456 bytes de RAM; NVIDIA RTX 4060 com 8.188 MiB reportados. A coleta mede o PID informado pelo próprio Godot, pois o executável `_console.exe` é um encaminhador com outro PID e não representa o consumo do renderizador.

**Ensaio de 620 s concluído:** `docs/evidencias/benchmark/dual-20261024T201613Z/report.json` registrou 620,39 s de intervalo simultâneo e resultado `passed`. Os dois renderizadores terminaram com código zero em 1080×1920, sem erros de engine, rejeições ou órfãos; cada bridge confirmou 78 ACKs de presentes, sem fila pendente, e ambos salvaram o snapshot final. FPS médio: **59,99 TikTok** e **59,95 Kwai**; p99 de frame: **17,24 ms** e **17,27 ms**, respectivamente. Os critérios automatizados do relatório passaram. O ensaio continua sem OBS/encoding nem fontes reais de live, conforme os limites acima.
