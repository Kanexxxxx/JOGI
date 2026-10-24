# Referências para modelagem — 23/10/2026

## Arquivos

- lula-front-tpose-v1.png: uma figura frontal em T-pose, fundo transparente; entrada principal avaliada no dry-run.
- flavio-front-tpose-v1.png: uma figura frontal em T-pose, fundo transparente; entrada principal avaliada no dry-run.
- lula-back-profile-v1.png e flavio-back-profile-v1.png: pranchas de apoio com costas e perfil. Não enviar como imagem principal para reconstruir um só personagem.

As quatro imagens foram geradas por imagegen integrada, a partir dos conceitos v3 aprovados, e inspecionadas visualmente. São referências 2D, não modelos 3D nem fotografias multivista calibradas. Proporções/perspectiva/poses variam entre vistas geradas; usar as pranchas de apoio para inspeção/modelagem, não como entrada multivista automaticamente validada. O fundo transparente frontal do Flávio tem um pequeno resíduo no canto superior esquerdo; conferir segmentação antes de upload real. Mãos são estilizadas e precisam de inspeção na malha/rig resultantes.

## API Tripo verificada

CLI 0.7.0, perfil default, região ov. doctor confirmou autenticação e acesso à API; saldo **0 disponível, 0 reservado**. Isso não é bloqueio de chave nem de rede. Saldo/plano da interface Studio não foi inspecionado. Nenhuma geração 3D paga, recarga ou compra foi executada.

## Planos avaliados, sem upload e sem cobrança

Rodados da raiz JOGI:

```powershell
& 'C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd' make assets/modeling-inputs/lula-front-tpose-v1.png --for game-pc --model tripo-v3.1 --then rig --dry-run --json
& 'C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd' make assets/modeling-inputs/flavio-front-tpose-v1.png --for game-pc --model tripo-v3.1 --then rig --dry-run --json
```

Ambos retornaram valid:true, errors:[], modelo v3.1-20260211, image-to-model com textura detailed/PBR e rig v2.5-20260210. Entregáveis previstos: FBX e GLTF. Avisos: --then substitui cadeia padrão; textura detailed tem faixa de preço maior. Dry-run não informa preço final nem comprova qualidade ou rig funcional.

## Próximo passo

Conferir a conta/rota de uso Tripo (Studio ou API) e seu custo disponível; resolver segmentação da imagem frontal e planejar cape como malha separada caso rig automático una tecido e membros. Com saldo/custo resolvidos, gerar primeiro **um** modelo, inspecionar face, malha e deformação antes de gastar com o segundo. Não alterar conceitos aprovados sem evidência de necessidade.

