# Registro histórico — primeira versão lateral, 24/10/2026

**Superado**: a direção vigente é a câmera atrás dos dois corredores, seguindo a referência posterior do usuário. Leia [ESTADO_ATUAL.md](ESTADO_ATUAL.md). A tarefa de arquibancada citada abaixo já terminou; não reenviar geração.

O usuário REJEITOU a composição frontal de Brasília: cenário lavado/básico, fontes e layout sem impacto. Mostrou três referências de corrida lateral de live e pediu pesquisa, cores fortes, ambientes estruturados/dinâmicos, movimento claro, separação perfeita dos dois, uso dos créditos e entrega até24/10 às09h. A direção anterior permanece como experimento, NÃO promover `broadcast_race` como produto final.

## Implementação atual aditiva

- `game/scripts/stadium_world.gd`, classeStadiumWorld: pista vermelha +X, raias Z=-2.2/+2.2, torcida animada1200 em1MultiMesh, LEDs, bandeiras, nuvens/palmas,30.352tri/24surfaces. Paralaxe100%/18%/6.5%, blocos8/16m. Dia/tarde/noite. Sem custoAPI. Autoragente stadium_world; contrato docs/STADIUM_WORLD.md, capturas arena-dia-v4/noite-v1. Fallback visual é básico de fundo, esperando arquibancada detalhada daAPI.
- `game/scripts/stadium_hud.gd`, classeStadiumHUD: Bungee+ChakraPetch/OFL, azul forte, vermelho/verde-amarelo, timer/metragem/kmh/vitórias reais, banners e4mecânicas. Autorstadium_hud validou/capturou. Root moveu footer de1358..1460 para1550..1652 para liberar pés. Badges atéy1500.
- `game/scripts/stadium_runner.gd`, classeStadiumRunner extendsHeroRunner: GLBs aprovados, VisualRoot.top_level=true ancorado emstage_position, rotaçãoY=-1.95 corre+X comleve3/4 para câmera. Física/contadores/colisores ainda no percurso-Z original. LODbias3, não altera asset fonte.
- `game/scripts/stadium_race.gd`, `game/scenes/main/stadium_race.tscn`: corrida real sobreRaceMain,50x600s. Câmara ortográficaKEEP_HEIGHT size10.5, posição(0,9.28,12), mira(0,2.35,0). Modelos separados ~370px/raia, sem divisão artificial de tela. Metros físicos permanecem reais; representação da vantagem comprimida/clamp1.9m para manter duelo noquadro; deslocamento do piso0.18worldunits/m aproxima passada àvelocidade. Obstáculos físicos mantêm colisores originais, meshes mapeados para a raia visual; sombras de contato suaves2quads, nenhum shadowpasscaro. P/pausa,1/2turbo,3/4ataque,5/6escudo,R/espaço restart.
- Primeira captura real: `docs/evidencias/estadio/corrida-lateral-v1.png`,1080x1920,14stestdescarta2s,60.002FPS/p9516.667ms, ambos~168m/09:47. **Não é aprovação visual nem32h**, cenário ainda esperaassetdetalhado, root precisa revisarrefinar.

## Fluidez corrigida além de metadados

`tools/inspect_animation_loop.py` constatou28.2graus entre último/primeiro quadro doAPIrun (ambos). `CandidatePresentation._continuous_run_loop` agora cria cópia local reamostrada60fps comsobreposição circular.12s, duraçãooriginal-.12. Fim/início têm mesma pose e fluxo de movimento; GLBoriginal intocado. `test_idle_presentation` verifica seamangular<.001rad paraambos; strictpassou, assimcomohero. Run/idle privados, blend.22s e suaviza speedscale por12/s. Ainda requer inspeção perceptiva/vídeo, não prometerperfeição.

## Crédito e arquibancada

SaldoAPI antesdaárea910/frozen0,90consumidos emrig25+run10+idle10 porpersonagem. Studio580 éoutrosaldo, não confundir.

Imagegen built-in gerou referência de arquibancada modular premium, salva **assets/environments/stadium/concepts/grandstand-reference-v1.png**. Fonte gerada em C:/Users/Kanex/.codex/generated_images/01a168f5-d766-7493-85ad-1f6e9261bf11/exec-7b26d6f4-343e-43f4-a5b8-6749e19d64b5.png. Promptstandalone6rows emptyyellow/green/blue seats, whitecantileverroof/cobaltfacia/goldfloodlights/LEDribbon/nopeople. Tooltransparenttrue mas a imagemvisível temfundo; não afirmaralpha semverificar.

Dryrun válido **docs/TRIPO_STADIUM_V1_PLAN.json**: image-to-modelv3.1-20260211,texture/pbrtrue,detailed;1task,semconversãoFBX. Preçooficialexpected40(30imagecomtexture+10detailed), verificarconsumed_creditreal. Primeiratentativafalhouredeantesregistrartarefa; saldo910/frozen0 ehistorysemnova geração confirmados. Uploadgratuito deu certo, então repetimosUMAvez.

**Tarefa ativa `8bbe10bc-8a27-4ce4-8081-430fd4afacf3`**. CLI make ainda aguardando noexecsession **37914**, modelo41% noúltimocheckpoint. NÃOreenviar geração: consultar taskget/watch se houver timeout. Resultado vai docs/TRIPO_STADIUM_V1_RESULT.json;arquivos assets/environments/stadium/tripo-grandstand-v1. Quando terminar,inspecionarGLB, otimizar localmente sepreciso, enquadrar módulo8m antesplugaremStadiumWorld.grandstand_scene. CadacomandoPago sempreprecedido dryrun. ArquivoUPLOAD contémfiletoken temporário; não publicar/dumparsegredos. Nenhuma chave foi lida.

## Validações anteriores e limites

- Brasília experimentalcapturasFullHDvalidas, rootGTK1inst60FPS. Duasinstâncias simultâneas24s:singlecam39.47FPS/p9529.3ms e split58.66FPS/p9521.66ms; NÃOprometer60FPS2lives. Novolateralmenospasses de sombra/LOD3 precisanovamedição.
- Editorproject.godot ainda aponta **race_main.tscn** antigo, não promovemosBrasíliarejeitada. Internaresolução agora `window/stretch/mode=viewport`,1080x1920+MSAA4. PrimeirasBrasíliacapturas596x1061eramreduzidas, não compararFPScomFullHD.
- Artistasstadium_world/HUD já entregaram; pedir revisão independente daNOVAdireção apósintegração. AntigarevisãoBrasíliaaprovadanãocobreStadiumRace nemnovoLoopbake.
- Próximos: esperarTripo/inspecionar/integrarasset,refinarrenderlateral+câmera/efeitos, testesintegrados+independente, testar2instnovas+OBS, criarlaucher/promovermainapósaceitevisual. EventosTikTok/Kwai/persistência32hcontinuampendentes.
- Usuário pediu explicitamente para deixar habilitaçãodepresentesporúltimo. Linkscontas TikToknostalgiia.br eKwai mentalista.. emmensagem; diznuncainiciouKwai eacreditapresentesTikTokpermitidos. Não tratarcomo confirmado. Nenhumacompra/login/livefoiiniciada.
