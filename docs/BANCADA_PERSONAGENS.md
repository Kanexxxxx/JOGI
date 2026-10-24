# Bancada dos personagens — 23/10/2026

Estado: bancada experimental funcional. Não representa integração à corrida nem liberação da transmissão.

## Contrato e critérios

- Usar Lula e Flávio aprovados, preservando os GLBs originais e seus SHA-256.
- Não consumir créditos Tripo, contratar serviços ou substituir modelos aprovados.
- Criar derivados separados, esqueleto, clipes reutilizáveis e inspeção frontal/lateral/traseira no Godot.
- Verificar importação, vínculo da malha ao esqueleto, movimentação real de ossos, texturas, fechamento do ciclo de corrida e liberação de nós.
- Conferir rostos e símbolos das capas nas capturas reais; não aprovar arte só por testes headless.

## Resultado atual

`ABRIR_BANCADA_PERSONAGENS.cmd` inicia a cena `game/scenes/characters/character_preview.tscn`. Não instala nada. Usa o Godot existente e permite alternar Espera, Corrida, Turbo, Frente, Esquerda, Verso e Direita. O barramento da live é parado e removido nesta cena; seu encerramento fecha o WebSocket.

Os derivados atuais estão em `assets/models/{lula,flavio}/rig-preview-v7/`; cópias de importação ficam em `game/assets/characters/preview-v7/`. Cada personagem tem 19 ossos e três clipes exportados. As texturas são 2K. Os originais continuam em `assets/models/{slug}/{slug}_base_v1.glb` e em Downloads.

O alvo de 15 mil triângulos do ART_DIRECTION.md prejudicou rosto/faixas na redução automática. A versão de bancada usa aproximadamente 60 mil triângulos por personagem: **exceção temporária de avaliação, não alteração silenciosa do orçamento de produção**. É aproximadamente 97% menos geometria que os originais de quase dois milhões. A redução não cria topologia profissional de deformação.

O rig foi produzido localmente no Blender, com pesos espaciais ajustados à pose de cada personagem, identificação aproximada da capa e suavização das transições. Reconectar emendas UV antes de suavizar os pesos eliminou os rasgos grosseiros observados. A capa continua parte da mesma malha: não há tecido físico ou retopologia manual.

## Evidências verificadas

- `evidencias/personagens/gda-scripts-v7.json`: os dois scripts válidos.
- `evidencias/personagens/gda-scene-v7.json`: cena válida.
- `evidencias/personagens/gda-preflight-v7.json`: `started=true`, `status=ready`, sem diagnósticos.
- `evidencias/personagens/gda-contract-v7.json`: teste estrito saiu com código 0. Confere ossos, skin, limite experimental de 60k, mapas 2K, três clipes, rotação real da perna, fechamento do ciclo dessa perna e ausência de nós órfãos após liberar os modelos. Não certifica estética.
- `MODELOS_DEFORMACAO_v7.json`: 16 amostras de corrida/turbo por personagem, sem arestas que excedam simultaneamente 0,05 unidade e seis vezes o comprimento de repouso. Esse diagnóstico não detecta toda dobra, interpenetração ou defeito visual.
- `evidencias/personagens/corrida-{frente,perfil,verso}-v7.png`: capturas reais no Godot/Vulkan/RTX 4060, inspecionadas.
- `evidencias/personagens/benchmark-v7.json`: bancada em **1080×1920**, 10,02 s, 601 frames, média **60,01 FPS**, p95 **16,825 ms**, limite 60 FPS, zero nós órfãos. **Uma sessão, sem pista, efeitos, OBS ou transmissão.** Não comprova desempenho de duas lives ou estabilidade de 32 horas.
- SHA-256 dos dois GLBs originais reconferidos e iguais ao inventário de recebimento.

## Experimentos anteriores

- `derived-v1`: redução 15k sem reconectar emendas; rejeitada por rasgos.
- `derived-v2`: redução 15k com weld; rejeitada por perda visual.
- `derived-v3`: UV nova/rebake 15k/2K; rejeitada por ruído no rosto/projeção.
- `derived-v4`: redução 60k/4K, base estática de avaliação com melhor reconhecimento.
- `rig-preview-v1`: exportou skin, mas não os clipes; o relatório inicial lista clipes pretendidos e não deve ser usado como prova de animação.
- `rig-preview-v2` a `v6`: tentativas intermediárias com defeitos de pesos, anatomia ou continuidade de emendas. **Não promover ao jogo.** A cena atual referencia somente v7.

Nenhum desses experimentos consumiu créditos Tripo. Os 580 créditos informados pelo usuário continuam como reserva; o saldo da conta não foi consultado nesta etapa.

## Próxima etapa concreta

Integrar v7 por uma cena de apresentação própria ao `CandidateRunner`, mantendo colisão primitiva e materiais importados separados dos efeitos. Normalizar altura/solo e orientação para correr em -Z; ligar espera/corrida/turbo aos estados reais. Antes de promover, inspecionar o modelo na câmera da pista e validar quedas/ataques, que ainda não têm clipes. Depois implementar o ciclo de 50 rodadas de dez minutos e sessões isoladas TikTok/Kwai conforme BRIEFING_RETOMADA.md.

Continuam pendentes: movimentos expressivos de ataque/impacto/recuperação/vitória/transformação, traje evoluído, capa articulada melhor, medição com pista/efeitos e duas capturas, conexão real das duas plataformas, recuperação e ensaio prolongado. A corrida principal ainda usa os bonecos procedurais antigos.

Para repetir o contrato atual:

```powershell
$env:GDA_GODOT = 'C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
& 'C:\Users\Kanex\.local\bin\gda.exe' script run res://tests/test_character_preview.gd --project game --strict --json
```

Ferramentas locais: `tools/prepare_character_lod.py`, `tools/bake_character_textures.py`, `tools/rig_character_preview.py`, `tools/audit_rig_deformation.py`. Os scripts de geração de derivados recusam sobrescrever versões existentes. Para novo experimento de rig, usar `-- --version v8` no Blender e revisar os novos arquivos antes de alterar referências do Godot.
