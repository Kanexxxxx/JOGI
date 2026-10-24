# TESTING.md — Estratégia de Testes Automatizados e Qualidade

---

## 1. Camadas de Teste do Projeto

Nenhuma funcionalidade em **Corrida dos Candidatos** é aceita sem passar pelas 4 camadas de validação automatizada:

### Camada 1: Validação Estática e Preflight no Godot 4 (`gda` CLI)
Executada após qualquer criação ou alteração em `.gd`, `.tscn`, `.tres` ou `.gdshader`:
```powershell
# 1. Atualizar índice de class_name
C:\Users\Kanex\.local\bin\gda.exe project scan --project C:\Users\Kanex\OneDrive\Desktop\JOGI --json

# 2. Validar sintaxe e tipagem estática do GDScript
C:\Users\Kanex\.local\bin\gda.exe script validate res://scripts/<arquivo>.gd --project C:\Users\Kanex\OneDrive\Desktop\JOGI --json

# 3. Validar integridade da cena e dependências ext_resource
C:\Users\Kanex\.local\bin\gda.exe scene validate res://scenes/<cena>.tscn --project C:\Users\Kanex\OneDrive\Desktop\JOGI --json

# 4. Boot controlado da cena (Preflight) para capturar erros em _ready()
C:\Users\Kanex\.local\bin\gda.exe scene preflight res://scenes/<cena>.tscn --project C:\Users\Kanex\OneDrive\Desktop\JOGI --json
```
- **Critério de Aprovação**: JSON retornado deve conter `"valid": true` e, no preflight, `"started": true` sem erros de script.

### Camada 2: Testes Unitários e de Integração Headless no Godot (`gda script run --strict`)
- Testes cobrindo:
  - Transições da `MatchStateMachine` (`Lobby -> Countdown -> Racing -> PhotoFinish -> Podium -> Reset`).
  - Cálculo determinístico de classificação (`1º` ao `6º` lugar via `Path3D`).
  - Aplicação de impulsos, escudos e período de invencibilidade pós-impacto (*grace period*).
  - **Verificação de Vazamento de Memória**: Ao final de 10 ciclos simulados de reset de partida, `Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)` DEVE ser exatamente `0`.

### Camada 3: Testes do Conector `LiveBridge` (`pytest` via `uv`)
- Testes unitários automatizados em `tests/live_bridge/` validando:
  - Sanitização de nomes de usuário e comentários maliciosos (remoção de BBCode `[color=...]`, tags HTML, caracteres de controle e truncamento em 24 caracteres).
  - Deduplicação idempotente de `event_id` repetidos.
  - Coalescing e rate limiting sob carga de `1.000 eventos/s` do `MockLiveEventSimulator`.

### Camada 4: Testes E2E e Visuais do Painel Administrativo (`playwright-cli`)
- Inspeção de acessibilidade (`playwright-cli snapshot`), verificação de zero erros no console (`playwright-cli console warning`) e captura de screenshots em `1440x900` e `390x844`.
