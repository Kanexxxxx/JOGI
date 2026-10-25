# Kwai: quatro presentes e cards maiores

Aplicado ao backend8766 e jogo Kwai, com backup e recuperação do checkpoint. TikTok e coletor/navegador Kwai não foram reiniciados para essa aplicação. Nenhuma LIVE ou compra/envio de presente foi iniciado.

## Referência fornecida pelo operador

As cinco imagens de25/10 às09:58/09:59 mostram o menu de presentes disponível ao espectador **em outra sala**. Isso serve como referência de imagem, nome visível e preço apresentado naquele menu. Não comprova disponibilidade universal nem especificamente na sala @mentalista... Não existe, nessas capturas, gift_id verificável.

| Efeito | Presente mostrado | Diamantes/unidade | Faixa preservada |
|---|---|---:|---|
|Impulso|Concha Rosa|5|T1:1–9|
|Escudo|Pérola do Mar|10|T2:10–99|
|Ataque|Gol de Rede|199|T3:100–999|
|Super Turbo|Roda-gigante|1999|T4:1000+|

Catálogo persistente: `game/assets/catalogs/kwai_gift_showcase.json`. Arquivos JPEG originais em `game/assets/gifts/kwai/`, sem edição ou arte oficial inventada. Godot usa AtlasTexture para selecionar regiões; hashes e origem em PROVENANCE.json. A imagem da roda-gigante já aparece parcialmente cortada na captura original, conservada como tal. IDs continuam null e `availability_confirmed=false`. `verified=true` se refere à referência visual/preço da captura, não à disponibilidade na conta.

A vitrine é informativa e não cria eventos, saldos ou presentes recebidos. Mecânica e finanças continuam usando o ID, valor unitário e quantidade efetivamente recebidos pelo conector. Mesma regra para ambas as equipes: escolha13/22 por identidade estável, presente sem equipe neutro, ataque ao adversário. Preço ausente não é preenchido a partir desta referência. Nenhuma compra foi necessária para preencher os quatro ícones.

## Legibilidade

Os quatro espaços passaram de uma linha de240px por card para **duas colunas de492px**, em duas linhas. Imagens44→84px, título29px, nome23px e valor21px. Ícones genéricos de habilidade, quando necessários, voltaram a ficar visíveis: um painel opaco os estava cobrindo. Chat, ranking e faixa de evento foram reposicionados para manter a área abaixo de1720px livre e não sobrepor os presentes.

A API `/api/gifts` agora também retorna a vitrine Kwai. Painel mostra diamantes e identifica a referência do menu; não declara preços não confirmados após troca de conta TikTok. F5 carrega o texto atualizado em um painel que já estava aberto.

## Validação

-6 testes Python do catálogo aprovados, incluindo isolamento TikTok/Kwai e ausência de IDs/disponibilidade inventados.
-Teste estrito Godot dedicado ao layout: cards sem interseção, tamanho492×100, ícones84×84, textos legíveis, ranking/instrução acima dos cards e limite inferior1720.
-Regressões de HUD, metas/avatares e fila de cards aprovadas.
-Teste Godot Kwai T1/T2/T3/T4 em ambas as equipes aprovado; neutralidade, valores desconhecidos, ataque ao adversário e deduplicação preservados.
-Captura GPU nativa1080×1920 do cenário isolado em `evidencias/estadio/kwai-gifts-large/kwai-gift-showcase.png`, conferida visualmente. Mostra a referência das quatro imagens; não é uma transmissão ou evento real.
-Backend atualizado, Godot conectado, telemetria recente,60FPS, persistência pronta e zero presentes pendentes: `evidencias/producao/kwai-current-showcase-active.json`.

Continuam sem homologação presentes reais na sala Kwai e disponibilidade nela dos quatro itens. O coletor reporta waiting_room/nenhum feed comprovado; a vitrine não corrige nem disfarça essa dependência externa.
