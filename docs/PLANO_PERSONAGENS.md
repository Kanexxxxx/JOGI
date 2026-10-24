# Plano inicial dos personagens — 23/10/2026

Escopo: Lula e **Flávio Bolsonaro**, para corrida 3D pequena em vídeo vertical. Prazo de produto: 24/10 às 09:00, horário de Brasília. Este arquivo é preparação de arte; não contém modelos gerados ou conceito visual aprovado. Primeiras pranchas 2D v1 foram geradas e inspecionadas: `../assets/concepts/flavio-v1.png` e `../assets/concepts/lula-v1.png`. Prompts e limites: `../assets/concepts/GERACAO.md`.

## Critério visual pedido

Corpo estilizado e compacto, rosto com alta semelhança à pessoa correta. Não trocar a identidade por um corredor genérico com barba/cor de roupa. Não prometer reprodução facial quase idêntica sem comparar o render produzido com referências reais. Qualidade será avaliada no close da transformação e também no enquadramento normal da corrida.

Primeiro reunir referências frontais, três quartos e perfil de cada pessoa, com créditos e origem. Perfil institucional identificado para Flávio: [Senado Federal](https://www25.senado.leg.br/web/senadores/senador/-/perfil/5894). [TODO] Selecionar e inspecionar as imagens adequadas de ambos antes de alimentar o gerador; o link institucional ainda não é uma prancha multivista pronta.

## Etapas e critérios de passagem

1. Prancha de cada personagem: corpo inteiro, frente, perfil e três quartos, sem texto desenhado na roupa. Inspecionar rosto e coerência entre vistas.
2. Comparação visual dos conceitos com referências: aprovar semelhança antes de gastar em reconstrução 3D.
3. Modelo texturizado de cada um. Inspecionar rosto, mãos, cabelo, roupa e perfil. Corrigir defeitos antes do rig.
4. Rig humanoide: validar ombros, cotovelos, quadril e joelhos em corrida e queda. Confirmar formatos reais de exportação e importação no Godot.
5. Animações reutilizáveis: espera, corrida, aceleração, ataque, impacto/queda, levantar, vitória e transformação. Produzir movimentos faltantes no Blender/engine ou por retarget compatível, sem prometer que um único comando fornece todos eles.
6. Uma transformação inicial por personagem: roupa/efeitos/câmera coordenados; volta legível à corrida. Não gastar primeiro com muitas skins.
7. Medir dois jogos e encoders simultâneos antes de fixar orçamento final de polígonos/texturas. Maior malha não garante melhor imagem na live.

## Predefinição Tripo inspecionada

CLI 0.7.0. Plano de avaliação validado gratuitamente em 23/10:

```powershell
& 'C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd' make '<descrição e referência a preparar>' --for game-pc --model tripo-v3.1 --then rig --dry-run --json
```

O dry-run efetivamente executado usou uma descrição de humanoide estilizado, não fotos das pessoas. Retornou `valid:true`, modelo `v3.1-20260211`, textura `detailed`, rig `v2.5-20260210` e entregáveis previstos FBX/GLTF. Avisos: `--then` substitui a cadeia padrão; textura detailed tem faixa de preço maior. Isso valida o plano técnico, **não semelhança facial, qualidade final nem preço total**.

Para os modelos finais, preferir referência visual inspecionada ao prompt textual isolado e validar novamente o comando com os arquivos reais. Tripo documenta entrada por múltiplas vistas; investigar disponibilidade no pipeline/API utilizado antes de escolhê-la: [Multi-view to 3D](https://www.tripo3d.ai/product-doc/model-generation/multi-view-to-3d).

Não houve geração paga. Tripo doctor informou saldo API zero. Não assumir que eventual assinatura/créditos do site sejam saldo disponível para essa API. [TODO] Cotar modelo, textura, rig e animações na rota escolhida; não há estimativa monetária confirmada neste plano. Fontes de preços a conferir: [API billing](https://platform.tripo3d.ai/docs/billing) e [Studio pricing](https://www.tripo3d.ai/pricing).

## Critérios de rejeição

- Rosto genérico ou confundível com Jair em vez de Flávio.
- Vistas inconsistentes ou textura que apenas cola uma fotografia sobre geometria defeituosa.
- Corrida com membros atravessando roupa/corpo, mãos deformadas ou rig quebrado.
- Corte de câmera que esconde ação relevante ou sequência infinita de cutscenes.
- Modelo pesado sem melhoria perceptível no enquadramento de live.

## Evidências e pendências

Briefing direto do usuário; skill local tripo-cli; saída de make --help e dois dry-runs; tripo doctor; documentação oficial de múltiplas vistas e cobrança. Foram produzidos conceitos 2D v1, ainda sem aprovação do usuário; modelos e animações não foram produzidos. Plano de rodada/ciclo e integrações está em `../BRIEFING_RETOMADA.md`.
