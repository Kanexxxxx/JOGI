# Referência visual oficial de direção — HUD JOGI (24/10/2026)

## Status
**Referência conceitual aprovada para estudo, não screenshot nem especificação para cópia literal.**
A imagem foi criada em conversa com o usuário em 24/10/2026. O original em PNG chama-se `HUD_CONCEITO_CHATGPT_2026-10-24.png`. **O PNG ainda precisa ser adicionado por um agente que tenha acesso à pasta local e ao arquivo original**, em `docs/referencias/hud-conceito-chatgpt-2026-10-24.png`. Não apontar este Markdown como se o PNG já estivesse aqui. Não gerar outra imagem no lugar do original.

## Estado anterior e o que deve mudar
- Cena atual `game/scenes/main/stadium_race.tscn`; HUD em `game/scripts/stadium_hud.gd`, coordenação em `game/scripts/stadium_race.gd`.
- Um painel de meta principal com rótulo `SEGUIDORES +0`; o usuário deseja três objetivos legíveis: **curtidas, presentes e 10.000 seguidores**. O total de seguidores do perfil não pode ser inventado se a plataforma apenas expõe novos follows.
- Placar Lula **13** e Flávio **22**: manter rostos/identidade, posição dinâmica, distância, velocidade e cor associados em uma única linha/card.
- Ano **2027** atualmente pouco legível: corrigir tipografia, contraste e localização sobre/ante o Planalto, sem esconder o prédio.
- Top 5 em texto e moedas: condensar, rotular métrica verdadeira; não confundir moedas com quantidade de presentes. Preservar Top 3 no pódio.
- Cards transitórios de interações: foto real do espectador quando disponível e autorizada, nome em **uma só linha**, reticências por largura, ação, presente real e quantidade; time somente se definido. Não mostrar retratos fictícios como usuários reais.
- `GiftVisualCache` **já é integrado a `StadiumRace` e a `StadiumHUD.set_gift_legend()`**; validar exibição real e fallback em vez de reimplementar conexão existente.
- Priorizar cenário 3D da corrida, pista cobalto, capas/modelos já aprovados. A imagem conceitual tem muitos painéis na parte inferior; simplificá-los.

## Safe areas e QA
`DESIGN.md` histórico registra área superior com sobreposição da plataforma e área inferior com chat/controles nativos. Não copiar literalmente metas no topo, card feed e ranking no rodapé se ficam invisíveis no TikTok/Kwai. Testar realmente os dois modos, com overlays e captura em celular. Usar containers/âncoras em Godot, truncamento correto para emojis, acentos e nomes gigantes. Exercitar 1080×1920, 720×1280, 540×960, 360×640.

## Fontes de verdade
Ler `AGENTS.md`, `CONTINUIDADE.md`, `docs/ESTADO_ATUAL.md`, `docs/REVISAO_ESTREIA_24.md`, `services/live_bridge/GIFT_VISUALS_CONTRACT.md`, `services/live_bridge/AUDIENCE_CONTRACT.md`, `services/live_bridge/KWAI_EVENTOS_PENDENTES.md`.

Referência é arte conceitual; capturas de validação devem ser tiradas diretamente do Godot. Registrar testes e commits em documentação de continuidade. O repositório é público: **não versionar segredos, cookies, tokens ou credenciais reais**.

## Próxima ação de quem tem a pasta do JOGI
Copie o PNG original enviado pelo usuário para `docs/referencias/hud-conceito-chatgpt-2026-10-24.png` e crie um commit somente da imagem e deste documento atualizado. Depois siga o arquivo `JOGI_PROMPT_MESTRE_RETOMADA_2026-10-24.md`, entregue ao agente na conversa.
