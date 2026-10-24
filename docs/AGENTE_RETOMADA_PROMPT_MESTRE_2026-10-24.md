# JOGI — PROMPT MESTRE DE RETOMADA, AUDITORIA, REDESIGN E ENTREGA

**Data de preparação:** 24/10/2026 (Brasil)  
**Destinatário:** próximo agente de desenvolvimento no ambiente Windows do usuário (Wordcraft / Antigravity / outro agente habilitado)  
**Projeto:** Corrida dos Candidatos / Corrida Presidencial 3D — JOGI  
**Pasta informada:** `C:\Users\Kanex\OneDrive\Desktop\JOGI`  
**GitHub:** <https://github.com/Kanexxxxx/JOGI>  
**Natureza:** ordem de trabalho; **não é certificado de conclusão nem relatório de testes executados no PC**.

> **INSTRUÇÃO INICIAL AO AGENTE:** Leia este documento inteiro antes de alterar código. O usuário interrompeu outra IA e deseja que você continue o trabalho existente, sem recriar o jogo, sem perder recursos aprovados e sem afirmar que passou em testes que ainda não executou. Não interrompa a missão após produzir um diagnóstico: corrija, implemente, valide, documente e faça commits das entregas viáveis. Quando depender de autorização/acesso externo, registre o bloqueio e prossiga nas demais tarefas locais.

---

## 0. O QUE FOI REALMENTE CONFERIDO ANTES DE ESCREVER ESTE DOCUMENTO

Este prompt foi reconstruído a partir de consulta ao GitHub do usuário, **não apenas da conversa**. A inspeção remota consultou a árvore do commit `9fc7e5a0de01340e59b1719e82ea1794be78a8a2`, além de arquivos reais da arquitetura, Godot, HUD, bridge Python, contratos de eventos, testes, operação e segurança. A árvore retornou **1.611 entradas** (arquivos e diretórios), sem truncamento, incluindo **1.369 blobs** e ampla coleção `.agents/`. Dois commits encontrados na branch `master`:

- `e22a3fa584ccf4375aaf0eeb33c6304fe854d46e` — `chore(checkpoint-ia1): salvar estado base deixado pela IA anterior (24/10 12:50)`.
- `9fc7e5a0de01340e59b1719e82ea1794be78a8a2` — `chore(project): include full game asset set`.

**Não presuma que esse SHA continue sendo o HEAD quando começar.** Execute `git fetch`, confira `git status`, `git log` e os arquivos que o usuário possa ter alterado localmente. O repositório estava **PÚBLICO** na consulta. Não foi possível aqui executar Godot, testes no Windows, OBS ou coleta de eventos reais; essas verificações são responsabilidade do agente com acesso ao PC.

### Descobertas verificadas no código — não repetir o diagnóstico antigo cegamente

1. **Cena ativa:** `game/project.godot` aponta `run/main_scene="res://scenes/main/stadium_race.tscn"`. O projeto tem `game/scripts/stadium_race.gd` e `game/scripts/stadium_hud.gd`, não apenas a arquitetura antiga baseada em `race_main.gd`.
2. **O cache de imagens de presentes JÁ FOI LIGADO AO JOGO:** em `game/scripts/stadium_race.gd` existem `gift_visuals = GiftVisualCache.new()`, conexão de `icon_ready`, `_observe_gift_visual()`, `_refresh_gift_legend()` e chamada `stadium_hud.set_gift_legend(entries)`. Em `game/scripts/stadium_hud.gd`, `set_gift_legend()` substitui ícones vetoriais por texturas. **Não classificar “ligar GiftVisualCache ao StadiumRace” como uma função inexistente.** O trabalho restante é confirmar a qualidade da ponta a ponta com imagens reais, fallback, persistência e comportamento visual.
3. **Meta atual:** `StadiumHUD._build_goal_panel()` constrói **uma meta principal** e exibe `SEGUIDORES +0` como contador separado. `update_live_goal(goal, followers)` é alimentado por `stadium_race.gd`. O backend/painel aceitam meta configurável por tipo (`likes`, `follows`, `gifts`, `coins`, `gift_specific`), mas **não há comprovação de três metas simultâneas independentes com a mesma persistência e apresentação**. Essa é uma mudança de produto a implementar, **mantendo compatibilidade**.
4. **Top 5:** `StadiumHUD._build_audience_panel()` monta linhas textuais e `update_leaderboard()` mostra nome e **moedas** (símbolo de diamante). Não é hoje a coleção de cards com avatares, miniaturas e linhas completas da referência. **Não trocar ranking por quantidade de presentes sem definir a métrica**.
5. **Interações:** `StadiumHUD.show_participation()` mostra uma frase temporária e `_build_chat_panel()` mantém até três linhas textuais; não há evidência de pipeline completo para **foto real de perfil** do espectador no Godot. Em `services/live_bridge/protocol.py`, as chaves de usuário aceitas incluem `user_id` e `display_name`, mas não foi observado `avatar_url` no contrato atual. A captura, sanitização, cache e renderização de avatares exigem implementação completa e segura.
6. **Kwai:** `services/live_bridge/adapters/kwai_adapter.py` é um receptor de webhook local, cuja própria documentação diz não haver coletor autorizado para Kwai Brasil. O bloqueio está documentado em `services/live_bridge/KWAI_EVENTOS_PENDENTES.md`. Não alegar integração real ou contornar proteções de acesso.
7. **TikTok:** adaptador `services/live_bridge/adapters/tiktok_adapter.py` e launcher com escuta pública existem. Os documentos relatam SDK TikTokLive 7.0.1 e testes de integração simulada, **não validação com presente real em sala aberta**.
8. **Sessões isoladas:** `tools/run_live_instances.py` configura TikTok na porta `8765` e Kwai na `8766`, com estados separados; `ABRIR_PREVIA_JOGO.cmd`, `ABRIR_TIKTOK.cmd`, `ABRIR_KWAI.cmd` e `ABRIR_DUAS_LIVES.cmd` já existem. Evitar criar segundo supervisor concorrente sem necessidade.
9. **Ciclo:** `docs/ESTADO_ATUAL.md` descreve 50 rodadas de 600 s, maior distância vence, 30 s de intervalo, reinício de ciclo, checkpoint e outbox com journal. Isso precisa ser retestado após alterações — não reconstruído automaticamente.
10. **Modelos aprovados:** `docs/ESTADO_ATUAL.md` aponta `game/assets/characters/api-cape-v13/{lula_run,flavio_run}.glb`, 65 ossos, capas `cape-motion-v1`, pista cobalto e Planalto local em Blender. **Não regredir para a bancada antiga `preview-v7` nem recriar rostos aprovados.**
11. **Áudio:** fala, efeitos, torcida e memes locais já têm implementação e testes descritos; faltam escuta humana, volume final e captura real. Não gastar créditos com regeneração desnecessária.
12. **Segurança:** há `SECURITY.md`, `.gitignore`, filtro localhost/Origin e validação de downloads de ícones. **Mas existe `LIVE_BRIDGE_LOCAL_TOKEN` em `.env.example` e não foi identificada sua imposição ao procurar o código de `server.py`**. Investigar a divergência entre política e implementação; não chamar a segurança de concluída apenas por existir o documento.
13. **Documentação desatualizada:** `GAME_DESIGN.md`, partes de `DESIGN.md`, `ARCHITECTURE.md`, `TESTING.md` e `MAPA_DO_PROJETO.md` ainda registram fases históricas, 300 s, seis corredores, ou candidatos antigos. **Não usá-los como verdade atual** quando contrariarem documentos recentes e código. Os documentos históricos podem ser preservados/arquivados, com avisos de precedência claros.
14. **Testes relatados não são testes repetidos aqui:** `docs/ESTADO_ATUAL.md` registra 86 testes + 27 subtestes em um checkpoint; relatório posterior da IA anterior informa 101 + 48. A diferença de escopo/época deve ser resolvida rodando as suítes atuais, não escolhendo o número mais favorável.
15. **Pendências de revisão:** `docs/REVISAO_INDEPENDENTE_POLIMENTO_2026-10-24.md` apontou salto lateral de marcações de 50 m e áudio de ultrapassagem obsoleto. Um relatório posterior diz que já foram corrigidos; a implementação atual precisa de **regressões explícitas** para confirmar ambos.

