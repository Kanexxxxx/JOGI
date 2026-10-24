# Interações do público — contrato implementado em 24/10/2026

O envelope continua `schema_version: "1.0"`, com os mesmos campos. Esta atualização
aceita torcida 13/22, eventos neutros e valores reais dos presentes.

## Escolha da equipe

- `13`, `#13`, `Lula`, `#1` e `1` escolhem `candidate_slot: 1`.
- `22`, `#22`, `Flávio`, `Flavio`, `Bolsonaro`, `verde-amarelo`, `#2` e `2`
  escolhem `candidate_slot: 2`. O `target: "bolsonaro"` legado é mantido por compatibilidade.
- Números isolados ou uma frase explícita (`vai 22`, `meu voto é 13`) contam como torcida.
  Comentários comuns (`tenho 22 anos`), números parciais e escolhas ambíguas
  (`#13 #22`) não geram voto. Texto livre nunca vai ao Godot.
- TikTok e Kwai guardam a última escolha de cada usuário em memória separada por
  plataforma, limitada a 10.000 usuários, por até 32 horas. Reiniciar o bridge limpa isso.
- Sem escolha, `gift`, `like_batch` e `share` são emitidos sem `candidate_slot`/`target`.
  São interações neutras: podem entrar em destaque/ranking/meta coletiva; o consumidor
  deve tratá-las como equipe 0 e não conceder efeito a um candidato arbitrário.
  `vote` continua exigindo equipe 1 ou 2.
- `default_candidate_slot` existe nos conectores, mas o padrão é `None`. Qualquer
  campanha futura com time padrão precisa configurá-lo explicitamente.

## Presentes e ranking

`user.user_id` é a identidade; `display_name` é somente apresentação sanitizada
(24 caracteres, sem BBCode, controles, bidi ou delimitadores HTML). O ranking deve
separar usuários por `source + user_id`, não pelo nome exibido.

`payload.repeat_count` é a quantidade NOVA desse pacote (delta), entre 1 e 1.000.
`payload.coin_value` já é o TOTAL desse delta: `preço unitário × repeat_count`.
**Não multiplicar novamente no ranking.** Aceita 0..100.000.000; zero significa
preço não informado pela plataforma, sem estimativa de moedas ou reais.
`gift_name` conserva o nome real recebido, sanitizado em até 32 caracteres.

O catálogo T1..T4 só classifica efeitos. Os adaptadores reais nunca substituem o
preço recebido pelo preço fictício do catálogo. O simulador mantém preços de teste
e `source: "simulator"`; esses eventos não comprovam receita real.

### TikTok

No SDK atual `repeat_count` e `streaking` pertencem ao evento, enquanto `gift` contém
metadados como nome, tipo e `diamond_count`. Campos em `gift` ainda são aceitos
como compatibilidade com os testes e conectores antigos.

Um combo 1 → 3 → 5 → final 5 emite deltas 1, 2, 2; o final não soma de novo.
Um delta maior que 1.000 é dividido em envelopes com IDs distintos, preservando
a quantidade total do combo sem ultrapassar o limite de cada pacote.
`group_id`/`streak_id` identificam combos distintos. Sem esse ID, o rastreador usa
a sequência por usuário/presente e reinicia após um combo encerrado quando recebe
uma nova sequência ascendente começando abaixo do total anterior. Presentes sem
combo são independentes. `common.msg_id`, `msg_id`, `message_id` ou `event_id`
identificam replays e geram IDs normalizados determinísticos, com cache de 15 minutos.
Sem ID upstream não há como distinguir com certeza dois pacotes idênticos de dois
presentes legítimos; essa limitação precisa ser verificada com um coletor real.

Referência primária verificada: https://ttl.docs.isaackogan.com/guides/gifts/

### Kwai e ingestão abreviada local

O Kwai continua um receptor passivo em **127.0.0.1**, sem coletor real conectado.
O emissor do webhook deve enviar `event_id` estável, `count`/`repeat_count` como
delta e `coin_value`/`coins`/`price` como preço UNITÁRIO. Ele não deve enviar o
acumulado do combo como delta. O envelope normalizado contém o total final.

Nos atalhos `/ws/ingest`, `unit_coin_value` (ou `coin_value` legado) também é
UNITÁRIO. Nos envelopes completos, `payload.coin_value` já é TOTAL. Eventos reais
sem preço usam zero; os usuários neutros não recebem torcida automática.

## Validação e estado real

Testes em `test_audience_events.py` verificam aliases, neutralidade, sanitização,
SDK com objetos, combo/deduplicação, preços e encaminhamento WebSocket loopback.
Não foi aberta live, não há confirmação de aptidão para presentes e nenhum teste
local comprova conexão real com TikTok ou Kwai.
