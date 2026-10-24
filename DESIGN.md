# DESIGN.md — Sistema Visual (HUD Broadcast 9:16 & Painel Administrativo Web)

> Estruturado com base nas melhores práticas de especificação de design systems para agentes (`VoltAgent/awesome-design-md`), combinado com `design-taste-frontend` e `web-design-guidelines`.

---

## 1. Identidade Visual e Conceito ("Arena Eleitoral de TV / Arcade Show")

**Corrida dos Candidatos** possui duas superfícies visuais complementares que compartilham tokens cromáticos e tipográficos, mas atendem a contextos distintos:
1. **HUD Broadcast Vertical (`1080x1920` — 9:16 dentro do Godot 4)**: Estética de programa de auditório esportivo / *Fall Guys* / *broadcast graphics* de alta energia. Alto contraste, bordas sólidas, leitura instantânea em telas pequenas com compressão de vídeo.
2. **Painel Administrativo & Telemetria Web (`1440x900` Desktop / `390x844` Mobile)**: Estética de *Broadcast Control Room* (mesa de corte/direção de TV ao vivo). Fundo escuro tático, indicadores numéricos tabulares sem jitter, botões de emergência claros e zero poluição decorativa.

---

## 2. Zonas Seguras para Transmissão Vertical 9:16 (`1080x1920`)

Os aplicativos do TikTok e do Kwai sobrepõem elementos nativos sobre o vídeo da live. O HUD do Godot DEVE respeitar rigorosamente o mapa abaixo:

```
+---------------------------------------+ y = 0
| [ZONA BLOQUEADA TOPO: 0 - 260px]      | <- Avatar do Host, Live Badge, Viewers
+---------------------------------------+ y = 260px
| [PLACAR LÍDERES & CRONÔMETRO: 260-440]| <- Top Bar / Placar Compacto dos Candidatos
+---------------------------------------+ y = 440px
|                                       |
|   [ALERTAS DE PRESENTES / COMBOS]     |
|                                       |
|      [JANELA DE AÇÃO 3D CENTRAL]      | [920-1080px: Botões
|         (Corredores na Pista)         |  Like/Share/Gift]
|                                       |
+---------------------------------------+ y = 1220px
| [BARRA DE INSTRUÇÃO RÁPIDA: 1220-1340]| <- Ex: "Digite #1, #2, #3 ou envie Rosa!"
+---------------------------------------+ y = 1340px
| [ZONA DE CHAT NATIVO: 1340 - 1920px]  | <- Comentários da Live e Bandeja de Gifts
|  (Apenas pista 3D de fundo, ZERO UI)  |
+---------------------------------------+ y = 1920px
```

---

## 3. Paleta de Cores e Tokens Semânticos

### 3.1 Superfícies (Broadcast Control & HUD Containers)
- `--bg-canvas`: `#0B0E17` (Azul-noite profundo de estúdio)
- `--bg-surface`: `#131826` (Painel principal / HUD container com 88% de opacidade `rgba(19, 24, 38, 0.88)`)
- `--bg-elevated`: `#1E263B` (Cards de fila de eventos / controles ativos)
- `--border-subtle`: `#2A3550` (Divisores técnicos `1px solid`)
- `--border-focus`: `#38BDF8` (Anel de foco acessível `2px solid`)

### 3.2 Cores Assinatura dos Candidatos (Alta Visibilidade 3D & HUD)
Cada candidato na pista possui uma cor primária saturada que nunca se confunde sob iluminação dinâmica ou compressão H.264:
- **Raia 1 — Candidato Vermelho Coral**: `#FF3B5C` (Texto sobre cor: `#FFFFFF`)
- **Raia 2 — Candidato Azul Elétrico**: `#00A8FF` (Texto sobre cor: `#FFFFFF`)
- **Raia 3 — Candidato Amarelo Ouro**: `#FFC800` (Texto sobre cor: `#0B0E17`)
- **Raia 4 — Candidato Verde Esmeralda**: `#00E676` (Texto sobre cor: `#0B0E17`)
- **Raia 5 — Candidato Roxo Neon**: `#B347FF` (Texto sobre cor: `#FFFFFF`)
- **Raia 6 — Candidato Laranja Solar**: `#FF7A00` (Texto sobre cor: `#0B0E17`)

### 3.3 Sinais Semânticos de Evento e Telemetria
- `--status-boost` (Turbo / Presente Positivo): `#00F5D4`
- `--status-hazard` (Obstáculo / Sabotagem): `#FF2A85`
- `--status-jackpot` (Presente Lendário / Mega Evento): `#FFD700`
- `--status-ok` (WebSocket Conectado / 60 FPS): `#22C55E`
- `--status-warn` (Fila Represada / Reconectando): `#F59E0B`
- `--status-danger` (Erro Crítico / Parada de Emergência): `#EF4444`

---

## 4. Tipografia e Escala

- **Display / HUD Placar e Alertas 3D**: `Chakra Petch`, `Montserrat Black` ou `Rubik Bold` (caixa alta nos nomes dos candidatos, contorno externo preto de `3px` a `4px` no Godot `LabelSettings` para leitura perfeita sobre qualquer fundo 3D).
- **Interface Administrativa (Corpo)**: `Inter` ou `Plus Jakarta Sans`.
- **Telemetria, Cronômetros, Contadores de Votos e Logs**: `JetBrains Mono` (ou `font-variant-numeric: tabular-nums` obrigatório em todos os números dinâmicos).
- **Tamanhos Mínimos no HUD `1080x1920`**:
  - Nome do Candidato no Placar: `32px` (Bold)
  - Posição (`1º`, `2º`, `3º`): `40px` (Black)
  - Banner de Presente ("@usuario enviou ROSA -> TURBO!"): `36px` (Título) / `28px` (Subtítulo)
  - Nunca usar fonte menor que `24px` no HUD de vídeo 9:16.

---

## 5. Regras de Componentes e Anti-Padrões

1. **Zero Números Saltitantes**: Todo cronômetro, FPS, contador de curtidas e placar usa `tabular-nums`.
2. **Truncamento Seguro de Nomes de Usuários**: Nomes vindos do TikTok/Kwai são truncados em 20–24 caracteres com reticências (`text-overflow: ellipsis`, `max-width`) para jamais quebrar o layout do banner.
3. **Sem Cards Aninhados Desnecessários**: No painel web, agrupar dados por seções claras (Status da Conexão, Controles da Partida, Simulador de Eventos, Fila em Tempo Real) com espaçamento generoso (`gap: 16px` / `padding: 20px`).
4. **Acessibilidade e Segurança Operacional**: Botões destrutivos no painel administrativo ("Reiniciar Partida Agora", "Limpar Fila de Presentes") ficam separados dos botões de simulação e exigem confirmação ou estado explícito.
