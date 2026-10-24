# Guia completo de operação — JOGI

Revisão: 24/10/2026. Pasta do projeto: `C:\Users\Kanex\OneDrive\Desktop\JOGI`.

**Uso permitido nesta preparação: prévia, configuração e gravação local. A estreia pública continua bloqueada pela análise de conformidade eleitoral e pelas verificações externas pendentes.** Leia [CONFORMIDADE_ELEITORAL_2026-10-24.md](CONFORMIDADE_ELEITORAL_2026-10-24.md). O jogo usa figuras públicas sintetizadas; o rótulo de IA não substitui essa avaliação. Não clique em “Iniciar LIVE” durante os testes deste guia.

Contas de referência: TikTok **@xinka_**; Kwai **@mentalista..**, com dois pontos finais. Uma sessão antiga pode continuar identificada como @nostalgiia.br: isso precisa ser resolvido antes de operar a nova conta. Não aproveite automaticamente seus rankings, presentes ou credenciais.

## A — Preparar o computador

1. Abra o Explorador de Arquivos, cole `C:\Users\Kanex\OneDrive\Desktop\JOGI` na barra de endereço e pressione Enter. Os arquivos `.cmd` são os atalhos de operação. Ative **Exibir → Mostrar → Extensões de nomes de arquivos** se não conseguir distingui-los.
2. Os requisitos encontrados neste PC são Godot **4.7.2**, Python **3.14.7** no ambiente virtual do backend, Node.js **24**, OBS Studio **33** e RTX **4060 de 8 GB**. Blender, GDA e Tripo são ferramentas de desenvolvimento; você não precisa abri-las para jogar. Não reinstale tudo para resolver um único erro.
3. Caminhos usados: Godot em `C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`; Python em `services\live_bridge\.venv\Scripts\python.exe`; Node em `C:\Program Files\nodejs\node.exe`; OBS em `C:\Program Files\obs-studio\bin\64bit\obs64.exe`. Não mova a pasta do Godot enquanto os atalhos apontarem para ela. O comando genérico `python` pode abrir a Microsoft Store; os atalhos usam o interpretador real.
4. Antes de abrir outra sessão, procure janelas antigas do JOGI e terminais dos atalhos. Abra os dois painéis indicados na etapa F e confira plataforma, conta e fila de presentes. **Não finalize um Python qualquer pelo Gerenciador de Tarefas.** Se identificar o terminal dono da sessão antiga, registre os dados e use Ctrl+C nele para encerramento controlado. Se não identificar a origem, guarde a mensagem de porta ocupada e peça diagnóstico.
5. Confirme internet, relógio e fuso de Brasília corretos. Não desative antivírus nem abra portas no roteador: os painéis são locais. Login nas plataformas deve ser feito por você, diretamente nos aplicativos ou navegador dedicado.
6. Deixe o PC na tomada. O supervisor solicita que o Windows permaneça acordado enquanto está em execução; confira também **Configurações → Sistema → Energia**, sobretudo se o terminal for fechado. Não suspenda nem reinicie o PC durante a sessão.
7. Feche jogos pesados e downloads dispensáveis. Preserve o formato vertical 9:16 do jogo. O monitor não precisa estar em pé; o enquadramento da captura é ajustado no software de transmissão. Faça teste local de imagem e áudio antes de qualquer operação autorizada.

## B — Abrir pela primeira vez

**Prévia local** mostra os recursos sem conectar uma live. **Produção local** abre backend, jogo e coletores; ainda não transmite vídeo. **Transmissão pública** é uma ação externa, manual, sujeita às autorizações e à conformidade.