### Ordem de precedência para resolver conflitos

1. **Decisões mais recentes do usuário nesta missão e nas imagens anexas** (ex.: metas simultâneas, 10 mil seguidores, HUD limpo, 2027 visível, nomes sem quebra).
2. **Comportamento atual verificado no código e testes reproduzíveis**, para descrever o que existe.
3. `docs/REVISAO_ESTREIA_24.md`, `docs/ESTADO_ATUAL.md`, `CONTINUIDADE.md`, `INICIAR_JOGO.md`, contratos específicos mais recentes.
4. `BRIEFING_RETOMADA.md` para decisões ainda não substituídas.
5. Demais documentos históricos, com marcação de obsolescência em vez de apagá-los.

> **Correção de prazo:** a revisão de 24/10 substituiu o objetivo anterior de **32 h** por **42 h**. O prazo “24/10 à meia-noite” era uma meta histórica; não transforme essa data em promessa futura automática. Um teste de 10 minutos não certifica 42 horas.

---

## 1. OBJETIVO CENTRAL E NÃO NEGOCIÁVEIS

O projeto é um **jogo 3D de transmissão vertical (9:16) em Godot**, uma corrida satírica Lula **13** versus **Flávio Bolsonaro 22**, em Brasília, em direção ao Palácio do Planalto, controlada de modo indireto por espectadores com comentários, curtidas, seguidores e presentes. O operador supervisiona; a corrida se executa automaticamente. O mesmo código base sustenta **duas sessões independentes** para TikTok e Kwai, com contas, filas, estados, catálogos, logs e painéis separados.

**Conservar:** personagens aprovados, identidade 13/22, animações/rigging existentes, capas verdes/vermelhas, pista cobalto, torcida 3D, câmera atrás dos corredores, Planalto, regras de distância e rodadas, presentes reais sem inflar moedas, reserva de efeitos entre rodadas, retomada pós-crash, áudios e o que já funciona. Não tornar a corrida visualmente vazia na tentativa de reduzir poluição. Não gerar novos rostos, voz política clonada ou recursos pagos sem ordem explícita.

**Entregar:** HUD de aparência profissional e bem menos poluído; metas de curtidas, presentes e seguidores (**10.000** como alvo de seguidores), nomes e cards de interações impecáveis em 9:16, ano 2027 claro, integração sólida de dados, auditoria e correção de segurança, testes e capturas reais das duas instâncias, documentação rastreável e commits bem segmentados. Não publicar live sem autorização explícita.

### Decisões sobre a imagem de referência

A arte conceitual **gerada nesta conversa** deve ser considerada **referência de estilo/composição**, não tela aprovada pixel a pixel, nem screenshot de Godot, nem prova de funcionalidades. Sua composição mostra três metas no topo, placares, 2027 grande, pista/corredores, cards de presentes/comentários e Top 5 com fotos. **Ela também contém exageros e possíveis conflitos com overlays nativos** (cards excessivos e blocos na região inferior); o design final deverá melhorar a própria referência.

**Arquivo fornecido ao agente pelo usuário:** `HUD_CONCEITO_CHATGPT_2026-10-24.png` (anexar/copiar na pasta do projeto, após a configuração da referência; se ainda ausente, informar isso como dependência e usar a especificação abaixo). O agente deverá versioná-la em `docs/referencias/hud-conceito-chatgpt-2026-10-24.png`, acompanhada de `docs/referencias/HUD_REFERENCIA.md`, e atualizar links nos documentos. **Não substitua imagens do jogo ou ativos produzidos pela IA anterior.**

Preferir PNG de referência em resolução original, não uma versão artificialmente reduzida. Se houver limites Git de tamanho, tratar corretamente Git LFS conforme `.gitattributes`; não subir base64 bruto em Markdown. Caso a imagem já esteja no repositório, reutilizar e não duplicar.

---

## 2. FASE ZERO — AUDITORIA NÃO DESTRUTIVA DO CHECKPOINT E PROTEÇÃO DO HISTÓRICO

Execute antes da primeira alteração:

```powershell
Set-Location 'C:\Users\Kanex\OneDrive\Desktop\JOGI'
git status --short --branch
git remote -v
git branch -avv
git log --oneline --decorate -12
git diff --stat
git diff --cached --stat
git lfs ls-files
```

