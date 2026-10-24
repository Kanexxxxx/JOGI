# Retomada de qualidade — 23/10/2026

Direção pedida pelo usuário: máxima qualidade, preservar os personagens aprovados, melhorar cenário, fundo, câmeras, efeitos e todos os detalhes; usar API só onde necessário. Escolha explícita: **Brasília estilizada com arena de corrida e identidade brasileira**. Não trocar rostos nem gerar heróis novos.

## Conta e uso confirmado

CLI atualizado pelo usuário; versão local verificada **0.7.3**. `doctor --json`: autenticação/rede válidas, API 1.000 créditos inicial. Studio 580 informado anteriormente é saldo distinto.

Ambos: importação e rig-check gratuitos; rig v3.0/Mixamo25 e `preset:run`10 por personagem. **70 consumidos e saldo API930/frozen0 confirmado** depois das duas provas. Nenhuma outra animação paga nesta atualização.

| Etapa | Lula | Flávio |
|---|---|---|
| Import | `3eb14169-776e-411f-81e2-6a39308d18a0` | `092bc520-52da-4cff-9572-acefe84df80e` |
| Check | `c5d764d2-2227-472c-9e51-5c95f7d3e0cd`, riggable true, biped, 0 | `b796eadf-3090-4252-bfd1-a92778b1d0c3`, riggable true, biped, 0 |
| Rig | `9b4cb475-8d2a-45b8-9783-6b5ae02a9650`, success25 | `4fe9cc22-6e03-4aa5-b74e-7c9497e9dd05`, success25 |
| Run | `750b86a1-86dd-421e-b19a-13ac5799d2b0`, success10 | `e44ca522-0839-4d0d-b6cd-07a59afb7c96`, success10 |

**Nunca reenviar tarefa por silêncio/timeout sem consultar o ID.** Metadados `docs/TRIPO_*` e diretórios `assets/models/{slug}/tripo-original-*`. Nenhuma chave lida/exposta. Dry-run obrigatório antes de cada etapa paga. Comandos de anim rig não oferecem dry-run: usar `make <source-id> --then 'rig:model=rig-v3.0,rig_type=biped,spec=mixamo,out_format=glb' --dry-run --json`, e a mesma cadeia sem dry-run para executar. Retarget cadeia `retarget:animation=preset:run,animate_in_place=true,out_format=glb`.

## Personagens e causa das deformações

A bancada antiga v7 local usava 60k/2K e rig aproximado. Usuário rejeitou sua qualidade. Ela NÃO é a apresentação final.

O APIrig Lula preservou contagem **1.960.784 triângulos**, 65 ossos e os três mapas4K byte-idênticos aos originais (reordenados). Positions/UV raw bytes entre export original e API não são idênticos; não afirmar GLB inteiro inalterado. Inspeção: `tools/inspect_tripo_character.py`, `docs/evidencias/personagens/tripo-lula-inspection.json` e seis renders.

API run deformou capa porque ela pertence à mesma malha do corpo e recebeu pesos dos membros. Corrigir localmente foi necessário. Melhor derivado: **assets/models/lula/tripo-cape-fixed-v13/model.glb**, SHA256 `ade9662e93870a06e35c83bfc7bfc7237b74780ca6a780679163d758a04989a9`. Script `tools/fix_tripo_cape.py` altera diretamente JOINTS/WEIGHTS selecionados, sem reexportar/remodelar face; JSON prova bytes restantes literalmente preservados. Capa pinada ao `mixamorig:Spine2` com transição no colar; máscara posterior/cor+exclusão anatômica evita selecionar faixas/calças. Versões1–12 são experimentos rejeitados, não promover.

O run da API também tinha deslocamento horizontal constante em Hips: X=-.017617/Z=-2.221747 GLTF, repouso X=.005859/Z=.044922. Isso colocava Lula ~5m para trás ao escalar, fazendo-o parecer menor. V13 já normaliza Hips X/Z; não aplicar uma compensação antiga fixa novamente. O showcase calcula diferença pose/repouso dinamicamente, portanto resulta zero quando o arquivo está corrigido.

