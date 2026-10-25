# Retomada das duas contas — 25/10/2026

## Estado aplicado

TikTok voltou para **@nostalgiia.br**, por solicitação do operador. O launcher usa `production/accounts/72282688fe011f2e`; a sessão de @xinka_ continua preservada em `fe7fa0c98188fdd1`. Nenhum voto, equipe ou presente da outra conta foi importado.

Kwai permanece **@mentalista..**. Seu jogo não abria porque havia um encerramento manual persistido, não porque o motor estivesse quebrado. O operador autorizou uma nova sessão. A pasta anterior inteira está em `LOCALAPPDATA/JOGI/live_bridge/kwai/production/archive/1b3c46347e4dd12e-20261025-092515`; o checkpoint está em `APPDATA/Godot/app_userdata/Corrida dos Candidatos/sessions/production/accounts/1b3c46347e4dd12e/archive/kwai-20261025-092515`. Histórico, bancos e checkpoints não foram apagados. Credencial, cookies, áudio e configurações foram conservados. A fila anterior tinha zero pendências, com integridade SQLite confirmada.

As duas sessões abriram na rodada1, em RACING, com persistência pronta e sem erro. Cada plataforma tem seu próprio supervisor. Os painéis foram abertos e autenticados por cookies HttpOnly num navegador local exclusivo do operador. `ABRIR_PAINEIS.cmd` reabre esse navegador sem colocar chaves em URLs, logs ou texto da página. Se ele já estiver aberto, usar suas abas existentes.

Nenhuma LIVE foi iniciada. OBS e TikTok LIVE Studio não foram reconfigurados nem usados para publicar conteúdo.

## Correções

- Kwai usava nome exibido como identidade DOM: removido. Somente IDs estáveis efetivamente disponíveis associam equipe; identidade ausente fica neutra.
- Equipes Kwai eram voláteis: histórico SQLite separado por conta conserva escolha e instante. Homônimos não se confundem, presentes atrasados consultam a escolha anterior, e trocas só afetam eventos futuros.
- Parser e fila Node descartavam o timestamp pago: ambos agora conservam horário e precisão, inclusive após reabrir a fila.
- Retry de presente congela o primeiro envelope/equipe até aceitação durável; uma troca de equipe durante a falha não redireciona o presente.
- Descoberta pode seguir uma âncora LIVE legítima, única e com proprietário correspondente ao perfil. Recomendações de outros canais e links ambíguos são recusados. Sem prova, continua aguardando URL legítima; não adivinha sala.
- Diagnósticos distinguem observação, voto válido, comentário ignorado, duplicado, HTTP aceito, ingestão confirmada e falha. Vídeo ativo não é declarado feed conectado; quadros binários desconhecidos são contabilizados.
- Kwai recebeu a confirmação interna de efeito, cards, ataque ao adversário e escudo sem impulso indevido já corrigidos no TikTok. Overrides de mecânica não alteram preço nem faixa financeira.
- Credencial administrativa deixa de ser trocada/apagada a cada abertura normal. Tokens de produtor e motor continuam efêmeros e separados.
- Adaptadores fecham seus bancos de equipes durante shutdown: corrigida a causa de falhas de limpeza SQLite no Windows encontradas pela suíte, sem ocultar os erros dos testes.
- Telemetria informa dimensões reais do render e da janela de prévia.

Os quatro presentes TikTok mantêm imagens autênticas. A confirmação das capturas pertence a @xinka_. Na conta @nostalgiia.br, os ícones permanecem, mas interface/API sinalizam **valor não confirmado**. Não se inventou catálogo Kwai nem se copiaram preços TikTok para ele. IDs e valores efetivos continuam vindo dos eventos legítimos.

## Testes e evidências

- Python completo: **136 testes e48 subtestes aprovados**, dois avisos de depreciação do SDK. Depois, um caso adicional de confirmação de catálogo por conta foi acrescentado; os5 testes de catálogo passaram no reteste.
- Godot: **35 scripts aprovados**; scripts/cena válidos e preflight `started=true`, sem diagnósticos. T1/T2/T3/T4 também foram exercitados com source/session Kwai num teste estrito separado, para ambas as equipes, incluindo ataque adversário, neutralidade, preço desconhecido e duplicado.
- Node: **22 testes aprovados** de observabilidade, fila paga e handoff; após revisão,14 de parser/fila passaram novamente, incluindo timestamp após restart e recusa de sala alheia.
- E2E Kwai isolado: webhook autenticado→backend→fila→Godot real→cards/ACK. Nove presentes, nove ACKs, destinos `[1,1,1,1,2,2,2,2,0]`, sem reaplicação.
- E2E TikTok isolado: classes SDK de comentários, presentes para ambas as equipes e neutro; três ACKs e replay bloqueado. Nenhuma compra, requisição SDK externa ou evento fictício em produção.
- QA dos painéis: autenticação, comandos com confirmação real do Godot, persistência, isolamento e layouts375/768/1440: **FUNCTIONAL_PASS**, zero erros JavaScript. Comandos destrutivos só atingiram instâncias temporárias, nunca8765/8766.
- Medição simultânea real:13 amostras por60s, telemetria recente em todas, FPS mínimo60, zero orphan nodes e presentes pendentes. Arquivo `evidencias/producao/dual-recovered-motion.json`.

