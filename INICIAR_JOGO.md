# Abrir o jogo

1. Para ver os bonecos, pista e animação sem contas conectadas, abra **ABRIR_PREVIA_JOGO.cmd**. A tela identifica o teste local; não gera público nem presentes fictícios.
2. Para a sessão TikTok, abra **ABRIR_TIKTOK.cmd**. Jogo e painel ficam separados da sessão Kwai. Painel: <http://127.0.0.1:8765/admin>.
3. Para a sessão Kwai, abra **ABRIR_KWAI.cmd**. Painel: <http://127.0.0.1:8766/admin>. **O coletor de comentários/presentes do Kwai ainda precisa ser conectado.** Acesso ao Kwai Studio e permissão para receber presentes não comprovam essa conexão.
4. Para abrir as duas sessões, use apenas **ABRIR_DUAS_LIVES.cmd**, sem abrir também os atalhos individuais.

Os atalhos não iniciam a transmissão. Mantenha a janela do supervisor aberta durante a operação; Ctrl+C encerra seus processos. Se uma porta estiver ocupada, o supervisor preserva o processo existente e informa que precisa de atenção.

No OBS/TikTok Studio, capture a janela **Corrida Presidencial - Tiktok** ou **Corrida Presidencial - Kwai**, conforme a conta. Use tela vertical **1080 × 1920**. Confirme imagem e áudio em uma gravação local antes de clicar em transmitir. A captura e o áudio no OBS ainda não foram validados nesta etapa.

## Interação

- Comentários **13** e **22** escolhem a equipe e dão impulsos pequenos com intervalo por pessoa.
- Presentes usam o valor recebido da plataforma. O painel aprende os IDs observados; permite escolher impulso, escudo, ataque ou super turbo por presente. Sem preço recebido, o sistema não inventa moedas.
- Top 5 de presentes durante a corrida; Top 3 dos mesmos apoiadores entre rodadas.
- Cada rodada dura **10 minutos**. Vence quem percorreu mais metros. Após 50 rodadas, começa um novo ciclo.
- O painel controla pausa, continuação, reinício, ações de teste e meta da live. Eventos de teste são simulações locais e não comprovam recebimento real de presentes.

## Recuperação e limites verificados

As sessões usam pastas independentes, checkpoint e diário de presentes. O supervisor reinicia somente o processo que falhou, com limite para falhas repetidas. Isso reduz perdas, mas não substitui um ensaio completo de 32 horas, ainda pendente.

Godot instalado esperado: `C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`. Nenhum atalho instala programas ou altera contas.