V13 vista no Blender e Godot: capa/estrela e rosto legíveis, sem rasgos grandes. Pequena fronteira de pesos escondida no ombro ainda merece revisão no ciclo inteiro e em clipes futuros. Fonte original e APIrun permanecem intactos.

## Arena e tela nova

- `tools/build_brasilia_arena.py`: gerador Blender, fonte `.blend` e GLB em `assets/environments/brasilia/arena-v1/`, cópia `game/assets/environments/brasilia/arena_v1.glb`.
- Arena46.880tri,13materiais,294meshes/possíveis surfaces, sem texturas externas. Congresso/catedral reinterpretados, arcos, piscinas, ipês e arquibancadas. Sem gastoAPI. GLB exclui chão/pista/luzes das beauty renders.
- `game/scripts/broadcast_hud.gd`: novo HUD PTBR, Lula vermelho, Flávio amarelo/verde, fonte Barlow Condensed/OFL em assets/fonts. Região essencial x48–900, y258–1328; topo/chat/borda direita reservados.
- `game/scripts/brasilia_showcase.gd` + `game/scenes/characters/brasilia_showcase.tscn`: composição real Godot, luz, céu, estrada e câmera frontal. É **PRÉVIA VISUAL**, não jogo conectado; dados do placar ficam iniciais. Para câmera frontal, Lula world+X ocupa esquerda da imagem.
- Atual usa LulaAPIv13 e Flávio original ainda Tpose; trocar Flávio só depois de prova aprovada. Não mostrar Tpose como final.
- Capturas internas `docs/evidencias/brasilia/arena-lula-capa-v13{,-verso}.png`. As anteriores rascunhosv1..3 têm defeitos/FlávioTpose. Últimas alterações de luz/fog e posição estão no código. F1 frente, F2 costas, F3 perfil.
- `--capture=<novo_png>` só permite arquivo novo em docs/evidencias/brasilia. Passar `-- --asset-preview` para impedir autoconexão no barramento, antes do autoload conectar.

## Regras já implementadas, separadas da apresentação

`game/resources/rounds_brasilia.json`: 50 nomes únicos, cinco atos, dez presets cada,600s. `race_main.gd`: ciclo1..50 automático, reinício do ciclo após pódio50, placar por ciclo, finalização idempotente, pausa, restart manual com rollback da tentativa. Elenco Flávio corrigido; telemetria tem round/cycle/nome/placar. Empate<=.01m com epsilon absoluto1e-9m.

`test_round_cycle.gd`, validações e quatro regressões strict passaram; evidências `docs/evidencias/round-cycle-*.json`. Revisor independente encontrou fronteira float100/100.01; corrigida e testada ambas ordens +100/100.01001 vence. **Revisão final independente aprovada**, sem achados restantes nesse escopo. Não é ensaio de32horas.

**A corrida principal ainda usa apresentação antiga.** Próximo passo de integração: apresentação HeroRunner + animações e arena/HUD novos no motor real, mantendo física/regras. Não substituir pelo showcase com métricas fixas. Medir duas instâncias+capturas antes de afirmar60FPS/32h. Backend e conectores reais permanecem pendentes conforme BRIEFING_RETOMADA.md; pergunta enviada sobre @TikTok/@Kwai, acessoKwaiPC/presentes e integrador, aguardando usuário.

## Agentes em trabalho neste checkpoint

- `asset_review`: rig/run Flávio35 concluídos e preservação inspecionada; corrige capa/origem local e renderiza. Nenhum outro gasto autorizado nessa delegação.
- `round_cycle`: regras concluídas/aprovadas; agora implementa somente CandidatePresentation e HeroRunner novos para conectar modelos reais à física existente, sem modificar mais RaceMain.
- `brasilia_environment`: criou arena e revisou ciclo independentemente; aguardada revisão boundary final.
- `live_readiness`: criou somente JSON das50rodadas, concluído.

Manter atualizações de progresso ao usuário. Nenhuma compra adicional, troca de motor, instalação ou upload de segredos é necessária. A preferência é qualidade comprovada por capturas reais, não afirmar perfeição nem tratar a bancada como jogo pronto.
