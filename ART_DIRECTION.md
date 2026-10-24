# ART_DIRECTION.md — Direção de Arte 3D e Pipeline Tripo CLI

---

## 1. Estilo Visual ("Caricatura Esportiva de TV / Stylized Broadcast 3D")

- **Referências de Tom e Proporção**: Personagens estilizados com cabeça ligeiramente ampliada (`1.35x` a `1.5x` em relação ao corpo estilizado) e ombros expressivos, garantindo que expressões, acessórios e cores de faixa sejam perfeitamente visíveis mesmo pela câmera traseira elevada da corrida.
- **Materiais e Shaders**: Uso de materiais PBR limpos com *roughness* controlado (`0.45` a `0.70`) combinados com leve *rim light* (luz de contorno via shader espacial) na cor assinatura do candidato para destacá-lo do piso da pista.
- **Iluminação da Arena 3D**:
  - `DirectionalLight3D` principal em ângulo de `55°` (sombras suaves e nítidas).
  - `WorldEnvironment` com céu de estádio iluminado, `AmbientLight` clara (evitando sombras pretas pesadas que ficam borradas na compressão de vídeo do TikTok/Kwai) e `Tonemap = ACES`.

---

## 2. Câmera Vertical 9:16 (`Camera3D`)

- **Resolução Base**: `1080x1920` (Portrait).
- **FOV**: `52°` a `58°` (evita distorção excessiva nas bordas verticais mantendo sensação de velocidade).
- **Comportamento de Rastreamento (`LeaderFollowCamera`)**:
  - Segue o ponto médio ponderado entre o **1º colocado (peso 0.65)** e o **centro do pelotão ativo (peso 0.35)**, com `offset = Vector3(0.0, 6.5, 10.5)` e inclinação `pitch = -24°`.
  - Garante que os corredores fiquem sempre posicionados na **Janela de Ação Central (`y: 440px a 1220px`)**, livres da sobreposição do chat inferior do TikTok/Kwai.

---

## 3. Pipeline Oficial de Geração 3D com Tripo CLI (`tripo-cli v0.7.0`)

Todos os modelos 3D gerados por IA utilizam o `tripo-cli` instalado em `C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd`.

### 3.1 Orçamento Técnico de Malhas (Polycount & Texturas)

| Categoria de Asset | Preset Tripo (`--for`) | Limite de Faces | Textura | Rigging | Destino no Projeto |
|---|---|---|---|---|---|
| **Candidato Corredor (Hero)** | `--for game-mobile` | `<= 15.000` tris | `2048x2048` PBR | `--then rig` (Humanoid T-Pose) | `assets/models/candidates/<slug>/` |
| **Obstáculo Dinâmico** | `--for game-mobile` | `<= 3.000` tris | `1024x1024` PBR | Estático / Colisor Primitivo | `assets/models/props/` |
| **Troféu / Pódio / Arco** | `--for game-mobile` | `<= 5.000` tris | `1024x1024` PBR | Estático | `assets/models/arena/` |

### 3.2 Fluxo de Trabalho Obrigatório (Zero Desperdício de Créditos)

1. **Validação Gratuita do Plano (`--dry-run --json`)**:
   ```powershell
   C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd make "stylized 3D caricature candidate runner in suit, T-pose, vibrant game show style" --for game-mobile --then rig --dry-run --json
   ```
   - Verificar `"valid": true` e `"errors": []`.
2. **Geração e Auto-Rigging**:
   ```powershell
   C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd make "stylized 3D caricature candidate runner in suit, T-pose, vibrant game show style" --for game-mobile --then rig -o ./assets/models/candidates/candidato_01 --json --yes
   ```
3. **Inspeção Visual do `preview.png`**:
   - Avaliar silhueta, simetria da T-Pose e leitura das cores antes de importar no Godot.
4. **Importação e Validação no Godot**:
   - Usar colisores primitivos (`CapsuleShape3D` para corredores; `BoxShape3D` / `CylinderShape3D` para obstáculos) em vez de `ConcavePolygonShape3D` gerado de malha bruta, preservando 60 FPS na física 3D.
