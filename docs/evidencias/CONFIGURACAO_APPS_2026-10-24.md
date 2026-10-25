# Inspeção dos aplicativos de transmissão — 24/10/2026

Inspeção local por Computer Use (`@oai/sky`), sem iniciar transmissão, instalar programas, autenticar contas ou modificar OBS. Escopo: TikTok LIVE Studio e disponibilidade do Kwai Studio. Este relatório não comprova homologação de eventos reais nem permissão de monetização.

## TikTok LIVE Studio

- Instalado e executando: **1.38.0** (ProductVersion `1.38.0.0`).
- Executável verificado: `C:\Program Files\TikTok LIVE Studio\1.38.0\TikTok LIVE Studio.exe`.
- Registro de desinstalação também confirma versão 1.38.0 e diretório de instalação.
- Janela encontrada pelo inventário, inicialmente minimizada; foi ativada e sua interface pôde ser visualizada.
- Estado observado: layout **horizontal**, cena `Tela + Câmera`, fonte antiga `Overwatch.exe` em vermelho e prévia preta. Portanto a captura do JOGI **ainda não está configurada ou comprovada**.
- A interface apresenta nome de exibição **Kanex**, mas não mostrou identificador público. Não foi possível confirmar que a sessão seja `@xinka_`.
- Controles exibem `Iniciar LIVE`, chat e espaço de presentes. Sua presença não comprova que `@xinka_` tenha LIVE e presentes habilitados.
- Rodapé indica alvo nominal de 60 FPS e envio 0 kbps, sem transmissão iniciada.
- Áudio, resolução de saída, bitrate, NVENC e ausência de eco **não foram homologados** nesta inspeção.

### Limitação prática encontrada

A árvore de acessibilidade expôs somente a janela raiz. Tentativas por coordenadas nos controles de perfil e seleção vertical, com ativação da janela e novas capturas, não produziram alteração visível. Nenhuma configuração foi declarada salva sem confirmação. Não foram usados mecanismos alternativos de injeção nem acessados arquivos de autenticação.

### Ação manual necessária

O operador deve abrir o perfil no Studio e confirmar **`@xinka_`**. Se outra conta estiver conectada, a troca e autenticação precisam ser realizadas manualmente. Depois, selecionar formato vertical 9:16, conferir saída 1080×1920 e configurar captura exclusiva da janela JOGI TikTok. Não reutilizar a fonte Overwatch nem presumir que a conta antiga seja adequada.

## Kwai

- Nenhum aplicativo nativo Kwai/Kuaishou foi encontrado no inventário de aplicativos do Computer Use, nas entradas de desinstalação HKCU/HKLM consultadas ou nos diretórios de primeiro nível de Program Files, Program Files (x86) e Local Programs. Isso não descarta instalação portátil em outro local.
- Existe `ABRIR_NAVEGADOR_KWAI.cmd`. Ele invoca `tools/kwai_live_collector.cjs` em modo visível com conta `mentalista..`, bridge `127.0.0.1:8766` e webhook `127.0.0.1:8786/webhook/kwai`.
- Esse navegador/coletor **não é um aplicativo transmissor Kwai Studio** nem prova recebimento de comentários/presentes reais.
- O launcher informa que o coletor de segundo plano cede temporariamente o perfil. Não foi executado durante esta inspeção para não interromper o coletor existente.
- A autenticação do portal, permissão real de transmissão pelo computador, disponibilidade de RTMP ou método autorizado de envio continuam pendentes de verificação com o operador. Não foi presumida chave RTMP nem instalada ferramenta.

## Critérios pendentes antes de operação

1. Confirmar manualmente `@xinka_` no Studio e LIVE/presentes dessa conta.
2. Conseguir resposta dos controles locais do Studio e salvar cena vertical própria do JOGI; validar fonte em prévia e gravação local.
3. Confirmar no portal Kwai da conta `mentalista..` qual rota de transmissão de computador está autorizada. Configuração do OBS, isoladamente, não prova destino Kwai funcional.
4. Conferir captura TikTok e captura Kwai separadas, sem capturar desktop/painel privado, e áudio sem duplicação.
5. Homologar eventos reais somente em sala autorizada e distinguir coletor ativo de sala conectada.
6. Manter início público manual e condicionado às verificações externas de conformidade descritas no projeto.

Nenhuma LIVE, instalação, geração paga ou alteração em arquivos centrais foi realizada por esta inspeção.

## Complemento do agente principal

OBS 33.0.0 foi aberto e observado sem gravação/transmissão ativa. Perfil/coleção existentes: Sem nome. Captura de jogo existente estava configurada para qualquer aplicativo em tela cheia, incompatível com a janela normal do JOGI. Não foi salva uma configuração aprovada de captura ou áudio.

O operador informou que reconheceu o Godot na prévia de captura do Studio. Naquele momento as janelas eram do benchmark temporário; isso não confirma a instância definitiva TikTok. Foram fornecidos passos para fechar seleção temporária e escolher o primeiro ícone de celular/vertical. A ferramenta conseguiu trazer o Studio à frente, mas cliques nas regiões da caixa não produziram a alteração esperada. Ação manual foi solicitada, sem iniciar LIVE. Permanecem pendentes saída1080x1920, enquadramento, conta@xinka_, FPS/codificação e áudio sem eco.
