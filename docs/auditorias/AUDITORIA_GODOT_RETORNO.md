# Auditoria Godot da retomada — 24/10/2026

Baseline auditado: `5f1cad12001be14f123b3095843a6d610f79cb95`, comparado a `e22a3fa`. A revisão começou sem alteração da implementação. Após os achados, a coordenação autorizou este agente a corrigir somente HUD, legibilidade do ano e seus testes. Correções de barramento, metas e persistência pertencem à coordenação e precisam de sua própria rechecagem.

## O que merece ser mantido

- HUD usa as fontes Nunito existentes e preserva as identidades 13/22; as posições mudam sem trocar rosto, cor ou raia. As três metas têm componentes separados e a meta de seguidores distingue novos follows da sessão de baseline manual.
- Top 5 é explicitamente em moedas, com Top 3 no pódio e estado vazio compacto. Não foi identificada mudança no cálculo financeiro ao adicionar fotos.
- AvatarVisualCache usa somente rota opaca local, limite de 512 KiB, dimensões máximas antes do decode, 96 px finais, LRU de 64 texturas, fila de 32 e duas tentativas. GiftVisualCache também mantém limites e origem local.
- AudienceDirector não persiste as fotos no checkpoint; o vínculo transitório possui teto de 256 identidades. Os cards recebem equipe neutra quando a pessoa ainda não escolheu candidato.
- Os scripts de personagens, modelos aprovados, corrida e capas não foram substituídos pelo redesign. Não se justifica regenerar personagens ou áudio para resolver os defeitos encontrados.
- As funções de metas, fotos e legendas foram estendidas sem eliminar os métodos legados. Contudo, compatibilidade de assinatura não garante compatibilidade de resultado: foram encontrados os problemas abaixo.

## Achados reproduzidos no baseline

| Prioridade | Achado | Evidência e consequência | Responsável pela correção |
|---|---|---|---|
| P1 | Contrato inconsistente de metas triplas | LiveEventBus valida `payload.live_goals`; StadiumRace lia `payload.goals`. Assim, o formato canônico era aceito mas não aplicado, e o alternativo usado pelo teste era rejeitado. Não é uma justificativa para afrouxar os testes. | Coordenação |
| P1 | URL do WebSocket validada somente por prefixo | `is_loopback_ws_url("ws://127.0.0.1:8765@evil.example/ws/godot")` retornou `true`, agora que o handshake também inclui token. O probe apenas chamou a função; não houve conexão externa ou exfiltração. Usar validação integral de host, porta e path. | Coordenação |
| P2 | Checkpoint legado perde a configuração no novo HUD | Probe com checkpoint válido sem `live_goals` e `live_goal` de curtidas com alvo 4.321 restaurou `live_goal=4321`, mas deixou `live_goals.likes=1000`. O novo HUD lê o segundo estado. | Coordenação |
| P2 | Combo visual mistura equipes | Mesmo doador e gift_id em sequência 13 → 22 gerou um único card com `team=1`, quantidade 2. A carta contradizia o evento recente destinado ao 22, embora a contabilidade permanecesse correta. | Corrigido neste pacote |
| P2 | Renovar combo mantém outro card vencido | Gift A em t=0, follow B em t=1, renovação A em t=4. Em t=7, B continuava na lista com `expires=4.4`, pois o algoritmo só examinava o último card, A, renovado até 7.4. | Corrigido neste pacote |
| P2 | Máscara circular em UV de atlas | A região recortada do rosto estava correta; a máscara usava o UV da PNG inteira. Isso produzia faixas coloridas na testa, visíveis na captura do baseline. | Corrigido neste pacote |
| P2 | Ano cortado pelo teto e depois pela própria placa | No baseline, a parte inferior de 2027 era ocultada pelo teto. Ao ampliar o texto, o billboard inclinado intersectava o fundo da placa e cortava o topo dos glifos. Corrigidos altura e afastamento em profundidade, sem desabilitar depth test. | Corrigido neste pacote |
| P3 | Teste de apresentação herdado não acompanha contrato atual | `test_hero_presentation` exige teto 2,5, mas o código usa 3,0. Depois da primeira falha, o teste ainda contém expectativas da reação antiga de 0,12 rad/0,4 s, em vez da queda atual. CandidatePresentation não mudou entre `e22a3fa` e este HEAD: é uma pendência herdada, não uma regressão introduzida pela IA substituta. | Coordenação |