| Plataforma | Cronômetro inicial→final | Lula (m) | Flávio (m) | Memória estática |
|---|---|---|---|---|
|TikTok|396,35→336,27s|2443,56→3164,63|2443,64→3164,74|115,58MB|
|Kwai|396,23→336,15s|2444,89→3165,93|2445,08→3166,26|118,31MB|

Velocidades oscilaram normalmente; cada painel mostra sua respectiva instância. Um minuto não homologa operação42h.

## Captura e qualidade

Os dois Godot renderizam **1080×1920**; a janela de prévia mede540×960. Não foi comprovado nesta execução qual textura/resolução chega à codificação efetiva de cada capturador.

Configuração OBS `JOGI-Kwai`: fonte exclusiva `JOGI-Kwai.exe`, áudio do aplicativo, crop zero e enquadramento1080×1920. Sem dispositivo global de microfone/desktop nessa coleção. Perfil selecionado `kwai live`: modoSimple, StreamEncoderNVENC,60FPS, vídeo10000kbps, áudio160kbps, canvas/saída1080×1920. ConfiguraçõesAdvanced/x264 presentes no arquivo não são o modo ativo. Destino e chaveRTMP preservados.

Não foi feita nova gravação OBS/Studio nem transmissão. Qualidade após compressão e recortes introduzidos pela interface móvel continuam exigindo inspeção da saída real. Para evitar corte manual, ajustar à tela mantendo proporção, sem esticar nem preencher cortando bordas. Prévia pequena não comprova baixa qualidade final.

## Dependências externas

TikTok @nostalgiia.br: **waiting_room**, backend/Godot saudáveis. Consulta offline espaçada120s; inconclusiva300s e HTTP429 respeita cooldown, com recuperação automática. Não foi reiniciado repetidamente para acelerar descoberta. Comentários reais comprovados anteriormente em @xinka_ não comprovam eventos reais nesta nova conta.

Kwai: webhook8786 ativo/autenticado, Chromium e perfil persistente preservados, sem rejeições de autenticação no receptor. URL configurada redireciona para **perfil**, sem chat/vídeo/WebSocket de eventos identificado. `waiting_room` significa nenhum feed comprovado; sozinho, não prova LIVE offline ou validade dos cookies na plataforma. Homologação ainda exige sala legítima acessível com feed e sua URL, quando não houver âncora com propriedade comprovada. Não existe captura de esquema binário real que permita prometer suporte universal ao protocolo Kwai.

Comentários, curtidas, seguidores, compartilhamentos, presentes e combos **reais** ainda dependem de sala disponível e autorizada. Testes internos não os homologam. Prontidão local não autoriza estreia pública nem dispensa regras das plataformas/conformidade eleitoral.

## Uso imediato

Jogos e painéis já abertos. Na próxima abertura: `ABRIR_TIKTOK.cmd`, `ABRIR_KWAI.cmd` (ou `ABRIR_DUAS_LIVES.cmd`) e `ABRIR_PAINEIS.cmd`. Nenhum atalho inicia transmissão. Não abrir outro launcher para a sessão já ativa. Encerramento local permanece26/10/2026 às07h Brasília; isso não promete encerrar OBS/Studio automaticamente.

## Recuperação adicional do renderizador

A inspeção final encontrou o TikTok20536 sem responder e sem conexão Godot, embora seu processo continuasse vivo. O log do motor registrou `VK_ERROR_OUT_OF_HOST_MEMORY` em `command_queue_execute_and_present`: falha de apresentação Vulkan. O Kwai35376 continuou a60FPS e avançou de rodada. O supervisor existente detecta saída de processo, mas não recuperava sozinho esse travamento com processo vivo; portanto, não está homologada operação sem supervisão.

Checkpoint/journal TikTok e banco foram copiados para `LOCALAPPDATA/JOGI/backups/tiktok-render-recovery-20261025-094219`, com JSON válido, SQLite íntegro e zero presentes pendentes. Fechamento normal foi tentado uma vez e não respondeu. Somente esse PID foi encerrado após verificar nome e pai; o supervisor reabriu o TikTok5576 a partir do último checkpoint. Backend, coletor, navegador e Kwai não foram reiniciados. Não se iniciou partida do zero; a rodada1 e seu progresso persistido foram recuperados. A recuperação usa o último checkpoint, não inventa os frames não persistidos.

Direct3D12 foi exercitado em teste GPU isolado na RTX4060, mantendo **Forward+**, qualidade e efeitos. As oito combinações de tier/equipe, neutralidade e duplicados passaram, com nove capturas. O projeto Windows agora seleciona `rendering_device/driver.windows=d3d12`. Log da instância reaberta confirma D3D12/Forward+; o Kwai que já estava funcionando continuou em Vulkan sem interrupção. Em sua próxima abertura, o projeto também usará D3D12.

Ver `evidencias/producao/dual-after-render-recovery.json`: inclui explicitamente o intervalo desconectado de manutenção e a recuperação subsequente, telemetria recente, distância e cronômetro avançando a60FPS e sem pendências. Essa amostra curta não prova eliminação de toda falha de driver nem estabilidade42h. Capturas D3D12 são fixtures TESTE LOCAL; não foram exibidas numa LIVE pública.
