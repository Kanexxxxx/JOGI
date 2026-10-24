# Checklist pré-live — JOGI

Data: __________ Operador: __________ Conta TikTok: **@xinka_** Conta Kwai: **@mentalista..**

**Situação em 24/10/2026: estreia pública bloqueada até avaliação jurídica e confirmação das políticas. Este checklist prepara testes locais; não autoriza clicar em Iniciar LIVE.** Consulte [conformidade](CONFORMIDADE_ELEITORAL_2026-10-24.md) e o [guia completo](GUIA_COMPLETO_OPERACAO_LIVES.md).

## Antes de abrir

- [ ] Pasta correta e atalhos presentes; Godot, Python .venv e Node encontrados.
- [ ] Internet, relógio/fuso de Brasília e energia conferidos; PC sem suspensão programada para a sessão.
- [ ] Sessão antiga identificada; sem encerrar processos desconhecidos ou apagar dados.
- [ ] Portas 8765, 8766 e 8786 sem conflitos não esclarecidos.
- [ ] Dados da conta antiga TikTok preservados e separados da @xinka_.

## Jogo e administração

- [ ] Prévia abre; personagens, capas, cenário, HUD e fontes legíveis.
- [ ] Atalho adequado usado uma única vez: TikTok, Kwai ou Duas Lives.
- [ ] Backend TikTok responde em http://127.0.0.1:8765/admin.
- [ ] Backend Kwai responde em http://127.0.0.1:8766/admin.
- [ ] Plataforma/conta corretas em cada painel; credenciais administrativas privadas.
- [ ] Godot conectado e telemetria recente nos dois painéis.
- [ ] Comando local retorna aplicado, não somente pendente.
- [ ] Modo production confirmado; simulador indisponível; sem usuários/eventos fictícios ou aviso de teste na saída definitiva.
- [ ] Três metas configuradas e confirmadas; quantidade de presentes separada de moedas.
- [ ] Seguidores exibidos como sessão/base manual quando o total real não está disponível.
- [ ] Quatro ações e catálogo observado revisados; ranking e ícones com fallback correto.
- [ ] Fila de presentes e estado de recuperação conferidos; nenhuma pendência ignorada.

## Captura e áudio — apenas prévia/gravação local nesta etapa

- [ ] Conta autenticada manualmente e permissões efetivamente verificadas no aplicativo TikTok.
- [ ] Conta autenticada manualmente e permissões efetivamente verificadas na ferramenta Kwai.
- [ ] Cena de cada plataforma captura somente seu Godot, sem painel, terminal, login ou notificações.
- [ ] Composição 9:16; saída 1080×1920 quando suportada; sem corte ou distorção.
- [ ] FPS/codificador e qualidade conferidos no aplicativo real, com hardware e upload compatíveis.
- [ ] Áudio de cada instância isolado; sem eco, narração duplicada, saturação ou microfone involuntário.
- [ ] Se houver câmera virtual OBS, áudio configurado separadamente.
- [ ] Gravação local de 60–120 s reproduzida e aprovada: imagem, som e efeitos.
- [ ] Duas rotas/destinos realmente independentes; duas cenas OBS não presumidas como dois envios.
- [ ] Desempenho estável com os dois jogos e os capturadores abertos; estatísticas OBS verificadas.

## Coletores e eventos reais — pendências externas até homologação autorizada

- [ ] Coletor TikTok da @xinka_ confirma sala real; reconectando não tratado como sucesso.
- [ ] Coletor Kwai autenticado, perfil dedicado liberado e URL real de sala conferida.
- [ ] Webhook Kwai ativo distinguido de conexão à sala.
- [ ] Em sala legalmente autorizada: curtidas, comentários 13/22 e seguidores homologados.
- [ ] Em sala legalmente autorizada e com decisão expressa de gasto: presente real/combos, moedas, identidade, efeito e ACK único homologados.
- [ ] Eventos de uma plataforma não alteram a outra; reconexão não duplica presentes confirmados.
- [ ] Ausências de imagem/valor tratadas honestamente, sem inventar dados.

## Encerramento e autorização

- [ ] Horário efetivo conferido nos dois painéis: padrão **26/10/2026, 07:00 Brasília**.
- [ ] Sei que Encerrar experiência é terminal e não se desfaz apagando arquivos.
- [ ] Sei onde ficam os logs/estado indicados pelo launcher e como preservar backup consistente.
- [ ] Sei que presentes após encerramento ficam retidos, sem efeito automático numa nova sessão.
- [ ] Sei encerrar processos próprios com Ctrl+C e parar separadamente eventual transmissão externa.
- [ ] Avaliação jurídica específica e políticas TikTok/Kwai confirmadas; rótulo IA não usado como autorização.
- [ ] Autorização explícita do operador para início público obtida **apenas depois** dos bloqueios resolvidos.

Pendências / evidência / responsável: __________________________________________

**Não marcar como aprovado um item apenas porque o código, uma simulação ou um teste isolado passou.**
