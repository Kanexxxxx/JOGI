# Revisão independente do backend e watchdog — 24/10/2026

Revisor não participou da implementação. Escopo somente leitura de implementação; este relatório é a única escrita deliberada. Nenhuma live externa, autenticação, geração paga ou transmissão foi iniciada.

## Resultado

Sem bloqueador novo identificado no catálogo de presentes e na supervisão por processo. Isso não valida a coleta real das plataformas, o integrador Kwai, a captura/áudio no OBS ou 32 horas contínuas de operação.

- Suíte completa: `services/live_bridge/.venv/Scripts/python.exe -m pytest services/live_bridge -q -p no:cacheprovider` — **69 passed, 27 subtests passed**, 46,43 s. Dois avisos de depreciação de dependências TikTokLive/websockets.
- Primeiro run: 68 passed e uma falha no encerramento de `TemporaryDirectory`, WinError 145, em `test_follow_goal_balance.py:83`. Asserções funcionais não falharam. O mesmo caso isolado passou; o segundo run completo passou. A pasta temporária estava vazia na inspeção posterior. Causa não comprovada; não foi alterado código para ocultar a falha.
- `tools/run_live_instances.py --both --check --offline`: valid=true; processes_started=false; portas 8765/8766, pastas e variáveis separadas.
- Teste adicional com processos falsos: porta TikTok ocupada preservada, somente bridge e jogo Kwai criados, encerramento somente dos filhos criados pelo launcher.
- Testes do watchdog cobrem reinício isolado, seis reinícios em dez minutos, backoff até 30 s, dependência e restauração da solicitação de suspensão do Windows.
- Catálogo: IDs por fonte, persistência, override somente para novos envelopes, pendências antigas preservadas e total real não recalculado por tier. Unitário 42 × delta 3 = 126 moedas uma única vez.
- Segurança: bind loopback; Host/Origin externos recusados; fonte diferente da plataforma recusada; sanitização de nomes; SQL parametrizado; painel usa textContent. Busca de padrões de credenciais em fontes Python/JS/JSON/Markdown/HTML de tools e services/live_bridge não encontrou chave embutida. Arquivos locais de credenciais não foram impressos.
- `git diff --check`: exit 0; avisos de normalização CRLF, sem erro de whitespace.

## Rechecagem focal após correções

As duas observações anteriores foram corrigidas e rechecadas independentemente:

1. `services/live_bridge/RELIABILITY_CONTRACT.md` agora descreve supervisão independente, backoff de 1 a 30 s, limite de seis reinícios em dez minutos e preservação do status do supervisor existente.
2. `tools/run_live_instances.py:54-58` só adiciona a pasta da plataforma a `state_dirs` quando não encontrou servidor existente. Assim, `LiveSupervisor.publish()` não grava no arquivo de status do proprietário da porta recusada, inclusive no encerramento.
3. Novo teste `test_rejected_second_launcher_preserves_owner_status` protege esse comportamento com conteúdo sentinela, dois filhos falsos somente da plataforma livre e encerramento dos filhos próprios. Execução independente focal: `pytest services/live_bridge/test_live_supervisor.py -q -p no:cacheprovider` — **5 passed em 0,05 s**.

A equipe principal informou ainda uma execução ampliada backend + TTS + SFX de **86 testes e 27 subtestes aprovados em 47,21 s**. Esse resultado ampliado não foi repetido pelo revisor nesta rechecagem focal. A execução completa do backend realizada diretamente por este revisor continua documentada acima.

Sem pendência bloqueadora nova encontrada nessa alteração. Limites de coleta real, OBS e ensaio de 32 horas continuam explicitamente fora do resultado.

Não foi instalado/reativado ECC nem executado hook de aprendizado.
