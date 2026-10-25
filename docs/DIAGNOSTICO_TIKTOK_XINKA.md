# Consulta TikTok LIVE de @xinka_ — 24/10/2026

## Causa comprovada do aviso errado

Biblioteca instalada: TikTokLive7.0.1. Em client/web/routes/fetch_room_id_api.py, message=user_not_found produz UserNotFoundError para três possibilidades: ausência de capacidade/dados de LIVE, nunca ter aberto LIVE, ou usuário inexistente. A rota HTML também usa esse erro quando LiveRoom está ausente e client/client.py reconhece que um desafio/captcha pode produzir essa situação. O adaptador JOGI convertia somente pelo nome da exceção para account_not_found e o painel declarava conta pública não encontrada. Essa equivalência estava errada.

O operador confirmou o perfil @xinka_. A investigação não fez nova consulta ao TikTok. Os registros existentes mostram HTTP429 seguido de JSONDecodeError e respostas200 seguidas de UserNotFoundError. Não é possível determinar, desses registros, qual causa upstream impediu a obtenção da sala. Não se conclui que a conta não existe ou que a permissão LIVE esteja negada.

## Correção

- UserOfflineError: waiting_room; nova consulta após120s.
- UserNotFoundError/erro de parsing/resolução: room_unavailable; consulta inconclusiva, espera300s; nunca declara o perfil inexistente.
- HTTP429 ou limite do assinador: rate_limited; espera mínima900s e respeita Retry-After maior, inclusive o prazo fornecido pelo erro do assinador.
- HTTP401/403 ou restrição reconhecida: access_blocked; espera900s, sem contornar restrições.
- Rede/conexão: connection_error; backoff15..300s, jitter adicional.
- Hooks do httpx registram o bloqueio antes do parser JSON do SDK e impedem que o fallback envie outra requisição imediatamente após429/401/403.
- unique_id entregue sem @: evita referer com @@ que o construtor do SDK gerava. Isso é um erro adicional corrigido; não se afirma que causou o bloqueio.
- Clientes descartados fecham também HTTP: disconnect(close_client=True).
- Metadados sanitizados expõem última categoria HTTP/erro e próximo horário de tentativa, sem cookies, corpo de resposta ou credenciais.

Não há evidência automática suficiente para um estado conta_inexistente: o endpoint LIVE é ambíguo. O painel explica isso em vez de fabricar certeza. Sala só fica connected após evento real de conexão do SDK.

## Validação e aplicação

23 testes focais offline passaram após os ajustes finais; incluem429/Retry-After, bloqueio do fallback, distinção offline/ambíguo/rede403, configuração real de hooks sem rede e fechamento de clientes falsos. Suíte backend durante a correção:120 testes e48subtestes aprovados,2avisos de depreciação; um teste adicional do assinador e o fechamento HTTP foram validados novamente na suíte focal. node --check e git diff --check aprovados. Revisão independente somente leitura: nenhumP1; observação de fechamento HTTP corrigida.

Nenhum serviço foi reiniciado nesta etapa; as portas permanecem com os processos existentes. O Python em execução ainda carrega o adaptador antigo. Aplicar exige autorização do operador para reiniciar somente o backend TikTok, preservando diretório, credenciais, cookies e outbox; Kwai e Godot devem permanecer abertos. Não há hot reload presumido. Não foi iniciada transmissão pública.
