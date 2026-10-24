# Auditoria do retorno — 24/10/2026

Recebido: `master@5f1cad12001be14f123b3095843a6d610f79cb95`. Árvore inicialmente limpa, `git fetch origin` concluído, HEAD e origin/master iguais. A comparação usa `e22a3fa` (checkpoint deixado antes da substituição) e os commits seguintes, sem atribuir à IA substituta os recursos já presentes nesse baseline.

## Parecer inicial, antes de grandes alterações

Manter o redesign: fontes Nunito, três metas simultâneas, ranking rotulado por moedas, painel compacto, cache de avatares com fallback e identificação 2027 melhoram a hierarquia. A captura real `docs/evidencias/estadio/retorno-baseline-1700.png` executou em1080×1920 por8s, média60,002FPS/p9516,667ms. O PNGconceitual foi lido sem alteração e tem2.370.882bytes; não é evidência de funcionalidade.

Problemas reproduzidos:

- **P1:** produtor/validador usam `payload.live_goals`, mas StadiumRace lia `payload.goals`. O teste também usava o nome errado e falhava emduasasserções. O comando real podia ser aceito sem aplicar as três metas. Corrigir consumidor e fixture ao contrato canônico; não afrouxar validação.
- **P1:** validação do WebSocket por prefixo aceita credenciais embutidas que desviam o host (exemplo reservado `evil.example`). Com headers de token, isso cria risco de envio externo caso a configuração local seja malformada. Restringir host, porta e caminho antes de conectar; nenhuma requisição externa de exploração foi feita.
- **P1:** coletor Kwai memoriza ID antes do ACK durável, podendo descartar presente após401/503/timeout. Correção em execução separada, com regressão da função real.
- **P2:** cookie administrativo compartilhado entre portas pode desautorizar o painel TikTok após login no Kwai. Correção em execução separada.
- **P2:** restauração de checkpoint legado preservava `live_goal` mas deixava `live_goals` nos valores padrão. Migração deve copiar a meta anterior ao slot correspondente.
- **P2:** cards de presente mesclam equipes diferentes quando o usuário troca13→22 dentro do TTL; expiração só no final da lista deixa cards antigos visíveis. Revisão/correção em execução separada.
- **P2 visual:** máscara circular usa UV da imagem inteira ao recortar AtlasTexture; isso produz uma faixa sobre o retrato. O ano2027 está parcialmente oculto pelo teto. Corrigir coordenadas da máscara e altura, preservando imagens/modelos.
- **Dívida herdada:** teste de apresentação ainda exige teto2,5× e impacto antigo, embora o baseline já tivesse teto3× e queda1,2s. Verificar contratos visuais e atualizar regressões de acordo, sem atribuir isso ao redesign.

## Verificações de origem

`test_stadium_integration.gd --strict` reproduziu duas falhas, sem erro de sintaxe. Revisão backend independente reproduziu110testes+48subtestes aprovados,2avisosdepreciação. Testes Godot focados de HUD/arte/persistência/ciclo passam, mas não substituem o fluxo do comando real nem teste de42h.

Os processos que já estavam ativos foram inventariados e preservados. Não houve broadcast público nem consumo de créditos nesta retomada. Commits de correções terão resultados posteriores registrados em `docs/AGENT_HANDOFF.md`.
