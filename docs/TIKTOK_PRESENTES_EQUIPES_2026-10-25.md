# TikTok: vitrine, equipes e entrega de presentes — 25/10/2026

## Aplicado na conta @xinka_

Painel8765 e Godot reconectados; revisão gifts-teams-20261025-v1 carregada. Checkpoint recuperado, persistência pronta,60FPS, zero presentes pendentes. A rodada19 terminou e a20 avançou normalmente. Nenhuma intervenção no Kwai, OBS ou cena pública. Os reinícios TikTok foram autorizados pelo operador e ocorreram com backups íntegros, credenciais iguais e filas vazias.

## Vitrine confirmada por imagens do operador

| Habilidade | Presente | Moedas/unidade | Confirmação |
|---|---|---:|---|
| Impulso | Rosa |1|captura da conta,00:35/00:36|
| Escudo | Mini dino |10|mesma captura|
| Ataque | Trompete de Festa |149|captura da conta|
| Super Turbo | Calêndula |1000|captura da conta|

Donut, Coração de Mão e Galáxia não foram confirmados nas imagens recebidas; foram substituídos por opções visíveis das faixas correspondentes. Assets são regiões AtlasTexture de JPEG originais fornecidos, sem imagens oficiais geradas ou alteradas. Origem e hashes em game/assets/gifts/tiktok/PROVENANCE.json; catálogo persistente em game/assets/catalogs/tiktok_gift_showcase.json. Os quatro ícones aparecem desde a abertura. Painel /api/gifts também mostra a vitrine, separada de presentes efetivamente recebidos.

As capturas não expõem gift_id. Esses campos permanecem null até serem recebidos do SDK, sem IDs inventados. O catálogo observado SQLite registra os IDs reais quando chegam. A mecânica automática permanece por valor unitário verdadeiro:1–9/T1;10–99/T2;100–999/T3;1000+/T4. Overrides de ação por ID não alteram preço, quantidade ou faixa financeira original. Os quatro presentes exibidos são exemplos confirmados dessas faixas, compartilhados entre as equipes.

## Equipe do remetente

IDs estáveis id/user_id/sec_uid identificam a pessoa. Nome e handle não atribuem equipe. Histórico local SQLite por conta preserva escolha e ordem temporal por até48h; mudança afeta apenas eventos futuros. A equipe é fixada no envelope do presente, não recalculada durante filas/replay. Eventos atrasados consultam a escolha válida no timestamp disponível. Se timestamps de segundos não permitem ordenar uma troca no mesmo segundo, a contribuição fica neutra em vez de beneficiar o lado errado. Sem timestamp, usa-se a ordem de recebimento. Uma escolha com ID numérico do checkpoint existente foi recuperada sem fabricar voto.

Sem equipe ou ID confiável: presente/quantidade/valor/ACK permanecem contabilizados, sem benefício retroativo nem escolha aleatória. A instrução COMENTE13OU22ANTESDEENVIARPRESENTES está no HUD. Valor desconhecido não produz efeito pago inventado.

## Efeitos e apresentação

T1 acelera o apoiado; T2 protege o apoiado; T3 ataca obrigatoriamente o adversário, rejeitando destino conflitante; T4 acelera e destaca o apoiado. Os limites existentes foram preservados. No TikTok, a notificação de presente recebe confirmação interna depois da execução; pode indicar aplicado, reservado para próxima rodada, neutro, valor desconhecido ou não confirmado/bloqueado. Somente aplicado destaca o card inferior. Presentes reservados mantêm a política existente; presente neutro não é convertido depois.

Combos mantêm deltas, inclusive após reconexão. Uma fila SQLite local adicional conserva envelopes pagos até aceitação do backend. Falha de callback não descarta silenciosamente o presente; recuperação usa o mesmo ID. O ACK final continua vindo do Godot/outbox duráveis. O estado de cooldown HTTP429 também é preservado através de reinício para não gerar consultas extras ao TikTok.

## Testes e evidências

- Backend:133 testes e48 subtestes aprovados;18 regressões finais de equipes, listener e catálogo também aprovadas. Dois avisos de depreciação do SDK.
- Godot:35 scripts exercitados;34 passaram na suíte inicial final. O restante apontou1px de margem em label de fallback; corrigido e aprovado em reteste estrito (tiktok-gifts-safezone-retest.json). Nenhuma falha pendente dessa suíte.
- Mecânicas: T1/T2/T3/T4 em ambas as equipes, ataque com destino conflitante, duplicado, presente neutro e valor desconhecido aprovados.
- Teste ponta a ponta isolado: dois votos SDK+replay, equipes distintas,3 presentes com destinos1/2/0,3 ACKs e nenhuma reaplicação. Relatório tiktok-gifts-sdk-e2e.json. Não envolveu LIVE, compra ou presente real.
- Nove capturas GPU da cena real em evidencias/estadio/gifts-teams-20261025: abertura e cada tier para ambas as equipes. Elas são fixtures explicitamente em TESTE LOCAL, nunca produção. Janela real TikTok também foi observada com os quatro presentes e valores após atualização.
- Medição final: rodada20 com cronômetro485,25→445,15s, telemetria recente e corrida avançando. Ver tiktok-gifts-motion.json.

Backups privados em LOCALAPPDATA/JOGI/backups/tiktok-gifts-teams-20261025-011259; não enviados ao GitHub. A correção anterior do relógio está no commit32a12ef.

## Estado externo e operação

O estado real consultado após atualização é waiting_room, sem feed conectado: a sala de teste não estava ativa. Houve comentários reais comprovados anteriormente pelo operador; nesta entrega não foram comprados/enviados presentes reais nem produzidos comentários fictícios em produção. Homologação de um novo presente de espectador real depende de LIVE legitimamente disponível e autorizada; os testes internos não substituem essa etapa. Não declarar autorização pública/eleitoral a partir da prontidão técnica.

Atualizar o painel comF5 carrega a vitrine administrativa nova. Os cards são indicadores de presentes, não botões para espectadores. Alterações experimentais antigas de diagnóstico Kwai ficaram fora desta publicação e não foram carregadas nos processos Kwai.
