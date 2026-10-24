# SECURITY.md — Política de Segurança, Segredos, Proteção Anti-SSRF e Entradas Externas

Este documento define as diretrizes e salvaguardas de segurança implementadas e aplicadas no projeto **Corrida dos Candidatos / JOGI**.

---

## 1. Gestão de Credenciais e Segredos

1. **Proibição Absoluta de Chaves no Chat ou no Repositório**:
   - Nenhuma chave de API (`TRIPO_API_KEY` iniciada por `tsk_...`, tokens ElevenLabs, chaves de stream RTMP, cookies de sessão de plataformas de live ou tokens administrativos) pode ser colada no chat ou salva em arquivos rastreados pelo Git.
2. **Autenticação Segura de Ferramentas CLI**:
   - Utilizar exclusivamente o fluxo OAuth/Device pelo navegador (`C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd login --region ov`) ou variável de ambiente local definida pelo próprio usuário no terminal do sistema operacional.
3. **Variáveis de Ambiente (`.env`)**:
   - Apenas `.env.example` (com placeholders fictícios) é versionado. Arquivos `.env`, `.env.local` e `*.key` estão bloqueados no [`.gitignore`](.gitignore).
4. **Verificação de Segredos Pré-Commit**:
   - Todo push é precedido por varredura automática regex contra padrões de chaves conhecidas (`sk_...`, `tsk_...`, `ghp_...`, `AKIA...`, `Bearer ...`).

---

## 2. Autenticação Local e Controle de Acesso

O ecossistema local do JOGI comunica o backend Python (`LiveBridge`), a interface administrativa web (`/admin`) e a engine do jogo (`Godot Engine`):

1. **Bind Exclusivo em Loopback (`127.0.0.1`)**:
   - Todos os serviços HTTP e WebSockets efetuam bind estritamente no endereço de loopback `127.0.0.1` (portas `8765` para TikTok e `8766` para Kwai). Nenhuma porta de escuta é exposta para `0.0.0.0` ou para redes locais/públicas.
2. **Token de Sessão Local (`LIVE_BRIDGE_LOCAL_TOKEN`)**:
   - Quando `LIVE_BRIDGE_LOCAL_TOKEN` está configurado, as APIs administrativas e `/ws/admin` exigem `X-JOGI-Token` ou cookie administrativo. O HTML de login continua acessível, sem segredos embutidos. Os atalhos/launcher de produção geram token administrativo separado quando nenhum válido foi fornecido e gravam `operator-token.key` no diretório privado de estado, fora do Git. Só o caminho é mostrado; o operador copia a chave localmente para o painel. A escrita é atômica com modo `0o600`; no Windows as permissões efetivas dependem das ACLs herdadas do perfil, sem promessa de isolamento contra outros processos do mesmo usuário.
   - Porta ocupada preserva o arquivo/token anterior. Saída graciosa remove somente o arquivo ainda contendo a chave gerada pelo próprio launcher; após crash pode restar arquivo obsoleto, renovado no próximo início livre. `--check` não gera credenciais. A chamada direta ao backend/construtor de baixo nível, sem token administrativo, continua loopback-only; ela exige configuração explícita de autenticação para ser usada como produção.
   - O launcher gera credenciais efêmeras distintas de motor (`LIVE_BRIDGE_ENGINE_TOKEN`) e produtor (`LIVE_BRIDGE_PRODUCER_TOKEN`). Em produção, `/ws/godot` aceita somente a credencial do motor ou a administrativa; a credencial de coleta não permite ocupar o canal nem confirmar presentes. O motor recebe sua credencial; o coletor recebe somente a de produtor, sem herdar tokens administrativos ou do motor.
   - `/ws/godot` aceita apenas telemetria, ACK de evento, resultado de comando e ping; nunca ingere envelopes administrativos ou de audiência. `/ws/ingest` aceita produtor autorizado, mas bloqueia comandos administrativos. Compatibilidade com o token produtor no canal do motor existe somente em desenvolvimento explícito.
3. **Cookie Administrativo com Proteção HttpOnly e SameSite**:
   - O acesso autenticado emite cookie com `HttpOnly`, `SameSite=Strict` e nome exclusivo por plataforma e porta. Cookies não são isolados por porta pelo navegador; o nome distinto permite manter os dois painéis autenticados no mesmo host sem um sobrescrever o outro.