Os probes isolados ficaram em `.tools/audit-godot-return/`, fora da implementação e ignorados pelo Git. Os resultados relevantes estão registrados acima sem dados de contas reais.

## Alterações feitas após autorização da coordenação

- `stadium_hud.gd`: a agregação de combos agora exige mesma identidade, presente **e equipe**. Deltas da mesma equipe continuam combinados. A expiração examina todos os dois slots, independentemente da ordem de renovação.
- A máscara circular normaliza a região UV dos dois AtlasTextures de rosto antes de calcular a borda. As PNGs originais não foram alteradas.
- O painel 2027 foi ampliado moderadamente para se aproximar da referência, elevado acima da cobertura real e recebeu afastamento suficiente para não atravessar o billboard dos textos. Nenhuma geometria do palácio foi regenerada.
- A faixa temporária de eventos passou de y=612 para y=1288..1344, deixando o ano e a arquitetura visíveis. Na captura de corrida, ela ocupa a área abaixo dos pés e antes dos blocos sociais. A coordenação deve conferir também chegada e outros enquadramentos.
- Nova suíte `test_hud_interaction_regressions.gd`; o teste de arte também verifica o fundo acima do teto real e o afastamento do texto em relação ao fundo.

## Testes reproduzidos

No baseline, nove de dez suítes focadas passaram em modo strict com stderr/diagnósticos vazios:

`test_hud_redesign_goals_avatars`, `test_rounded_hud`, `test_stadium_art_revision`, `test_paid_round_boundary`, `test_race_persistence`, `test_round_finish_presentation`, `test_round_cycle`, `test_audience_director` e `test_gift_visual_cache`.

`test_hero_presentation` falhou com `FAIL: Turbo deve respeitar teto de animação`.

Após as correções deste pacote:

- `test_hud_interaction_regressions`, `test_stadium_art_revision` e `test_hud_redesign_goals_avatars`: exit 0, stderr vazio, diagnósticos vazios.
- `stadium_hud.gd`: validação `valid:true`.
- Cena principal: `valid:true`; preflight `started:true`, `status:ready`, sem diagnósticos.
- `git diff --check` nos arquivos alterados: sem erros; apenas avisos de normalização CRLF.

## Comparação visual e limites

Foram vistos o PNG conceitual oficial, `retorno-baseline-1700.png` e as capturas GPU de correção. A referência é direção de estilo, não screenshot funcional: seus totais de seguidores e presentes não devem ser copiados como dados reais.

Captura recomendada após as correções: `docs/evidencias/estadio/auditoria-hud-planalto-v3.png`. Render real Vulkan/RTX 4060 em 1080×1920, ensaio de 7 s, 301 amostras após aquecimento, média 60 FPS e p95 16,67 ms. Nela, os retratos são circulares, 2027 aparece inteiro e o alerta não cobre o ano.

`auditoria-hud-planalto-v1.png` documenta o primeiro reparo; `v2` é evidência intermediária com o topo do texto cortado e **não deve ser usada como captura final**.

Ainda não comprovado por esta auditoria: avatar/foto real entregue por sala de live autenticada, miniatura de presente real nessa sala, sobreposições nativas de TikTok/Kwai, legibilidade em cada tamanho móvel solicitado, gravação OBS, duas instâncias por dez minutos ou operação real de 42 horas. Os testes do HUD usam texturas locais geradas como fixtures e exercitam limites e estados; não comprovam uma coleta real da plataforma.

Observação adicional: o HUD preserva vários tipos comuns de graphemes, mas os sanitizadores anteriores do barramento/AudienceDirector removem ZWJ e limitam nomes por codepoints. O teste que injeta emojis diretamente no HUD não comprova preservação de nomes compostos de ponta a ponta. Isso é uma limitação de cobertura, não execução de texto ou exposição de credenciais.

Não houve chamada de geração paga, transmissão pública, alteração de credenciais ou mudança em processos alheios nesta auditoria. Commits e publicação ficam sob controle da coordenação.
