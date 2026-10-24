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
   - As rotas administrativas (`/api/admin/*`, `/ws/admin`, `/ws/godot`, `/ws/ingest`) e o acesso ao painel exigem o cabeçalho `X-JOGI-Token` ou cookie HTTP seguro.
3. **Cookie Administrativo com Proteção HttpOnly e SameSite**:
   - O acesso ao painel administrativo web emite cookie de sessão com flags `HttpOnly`, `SameSite=Strict` e restrição ao host local, mitigando ataques de Cross-Site Scripting (XSS) e Cross-Site WebSocket Hijacking (CSWSH).
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
   - Webhook passivo local protegido por autenticação e validação rigorosa de payload; eventos duplicados são descartados por deduplicação LRU.

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
   - Limite máximo de bytes (`512 KB`), timeout de conexão (`2.5 s`) e teto de dimensões de imagem (`2048 px` máx de origem, reduzida para `<= 96 px` no cache de textura).
   - Validação estrita de cabeçalho MIME (`image/png`, `image/jpeg`, `image/webp`). Cargas SVG, HTML ou XML são prontamente recusadas para evitar ataques de XML External Entity (XXE) ou SVG script execution.
5. **Rotas Opacas Locais**:
   - O Godot Engine nunca requisita URLs externas diretamente da internet. O Godot comunica-se exclusivamente com as rotas locais opacas do `LiveBridge` local: `/gift-icons/<sha256>` e `/viewer-avatars/<sha256>`.

---

## 6. Privacidade e Tratamento de Dados de Espectadores

1. **Zero Persistência de Dados Pessoais (PII)**:
   - Fotos de perfil e dados de espectadores são armazenados apenas de forma transitória e efêmera na memória RAM (`AudienceDirector` e `AvatarVisualCache`), com limite estrito de LRU (64 a 256 entradas) e expiração automática por TTL.
   - O arquivo de checkpoint persistente (`RacePersistence`) e o banco de dados outbox SQLite não armazenam fotos de perfis de espectadores nem links pessoais.
2. **Flag de Desativação Rápida (`LIVE_AVATARS_ENABLED`)**:
   - O sistema suporta a variável de ambiente `LIVE_AVATARS_ENABLED=0`, permitindo desativar instantaneamente o download e a exibição de avatares caso desejado, exibindo monogramas com iniciais limpas em seu lugar.

---

## 7. Política de Menor Privilégio e Revisão de Código

- Agentes revisores automatizados (`security-reviewer` e `independent-reviewer`) operam exclusivamente em modo **somente leitura** (`enable_write_tools: false`).
- Servidores MCP externos operam isolados com permissões limitadas ao workspace do projeto.
- Não há mecanismos de execução remota de código (RCE) ou avaliação arbitrária de código (`eval`, `OS.execute` com dados externos).
