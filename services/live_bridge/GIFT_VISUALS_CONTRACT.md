# Presentes, metas por ID e controles de áudio

As instâncias TikTok e Kwai mantêm porta, catálogo, fila, meta, áudio e cache separados. Os campos e os testes abaixo descrevem o jogo; valores em moedas não são valores em reais nem promessa de receita. O catálogo é observado, não uma tabela oficial inventada.

## Balanceamento

Ação automática pelo valor **unitário real**: 1–9 impulso; 10–99 escudo; 100–999 ataque; 1.000+ super turbo. Preço desconhecido 0 agradece, mas não acelera. Overrides do catálogo alteram somente ação/tier dos próximos eventos e removem alvos de ataque quando a nova ação não é ataque. Os totais anteriores não mudam.

Força pelo total do envelope: `coin_value = unit_coin_value * repeat_count`, uma única vez. `repeat_count` é delta novo, não combo acumulado.

| Total de moedas | boost_percent | boost_amount (base 12 m/s) | boost_duration |
|---|---:|---:|---:|
| 0 | 0 | 0 | 0 |
| 1–9 | 5 | 0,6 | 3 s |
| 10–99 | 15 | 1,8 | 4 s |
| 100–999 | 35 | 4,2 | 5 s |
| 1.000–9.999 | 70 | 8,4 | 8 s |
| 10.000–29.999 | 150 | 18 | 10 s |
| 30.000+ | 200 | 24 | 10 s |

Mesma regra para as duas equipes. Comentário mantém 1,1 m/s por 1 s, cooldown de 2 s por usuário. O maior impulso não soma indefinidamente; a aplicação/limites de duração no Godot pertencem a LiveEventBus/CandidateRunner. O simulador T4 agora parte de 1.000 moedas ilustrativas.

## Meta por presente

Comando `set_live_goal` com `goal_kind: "gift_specific"`, `goal_gift_id: "5655"`, `goal_target: 100`, `goal_label: "Meta de rosas"`. ID é string de 1 a 64 caracteres, sem controles. Os outros tipos continuam `likes`, `follows`, `gifts`, `coins` e não conservam um ID antigo.

HTTP: `/api/admin/command?command=set_live_goal&goal_kind=gift_specific&goal_gift_id=5655&goal_target=100&goal_label=Rosas`. WS admin envia os mesmos quatro campos em `params`. Arquivo local `live_goal.json` persiste o ID. O painel oferece IDs observados da própria plataforma, não infere rosas por nome. O Godot conta unidades do ID exato na sessão, inclui neutros, mantém deduplicação/checkpoint e publica `live_goal.value/progress`.

## Imagens observadas

Campos opcionais do payload:

```json
{"gift_id":"5655","gift_image_url":"https://p16-sign-va.tiktokcdn.com/gift/rose.webp?sig=...","gift_icon_path":"/gift-icons/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
```

`gift_image_url` vem de `Gift.image.url_list` no SDK TikTok ou `gift_image_url/gift_image.url_list` do coletor Kwai. Nenhuma imagem é inventada como oficial. URL inválida é descartada sem recusar um presente pago.

O bridge aceita somente HTTPS sem usuário/senha, fragmento ou porta alternativa e CDNs limitadas aos sufixos tiktokcdn.com, tiktokcdn-us.com, tiktokcdn-eu.com, byteoversea.com, ibytedtos.com, byteimg.com, kwimgs.com e kwai.net. Download não segue redirects, exige DNS público, TLS normal, timeout 5 s, máximo 1 MiB, PNG/JPEG/WebP com dimensões até 4096. Cache tem no máximo 256 tentativas/imagens por processo, um download por vez e intervalo mínimo de 0,5 s. Fonte desconhecida fica com ícone genérico.

A rota é exatamente `/gift-icons/<sha256-da-URL>`, **sem extensão**, porque o tipo real só é conhecido depois do download. Responde 404 enquanto pendente; quando pronta, responde tipo real e `X-Content-Type-Options: nosniff`. Manifesto privado guarda URL de origem, SHA256 dos bytes, tamanho, dimensões e data. Não contém chave da conta. Cache de imagem nunca bloqueia a aceitação durável/ACK de presente.

`GiftVisualCache` no Godot: `register_event(envelope)`, `get_icon(gift_id) -> Texture2D`, sinal `icon_ready(gift_id, texture)`. Só baixa a rota opaca do bridge local definido por `LIVE_BRIDGE_WS_URL`; não busca URL externa. Um HTTP por vez, limite 1 MiB, zero redirects, cinco tentativas com backoff, 64 pendências, 256 IDs e 64 texturas com maior dimensão de 512 px. Valida dimensões antes de decodificar e conserva proporção. Falha mantém o ícone genérico de impulso/escudo/ataque/super, sem alegação de presente oficial. A legenda associa a foto ao action_id efetivamente recebido.

## Áudio local

`set_audio_settings` exige quatro booleanos explícitos: `voices_enabled`, `sfx_enabled`, `crowd_enabled`, `memes_enabled`. Action ID `admin_set_audio_settings`. HTTP aceita apenas strings `true/false`; WS usa booleanos JSON. Não faz chamadas à ElevenLabs nem gera custos.

`audio_settings.json` por plataforma é salvo atomicamente após comando local e apenas a configuração mais recente é reenviada ao Godot quando reconecta. Não há envio de defaults enquanto não configurado. A interface só habilita controles quando o Godot conectado publica telemetria recente contendo as quatro flags. `audio_settings_applied` compara confirmação real com solicitado; `audio_settings_requested` é configuração desejada, não prova de som audível. Captura/volume no OBS e revisão auditiva continuam verificações próprias.

## Validações

`test_gift_art_balance.py`: todos limiares, simetria, combo sem dupla contagem, preço desconhecido, URL/path/dimensões, adaptadores, rota cache/restauração/corrupção, saturação, meta ID HTTP/WS/persistência/isolamento.

`test_audio_settings.py`: booleanos estritos, comandos malformados, persistência, última configuração, confirmação por telemetria e isolamento.

`game/tests/test_gift_visual_cache.gd`: origem local, caminho exato, decode/resolução, rejeição antes de alocação, limites de mil registros e limpeza strict.