4. **Token de Produtor Confiável (`LIVE_BRIDGE_PRODUCER_TOKEN`)**:
   - Webhooks locais de entrada (ex: ingestão de eventos Kwai em `/webhook/kwai`) exigem validação de token do produtor no cabeçalho `X-JOGI-Token` ou `Authorization: Bearer <token>`, impedindo que agentes não autorizados na máquina injetem presentes ou votos arbitrários.

---

## 3. Segurança das Integrações de Live (TikTok e Kwai)

1. **Isolamento de Processos e Portas Independentes**:
   - A instância do TikTok roda isolada na porta `8765`, com seu próprio banco SQLite e journal.
   - A instância do Kwai roda isolada na porta `8766`, com banco e diretórios de armazenamento completamente separados.
   - Uma falha, reinício ou bloqueio em uma das instâncias não impacta a integridade nem os dados da outra.
2. **Adaptador TikTok Live**:
   - Conexão passiva com reconexão exponencial e isolamento em thread de coleta; envelopes recebidos são convertidos no formato formal validado (`schema_version=1.0`).
3. **Adaptador Kwai Live**:
   - Webhook local autenticado e coletor de página autorizado pelo operador. Isso não comprova compatibilidade com uma sala real do Kwai Brasil; login, sala ativa e metadados de presentes ainda precisam de validação real.
   - Presentes capturados são guardados antes do envio em `collector_gifts.sqlite3`, fora do repositório, com SQLite WAL e sincronização FULL. A fila retém até 10.000 pendências e até 10.000 IDs confirmados. Não armazena tokens ou URLs de avatar; imagens opcionais ficam em RAM no coletor e podem perder sua associação após reinício, sem perder os valores do presente.
   - O coletor só remove um presente depois de ACK explícito do mesmo ID bruto, com `accepted` ou `duplicate` da outbox durável da ponte. HTTP 200 isolado não é confirmação. Falhas 401/503 ou timeout mantêm a pendência e geram estado de atenção/repetição.
   - Fila cheia ou erro de armazenamento suspende a captura automática, preserva pendências anteriores e exige intervenção. Eventos que não puderam ser aceitos nessa capacidade finita não são apresentados como entregues; não há garantia para eventos que ocorram enquanto a coleta estiver suspensa.

---

## 4. Tratamento de Entradas Externas da Live (Untrusted Input)

Em transmissões públicas, nomes de usuários e comentários chegam de espectadores desconhecidos e são tratados como **dados não confiáveis**:

| Vetor de Risco | Regra de Mitigação Obrigatória |
|---|---|
| **Injeção de BBCode no Godot HUD** | Renderizar nomes e ações exclusivamente através de nós `Label` (texto puro estático), nunca interpolar `display_name` ou texto em `RichTextLabel` com BBCode ativo. |
| **Caracteres de Controle e Bidi Override** | Sanitização automática em GDScript e Python removendo caracteres de formatação bidirecional (`\u202e`, `\u200e`, etc.), caracteres de controle C0/C1 e espaços excessivos, preservando acentos da língua portuguesa. |
| **Integridade de Grapheme Clusters UTF-8** | Truncamento visual (`ellipsize_utf8`) baseado em agrupamento de grafemas, impedindo que sequências ZWJ (`U+200D`), seletores de variação (`U+FE0F`) ou modificadores de tom de pele em emojis compostos sejam partidos ao meio. |
| **XSS no Painel Administrativo Web** | Renderizar nomes, mensagens e telemetria exclusivamente via `textContent` em elementos do DOM; proibido utilizar `innerHTML` ou injeções HTML diretas. |
| **DoS por Flood de Comentários / Likes / Presentes** | O `LiveBridge` aplica rate limiting por usuário, janela de agregação para curtidas e buffer delimitado de eventos por frame. O Godot HUD impõe taxa máxima de atualização visual para entradas de chat. |
| **Falsificação de Comandos e Parâmetros** | Validação rígida de tipo e intervalo para todos os campos (`candidate_slot` limitado a 0..2, `coin_value` inteiro não negativo, metas limitadas por valores máximos auditados). |

---

## 5. Download Seguro e Cache de Avatares e Ícones de Presentes (Anti-SSRF)

