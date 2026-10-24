# Plano de execução sem gasto — 23/10/2026

Restrição explícita do usuário: **não gastar dinheiro com o projeto**. Não contratar plano, recarregar crédito nem ativar assinatura/trial que exija pagamento. Créditos gratuitos existentes podem servir para testes, respeitando exportação e licença. Nenhuma compra ou geração 3D foi feita nesta pesquisa.

## Caminho recomendado

**Meshy 6 Lite gratuito → Blender → Mixamo ou rig local → GLB → Godot.** Fazer primeiro um personagem completo para provar qualidade, download, animação e importação, antes de gerar o outro.

Estado verificado ao vivo: abriu-se `https://www.meshy.ai/pt-BR/workspace`; há Entrar/Inscreva-se grátis, sem sessão autenticada identificada. A opção **Meshy 6 Lite** existe, foi selecionada e a tela mostra **10 créditos**, licença **CC BY 4.0**. Não houve upload nem geração. O custo de textura/pós-processamento não está incluído como confirmado nesse valor.

Documentação específica do plano gratuito: 100 créditos mensais e 10 downloads mensais de modelos **6 Lite**, com uso comercial permitido mediante atribuição. Modelos de versões 6/7 exigem plano pago para download; não gastar cota nessas versões para este teste. A exportação efetiva da conta e os formatos disponíveis ainda devem ser comprovados depois do login e da geração; selecionar Lite é pré-requisito, não prova de download.

Fonte: https://help.meshy.ai/en/articles/15696428-what-is-included-on-the-free-plan . A página sobre dificuldades de download confirma restrição para 6/7: https://help.meshy.ai/en/articles/10421033-why-can-t-i-download-my-model . Há textos genéricos antigos que parecem contradizer o detalhe do Lite; usar a tela real e completar um download para decidir viabilidade.

## Animação e capa

Mixamo é gratuito com Adobe ID e permite uso dos personagens/animações em jogos comerciais, conforme https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html . Isso não transfere direitos de um modelo externo com licença restrita.

A documentação alerta para proporções muito deformadas e grandes roupas/apêndices. Por isso testar primeiro o corpo humanoide; separar capa do rig automático se a malha permitir, animando o tecido no Blender/Godot. Não prometer rig automático funcional para a capa ou rosto. Não serão aceitos personagens genéricos como substituição silenciosa dos conceitos aprovados.

Blender executável confirmado nesta execução: **5.2.2 LTS**. Pode ser usado para limpeza de malha, materiais, esqueleto, animação e exportação sem créditos de geração. A fidelidade facial continuará precisando de inspeção e ajustes; a gratuidade não garante resultado equivalente às imagens conceituais.

## Alternativas

| Caminho | Uso viável agora | Limite |
|---|---|---|
| Tripo H2.5 com os 200 créditos existentes | Teste técnico local não comercial | Plano Free limita exportação a H2.5; guia comercial não concede uso comercial no Free |
| Meshy 6 Lite | Primeiro candidato a pipeline gratuito para a live, com atribuição | Login e download efetivo pendentes; não usar versões de exportação paga |
| Blender local | Correções, rig, animação; também modelagem própria | Trabalho técnico/artístico maior; não é botão que reconstrói rosto automaticamente |
| Hunyuan3D local ou demo | Pesquisa secundária | Instalação pesada e exigência de hardware; demo online ainda não testada |

Tripo: o guia específico de uso comercial informa que Free não concede esse uso, diferente de alguns resumos de marketing. Como o projeto será monetizado com presentes, não adotar seus modelos gratuitos como assets finais sem licença adequada. Fonte: https://www.tripo3d.ai/help/privacy-policy/how-to-use-tripo-models-commercially . Saldo Studio é separado do saldo API; nada será recarregado.

Hunyuan3D-2.1 oficial declara 10 GB de VRAM para geometria e 21 GB para textura; a GPU local foi verificada como RTX 4060 com **8188 MiB** via nvidia-smi. Portanto não priorizar a instalação padrão local antes do prazo. Variantes/offload não foram avaliados nem instalados. Fonte: https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1 .

## Primeiro teste de aceite

1. Usuário entra no Meshy; confirmar saldo gratuito, versão Lite e condições sem cartão.
2. Gerar somente Lula a partir de `assets/modeling-inputs/lula-front-tpose-v1.png`, com cota gratuita e sem upgrades; conferir preço mostrado antes da geração.
3. Baixar um arquivo de malha com textura utilizável. Se surgir paywall, interromper essa rota, sem assinatura.
4. Inspecionar semelhança facial, membros e separação da capa no Blender; corrigir defeitos relevantes.
5. Produzir/aplicar pelo menos corrida e queda, exportar GLB e testar no Godot.
6. Só repetir para Flávio quando esse caminho inteiro estiver comprovado.

O teste ainda **não ocorreu**: falta sessão Meshy. A pesquisa e seleção de versão ocorreram. Não confundir tela de exemplo do site com modelo produzido pelo projeto.
