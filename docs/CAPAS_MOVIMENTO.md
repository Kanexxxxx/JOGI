# Capas em movimento — 24/10/2026

Pedido atendido: tornar o tecido visivelmente móvel durante a corrida, acompanhando velocidade, turbo, tropeço, chegada, comemoração e pausa, sem alterar os rostos aprovados.

`CandidatePresentation` seleciona uma derivação local dos dois modelos de corrida. A derivação isola os triângulos da capa e inclui uma máscara por vértice: ombros e gola têm deslocamento zero; a amplitude cresce até a barra. O corpo mantém o material importado original. Somente a capa recebe o shader, com as mesmas texturas de cor, normal e metal/aspereza. A estrela e a bandeira acompanham o tecido.

O relógio é explícito, sem `TIME` no shader. Frequência e amplitude passam suavemente entre os estados. O pano acompanha a velocidade da corrida, ganha intensidade no turbo, desacelera no tropeço e fica totalmente congelado na pausa. A chegada usa a velocidade da animação de chegada mesmo quando a pontuação já está encerrada. O deslocamento principal ocorre para trás, afastando a barra das pernas. É deformação procedural de apresentação, sem simulação de colisão física do tecido.

Arquivos:

- `tools/prepare_cape_motion.py`: geração local pelo Blender, sem API ou créditos; recusa sobrescrever derivados existentes.
- `game/assets/characters/cape-motion-v1/manifest.json`: hashes, contagens e preservação do buffer original.
- `game/scripts/candidate_cape_motion.gd` e `game/shaders/candidate_cape_motion.gdshader`: controle e deformação somente da capa.
- `game/tests/test_cape_motion.gd`: modelos reais, máscaras, material do corpo, texturas, corrida, turbo, tropeço, pausa e reinício.
- `game/tests/capture_cape_motion.gd`: três imagens GPU com esqueleto e câmera fixos.
- `tools/measure_cape_capture.py`: comparação das imagens GPU.

Não foram sobrescritos os GLBs originais. Os buffers anteriores de geometria, UVs, imagens, pesos e animações continuam byte a byte dentro dos derivados; foram acrescentados índices/atributos da superfície da capa e sua máscara. A contagem de triângulos permanece em 1.960.784 para Lula e 1.978.479 para Flávio.

Validação realizada:

- GDA project scan: sem erros de engine.
- GDA script validate dos dois scripts: `valid: true`.
- GDA scene validate `stadium_race.tscn`: `valid: true`.
- GDA scene preflight: `started: true`, `status: ready`, diagnósticos vazios.
- GDA strict `test_cape_motion`, `test_hero_presentation`, `test_round_finish_presentation`: status 0, stderr e diagnósticos vazios.
- GPU Vulkan RTX 4060: shader compilado, três capturas salvas e verificadas.
- A troca da fase com a mesma pose alterou 64.537 pixels. A comparação da pausa mudou zero pixels e manteve RGBA exatamente igual. Região alterada: x95..973, y434..646 numa imagem 1024×1024; cabeça e corpo fora da capa permanecem iguais.
- `git diff --check` nos arquivos alterados: sem erro.

Evidências: `docs/evidencias/estadio/capas-mesma-pose-0.png`, `capas-mesma-pose-1.png`, `capas-mesma-pose-2.png`, `capas-movimento-gpu.json`.

A revisão independente posterior aprovou máscaras, preservação binária das fontes, pausa e os três testes strict, sem bloqueios. Capturas integradas: `pista-cobalto-capas-v2.png` (14 s, média 59,90 FPS) e `podio-cobalto-capas-v2.png` (11 s, média 60 FPS), ambas 1080×1920. O teste integrado do estádio também passou após a alteração, com stderr vazio. Não foi medida uma transmissão completa de 32 horas nesta tarefa.
