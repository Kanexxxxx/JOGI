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


## Estabilização final de produção e conta — 24/10/2026

- Backend final: **116 testes +48 subtestes aprovados**, 2 avisos de depreciação do SDK, em73,94 s. Evidência: `evidencias/producao/pytest-final-serial.txt`. Uma execução concorrente anterior teve timeout de 10 s no subprocesso do teste de crash e avisos de cache; mantida em `pytest-final-account.txt`. O mesmo caso passou isolado em2,19 s e a suíte completa passou depois, sem alterar o teste de crash.
- Godot: **32 scripts SceneTree strict aprovados**, incluindo corrupção de checkpoint, bloqueio de dados legados e separação de contas. `evidencias/producao/godot-suite-account-final.json`.
- Scan sem erros de engine; cena válida e preflight `started:true`, `ready`, diagnostics[]. Arquivos `*-account-final.json` em `evidencias/producao`.
- Node:8 testes do coletor Kwai aprovados, incluindo preço unitário, combos/zero, reenvio HTTP e ACK durável.
- Painel: `evidencias/admin-production/report.json`, FUNCTIONAL_PASS com dois bridges autenticados efêmeros e dois Godot reais headless. Exercita comandos aplicados, metas, áudio, reconexão, HTTP fallback, isolamento, persistência de término offline e autenticação. Sem sala real.
- Carga GPU de120 s: `evidencias/benchmark/dual-20261024T220659Z/report.json`, 1000 identidades por plataforma, 200 presentes únicos cada,600 unidades/24150 moedas por canal; sem duplicação/rejeição/pendência, ACKp95 cerca de 44 ms, FPS59,92/59,90. Não inclui codificação OBS ou coletor real.
- Carga backend: `evidencias/load/load-20261024T215739Z.json`, consumidores sintéticos duráveis claramente identificados,1000 identidades/300 presentes únicos por plataforma,2250 moedas por canal. Crash/restart do próprio worker TikTok com um ACK retido recuperou pagamentos sem duplicar; Kwai continuou independente. Eventos gratuitos em RAM podem se perder na queda, contabilizados separadamente. Não é execução Godot.
- Capturas nativas finais: `evidencias/estadio/producao-encerramento-final/`,20 imagens em1080x1920/720x1280/540x960/360x640, dia/ultrapassagem/noite/pódio/encerrado. Principal inspecionou tela terminal540x960: velocidades zero, agradecimento, sem CTA/habilidades/evento antigo. Posições450/480m nos cenários visuais são fixtures controladas; não são resultado de público real. Captura dia vazia preserva contadores zero.
- Ensaio final concorrente `dual-20261024T231435Z`: integridade/eventos passou, mas médias47,90/48,85 FPS ficaram abaixo do alvo; executado simultaneamente com pytest e QA de mais dois Godot. Não conta como aprovação de desempenho 60 FPS. Resultado e limitação preservados.

### Inicialização e aplicativos

`evidencias/producao/diagnostico-inicializacao-final.txt` verificou executáveis e conta nova no plano. As portas 8765/8766 pertencem a processos antigos preservados; health TikTok ainda informa nostalgiia.br e aguardando sala; Kwai informa mentalista.. e requires_collector;8786 não está escutando. Isso é um bloqueio operacional concreto para abrir novos serviços nessas mesmas portas, não autorização para matar processos.

`DIAGNOSTICAR_JOGO.cmd` é somente leitura. `ABRIR_PREVIA_JOGO.cmd` define development; atalhos de operação definem production e usam o Python real da.venv. Os launchers não iniciam transmissão pública. O erro histórico exato informado pelo usuário não veio acompanhado de log; não se atribui causa única sem evidência.

Captura definitiva, gravação local com áudio isolado, conta@xinka_ autenticada e permissões/eventos reais ainda não estão homologados. Consulte `evidencias/CONFIGURACAO_APPS_2026-10-24.md` e os guias. Não houve uso de API paga ou transmissão pública. Testes curtos não certificam 42 horas.


### Repetição gráfica final sem testes concorrentes

`evidencias/benchmark/dual-20261024T231858Z/report.json`: 90 segundos, ambos em 1080×1920, fontes inalteradas, todos os critérios de integridade aprovados e `performance_target_met:true`. Média TikTok **59,918 FPS**, Kwai **59,923 FPS**; p95 frame TikTok **17,171 ms**, 0 órfãos. Cada canal confirmou exatamente os 200 presentes únicos de carga, 600 unidades e 24.150 moedas; ACK p95 ponte→jogo **249/247 ms**. Pico working set cerca **1045/1032 MiB**; memória de renderizador cerca **2245 MiB por jogo**. O tempo de recibo durável produtor→ponte p95 foi 105 ms, distinto do ACK de aplicação no jogo. OBS encoding e sala real continuam fora do ensaio.

### Título de captura e abertura visível

A verificação real do Windows encontrou os dois títulos genéricos apesar da chamada DisplayServer. Corrigido para a propriedade persistente `Window.title`; novo teste strict em `window-title-storage-final.json` passou. Duas janelas reais agora mostram **Corrida Presidencial - Tiktok (DEBUG)** e **Corrida Presidencial - Kwai (DEBUG)**. O sufixo é do executável de desenvolvimento Godot e não aparece no HUD. As janelas para configuração foram abertas em produção com coletores desativados, portas efêmeras e estado temporário privado, sem alterar os processos antigos. Isso prova abertura e identidade de captura, não homologa transmissão/eventos reais.
