# Kwai: arquitetura local implementada e limites reais — 24/10/2026

O usuário confirmou que as duas contas permitem live e presentes (`@nostalgiia.br` no TikTok e `@mentalista..` no Kwai).

## 1. Limite da nuvem oficial Kuaishou / Kwai Brasil

- A documentação oficial **Kuaishou SmallPlay** para callbacks de presentes/chat exige app registrado, credenciais de parceiro, vínculo por `roomCode` e callback HTTPS público assinado ([documentação oficial](https://open.kuaishou.com/miniPlayDocs/technologyrelated/Affiliatedability/basicability/localdevelopment.html)). Não há evidência de habilitação regional direta desse produto para contas comuns do **Kwai Brasil**.
- O portal internacional **Kwai for Business Marketing API** ([developers.kwai.com](https://developers.kwai.com/)) foca em anúncios e não expõe WebSocket público de sala de live como o TikTok.

## 2. Solução local implementada neste projeto (Zero-CORS Loopback + Playwright)

Para permitir que a sessão **Kwai (`127.0.0.1:8766`)** opere no mesmo PC sem depender de servidor externo nem expor portas na internet:

1. **Receptor Loopback (`KwaiLiveAdapter` em `http://127.0.0.1:8786/webhook/kwai`)**:
   - Ativado automaticamente por `LiveBridgeServer.start_live_listener()` quando `--platform kwai` está em uso (`require_collector_room=True`).
   - Só marca `platform_events_connected = True` (`status = "connected"`) quando recebe batimentos recentes (`TTL = 25s`) confirmando **sala de live ativa**; caso contrário, informa honestamente `webhook_listening`, `waiting_room` ou `login_required`.
2. **Coletor Local Dedicado (`tools/kwai_live_collector.cjs`)**:
   - Executado e supervisionado automaticamente por `tools/run_live_instances.py` em `ABRIR_KWAI.cmd` e `ABRIR_DUAS_LIVES.cmd`.
   - Usa Chromium via Playwright com perfil persistente isolado em `%LOCALAPPDATA%\JOGI\live_bridge\kwai\browser_profile` e bloqueio estrito de navegação top-frame fora de `https://*.kwai.com` (`validate_kwai_live_url`).
   - Extrai eventos em 3 camadas (respostas JSON de endpoints de live, frames WebSocket e `MutationObserver` da sala ao vivo) e entrega direto do processo Node para `http://127.0.0.1:8786/webhook/kwai` (imune a CORS e sem permitir que páginas externas enviem comandos administrativos).
   - Ignora comentários de vídeos gravados (VOD) e perfis offline (`isLiving: false`), evitando falsos positivos.
3. **Configuração de URL e Login Único**:
   - O painel `http://127.0.0.1:8766/admin` exibe a seção **Coletor Local Kwai LIVE**, permitindo colar o link exato `https://www.kwai.com/...` da transmissão caso o redirecionamento automático de `@mentalista..` mude.
   - Se o Kwai exigir login/captcha na primeira execução, basta abrir `ABRIR_NAVEGADOR_KWAI.cmd`: o coletor em segundo plano cede automaticamente o perfil (`headed_login.lock`) enquanto a janela visível estiver aberta e retoma a coleta assim que ela é fechada.

## 3. Pendência operacional real antes da estreia

- **Validação em sala real ao vivo**: os fluxos do adaptador, allowlist anti-SSRF, fila durável SQLite e coletor Playwright foram testados ponta a ponta em suíte automatizada (`services/live_bridge/test_kwai_collector.py`), mas **ainda é necessário validar com uma transmissão real aberta na conta `@mentalista..`**, especialmente para confirmar se os presentes enviados no layout web atual do Kwai Brasil trazem `coin_value` explícito no payload de rede (quando o preço não vem explícito, o sistema registra o presente com `coin_value = 0` sem inventar valores financeiros).