1. Confirme a branch real (`master` no estado consultado), upstream e SHA. **Nunca assuma `main`** por padrão.
2. Confirme a diferença entre o conteúdo local e o remoto. Faça `git fetch` antes de decidir usar `pull`; não sobrescreva modificações sem commit, não dê `reset --hard` e não aplique `push --force`.
3. Gere inventário de pastas/arquivos sem abrir/cachear mídia paga ou modificar binários. Verifique arquivos grandes, `.gitattributes`, Git LFS e dependências dos `.glb`/texturas; a primeira imagem/conjunto de assets pode não ter sido enviado integralmente apenas por causa do commit.
4. Compare o checkpoint inicial `e22a3fa` com o commit de assets `9fc7e5a`, e com qualquer HEAD mais novo. Marque quais alterações pertencem a qual fase/IA, sem atribuir autoria indevida.
5. Antes de commits, faça **varredura de segredos** na árvore atual **e, quando viável, no histórico remoto** (arquivos `.json`, `.md`, logs, dumps de API, traces, cabeçalhos, URLs assinadas, configs, metadata e mídia). Não imprima valores de segredos no relatório. Se houver exposição, interrompa novo compartilhamento desse material e documente remediação/rotação. Como o repositório é público, trate material já publicado como potencialmente divulgado.
6. Certifique-se de que `LOCALAPPDATA/JOGI/live_bridge/{tiktok,kwai}` e backups/SQLite reais permaneçam fora do repo/OneDrive. Não copie contas/sessões/arquivos de autenticação para o GitHub.
7. Verifique se o usuário já está executando o jogo, bridge, supervisor, Godot headless, OBS ou TikTok LIVE Studio; não mate processo não pertencente ao teste sem inspecionar o PID e obter razão técnica. Preserve janela ativa quando possível.
8. Crie **registro de baseline**, preferencialmente um commit separado para documentação/testes; não faça commit fictício se a árvore já estiver limpa.

**Artefatos:** `docs/auditorias/AUDITORIA_RETOMADA_<data>.md`, tabela de evidências, mapa de dependências e classificação `EXISTE/VALIDADO/NÃO TESTADO/PARCIAL/BLOQUEADO/REGRESSÃO`. Não trocar “existe no repo” por “funciona em live”.

---

## 3. FASE 1 — VALIDAÇÃO DA ARQUITETURA E DO PRODUTO REAL

### 3.1 Componentes a estudar primeiro

| Área | Código/diretório | Responsabilidade / verificação |
|---|---|---|
| Jogo principal | `game/project.godot`, `game/scenes/main/stadium_race.tscn`, `game/scripts/stadium_race.gd` | cena ativa, estados, câmera, eventos, montagem de HUD, regras |
| HUD | `game/scripts/stadium_hud.gd` | posicionamento, metas, ranking, textos, overlays, legendas |
| Público | `game/scripts/audience_director.gd` | rankings, métricas, participantes, neutralidade, dedup |
| Eventos Godot | `game/scripts/live_event_bus.gd` | WS, validação, ACK, identificação, sanitização |
| Imagens | `game/scripts/gift_visual_cache.gd`, `services/live_bridge/gift_images.py` | miniaturas seguras, cache, fallback, limites |
| Mundo e personagens | `stadium_world.gd`, `candidate_presentation.gd`, `candidate_cape_motion.gd`, assets Planalto/rigs | posição, 2027, visibilidade, desempenho |
| Persistência | `race_persistence.gd`, `race_session_store.gd`, `outbox.py` | checkpoint, replay, ACK, reserva de presentes |
| Backend | `services/live_bridge/server.py`, `protocol.py`, `live_goal.py`, `gift_catalog.py` | metadados e contrato de eventos/metas |
| TikTok | `services/live_bridge/adapters/tiktok_adapter.py` | SDK, conta, combos, limites, follow |
| Kwai | `services/live_bridge/adapters/kwai_adapter.py`, `KWAI_EVENTOS_PENDENTES.md` | webhook passivo e dependência de fonte autorizada |
| Painel | `services/live_bridge/admin/{index.html,app.js,styles.css}` | controle, metas, saúde, telemetria e responsividade |
| Launchers | `tools/run_live_instances.py`, `tools/live_supervisor.py`, `ABRIR_*.cmd` | prévia, duas janelas, isolamento, processos |
| Testes | `game/tests/`, `services/live_bridge/test_*.py`, `tools/test_*.py` | regressões reais |
| Skills e agentes | `.agents/agents/`, `.agents/skills/`, `AGENTS.md` | execução especializada, revisões independentes |

### 3.2 Regras a preservar, mas verificar

- 50 rodadas por ciclo, 600 segundos cada, vitória pela maior distância, sem corrida até linha fixa.
- Intervalo total de 30 s: chegada 3 s, pódio 24 s, contagem 3 s, conforme relatório recente.
- Reinício após a rodada 50 para novo ciclo, mantendo integridade da deduplicação e do histórico.
- Placar acompanha líder real; identidade completa 13/22 move como unidade.
- Efeitos pagos no pódio somam no ranking imediatamente, mas o efeito mecânico é aplicado na largada seguinte.
- Presente sem equipe escolhida é neutro: não atribuir ao 13 nem ao 22 por padrão.
- Valor em moedas reportado pela plataforma não é valor em reais, nem estimativa financeira.
- Pacotes de combo TikTok vêm com **delta de `repeat_count`**, e o envelope contém `coin_value` total do delta. **Não multiplicar outra vez**.
- Falha/replay de entrega é ao menos uma vez + dedup/checkpoint, não prometida exatamente uma vez.

### 3.3 Áudio e renderização

Inspecione `RaceAudio`, `RaceAmbience`, `RaceSoundEffects`, `RaceMemeBoard`, fontes locais Nunito, shaders e modelos. Confirme os arquivos efetivamente presentes e resolvidos pelo Godot. Não regenerar modelos de 65 ossos ou falas para corrigir falha simples de HUD. Verifique posições de sombra, marcadores de 50 m, falas de ultrapassagem, blend de capas, queda, festa, entrada da próxima rodada, áudio congelado na pausa e liberação de nós.

---

## 4. FASE 2 — NOVO HUD: MENOS POLUIÇÃO, MAIS LEITURA

**Objetivo visual:** estética de transmissão esportiva 3D profissional, limpa, brasileira e divertida. Pista cobalto, personagens atuais e Planalto são os protagonistas. A imagem de referência sugere a hierarquia, mas os painéis não podem dominar a cena. Trabalhe com um **sistema de layout** de Godot, não uma nova lista de `Rect2` fixos espalhados.

