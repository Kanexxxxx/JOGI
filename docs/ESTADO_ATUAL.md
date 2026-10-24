# Estado atual — 24/10/2026

## Abrir e operar

Cena principal: `game/scenes/main/stadium_race.tscn`, configurada em `game/project.godot`. Atalhos e operação: [INICIAR_JOGO.md](../INICIAR_JOGO.md).

Sessões independentes: TikTok `127.0.0.1:8765`, Kwai `127.0.0.1:8766`. Supervisor reinicia cada processo isoladamente, com espera progressiva e limite de seis reinícios em dez minutos. Uma segunda abertura recusada preserva processos e status do supervisor existente. Não inicia broadcast e não altera variáveis globais.

## Apresentação vigente

Câmera em perspectiva atrás de Lula e Flávio, correndo na mesma direção em raias separadas. A vantagem visual é comprimida para manter ambos enquadrados; distância e resultado usam a simulação real. Render interno 1080×1920, MSAA 4×, limite de 60 FPS.

A pista foi trocada de vermelho para azul-cobalto a pedido do usuário, com linhas brancas e granulação reduzida para separar as capas vermelha e verde. Arquibancadas detalhadas dos dois lados, torcida com volumes 3D e animação compartilhada, bandeiras, painéis de direção e iluminação por rodada.

Palácio do Planalto reconstruído localmente em Blender: `game/assets/environments/planalto/planalto_v1.glb`, 42.752 triângulos. É uma interpretação estilizada baseada nas referências arquitetônicas, não um levantamento dimensional. Arquibancada derivada local: `grandstand_100k_v2.glb`; original da API preservado.

Bonecos aprovados: `game/assets/characters/api-cape-v13/{lula_run,flavio_run}.glb`. A pasta tem esse nome, mas o Flávio usa a correção de capa v8. Faces, mapas 4K e fontes originais preservados. Corrida, espera e impacto com rig de 65 ossos; loop de corrida corrigido localmente e transições suavizadas. Chegada com corrida final curta e comemoração corporal por braços/saltos; não foi criado blendshape facial de sorriso.

Ondulação adicional das capas: derivados locais em `game/assets/characters/cape-motion-v1`, selecionados por CandidatePresentation. Corpo/rosto conservam material original; apenas a superfície da capa recebe shader com máscara de barra livre e ombros presos. Amplitude/frequência acompanham a velocidade e o turbo, suavizam no impacto/comemoração e congelam na pausa. Não é simulação física de tecido com colisão; é deformação visual controlada e limitada. GLBs fonte, texturas e animações originais permanecem intactos. Testes de capa, apresentação e comemoração passaram sem stderr; revisão independente sem bloqueios.

## Corrida e interação

50 rodadas de 600 segundos por ciclo; vence a maior distância. O fim libera a faixa de chegada e câmera de comemoração. Empate não soma vitória. Obstáculos provocam reação de impacto ou são absorvidos por escudo.

Comentários 13/22 escolhem equipe e dão impulso pequeno com intervalo por usuário. Likes, compartilhamentos e seguidores alimentam participação/metas. Sem equipe escolhida, presentes ficam neutros no ranking e não favorecem um candidato automaticamente.

Top 5 de presenteadores durante a corrida; Top 3 dos mesmos apoiadores no pódio. Nomes sanitizados e limitados. Moedas recebidas não são convertidas em reais. O catálogo aprende IDs/preços observados e permite mudar a ação por ID, mantendo valores financeiros e eventos já pendentes.

Presentes durante PHOTO_FINISH/PODIO somam imediatamente e reservam efeito para a próxima rodada, com agregados limitados e sem mudar o resultado fechado. Ver [PRESENTES_ENTRE_RODADAS.md](PRESENTES_ENTRE_RODADAS.md).

## Recuperação

Outbox SQLite durável no bridge e journal antes do ACK no jogo. Checkpoint periódico por canal, validação antes da recuperação, deduplicação e cópia de segurança. Após uma queda abrupta, andamento pode voltar até o último checkpoint (30 s); não prometer recuperação perfeita do instante da queda. Testes de replay cobrem presentes do intervalo e ausência de contagem duplicada.

