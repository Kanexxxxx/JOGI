# Briefing atualizado — Corrida dos Candidatos

Registrado em 23/10/2026 a partir da explicação direta do usuário. Este documento corrige a interpretação do produto no levantamento anterior. Não modifica código nem substitui os registros históricos. Nas decisões de produto, esta explicação tem precedência sobre os planos antigos.

## Produto pedido

O operador inicia e acompanha a transmissão; os espectadores são os jogadores. O jogo corre automaticamente e responde às interações da live. Elenco confirmado: **Lula e Flávio Bolsonaro**, não Jair Bolsonaro. Interface, instruções e apresentação em português brasileiro.

Dois personagens 3D pequenos, caricatos, reconhecíveis e com proporções expressivas; diferenças exatas de altura/proporção ainda não foram definidas. A prioridade solicitada é criar os personagens e suas animações antes de desenvolver a experiência final da corrida. Evitar repetir a aparência genérica do protótipo.

A pista deve sustentar corrida contínua. Presentes aumentam velocidade/progresso e podem causar ataques temáticos ao adversário. O público influencia o resultado e o término; não está confirmado que a regra antiga de 300 segundos deva permanecer. A expressão “cronometragem disparar” precisa ser traduzida em uma regra clara de velocidade, distância ou pontuação. Não assumir que pagar reduz um cronômetro.

Obstáculos, reações e itens devem ter relação criativa com os personagens. Os exemplos de quantidade de rosas e leis foram ilustrações: não são catálogo ou regras aprovadas. Pesquisa futura deve identificar Lula e Flávio corretamente, usar fontes verificáveis para referências reais e distinguir fatos, alegações, sátira e invenção. Nenhum dossiê político foi produzido nesta etapa.

Presentes especiais devem produzir acontecimentos memoráveis: reação do personagem, câmera dedicada, transformação/troca de roupa e aceleração especial. O jogo precisa conectar visualmente o presente à consequência, para que o espectador entenda a ação que provocou.

## Plataformas e operação

TikTok e Kwai. Mesmo jogo, com catálogos de presentes e públicos distintos. Decisão técnica adotada a partir da resposta: duas sessões isoladas, uma por plataforma, compartilhando código e assets. Prazo confirmado pelo usuário: sábado **24/10/2026 às 09:00, America/Sao_Paulo**. Objetivo de operação: **32 horas**.

Cada sessão terá ciclos de **50 rodadas por tempo fixo**, decisão confirmada pelo usuário. Configuração inicial adotada: **10 minutos por rodada**, ajustável; vence quem acumular mais distância quando o tempo terminar. Não usar chegada por distância fixa. Ao completar a rodada 50, encerra o ciclo, reinicia o estado de jogo e começa outro ciclo. O reinício deve preservar os registros técnicos de eventos já processados, evitando reprocessar presentes antigos. Cinquenta rodadas de 10 minutos somam 8h20 de corrida, sem contar intervalos.

O usuário já transmitiu jogos no TikTok LIVE Studio neste PC com bom desempenho percebido. OBS foi mencionado, mas ainda não usado para iniciar transmissão. Isso não confirma acesso a presentes, captura de eventos ou transmissão no Kwai; esses itens seguem pendentes.

O usuário priorizou a melhor qualidade possível, com rosto quase idêntico e poucas tentativas bem preparadas. Não definiu teto numérico de gastos. Isso não autoriza recarga ou compra automática. Qualquer gasto futuro deve ter plano e custo concretos; o saldo atual zero do Tripo impede geração pela API consultada.

Proposta técnica: um projeto de jogo, com configuração e processos separados por plataforma se as corridas forem independentes. Jogo/renderização e captura podem ocorrer no PC de transmissão; não é necessário hospedar o jogo em um site para espectadores controlarem pelos eventos da live. Necessidade de servidor remoto só pode ser definida depois da infraestrutura escolhida.

## Pré-requisitos verificados agora

| Item | Resultado | Limite |
|---|---|---|
| Godot/GDA e protótipo | Testes atuais detalhados em MAPA_DO_PROJETO.md | Visual final e 32h não validados |
| Tripo CLI | 0.7.0, doctor ok para autenticação e API | Saldo da API: **0 créditos** |
| Tripo plano de modelo + rig | dry-run `valid:true`, sem erros | Nenhuma geração paga feita; aviso: --then substitui cadeia padrão |
| Dreamina Canvas | 1.0.3, schema lido, auth status `loggedIn:true` | Modelos, saldo e geração ainda não verificados |
| Blender | Executável localizado em Blender 5.2 | Pipeline de exportação/rig ainda não testado |
| OBS | Executável localizado | Acesso às lives, perfis e transmissão não verificados |
| PC | Ryzen 7 5700X, RTX 4060, ~15,9 GB RAM | Duas sessões + encoders precisam de medição real |
| TikTokLive Python | Não instalada no ambiente do projeto | Adaptador existe, mas não é iniciado pelo servidor |
| Kwai | Receptor local existente, desativado por padrão | Coletor real de eventos não implementado |

Autenticação de ferramentas de mídia não significa conexão de conta TikTok/Kwai. Não foram solicitados ou expostos segredos.

