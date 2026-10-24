# Efeitos da arena

`StadiumEffects` é somente apresentação. A API recebe a posição de palco do corredor, no eixo +X; Z separa as duas raias. Não altera distância, efeitos mecânicos ou materiais dos personagens.

```gdscript
var effects: StadiumEffects = StadiumEffects.new()
add_child(effects)
effects.set_runner_state(1, lula.stage_position, turbo_lula, escudo_lula, tropeço_lula)
effects.set_runner_state(2, flavio.stage_position, turbo_flavio, escudo_flavio, tropeço_flavio)
effects.trigger_moment("super_turbo", 1)
effects.trigger_moment("podium", 2)
effects.set_paused(race_paused)
# Ao reiniciar a rodada:
effects.clear_effects()
```

O rastro dourado da equipe 1 e ciano da equipe 2 nasce atrás dos pés, em -X, e acompanha somente o turbo. Impactos produzem poeira curta; escudos produzem oito brilhos rápidos, sem adicionar outra esfera sobre o personagem. O confete colorido é uma salva acionada por largada, empate ou pódio; não há chuva permanente.

São **368 partículas de capacidade máxima**, sete emissores com um passe cada e oito nós incluindo a raiz. Todos os pools e malhas são construídos uma vez. Eventos reutilizam os mesmos emissores e têm intervalo mínimo; não criam timers, tweens ou nós por presente. Nenhum serviço externo é usado e nenhum crédito é consumido.

`set_paused(true)` congela partículas e o relógio dos efeitos. `set_render_layer(mask)` permite integrar câmeras por camada. `get_effect_budget()` expõe o orçamento. Posições não finitas, equipes inexistentes e eventos desconhecidos são ignorados.

Validação automatizada: `game/tests/test_stadium_effects.gd` cobre direção dos rastros, emissão apenas por evento, seleção de raia, mil eventos sem crescimento de nós/capacidade, pausa, camadas e reinício. A avaliação final de aparência e FPS deve ocorrer com personagens e cenário completos.

Referências de API: [GPUParticles3D](https://docs.godotengine.org/en/stable/classes/class_gpuparticles3d.html) e [ParticleProcessMaterial](https://docs.godotengine.org/en/stable/classes/class_particleprocessmaterial.html).
