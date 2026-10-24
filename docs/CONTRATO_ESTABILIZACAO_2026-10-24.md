# Contrato da estabilização final — 24/10/2026

Base: `master@3e22ce5ffc5b3ac67308b28b032f167806a7eeef`, árvore limpa e remoto confirmado. Entrega técnica até 21h de Brasília. Os processos do operador nas portas 8765 e 8766 permanecem fora do escopo dos testes.

## Contratos entre equipes

- `JOGI_MODE=production|development`, padrão `production`; valor inválido deve falhar com segurança. Simulação exige desenvolvimento explícito, com armazenamento separado da produção.
- Produção recusa eventos `source=simulator`, rotas/ações de simulação e atalhos de prévia. HUD mostra atividade somente recebida; não divulga informações técnicas nem preenche métricas vazias com exemplos.
- Comando administrativo retorna recebimento `queued` com `event_id`; isso não comprova execução. Godot responde pelo canal autenticado com `{type:command_result,event_id,command,status:applied|rejected,message?}`. Backend correlaciona comando e resultado; painel distingue pendente, aplicado, rejeitado e conexão indisponível.
- `end_experience` é terminal, persistente e idempotente. `JOGI_END_AT` usa data absoluta com fuso; padrão `2026-10-26T07:00:00-03:00` (=10h UTC). Reinício após prazo ou encerramento manual não abre nova rodada.
- Presentes aceitos são duráveis antes de confirmação. Após encerramento, permanecem identificados como pendências após o fechamento, sem efeitos fictícios nem descarte silencioso. ACK do jogo só pode ocorrer após gravação durável.
- TikTok e Kwai mantêm contas, cookies, bancos, metas, comandos e rankings independentes. Webhook ativo não equivale a sala real conectada.

## Critérios de aceite

1. Testes de produção recusam simulação; desenvolvimento continua disponível isoladamente.
2. Painel → backend → Godot → resultado correlacionado comprova execução, incluindo falhas e reconexão.
3. Encerramento testado com relógio controlado, reinício e presentes na fronteira.
4. Carga com 1.000 identidades sintéticas; perda de eventos gratuitos, se houver por política de fila, contabilizada; presentes nunca declarados aplicados sem confirmação durável.
5. Capturas nativas do Godot e do painel; inspeção visual além de asserts. Manter modelos, animações e vozes aprovados.
6. Segurança e revisão independente antes do veredito. Homologação real TikTok/Kwai e avaliação jurídica são condições separadas da aprovação dos testes.

Nenhuma transmissão pública, geração paga, encerramento de OBS ou desligamento do computador faz parte dos testes.
