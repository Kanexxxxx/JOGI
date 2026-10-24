# Modelos exportados recebidos — 23/10/2026

Os GLBs enviados pelo usuário foram copiados, preservando Downloads e sem substituir versões diferentes. O nome duplicado `.glb.glb` foi simplificado apenas nas cópias do projeto.

| Personagem | Cópia no projeto | Triângulos | Texturas | Rig/animações |
|---|---|---:|---|---|
| Lula | assets/models/lula/lula_base_v1.glb | 1.960.784 | Três mapas 4096×4096 embutidos | Ausentes |
| Flávio | assets/models/flavio/flavio_base_v1.glb | 1.978.479 | Três mapas 4096×4096 embutidos | Ausentes |

Verificações: cabeçalho/comprimento GLB 2.0, JSON interno, ausência de dependências externas e SHA-256 das cópias conferidos. Ambos importaram no Blender 5.2.2 LTS, com uma malha/um material cada, três imagens carregadas, zero armatures e zero actions. Fontes: `MODELOS_RECEBIDOS.json` e `MODELOS_BLENDER_IMPORT.json`. Repetição da importação: Blender `--background --python tools/inspect_character_models.py`.

Não houve modificação das malhas, compra, geração, otimização ou rig. Os modelos ainda não foram integrados à cena do jogo nem aprovados em inspeção visual local. Não confundir importação bem-sucedida com confirmação de FPS ou qualidade das capas.

Próxima etapa técnica: preservar estas cópias como originais de alta resolução; criar versões leves com topologia adequada à deformação e conferir transferência de textura/normal; separar a capa quando necessário; preparar rig/animações e medir desempenho no Godot. A contagem atual é elevada em relação ao orçamento definido para corredores em ART_DIRECTION.md. A malha/material únicos não demonstram que capa e corpo sejam ilhas geométricas independentes; isso precisa de inspeção antes de separar ou rigar.
