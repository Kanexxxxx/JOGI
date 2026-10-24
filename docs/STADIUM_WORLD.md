# Arena esportiva lateral — contrato visual

Implementação aditiva em `game/scripts/stadium_world.gd`, classe `StadiumWorld`. Cenas isoladas em `game/scenes/environment/stadium_world.tscn` e `stadium_preview.tscn`. A cena de prévia não contém candidatos, pontuação ou integração de live.

- Eixo da corrida: +X; piso em Y=0. Raias em Z=-2,2 (fundo) e Z=+2,2 (frente). Limites brancos em Z=-4,4/0/+4,4.
- `set_travel_distance(distance: float)` recebe a distância da simulação. Pista e sinalização próximas correm a 100%, arquibancada a 18%, paisagem a 6,5%; módulos se repetem em 8/16 m. O estado da simulação e o movimento dos personagens são responsabilidade da corrida.
- `set_round_metadata(metadata: Dictionary)` usa `preset_id` 1–10 para três famílias de atmosfera: dia, fim de tarde e noite. Não representa cinquenta cenários diferentes. A luz frontal continua ativa à noite para preservar leitura dos rostos.
- `set_render_layer(mask: int)` propaga a máscara aos elementos visuais. `build_lighting=false` permite usar iluminação externa.
- `grandstand_scene: PackedScene` permite substituir o módulo de arquibancada. O módulo deve ter 8 m de largura, origem central em X, base em Y=0, frente em Z≈3,4 e fundo em Z≈-3; é instanciado a cada 8 m em X, deslocado para Z=-10. A camada recebe compressão cenográfica Y=0,55/Z=0,5 com deslocamento Z=-3,3 para a câmera vertical.

O fallback inclui pista de tartan com microtextura, gramado com cortes alternados, linhas de velocidade, arquibancada em degraus com escadas livres, cobertura com tirantes, faixas LED animadas, bandeiras brasileiras ao vento, palmeiras, nuvens e torres de refletores. A torcida usa 1.200 silhuetas com cores/peles variadas e braços animados por shader. É deliberadamente uma multidão de fundo de baixo custo.

Orçamento medido em execução: **14.752 triângulos estáticos + 15.600 da torcida = 30.352 triângulos**, 24 superfícies estáticas e uma chamada MultiMesh. Os elementos estáticos são combinados por material dentro de cada camada. Não há corpos físicos, texturas externas, geração paga, segredos ou entradas de chat neste módulo.

Validação: scan de classes, script validate, scene validate e scene preflight com `started=true`, `status=ready`, `diagnostics=[]`. Capturas em `docs/evidencias/estadio/`. A captura isolada usa câmera ortográfica em `(0,6.8,12)`, mirando `(0,1,0)`, KEEP_HEIGHT e tamanho 11. O enquadramento final depende do HUD e dos modelos integrados; a prévia não comprova FPS de duas instâncias nem funcionamento por 32 horas.

Comando de captura (recusa sobrescrever PNG existente):

```powershell
& 'C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path game res://scenes/environment/stadium_preview.tscn -- --stadium-capture=dia-v4
```