Tanto o cache de ícones de presentes (`gift_images.py` / `gift_visual_cache.gd`) quanto o cache de avatares de espectadores (`avatar_images.py` / `avatar_visual_cache.gd`) implementam defesas rigorosas contra Server-Side Request Forgery (SSRF):

1. **Lista de Domínios Permitidos (Allowlist de CDNs)**:
   - Somente URLs de CDNs oficiais verificadas das plataformas (TikTok e Kwai) são aceitas para download de imagens remotas.
2. **DNS Pinning e Resolução Prévia de IP Público**:
   - O endereço remoto é resolvido por DNS antes da conexão. Se o endereço IP resolvido for privado (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`), de loopback (`127.0.0.0/8`), de link-local (`169.254.0.0/16`) ou multicast, a requisição é **imediatamente rejeitada**, prevenindo ataques de DNS rebinding.
   - A conexão TLS é estabelecida diretamente com o IP público validado, enviando o SNI e o cabeçalho `Host` originais.
3. **Bloqueio de Redirecionamentos (`max_redirects = 0`)**:
   - Requisições HTTP não seguem redirecionamentos automáticos (respostas `301`, `302`, `307`), impedindo que um endpoint inicial seguro redirecione para um endereço interno ou malicioso.
4. **Limites Rígidos de Resposta e Recursos**:
   - Avatares: até 512 KiB, timeout de download de 4 s, origem até 2048 px e textura Godot até 96 px. Ícones de presentes: até 1 MiB, timeout de 5 s, origem até 4096 px e textura Godot até 512 px.
   - Validação estrita de cabeçalho MIME (`image/png`, `image/jpeg`, `image/webp`). Cargas SVG, HTML ou XML são prontamente recusadas para evitar ataques de XML External Entity (XXE) ou SVG script execution.
5. **Rotas Opacas Locais**:
   - O Godot Engine nunca requisita URLs externas diretamente da internet. O Godot comunica-se exclusivamente com as rotas locais opacas do `LiveBridge` local: `/gift-icons/<sha256>` e `/viewer-avatars/<sha256>`.

---

## 6. Privacidade e Tratamento de Dados de Espectadores

1. **Persistência mínima, com cache privado e limitado**:
   - O cache Godot de avatares fica em RAM (LRU de 64 texturas). A ponte pode guardar até 128 imagens de avatar em disco local, nomeadas por hash, com metadados de integridade e validade de seis horas. Esses metadados não contêm URL de origem, ID ou nome do espectador.
   - O TTL impede servir imagens vencidas; a remoção de arquivos é feita ao carregar o cache, acessar uma entrada vencida ou desalojar entradas pelo limite. Não há promessa de exclusão física exatamente no segundo em que vence o TTL.
   - Outbox, journal e checkpoint preservam IDs e nomes sanitizados necessários à deduplicação, ranking e recuperação. Não guardam bytes de foto de perfil nem a URL original do avatar; caminhos opacos podem acompanhar eventos pendentes.
   - A outbox da ponte mantém pendências até confirmação, com capacidade finita; registros confirmados são podados pelo limite de 50.000 e retenção configurada de 36 horas. Isso não é a retenção do checkpoint/journal do jogo: estes preservam o estado da sessão e nomes/IDs do ranking, sem expiração automática equivalente ao TTL das fotos. Limpeza de sessão/dados exige uma ação própria do operador, sem apagar registros para resolver divergência de documentação.
   - A fila durável do coletor também preserva identificadores, nomes e valores de presentes até sua confirmação. Todas essas pastas são locais, fora do Git; não se deve chamá-las de armazenamento sem dados pessoais.
2. **Flag de Desativação Rápida (`LIVE_AVATARS_ENABLED`)**:
   - O sistema suporta a variável de ambiente `LIVE_AVATARS_ENABLED=0`, permitindo desativar instantaneamente o download e a exibição de avatares caso desejado, exibindo monogramas com iniciais limpas em seu lugar.

---

## 7. Política de Menor Privilégio e Revisão de Código

- Agentes revisores automatizados (`security-reviewer` e `independent-reviewer`) operam exclusivamente em modo **somente leitura** (`enable_write_tools: false`).
- Servidores MCP externos operam isolados com permissões limitadas ao workspace do projeto.
- Não há mecanismos de execução remota de código (RCE) ou avaliação arbitrária de código (`eval`, `OS.execute` com dados externos).
