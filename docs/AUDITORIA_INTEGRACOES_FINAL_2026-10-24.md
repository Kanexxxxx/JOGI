# Auditoria final das integrações — 24/10/2026, 23h26 BRT

## Resultado efetivamente observado

As duas corridas estão simultaneamente ativas, independentes e com telemetria recente. Nenhum evento sintético foi enviado às sessões de produção. Nenhuma transmissão pública foi iniciada.

| Sistema | Evidência local | Conexão externa |
|---|---|---|
| TikTok @xinka_ | backend 8765, Godot conectado, telemetria fresca, zero presentes pendentes | alterna room_unavailable e rate_limited; NÃO conectado a uma sala |
| Kwai @mentalista.. | backend 8766, Godot conectado, webhook autenticado 8786, um coletor | waiting_room, sem sala detectada; NÃO comprova eventos reais |

## Medição de movimento sem intervenção

13 amostras a cada 15 segundos, durante três minutos. Valores internos do Godot transmitidos ao backend e utilizados pelo painel. Não houve reinício de rodada nem alteração administrativa.

| Corrida | Janela em RACING | Lula, metros | Flávio, metros | Cronômetro restante | FPS reportado |
|---|---|---|---|---|---|
| TikTok, rodada 11 | 165 s (primeira amostra estava em COUNTDOWN) | 163,90 → 2.146,32 | 163,77 → 2.146,08 | 586,35 → 421,15 s | 60 |
| Kwai, rodada 12 | 180 s | 4.681,88 → 6.844,89 | 4.681,72 → 6.844,80 | 209,87 → 29,62 s | 60 |

Velocidades instantâneas inicial/final: TikTok Lula 12,53/11,27 m/s, Flávio 12,47/12,52 m/s; Kwai Lula 12,08/13,00 m/s, Flávio 11,66/12,86 m/s. Telemetria fresca em todas as amostras; zero orphan nodes na inspeção final. Evidência: `evidencias/producao/movimento-integracoes-20261024.json`. O pequeno desvio de tempo decorre dos instantes de amostragem/telemetria; não representa cronômetros compartilhados. A observação desta etapa foi pela telemetria, sem uma nova avaliação visual quadro a quadro.

## TikTok: causa e limites

SDK TikTokLive 7.0.1. O endpoint de descoberta retornou HTTP 429: isso é limitação externa, não prova de perfil inexistente. UserNotFoundError também é ambíguo nesse SDK. A correção 2505901 já está carregada: ID xinka_ sem @ duplicado, classificação room_unavailable, interrupção do fallback HTTP após bloqueio, fechamento do cliente e backoff. Logs locais mostram 22h19, 22h34 e 22h54 com aproximadamente 900 s após 429; tentativas inconclusivas aguardam 300 s. Não foram feitas consultas manuais adicionais à plataforma nesta auditoria. Existe somente uma instância responsável por essa conta. A recuperação está preparada, mas estabelecer uma sala real ainda depende da plataforma e de LIVE legitimamente disponível/autorizada.

## Kwai: defeitos corrigidos e aplicação real

Uma página Chromium fechada ainda era considerada utilizável. Além disso, page.evaluate podia permanecer pendente e impedir heartbeat e liberação do perfil. Corrigidos: validade da página/contexto, invalidação ao fechar, prazo de 5 s para leitura, liberação coordenada independente da leitura, prazo para fechamento e classificação de falha de rede/HTTP como error em vez de waiting_room. A confirmação de liberação só ocorre após fechamento aceito; nenhum SingletonLock foi removido.

Processos foram identificados novamente. O Chromium dedicado filho do coletor 20688 foi fechado normalmente via Restart Manager, sem force. Perfil/cookies completos: backup de 585 arquivos com hashes e verificação SQLite; fila íntegra com zero pendências. Somente o coletor foi substituído sob supervisor 54424. Em seguida, a nova coordenação liberou o perfil normalmente e validou outro backup de 583 arquivos; coletor intermediário 28616; versão final 41480 após novo backup verificado de 594 arquivos. Backends 35692/34944 e Godot 41868/53616 preservados nesta manutenção. PIDs são evidência datada, não parâmetros fixos para operações futuras.

Após aplicação: heartbeat recente (3,46 s na amostra), waiting_room e webhook ativo. O login manual já realizado foi preservado; não houve nova solicitação de login detectada. Isso não certifica indefinidamente a validade dos cookies nem a decodificação de eventos de uma sala real. A descoberta a partir do perfil e o eventual URL legítimo de sala precisam ser homologados quando disponíveis; configured=false indica ausência de URL de sala explícito, não ausência do receptor.

## Testes isolados

- Python: 121 testes e 48 subtestes aprovados; duas advertências de depreciação do SDK.
- Godot: 32 testes aprovados.
- Node: 16 testes aprovados, incluindo ACK durável, repetição, retenção após falha HTTP e preservação de cookies/fila.
- Chromium real em perfil temporário e servidor loopback: dois ciclos de login/liberação, mesmo PID do coletor, cookie preservado, recuperação de renderer deliberadamente travado, recuperação após encerramento do Chromium de teste e HTTP 503 distinguido de sala offline. PASS. Nenhuma requisição externa nesse teste.
- Painel/backend + duas instâncias Godot headless isoladas: FUNCTIONAL_PASS. Comentários, metas, controles, áudio, efeitos e ciclo/encerramento testados em desenvolvimento. A revisão visual do último relatório permanece separada.
- Carga: 1.000 identidades e 300 presentes únicos por plataforma; duplicados e recuperação durável verificados, zero presentes pendentes ao final. Consumidores sintéticos, não salas nem Godot de produção. Evidência: `evidencias/load/load-20261025T021353Z.json`.

Nenhum desses testes comprova comentários, curtidas, seguidores, compartilhamentos, combos ou presentes REAIS de TikTok/Kwai. Ainda é necessário validar os formatos efetivos, identificação da sala, valores de presentes e ACK ponta a ponta com LIVE autorizada.

## Limites operacionais e estreia

Captura e áudio foram anteriormente conferidos por gravações locais; OBS e Studio não foram reconfigurados. Não há certificação de 42 horas. O supervisor reinicia processos que terminam, mas um jogo congelado com processo vivo exige intervenção; a telemetria obsoleta é detectada. Não existe encerramento automático das transmissões externas homologado: o fim persistente do jogo não encerra OBS/Studio. Conclusão técnica não significa permissão jurídica ou autorização para transmitir. Consultar `CONFORMIDADE_ELEITORAL_2026-10-24.md` antes de qualquer estreia.

O defeito de Pausar foi excluído do escopo por instrução expressa do operador. Segredos, cookies, bancos e backups permanecem fora do Git.

Revisão independente estática: os pontos de concorrência, cooldown e recuperação foram revisados e corrigidos; sem outro defeito bloqueante identificado no diff. O teste com renderer travado falhou antes do tratamento do timeout de navegação; a execução final após essa correção passou. Erros intermediários não foram usados como evidência de aprovação.
