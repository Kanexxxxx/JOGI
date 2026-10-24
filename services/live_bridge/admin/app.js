/* Local control room. Displayed race state comes only from the bridge/Godot. */
(() => {
  'use strict';
  const get = (id) => document.getElementById(id);
  const state = {
    ws: null,
    reconnect: null,
    snapshot: {},
    online: false,
    authRequired: false,
    goalDirty: false,
    multiGoalsDirty: false,
    audioDirty: false,
    kwaiUrlDirty: false,
    sequence: 0,
  };
  const base = window.location.origin;
  const text = (id, value) => {
    const element = get(id);
    if (element) element.textContent = String(value);
  };
  const clock = (value) => {
    const s = Math.max(0, Math.floor(Number(value) || 0));
    return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
  };
  function log(kind, message) {
    const feed = get('terminal-log-body');
    if (!feed) return;
    const row = document.createElement('div');
    row.className = 'log-entry system';
    for (const [cls, value] of [
      ['log-time', new Date().toLocaleTimeString('pt-BR')],
      ['log-badge', kind],
      ['log-content', message],
    ]) {
      const span = document.createElement('span');
      span.className = cls;
      span.textContent = String(value);
      row.appendChild(span);
    }
    feed.appendChild(row);
    while (feed.children.length > 50) feed.firstElementChild.remove();
    text('terminal-event-count', `${feed.children.length} eventos`);
    feed.scrollTop = feed.scrollHeight;
  }

  function populateGiftSelect(selectEl, entries, platform, fallbackSelected) {
    if (!selectEl || document.activeElement === selectEl) return;
    const selected = selectEl.value || fallbackSelected || '';
    selectEl.replaceChildren();
    const empty = document.createElement('option');
    empty.value = '';
    empty.textContent = 'Selecione um ID observado nesta plataforma';
    selectEl.appendChild(empty);
    const giftIds = new Set();
    for (const entry of entries) {
      if (entry.source !== platform || giftIds.has(entry.gift_id)) continue;
      giftIds.add(entry.gift_id);
      const option = document.createElement('option');
      option.value = entry.gift_id;
      option.textContent = `${entry.gift_name} · ID ${entry.gift_id}`;
      selectEl.appendChild(option);
    }
    if (selected && !giftIds.has(selected)) {
      const option = document.createElement('option');
      option.value = selected;
      option.textContent = `ID ${selected} · meta já configurada`;
      selectEl.appendChild(option);
    }
    selectEl.value = selected;
  }

  function render(data) {
    state.snapshot = data;
    state.authRequired = false;
    const authSec = get('auth-unlock-section');
    if (authSec) authSec.hidden = true;

    const platform = String(data.platform || 'local').toLowerCase();
    const accountLabel = data.account ? ` · @${data.account}` : '';
    text('text-backend-status', `${platform.toUpperCase()}${accountLabel} · ${state.online ? 'Online local' : 'Sem conexão'}`);
    const pill = get('channel-pill');
    if (pill) {
      pill.className = `on-air-pill ${platform === 'tiktok' ? 'channel-tiktok' : platform === 'kwai' ? 'channel-kwai' : ''}`;
    }
    text(
      'channel-pill-text',
      platform === 'tiktok'
        ? `TIKTOK :${window.location.port || 8765}`
        : platform === 'kwai'
        ? `KWAI :${window.location.port || 8766}`
        : 'PAINEL LOCAL'
    );
    const backend = get('dot-backend');
    if (backend) backend.className = `status-indicator-dot ${state.online ? 'online' : ''}`;
    const ageSuffix = Number.isFinite(Number(data.telemetry_age_seconds)) ? ` (${Number(data.telemetry_age_seconds).toFixed(1)}s)` : '';
    text(
      'text-godot-status',
      data.godot_connected
        ? data.telemetry_fresh
          ? `Telemetria ao vivo${ageSuffix}`
          : data.telemetry_stale
          ? `Telemetria obsoleta${ageSuffix}`
          : 'Conectado; telemetria pendente'
        : 'Aguardando jogo'
    );
    const game = get('dot-godot');
    if (game) game.className = `status-indicator-dot ${data.godot_connected && data.telemetry_fresh ? 'online' : ''}`;
    const collector = data.platform_events_status;
    text(
      'phase-label-info',
      data.platform_events_connected
        ? `Eventos ${platform.toUpperCase()} conectados`
        : collector === 'waiting_room'
        ? `${platform === 'kwai' ? 'Kwai' : 'TikTok'}: aguardando sala AO VIVO`
        : collector === 'reconnecting'
        ? `${platform.toUpperCase()}: reconectando automaticamente`
        : collector === 'account_not_found'
        ? `${platform.toUpperCase()}: conta pública não encontrada`
        : collector === 'webhook_listening'
        ? 'Kwai: receptor :8786 ativo · aguardando coletor/sala'
        : collector === 'login_required'
        ? 'Kwai: login único necessário (ABRIR_NAVEGADOR_KWAI.cmd)'
        : collector === 'kwai_requires_collector'
        ? 'Kwai: coletor externo pendente (bloqueio oficial sem API nuvem)'
        : `Coletor: ${collector || 'não conectado'} · testes locais disponíveis`
    );
    const stateName = String(data.race_state || 'Aguardando');
    text('race-state-badge', stateName);
    const stateBadge = get('race-state-badge');
    if (stateBadge) {
      const stateClass =
        stateName === 'RACING'
          ? 'state-racing'
          : stateName === 'COUNTDOWN'
          ? 'state-countdown'
          : stateName === 'PHOTO_FINISH'
          ? 'state-photofinish'
          : stateName === 'PODIO'
          ? 'state-podio'
          : 'state-lobby';
      stateBadge.className = `race-state-badge ${stateClass}`;
    }
    text('timer-phase', clock(data.phase_timer_seconds));
    text('timer-total', clock(data.race_timer_seconds));
    text('advantage-display', `${data.advantage_leader || 'Empate'} · ${Number(data.advantage_meters || 0).toFixed(1)} m`);
    const metrics = data.metrics || {};
    for (const [id, key] of [
      ['metric-received', 'received_total'],
      ['metric-accepted', 'accepted_total'],
      ['metric-dropped', 'duplicates_dropped'],
      ['metric-rejected', 'invalid_rejected'],
    ]) {
      text(id, metrics[key] || 0);
    }

    const perf = (data.telemetry_fresh && (data.performance || data.telemetry?.performance)) || {};
    const rawTelemetry = data.telemetry_fresh ? data.telemetry || {} : {};
    const fpsVal = Number(perf.fps);
    const fpsEl = get('perf-fps');
    if (fpsEl) {
      fpsEl.textContent = Number.isFinite(fpsVal) && fpsVal > 0 ? `${fpsVal.toFixed(1)} FPS` : '—';
      fpsEl.className = `metric-value tabular-nums ${
        !Number.isFinite(fpsVal) || fpsVal <= 0 ? '' : fpsVal >= 55 ? 'ok' : fpsVal >= 40 ? 'warn' : 'danger'
      }`;
    }
    text('perf-frame-ms', Number.isFinite(Number(perf.frame_ms)) && data.telemetry_fresh ? `${Number(perf.frame_ms).toFixed(2)} ms` : '—');
    text('perf-mem-mb', Number.isFinite(Number(perf.static_mem_mb)) && data.telemetry_fresh ? `${Number(perf.static_mem_mb).toFixed(1)} MB` : '—');
    text('perf-draw-calls', Number.isFinite(Number(perf.draw_calls)) && data.telemetry_fresh ? `${Number(perf.draw_calls)}` : '—');
    const orphans = Number(perf.orphan_nodes);
    const orphanEl = get('perf-orphans');
    if (orphanEl) {
      orphanEl.textContent = Number.isFinite(orphans) && data.telemetry_fresh ? `${orphans}` : '—';
      orphanEl.className = `metric-value tabular-nums ${
        !data.telemetry_fresh || !Number.isFinite(orphans) ? '' : orphans === 0 ? 'ok' : 'warn'
      }`;
    }
    text(
      'perf-round-cycle',
      data.telemetry_fresh && rawTelemetry.current_round
        ? `R${String(rawTelemetry.current_round).padStart(2, '0')}/50 · C${rawTelemetry.cycle_number || 1}`
        : '—'
    );

    const kwaiSection = get('kwai-collector-section');
    if (kwaiSection) {
      kwaiSection.hidden = platform !== 'kwai';
      if (platform === 'kwai') {
        const kw = data.kwai_collector || {};
        text(
          'kwai-webhook-badge',
          `Webhook: ${kw.webhook_url || 'http://127.0.0.1:8786/webhook/kwai'} (${kw.webhook_listening ? 'ESCUTANDO' : 'OFFLINE'})`
        );
        text(
          'kwai-collector-detail',
          kw.collector_detail
            ? `${kw.collector_detail} · Alvo: ${kw.target_url || '@mentalista..'} · Encaminhados: ${Number(kw.collector_events_forwarded || 0)}`
            : `Alvo atual: ${kw.target_url || 'https://www.kwai.com/@mentalista..'} · Aguardando batimento do coletor local.`
        );
        const urlInput = get('kwai-live-url');
        if (urlInput && !state.kwaiUrlDirty && document.activeElement !== urlInput) {
          urlInput.value = kw.live_url || '';
        }
      }
    }

    const runners = Array.isArray(data.candidates) ? data.candidates : [];
    const farthest = Math.max(1, ...runners.map((r) => Number(r.distance_meters) || 0));
    const table = get('telemetry-table-body');
    if (table) table.replaceChildren();
    for (const runner of runners) {
      const slot = Number(runner.slot);
      if (![1, 2].includes(slot)) continue;
      const prefix = `c${slot}`;
      const number = slot === 1 ? '13' : '22';
      const distance = Number(runner.distance_meters || 0);
      const speed = Number(runner.speed_mps || 0);
      text(`${prefix}-name`, `${number} ${runner.name}`);
      text(`${prefix}-pos`, `${runner.position}º`);
      text(`${prefix}-meters`, `${distance.toFixed(1)} m`);
      text(`${prefix}-speed`, `${speed.toFixed(1)} m/s`);
      text(`${prefix}-votes`, runner.votes || 0);
      const percent = Math.max(0, Math.min(100, (100 * distance) / farthest));
      const fill = get(`${prefix}-fill`);
      if (fill) fill.style.width = `${percent}%`;
      get(`${prefix}-prog-bar`)?.setAttribute('aria-valuenow', String(Math.round(percent)));
      const flags = runner.status || {};
      const badges =
        [flags.turbo && '⚡ Turbo', flags.shield && '🛡 Escudo', flags.stumble && '💥 Tropeço'].filter(Boolean).join(' · ') ||
        'Corrida normal';
      text(`${prefix}-badges`, badges);
      if (table) {
        const row = document.createElement('tr');
        for (const value of [
          `${runner.position}º`,
          `${number} ${runner.name}`,
          `${distance.toFixed(1)} m`,
          `${speed.toFixed(1)} m/s`,
          runner.votes || 0,
          badges,
        ]) {
          const cell = document.createElement('td');
          cell.textContent = String(value);
          row.appendChild(cell);
        }
        table.appendChild(row);
      }
    }

    const goal = data.live_goal;
    if (goal) {
      text('goal-current', `${goal.goal_label}: ${Number(goal.goal_target).toLocaleString('pt-BR')} (${goal.goal_kind})`);
      if (!state.goalDirty && !get('goal-form')?.contains(document.activeElement)) {
        get('goal-kind').value = goal.goal_kind;
        get('goal-target').value = goal.goal_target;
        get('goal-label').value = goal.goal_label;
        get('goal-gift-wrap').hidden = goal.goal_kind !== 'gift_specific';
        if (goal.goal_gift_id) get('goal-gift-id').value = goal.goal_gift_id;
      }
    }
    text(
      'goal-progress-text',
      data.live_goal_applied && goal && Number.isFinite(Number(goal.value))
        ? `Progresso no jogo: ${Number(goal.value).toLocaleString('pt-BR')} / ${Number(goal.goal_target).toLocaleString('pt-BR')}`
        : 'Meta configurada no bridge; progresso aguardando confirmação do jogo.'
    );

    const audience = data.audience || {};
    const totals = audience.session || {};
    const sum = (value) => (Array.isArray(value) ? value.reduce((total, n) => total + (Number(n) || 0), 0) : Number(value) || 0);
    const sessionLikes = sum(totals.likes);
    const sessionGifts = sum(totals.gifts);
    const sessionCoins = sum(totals.coins);
    const sessionFollows = sum(totals.follows);

    const liveGoals = data.live_goals || {};
    if (liveGoals.likes && liveGoals.gifts && liveGoals.follows) {
      const lgLikes = liveGoals.likes;
      const lgGifts = liveGoals.gifts;
      const lgFollows = liveGoals.follows;
      const likesVal = Number.isFinite(Number(lgLikes.value)) ? Number(lgLikes.value) : sessionLikes;
      const giftsVal = Number.isFinite(Number(lgGifts.value))
        ? Number(lgGifts.value)
        : lgGifts.goal_kind === 'coins'
        ? sessionCoins
        : sessionGifts;
      const baseline = lgFollows.follower_baseline !== null && lgFollows.follower_baseline !== undefined
        ? Number(lgFollows.follower_baseline)
        : null;
      const followsSessionVal = Number.isFinite(Number(lgFollows.session_follows)) ? Number(lgFollows.session_follows) : sessionFollows;
      const followsVal = baseline !== null ? baseline + followsSessionVal : followsSessionVal;

      text('mg-likes-progress', `${likesVal.toLocaleString('pt-BR')} / ${Number(lgLikes.goal_target || 1000).toLocaleString('pt-BR')}`);
      text('mg-gifts-progress', `${giftsVal.toLocaleString('pt-BR')} / ${Number(lgGifts.goal_target || 500).toLocaleString('pt-BR')}`);
      text(
        'mg-follows-progress',
        baseline !== null
          ? `${followsVal.toLocaleString('pt-BR')} / ${Number(lgFollows.goal_target || 10000).toLocaleString('pt-BR')} (base ${baseline.toLocaleString('pt-BR')} +${followsSessionVal})`
          : `+${followsSessionVal.toLocaleString('pt-BR')} na live · Alvo ${Number(lgFollows.goal_target || 10000).toLocaleString('pt-BR')}`
      );

      if (!state.multiGoalsDirty && !get('multi-goals-form')?.contains(document.activeElement)) {
        if (get('mg-likes-target')) get('mg-likes-target').value = lgLikes.goal_target || 1000;
        if (get('mg-likes-label')) get('mg-likes-label').value = lgLikes.goal_label || 'Meta de curtidas';
        if (get('mg-gifts-kind')) get('mg-gifts-kind').value = lgGifts.goal_kind || 'gifts';
        if (get('mg-gifts-gift-wrap')) get('mg-gifts-gift-wrap').hidden = lgGifts.goal_kind !== 'gift_specific';
        if (lgGifts.goal_gift_id && get('mg-gifts-gift-id')) get('mg-gifts-gift-id').value = lgGifts.goal_gift_id;
        if (get('mg-gifts-target')) get('mg-gifts-target').value = lgGifts.goal_target || 500;
        if (get('mg-gifts-label')) get('mg-gifts-label').value = lgGifts.goal_label || 'Meta de presentes';
        if (get('mg-follows-target')) get('mg-follows-target').value = lgFollows.goal_target || 10000;
        if (get('mg-follows-baseline')) get('mg-follows-baseline').value = baseline !== null ? String(baseline) : '';
        if (get('mg-follows-label')) get('mg-follows-label').value = lgFollows.goal_label || 'Meta de seguidores';
      }
    }

    text(
      'audience-totals',
      Object.keys(totals).length
        ? `Curtidas ${sessionLikes} · Seguidores ${sessionFollows} · Comentários ${sum(totals.votes)} · Presentes ${sessionGifts} · Moedas ${sessionCoins} · Compartilhamentos ${sum(totals.shares)}`
        : 'Interações aguardando telemetria.'
    );
    text(
      'outbox-status',
      `Presentes aguardando confirmação: ${Number(data.pending_gifts || 0)} · Confirmados nesta execução: ${Number(metrics.gift_acks_total || 0)}`
    );
    const qSizes = data.queue_sizes || {};
    const caches = data.image_caches || {};
    const gCache = caches.gift_icons || {};
    const aCache = caches.viewer_avatars || {};
    text(
      'cache-diagnostics',
      `Filas P0:${qSizes.p0_admin || 0} P1:${qSizes.p1 || 0} P2:${qSizes.p2 || 0} · Miniaturas presentes: ${gCache.ready || 0} prontas (${gCache.pending || 0} pend.) · Avatares: ${
        aCache.enabled === false ? 'desativados' : `${aCache.ready || 0}/${aCache.max_avatars || 128} prontos`
      } · Auth: ${data.auth_mode || 'loopback_only'}`
    );

    const audio = data.audio || {};
    text('audio-status', `Voz: ${audio.voice_status || 'estado ainda não informado pelo jogo'}`);
    const audioFields = [
      ['audio-voices', 'voices_enabled'],
      ['audio-sfx', 'sfx_enabled'],
      ['audio-crowd', 'crowd_enabled'],
      ['audio-memes', 'memes_enabled'],
    ];
    const audioKnown = data.godot_connected && data.telemetry_fresh && audioFields.every(([, key]) => typeof audio[key] === 'boolean');
    for (const [id, key] of audioFields) {
      get(id).disabled = !audioKnown;
      if (audioKnown && !state.audioDirty && !get('audio-form').contains(document.activeElement)) get(id).checked = audio[key];
    }
    get('audio-apply').disabled = !audioKnown;
    text(
      'audio-confirmation',
      !audioKnown
        ? 'Aguardando confirmação do jogo para controlar o áudio.'
        : data.audio_settings_applied
        ? 'Estado do áudio confirmado pelo jogo.'
        : 'Alteração solicitada; aguardando confirmação do jogo.'
    );
    const leaders = get('top-supporters');
    if (leaders) {
      leaders.replaceChildren();
      const supporters = Array.isArray(audience.top_supporters) ? audience.top_supporters.slice(0, 5) : [];
      for (const supporter of supporters) {
        const row = document.createElement('li');
        const team = Number(supporter.team);
        row.textContent = `${supporter.display_name || 'Espectador'} · ${
          team === 1 ? '13 Lula' : team === 2 ? '22 Flávio' : 'Sem time'
        } · ${Number(supporter.coins || 0).toLocaleString('pt-BR')} moedas`;
        leaders.appendChild(row);
      }
      if (!supporters.length) {
        const row = document.createElement('li');
        row.textContent = 'Aguardando presentes contabilizados pelo jogo.';
        leaders.appendChild(row);
      }
    }
    const lead = get('tug-of-war-fill');
    if (lead && runners.length === 2) {
      const r1 = runners.find((r) => Number(r.slot || 1) === 1) || runners[0];
      const r2 = runners.find((r) => Number(r.slot || 2) === 2) || runners[1];
      const diff = Number(r1?.distance_meters || 0) - Number(r2?.distance_meters || 0);
      const pct = Math.abs(diff) < 0.01 ? 50 : Math.max(8, Math.min(92, 50 + (diff / 50) * 42));
      lead.style.width = `${pct.toFixed(1)}%`;
    }
  }

  async function poll() {
    try {
      const response = await fetch(`${base}/api/state`, { cache: 'no-store' });
      if (response.status === 401) {
        state.online = false;
        state.authRequired = true;
        const authSec = get('auth-unlock-section');
        if (authSec) authSec.hidden = false;
        text('text-backend-status', 'Autenticação local necessária (LIVE_BRIDGE_LOCAL_TOKEN)');
        text('text-godot-status', 'Bloqueado até autenticar');
        return;
      }
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      state.online = true;
      render(await response.json());
    } catch (_) {
      state.online = false;
      text('text-backend-status', 'Servidor indisponível; comandos não aplicados');
      text('text-godot-status', 'Estado não confirmado');
    }
  }

  async function refreshCatalog() {
    if (state.authRequired) return;
    const container = get('gift-catalog-list');
    if (!container || container.contains(document.activeElement)) return;
    try {
      const response = await fetch(`${base}/api/gifts`, { cache: 'no-store' });
      if (response.status === 401) return;
      if (!response.ok) throw new Error('Catálogo indisponível');
      const data = await response.json();
      container.replaceChildren();
      populateGiftSelect(get('goal-gift-id'), data.entries, state.snapshot.platform, state.snapshot.live_goal?.goal_gift_id);
      populateGiftSelect(
        get('mg-gifts-gift-id'),
        data.entries,
        state.snapshot.platform,
        state.snapshot.live_goals?.gifts?.goal_gift_id
      );
      if (!data.entries.length) {
        container.textContent = 'Nenhum presente identificado recebido nesta instância.';
        return;
      }
      for (const entry of data.entries) {
        const row = document.createElement('label');
        row.className = 'gift-catalog-row';
        const caption = document.createElement('span');
        caption.textContent = `${entry.gift_name} · ${entry.source} · ID ${entry.gift_id} · ${
          entry.unit_coin_value || 'valor desconhecido'
        } moeda(s)/unidade`;
        const select = document.createElement('select');
        select.className = 'form-select';
        select.setAttribute('aria-label', `Ação de ${entry.gift_name}`);
        for (const [value, name] of [
          ['default', 'Automático pelo valor'],
          ['boost', 'Impulso'],
          ['shield', 'Escudo'],
          ['attack', 'Ataque'],
          ['super_turbo', 'Super turbo'],
        ]) {
          const option = document.createElement('option');
          option.value = value;
          option.textContent = name;
          select.appendChild(option);
        }
        select.value = entry.override ? entry.action : 'default';
        select.addEventListener('change', async () => {
          try {
            const query = new URLSearchParams({ source: entry.source, gift_id: entry.gift_id, action: select.value });
            const result = await fetch(`${base}/api/admin/gift?${query}`, { cache: 'no-store' });
            if (!result.ok) throw new Error('Ação não confirmada');
            log('recibo', `Ação do presente ${entry.gift_id} atualizada`);
          } catch (error) {
            log('erro', error.message);
          }
        });
        row.append(caption, select);
        container.appendChild(row);
      }
    } catch (error) {
      log('erro', error.message);
    }
  }

  async function send(message) {
    try {
      if (state.ws?.readyState === WebSocket.OPEN) {
        const label =
          message.command ||
          (message.action ? `Ação ${message.action} (#${message.candidate_slot || 1})` : `Simular ${message.event_type || 'evento'}`);
        state.ws.send(JSON.stringify(message));
        log('solicitação', label);
        return true;
      }
      const simulation = message.type === 'simulate_event';
      const values = simulation
        ? { event_type: message.event_type, ...(message.data || {}) }
        : {
            command: message.command || (message.action === 'turbo' ? 'boost' : message.action),
            ...(message.params || {}),
            ...(message.candidate_slot ? { candidate_slot: message.candidate_slot } : {}),
          };
      const query = new URLSearchParams(
        Object.entries(values).map(([key, value]) => [
          key,
          value !== null && typeof value === 'object' ? JSON.stringify(value) : String(value),
        ])
      );
      const response = await fetch(`${base}/api/admin/${simulation ? 'simulate' : 'command'}?${query}`, { cache: 'no-store' });
      const ack = await response.json();
      if (!response.ok || !['ok', 'accepted', 'duplicate'].includes(ack.status)) throw new Error(ack.message || ack.status);
      log('recibo', ack.message || ack.status);
      await poll();
      return true;
    } catch (error) {
      log('erro', `Comando não confirmado: ${error.message}`);
      return false;
    }
  }

  function connect() {
    clearTimeout(state.reconnect);
    state.reconnect = null;
    if (state.ws) {
      state.ws.onclose = null;
      state.ws.close();
    }
    if (state.authRequired) return;
    const socket = new WebSocket(`${window.location.protocol === 'https:' ? 'wss' : 'ws'}://${window.location.host}/ws/admin`);
    state.ws = socket;
    socket.onopen = () => {
      state.online = true;
      log('conexão', 'Painel local conectado');
    };
    socket.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === 'state_update') render(data);
        else if (data.type === 'command_ack') log(data.status === 'ok' ? 'recibo' : 'erro', data.message || data.status);
        else if (data.type === 'telemetry_event') log('evento', data.action || 'Atualização');
      } catch (_) {
        log('erro', 'Resposta inválida');
      }
    };
    socket.onclose = () => {
      if (!state.reconnect && !state.authRequired) state.reconnect = setTimeout(connect, 2000);
    };
  }

  const click = (id, callback) => get(id)?.addEventListener('click', callback);
  const command = (value) => send({ type: 'admin_command', command: value });
  const simulate = (kind, slot, extra = {}) => {
    state.sequence += 1;
    const parsedSlot = slot === '0' || slot === 0 ? 0 : Number(slot || 1);
    return send({
      type: 'simulate_event',
      event_type: kind,
      data: {
        candidate_slot: parsedSlot,
        user_id: `sim_${kind}_${Date.now()}_${state.sequence}`,
        display_name: 'Teste local',
        ...extra,
      },
    });
  };

  get('auth-unlock-form')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const input = get('auth-token-input');
    const token = String(input?.value || '').trim();
    if (!token) {
      text('auth-unlock-feedback', 'Informe o LIVE_BRIDGE_LOCAL_TOKEN configurado no ambiente.');
      return;
    }
    try {
      const res = await fetch(`${base}/api/admin/session`, {
        method: 'GET',
        headers: { 'X-JOGI-Token': token },
        cache: 'no-store',
      });
      if (input) input.value = '';
      if (!res.ok) {
        text('auth-unlock-feedback', 'Token recusado pelo servidor local.');
        return;
      }
      state.authRequired = false;
      const authSec = get('auth-unlock-section');
      if (authSec) authSec.hidden = true;
      await poll();
      connect();
      await refreshCatalog();
      log('conexão', 'Sessão local autenticada via cookie HttpOnly.');
    } catch (error) {
      text('auth-unlock-feedback', `Falha ao autenticar: ${error.message}`);
    }
  });

  click('btn-reconnect', connect);
  for (const [id, value] of [
    ['btn-start-race', 'start_race'],
    ['btn-skip-lobby', 'skip_lobby'],
    ['btn-pause-race', 'pause_race'],
    ['btn-resume-race', 'resume_race'],
    ['btn-reset-dedup', 'reset_dedup'],
  ]) {
    click(id, () => command(value));
  }
  click('btn-restart-race', () => get('modal-restart')?.classList.add('active'));
  click('btn-cancel-restart', () => get('modal-restart')?.classList.remove('active'));
  click('btn-confirm-restart', () => {
    get('modal-restart')?.classList.remove('active');
    command('restart_race');
  });
  get('candidates-grid')?.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-action]');
    if (button) send({ type: 'candidate_action', action: button.dataset.action, candidate_slot: Number(button.dataset.slot) });
  });
  click('btn-sim-vote', () => simulate('vote', get('sim-vote-cand')?.value, { count: Number(get('sim-vote-qty')?.value || 1) }));
  document.querySelectorAll('[data-likes]').forEach((button) =>
    button.addEventListener('click', () => simulate('like', get('sim-like-cand')?.value, { count: Number(button.dataset.likes) }))
  );
  click('btn-sim-share', () => simulate('share', get('sim-share-cand')?.value));
  click('btn-sim-follow', () => simulate('follow', get('sim-share-cand')?.value));
  document.querySelectorAll('.gift-button[data-tier]').forEach((button) =>
    button.addEventListener('click', () => simulate('gift', get('sim-gift-cand')?.value, { gift_tier: button.dataset.tier, count: 1 }))
  );
  click('btn-sim-custom-gift', () => {
    const coins = Number(get('sim-gift-coins')?.value);
    const count = Number(get('sim-gift-count')?.value);
    if (!Number.isInteger(coins) || coins < 0 || coins > 100000 || !Number.isInteger(count) || count < 1 || count > 1000) {
      return log('erro', 'Valor ou quantidade inválidos');
    }
    simulate('gift', get('sim-gift-cand')?.value, { unit_coin_value: coins, count });
  });
  click('btn-burst-events', () => simulate('burst', 1, { count: 40 }));
  click('btn-clear-log', () => {
    get('terminal-log-body')?.replaceChildren();
    text('terminal-event-count', '0 eventos');
  });
  click('btn-refresh-gifts', refreshCatalog);
  get('goal-form')?.addEventListener('input', () => {
    state.goalDirty = true;
  });
  get('multi-goals-form')?.addEventListener('input', () => {
    state.multiGoalsDirty = true;
  });
  get('audio-form')?.addEventListener('input', () => {
    state.audioDirty = true;
  });
  get('kwai-collector-form')?.addEventListener('input', () => {
    state.kwaiUrlDirty = true;
  });

  const saveKwaiUrl = async (rawUrl) => {
    try {
      const query = new URLSearchParams({ live_url: String(rawUrl || '').trim() });
      const res = await fetch(`${base}/api/admin/kwai-collector?${query}`, { cache: 'no-store' });
      const payload = await res.json();
      if (!res.ok || payload.status !== 'ok') throw new Error(payload.message || 'URL Kwai inválida');
      state.kwaiUrlDirty = false;
      log(
        'recibo',
        payload.kwai_collector?.live_url
          ? `URL Kwai atualizada: ${payload.kwai_collector.live_url}`
          : 'Coletor Kwai restaurado para @mentalista..'
      );
      await poll();
    } catch (error) {
      log('erro', error.message);
    }
  };
  get('kwai-collector-form')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    await saveKwaiUrl(get('kwai-live-url')?.value || '');
  });
  click('btn-reset-kwai-url', async () => {
    const input = get('kwai-live-url');
    if (input) input.value = '';
    await saveKwaiUrl('');
  });
  get('audio-form')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (get('audio-apply').disabled) return;
    const params = {
      voices_enabled: get('audio-voices').checked,
      sfx_enabled: get('audio-sfx').checked,
      crowd_enabled: get('audio-crowd').checked,
      memes_enabled: get('audio-memes').checked,
    };
    if (await send({ type: 'admin_command', command: 'set_audio_settings', params })) state.audioDirty = false;
  });

  get('mg-gifts-kind')?.addEventListener('change', () => {
    if (get('mg-gifts-gift-wrap')) get('mg-gifts-gift-wrap').hidden = get('mg-gifts-kind').value !== 'gift_specific';
  });
  get('multi-goals-form')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const likesTarget = Number(get('mg-likes-target')?.value);
    const giftsKind = get('mg-gifts-kind')?.value || 'gifts';
    const giftsTarget = Number(get('mg-gifts-target')?.value);
    const giftsGiftId = get('mg-gifts-gift-id')?.value || '';
    const followsTarget = Number(get('mg-follows-target')?.value);
    const rawBaseline = String(get('mg-follows-baseline')?.value || '').trim();
    const baseline = rawBaseline === '' ? null : Number(rawBaseline);

    for (const val of [likesTarget, giftsTarget, followsTarget]) {
      if (!Number.isInteger(val) || val < 1 || val > 1000000000) {
        return log('erro', 'Alvo das metas deve ser inteiro entre 1 e 1.000.000.000.');
      }
    }
    if (baseline !== null && (!Number.isInteger(baseline) || baseline < 0 || baseline > 1000000000)) {
      return log('erro', 'Base manual de seguidores deve ser vazia ou inteiro >= 0.');
    }
    if (giftsKind === 'gift_specific' && !giftsGiftId) {
      return log('erro', 'Selecione um ID de presente observado para a meta específica.');
    }

    const liveGoals = {
      likes: {
        goal_kind: 'likes',
        goal_target: likesTarget,
        goal_label: String(get('mg-likes-label')?.value || 'Meta de curtidas').slice(0, 40),
      },
      gifts: {
        goal_kind: giftsKind,
        goal_target: giftsTarget,
        goal_label: String(get('mg-gifts-label')?.value || 'Meta de presentes').slice(0, 40),
        ...(giftsKind === 'gift_specific' ? { goal_gift_id: giftsGiftId } : {}),
      },
      follows: {
        goal_kind: 'follows',
        goal_target: followsTarget,
        goal_label: String(get('mg-follows-label')?.value || 'Meta de seguidores').slice(0, 40),
        follower_baseline: baseline,
      },
    };
    if (await send({ type: 'admin_command', command: 'set_live_goals', params: { live_goals: liveGoals } })) {
      state.multiGoalsDirty = false;
    }
  });

  get('goal-kind')?.addEventListener('change', () => {
    get('goal-gift-wrap').hidden = get('goal-kind').value !== 'gift_specific';
  });
  get('goal-form')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const target = Number(get('goal-target').value);
    if (!Number.isInteger(target) || target < 1 || target > 1000000000) return log('erro', 'Quantidade inválida');
    const kind = get('goal-kind').value;
    const giftId = get('goal-gift-id').value;
    if (kind === 'gift_specific' && !giftId) {
      log('erro', 'Receba um presente identificado e selecione o ID antes de aplicar esta meta.');
      return;
    }
    if (
      await send({
        type: 'admin_command',
        command: 'set_live_goal',
        params: {
          goal_kind: kind,
          goal_target: target,
          goal_label: get('goal-label').value.slice(0, 40),
          ...(kind === 'gift_specific' ? { goal_gift_id: giftId } : {}),
        },
      })
    ) {
      state.goalDirty = false;
    }
  });
  connect();
  poll();
  refreshCatalog();
  setInterval(poll, 1000);
  setInterval(refreshCatalog, 5000);
})();