1. Dê dois cliques em **ABRIR_PREVIA_JOGO.cmd**. Aguarde o carregamento e confira pista azul, Lula/13, Flávio/22, capas, HUD, legibilidade e movimento. A prévia usa desenvolvimento; eventos de teste não comprovam conexão com espectadores. Feche essa janela antes da captura definitiva.
2. Para somente TikTok, abra **ABRIR_TIKTOK.cmd**. Para somente Kwai, abra **ABRIR_KWAI.cmd**. Para os dois juntos, use **ABRIR_DUAS_LIVES.cmd**, sem abrir também os atalhos individuais. Deixe o terminal aberto.
3. Leia as mensagens: caminho dos logs, painel, conta e pasta de dados. Uma mensagem de “processo iniciado” ainda não comprova que o jogo conectou. Portas ocupadas exigem investigar a sessão existente; repetir duplo clique não resolve.
4. Abra o painel correto. Confirme backend respondendo, Godot conectado, telemetria recente e mudança real do cronômetro. Confira a conta antes de aceitar eventos.
5. As sessões usam portas diferentes: TikTok **8765**, Kwai **8766**, webhook local Kwai **8786**. A porta do webhook disponível não significa conexão com a sala Kwai.
6. O padrão é **production**: simulador bloqueado e sem usuários fictícios de preenchimento. Não troque para desenvolvimento para ocultar uma falha de produção. Um encerramento persistido pode impedir retomada, corretamente; veja a etapa I.

## C — Preparar o TikTok

1. Abra **TikTok LIVE Studio** pelo menu Iniciar, se instalado. Entre manualmente e confira que a conta é **@xinka_**. A conta antiga não serve como comprovação de acesso da nova.
2. Verifique no próprio aplicativo se a conta pode transmitir e receber Presentes de LIVE. O relato de acesso anterior não homologa a nova conta. Se aparecer restrição ou pedido de acesso, registre exatamente a mensagem; não contorne a restrição.
3. Crie uma cena identificada como **JOGI TikTok**. Escolha orientação vertical, quando disponível, e resolução **1080×1920**. Os nomes dos menus variam conforme versão e permissões; a configuração efetiva precisa ser conferida na tela.
4. Adicione uma fonte de captura de jogo ou janela e selecione **Corrida Presidencial - Tiktok**. Confira pelo painel correspondente. Capture somente essa janela, sem o terminal, painel administrativo ou navegador de login. Ajuste para caber inteiro sem esticar e sem cortar metas, ranking ou rodapé.
5. Configure a entrada de áudio do jogo. Use fones para ouvir a prévia. Verifique os medidores e uma gravação local. Não deixe o mesmo som chegar por captura de aplicativo e áudio geral do desktop ao mesmo tempo.
6. Comece por 60 FPS se a prévia e a codificação forem estáveis; 30 FPS é uma alternativa caso o teste com captura apresente sobrecarga. Qualidade e bitrate dependem da conexão e do limite exibido pela plataforma; não há bitrate universal aprovado neste manual.
7. Sem iniciar transmissão, revise enquadramento, conta, áudio e ausência de informações privadas. Depois, no painel TikTok, confira o estado do coletor. “Reconectando” não é “conectado”.
8. Curtidas, comentários 13/22, seguidores e presentes reais só podem ser homologados numa sala autorizada e legalmente permitida. O jogo e um SDK instalados não comprovam essa etapa. **Não se presume chave RTMP disponível.**

Na inspeção prática de 24/10, o TikTok LIVE Studio **1.38** apresentava composição horizontal preta e uma fonte antiga de Overwatch; a conta autenticada não foi confirmada. Portanto, a cena JOGI vertical, a conta @xinka_ e suas permissões continuam pendentes de configuração/validação no aplicativo. Não cole senhas ou chaves no chat.

## D — Preparar o Kwai

