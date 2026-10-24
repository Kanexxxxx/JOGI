# Mapa de retomada — JOGI / Corrida dos Candidatos

> **Atualização de intenção:** após este inventário, o usuário esclareceu que o elenco será **Lula e Flávio Bolsonaro**, com espectadores controlando a corrida e término ainda a definir. Leia [BRIEFING_RETOMADA.md](BRIEFING_RETOMADA.md) para a visão atual. O mapa abaixo descreve o código antigo encontrado, não o produto final pedido.

Mapeamento realizado em 23/10/2026. Fontes: arquivos locais, comandos Git, testes executados nesta data e revisão independente somente leitura. Este relatório registra o estado encontrado; não altera regras nem declara o produto pronto para transmissão.

## O que esta pasta é

Um protótipo local de jogo 3D para lives verticais. A versão presente coloca Lula e Bolsonaro correndo em duas raias: comentários, curtidas, compartilhamentos e presentes são convertidos em votos, turbos, escudos ou ataques contra o adversário. A pista é reciclada continuamente, mas cada partida tem 300 segundos. Vence quem percorreu a maior distância.

Existem três partes de produto: o jogo Godot, a ponte de eventos Python e o painel administrativo web. A pasta `.agents/` contém instruções e ferramentas de desenvolvimento; não é um quarto componente executado pelo jogo.

## Mapa de navegação

| Caminho | O que contém | Onde começar |
|---|---|---|
| `game/` | Projeto Godot, cena, quatro scripts de produto e quatro de teste | `game/project.godot` |
| `game/scripts/race_main.gd` | Estados da partida, pista, obstáculos, HUD e telemetria | `RaceMain._ready`, `_physics_process` |
| `game/scripts/candidate_runner.gd` | Personagens procedurais, movimento, turbo, escudo e tropeço | `CandidateRunner` |
| `game/scripts/live_event_bus.gd` | Cliente WebSocket, validação, deduplicação e sinais | `LiveEventBusInstance` |
| `game/scripts/race_camera.gd` | Câmera da corrida | `RaceCamera` |
| `services/live_bridge/` | Serviço local Python, protocolo, simulador e testes | `server.py`, `protocol.py` |
| `services/live_bridge/admin/` | Painel HTML/CSS/JavaScript, sem build npm | `index.html`, `app.js`, `CONTRACT.md` |
| `services/live_bridge/adapters/` | Adaptadores simulador, TikTok e receptor Kwai | `base.py`, `tiktok_adapter.py`, `kwai_adapter.py` |
| `.agents/` | Agentes, skills, regras, workflows e configurações locais | `AGENTS.md`, `.agents/reports/live-integration-plan.md` |
| Documentos da raiz | Produto pretendido, arte, arquitetura, integração, segurança e continuidade histórica | `GAME_DESIGN.md`, `CONTINUIDADE.md` |
| `docs/codebase/` | Sete documentos técnicos deste levantamento | Links abaixo |

```text
Simulador / painel / cliente de ingestão
                  ↓
Python LiveBridge: validação → deduplicação → filas → limite de envio
                  ↓ WebSocket local
Godot LiveEventBus → sinais → RaceMain → CandidateRunner → imagem 9:16
                  ↑                    ↓
                  └──── telemetria ────┘ → painel web

TikTok e Kwai: adaptadores existem, mas não são inicializados por server.py.
```

## O que existe e o que ainda era intenção

| Área | Encontrado no código | Limite / diferença em relação aos documentos |
|---|---|---|
| Elenco | Dois competidores, Lula e Bolsonaro | DESIGN e TESTING ainda mencionam seis raias/candidatos |
| Partida | 300 s, distância acumulada, oito chunks de 40 m | Pista infinita não significa partida sem fim |
| Ciclo 24/7 | Estados lobby, contagem, corrida, apuração e pódio | `auto_loop_after_podium=false`; para no pódio por padrão |
| Tempos | Lobby 6 s, contagem 3 s, apuração 3 s, pódio 6 s | GAME_DESIGN descreve lobby 20 s, contagem 5 s e pódio 15 s |
| Arte | Geometria e caricaturas montadas em GDScript | Não foram encontrados modelos GLB/FBX nem biblioteca de assets Tripo em `game/` |
| Mecânicas | Voto, turbo, escudo, tropeço e pilha de documentos | Likes, shares e duração/intensidade dos presentes divergem do design |
| Painel | Comandos, simulador, WebSocket, fallback HTTP e telemetria | Simulação local também altera números/fases; não usar como prova isolada da corrida real |
| TikTok | Adaptador escrito, import opcional de TikTokLive | Dependência ausente do manifesto; CLI do servidor não inicia o adaptador; live real não testada |
| Kwai | Receptor de webhook local, desativado por padrão | Falta a fonte que capture eventos reais e alimente o webhook |
| Arquitetura | Uma cena principal; montagem procedural em quatro scripts | Resources `.tres`, módulos/autoloads e pooling descritos não estão integralmente materializados |
| Segurança | Bind local, validação de Host/Origin, sanitização, filas limitadas e deduplicação | Token de sessão exigido em SECURITY não é validado pelo servidor atual |

Exemplos verificáveis de divergência: `GAME_DESIGN.md` descreve impulso a cada 50 likes e share com recuperação/cooldown; `live_event_bus.gd` impulsiona os envelopes diretamente. T1 no protocolo dura 3 s; T4 usa +7,5 m/s por 5 s, enquanto o design descreve +8 m/s por 8 s.

