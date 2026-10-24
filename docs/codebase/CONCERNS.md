# Pendências e divergências — 23/10/2026

## 1) Principais riscos

| Prioridade | Achado | Evidência | Impacto | Próximo trabalho proposto |
|---|---|---|---|---|
| Alta | Código sem histórico Git; game/services não rastreados | git log/status/remote | Sem baseline versionada local | Revisar inventário e criar primeiro commit completo |
| Alta | Simulação própria do painel altera números e fases | admin/app.js:896 e chamada no init | Painel pode não representar o jogo | Separar modo demonstração e telemetria real |
| Alta | Auto-loop desativado por padrão | race_main.gd:34, race_main.tscn | Interrompe objetivo 24/7 no pódio | Definir/validar operação contínua |
| Alta | Adaptadores não são iniciados pela CLI | server.py:1087, pyproject.toml | Não há captura real automática | Ligar e validar uma fonte real após estabilizar offline |
| Média | Contrato de ARCHITECTURE difere de protocol.py | actor/event_type/target versus user/slot | Novos clientes podem emitir pacotes rejeitados | Consolidar contrato de execução |
| Média | Regras e tempos divergem do design | race_main.gd, live_event_bus.gd, protocol.py | Balanceamento e expectativas diferentes | Escolher fonte de regras e sincronizar |

## 2) Débito técnico

| Item | Evidência / origem observável | Risco | Sugestão |
|---|---|---|---|
| Documentos de fases diferentes | DESIGN/TESTING ainda falam em seis candidatos | Retomar escopo antigo por engano | Atualizar após decisão de produto |
| Módulos grandes | server.py, race_main.gd, admin/app.js excedem 500 linhas | Mudanças cruzam várias responsabilidades | Extrair módulos com testes existentes como proteção |
| Caminhos fixos | test_e2e_runner.py usa caminhos Windows pessoais | Falha em outra máquina | Configuração explícita de binários |
| Arte procedural versus pipeline previsto | candidate_runner.gd; ausência de biblioteca de modelos em game | Visual final ainda não avaliado | Validar aparência antes de gerar assets |
| Arquitetura Resources/pooling prometida | ARCHITECTURE versus spawn/queue_free do jogo | Complexidade e estabilidade ainda sem prova | Medir necessidade antes de refatorar |

Não foi determinado o motivo histórico dessas diferenças: não há commits para reconstruí-lo. O texto de fuzzing HACKER_BBCODE no simulador é dado de teste, não uma pendência de produção.

## 3) Segurança

| Risco | Categoria | Mitigação presente | Lacuna / evidência |
|---|---|---|---|
| Autorização local | Controle de acesso | Bind 127.0.0.1, validação Host/Origin | LOCAL_TOKEN descrito em SECURITY não é validado em server.py |
| Entradas de usuários | Injeção | Sanitização protocol.py e textContent no painel | Auditoria exaustiva não realizada |
| Sobrecarga de eventos | Disponibilidade | Filas limitadas, LRU e token bucket | Estabilidade prolongada não medida |
| Segredos | Gestão de credenciais | .gitignore e exemplos locais | Não foi realizada varredura completa de valores sensíveis |

Este mapa não substitui auditoria de segurança. Não foi identificada necessidade de credenciais para os testes locais realizados.

## 4) Performance e escala

| Ponto | Evidência | Sintoma observado | Risco / próximo teste |
|---|---|---|---|
| Obstáculos criados/removidos | race_main.gd spawn e queue_free | Nenhuma medição de vazamento feita | Medir muitas rodadas e contagem de nós |
| Estado em memória | server.py, protocol.py | Não há persistência identificada | Perda no reinício; avaliar recuperação |
| FPS | Painel mostra texto fixo; execução foi headless | FPS real desconhecido | Medir renderização 1080x1920 |
| Dupla simulação | app.js + Godot | Identificada por leitura | Medir divergência e remover ambiguidade |

## 5) Áreas frágeis e histórico

Não é possível calcular churn: Git não tem commits. Áreas de maior concentração são RaceMain, LiveBridgeServer, protocol.py e app.js. Mudanças futuras devem preservar uma base versionada, validar contrato Python/Godot e repetir as suítes pertinentes. Revisão independente somente leitura confirmou os achados principais; não participou da criação do código.

## 6) Pergunta de intenção

1. [ASK USER] Manter Lula vs. Bolsonaro na retomada ou escolher outro elenco? Não é necessário responder para concluir o mapa; é uma decisão antes de alterar o produto.

## 7) Evidências

`GAME_DESIGN.md`; `DESIGN.md`; `ARCHITECTURE.md`; `TESTING.md`; `SECURITY.md`; `game/scripts/{race_main,live_event_bus,candidate_runner}.gd`; `game/scenes/main/race_main.tscn`; `services/live_bridge/{server,protocol,test_e2e_runner}.py`; `services/live_bridge/admin/app.js`; comandos Git; resultados detalhados em `TESTING.md` desta pasta.