### 4.1 Regras de composição

1. Especificar e validar zonas seguras **por plataforma**. O `DESIGN.md` antigo bloqueia topo `0–260 px` e recomenda nenhuma UI em `1340–1920 px` por causa dos controles nativos da live; a captura atual e a imagem conceitual divergem. Teste com sobreposições reais/simuladas dos apps TikTok e Kwai, inclusive nomes da live, chat, barra de presentes, botão seguir, reações e controles. **Não copiar as três metas no topo cegamente se elas ficarem cobertas no app**.
2. Cena principal deve permanecer dominante — alvo inicial aproximado de 55–65% da altura disponível **não é uma regra rígida**; vale legibilidade e ausência de bloqueio da ação.
3. Agrupar informação por função: metas / título & tempo / classificação dos candidatos / aviso contextual / corrida 3D / social & ranking / habilidades; sempre respeitando safe areas.
4. Reduzir brilho, bordas pesadas, sombras duplicadas e saturação das arquibancadas; o visual deve melhorar em celular comprimido, não apenas no monitor em 1080p.
5. Usar containers, âncoras, limites de largura, padding consistente, centralização, fontes Nunito existentes, `clip_text`, medidas por fontes e layouts testáveis. Corrigir jitter de números com fontes tabulares/alinhamento fixo. Não interpolar nome do usuário em BBCode.
6. Sinalização clara do estado TESTE LOCAL / SIMULADOR / TIKTOK / KWAI, sem divulgar identidade de sessão/credenciais do operador.

### 4.2 Três metas simultâneas (mudança real de modelo de dados)

Precisamos de **três metas independentes e visíveis**: curtidas, presentes e seguidores, com estados e progressos próprios. O sistema atual tem **uma** meta ativa `set_live_goal` mais `SEGUIDORES +N`; proponha extensão retrocompatível, sem corromper `live_goal.json`, checkpoints ou clientes existentes.

- **Curtidas:** alvo inicial ilustrativo 1.000; progresso conforme eventos reais da sessão, sem inventar contagem global do perfil.
- **Presentes:** meta configurável por unidades de presentes, ou **presente específico por ID** (`gift_specific`) quando selecionado. Exemplo visual 500 é **fictício**, não aprovado como meta definitiva. Distinguir `gifts` (unidades) e `coins` (valor de moedas), não trocar sem aviso.
- **Seguidores:** **10.000 seguidores** é o objetivo informado pelo usuário. Diferenciar: `follows durante a live` x `total de seguidores do perfil`. Se a API não disponibiliza total verificado, **não mostrar “0/10.000” como total real**. Exibir `SEGUIDORES · META 10K · total indisponível` ou progresso da sessão com legenda explícita; permitir baseline manual apenas se rotulado, datado e auditável. Sem API/consentimento, não fazer scraping de seguidores.
- Painel admin deve configurar cada meta separadamente, com validação de limites, plataforma, persistência versionada e estado `configurado/aplicado/aguardando dados`. O comando legado `set_live_goal` deve seguir funcionando ou ser migrado com testes, sem retorno silencioso falso.
- Layout alternativo se três cards simultâneos ficarem pequenos: barra horizontal fina de 3 segmentos, duas linhas compactas ou metas rotativas com indicadores fixos. **As três informações devem continuar localizáveis e não confundidas**.
- Progresso em `pt-BR`: separador de milhar correto, números grandes e percentuais limitados visualmente, sem truncar o valor persistido.

### 4.3 Placar e cronômetro

- Dois cards compactos com avatar/retrato correto, número (`13` / `22`), nome, equipe, metros, km/h, posição e progresso. Garantir que reordenação preserve os atributos completos da equipe.
- Evitar fontes minúsculas, retratos esmagados, números que mudam a largura do card ou título longo que invade o cronômetro.
- Cronômetro grande e legível; `RODADA 01/50`, ciclo e vitórias secundários, mas visíveis.
- Checagem de empate, troca de líder, estado de pódio, pausa, cooldown das falas, velocidade e distância extremas.
- Não usar retratos genéricos diferentes dos modelos aprovados sem revisão do usuário.

### 4.4 Planalto e “2027”

Na prévia do usuário, o ano `2027` é difícil de enxergar. **A decisão mais recente é torná-lo claramente legível**, corrigindo a indicação antiga de “2027 discreto”. Use tipografia/placa com contraste e escala moderados, sem virar outdoor gigante nem encobrir arquitetura. Evite excesso de placas `BRASIL`, refletores e faixas que briguem com o Planalto. Testar dia/noite, zoom, enquadramento, compressão e câmera de chegada. Preservar modelo atual v2 e escadaria/acessos adequados, salvo correção técnica pontual.

### 4.5 Interações e cards com perfis reais

Design desejado: entrada discreta por 2–4 s, pequeno avatar circular, `@usuário`, ação (`comentou 13`, `mandou Rosa ×3`, `começou a seguir`), miniatura de presente se disponível e chip da equipe **apenas quando houver escolha real**. **Não atribuir time a follow/gift neutro.** Mostrar um ou dois cards prioritários por vez; não abrir uma coluna com cinco cards permanentemente sobre os corredores.

O contrato atual aceita `user_id/display_name` no usuário e imagens de **presentes**, mas não o pipeline de avatares; necessário:

1. Verificar se SDK/coletor permitido fornece avatar (URL oficial e fallback). Propor campo opcional `avatar_url` ou identificador opaco de asset, sem afetar `schema_version=1.0` ou validadores atuais. Se a mudança for incompatível, versionar o schema e suportar consumidor antigo.
2. Sanitizar avatar como **input externo**: lista de hosts de CDNs oficialmente verificados, HTTPS, sem credenciais/fragmentos, DNS/IP público anti-SSRF, sem redirects inseguros, timeout, limite de pixels/bytes, MIME validado, sem cookies, cache local com teto e limpeza/TTL. O Godot baixa apenas URL relativa do **bridge local**, nunca endereço arbitrário vindo do comentário.
3. Respeitar privacidade: armazenar o mínimo necessário, documentar retenção de fotos/IDs, evitar persistir fotos pessoais em Git, logs e checkpoints indefinidamente; opção de desabilitar avatares e fallback consistente.
4. Não carregar imagens na thread de renderização de forma bloqueante; cache + fila limitada + cancelamento na troca de rodada/sessão.
5. Nome mostrado em **UMA LINHA** com truncamento por largura visual e reticências, mantendo UTF-8 e grapheme clusters (emojis combinados, acentos), sem cortar caracteres no meio. `display_name` não deve ser usado como chave exclusiva; a identidade é `source + user_id`.
6. Testar inclusive nomes sem `@`, nomes muito longos, emojis e zero-width, `×1`, `×10`, `×999`, `×10.000`, foto vazia, foto quebrada, recibo duplicado, usuário da plataforma correta e mais de 50 eventos/s.
7. **Não criar relatos fictícios de espectadores na versão de transmissão.** Use dados simulados com status `SIMULAÇÃO` apenas em bancadas/testes explícitos. A prévia pode ter eventos de demonstração opt-in, mas nunca indistinguíveis de interações reais.

