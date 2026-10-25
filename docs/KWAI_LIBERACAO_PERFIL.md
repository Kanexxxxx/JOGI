# Liberação segura do perfil Kwai

Aplicação real concluída em 24/10/2026, 23h26 BRT. Consulte [a auditoria final](AUDITORIA_INTEGRACOES_FINAL_2026-10-24.md).

Execute ABRIR_NAVEGADOR_KWAI.cmd para login manual no navegador dedicado. O coletor fecha seu próprio Chromium e confirma a liberação; a janela de login utiliza o perfil existente. Após o login, feche somente essa janela no X: o coletor retoma automaticamente. Nunca abra o mesmo perfil por atalhos Chrome genéricos nem remova arquivos SingletonLock. Sem confirmação de liberação, o login falha de forma segura.

O modo login não abre a fila SQLite nem envia presentes. A fila permanece com o coletor. A propriedade usa PID e nonce, com rejeição de confirmações antigas. Cookies, credenciais e banco permanecem locais. Verificados dois ciclos em Chromium real isolado e liberação real em produção; não foram iniciadas LIVEs.

O coletor final desta manutenção foi 41480, supervisionado por 54424; sempre redescobrir identidades antes de operações futuras. Backups completos e verificados estão em LOCALAPPDATA/JOGI/backups, fora do repositório.
