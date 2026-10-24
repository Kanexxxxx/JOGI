# Convenções observadas — 23/10/2026

## 1) Nomes

| Elemento | Padrão | Exemplo / evidência |
|---|---|---|
| Arquivos | snake_case | candidate_runner.gd, protocol.py, test_live_bridge.py |
| Funções/variáveis | snake_case | start_racing, candidate_slot |
| Tipos/classes | PascalCase | CandidateRunner, LiveBridgeServer |
| Membros internos | Prefixo `_` | _physics_process, _dispatch_loop |
| Constantes | UPPER_SNAKE_CASE | MAX_PACKET_BYTES, CANDIDATE_DEFS |
| Documentos centrais | Maiúsculas | GAME_DESIGN.md, SECURITY.md |

## 2) Formatação e validação

AGENTS exige GDScript tipado; os scripts inspecionados usam tipos, class_name e retornos anotados. GDScript usa tabulação; Python usa anotações e dataclasses. Não foi encontrada configuração de formatter/linter do produto. A compilação dos oito scripts passou via GDA; isso não é auditoria formal de tipagem completa.

Validação: `gda script validate --all --project <raiz>/game --godot <console> --json`. Respeitar `.cmd` ao invocar npm/npx/tripo em PowerShell, conforme AGENTS.

## 3) Imports e módulos

Godot referencia `res://` relativo à pasta game. Python usa imports locais; adaptadores apresentam fallback entre `from protocol` e `from ..protocol`, facilitando execução de scripts e uso como módulo. Não foi identificado alias de imports frontend nem bundler. JavaScript inicia pelo HTML servido.

## 4) Erros, logs e dados externos

Python usa logging, exceções e respostas estruturadas. O barramento Godot emite event_rejected e sinaliza conexão. O painel usa textContent para dados de usuários. SECURITY proíbe segredos em chat/Git; `.gitignore` bloqueia `.env`, chaves e arquivos locais de configuração. Não foram abertos valores de credenciais nem feita auditoria exaustiva de segredos neste mapa.

## 5) Testes

Python: arquivos `test_*.py` próximos ao código, unittest/pytest e async. Godot: `game/tests/test_*.gd`, scripts SceneTree com marcadores PASS/FAIL. Integração local via sockets e simuladores; não há prova de live externa. [TODO] Cobertura percentual e limiar automatizado não identificados no manifesto.

## 6) Evidências

`AGENTS.md`; `SECURITY.md`; `.gitignore`; `services/live_bridge/pyproject.toml`; `services/live_bridge/adapters/tiktok_adapter.py`; `services/live_bridge/server.py`; `services/live_bridge/admin/app.js`; `game/scripts/*.gd`; `game/tests/*.gd`.
