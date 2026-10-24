# Stack observada — 23/10/2026

## 1) Runtime

| Área | Valor | Evidência |
|---|---|---|
| Jogo | GDScript / Godot 4; configuração 4.7, executável 4.7.2 confirmado | `game/project.godot`, comando `--version` |
| Backend | Python >=3.11; ambiente local 3.14.7 | `services/live_bridge/pyproject.toml`, `.venv/Scripts/python.exe --version` |
| Painel | HTML, CSS e JavaScript direto no browser | `services/live_bridge/admin/` |
| Pacotes | uv e uv.lock; sem package.json no produto | `services/live_bridge/uv.lock` |
| Build | Cena Godot e arquivos estáticos; sem build npm identificado | `game/project.godot`, `server.py` |

## 2) Dependências de produção

`websockets>=12.0` é a única dependência direta declarada em `services/live_bridge/pyproject.toml`. O serviço usa asyncio, json, logging e outras bibliotecas padrão. TikTokLive tem import opcional em `adapters/tiktok_adapter.py`, mas não está no manifesto nem no lock como dependência do projeto. Não foi identificado ORM, banco de dados, framework frontend ou FastAPI em execução.

## 3) Ferramentas de desenvolvimento

pytest>=8 e pytest-asyncio>=0.23 são grupos dev declarados. GDA 0.24.1 e Godot 4.7.2 foram verificados e usados nos testes. Tripo é ferramenta de arte prevista em `ART_DIRECTION.md`; não foi utilizado. Não há CI/Docker ou linter/formatter configurado identificado no produto.

## 4) Comandos principais

Executar da raiz:

```powershell
.\services\live_bridge\.venv\Scripts\python.exe .\services\live_bridge\server.py
.\services\live_bridge\.venv\Scripts\python.exe -m pytest services/live_bridge -q -p no:cacheprovider
.\services\live_bridge\.venv\Scripts\python.exe services/live_bridge/test_e2e_runner.py
```

Para recriar dependências conforme README: `C:\Users\Kanex\.local\bin\uv.exe sync --project services/live_bridge`. Não foi necessário instalar ou sincronizar pacotes nesta etapa. Comandos GDA e de abertura visual: `TESTING.md` desta pasta e `../../MAPA_DO_PROJETO.md`.

## 5) Ambiente e configuração

Configuração real do jogo: `game/project.godot`, resolução 1080x1920, prévia 540x960, autoload LiveEventBus. Serviço: argumentos `--host` e `--port`, loopback por padrão. `.env.example` é documentação de variáveis pretendidas, não prova de carregamento automático; `server.py` não lê LIVE_MODE ou LIVE_BRIDGE_LOCAL_TOKEN. E2E fixa caminhos locais de GDA/Godot. [TODO] Portabilidade desses caminhos e estratégia de exportação/distribuição.

## 6) Evidências

`game/project.godot`; `services/live_bridge/pyproject.toml`; `services/live_bridge/uv.lock`; `services/live_bridge/server.py`; `services/live_bridge/test_e2e_runner.py`; `.env.example`; versões executadas no levantamento.
