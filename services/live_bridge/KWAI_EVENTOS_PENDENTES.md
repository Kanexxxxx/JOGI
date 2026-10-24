# Kwai: bloqueio de eventos e caminho possível — 24/10/2026

O usuário confirmou que as duas contas permitem live e presentes. Isso resolve
a elegibilidade declarada; não fornece automaticamente acesso programático aos eventos.

Há documentação oficial **Kuaishou SmallPlay** de callbacks para presentes,
comentários, likes, follows e shares. Ela exige cadastro/app, credenciais,
permissões liberadas pela plataforma, vínculo da sala por `roomCode` e callback
HTTPS com assinatura. A identificação da mensagem e os valores unitário/total
estão documentados. Não obtive evidência de que a conta **Kwai Brasil** possa
usar esse produto do portal Kuaishou com o acesso atual. Isso precisa ser
confirmado pela plataforma/integração aprovada. [Documentação oficial](https://open.kuaishou.com/miniPlayDocs/technologyrelated/Affiliatedability/basicability/localdevelopment.html).

O portal internacional encontrado é **Kwai for Business Marketing API**; sua
existência não comprova uma API de presentes/chat de live para o jogo.
[Portal oficial](https://developers.kwai.com/). A página de criadores confirma
o recurso de presentes, sem apresentar esse acesso técnico.
[Kwai for creators](https://www.kwai.com/creators/earn).

No projeto, `127.0.0.1:8786/webhook/kwai` é apenas um receptor passivo local.
Faltam um produtor autorizado de eventos da sala, IDs estáveis e valores reais,
mais a autenticação/verificação do transporte escolhido. Um callback da nuvem
não alcança diretamente um endereço de loopback; nenhum endpoint público foi
publicado e nenhum app/parceria regional foi aprovado nesta tarefa.

Alternativa viável hoje: TikTok com o SDK preparado; no Kwai, transmitir a imagem
do jogo e operar interações manualmente, identificadas como operação/teste, ou
conectar um integrador já autorizado e documentado que entregue eventos ao bridge.
Isso não equivale a duas plataformas totalmente automatizadas. Sem esse produtor,
a automação de comentários/presentes do Kwai é um bloqueio técnico real.

Não comprei serviço, acessei conta, extraí cookie, usei OCR como prova de presentes
nem inventei conexão. O painel informa `kwai_requires_collector`.
