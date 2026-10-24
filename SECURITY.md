# SECURITY.md — Política de Segurança, Segredos e Entradas Externas

---

## 1. Gestão de Credenciais e Segredos

1. **Proibição Absoluta de Chaves no Chat ou no Repositório**:
   - Nenhuma chave de API (`TRIPO_API_KEY` iniciada por `tsk_...`, chaves de stream, cookies de sessão do TikTok/Kwai ou tokens de administração) pode ser colada no chat ou salva em arquivos rastreados pelo Git.
2. **Autenticação Segura do Tripo CLI**:
   - Utilizar exclusivamente o fluxo OAuth/Device pelo navegador (`C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd login --region ov`) ou variável de ambiente local definida pelo próprio usuário no terminal.
3. **Variáveis de Ambiente (`.env`)**:
   - Apenas `.env.example` (com placeholders vazios) é versionado. Arquivos `.env`, `.env.local` e `*.key` estão bloqueados no [`.gitignore`](file:///C:/Users/Kanex/OneDrive/Desktop/JOGI/.gitignore).

---

## 2. Tratamento de Entradas Externas da Live (Untrusted Input)

Em uma transmissão pública no TikTok ou Kwai, qualquer espectador pode enviar nomes de perfil e comentários contendo payloads maliciosos:

| Vetor de Risco | Regra de Mitigação Obrigatória |
|---|---|
| **Injeção de BBCode no Godot HUD** | Nunca interpolar `display_name` ou texto do chat diretamente em `RichTextLabel` com `bbcode_enabled = true`. Usar `Label` padrão (texto puro) ou escapar `[` por `[lb]` antes da renderização. |
| **XSS no Painel Administrativo Web** | Renderizar nomes e mensagens exclusivamente como texto escapado; proibido usar `innerHTML` ou `dangerouslySetInnerHTML`. |
| **DoS por Flood de Chat / Likes / Presentes** | O `LiveBridge` aplica limite de taxa por usuário, agregação em janelas de `200ms` e teto máximo de eventos enviados por frame ao Godot. |
| **Falsificação de Comandos Locais (WebSocket)** | O servidor `LiveBridge` e o Painel Admin fazem bind exclusivamente em `127.0.0.1` (localhost) e validam um token de sessão local efêmero (`LIVE_BRIDGE_LOCAL_TOKEN`). |
| **SSRF / Download de Avatares Externos** | Caso avatares de doadores sejam exibidos, validar o domínio de origem (CDNs oficiais), limitar tamanho máximo de resposta (`<= 512 KB`), timeout de `2s` e decodificar apenas formatos de imagem seguros (PNG/JPEG/WebP). |

---

## 3. Política de Menor Privilégio para Agentes e MCPs

- Agentes revisores (`security-reviewer` e `independent-reviewer`) operam em modo **somente leitura** (`enable_write_tools: false`).
- MCPs não utilizados pelo projeto não são habilitados globalmente; servidores específicos do jogo (`gda-mcp`) ficam restritos ao escopo local do workspace (`.agents/plugins/corrida-gamedev/mcp_config.json`).