## Pipeline proposto para personagens e animações

1. Duas referências visuais coerentes, com frente e perfil/silhueta, roupas e proporções definidas; validar antes de consumir créditos 3D.
2. Dois modelos com esqueleto utilizável e importação Godot validada. Uma aparência base e uma transformação inicial para cada personagem são proposta de escopo, não arte aprovada.
3. Conjunto inicial proposto: espera, corrida, aceleração, ataque, impacto/queda, recuperação, comemoração e transformação. Evitar gerar um modelo novo para cada movimento: usar o esqueleto e animações reutilizáveis.
4. Cutscenes curtas dentro do motor, coordenadas com fila de eventos. Decidir como manter a corrida legível durante a cena e impedir que várias ativações escondam o jogo.
5. Só depois integrar a pista final, HUD, reações e efeitos com os personagens validados.

IA de vídeo produz clips; isso não equivale a animações de esqueleto utilizáveis por um personagem jogável. Modelagem, rigging, retarget e inspeção de deformação continuam necessários.

## Bloqueios reais para transmissão e presentes

- Trocar nome no HUD não cria Flávio: o protótipo e os personagens precisam ser redesenhados.
- O servidor não inicializa adaptadores; apenas o simulador local foi validado ponta a ponta.
- Dois Godots no mesmo LiveBridge recebem os mesmos eventos e disputam a única telemetria armazenada. Corridas independentes precisam de bridges/portas/estado separados e URL configurável no jogo.
- O contrato/adaptadores agrupam presentes por tiers e não preservam toda a identidade nativa necessária para um catálogo de presentes específicos por plataforma. Definir ID, combo, usuário, alvo e efeito por plataforma.
- É necessário definir escolha do candidato pelo usuário antes do presente. Os adaptadores atuais favorecem slot 1 quando não há voto anterior.
- Não há fila durável, checkpoint ou supervisor de recuperação demonstrados. O despacho pode consumir eventos sem Godot conectado, e filas cheias podem descartar itens. Isso precisa ser resolvido para não perder ações durante quedas.
- A simulação do painel deve ser separada do estado real.
- Presentes caros devem ter prioridade, idempotência e regra explícita de combos; ações cosméticas/cutscenes não podem bloquear ingestão ou alterar tempo de efeito de maneira imprevisível.
- Catálogo e valores atuais de presentes devem vir das contas/plataformas reais; não assumir preços universais, nem que os presentes mais caros sejam iguais nas duas.

## Estabilidade exigida

Proposta de critérios: reinício automático controlado, reconexão de conectores, isolamento por plataforma, limites de filas/cutscenes, checkpoint de corrida e eventos, logs limitados, métricas de FPS/latência/memória e ensaio com captura/transmissão. Nenhuma alteração global de energia/Windows foi feita.

Teste completo de 32 horas só será comprovado depois de executado por 32 horas; testes rápidos/headless não o substituem. Planejar o maior ensaio possível antes do prazo, sem prometer a produção completa antes de validar arte e eventos reais.

## O que depende do usuário

1. Confirmar PC de operação e acesso já habilitado para transmitir do computador em cada conta; informar software/integrador usado e os identificadores públicos das salas quando formos conectar. Login deve ocorrer nas ferramentas oficiais, sem senhas/cookies/chaves no chat. Prazo já confirmado: 24/10 às 09:00.
2. Plataforma definida: mesmo projeto, sessões isoladas e catálogos próprios. Validar essa interpretação antes de uma eventual alteração para corrida compartilhada.
3. Rodada por tempo e ciclo de 50 já confirmados; configuração inicial de 10 minutos adotada. Qualidade visual é prioridade; orçamento numérico não definido. Preparar custo antes de geração paga ou recarga.
4. Na etapa visual, aprovar os dois conceitos. Na etapa de integração, conferir catálogo de presentes disponível e realizar um teste real pequeno de cada fonte, incluindo comentários e combo de presente.

Podemos avançar sem essas respostas na especificação, pesquisa factual e preparação de conceitos. Geração paga depende do orçamento; implementação da vitória depende da regra de término; conexão real depende das contas/fonte de eventos.

## Próxima sequência proposta

Primeiro: conceitos dos dois personagens, levantamento de custos/rig/animações e prova do caminho de eventos de cada plataforma. Essa prova técnica pode ocorrer em paralelo à arte para evitar descobrir ausência de conector apenas no fim. Depois: integração dos modelos, efeitos e regras; por fim: recuperação de falhas e ensaio prolongado. Escopo final até sábado deve ser fechado a partir dessas provas, sem apresentar o protótipo atual como produto final.

## Evidências

Explicação do usuário nesta conversa; AGENTS.md; skills tripo-cli e dreamina-canvas-cli; saída de tripo doctor e make --dry-run; Dreamina --version/schema/auth status; inventário CIM e caminhos de OBS/Blender; `services/live_bridge/{server,protocol}.py`; `services/live_bridge/adapters/{tiktok_adapter,kwai_adapter}.py`; `services/live_bridge/pyproject.toml`; `game/scripts/live_event_bus.gd`; inspeção independente de prontidão de integração.