O JSON exemplificado em `ARCHITECTURE.md` também é histórico: usa `actor`, `target_candidate_id` e outros nomes; o contrato de execução em `protocol.py` usa `user`, `candidate_slot`, `gift`, `vote`, `like_batch`, `share` e `admin_command`.

## Repositórios e origem

O repositório desta pasta é **local**, na branch `master`, sem commits e sem remotes configurados. Há arquivos já preparados no índice, mas `game/` e `services/` aparecem como não rastreados. Portanto, um commit apenas dos arquivos já staged deixaria o código principal de fora. Não foi encontrado outro `.git` nas partes de produto inspecionadas. A inspeção recursiva encontrou acesso negado em `.pytest_cache`, um cache de testes; não foi necessário acessá-lo para mapear o código.

Não há URL do GitHub do próprio JOGI recuperável pela configuração local. Isso não prova que nunca existiu uma cópia remota em outra conta/pasta.

Repositórios relacionados, com páginas verificadas em 23/10/2026:

| Repositório | Relação com JOGI |
|---|---|
| [godotengine/godot](https://github.com/godotengine/godot) | Motor do jogo |
| [aigengame/godot-agent](https://github.com/aigengame/godot-agent) | GDA usado para validar e executar o projeto |
| [isaackogan/TikTokLive](https://github.com/isaackogan/TikTokLive) | Biblioteca de terceiros referenciada pelo adaptador TikTok; não incluída no manifesto atual |
| [astral-sh/uv](https://github.com/astral-sh/uv) | Gerenciador do ambiente Python previsto nos comandos locais |

Esses projetos não são repositórios do JOGI. A ferramenta Tripo é descrita em `ART_DIRECTION.md`; geração paga e autenticação não foram exercitadas neste levantamento.

## Verificação atual, sem depender do relatório antigo

| Verificação em 23/10/2026 | Resultado |
|---|---|
| Python do ambiente virtual | 3.14.7 |
| GDA | 0.24.1 |
| Godot console | 4.7.2 stable |
| `python -m pytest services/live_bridge -q -p no:cacheprovider` | 27 aprovados em 22,53 s |
| GDA project scan em `game/` | Executado |
| GDA script validate --all | 8/8 válidos; sem diagnósticos |
| GDA scene validate | `valid:true` |
| GDA scene preflight | `started:true`, `status:ready` |
| Testes Godot de corrida, telemetria e protótipo | Três suítes aprovadas em modo strict |
| `test_e2e_runner.py` | Aprovado: conexão local, eventos e telemetria; servidor encerrado ao final |
| Revisão independente | Realizada em leitura; confirmou divergências e pendências |

Não verificado: aparência em janela/browser, 60 FPS renderizados, OBS/transmissão, captura de live real, soak test 24/7, memória após muitas rodadas, segurança completa ou credenciais/configuração de terceiros. Headless aprovado não comprova esses itens.

## Como retomar localmente

Na raiz `C:\Users\Kanex\OneDrive\Desktop\JOGI`, em terminais separados:

```powershell
# Backend e painel: http://127.0.0.1:8765/admin/
.\services\live_bridge\.venv\Scripts\python.exe .\services\live_bridge\server.py

# Jogo; o executável foi localizado e sua versão foi verificada
& 'C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path '.\game'

# Opcional: eventos sintéticos locais
.\services\live_bridge\.venv\Scripts\python.exe .\services\live_bridge\simulator.py --mode normal --count 50
```

Backend e Godot foram exercitados juntos pelo teste E2E; a sequência de abertura visual acima não foi executada nesta etapa.

Ordem proposta para a próxima etapa, ainda sem implementação:
1. Inspecionar visualmente jogo e painel com o simulador.
2. Criar uma base Git completa e revisada, incluindo o código hoje não rastreado.
3. Separar simulação do painel e telemetria real; alinhar contrato e regras escolhidas.
4. Validar repetição automática de rodadas, limites e estabilidade prolongada.
5. Só então conectar uma plataforma real e verificar os eventos efetivamente recebidos.

## Documentação técnica detalhada

- [Stack e comandos](docs/codebase/STACK.md)
- [Estrutura e pontos de entrada](docs/codebase/STRUCTURE.md)
- [Arquitetura e fluxo](docs/codebase/ARCHITECTURE.md)
- [Convenções](docs/codebase/CONVENTIONS.md)
- [Integrações e armazenamento](docs/codebase/INTEGRATIONS.md)
- [Testes e resultados](docs/codebase/TESTING.md)
- [Riscos, divergências e decisões pendentes](docs/codebase/CONCERNS.md)

## Decisão para a continuação

1. [ASK USER] A retomada mantém Lula vs. Bolsonaro como tema, ou a corrida deve receber outro elenco? O mapa preserva o tema encontrado; a resposta só é necessária antes de mudar o produto.

## Evidências principais

`game/project.godot`, `game/scenes/main/race_main.tscn`, `game/scripts/*.gd`, `game/tests/*.gd`, `services/live_bridge/{server,protocol,simulator}.py`, `services/live_bridge/adapters/*.py`, `services/live_bridge/admin/app.js`, `services/live_bridge/pyproject.toml`, `services/live_bridge/uv.lock`, `GAME_DESIGN.md`, `ARCHITECTURE.md`, `SECURITY.md`, `CONTINUIDADE.md`; saídas de Git, pytest e GDA desta execução.