### 4.6 Ranking Top 5 (sem mentir sobre a métrica)

- Hoje o Top 5 mostra **moedas**. Permitir exibição compacta de avatares e nomes, mas preservar o ranking financeiro já implementado até decisão documentada. Rotular `TOP 5 · MOEDAS` ou `TOP 5 · PRESENTEADORES (MOEDAS)` quando usar `coins`; se também mostrar quantidade de presentes, indicar a unidade separadamente.
- Formato mínimo por linha: posição, avatar opcional, nome com reticências, número com unidade e identificação da equipe se houver. Top 3 do pódio continua seguindo contrato existente.
- Estados vazios compactos e legíveis; evitar painel grande com cinco travessões permanentes. A visualização pode reduzir altura quando vazia, mostrar apenas Top 3 + expansão em contexto, desde que não perca funcionalidades importantes.
- Testar duas pessoas com mesmo `display_name`, mudança de nick, moedas empatadas, neutros, erros de carga e reconexão. Não usar imagens aleatórias nem avatares artificiais para espectadores reais.

### 4.7 Faixa de habilidades / presentes

As quatro habilidades `IMPULSO`, `ESCUDO`, `ATAQUE`, `SUPER TURBO` já existem. A integração de **ícones de presente observado** com a legenda existe no código; agora testar de ponta a ponta:

- payload real/simulado com `gift_id`, `gift_image_url`, `gift_icon_path`;
- primeiro download, cache quente/frio, 404 temporário, falha HTTPS, reconexão, duas plataformas com mesmo ID;
- imagem proporcional, sem bordas/estouro, legenda de ação correta, fallback vetorial explícito quando não observado;
- vários presentes da mesma categoria e mudanças de override: **não usar miniatura errada ao promover/substituir o presente anterior**;
- não bloquear ACK de presente pago por falha de imagem;
- descrição de ação em português e ligação clara entre presente e efeito; sem prometer que envio gera benefício real fora do jogo.

### 4.8 Testes visuais obrigatórios

Testar viewport do Godot em **1080×1920, 720×1280, 540×960 e 360×640** (quando aplicável à renderização/captura), e painel admin em **375/390, 768 e 1440 px**. Capturas **reais da cena**, não mockups, nas situações: vazio; dois candidatos empatados; ultrapassagem; topo 5 preenchido; nome/emoji extremos; combo grande; meta de 10k; falta de avatar; efeitos e pódio; noite e dia; duas plataformas. Verificar margens seguras com overlays aproximados de TikTok/Kwai e texto legível após downscale/compressão para tela de celular. Iterar até não haver clipping, flicker, overlap, invasão dos corredores ou valores ambíguos.

---

## 5. FASE 3 — SEGURANÇA, CONFIABILIDADE E CONTROLE LOCAL

**Não apagar o sistema existente de segurança; testar suas garantias reais.**

- Auditar rotas HTTP/WS `/ws/godot`, `/ws/ingest`, `/ws/admin`, `/api/admin`, `/health`, `/gift-icons/<hash>`; conferir bind loopback, Host, Origin, headers, WebSocket, CSRF/CSWSH, limites de corpo, autenticação e permissões. O `.env.example` menciona `LIVE_BRIDGE_LOCAL_TOKEN`; determinar se o **token de sessão é implementado**. Se não for, documentar e implementar mecanismo de autenticação local compatível, sem deixar segredo embutido no cliente web ou comprometimento pela interface. Respeitar a realidade do host local e a necessidade de integração Godot.
- Validar fluxos administrativos: dados da live jamais podem se passar por `admin`; impedir falsificação de `source`, `event_id`, comandos de reinício e ações pagas; testes negativos.
- Verificar proteção SSRF no cache atual de miniaturas de presentes (`gift_images.py`), inclusive **DNS rebinding e IP de conexão**, redirects, decompression bombs, MIME spoof, tamanho, cache key, vazamento de URLs assinadas, falhas 404 e recursos de rede. Propor mesma política para avatares.
- Revisar persistência de IDs, nomes e caches; exclusão/TTL adequados, integridade do arquivo SQLite e journal, permissões locais, checkpoint versionado, restauração a partir de backup e logs sem dados sensíveis.
- Testar ACK, replay, deduplicação após restart, overflows e prioridades (P0 presentes versus P1/P2). Não perder contagem de moedas ao aplicar limites mecânicos de turbo/ataque, nem duplicar combos.
- Dependências Python `uv.lock`, SDK TikTokLive opcional, versões Godot/Blender e licenças de modelos/fotos/áudios/fontes. Dependência desatualizada deve ser avaliada com testes, não atualizada às cegas em produção.
- Tornar visíveis os estados de conexão no admin: `connected`, `waiting_room`, `reconnecting`, `account_not_found`, `kwai_requires_collector`, e **telemetria obsoleta**, sem apresentar dados antigos como atividade ao vivo.
- Repositório público: varredura antes de cada push, proteção de segredos em Git, sem credenciais em histórico, sem chaves de stream, cookies, `.env`, contas locais, dumps não sanitizados ou endpoints assinados. Se um segredo já foi publicado, alertar para rotação — reescrever Git sozinho não revoga credencial vazada.
- Remover ou corrigir referências documentais perigosas e caminhos locais `file:///...` nos README principais quando deveriam ser links relativos. Preservar contratos históricos e decisões de arquitetura.

---

## 6. FASE 4 — CONEXÕES TIKTOK E KWAI

### TikTok

