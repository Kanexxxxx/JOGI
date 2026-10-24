# Revisao do HUD - 24/10/2026

O placar continua recebendo metros e velocidade em m/s do coordenador. A ordem visual das linhas acompanha quem possui maior distancia; referencias a Lula/Flavio, numeros 13/22 e raias permanecem vinculadas ao mesmo candidato. Empates exatos mantem a ultima ordem. Rotulos 1º/2º tornam a lideranca imediata, com EMPATE quando necessario.

`apply_state(Dictionary)` preserva todas as chaves existentes e aceita `winner_id` (slot interno 1/2; tambem 13/22), `state_name` e `next_round_in` (segundos reais restantes ate a largada). `round_finished` exibe o vencedor ou empate, sem inferir votacao eleitoral. O coordenador deve fornecer o intervalo real; o HUD nao avanca rodada.

Fonte Nunito local, OFL, repositorio oficial: https://github.com/google/fonts/tree/main/ofl/nunito . Pesos 800/900 em FontVariation; licenca incluida. Paineis, badges e avisos usam cantos arredondados.

Comentarios entram por `show_participation`, tres linhas fixas, TTL de nove segundos, intervalo global de 0,65s e por nome de dois segundos, memoria limitada. Labels literais, nomes sem controles/bidi e limites de caracteres. Presentes e seguidores continuam com reconhecimento destacado; nao sao inventados nomes, valores ou seguidores.

`set_gift_legend(Array[Dictionary])`: ate quatro entradas com `action` (boost/shield/attack/super_turbo), `texture` (Texture2D local opcional), `label` e `amount` opcional. URLs nao sao baixadas pelo HUD. Sem imagem real recebida, os icones de mecanicas permanecem. Rotulos devem vir da configuracao real da plataforma.

Aceite: velocidade converte m/s para km/h; lider troca linha/rotulo sem trocar identidade; vencedor e contador estao corretos; feed limitado expira sem criar novos nodes; estilos possuem raios; fonte contem acentos; nenhum numero/ranking/seguidor sintetico aparece fora do teste.

Validacao executada: `gda script validate res://scripts/stadium_hud.gd` valid=true; `test_rounded_hud.gd` e regressao `test_stadium_hud.gd` em modo strict com exit_status=0, stderr vazio, diagnostics vazios. Teste visual GPU produziu `docs/evidencias/estadio/hud-arredondado-v3.png` em 1080x1920. Essa captura e uma fixture explicitamente TESTE LOCAL sobre fundo cinza; o teste integrado deve confirmar a sobreposicao no cenario real.

Teste adicional: mil comentarios no mesmo instante mantem uma entrada aceita; seis entradas espacadas deixam apenas tres linhas; expiram em nove segundos; controles bidi sao retirados; imagem local substitui icone somente quando recebida. Valores altos de metas/seguidores sao abreviados e o tamanho do texto se ajusta ao espaco. O feed nao e historico completo do chat, apenas reconhecimento visual recente.
