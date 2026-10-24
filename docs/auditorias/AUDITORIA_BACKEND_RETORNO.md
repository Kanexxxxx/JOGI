# Auditoria independente do backend — retorno de 24/10/2026

Baseline auditado: `5f1cad12001be14f123b3095843a6d610f79cb95`, branch `master`. Auditor não participou das alterações de segurança/metas/avatares da IA substituta. Primeiro investigou em modo somente leitura; após reportar os achados, recebeu autorização do coordenador para corrigir os pontos abaixo. Não executou transmissões, login em plataforma, coleta de sala real ou geração paga. Commits e push ficam com a coordenação.

## Melhorias mantidas

- Autenticação de produtor em cabeçalho, validação Host/Origin e bloqueio de comandos administrativos pelo canal `/ws/ingest`. Um teste isolado de spoofing com token fictício de produtor recusou o comando sem enfileirá-lo.
- Token efêmero por instância no launcher, separado das credenciais da plataforma e transmitido ao Godot/coletor por ambiente, sem gravá-lo no repositório ou HTML.
- Anti-SSRF de ícones e avatares: hostname HTTPS permitido, resolução de IP público, conexão direta ao IP validado com SNI/certificado do hostname original e ausência de redirects. URLs externas não são solicitadas pelo Godot.
- Três metas no backend com persistência e adaptação do contrato legado. Asserções específicas do Godot são revisadas separadamente pelo coordenador; passar nos testes Python não comprova a apresentação no jogo.
- Imagens locais com limites de bytes, dimensões, capacidade e fallback. Avatares retiram a URL original antes de entrar na outbox da ponte.
- Sessões e diretórios TikTok/Kwai separados; catálogo e outbox preservam o valor total real de cada delta de presente.

## Achados e correções autorizadas

### P1 — o coletor descartava um presente depois de falhar no envio

Antes da correção, `forwardEvent` em `tools/kwai_live_collector.cjs` inseria o ID em `seenIds` antes de chamar o webhook. Uma prova com a função original extraída para uma VM, sem navegador ou rede externa, chamou duas vezes o mesmo ID e simulou a primeira falha HTTP: resultado `attempts=1`, `forwarded=0`, sem segunda tentativa.

Corrigido com `tools/kwai_gift_delivery.cjs`: SQLite WAL/FULL antes do envio, com até 10.000 pendências e 10.000 IDs confirmados. Repetições usam o mesmo ID; o registro pendente só é removido após resposta explícita com o mesmo `raw_event_id`, `acknowledged=true` e `delivery_status=accepted|duplicate`. HTTP 200 sozinho, ID diferente ou ausência de confirmação não libera a pendência. Arte opcional fica em RAM, sem persistir URLs de avatar.

Também foi corrigida a fronteira de aceitação no adaptador. Presentes com sink durável não passam pela deduplicação antecipada de `ViewerContext` nem pelo callback que engolia exceções no `BaseLiveAdapter`. O adaptador aguarda a outbox da ponte confirmar aceitação; falha/timeout produz 503 e permite repetir. O contrato padrão de normalização sem sink e os adaptadores TikTok não foram alterados; `remember=True` continua sendo o padrão do helper de identidade.

Estados de falha 401/503/timeout mantêm a fila e não somam `forwarded`. Erro de disco/fila cheia suspende a captura e publica estado de atenção. As pendências anteriores ficam preservadas, mas a capacidade é finita: não há garantia sobre eventos que não puderem ser aceitos enquanto a captura estiver suspensa.

### P2 — cookies administrativos de duas plataformas se sobrescreviam

Antes, o nome `jogi_admin_session` e o path `/` eram iguais em 8765/8766, embora o valor esperado dependesse da porta/plataforma. Cookies do navegador não são isolados por porta. Com token local configurado, a prova mostrou TikTok autorizado antes e não autorizado depois de autenticar Kwai no mesmo host.

`server.py` agora usa nome de cookie por plataforma e porta. O teste com um único `CookieJar` autentica as duas instâncias e lê o estado de ambas com sucesso. Nenhum token real foi usado ou impresso.

### P2 — a política de privacidade descrevia um comportamento inexistente

`SECURITY.md` afirmava que fotos ficavam somente em RAM, sem persistência de dados pessoais. O código já guardava até 128 avatares no disco local com validade de seis horas, e a recuperação/ranking preserva nomes e IDs sanitizados. A política foi corrigida para distinguir cache Godot em RAM, cache privado da ponte em disco e registros financeiros/de deduplicação. O TTL limita a validade de acesso; exclusão física é preguiçosa, sem promessa de apagamento no instante exato do vencimento.

O fluxo auditado retira `avatar_url` antes de guardar o envelope na outbox da ponte; caminhos opacos podem seguir para o journal. `AudienceDirector.export_state` preserva nomes, identidades com fonte e apoiadores, sem exportar seu mapa transitório de avatares. A retenção dos registros financeiros é distinta: outbox confirmada com limite de 50.000/36 horas; pendências até ACK; journal/checkpoint da sessão sem expiração automática de seis horas. Nenhum registro real foi aberto ou apagado nesta revisão.

Também foram corrigidos os limites distintos de presentes e avatares e o fato de autenticação administrativa estrita depender de `LIVE_BRIDGE_LOCAL_TOKEN`. O modo padrão do launcher com somente token de produtor continua permitindo o painel em loopback, com Host/Origin.

## Verificação executada

- Baseline: `services/live_bridge/.venv/Scripts/python.exe -m pytest services/live_bridge tools -q -p no:cacheprovider` — **110 testes e 48 subtestes passaram**, 56,24 s, dois avisos de depreciação do SDK.
- Após as correções: mesma suíte — **112 testes e 48 subtestes passaram**, 59,55 s, mesmos dois avisos.
- `node --check tools/kwai_live_collector.cjs` — sem erro de sintaxe.
- Testes Node do armazenamento e transporte: `node --test tools/test_kwai_gift_delivery.cjs` — **5 passaram**; cobrem falhas 401/503/rede, ACK falso, ID incorreto, reinício com pendência, capacidade finita e flush concorrente. Incluem transporte HTTP real em loopback; nenhum navegador ou serviço de plataforma é aberto.
- `test_kwai_durable_return.py`: mesmo navegador lógico com dois cookies; webhook 401 → 503 por falha de armazenamento → aceitação → repetição deduplicada; valor de 10 moedas entra uma única vez na outbox.
- `tools/run_live_instances.py --both --check --offline` — plano válido, sem iniciar processos, listener ou coleta externa.
- `git diff --check` nos arquivos de implementação — sem erro de whitespace; avisos de normalização CRLF não são falhas funcionais.
- Node local verificado: **v24.20.0**, com `node:sqlite` disponível. O coletor não instala pacote nem faz chamadas pagas.

## Limites ainda abertos

- O coletor de Kwai continua sendo experimental até confirmar login, sala real e formato de metadados de comentários/presentes. Fixtures DOM/JSON não provam compatibilidade com Kwai Brasil. Feed sem ID confiável continua ambíguo; não é possível inferir com certeza se dois pacotes idênticos são replay ou presentes distintos.
- Este trabalho não valida OBS, som audível, revisão visual do Godot nem 42 horas contínuas. O benchmark simultâneo pertence à coordenação.
- Segurança e testes de aceitação local não certificam uma conta, uma live pública ou regras comerciais da plataforma.
- A rota de compatibilidade de bootstrap por query de token ainda existe no servidor; o caminho recomendado é cabeçalho/fluxo local autenticado, sem colocar tokens em URLs. Não foram consultados histórico de navegador nem credenciais reais nesta auditoria.