- Validar o `TikTokLiveAdapter` existente (o launcher já pode chamar `--listen-live`), conta/porta configuradas e estado de conexão. Verificar permissões/funcionamento da versão SDK instalada antes de mudar.
- Testes simulados de `13` / `22`, likes, follow, share, presentes, gift ID/preço unitário, streaks/deltas, participantes sem time e reconexão; depois teste com **sala real e eventos autorizados**, diferenciando resultados. Não gerar compra/presente real automaticamente nem transmitir sem autorização.
- Se a API não disponibilizar total de seguidores, a meta 10k não poderá fingir ter sido validada. Acompanhar follows recebidos durante a sessão separadamente.

### Kwai

**Bloqueio documentado, não trabalho trivial:** não existe coletor real comprovado no projeto para Kwai Brasil. O webhook `127.0.0.1:8786/webhook/kwai` **não é um coletor**; callbacks externos HTTPS não alcançam loopback por mágica. Primeiro avalie caminhos oficiais, parceiro/integrador autorizado e compatibilidade regional. Uma API do Kuaishou SmallPlay não prova por si só acesso ao Kwai Brasil. Não pedir cookies de sessão, não criar bypass de autenticação, não forçar automação via scraping restrito.

- Se coletor autorizado existir, implemente produtor autenticado com assinatura/identificadores estáveis, replays seguros, métricas de health, mapeamento unitário de moedas/deltas, identidades e imagens; teste em sala real quando houver permissão.
- Se não existir, mantenha o bridge Kwai funcional em simulação/manual, identifique `kwai_requires_collector`, documente exatamente a dependência e evite descrever a automação como concluída. A live pode renderizar o jogo, mas interações automáticas permanecem bloqueadas.
- Não aceitar qualquer POST local indiscriminadamente como presente pago. Adicionar autenticação/mecanismo de confiança do produtor, validação de origem e proteção contra replay apropriados à arquitetura.

### Isolamento

Dois jogos e pontes **com ports 8765/8766** e `LIVE_PLATFORM/LIVE_BRIDGE_WS_URL` próprios; bancos, imagens, metas, logs, ranking e caches separados; falha Kwai não derruba TikTok. Teste `--both --check`, `--both --offline`, e inicializações individuais; não confundir um usuário TikTok com igual `user_id` no Kwai. Consolide métricas operacionais sem compartilhar dados entre plataformas.

---

## 7. FASE 5 — PERFIS ADMINISTRATIVOS, ACESSIBILIDADE E OPERAÇÃO

- Auditoria do painel web atual (`services/live_bridge/admin`), sem recriá-lo em React: o projeto usa **HTML/CSS/JS sem build pesado**, Playwright para QA. Aproveitar `index.html`, `app.js`, `styles.css` e contratos existentes; corrigir responsividade, `aria`, foco, estados de botões, erro/timeout, prevenção de cliques duplicados, validação de input, segurança XSS.
- Adicionar gestão das três metas por plataforma com unidades, baseline, fontes dos dados e estado de aplicação.
- Criar telas de diagnóstico de cache/miniaturas, presença de coletor, lag de telemetria, filas, ACKs pendentes, último restart, supervisão e status OBS quando mensurável; **não apresentar métricas sem fonte**.
- Comandos de simulação devem permanecer visivelmente rotulados `TESTE` e **jamais disparar ações na plataforma**. Reinício deve exigir confirmação. Encerramento pode preservar a instância do outro serviço.
- Documentar operador: prévia local, TikTok, Kwai, duas instâncias, gravação, pausa, emergência e recuperação. Não alterar perfis/configurações OBS preexistentes sem backup/autorização.

---

## 8. FASE 6 — TESTES REPRODUZÍVEIS E DESEMPENHO DO PC

Antes de começar: faça backup do estado relevante e descubra o executável real do Godot; `AGENTS.md` menciona GDA `C:\Users\Kanex\.local\bin\gda.exe` e `INICIAR_JOGO.md` Godot 4.7.2 dentro de `Downloads`. **Verifique caminho e versão real**, não presuma que estão instalados idênticos. O projeto Godot está em `game/`, não na raiz para comandos `--project`.

### Comandos de partida sugeridos (adaptar aos binários disponíveis)

```powershell
# Na raiz do repositório:
& 'C:\Users\Kanex\.local\bin\gda.exe' project scan --project game --json
& 'C:\Users\Kanex\.local\bin\gda.exe' scene validate res://scenes/main/stadium_race.tscn --project game --json
& 'C:\Users\Kanex\.local\bin\gda.exe' scene preflight res://scenes/main/stadium_race.tscn --project game --json

# Usar interpretador do uv/venv existente; não pip global:
& 'services\live_bridge\.venv\Scripts\python.exe' -m pytest services/live_bridge -q -p no:cacheprovider
& 'services\live_bridge\.venv\Scripts\python.exe' tools/run_live_instances.py --both --check
```

- Faça suíte Godot focada e ampliada: `test_stadium_hud.gd`, `test_rounded_hud.gd`, `test_stadium_integration.gd`, `test_gift_visual_cache.gd`, `test_audience_director.gd`, `test_round_cycle.gd`, `test_paid_round_boundary.gd`, `test_race_persistence.gd`, `test_live_bridge_e2e.gd`, áudio e arte. Use GDA com `--strict` quando aplicável, relatando warnings e exit status.
- Adicione testes de **três metas simultâneas**, migração e persistência de configurações, nomes truncados Unicode, gráficos de perfil, avatares maliciosos, 404/bad MIME do cache, textos longos e metas com valores elevados.
- Teste os dois P2 da revisão independente (marcação 50 m mantendo lateral coerente; narração antiga cancelada em trocas rápidas), inclusive se o código parecer já corrigido.
- Controle de memória: objetos órfãos após testes (`OBJECT_ORPHAN_NODE_COUNT`), recursos de cache, timers/tweens, liberação de PNGs/texturas e desconexões; registrar diferenças entre testes headless e janela real. Não declarar `0 warnings` caso haja avisos intermitentes.
- **Benchmarks simultâneos obrigatórios:** duas instâncias em **1080×1920** durante **10 minutos contínuos reais**, mais codificação/gravação curta pelo OBS ou captura real configurada. Medir FPS médio/p1/p95 de frame time, CPU, GPU, uso de VRAM/RAM por processo, spool SQLite, filas, jitter, áudio, tempo de carregamento, quadro perdido e logs; separar carga do encode da carga do jogo.
- Hardware histórico documentado: Ryzen 7 5700X, RTX 4060, aproximadamente 16 GB RAM. **Confirme no PC**, não use a especificação como evidência de desempenho.
- Testes de falha isolada: desconexão TikTok/Kwai, matar um processo sob controle e retomar, bridge sem Godot, pendências em outbox, disco quase cheio, perda/reconexão de rede, dezenas de presentes, neutralidade, perfis longos, pódio/rodada 50/ciclo seguinte.
- **42 horas:** tratar como objetivo operacional de soak test futuro. Teste 10 minutos é porta inicial, **não certificação de estabilidade por 42 h**. Se não conseguir testar por 42 horas nesta sessão, documentar risco residual e critério/roteiro completo de validação posterior.
- Tirar screenshots reais do Godot em TikTok e Kwai, com marcas de TESTE/REAL claras. Capturar áudio de ~30 s sem iniciar live; comparar imagem real com o conceito, iterar e anexar evidências. **Não afirmar que janela está aberta na tela do usuário se não verificou o processo/janela.**

