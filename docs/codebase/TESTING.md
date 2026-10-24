# Testes e verificação — 23/10/2026

## 1) Stack e comandos

Manifesto: pytest>=8 e pytest-asyncio>=0.23. Testes Python usam também unittest/IsolatedAsyncioTestCase e asserts. Godot usa scripts SceneTree; GDA 0.24.1 orquestra Godot 4.7.2. Executar na raiz JOGI:

```powershell
.\services\live_bridge\.venv\Scripts\python.exe -m pytest services/live_bridge -q -p no:cacheprovider
.\services\live_bridge\.venv\Scripts\python.exe services/live_bridge/test_e2e_runner.py

$gdaExe = 'C:\Users\Kanex\.local\bin\gda.exe'
$godotExe = 'C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
& $gdaExe project scan --project '.\game' --json
& $gdaExe script validate --all --project '.\game' --godot $godotExe --json
& $gdaExe scene validate res://scenes/main/race_main.tscn --project '.\game' --json
& $gdaExe scene preflight res://scenes/main/race_main.tscn --project '.\game' --godot $godotExe --json
foreach ($suite in @('test_lula_vs_bolsonaro','test_fase3_admin_telemetry','test_race_prototype')) {
    & $gdaExe script run "res://tests/$suite.gd" --strict --project '.\game' --godot $godotExe --json
}
```

Os comandos foram executados com caminhos absolutos equivalentes. GDA script validate pode retornar exit code zero com valid=false; conferir o JSON. O scan foi executado antes da validação; script/scene/preflight acima tiveram resultados positivos.

## 2) Layout

`services/live_bridge/test_live_bridge.py`, `adapters/test_adapters.py` e `test_e2e_runner.py`; este último fornece main para execução explícita E2E. `game/tests/` contém testes de protótipo, sátira de dois corredores, telemetria administrativa e integração WebSocket. Configuração pytest está em `pyproject.toml`.

## 3) Escopo e resultados desta inspeção

| Camada | Resultado atual | Limite |
|---|---|---|
| Python unitário/integração | 27 aprovados em 22,53 s | Não é live externa |
| Compilação GDScript | 8 scripts válidos | Não prova comportamento em carga |
| Cena | Válida; preflight ready/started | Não mede aparência ou FPS |
| Godot mecânicas/telemetria/protótipo | Três suítes strict aprovadas | Cenários automatizados existentes |
| E2E Godot + Python | Aprovado, conexão/telemetria/eventos | Simulador local; seis envelopes aceitos no servidor |
| Browser/visual | Não executado | [TODO] Janelas desktop/mobile e alinhamento do HUD |
| Live real / 24 horas / FPS | Não executado | [TODO] Captura real, estabilidade, medição e memória |

## 4) Isolamento

Adaptadores são exercitados com eventos sintéticos e simulador; testes de servidor usam sockets locais. O E2E sobe sua própria instância em 8765 e encerra-a; depende de a porta estar livre e dos caminhos de binários fixados no runner. A suíte headless pode manipular tempos/estados, portanto aprovação não equivale a uma sessão visual completa.

## 5) Cobertura e qualidade

[TODO] Não foi identificado limiar de cobertura ou relatório percentual. Ausência de falha nas suítes não cobre reinício automático padrão, fidelidade da telemetria do painel, limites descritos de likes/shares, contrato documental antigo, soak test ou proteção por token. `CONTINUIDADE.md` relata aprovações históricas; os resultados acima foram verificados novamente em 23/10/2026. Nenhum teste novo foi adicionado para a tarefa de documentação.

## 6) Evidências

`services/live_bridge/pyproject.toml`; `services/live_bridge/test_live_bridge.py`; `services/live_bridge/adapters/test_adapters.py`; `services/live_bridge/test_e2e_runner.py`; `game/tests/*.gd`; saídas de pytest e GDA desta execução; `TESTING.md` da raiz.
