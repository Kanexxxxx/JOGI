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
    receipts: new Map(),
    inFlightCommands: new Set(),
    receiptWaiters: new Map(),
    modalCommand: null,
    modalReturnFocus: null,
    lastEventsSignature: '',
    pollRunning: false,
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

  const finalReceipts = new Set(['applied', 'rejected', 'timeout', 'disconnected']);
  const commandLabels = {start_race:'Iniciar',skip_lobby:'Pular lobby',pause_race:'Pausar',resume_race:'Continuar',restart_race:'Reiniciar',reset_dedup:'Limpar deduplicação',set_live_goals:'Alterar três metas',set_live_goal:'Alterar meta',set_audio_settings:'Alterar áudio',boost:'Impulso',shield:'Escudo',attack:'Ataque',end_experience:'Encerrar experiência'};
  function feedback(message, kind = 'info') {
    text('command-feedback', message);
    const element = get('command-feedback');
    if (element) element.dataset.status = kind;
  }
  function observeReceipt(receipt, notify = false) {
    if (!receipt || !receipt.event_id || !receipt.status) return;
    const previous = state.receipts.get(receipt.event_id);
    if (previous && ['applied','rejected'].includes(previous.status) && receipt.status==='queued') return;
    state.receipts.set(receipt.event_id, {...previous, ...receipt});
    while (state.receipts.size > 100) state.receipts.delete(state.receipts.keys().next().value);
    const applied = receipt.status === 'applied';
    if (notify && previous?.status !== receipt.status) {
      const message = `${commandLabels[receipt.command] || receipt.command || 'Comando'}: ${applied ? 'executado e confirmado pelo jogo' : receipt.status === 'queued' ? 'na fila; aguardando execução do jogo' : receipt.status === 'rejected' ? 'recusado pelo jogo' : 'sem confirmação de execução'}`;
      feedback(message, applied ? 'success' : receipt.status === 'queued' ? 'pending' : 'error');
      log(applied ? 'confirmado' : receipt.status === 'queued' ? 'aguardando' : 'atenção', message);
    }
    const waiter = state.receiptWaiters.get(receipt.event_id);
    if (waiter && finalReceipts.has(receipt.status)) {
      clearTimeout(waiter.timer);
      state.receiptWaiters.delete(receipt.event_id);
      waiter.resolve(applied);
      if(!notify) feedback(`${commandLabels[receipt.command] || receipt.command}: ${applied ? 'executado e confirmado pelo jogo' : 'execução não confirmada pelo jogo'}`,applied?'success':'error');
    }
    renderReceipts();
    updateControls();
  }
  function renderReceipts() {
    const list = get('command-receipts');
    if (!list) return;
    const receipts = [...state.receipts.values()].slice(-8).reverse();
    list.replaceChildren();
    for (const item of receipts) {
      const li = document.createElement('li');
      li.dataset.status = item.status;
      const labels = {queued:'Aguardando execução',applied:'Confirmado pelo jogo',rejected:'Recusado',timeout:'Confirmação não recebida',disconnected:'Jogo desconectou antes da confirmação'};
      li.textContent = `${commandLabels[item.command] || item.command || 'Comando'} · ${labels[item.status] || 'Estado pendente'}`;
      if (item.message) li.title = String(item.message).slice(0,240);
      list.appendChild(li);
    }
    if (!receipts.length) { const li=document.createElement('li');li.textContent='Nenhum comando registrado nesta execução.';list.appendChild(li); }
  }
  function waitForReceipt(eventId) {
    const known = state.receipts.get(eventId);
    if (known && finalReceipts.has(known.status)) {
      const applied = known.status === 'applied';
      feedback(`${commandLabels[known.command] || known.command}: ${applied ? 'executado e confirmado pelo jogo' : 'execução não confirmada pelo jogo'}`, applied ? 'success' : 'error');
      return Promise.resolve(applied);
    }
    return new Promise(resolve => {
      const timer = setTimeout(() => {
        state.receiptWaiters.delete(eventId);
        feedback('Comando enviado, mas a execução ainda não foi confirmada. Confira os recibos antes de repetir.', 'pending');
        log('atenção','Execução ainda sem confirmação do jogo. Não foi apresentada como sucesso.');
        resolve(false);
      },12000);
      state.receiptWaiters.set(eventId,{resolve,timer});
    });
  }
  function commandPending(command) { return state.inFlightCommands.has(command) || [...state.receipts.values()].some(r=>r.command===command && r.status==='queued'); }
  function updateControls() {
    const data=state.snapshot;
    const backendReady=state.online && !state.authRequired;
    const gameReady=backendReady && data.godot_connected===true && data.telemetry_fresh===true;
    const persistenceBlocked=gameReady && data.runtime_mode==='production' && data.telemetry?.persistence?.ready!==true;
    const ended=data.operational_shutdown?.ended===true || data.telemetry?.experience_ended===true;
    const commands = {'btn-start-race':'start_race','btn-skip-lobby':'skip_lobby','btn-pause-race':'pause_race','btn-resume-race':'resume_race','btn-restart-race':'restart_race','btn-reset-dedup':'reset_dedup','btn-end-experience':'end_experience','btn-apply-multi-goals':'set_live_goals','audio-apply':'set_audio_settings'};
    for(const [id,command] of Object.entries(commands)) {
      const el=get(id);if(!el) continue;
      const config=['set_live_goal','set_live_goals','set_audio_settings'].includes(command);
      const recoveryControl = ['resume','resume_race','pause','pause_race'].includes(command) && backendReady && Boolean(data.godot_connected);
      el.disabled=!(gameReady || recoveryControl) || (ended && !config) || commandPending(command);
      if(persistenceBlocked && !config && !['pause_race','end_experience'].includes(command)) el.disabled=true;
      if(command==='end_experience') el.disabled=!backendReady || ended || commandPending(command);
      if(id==='audio-apply') el.disabled ||= !['voices_enabled','sfx_enabled','crowd_enabled','memes_enabled'].every(k=>typeof data.audio?.[k]==='boolean');
      el.title=!backendReady?'Conexão autenticada indisponível':persistenceBlocked?'Armazenamento do jogo exige recuperação':!gameReady?'Aguardando telemetria atual do jogo':ended&&!config?'Experiência encerrada definitivamente':commandPending(command)?'Aguardando confirmação deste comando':'';
    }
    for(const el of document.querySelectorAll('#goal-form button[type="submit"], #candidates-grid button[data-action]')) { const action=el.dataset.action; const pending=action ? (action==='turbo'?'boost':action) : 'set_live_goal';el.disabled=!gameReady || Boolean((ended || persistenceBlocked) && el.closest('#candidates-grid')) || commandPending(pending); }
    for(const el of document.querySelectorAll('#simulator-section button')) el.disabled=!gameReady || ended || data.simulation_allowed!==true;
    for(const el of document.querySelectorAll('#gift-catalog-list select, #kwai-collector-form button')) el.disabled=!backendReady;
    const simulator=get('simulator-section');if(simulator) simulator.hidden=data.simulation_allowed!==true;
    const mode=data.runtime_mode==='development'?'DESENVOLVIMENTO · eventos sintéticos permitidos':'PRODUÇÃO · simulação bloqueada';
    text('runtime-mode',mode);
    text('storage-attention',persistenceBlocked?'ATENÇÃO: a persistência do jogo está indisponível. A corrida permanece bloqueada; presentes aguardam confirmação. Recupere os dados antes de continuar.':'');
  }
  function safeCachedImage(value,kind) {
    const pattern=kind==='avatar'?/^\/viewer-avatars\/[a-f0-9]{64}$/:/^\/gift-icons\/[a-f0-9]{64}$/;
    return typeof value==='string' && pattern.test(value) ? value : null;
  }
  function visual(value,kind,label) {
    const holder=document.createElement('span');holder.className=kind==='avatar'?'viewer-avatar':'gift-thumbnail';
    holder.textContent=kind==='avatar' ? (String(label||'?').trim().slice(0,1).toUpperCase()||'?') : '◇';
    const url=safeCachedImage(value,kind);
    if(url) { const img=document.createElement('img');img.src=url;img.alt=kind==='avatar'?'':'Ícone do presente';img.loading='lazy';img.referrerPolicy='no-referrer';img.addEventListener('error',()=>img.remove());holder.appendChild(img); }
    return holder;
  }
  function renderEvents(events) {
    const list=get('live-events');if(!list||!Array.isArray(events)) return;
    const recent=events.slice(-30).reverse();
    const signature=JSON.stringify(recent);
    if(signature===state.lastEventsSignature) return;state.lastEventsSignature=signature;
    list.replaceChildren();
    const statusLabels={received:'Recebido',queued:'Na fila',dispatched:'Enviado ao jogo',confirmed:'Confirmado pelo jogo',rejected:'Rejeitado',duplicate:'Duplicado',after_close_pending:'Presente preservado após encerramento'};
    const kinds={gift:'Presente',vote:'Comentário / voto',like_batch:'Curtidas',follow:'Novo seguidor',share:'Compartilhamento',chat:'Comentário'};
    for(const event of recent) {
      const payload=event.payload||{};const user=event.user||{};
      const row=document.createElement('li');row.className='live-event-row';row.dataset.status=event.processing_status||'received';
      const name=user.display_name || user.user_id || 'Identificação não fornecida';
      row.appendChild(visual(payload.avatar_icon_path,'avatar',name));
      const body=document.createElement('div');body.className='event-body';
      const title=document.createElement('strong');title.textContent=name;body.appendChild(title);
      const detail=document.createElement('span');
      const parts=[String(event.source||'Origem não fornecida').toUpperCase(),kinds[event.event_type]||event.event_type||'Interação'];
      if(event.event_type==='gift') {
        parts.push(payload.gift_name || (payload.gift_id ? `ID ${payload.gift_id}` : 'Nome não fornecido'));
        if(Number.isInteger(payload.repeat_count)) parts.push(`×${payload.repeat_count}`);
        if(Number.isInteger(payload.coin_value) && payload.coin_value>0) parts.push(`${payload.coin_value.toLocaleString('pt-BR')} moedas`);
        else parts.push('Moedas não informadas');
      } else if(payload.vote_keyword) parts.push(String(payload.vote_keyword));
      else if(payload.candidate_slot===1||payload.candidate_slot===2) parts.push(payload.candidate_slot===1?'13 Lula':'22 Flávio');
      if(event.event_type==='like_batch' && Number.isInteger(payload.like_count)) parts.push(`+${payload.like_count}`);
      detail.textContent=parts.join(' · ');body.appendChild(detail);
      const status=document.createElement('small');status.textContent=statusLabels[event.processing_status]||'Recebido';body.appendChild(status);
      row.appendChild(body);if(event.event_type==='gift') row.appendChild(visual(payload.gift_icon_path,'gift',''));list.appendChild(row);
    }
    if(!recent.length) {const li=document.createElement('li');li.className='empty-state';li.textContent='Nenhuma interação recebida nesta execução.';list.appendChild(li);}
  }
  function renderShutdown(value={}) {
    const date=value.end_at ? new Date(value.end_at) : null;
    text('shutdown-deadline',date && !Number.isNaN(date.getTime()) ? `Encerramento do jogo: ${date.toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'})} · horário de Brasília` : 'Horário de encerramento não configurado ou inválido.');
    text('shutdown-state',value.ended ? 'ENCERRADO DEFINITIVAMENTE' : value.end_at ? 'Programação ativa' : 'Aguardando configuração');
    text('shutdown-detail',`${value.ended ? 'Novas rodadas bloqueadas. ' : ''}Presentes pendentes preservados: ${Number(value.pending_gifts||0)}. ${value.reason ? `Motivo: ${value.reason}. ` : ''}OBS, plataformas e computador não são desligados.`);
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
    for(const receipt of Array.isArray(data.recent_commands)?data.recent_commands:[]) observeReceipt(receipt);
    renderEvents(data.recent_events);
    renderShutdown(data.operational_shutdown);
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
        : collector === 'account_not_found' || collector === 'room_unavailable'
        ? `${platform.toUpperCase()}: sala indisponível ou consulta inconclusiva; perfil não declarado inexistente`
        : collector === 'rate_limited'
        ? 'TikTok: limite de requisições · aguardando intervalo de segurança'
        : collector === 'access_blocked'
        ? 'TikTok: acesso à consulta bloqueado · requer verificação'
        : collector === 'connection_error'
        ? 'TikTok: erro de conexão · nova tentativa com espera'
        : collector === 'webhook_listening'
        ? 'Kwai: receptor :8786 ativo · aguardando coletor/sala'
        : collector === 'login_required'
        ? 'Kwai: login único necessário (ABRIR_NAVEGADOR_KWAI.cmd)'
        : collector === 'kwai_requires_collector'
        ? 'Kwai: coletor pendente; conexão com sala real ainda não comprovada'
        : `Coletor: ${collector || 'não conectado'}`
    );
    const stateName = String(data.race_state || 'Aguardando');
    const stateLabels={LOBBY_VOTACAO:'Aguardando largada',COUNTDOWN:'Contagem regressiva',RACING:'Corrida em andamento',PHOTO_FINISH:'Chegada',PODIO:'Pódio',ENDED:'Experiência encerrada'};
    text('race-state-badge',!data.telemetry_fresh ? 'Aguardando jogo' : data.telemetry?.race_paused ? 'Corrida pausada' : stateLabels[stateName] || stateName);
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
    text('timer-phase', data.telemetry_fresh ? clock(data.phase_timer_seconds) : '—');
    text('timer-total', data.telemetry_fresh ? clock(data.race_timer_seconds) : '—');
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
    const wins=Array.isArray(rawTelemetry.cycle_wins)?rawTelemetry.cycle_wins:null;
    const winner=Number(rawTelemetry.winner_id);
    text('round-result',wins ? `${winner===1?'Vencedor da rodada:13 Lula. ':winner===2?'Vencedor da rodada:22 Flávio. ':'Nenhum vencedor confirmado nesta rodada. '}Ciclo ${rawTelemetry.cycle_number||1}:13 Lula ${Number(wins[0]||0)} × ${Number(wins[1]||0)} Flávio22.` : 'Resultado e placar do ciclo aguardando telemetria.');
    const history = get('round-history');
    if (history) {
      history.replaceChildren();
      const results = Array.isArray(rawTelemetry.round_history) ? rawTelemetry.round_history.slice(-10).reverse() : [];
      for (const result of results) {
        const row = document.createElement('li');
        const winnerName = result.winner_slot === 1 ? '13 Lula' : result.winner_slot === 2 ? '22 Flávio' : 'Empate';
        row.textContent = `C${Number(result.cycle)} · Rodada ${Number(result.round)} · ${winnerName} · Lula ${Number(result.lula_m).toFixed(1)} m / Flávio ${Number(result.flavio_m).toFixed(1)} m`;
        history.appendChild(row);
      }
      if (!results.length) { const row=document.createElement('li'); row.textContent='Nenhuma rodada concluída confirmada nesta sessão.'; history.appendChild(row); }
    }
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

    const runners = Array.isArray(data.candidates) ? [...data.candidates].sort((a,b)=>Number(a.position||99)-Number(b.position||99)) : [];
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
      text(`${prefix}-pos`, data.telemetry_fresh ? `${runner.position}º` : '—');
      text(`${prefix}-meters`, data.telemetry_fresh ? `${distance.toFixed(1)} m` : '—');
      text(`${prefix}-speed`, data.telemetry_fresh ? `${speed.toFixed(1)} m/s` : '—');
      text(`${prefix}-votes`, data.telemetry_fresh ? runner.votes || 0 : '—');
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
          cell.textContent = data.telemetry_fresh || String(value).startsWith(number+' ') ? String(value) : '—';
          row.appendChild(cell);
        }
        table.appendChild(row);
      }
    }

    updateControls();
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
    text('audio-status', `Voz: ${audio.voice_status ? String(audio.voice_status).replaceAll('_',' ').toLowerCase() : 'estado ainda não informado pelo jogo'}`);
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
    updateControls();
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
    if(state.pollRunning) return;
    state.pollRunning=true;
    try {
      const response = await fetch(`${base}/api/state`, { cache: 'no-store' });
      if (response.status === 401) {
        state.online = false;
        state.authRequired = true;
        const authSec = get('auth-unlock-section');
        if (authSec) authSec.hidden = false;
        text('text-backend-status', 'Autenticação local necessária (LIVE_BRIDGE_LOCAL_TOKEN)');
        text('text-godot-status', 'Bloqueado até autenticar');
        updateControls();
        return;
      }
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      state.online = true;
      render(await response.json());
    } catch (_) {
      state.online = false;
      text('text-backend-status', 'Servidor indisponível; comandos não aplicados');
      text('text-godot-status', 'Estado não confirmado');
      updateControls();
    } finally { state.pollRunning=false; }
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
            log('configuração', `Regra do presente ${entry.gift_id} salva na ponte para os próximos presentes.`);
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
    const simulation=message.type==='simulate_event';
    const commandName=message.command || (message.action==='turbo'?'boost':message.action);
    if(!state.online || state.authRequired) { feedback('Conexão autenticada indisponível. Nenhum comando enviado.','error');return false; }
    if(simulation && state.snapshot.simulation_allowed!==true) { feedback('Simulação bloqueada no modo de produção.','error');return false; }
    if(commandName!=='end_experience' && (!state.snapshot.godot_connected || (!state.snapshot.telemetry_fresh && !['resume','resume_race','pause','pause_race'].includes(commandName)))) { feedback('Aguardando telemetria atual do jogo. Nenhum comando enviado.','error');return false; }
    if(commandName && commandPending(commandName)) { feedback('Este comando já está aguardando confirmação.','pending');return false; }
    if(commandName) {state.inFlightCommands.add(commandName);updateControls();}
    try {
      const values=simulation ? {event_type:message.event_type,...(message.data||{})} : {command:commandName,...(message.params||{}),...(message.candidate_slot?{candidate_slot:message.candidate_slot}:{})};
      const query=new URLSearchParams(Object.entries(values).map(([key,value])=>[key,value!==null && typeof value==='object'?JSON.stringify(value):String(value)]));
      feedback(simulation?'Enviando evento sintético isolado…':'Enviando solicitação ao jogo…','pending');
      const response=await fetch(`${base}/api/admin/${simulation?'simulate':'command'}?${query}`,{cache:'no-store'});
      const ack=await response.json();
      if(!response.ok || !['ok','accepted','duplicate','queued','applied'].includes(ack.status)) throw new Error(ack.message||'Solicitação recusada');
      if(simulation) {log('teste','Evento sintético aceito pela ponte; não representa uma interação real.');await poll();return true;}
      if(!ack.event_id) {feedback('Ponte recebeu a solicitação; execução do jogo ainda sem confirmação.','pending');log('atenção','Resposta sem recibo de execução do jogo.');return false;}
      observeReceipt({...ack,command:commandName,status:ack.status==='applied'?'applied':'queued'},true);
      await poll();
      return await waitForReceipt(ack.event_id);
    } catch(error) {feedback(`Solicitação não confirmada: ${error.message}`,'error');log('erro',`Comando não confirmado: ${error.message}`);return false;} finally {if(commandName) state.inFlightCommands.delete(commandName);updateControls();}
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
        else if (data.type === 'command_ack' || data.type === 'command_result') { if(data.event_id) observeReceipt(data,true); else if(data.status==='error') {feedback(data.message||'Comando recusado','error');log('erro',data.message||'Comando recusado');} }
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
  ]) {
    click(id, () => command(value));
  }
  function closeConfirmation() {
    get('modal-restart')?.classList.remove('active');state.modalCommand=null;
    state.modalReturnFocus?.focus();
  }
  function confirmAction(commandName,title,description) {
    state.modalCommand=commandName;state.modalReturnFocus=document.activeElement;
    text('modal-restart-title',title);text('modal-restart-desc',description);
    get('modal-restart')?.classList.add('active');get('btn-cancel-restart')?.focus();
  }
  click('btn-restart-race',()=>confirmAction('restart_race','Reiniciar a rodada?','Os corredores voltarão à largada e o cronômetro da rodada será reiniciado. Presentes já registrados não são apagados.'));
  click('btn-reset-dedup',()=>confirmAction('reset_dedup','Limpar a deduplicação?','Esta ação remove a proteção de repetição em memória do jogo. Eventos reenviados podem exigir conferência. Não limpa presentes duráveis nem histórico.'));
  click('btn-end-experience',()=>confirmAction('end_experience','Encerrar a experiência definitivamente?','Novas rodadas serão bloqueadas inclusive após reiniciar o programa. Presentes pendentes permanecem preservados. A transmissão externa e o computador não serão desligados.'));
  click('btn-cancel-restart',closeConfirmation);
  click('btn-confirm-restart',()=>{const selected=state.modalCommand;closeConfirmation();if(selected) command(selected);});
  get('modal-restart')?.addEventListener('keydown',event=>{
    if(event.key==='Escape'){event.preventDefault();closeConfirmation();}
    if(event.key==='Tab'){const controls=[get('btn-cancel-restart'),get('btn-confirm-restart')];const index=controls.indexOf(document.activeElement);event.preventDefault();controls[(index+(event.shiftKey?-1:1)+controls.length)%controls.length]?.focus();}
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
  updateControls();
  connect();
  poll();
  refreshCatalog();
  setInterval(poll, 1000);
  setInterval(refreshCatalog, 5000);
})();