---

## 9. FASE 7 — PADRÃO DE COMMIT E TRANSFERÊNCIA ENTRE AGENTES

### Git

1. `git fetch`/`git status` antes de cada fase. **Branch corrente `master` na inspeção**, mas confirme. Se outro agente trabalhar simultaneamente, criar branch de trabalho ou usar commits pequenos; não pisar no trabalho alheio.
2. Commits independentes, revisáveis e completos, por tema: `docs: documenta auditoria e checkpoint`; `feat(hud): ...`; `feat(goals): ...`; `feat(audience): ...`; `fix(security): ...`; `test(...): ...`; `docs(handoff): ...`.
3. Cada commit precisa de teste adequado e descrição de mudança real. Não fazer commit de binários gerados/cache sem necessidade nem usar `git add .` sem revisar `git status`/`git diff --cached`.
4. Conferir que nenhuma chave/URL assinada/sessão entrou no staged. Nunca subir `.env`, `.db`, `.sqlite`, cookies, perfis OBS, tokens de live, segredos Tripo/ElevenLabs, arquivos de login, logs com PII ou memória temporal do agent.
5. `git pull --rebase` só quando seguro, sem mudanças não preservadas; conflitos devem ser resolvidos, não descartados. `push` para remote correto; se remoto estiver à frente, fetch/rebase/merge preservando commits. **Nunca force push** sem ordem explícita e revisão.
6. Revalidar URLs da imagem e docs no repo após push; diferenciar `commit local` de `push concluído` com hash no remoto.

### Documentação de continuidade (obrigatória, sempre atualizada)

Mantenha `CONTINUIDADE.md` e `docs/ESTADO_ATUAL.md` como verdade viva. Crie ou atualize:

- `docs/AGENT_HANDOFF.md`: tabela cronológica de sessões de agentes (identificador, início/fim, commit base/final, arquivos/funcionalidades, limitações, próximo passo exato, testes com outputs e links).
- `docs/CHECKLIST_ENTREGA.md`: `VALIDADO / IMPLEMENTADO, NÃO VALIDADO / PENDENTE / BLOQUEADO / REGRESSÃO` com IDs de evidência, sem percentuais arbitrários.
- `docs/auditorias/AUDITORIA_RETOMADA_<data>.md`: escopo, fontes, testes, achados P0–P3 e riscos.
- `docs/referencias/HUD_REFERENCIA.md`: link para PNG versionado e regras de interpretação (conceitual, não captura real); layout e restrições de overlay.
- `docs/TESTES_FINAIS.md`: comandos, ambiente, versões, hardware, hashes, duração, resultado real, prints/logs sanitizados e falhas.

**Não criar outro `CONTINUIDADE_IA.md` concorrente se `CONTINUIDADE.md` já é a fonte oficial.** Se o usuário exigir tal nome, fazer arquivo curto apontando para a fonte real, evitando divergência. Um futuro agente deve começar pela sequência `AGENTS.md` → `CONTINUIDADE.md` → `docs/ESTADO_ATUAL.md` → `docs/AGENT_HANDOFF.md` → `docs/REVISAO_ESTREIA_24.md` → testes/código.

### Modelo de entrada em AGENT_HANDOFF.md

```md
## 2026-10-24 — agente [identificador] — [sessão]
- Recebido em: master@<sha>
- Entregue em: master@<sha>; push: [sim/não]
- Objetivo da sessão: ...
- Alterações verificáveis: `path:linhas`, resumo de cada mudança
- Testes: comando, exit code, resultado, ambiente, capturas/logs
- Segurança: varredura e pendências sem expor dados
- Decisões: alternativas consideradas e motivo da escolha
- Pendente/Bloqueado: ...
- Próxima ação exata: abrir `<arquivo>`, alterar `<função>`, verificar `<teste>`
- Estado das janelas/processos: PIDs confirmados, portas, comandos de parada
```

O agente atual não deve reivindicar trabalho que foi executado pela IA anterior. Registrar as diferenças em relação a `e22a3fa`/`9fc7e5a` e a commits intermediários.

---

## 10. AGENTES/SKILLS — USAR QUANDO REALMENTE ÚTEIS

O repositório já tem `.agents/agents/` e `.agents/skills/`. Não duplique ou reinvente sua equipe. Consulte `AGENTS.md` e selecione responsabilidades concretas:

- `tech-lead`: arquitetura, precedência de contratos, compatibilidade da meta múltipla, migração;
- `godot-engineer`: HUD, layout, cena, câmera, sinais, cache;
- `game-designer`: regras dos efeitos, ranking e metas; neutralidade de torcida;
- `3d-art-director`: legibilidade do Planalto e dos personagens, iluminação e 2027;
- `live-integration-engineer`: TikTok/Kwai, contrato avatar, segurança de ingesta;
- `qa-engineer`: testes de regressão, Playwright, captura real, benchmark;
- `security-reviewer` e `independent-reviewer`: revisão **somente leitura** antes de merges/entregas.

Skills locais relevantes: `gda`, `godot-gdscript`, `godot-ui-control`, `godot-performance-optimization`, `godot-debugging-profiling`, `godot-testing-patterns`, `web-design-guidelines`, `design-taste-frontend`, `delivery-gate`, `production-audit`, `git-workflow`, `error-handling`, `playwright-cli`. Só execute ferramentas disponíveis e verificadas; não afirme possuir capacidades que não tem. Não gaste créditos de Tripo/ElevenLabs sem confirmação e estimativa prévia.

---

## 11. DEFINITION OF DONE — CRITÉRIOS DE ACEITE CONCRETOS

