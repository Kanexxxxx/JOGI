# Palácio do Planalto — ativo original local

Reconstrução 3D estilizada guiada por duas fotografias oficiais. Não é levantamento arquitetônico de medidas reais. As fotos ficam em `reference/` somente como referência de modelagem e **não são texturas do ativo**.

Versão entregue: `v1/planalto_v1.glb`, fonte Blender `v1/planalto_v1.blend`, cópia Godot `game/assets/environments/planalto/planalto_v1.glb`.

- 42.752 triângulos, 12 malhas/superfícies PBR, 2.548.172 bytes.
- Frente **−X**, altura **Y**, largura **Z**. Origem no centro da edificação, ao nível do chão.
- Corpo: profundidade X 10,5 m, altura Y 8,17 m, largura Z 38,4 m.
- Limites completos com rampa e água: mínimo `(-15.975, 0, -19.7)`, máximo `(5.75, 8.17, 19.7)`; dimensão `(21.725, 8.17, 39.4)` m.
- Instalação sugerida: posição `(48, 0, 0)`, sem rotação. A rampa avança até X32,025 e a fachada olha para a câmera situada em −X.

As nove lâminas frontais e nove posteriores possuem curvas próprias, pontas estreitas e apoio na laje intermediária. A caixa de vidro é recuada, com montantes e travessas geométricas. A cobertura em balanço, pilotis, rampa curva, pequeno parlatório e espelhos d’água também são malhas, sem imagem de fundo ou texto decorativo.

Os previews `planalto-perspectiva.png` e `planalto-frente.png` incluem piso verde de estúdio. Esse piso, luzes e câmera estão salvos no `.blend`, mas **excluídos do GLB de jogo**. A água é PBR opaca refletiva, sem reflexão dinâmica ou animação configurada. O ativo não contém colisão, LOD, pessoas ou reivindicação de FPS em produção.

Gerar outra versão sem sobrescrever:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python tools/build_planalto_palace.py -- --version v2
```

O teste `game/tests/test_planalto_asset.gd` instancia o GLB real em X48 e confere dimensões, orientação da base, origem, triângulos e superfícies.

Fontes primárias: [Casa Civil — fotos do Planalto](https://www.gov.br/casacivil/pt-br/assuntos/centrais-de-conteudo/imagens/destaques-area-de-imprensa/fotos-do-palacio-do-planalto), fotografia creditada a Roberto Stuckert Filho/PR; [Fundação Oscar Niemeyer — Palácio do Planalto](https://www.oscarniemeyer.org.br/obra/pro081/), fotografia identificada no arquivo como Moch.
