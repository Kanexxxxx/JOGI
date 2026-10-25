# Conta da LIVE TikTok — 25/10/2026

## Divergência confirmada

O backend e o coletor estavam em `@xinka_`. O registro de login do LIVE Studio de 14h05min14s indicava `username=nostalgiia.br`. O operador confirmou expressamente que a LIVE aberta pertence a `@nostalgiia.br` e forneceu seu link público. Não foram copiados cookies, chaves ou campos privados do registro do Studio.

Enquanto o coletor estava na conta errada, seus contadores de comentários e presentes observados permaneceram em zero. O chat nativo do Studio mostrava comentários 13/22. Isso não é uma falha de interpretação do número dentro do Godot: esses eventos ainda não haviam chegado ao JOGI.

## Ajuste aplicado

- Conta padrão do launcher e rótulo do atalho alterados para `@nostalgiia.br`. O launcher também passa a imprimir a conta por extenso, além da plataforma e porta.
- O diretório de `@xinka_` foi preservado, sem mover seu histórico, votos ou presentes para outra conta.
- Retomada a sessão própria de `@nostalgiia.br`: checkpoint válido da rodada 14/50, ciclo 1. Os bancos dessa conta passaram pela verificação de integridade e tinham zero presentes pendentes.
- Preservado o prazo de cooldown mais conservador entre as sessões. Foi transferido somente o prazo de controle de requisições; equipes, eventos, valores, votos e credenciais não foram mesclados. Trocar a conta não autoriza ignorar um HTTP 429.
- Pausa autenticada do jogo anterior confirmada pelo motor, checkpoint conferido e backup consistente das duas sessões antes de encerrar os processos TikTok. Supervisor suspenso durante a manutenção para impedir respawn concorrente. O jogo anterior fechou normalmente; não houve encerramento permanente da experiência.
- Iniciada uma única instância TikTok com backend, Godot e armazenamento de `@nostalgiia.br`. A janela abriu normalmente no desktop interativo.
- Painel autenticado aberto somente para TikTok. `tools/open_admin_panels.cjs tiktok` agora limita o atalho à plataforma solicitada; o padrão continua abrindo ambas. Nenhuma configuração, cookie, processo ou comando Kwai foi alterado.

Backup privado:

`C:\Users\Kanex\AppData\Local\JOGI\backups\tiktok-interactive-desktop-20261025-142221`

O backup da sessão anterior está em `consistent`; o da conta de destino está em `nostalgiia-before-switch`.

## Captura e validação

A janela anterior do Godot estava minimizada. Sua física, cronômetro e telemetria continuavam avançando, mas a captura apresentada pelo Studio havia congelado. Depois da recuperação, a prévia do Studio voltou a mostrar a rodada 14, avanço das distâncias e atualização do cronômetro; o Studio indicou 60/60 FPS e zero quadros perdidos na inspeção. Nenhuma transmissão foi iniciada ou encerrada pelo agente.

Os 20 testes direcionados do launcher, isolamento e recuperação passaram, e o JavaScript do atalho de painel passou no `node --check`. As regras de comentários, equipes, habilidades e ACK não foram reescritas; os testes isolados da recuperação anterior permanecem distintos da comprovação de eventos reais.

## Limite externo

A primeira tentativa da conta correta foi deixada para o prazo de cooldown preservado: **14h35min03s, Brasília**. Antes desse horário, `rate_limited` representa a espera persistida; não uma nova recusa já observada da conta correta.

O monitor desta manutenção lê somente `/api/state` em localhost. Não faz consultas adicionais ao TikTok, não injeta eventos e não aciona presentes pagos. Eventos emitidos enquanto o coletor está desconectado não têm entrega confirmada ao jogo; não há promessa de recuperar comentários/presentes antigos por esse SDK.

Antes de cada LIVE, o @ conectado no Studio precisa coincidir com o @ mostrado no painel JOGI. O nome de exibição `Kanex` não identifica unicamente qual das contas está conectada.