Marque `PRONTO` **somente se houver evidência** de todos os itens pertinentes:

- [ ] Cena `stadium_race.tscn` roda em Godot instalado, sem erros críticos, e identidade Lula 13 / Flávio 22 preservada.
- [ ] HUD novo integrado ao Godot (não apenas mockup HTML), com legibilidade e safe areas verificadas TikTok/Kwai.
- [ ] Três metas independentes (curtidas, presentes, seguidores 10k) exibem **valor e fonte honestos** e persistem corretamente por plataforma.
- [ ] Fotos de perfil verdadeiras somente quando permitidas/disponíveis, com fallback, privacidade, cache e segurança anti-SSRF.
- [ ] Nomes e valores **não quebram uma segunda linha** nem invadem cards, inclusive Unicode e `×10.000`.
- [ ] Top 5 com métrica claramente rotulada, neutralidade e identidade estáveis, Top 3 do pódio mantido.
- [ ] `GiftVisualCache` existente validado com presente real/observado e fallback, sem impacto na entrega/ACK.
- [ ] Palácio do Planalto/`2027` legíveis e corredor/torcida no centro da atenção.
- [ ] Dois bugs P2 antigos têm regressões específicas aprovadas.
- [ ] Ciclo de 50×600 s e transição de 30 s preservados; presentes de pódio não recontados.
- [ ] Auditoria de segurança final (incluindo token local, validação, cache, dependências e segredos públicos) sem P0/P1 abertos.
- [ ] TikTok: distinguir simulador de validação **real** com comentários/presentes em sala.
- [ ] Kwai: identificar de forma honesta `REAL VALIDADO` ou `BLOQUEADO POR COLETOR NÃO AUTORIZADO`; não maquiar.
- [ ] Painel admin responsivo, seguro, testado em 375/768/1440 e com controles operacionais.
- [ ] Duas instâncias 1080×1920 por pelo menos 10 min com métricas reais; OBS/gravação curta também medidos.
- [ ] Testes Godot, pytest e Playwright repetidos, versões/hash/logs registrados.
- [ ] Referência de imagem no repo e seu caráter conceitual documentado; capturas reais de antes/depois anexadas.
- [ ] Git limpo, commits atribuíveis, push remoto verificado, documentos de handoff atualizados.
- [ ] Nenhuma transmissão pública iniciada e nenhuma compra/geração paga não autorizada.

**Se não completar todos:** entregue o máximo seguro e viável, registre o estado exato, os bloqueios e os próximos passos, sem usar “100% concluído” falsamente.

---

## 12. RELATÓRIO FINAL QUE O USUÁRIO DEVE RECEBER

A resposta final deve ser compreensível, estruturada e baseada no **que de fato rodou no PC**:

1. **Estado inicial e final:** SHA recebido, SHA entregue, branch, push, diferença por funcionalidade/arquivo.
2. **O que já estava pronto** e foi preservado.
3. **O que você criou/corrigiu**, sem reivindicar mérito do outro agente.
4. **Antes × depois visual:** imagens reais do Godot comparadas à referência (referência não é prova da implementação).
5. **Segurança:** problemas encontrados, correções, riscos residuais sem expor segredo.
6. **TikTok / Kwai:** cada estado verificado (simulador, collector real, conectado, bloqueado, etc.).
7. **Testes:** comandos, versões, resultados, avisos e limites.
8. **Desempenho das duas janelas:** FPS, frametime p95, CPU/GPU/RAM/VRAM, estabilidade, áudio e captura OBS.
9. **Pontos positivos e negativos**, riscos P0–P3 e prioridades de melhoria.
10. **Handoff:** link do documento, hash do último commit, comando de inicialização, processos/janelas que permanecem abertos e próximo passo exato para a IA seguinte.

### Comandos de operação já presentes (verificar antes de executar)

```powershell
.\ABRIR_PREVIA_JOGO.cmd
.\ABRIR_TIKTOK.cmd
.\ABRIR_KWAI.cmd
.\ABRIR_DUAS_LIVES.cmd
# Alternativa planejada de teste, sem publicar lives:
& 'services\live_bridge\.venv\Scripts\python.exe' tools\run_live_instances.py --both --offline
```

**Ao concluir as tarefas locais**, deixar visíveis as duas janelas TikTok/Kwai para inspeção do usuário, **se a sessão tiver controle autorizado da máquina**, identificando visualmente os estados simulados. Caso controle gráfico não esteja disponível, informe o limite e entregue capturas/comandos reproduzíveis, não invente PID ou janela.

---

## 13. PRIMEIRA AÇÃO EXATA PARA O AGENTE QUE RECEBER ESTE PROMPT

1. Abrir a pasta e conferir `git status`, `master`/HEAD, os dois commits antigos e qualquer novo commit.
2. Ler `AGENTS.md`, `CONTINUIDADE.md`, `docs/ESTADO_ATUAL.md`, `docs/REVISAO_ESTREIA_24.md`, `services/live_bridge/KWAI_EVENTOS_PENDENTES.md`, `services/live_bridge/GIFT_VISUALS_CONTRACT.md`, `services/live_bridge/AUDIENCE_CONTRACT.md` e `docs/REVISAO_INDEPENDENTE_POLIMENTO_2026-10-24.md`.
3. Conferir presença de `docs/referencias/hud-conceito-chatgpt-2026-10-24.png` e versionar a **imagem exata fornecida pelo usuário**, sem recriá-la. Se não houver arquivo local, solicitar a imagem, mas continuar auditoria técnica.
4. Reproduzir prévia do Godot e exames de testes. Fazer baseline de screenshot, avisos e performance.
5. Verificar primeiro a integração do `GiftVisualCache` **já presente**, a meta única do HUD e a ausência de avatar. Atualizar backlog com P0–P3.
6. Implementar modelo/painel de metas múltiplas com testes e compatibilidade, depois o layout e cards/avatares; iterar com imagem real do jogo, sem tocar nos rigs aprovados.
7. Proteger backend/segredos e validar segurança; finalizar ou classificar corretamente conexão real das duas plataformas.
8. Executar QA, benchmark, captura, revisão independente; documentar e fazer commits/push. Em caso de bloqueio operacional, entregue estado exato e continue nas demais tarefas.

**NÃO espere outro agente voltar para começar. NÃO declare que terminou algo apenas por existir arquivo. NÃO comprometa credenciais. NÃO perca o trabalho anterior.**