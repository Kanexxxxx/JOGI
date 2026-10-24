/* Local control room. Displayed race state comes only from the bridge/Godot. */
(() => {
  'use strict';
  const get = (id) => document.getElementById(id);
  const state = { ws: null, reconnect: null, snapshot: {}, online: false, goalDirty: false, audioDirty: false, sequence: 0 };
  const base = window.location.origin;
  const text = (id, value) => { const element = get(id); if (element) element.textContent = String(value); };
  const clock = (value) => {
    const s = Math.max(0, Math.floor(Number(value) || 0));
    return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
  };
  function log(kind, message) {
    const feed = get('terminal-log-body'); if (!feed) return;
    const row = document.createElement('div'); row.className = 'log-entry system';
    for (const [cls, value] of [['log-time', new Date().toLocaleTimeString('pt-BR')], ['log-badge', kind], ['log-content', message]]) {
      const span = document.createElement('span'); span.className = cls; span.textContent = String(value); row.appendChild(span);
    }
    feed.appendChild(row);
    while (feed.children.length > 50) feed.firstElementChild.remove();
    text('terminal-event-count', `${feed.children.length} eventos`); feed.scrollTop = feed.scrollHeight;
  }
  function render(data) {
    state.snapshot = data;
    text('text-backend-status', `${String(data.platform || 'local').toUpperCase()} · ${state.online ? 'Online local' : 'Sem conexão'}`);
    const backend = get('dot-backend'); if (backend) backend.className = `status-indicator-dot ${state.online ? 'online' : ''}`;
    text('text-godot-status', data.godot_connected ? (data.telemetry_fresh ? 'Telemetria recente' : 'Conectado; telemetria pendente') : 'Aguardando jogo');
    const game = get('dot-godot'); if (game) game.className = `status-indicator-dot ${data.godot_connected && data.telemetry_fresh ? 'online' : ''}`;
    const collector = data.platform_events_status;
    text('phase-label-info', data.platform_events_connected ? 'Eventos reais conectados'
      : collector === 'waiting_room' ? 'TikTok: aguardando a live pública'
      : collector === 'kwai_requires_collector' ? 'Kwai: coletor externo pendente'
      : `Coletor: ${collector || 'não conectado'} · testes locais disponíveis`);
    text('race-state-badge', data.race_state || 'Aguardando');
    text('timer-phase', clock(data.phase_timer_seconds)); text('timer-total', clock(data.race_timer_seconds));
    text('advantage-display', `${data.advantage_leader || 'Empate'} · ${Number(data.advantage_meters || 0).toFixed(1)} m`);
    const metrics = data.metrics || {};
    for (const [id, key] of [['metric-received', 'received_total'], ['metric-accepted', 'accepted_total'], ['metric-dropped', 'duplicates_dropped'], ['metric-rejected', 'invalid_rejected']]) text(id, metrics[key] || 0);
    const runners = Array.isArray(data.candidates) ? data.candidates : [];
    const farthest = Math.max(1, ...runners.map((r) => Number(r.distance_meters) || 0));
    const table = get('telemetry-table-body'); if (table) table.replaceChildren();
    for (const runner of runners) {
      const slot = Number(runner.slot); if (![1, 2].includes(slot)) continue;
      const prefix = `c${slot}`; const number = slot === 1 ? '13' : '22';
      const distance = Number(runner.distance_meters || 0); const speed = Number(runner.speed_mps || 0);
      text(`${prefix}-name`, `${number} ${runner.name}`); text(`${prefix}-pos`, `${runner.position}º`);
      text(`${prefix}-meters`, `${distance.toFixed(1)} m`); text(`${prefix}-speed`, `${speed.toFixed(1)} m/s`); text(`${prefix}-votes`, runner.votes || 0);
      const percent = Math.max(0, Math.min(100, 100 * distance / farthest));
      const fill = get(`${prefix}-fill`); if (fill) fill.style.width = `${percent}%`;
      get(`${prefix}-prog-bar`)?.setAttribute('aria-valuenow', String(Math.round(percent)));
      const flags = runner.status || {};
      const badges = [flags.turbo && '⚡ Turbo', flags.shield && '🛡 Escudo', flags.stumble && '💥 Tropeço'].filter(Boolean).join(' · ') || 'Corrida normal';
      text(`${prefix}-badges`, badges);
      if (table) {
        const row = document.createElement('tr');
        for (const value of [`${runner.position}º`, `${number} ${runner.name}`, `${distance.toFixed(1)} m`, `${speed.toFixed(1)} m/s`, runner.votes || 0, badges]) {
          const cell = document.createElement('td'); cell.textContent = String(value); row.appendChild(cell);
        }
        table.appendChild(row);
      }
    }
    const goal = data.live_goal;
    if (goal) {
      text('goal-current', `${goal.goal_label}: ${Number(goal.goal_target).toLocaleString('pt-BR')} (${goal.goal_kind})`);
      if (!state.goalDirty && !get('goal-form')?.contains(document.activeElement)) {
        get('goal-kind').value = goal.goal_kind; get('goal-target').value = goal.goal_target; get('goal-label').value = goal.goal_label;
        get('goal-gift-wrap').hidden = goal.goal_kind !== 'gift_specific';
        if (goal.goal_gift_id) get('goal-gift-id').value = goal.goal_gift_id;
      }
    }
    text('goal-progress-text', data.live_goal_applied && goal && Number.isFinite(Number(goal.value))
      ? `Progresso no jogo: ${Number(goal.value).toLocaleString('pt-BR')} / ${Number(goal.goal_target).toLocaleString('pt-BR')}`
      : 'Meta configurada no bridge; progresso aguardando confirmação do jogo.');
    const audience = data.audience || {}; const totals = audience.session || {};
    const sum = (value) => Array.isArray(value) ? value.reduce((total, n) => total + (Number(n) || 0), 0) : (Number(value) || 0);
    text('audience-totals', Object.keys(totals).length ? `Curtidas ${sum(totals.likes)} · Seguidores ${sum(totals.follows)} · Comentários ${sum(totals.votes)} · Presentes ${sum(totals.gifts)} · Moedas ${sum(totals.coins)} · Compartilhamentos ${sum(totals.shares)}` : 'Interações aguardando telemetria.');
    text('outbox-status', `Presentes aguardando confirmação: ${Number(data.pending_gifts || 0)} · Confirmados nesta execução: ${Number(metrics.gift_acks_total || 0)}`);
    const audio = data.audio || {};
    text('audio-status', `Voz: ${audio.voice_status || 'estado ainda não informado pelo jogo'}`);
    const audioFields = [['audio-voices','voices_enabled'],['audio-sfx','sfx_enabled'],['audio-crowd','crowd_enabled'],['audio-memes','memes_enabled']];
    const audioKnown = data.godot_connected && data.telemetry_fresh && audioFields.every(([, key]) => typeof audio[key] === 'boolean');
    for (const [id, key] of audioFields) {
      get(id).disabled = !audioKnown;
      if (audioKnown && !state.audioDirty && !get('audio-form').contains(document.activeElement)) get(id).checked = audio[key];
    }
    get('audio-apply').disabled = !audioKnown;
    text('audio-confirmation', !audioKnown ? 'Aguardando confirmação do jogo para controlar o áudio.'
      : data.audio_settings_applied ? 'Estado do áudio confirmado pelo jogo.' : 'Alteração solicitada; aguardando confirmação do jogo.');
    const leaders = get('top-supporters'); if (leaders) {
      leaders.replaceChildren(); const supporters = Array.isArray(audience.top_supporters) ? audience.top_supporters.slice(0, 5) : [];
      for (const supporter of supporters) {
        const row = document.createElement('li'); const team = Number(supporter.team);
        row.textContent = `${supporter.display_name || 'Espectador'} · ${team === 1 ? '13 Lula' : team === 2 ? '22 Flávio' : 'Torcida neutra'} · ${Number(supporter.coins || 0).toLocaleString('pt-BR')} moedas`; leaders.appendChild(row);
      }
      if (!supporters.length) { const row = document.createElement('li'); row.textContent = 'Aguardando presentes contabilizados pelo jogo.'; leaders.appendChild(row); }
    }
    const lead = get('tug-of-war-fill');
    if (lead && runners.length === 2) {
      const total = runners.reduce((sum, r) => sum + Number(r.distance_meters || 0), 0);
      lead.style.width = `${total ? 100 * Number(runners[0].distance_meters || 0) / total : 50}%`;
    }
  }
  async function poll() {
    try {
      const response = await fetch(`${base}/api/state`, { cache: 'no-store' });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      state.online = true; render(await response.json());
    } catch (_) {
      state.online = false; text('text-backend-status', 'Servidor indisponível; comandos não aplicados'); text('text-godot-status', 'Estado não confirmado');
    }
  }
  async function refreshCatalog() {
    const container = get('gift-catalog-list'); if (!container || container.contains(document.activeElement)) return;
    try {
      const response = await fetch(`${base}/api/gifts`, {cache:'no-store'});
      if (!response.ok) throw new Error('Catálogo indisponível');
      const data = await response.json(); container.replaceChildren();
      const goalGift = get('goal-gift-id');
      if (goalGift && document.activeElement !== goalGift) {
        const selected = goalGift.value || state.snapshot.live_goal?.goal_gift_id || '';
        goalGift.replaceChildren();
        const empty = document.createElement('option'); empty.value = ''; empty.textContent = 'Selecione um ID observado nesta plataforma'; goalGift.appendChild(empty);
        const giftIds = new Set();
        for (const entry of data.entries) {
          if (entry.source !== state.snapshot.platform || giftIds.has(entry.gift_id)) continue;
          giftIds.add(entry.gift_id);
          const option = document.createElement('option'); option.value = entry.gift_id; option.textContent = `${entry.gift_name} · ID ${entry.gift_id}`; goalGift.appendChild(option);
        }
        if (selected && !giftIds.has(selected)) {
          const option = document.createElement('option'); option.value = selected; option.textContent = `ID ${selected} · meta já configurada`; goalGift.appendChild(option);
        }
        goalGift.value = selected;
      }
      if (!data.entries.length) { container.textContent = 'Nenhum presente identificado recebido nesta instância.'; return; }
      for (const entry of data.entries) {
        const row = document.createElement('label'); row.className = 'gift-catalog-row';
        const caption = document.createElement('span'); caption.textContent = `${entry.gift_name} · ${entry.source} · ID ${entry.gift_id} · ${entry.unit_coin_value || 'valor desconhecido'} moeda(s)/unidade`;
        const select = document.createElement('select'); select.className = 'form-select'; select.setAttribute('aria-label', `Ação de ${entry.gift_name}`);
        for (const [value, name] of [['default','Automático pelo valor'],['boost','Impulso'],['shield','Escudo'],['attack','Ataque'],['super_turbo','Super turbo']]) {
          const option = document.createElement('option'); option.value=value; option.textContent=name; select.appendChild(option);
        }
        select.value = entry.override ? entry.action : 'default';
        select.addEventListener('change', async () => {
          try {
            const query = new URLSearchParams({source:entry.source,gift_id:entry.gift_id,action:select.value});
            const result = await fetch(`${base}/api/admin/gift?${query}`, {cache:'no-store'});
            if (!result.ok) throw new Error('Ação não confirmada');
            log('recibo', `Ação do presente ${entry.gift_id} atualizada`);
          } catch (error) { log('erro', error.message); }
        });
        row.append(caption, select); container.appendChild(row);
      }
    } catch (error) { log('erro', error.message); }
  }
  async function send(message) {
    try {
      if (state.ws?.readyState === WebSocket.OPEN) {
        state.ws.send(JSON.stringify(message)); log('solicitação', message.command || `Simular ${message.event_type}`); return true;
      }
      const simulation = message.type === 'simulate_event';
      const values = simulation ? { event_type: message.event_type, ...(message.data || {}) }
        : { command: message.command || (message.action === 'turbo' ? 'boost' : message.action), ...(message.params || {}), ...(message.candidate_slot ? { candidate_slot: message.candidate_slot } : {}) };
      const query = new URLSearchParams(Object.entries(values).map(([key, value]) => [key, String(value)]));
      const response = await fetch(`${base}/api/admin/${simulation ? 'simulate' : 'command'}?${query}`, { cache: 'no-store' });
      const ack = await response.json();
      if (!response.ok || !['ok', 'accepted', 'duplicate'].includes(ack.status)) throw new Error(ack.message || ack.status);
      log('recibo', ack.message || ack.status); await poll(); return true;
    } catch (error) { log('erro', `Comando não confirmado: ${error.message}`); return false; }
  }
  function connect() {
    clearTimeout(state.reconnect); state.reconnect = null;
    if (state.ws) { state.ws.onclose = null; state.ws.close(); }
    const socket = new WebSocket(`${window.location.protocol === 'https:' ? 'wss' : 'ws'}://${window.location.host}/ws/admin`); state.ws = socket;
    socket.onopen = () => { state.online = true; log('conexão', 'Painel local conectado'); };
    socket.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === 'state_update') render(data);
        else if (data.type === 'command_ack') log(data.status === 'ok' ? 'recibo' : 'erro', data.message || data.status);
        else if (data.type === 'telemetry_event') log('evento', data.action || 'Atualização');
      } catch (_) { log('erro', 'Resposta inválida'); }
    };
    socket.onclose = () => { if (!state.reconnect) state.reconnect = setTimeout(connect, 2000); };
  }
  const click = (id, callback) => get(id)?.addEventListener('click', callback);
  const command = (value) => send({ type: 'admin_command', command: value });
  const simulate = (kind, slot, extra = {}) => {
    state.sequence += 1;
    return send({ type: 'simulate_event', event_type: kind, data: { candidate_slot: Number(slot || 1), user_id: `sim_${kind}_${Date.now()}_${state.sequence}`, display_name: 'Teste local', ...extra } });
  };
  click('btn-reconnect', connect);
  for (const [id, value] of [['btn-start-race', 'start_race'], ['btn-skip-lobby', 'skip_lobby'], ['btn-pause-race', 'pause_race'], ['btn-resume-race', 'resume_race'], ['btn-reset-dedup', 'reset_dedup']]) click(id, () => command(value));
  click('btn-restart-race', () => get('modal-restart')?.classList.add('active'));
  click('btn-cancel-restart', () => get('modal-restart')?.classList.remove('active'));
  click('btn-confirm-restart', () => { get('modal-restart')?.classList.remove('active'); command('restart_race'); });
  get('candidates-grid')?.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-action]'); if (button) send({ type: 'candidate_action', action: button.dataset.action, candidate_slot: Number(button.dataset.slot) });
  });
  click('btn-sim-vote', () => simulate('vote', get('sim-vote-cand')?.value, { count: Number(get('sim-vote-qty')?.value || 1) }));
  document.querySelectorAll('[data-likes]').forEach((button) => button.addEventListener('click', () => simulate('like', get('sim-like-cand')?.value, { count: Number(button.dataset.likes) })));
  click('btn-sim-share', () => simulate('share', get('sim-share-cand')?.value));
  click('btn-sim-follow', () => simulate('follow', get('sim-share-cand')?.value));
  document.querySelectorAll('.gift-button[data-tier]').forEach((button) => button.addEventListener('click', () => simulate('gift', get('sim-gift-cand')?.value, { gift_tier: button.dataset.tier, count: 1 })));
  click('btn-sim-custom-gift', () => {
    const coins = Number(get('sim-gift-coins')?.value); const count = Number(get('sim-gift-count')?.value);
    if (!Number.isInteger(coins) || coins < 0 || coins > 100000 || !Number.isInteger(count) || count < 1 || count > 1000) return log('erro', 'Valor ou quantidade inválidos');
    simulate('gift', get('sim-gift-cand')?.value, { unit_coin_value: coins, count });
  });
  click('btn-burst-events', () => simulate('burst', 1, { count: 40 }));
  click('btn-clear-log', () => { get('terminal-log-body')?.replaceChildren(); text('terminal-event-count', '0 eventos'); });
  click('btn-refresh-gifts', refreshCatalog);
  get('goal-form')?.addEventListener('input', () => { state.goalDirty = true; });
  get('audio-form')?.addEventListener('input', () => { state.audioDirty = true; });
  get('audio-form')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (get('audio-apply').disabled) return;
    const params = {voices_enabled:get('audio-voices').checked,sfx_enabled:get('audio-sfx').checked,crowd_enabled:get('audio-crowd').checked,memes_enabled:get('audio-memes').checked};
    if (await send({type:'admin_command',command:'set_audio_settings',params})) state.audioDirty = false;
  });
  get('goal-kind')?.addEventListener('change', () => { get('goal-gift-wrap').hidden = get('goal-kind').value !== 'gift_specific'; });
  get('goal-form')?.addEventListener('submit', async (event) => {
    event.preventDefault(); const target = Number(get('goal-target').value);
    if (!Number.isInteger(target) || target < 1 || target > 1000000000) return log('erro', 'Quantidade inválida');
    const kind = get('goal-kind').value;
    const giftId = get('goal-gift-id').value;
    if (kind === 'gift_specific' && !giftId) { log('erro', 'Receba um presente identificado e selecione o ID antes de aplicar esta meta.'); return; }
    if (await send({ type: 'admin_command', command: 'set_live_goal', params: { goal_kind: kind, goal_target: target, goal_label: get('goal-label').value.slice(0, 40), ...(kind === 'gift_specific' ? {goal_gift_id: giftId} : {}) } })) state.goalDirty = false;
  });
  connect(); poll(); refreshCatalog(); setInterval(poll, 1000); setInterval(refreshCatalog, 5000);
})();