## Áudio e créditos

ElevenLabs: 30 falas e quatro efeitos gerados e guardados localmente. Uma voz por vez e pool limitado de efeitos, com cooldown, prioridades e redução do volume dos efeitos durante fala. Usa vozes genéricas distintas; não clonagem das vozes dos políticos. A chave fica fora do Godot e dos arquivos versionados. Escuta humana e captura no OBS ainda precisam de confirmação.

Geração já realizada: 434 créditos ElevenLabs no último registro confirmado. Tripo API: rig/corrida/espera dos dois, arquibancada e dois impactos; 150 créditos consumidos nessas tarefas, saldo esperado 850 de 1.000 iniciais. O saldo de 580 informado no Studio é separado. Não houve geração paga nesta continuação.

## Evidências e limites

- `evidencias/estadio/pista-cobalto-v1.png`: captura real 1080×1920; ensaio de 8 s, cerca de 59,99 FPS, p95 16,67 ms. Público da captura é simulação explicitamente marcada como teste.
- `evidencias/estadio/pista-cobalto-capas-v2.png`: piso azul com as novas capas, ensaio de 14 s, média de 59,90 FPS e p95 16,67 ms. `podio-cobalto-capas-v2.png`: comemoração real com Top 3, ensaio de 11 s e média de 60 FPS. Houve breve sobreposição dos dois processos, não um ensaio completo de duas lives.
- `evidencias/estadio/corrida-final-v5.png`: apresentação anterior à troca do piso, 14 s, cerca de 60 FPS.
- `services/live_bridge/qa-panel/report.json`: 15 jornadas funcionais; larguras 375/768/1440, sem overflow nem erros de rede/console. Não é auditoria completa de acessibilidade nem aprovação visual do usuário.
- Suíte ampliada backend + ferramentas de áudio: **86 testes + 27 subtestes passaram** (47,21 s), com dois avisos de depreciação do SDK. Primeiro run teve duas falhas de limpeza de pastas temporárias (WinError 145), sem falha nas asserções funcionais; casos isolados e repetição completa passaram. Causa dessas falhas de limpeza não comprovada. Revisão independente aprovou a proteção do status e os cinco testes focais do supervisor.
- E2E atualizado usa `stadium_race.tscn`: bridge → WebSocket → aplicação no personagem → ACK de presente simulado passou, sem live externa. Encerramento headless ainda emite aviso de dois objetos; integração do estádio emite aviso de seis. Não esconder esses avisos como certificação de estabilidade.
- GDA: scripts da reserva e persistência válidos, cena válida e preflight `ready`; testes de reserva/persistência passaram sem stderr. Revisão independente da reserva sem bloqueios.
- Após integrar as capas, `test_stadium_integration.gd` foi executado novamente e passou com stderr vazio; o aviso de seis objetos descrito acima pertence às execuções anteriores. O E2E anterior ainda registrou dois objetos no encerramento. Não foi identificada causa definitiva desses avisos intermitentes.
- Ensaio anterior com duas instâncias: cerca de 60 FPS em ambas durante sobreposição de aproximadamente 20 s. Não incluiu codificação OBS nem teste de 32 horas.

## Pendências de estreia

1. **Kwai:** Studio permite preparar transmissão, mas ainda não há coletor comprovado de comentários/presentes conectado ao bridge. Webhook passivo não substitui coletor. Não apresentar isso como integração concluída.
2. **TikTok:** SDK instalado e escuta pública preparada para `nostalgiia.br`; falta validar eventos de uma sala real. O launcher não inicia a live.
3. **OBS:** aplicativo instalado e configuração vertical vista em logs anteriores; captura da janela e áudio final não foram confirmados. Controle nativo de janelas indisponível na última tentativa. Não sobrescrever o perfil antigo.
4. Ouvir as falas/efeitos e confirmar volume em gravação local.
5. Validar estabilidade prolongada com os dois jogos e codificação. Testes curtos não comprovam operação contínua de 32 horas.

O prazo informado era 24/10 às 09h e já passou. Não declarar estreia pronta enquanto as pendências acima continuarem abertas.
