# Revisão visual: capas, Planalto e distância

Atualização local de 24/10/2026. Nenhuma geração paga ou crédito consumido nesta revisão. Os modelos originais, rostos, mapas PBR, rig e animações importadas continuam preservados.

## Capas

`CandidateCapeMotion` conserva a máscara exclusiva da capa nos GLBs derivados existentes. A gola/ombros com máscara zero continuam presos. O shader combina uma onda longitudinal, outra transversal e levantamento da barra; os diferentes trechos do pano deixam de transladar como uma placa rígida. Amplitude de corrida estabiliza em 0,15 unidade do modelo e aumenta até 0,245 no turbo, com transição suave por velocidade. A frequência também acompanha a corrida. No tropeço o vento diminui e na pausa fase/amplitude congelam. É deformação visual procedural, não uma simulação física de tecido com colisão.

`capture_cape_motion.gd` fixa exatamente o mesmo esqueleto/câmera, altera só a fase do pano e repete a imagem pausada. Capturas `capas-ondas-v2-mesma-pose-{0,1,2}.png`: 85.637 pixels variam na região da capa; a pausa produz zero pixel de diferença. O limite superior da região alterada começa em y=437 numa imagem 1024×1024; a cabeça permanece igual.

## Planalto

Nova versão aditiva `game/assets/environments/planalto/planalto_v2.glb`, gerada por Blender local com `tools/build_planalto_palace.py -- --version v2`. A v1 continua preservada. Há 43.584 triângulos, 12 superfícies/materiais e 2.609.996 bytes. SHA256 `8449efb8e0edd045b91c85d9f22ac702c57707c5e3325d63ed40b54558a0053b`.

Foi corrigido um defeito real: a face superior da rampa tinha winding para baixo e podia desaparecer por culling. As normais dos volumes fechados agora são recalculadas para fora antes da exportação. O patamar também ganhou continuidade até a fachada, fechando um vão de aproximadamente 0,91 m. A escadaria oposta à rampa foi adicionada como elemento cenográfico solicitado para a arena. Não é apresentada como reprodução medida de uma segunda rampa do edifício real. O texto discreto `2027` aparece acima da cobertura, separado da geometria patrimonial.

Referências oficiais consultadas: [Casa Civil — fotografias do Planalto](https://www.gov.br/casacivil/pt-br/assuntos/centrais-de-conteudo/imagens/destaques-area-de-imprensa/fotos-do-palacio-do-planalto), [Fundação Oscar Niemeyer — Palácio do Planalto](https://www.oscarniemeyer.org.br/obra/pro081/). O cenário é uma reconstrução estilizada, não levantamento arquitetônico.

## Torcida e metros na pista

Pessoas da torcida maiores: largura/profundidade de 0,88 para 0,98 e altura multiplicada por 1,16. Os braços giram em torno do ombro sem encurtar a malha. Fases/velocidades individuais reduzem o sincronismo coletivo e a repetição aleatória por bloco foi removida. O número de instâncias e os draw calls do MultiMesh continuam iguais.

Contrato novo: `StadiumWorld.set_race_progress(meters: float)` recebe a média dos metros reais dos dois corredores, antes da compressão visual. Seis nós fixos são reciclados em intervalos de 50 m, projetados a 0,18 unidade de cenário por metro real. As marcações alternam as bordas da pista e desaparecem quando passam ou ficam perto demais da câmera. Fonte Nunito igual ao HUD, largura máxima de texto limitada a 1,8 m. Não há criação contínua de nós por quilometragem. A pista azul-cobalto permanece.

## Validação

- GDA project scan: nenhum erro de engine.
- GDA `script validate`: `stadium_world.gd` e `candidate_cape_motion.gd` válidos.
- GDA `scene validate` da cena StadiumRace: válido.
- GDA `scene preflight`: `started=true`, `status=ready`, diagnóstico vazio.
- GDA strict `test_stadium_art_revision.gd`: passou sem stderr; inclui 10.000 atualizações de distância, identidade dos seis nós, conversão metros/projeção, reset, rejeição de NaN, vento de corrida/turbo/impacto/pausa.
- GDA strict `test_cape_motion.gd`: passou com os dois personagens, máscaras de ombro/barra, materiais originais, pausa e reset.
- Captura GPU `arte-revisada-capascenario-v2.png`: viewport real 1080×1920, 361 amostras após aquecimento, média 59,999 FPS e p95 16,667 ms. É medição curta de uma instância, sem promessa de teste completo de 42 horas nem de duas instâncias com OBS.

Capturas e comparação numérica ficam em `docs/evidencias/estadio/`. A integração da chamada `set_race_progress` no controlador da corrida e os ensaios finais de duas instâncias pertencem à validação integrada do projeto.
