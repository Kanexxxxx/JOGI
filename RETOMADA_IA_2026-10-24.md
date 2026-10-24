# RETOMADA JOGI — LEIA ANTES DE EDITAR (24/10/2026)

**Ponto de entrada para qualquer IA/agente que continue o projeto.** O jogo em Godot e o LiveBridge já têm implementação extensa; não reinicie o projeto nem replique funções existentes sem verificar o código.

1. **Prompt mestre de continuidade baseado no repositório:** [docs/AGENTE_RETOMADA_PROMPT_MESTRE_2026-10-24.md](docs/AGENTE_RETOMADA_PROMPT_MESTRE_2026-10-24.md).
2. **Direção oficial da arte e referência visual do HUD:** [docs/referencias/HUD_REFERENCIA.md](docs/referencias/HUD_REFERENCIA.md) · [docs/referencias/HUD_REFERENCIA_2026-10-24.md](docs/referencias/HUD_REFERENCIA_2026-10-24.md) · PNG original: [docs/referencias/hud-conceito-chatgpt-2026-10-24.png](docs/referencias/hud-conceito-chatgpt-2026-10-24.png).
3. **Estado factual, auditorias e transferências entre agentes:** [CONTINUIDADE.md](CONTINUIDADE.md), [docs/ESTADO_ATUAL.md](docs/ESTADO_ATUAL.md), [docs/REVISAO_ESTREIA_24.md](docs/REVISAO_ESTREIA_24.md), [AGENTS.md](AGENTS.md).

**Material de referência publicado:** o arquivo PNG original `HUD_CONCEITO_CHATGPT_2026-10-24.png` (`2.370.882` bytes, SHA-256 `3859DF3DB23DEEAD064A8C75E83F86055ECFE47FE63602423916C4E186CD01D8`) está versionado intacto via Git LFS em [docs/referencias/hud-conceito-chatgpt-2026-10-24.png](docs/referencias/hud-conceito-chatgpt-2026-10-24.png). Todos os agentes devem consultá-lo como **referência conceitual oficial de direção visual** (inspiração de hierarquia e clareza, mantendo o jogo limpo, responsivo e sem excesso de elementos).

**Constatações importantes:** `GiftVisualCache` já está integrado ao `stadium_race.gd` e à legenda no HUD; a meta de seguidores do usuário é **10.000** (não inventar total global do perfil se indisponível na API pública); cards transitórios de interações devem priorizar leitura em uma linha e segurança anti-SSRF; e toda afirmação sobre TikTok/Kwai deve distinguir com precisão simulador local, coletor local e validação em sala real.

**Segurança:** o repositório é público; nunca faça commit de credenciais/tokens/cookies reais. Não faça operações pagas nem inicie live pública sem autorização.

**Transferência:** registre sessão, alterações, testes, evidências e SHA final em `docs/AGENT_HANDOFF.md` e [CONTINUIDADE.md](CONTINUIDADE.md), e confirme o push remoto.
