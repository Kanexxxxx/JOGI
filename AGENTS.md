# AGENTS.md — Diretrizes Mestras e Orquestração (Corrida dos Candidatos)

Este arquivo define as instruções persistentes, a estrutura da equipe de agentes, os fluxos de trabalho e as políticas de ferramentas para o projeto **Corrida dos Candidatos** no Google Antigravity (`Antigravity CLI v1.4.2` / `Gemini 4 Argon (High)`).

---

## 1. Visão Geral do Projeto

**Corrida dos Candidatos** é um jogo 3D automatizado e interativo projetado para transmissões ao vivo 24/7 no **TikTok Live** e no **Kwai**, renderizado em formato vertical **9:16 (`1080x1920`)** a **60 FPS** no **Godot 4.x**.
Espectadores interagem em tempo real por meio de **curtidas**, **comentários de voto** (`#1`, `#2`, palavras-chave), **compartilhamentos** e **presentes/moedas**, acionando impulsos (turbos), escudos, eventos climáticos e obstáculos físicos na pista 3D.

---

## 2. Equipe de Agentes Especializados (`.agents/agents/`)

O Antigravity descobre nativamente os agentes em `.agents/agents/*.md`, invocáveis via `invoke_subagent`:

| Agente (`TypeName`) | Papel Principal | Skills Primárias | Escrita |
|---|---|---|---|
| `tech-lead` | Arquitetura, divisão em fases, contratos JSON/`.tres`, controle de escopo | `gda`, `godot-autoload-architecture`, `architecture-decision-records`, `delivery-gate` | Sim |
| `game-designer` | Regras da corrida, loop de retenção, tabela de presentes/votos, balanceamento | `godot-resources`, `godot-ui-control`, `product-lens` | Sim |
| `godot-engineer` | Cenas 3D `.tscn`, GDScript 2.0 tipado, física 3D, câmeras, animações, HUD 9:16, 60 FPS | `gda`, `godot-gdscript`, `godot-3d-essentials`, `godot-physics-3d`, `godot-state-machine-advanced`, `godot-animation`, `godot-ui-control`, `godot-audio`, `godot-shaders`, `godot-performance-optimization` | Sim |
| `3d-art-director` | Estilo caricato 3D, geração/rigging via Tripo CLI, iluminação, legibilidade mobile | `tripo-cli`, `godot-3d-essentials`, `godot-shaders`, `design-taste-frontend`, `image-to-code` | Sim |
| `live-integration-engineer` | Conectores TikTok/Kwai, fila prioritária, deduplicação LRU, simulador local, painel web | `godot-signals-groups`, `web-design-guidelines`, `playwright-cli`, `error-handling` | Sim |
| `qa-engineer` | Testes headless (`gda`), testes de estresse de live, verificação de FPS e orphan nodes | `gda`, `godot-testing-patterns`, `godot-debugging-profiling`, `playwright-cli`, `tdd-workflow` | Sim |
| `security-reviewer` | Auditoria de entradas de chat, proteção de segredos, bind localhost e dependências | `delivery-gate`, `production-audit` | Somente leitura |
| `independent-reviewer` | Revisão independente ("olhos frescos") de código, cenas e testes antes de concluir fases | `gda`, `agent-self-evaluation`, `delivery-gate`, `verification-loop` | Somente leitura |

---

## 3. Fluxo Obrigatório de Trabalho (Quality Gate)

Nenhuma fase ou funcionalidade é considerada pronta sem cumprir as 5 etapas abaixo:

1. **Especificação & Contrato (`tech-lead` + `game-designer`)**: Definição clara dos sinais (`LiveEventBus`), Resources (`.tres`) e critérios de aceite.
2. **Implementação Especializada (`godot-engineer` / `live-integration-engineer` / `3d-art-director`)**:
   - Código GDScript 100% estaticamente tipado (`var x: float = 1.0`, `func f() -> void:`).
   - Modelos 3D gerados pelo `tripo-cli` sempre precedidos por `--dry-run --json`.
3. **Validação Automatizada (`qa-engineer`)**:
   - `C:\Users\Kanex\.local\bin\gda.exe project scan --json`
   - `C:\Users\Kanex\.local\bin\gda.exe script validate <script> --json` (`"valid": true`)
   - `C:\Users\Kanex\.local\bin\gda.exe scene validate <scene> --json` (`"valid": true`)
   - `C:\Users\Kanex\.local\bin\gda.exe scene preflight <scene> --json` (`"started": true`)
4. **Auditoria de Segurança (`security-reviewer`)**: Verificação de sanitização de entradas externas (nomes/comentários da live) e ausência de chaves expostas.
5. **Revisão Independente (`independent-reviewer`)**: Auditoria final sem ter participado da escrita do código.

---

## 4. Políticas de Ferramentas e Ambiente Windows/PowerShell

- **Shims npm/npx/tripo no PowerShell**: Sempre invocar `.cmd` (`npm.cmd`, `npx.cmd`, `C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd`) para evitar bloqueios de `ExecutionPolicy` em scripts `.ps1`.
- **Python & uv**: Utilizar `C:\Users\Kanex\.local\bin\uv.exe` ou `py` (Python `3.14.7`). Nunca usar `pip install` global.
- **Godot Agent (`gda`)**: Binário em `C:\Users\Kanex\.local\bin\gda.exe` (e servidor MCP em `C:\Users\Kanex\.local\bin\gda-mcp.exe`). Requer a variável `GDA_GODOT` apontando para o executável console do Godot 4.6+ (`Godot_v4.*_console.exe`).
- **Proteção de Créditos e Segredos**:
  - Jamais pedir chaves de API (`TRIPO_API_KEY`, tokens de live) no chat.
  - Jamais executar comandos de geração 3D pagos para fins de diagnóstico; usar `tripo.cmd doctor` e `tripo.cmd make ... --dry-run --json`.

---

## 5. Mapa de Documentação Viva do Projeto

- [`DESIGN.md`](DESIGN.md) — Sistema visual do HUD 9:16 e Painel Administrativo Web.
- [`GAME_DESIGN.md`](GAME_DESIGN.md) — Regras da corrida, candidatos, presentes, votos e balanceamento.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — Arquitetura de módulos, `LiveEventBus`, WebSocket e estados.
- [`ART_DIRECTION.md`](ART_DIRECTION.md) — Direção de arte 3D, proporções caricatas, pipeline Tripo CLI e iluminação.
- [`INTEGRATIONS.md`](INTEGRATIONS.md) — Conectores TikTok Live / Kwai, deduplicação, filas e simulador local.
- [`TESTING.md`](TESTING.md) — Estratégia de testes automatizados (Godot, Python, Playwright, Stress Test).
- [`SECURITY.md`](SECURITY.md) — Segurança de entradas externas, variáveis de ambiente e menor privilégio.
- [`CONTINUIDADE.md`](CONTINUIDADE.md) — Inventário atual do ambiente, pendências e plano de retomada.
