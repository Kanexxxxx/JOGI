# Referência visual oficial de direção — HUD JOGI (24/10/2026)

- **Arquivo PNG original versionado (intacto, sem recriação ou recompressão):** [hud-conceito-chatgpt-2026-10-24.png](hud-conceito-chatgpt-2026-10-24.png) (`2.370.882` bytes · SHA-256 `3859DF3DB23DEEAD064A8C75E83F86055ECFE47FE63602423916C4E186CD01D8`).
- **Prompt mestre associado:** [../AGENTE_RETOMADA_PROMPT_MESTRE_2026-10-24.md](../AGENTE_RETOMADA_PROMPT_MESTRE_2026-10-24.md).

![Referência conceitual oficial do HUD JOGI](hud-conceito-chatgpt-2026-10-24.png)

## Status
**Referência conceitual oficial aprovada para direção visual e estudo de hierarquia — não é screenshot do Godot nem especificação para cópia literal pixel a pixel.**
Use suas melhorias visuais como inspiração (três metas claras, placar esportivo limpo, `2027` legível sobre o Planalto, cards sociais concisos, Top 5 organizado e 4 habilidades na base), mas **mantenha o jogo limpo, responsivo, respeitando safe areas de TikTok/Kwai e sem excesso de elementos sobre os corredores**.

## Diretrizes obrigatórias derivadas desta referência
- Cena ativa: `game/scenes/main/stadium_race.tscn`; HUD em `game/scripts/stadium_hud.gd`, coordenação em `game/scripts/stadium_race.gd`.
- **Três objetivos simultâneos e independentes**: **Curtidas**, **Presentes** (unidades ou presente específico por ID) e **Seguidores (meta 10.000)**. O total global de seguidores do perfil nunca deve ser inventado como `0/10.000` real quando a plataforma expõe apenas novos follows da sessão (exibir claramente progresso da sessão ou baseline manual rotulado).
- **Placar Lula `13` vs Flávio `22`**: manter retratos aprovados, posição dinâmica (`1º` / `2º`), distância (`m`), velocidade (`KM/H`), barra de vantagem e cores da equipe movendo-se como unidade.
- **Ano `2027` claramente legível**: reforçar contraste, tipografia e escala equilibrada junto ao Palácio do Planalto sem encobrir sua arquitetura.
- **Top 5 com métrica honesta**: rotular explicitamente `TOP 5 · MOEDAS` (preservando o cálculo financeiro real e o Top 3 no pódio), com truncamento limpo em uma linha e estado vazio compacto.
- **Cards transitórios de interações**: entrada discreta (máximo 1–2 cards simultâneos com TTL curto, nunca 5 cards fixos tapando os corredores), foto real do espectador apenas via cache local seguro anti-SSRF (com fallback limpo de iniciais/ícone), nome em **uma única linha** com reticências e chip `13`/`22` somente quando houver time escolhido.
- **`GiftVisualCache`**: já conectado a `StadiumRace` e `StadiumHUD.set_gift_legend()`; manter proporção, legendas em português e fallback vetorial limpo.

## Safe areas e QA
Respeitar sobreposições nativas de TikTok/Kwai no topo e rodapé, validar em `1080×1920`, `720×1280`, `540×960` e `360×640` no Godot e `375px / 768px / 1440px` no painel web. Capturas de entrega devem vir sempre do motor Godot real, diferenciadas da imagem conceitual acima.

## Fontes de verdade
Ler `AGENTS.md`, `CONTINUIDADE.md`, `docs/ESTADO_ATUAL.md`, `docs/AGENTE_RETOMADA_PROMPT_MESTRE_2026-10-24.md`, `docs/REVISAO_ESTREIA_24.md`, `services/live_bridge/GIFT_VISUALS_CONTRACT.md`, `services/live_bridge/AUDIENCE_CONTRACT.md` e `services/live_bridge/KWAI_EVENTOS_PENDENTES.md`.