1. Abra a ferramenta de transmissão que sua conta realmente oferece. A página informada pelo operador é [Kwai Studio](https://studio.kwai.com/live/list). Faça login manualmente, confira **@mentalista..** e verifique acesso à preparação de LIVE e presentes. A página aberta não comprova autorização nem publicação.
2. Se houver captura de jogo/janela, selecione exclusivamente **Corrida Presidencial - Kwai**, ajuste orientação vertical e áudio. Se a ferramenta oferecer apenas outro método, documente o método disponível antes de conectar. Não invente RTMP, plug-in ou aplicativo já instalado.
3. **ABRIR_KWAI.cmd** ou **ABRIR_DUAS_LIVES.cmd** inicia o coletor local junto da sessão. Se precisar autenticar o navegador do coletor, abra **ABRIR_NAVEGADOR_KWAI.cmd** e faça login nele. Esse perfil é dedicado à coleta; não é necessariamente o mesmo do seu navegador habitual.
4. O atalho visível permite que o coletor em segundo plano ceda o perfil. Ao terminar o login, feche a janela dedicada ou use Ctrl+C no terminal desse atalho para devolver o perfil à coleta automática. Evite abrir vários navegadores dedicados simultaneamente.
5. No painel Kwai, localize a configuração da sala e informe a **URL real da sala de LIVE**, quando disponível. Um link de perfil não substitui o endereço da sala. Não exponha cookies nem credenciais.
6. Confira no painel o estado específico do coletor e da sala: necessidade de login, reconectando ou conectado. **Webhook ativo em 8786 é somente o receptor local.** O coletor Kwai continua experimental até homologação de eventos reais, incluindo presentes em sequência.
7. Se o navegador pedir verificação de segurança, conclua manualmente o fluxo permitido. Não tente burlar CAPTCHA ou bloqueios. Se houver perfil ocupado, feche primeiro a janela dedicada que você abriu; não apague cookies ou perfis como primeira tentativa.

Na inspeção prática de 24/10, **Kwai Studio instalado não foi localizado**. A página web informada pelo operador não equivale à instalação de um transmissor para PC. Login, método de captura disponível, URL real de sala e recebimento real permanecem pendências externas. Configure localmente sem iniciar uma transmissão para cumprir este guia.

## E — OBS Studio: imagem e áudio

1. Abra **OBS Studio**. Em **Perfil**, crie um perfil com nome claro, por exemplo **JOGI vertical**. Em **Coleção de cenas**, crie uma coleção JOGI. Preserve a configuração antiga antes de substituir fontes.
2. Em **Configurações → Vídeo**, defina resolução base e saída **1080×1920** e FPS **60**, se o teste com captura sustentar. As configurações visíveis devem ser conferidas; não se presume que já estejam aplicadas.
3. Crie uma cena **JOGI TikTok**. Em Fontes, adicione **Captura de jogo**, escolha a opção de capturar uma janela específica e selecione a janela TikTok do Godot. Se houver somente “qualquer aplicativo em tela cheia”, mude para janela específica. Crie outra cena **JOGI Kwai**, apontando para o outro jogo.
4. Clique com o botão direito na fonte → **Transformar → Ajustar à tela**. Confira todas as bordas e a proporção; não use “esticar” para preencher deformando os personagens. Bloqueie a fonte após ajustar.
5. Na saída de gravação, selecione NVIDIA NVENC H.264 quando estiver disponível. A RTX 4060 suporta codificação por hardware; a opção efetiva e a carga devem ser verificadas no OBS. Não altere a transmissão para um servidor/conta não verificados.
6. Para isolar as duas versões, prefira captura de áudio por aplicativo/processo, quando disponível. Cada destino deve receber apenas o áudio da instância correspondente. Se a captura do desktop já inclui esse som, desative sua duplicação na cena/rota. Mantenha a monitoração em fones e evite “monitorar e enviar” voltando ao próprio desktop.
7. Confira picos nos medidores; deixe margem abaixo de 0 dB e reduza torcida/memes antes de aumentar a narração. Desative microfone se não for usado. Faça uma **gravação local de 60–120 segundos**, com corrida e efeitos, reproduza o arquivo e procure silêncio, eco, cortes e saturação.
8. Abra **Exibir → Estatísticas** e acompanhe frames perdidos por renderização/codificação. Se estiver pesado, feche aplicativos dispensáveis e teste 30 FPS na captura antes de reduzir a legibilidade. O benchmark do jogo não incluiu codificação OBS.
9. Se a imagem ficar preta, confirme janela selecionada e jogo visível, saia de menus suspensos, recrie apenas a fonte problemática e teste **Captura de janela** como alternativa. Evite “Captura de tela” durante login ou administração, pois pode mostrar dados privados.

### Duas plataformas ao mesmo tempo

Duas cenas no OBS são alternativas de composição; isso não cria dois destinos independentes automaticamente. Use captura direta do Godot TikTok no LIVE Studio e captura direta do Godot Kwai na ferramenta Kwai, se ambas oferecerem esse recurso. Outra arquitetura exige verificar sessões de OBS/encaminhamento e isolamento de áudio; não basta duplicar cenas.

**Câmera virtual do OBS transporta vídeo, não o áudio do jogo.** Se uma plataforma aceitar a câmera virtual, a entrada de áudio precisa ser configurada e testada separadamente. Não habilite captura global que misture os dois narradores. Não há instalação automática de plugins nem garantia de transmissão simultânea independente nesta etapa.

Até a inspeção prática dos aplicativos e da gravação final, captura, NVENC, roteamento e permissões são itens pendentes, não configurações aprovadas.

## F — Usar os painéis

- TikTok: [http://127.0.0.1:8765/admin](http://127.0.0.1:8765/admin).
- Kwai: [http://127.0.0.1:8766/admin](http://127.0.0.1:8766/admin).

1. Confira o identificador da plataforma. Os painéis controlam somente sua própria origem/porta. Não abra uma URL de painel enviada por espectador.
2. Se aparecer autenticação, use a credencial administrativa local. O launcher informa a localização de **operator-token.key** na pasta privada de estado, fora do repositório. Abra esse arquivo localmente e copie seu conteúdo somente para o campo do painel correspondente. Não fotografe, registre em logs, cole em URL ou envie no chat. Os tokens de motor e coletor têm funções diferentes e não substituem o de operador.
3. Antes de comandar, confira backend, Godot conectado e telemetria recente. “Desconectado” ou informação antiga bloqueia os controles de corrida por segurança. A exceção é Encerrar experiência: a ponte preserva essa decisão e o Godot a aplica ao reconectar.
4. Use os controles de largada/lobby conforme o estado mostrado. **Pausar** interrompe a corrida; **continuar** retoma. **Reiniciar rodada** exige confirmação e não apaga o histórico durável de presentes. A rodada dura 10 minutos; são 50 rodadas por ciclo e 30 segundos de intervalo.
5. Configure as três metas e clique **Aplicar 3 metas simultâneas**. Curtidas, quantidade de presentes e seguidores são métricas distintas; moedas não são quantidade de presentes. Sem total de seguidores fornecido pela plataforma, o painel exibe novos seguidores da sessão; uma base inserida por você fica identificada como manual.
6. No catálogo, selecione um presente já observado e configure a ação para os próximos eventos: impulso, escudo, ataque ou super turbo. O catálogo contém os presentes recebidos, não uma lista oficial completa de todos os presentes possíveis. Salvar uma regra não executa um efeito retroativo.
7. Em eventos recentes, confira origem, ID/nome, quantidade e moedas quando conhecidas. Em caso de valor ausente, não estime preço nem receita. O Top 5 usa moedas; quantidade aparece separadamente. A falta de avatar/ícone pode resultar em inicial ou símbolo neutro, sem inventar identidade.
8. Em **Áudio e apresentação**, ajuste Narração, Efeitos, Torcida e Memes revisados e aplique. A alteração precisa voltar confirmada pelo jogo.
9. Veja os recibos: **queued/pendente** significa recebido pela ponte; **applied/aplicado** significa executado pelo Godot; **rejected/rejeitado** informa recusa. **timeout/desconectado** não comprova execução. Não repita um comando pendente às cegas.
10. **Encerrar experiência com segurança** é terminal para aquela sessão. Use a etapa I; não confunda com pausar ou fechar a janela.

Presentes têm estados próprios: `queued` aguardando, `dispatched` enviados, `confirmed` confirmados duravelmente pelo jogo, `duplicate` repetidos, `rejected` recusados e `after_close_pending` preservados após encerramento. Um evento na lista ainda não significa efeito confirmado.

## G — Validar interações

Faça primeiro o teste isolado de desenvolvimento. Depois, apenas com sala autorizada e condições legais, homologue eventos reais. Não envie dinheiro para testar sem decisão expressa do operador.

| Conferência | O que observar | Limite da evidência local |
|---|---|---|
| Curtidas | Contador e meta sobem na plataforma correta | Simulação não prova recepção real |
| Comentários 13/22 | Nome sanitizado, equipe correta e movimento correspondente | Verificar moderação/entrega da plataforma |
| Seguidores | Novos seguidores e meta coerentes | Total do perfil não é presumido |
| Presentes | ID, quantidade, moedas conhecidas, efeito e confirmação | Combos e valores exigem homologação por plataforma |
| Retratos e ícones | Imagem local ou fallback neutro | CDN externa pode falhar/omitir imagem |
| Quatro ações | Impulso acelera; escudo protege; ataque atinge rival; turbo tem efeito próprio | Teste não autoriza gasto nem transmissão |
| Ranking | Moedas acumulam para a identidade correta; sem duplicar reenvio | Confirmar identidade do coletor real |
| Recuperação | Presente confirmado não pontua de novo; pendente permanece rastreável | Nem toda interação gratuita é durável |
| Isolamento | Evento TikTok não altera Kwai e vice-versa | Repetir com software de captura ligado |

Registre data, plataforma, ID do evento, resultado e referência do log; não registre tokens ou cookies. Eventos gratuitos em memória podem ser perdidos numa queda abrupta. A garantia de persistência dos presentes confirmados não é uma garantia de recuperar todo comentário ou curtida.

## H — Operação avançada e recuperação

### Monitoramento e sessões longas

Acompanhe o Gerenciador de Tarefas (Ctrl+Shift+Esc) para CPU, memória e GPU, o FPS/telemetria do painel e as estatísticas do OBS. Registre consumo inicial e compare ao longo da operação. Não prometa 42 horas sem ensaio correspondente. Evite atualizações/reinícios e troca de dispositivos de áudio durante a sessão.

Se houver lentidão, confirme primeiro se é renderização, codificação ou internet. Reduza aplicativos extras e efeitos/captura apenas após registrar o estado. Não diminua buffers/limites da fila de presentes para esconder acúmulo. Frames perdidos por rede no OBS não significam necessariamente FPS ruim no Godot.

### Queda de rede ou processo

1. Mantenha o jogo e a ponte abertos se estiverem saudáveis. Os coletores tentam reconectar; acompanhe o estado real, sem considerar uma tentativa como sucesso.
2. Se um processo falhar, registre horário, plataforma, mensagem e fila. O supervisor pode recuperar processos sob seu controle, desde que a experiência não esteja encerrada. Não abra um segundo launcher sobre o primeiro.
3. Se precisar reiniciar manualmente, identifique o terminal proprietário, use Ctrl+C e aguarde suas portas serem liberadas. Preserve toda a pasta de estado informada pelo launcher antes de intervenção técnica. Reabra o mesmo atalho, para a mesma conta/modo.
4. Confira identidade, checkpoint, histórico, fila e ACKs. Não use “limpar deduplicação” para forçar um presente já confirmado a reaparecer. Não recrie um evento pago manualmente sem conciliação do ID original.
5. Se houver dados antigos sem conta/modo identificáveis, o bloqueio de migração evita misturar sessões. Faça inventário e backup antes de classificar/restaurar. Não renomeie nem apague arquivos para vencer o bloqueio.

### Logs, backup e restauração

O launcher mostra a pasta privada de estado em `%LOCALAPPDATA%\JOGI\live_bridge\...` e os logs `bridge-<data-hora>.log`; Kwai também possui log do coletor. Use o caminho impresso pela execução atual, pois conta e modo fazem parte do isolamento. Os checkpoints Godot ficam no armazenamento de usuário do Godot: `user://sessions/<modo>/accounts/<identificador-da-conta>/<plataforma>`. O identificador é um hash reduzido da conta normalizada, não sua senha. Dados antigos sem conta são bloqueados para classificação; não são migrados automaticamente. Esses checkpoints não são os arquivos `.tscn` do projeto.

Para abrir LOCALAPPDATA, pressione Win+R, digite `%LOCALAPPDATA%\JOGI` e confirme. Para localizar dados Godot, use Win+R e `%APPDATA%\Godot\app_userdata`, localizando a pasta do nome do projeto e suas sessões. Não copie um banco SQLite ativo isoladamente: use uma ferramenta de backup SQLite ou encerre controladamente os processos e preserve a pasta completa, incluindo eventuais arquivos auxiliares do banco.

Mantenha backup fora da pasta publicada: estado backend, sessões Godot correspondentes, configuração relevante e logs da mesma conta/modo. Não compartilhe o arquivo de token nem perfis/cookies de navegador. Uma restauração exige conta, modo, versão e momento compatíveis; preserve também uma cópia do estado atual antes de substituir qualquer dado. Não há botão universal de restauração homologado: solicite recuperação assistida quando houver presentes pendentes ou dados legados.

O painel deve continuar em `127.0.0.1`; não exponha portas por túnel ou roteador. Não desative a autenticação por ser localhost. Outra pessoa/processo no PC pode tentar acessar o serviço. Guarde credenciais apenas nos locais privados indicados.

## I — Encerrar

O horário padrão configurado é **26/10/2026 às 07:00 de Brasília**, expresso como `2026-10-26T07:00:00-03:00`. Confira o horário efetivo em **Encerramento operacional** nos dois painéis e no plano do launcher. Esse horário não autoriza a transmissão durante a janela eleitoral.

Antes de uma nova operação ainda não encerrada, um técnico pode configurar `JOGI_END_AT` com data, segundos e fuso explícitos. Exemplo de inspeção sem iniciar processos, no PowerShell aberto na pasta do projeto:

```powershell
& '.\services\live_bridge\.venv\Scripts\python.exe' '.\tools\run_live_instances.py' --both --mode production --check
```

Não altere o horário para contornar um encerramento já persistido. Alterar ambiente, atualizar a página ou clicar em reiniciar não desfaz a decisão terminal. Uma nova experiência exige planejamento e recuperação/classificação assistida, preservando os presentes anteriores.

1. Para terminar manualmente, use **Encerrar experiência com segurança** em cada painel e confirme a consequência. Aguarde estado encerrado e recibo aplicado; se o Godot estiver offline, a ponte preserva a decisão e o jogo deve encerrá-la ao reconectar.
2. Confira que cronômetro/rodadas não retomam e que comandos de largada/continuação estão bloqueados. Presentes pendentes permanecem registrados; eventos pagos recebidos após o fechamento ficam retidos como `after_close_pending`, sem descarte silencioso e sem efeito automático numa nova sessão.
3. Pare **manualmente** qualquer transmissão externa no TikTok, Kwai e/ou OBS, se existia uma transmissão autorizada. Encerrar JOGI não encerra a live nem o computador. Verifique os indicadores de cada aplicativo.
4. Pare gravação local, salve seu arquivo, registre filas e logs. Use Ctrl+C no terminal do launcher para encerrar os processos criados por ele. Feche o navegador dedicado quando apropriado. Preserve dados para conciliação.

## Problemas e soluções

| Sintoma | Causa provável | Como verificar | Como resolver | Como confirmar |
|---|---|---|---|---|
| Jogo não abre | Executável/caminho ausente ou bloqueio diagnosticado | Leia terminal e confira caminhos da etapa A | Corrija somente o requisito apontado; preserve a janela de erro | Jogo visível e telemetria recente |
| Janela abre e fecha | Exceção, recurso ou estado inválido | Consulte o último log e horário | Registre mensagem completa; use prévia/diagnóstico para separar recurso e produção | Processo permanece e painel confirma conexão |
| Godot preto | Carregamento, renderização ou captura equivocada | Compare janela Godot com imagem no capturador | Aguarde carga inicial; se só captura está preta, ajuste fonte; se Godot também, preserve log para diagnóstico gráfico | Cena aparece no Godot e captura |
| Python não encontrado | Atalho/caminho .venv removido; alias Store | Confira `.venv\Scripts\python.exe` | Use o atalho do projeto; restaure ambiente específico assistidamente, sem instalação global | Diagnóstico encontra interpretador e backend responde |
| Backend não inicia | Dependência, configuração ou porta | Log da plataforma e mensagem do launcher | Corrija causa indicada; não substitua banco por vazio | Painel e `/health` respondem |
| Porta ocupada | Sessão anterior ou outro programa | Confira 8765/8766/8786 e identidade da sessão | Identifique proprietário e encerre pelo terminal correto, após preservar dados | Nova sessão usa a conta correta sem conflito |
| Painel não carrega | Backend ausente ou endereço errado | Use URL exata da plataforma | Abra atalho correspondente; não tente porta aleatória | Página correta carregada |
| Painel sem Godot | Jogo caiu, credencial do motor ou telemetria antiga | Indicadores e log de conexão | Aguarde recuperação do supervisor; diagnostique autenticação/cena se persistir | Conectado e telemetria atual |
| Erro de autenticação | Token de outra plataforma/sessão | Confira caminho privado mostrado pelo launcher | Use somente token administrativo atual no campo local; recarregue/autentique | Painel obtém estado e recibo real |
| TikTok/Kwai offline | Sala não disponível, login/permissão ou rede | Estado específico do coletor e conta | Resolva acesso manualmente; aguarde reconexão sem burlar restrições | Coletor confirma sala real; evento autorizado é recebido |
| Kwai exige login | Perfil dedicado não autenticado | Mensagem do coletor | Abra ABRIR_NAVEGADOR_KWAI.cmd, autentique e feche para devolver perfil | Estado deixa necessidade de login |
| Presentes não aparecem | Sem sala real, ação não mapeada ou fila pendente | ID no coletor, painel e estados de processamento | Diferencie ausência de recepção e pendência; preserve ID para conciliar | Mesmo ID confirmado uma única vez |
| Fotos/ícones ausentes | Plataforma não forneceu ou cache/CDN falhou | Campo e diagnóstico do cache | Aceite fallback; investigue domínio/rede sem desativar validação | Imagem legítima ou fallback estável |
| Sem áudio | Saída errada, mudo, opção desativada ou captura só vídeo | Painel, mixer Windows e medidor do capturador | Ative som necessário e selecione entrada/saída correta | Gravação local reproduz som |
| Eco/vozes duplicadas | Áudio desktop + aplicativo ou duas instâncias | Desative uma fonte de cada vez na prévia | Isole processo por destino e use fones | Gravação tem uma única narração |
| OBS preto | Fonte em tela cheia ou janela errada | Propriedades da Captura de jogo | Selecione janela específica; teste Captura de janela | Gravação mostra cena completa |
| FPS baixo | GPU/RAM/codificação sobrecarregada | Painel, Tarefas e Estatísticas OBS | Feche carga extra; teste captura 30 FPS e NVENC disponível | Teste local estável com duas instâncias |
| Estado antigo bloqueia início | Arquivos legados ou conta anterior | Mensagem cita estado/conta e caminho | Preserve pastas; classifique/migre assistidamente | Conta/modo inequívocos e fila conciliada |
| Encerrado e não reinicia | Estado terminal persistido | Encerramento operacional e razão | Comportamento esperado; não apague estado nem force restart | Sem novas rodadas; pendências preservadas |

## O que foi verificado e o que falta

Os testes documentados exercitaram duas instâncias locais, painel autenticado, comandos confirmados pelo Godot, isolamento, persistência e carga sintética. O ensaio GPU simultâneo de 620 segundos atingiu aproximadamente 60 FPS em 1080×1920 sem OBS/codificação. Há também carga de backend e ensaio GPU com mil identidades sintéticas por plataforma. Consulte [TESTES_FINAIS.md](TESTES_FINAIS.md) e `docs/evidencias/` para os relatórios e seus limites.

Isso **não certifica 42 horas**, acesso da nova conta TikTok, captura/áudio final nos aplicativos, conexão real Kwai, recebimento real de presentes ou autorização pública. O procedimento completo deve ser marcado no [CHECKLIST_PRE_LIVE.md](CHECKLIST_PRE_LIVE.md), registrando essas pendências. A preparação dos aplicativos só fica aprovada quando houver inspeção e gravação local correspondentes.
