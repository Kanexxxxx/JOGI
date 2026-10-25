# Liberação segura do perfil Kwai

Correção preparada, não aplicada ao coletor ativo PID3376. Supervisor responsável PID54424. Não houve encerramento de processo Kwai.

O modo login agora não abre a fila SQLite nem envia eventos. Cria solicitação exclusiva com nonce, aguarda confirmação do coletor atualizado após fechar seu próprio contexto Chromium, abre o perfil existente para login manual e remove somente a própria solicitação ao fechar. A fila permanece com o coletor. Sem confirmação, falha sem abrir o perfil, sem remover SingletonLock/arquivos Chromium, sem matar processos. Coletor antigo sem confirmação é recusado explicitamente.

Aplicação futura exige autorização para reiniciar somente o coletor Node, preservando backend Kwai, Godot, perfil/cookies e fila. Antes: backup consistente e conferência de pendências; depois: validar troca de propriedade do perfil no Windows. Essa integração real ainda não foi executada. Não usar o atalho de login enquanto o coletor antigo estiver ativo esperando que já possua o novo protocolo.

14 testes Node locais aprovados: exclusão de solicitações, nonce, timeout, preservação de cookies/fila, fluxo login com navegador falso sem rede e oito regressões de presentes/ACK. Revisão independente não concluída por limite de uso do subagente; não declarar aprovação independente.

TikTok: reinício autorizado concluído; antigo backend42696 substituído pelo35692 através do supervisor54424. Godot23936 e Kwai34944/coletor3376 mantidos; credenciais iguais verificadas por hash sem exibir valores. Backup SQLite íntegro em LOCALAPPDATA/JOGI/backups/tiktok-restart-20261024-221358; zero presentes pendentes. Estado novo room_unavailable com próximo retry de300s confirma lógica carregada, sem perfil declarado inexistente. Nenhuma LIVE pública iniciada.
