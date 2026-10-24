/**
 * Corrida dos Candidatos • Live Control Room
 * Client JavaScript Application (app.js)
 * 
 * Features:
 * - Primary WebSocket connection (ws://127.0.0.1:8765/ws/admin)
 * - Automatic exponential backoff reconnection (1s..10s)
 * - Graceful fallback to HTTP polling (GET /api/state, POST /api/admin/command, POST /api/admin/simulate)
 * - Smooth, non-destructive DOM updates (preserves input focus)
 * - 100% strict string sanitization (textContent only, zero unsanitized innerHTML)
 * - Full telemetry, candidate controls, live event simulator and event logs
 */

(function () {
  'use strict';

  // --- Configuration & Endpoints ---
  const CONFIG = {
    wsHost: window.location.hostname || '127.0.0.1',
    wsPort: window.location.port || 8765,
    wsPath: '/ws/admin',
    httpBase: window.location.origin,
    reconnectMinMs: 1000,
    reconnectMaxMs: 10000,
    httpPollIntervalMs: 500,
    maxLogEntries: 50
  };

  // --- State Store ---
  const state = {
    ws: null,
    wsConnected: false,
    godotConnected: false,
    platform: 'local',
    telemetryFresh: false,
    reconnectAttempts: 0,
    reconnectTimer: null,
    httpPollingTimer: null,
    raceState: 'LOBBY_VOTACAO',
    phaseTimer: 20.0,
    raceTimer: 0.0,
    metrics: {
      received_total: 0,
      accepted_total: 0,
      duplicates_dropped: 0,
      invalid_rejected: 0,
      dispatched_to_godot: 0
    },
    candidates: [
      { slot: 1, name: 'Lula', color: '#FF3B5C', position: 1, distance_meters: 0.0, progress_pct: 0, speed_mps: 12.0, votes: 0, status: { turbo: false, shield: false, stumble: false } },
      { slot: 2, name: 'Bolsonaro', color: '#00A8FF', position: 2, distance_meters: 0.0, progress_pct: 0, speed_mps: 12.0, votes: 0, status: { turbo: false, shield: false, stumble: false } }
    ],
    logEntriesCount: 0
  };

  // --- DOM Elements Cache ---
  const dom = {
    dotBackend: document.getElementById('dot-backend'),
    textBackend: document.getElementById('text-backend-status'),
    dotGodot: document.getElementById('dot-godot'),
    textGodot: document.getElementById('text-godot-status'),
    btnReconnect: document.getElementById('btn-reconnect'),

    // Match control
    raceStateBadge: document.getElementById('race-state-badge'),
    timerPhase: document.getElementById('timer-phase'),
    timerTotal: document.getElementById('timer-total'),
    advantageDisplay: document.getElementById('advantage-display'),
    tugOfWarFill: document.getElementById('tug-of-war-fill'),
    btnStartRace: document.getElementById('btn-start-race'),
    btnSkipLobby: document.getElementById('btn-skip-lobby'),
    btnRestartRace: document.getElementById('btn-restart-race'),
    btnResetDedup: document.getElementById('btn-reset-dedup'),

    // Modal
    modalRestart: document.getElementById('modal-restart'),
    btnCancelRestart: document.getElementById('btn-cancel-restart'),
    btnConfirmRestart: document.getElementById('btn-confirm-restart'),

    // Simulator
    simVoteCand: document.getElementById('sim-vote-cand'),
    simVoteQty: document.getElementById('sim-vote-qty'),
    btnSimVote: document.getElementById('btn-sim-vote'),
    simLikeCand: document.getElementById('sim-like-cand'),
    btnLike10: document.getElementById('btn-like-10'),
    btnLike50: document.getElementById('btn-like-50'),
    btnLike200: document.getElementById('btn-like-200'),
    simShareCand: document.getElementById('sim-share-cand'),
    btnSimShare: document.getElementById('btn-sim-share'),
    simGiftCand: document.getElementById('sim-gift-cand'),
    btnBurst: document.getElementById('btn-burst-events'),

    // Telemetry & Metrics
    metricReceived: document.getElementById('metric-received'),
    metricAccepted: document.getElementById('metric-accepted'),
    metricDropped: document.getElementById('metric-dropped'),
    metricRejected: document.getElementById('metric-rejected'),
    telemetryTableBody: document.getElementById('telemetry-table-body'),
    terminalLogBody: document.getElementById('terminal-log-body'),
    terminalCount: document.getElementById('terminal-event-count'),
    btnClearLog: document.getElementById('btn-clear-log')
  };

  // --- Formatting Helpers ---
  function formatSecondsToMMSS(seconds) {
    const s = Math.max(0, Math.floor(seconds || 0));
    const mins = Math.floor(s / 60);
    const secs = s % 60;
    return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  }

  function getTimestampString() {
    const d = new Date();
    return `[${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}:${String(d.getSeconds()).padStart(2, '0')}]`;
  }

  // --- Event Feed Logger (Strictly XSS-Safe) ---
  function appendLogEntry(type, user, actionText) {
    if (!dom.terminalLogBody) return;

    const row = document.createElement('div');
    row.className = `log-entry ${type}`;

    const tsSpan = document.createElement('span');
    tsSpan.className = 'log-ts';
    tsSpan.textContent = getTimestampString();

    const typeSpan = document.createElement('span');
    typeSpan.className = `log-type ${type}`;
    typeSpan.textContent = type.toUpperCase();

    const userSpan = document.createElement('span');
    userSpan.className = 'log-user';
    userSpan.textContent = String(user || 'anon');

    const actionSpan = document.createElement('span');
    actionSpan.className = 'log-action';
    actionSpan.textContent = String(actionText || '');

    row.appendChild(tsSpan);
    row.appendChild(typeSpan);
    row.appendChild(userSpan);
    row.appendChild(actionSpan);

    dom.terminalLogBody.appendChild(row);
    state.logEntriesCount++;

    // Prune entries exceeding max limit
    while (dom.terminalLogBody.children.length > CONFIG.maxLogEntries) {
      dom.terminalLogBody.removeChild(dom.terminalLogBody.firstElementChild);
    }

    if (dom.terminalCount) {
      dom.terminalCount.textContent = `${dom.terminalLogBody.children.length} eventos`;
    }

    // Auto-scroll to latest
    dom.terminalLogBody.scrollTop = dom.terminalLogBody.scrollHeight;
  }

  // --- Update UI with State Data (Zero Layout Thrashing & No Focus Loss) ---
  function updateUI() {
    // 1. Connection Status Badges
    if (dom.dotBackend && dom.textBackend) {
      if (state.wsConnected) {
        dom.dotBackend.className = 'status-indicator-dot online';
        dom.textBackend.textContent = `${state.platform.toUpperCase()} · WS local`;
      } else {
        dom.dotBackend.className = 'status-indicator-dot connecting';
        dom.textBackend.textContent = 'HTTP Fallback';
      }
    }

    if (dom.dotGodot && dom.textGodot) {
      if (state.godotConnected) {
        dom.dotGodot.className = 'status-indicator-dot online';
        dom.textGodot.textContent = state.telemetryFresh ? 'Conectado · telemetria recente' : 'Conectado · aguardando telemetria';
      } else {
        dom.dotGodot.className = 'status-indicator-dot';
        dom.textGodot.textContent = 'Aguardando Godot';
      }
    }

    // 2. Race State & Timers
    if (dom.raceStateBadge) {
      dom.raceStateBadge.textContent = state.raceState;
      let badgeClass = 'race-state-badge';
      if (state.raceState.includes('LOBBY')) badgeClass += ' state-lobby';
      else if (state.raceState.includes('COUNTDOWN')) badgeClass += ' state-countdown';
      else if (state.raceState.includes('RACING')) badgeClass += ' state-racing';
      else if (state.raceState.includes('PHOTO')) badgeClass += ' state-photofinish';
      else if (state.raceState.includes('PODIO')) badgeClass += ' state-podio';
      dom.raceStateBadge.className = badgeClass;
    }

    if (dom.timerPhase) {
      dom.timerPhase.textContent = formatSecondsToMMSS(state.phaseTimer);
    }
    if (dom.timerTotal) {
      dom.timerTotal.textContent = formatSecondsToMMSS(state.raceTimer);
    }

    // 3. Metrics Counters
    if (dom.metricReceived) dom.metricReceived.textContent = String(state.metrics.received_total || 0);
    if (dom.metricAccepted) dom.metricAccepted.textContent = String(state.metrics.accepted_total || 0);
    if (dom.metricDropped) dom.metricDropped.textContent = String(state.metrics.duplicates_dropped || 0);
    if (dom.metricRejected) dom.metricRejected.textContent = String(state.metrics.invalid_rejected || 0);

    // 4. Candidate Cards Update
    state.candidates.forEach((cand) => {
      const slot = cand.slot;
      const nameEl = document.getElementById(`c${slot}-name`);
      const posEl = document.getElementById(`c${slot}-pos`);
      const metersEl = document.getElementById(`c${slot}-meters`);
      const fillEl = document.getElementById(`c${slot}-fill`);
      const speedEl = document.getElementById(`c${slot}-speed`);
      const votesEl = document.getElementById(`c${slot}-votes`);
      const badgesRow = document.getElementById(`c${slot}-badges`);
      const progBar = document.getElementById(`c${slot}-prog-bar`);

      if (nameEl && cand.name) {
        nameEl.textContent = `#${slot} ${cand.name}`;
      }

      if (posEl) {
        posEl.textContent = `${cand.position}º`;
        if (cand.position === 1) {
          posEl.className = 'pos-badge first tabular-nums';
        } else {
          posEl.className = 'pos-badge tabular-nums';
        }
      }

      if (metersEl) {
        metersEl.textContent = `${Number(cand.distance_meters || 0).toFixed(1)}m`;
      }
      const maxDist = Math.max(50.0, ...state.candidates.map((c) => c.distance_meters || 0));
      const pct = Math.max(0, Math.min(100, Math.round(((cand.distance_meters || 0) / maxDist) * 100)));
      if (fillEl) {
        fillEl.style.width = `${pct}%`;
      }
      if (progBar) {
        progBar.setAttribute('aria-valuenow', String(pct));
      }

      if (speedEl) {
        speedEl.textContent = `${Number(cand.speed_mps || 10.0).toFixed(1)} m/s`;
      }
      if (votesEl) {
        votesEl.textContent = String(cand.votes || 0);
      }

      if (badgesRow) {
        // Clear and rebuild chips safely with createElement
        badgesRow.replaceChildren();
        if (cand.status?.turbo) {
          const chip = document.createElement('span');
          chip.className = 'status-chip turbo';
          chip.textContent = '⚡ TURBO';
          badgesRow.appendChild(chip);
        }
        if (cand.status?.shield) {
          const chip = document.createElement('span');
          chip.className = 'status-chip shield';
          chip.textContent = '🛡️ ESCUDO';
          badgesRow.appendChild(chip);
        }
        if (cand.status?.stumble) {
          const chip = document.createElement('span');
          chip.className = 'status-chip stumble';
          chip.textContent = '💥 TROPEÇO';
          badgesRow.appendChild(chip);
        }
      }
    });

    // 4b. Tug-of-War Advantage Display Update
    const cand1 = state.candidates.find((c) => c.slot === 1);
    const cand2 = state.candidates.find((c) => c.slot === 2);
    if (cand1 && cand2 && dom.advantageDisplay && dom.tugOfWarFill) {
      const d1 = cand1.distance_meters || 0;
      const d2 = cand2.distance_meters || 0;
      const diff = d1 - d2;
      const clampedDiff = Math.max(-30.0, Math.min(30.0, diff));
      const fillPct = 50.0 + (clampedDiff / 30.0) * 45.0;
      dom.tugOfWarFill.style.width = `${fillPct.toFixed(1)}%`;
      if (diff > 0.5) {
        dom.advantageDisplay.textContent = `🚩 +${diff.toFixed(1)}m LULA NA FRENTE`;
        dom.advantageDisplay.style.color = '#FF3B5C';
      } else if (diff < -0.5) {
        dom.advantageDisplay.textContent = `🚩 +${(-diff).toFixed(1)}m BOLSONARO NA FRENTE`;
        dom.advantageDisplay.style.color = '#00A8FF';
      } else {
        dom.advantageDisplay.textContent = '⚔️ EMPATADOS';
        dom.advantageDisplay.style.color = '#FBBF24';
      }
    }

    // 5. Leaderboard Table
    updateLeaderboardTable();
  }

  function updateLeaderboardTable() {
    if (!dom.telemetryTableBody) return;

    // Sort by position ascending
    const sorted = [...state.candidates].sort((a, b) => (a.position || 0) - (b.position || 0));

    dom.telemetryTableBody.replaceChildren();

    sorted.forEach((c) => {
      const tr = document.createElement('tr');

      const tdPos = document.createElement('td');
      tdPos.className = 'table-data-num';
      tdPos.textContent = `${c.position}º`;

      const tdCand = document.createElement('td');
      tdCand.textContent = `#${c.slot} ${c.name}`;
      tdCand.style.color = c.color;
      tdCand.style.fontWeight = '700';

      const tdDist = document.createElement('td');
      tdDist.className = 'table-data-num';
      tdDist.textContent = `${Number(c.distance_meters || 0).toFixed(1)}m`;

      const tdSpeed = document.createElement('td');
      tdSpeed.className = 'table-data-num';
      tdSpeed.textContent = `${Number(c.speed_mps || 10).toFixed(1)} m/s`;

      const tdVotes = document.createElement('td');
      tdVotes.className = 'table-data-num';
      tdVotes.textContent = String(c.votes || 0);

      const tdStatus = document.createElement('td');
      const statuses = [];
      if (c.status?.turbo) statuses.push('⚡Turbo');
      if (c.status?.shield) statuses.push('🛡️Escudo');
      if (c.status?.stumble) statuses.push('💥Tropeço');
      tdStatus.textContent = statuses.length > 0 ? statuses.join(' | ') : '-';

      tr.appendChild(tdPos);
      tr.appendChild(tdCand);
      tr.appendChild(tdDist);
      tr.appendChild(tdSpeed);
      tr.appendChild(tdVotes);
      tr.appendChild(tdStatus);

      dom.telemetryTableBody.appendChild(tr);
    });
  }

  // --- Outbound Message Dispatcher (WS with HTTP Fallback) ---
  async function sendAdminMessage(msg) {
    if (state.ws && state.wsConnected && state.ws.readyState === WebSocket.OPEN) {
      try {
        state.ws.send(JSON.stringify(msg));
        return true;
      } catch (err) {
        console.warn('Falha no envio WebSocket, tentando fallback HTTP:', err);
      }
    }

    // HTTP Fallback
    try {
      let endpoint = `${CONFIG.httpBase}/api/admin/command`;
      let bodyData = msg;

      if (msg.type === 'simulate_event') {
        endpoint = `${CONFIG.httpBase}/api/admin/simulate`;
        bodyData = {
          event_type: msg.event_type,
          ...msg.data
        };
      } else if (msg.type === 'admin_command') {
        bodyData = {
          command: msg.command,
          params: msg.params || {}
        };
      } else if (msg.type === 'candidate_action') {
        const cmd = msg.action === 'attack' ? 'attack' : `candidate_${msg.action}`;
        bodyData = {
          command: cmd,
          params: {
            candidate_slot: msg.candidate_slot,
            target_slot: msg.target_slot || (msg.candidate_slot === 1 ? 2 : 1)
          }
        };
      }

      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(bodyData)
      });
      if (res.ok) {
        return true;
      }
    } catch (fetchErr) {
      // Local dev server might not be running yet, simulate local optimistic update
      console.info('Modo Local Offline: comando aplicado localmente.', fetchErr.message);
    }
    return false;
  }

  // --- WebSocket Connection Management ---
  function connectWebSocket() {
    if (state.reconnectTimer) {
      clearTimeout(state.reconnectTimer);
      state.reconnectTimer = null;
    }

    const wsUrl = `ws://${CONFIG.wsHost}:${CONFIG.wsPort}${CONFIG.wsPath}`;
    appendLogEntry('command', 'WebSocket', `Conectando a ${wsUrl}...`);

    try {
      state.ws = new WebSocket(wsUrl);
    } catch (e) {
      handleWebSocketFailure();
      return;
    }

    state.ws.onopen = function () {
      state.wsConnected = true;
      state.reconnectAttempts = 0;
      stopHttpPolling();
      appendLogEntry('command', 'WebSocket', 'Conexão estabelecida com sucesso!');
      updateUI();
      // Solicita estado inicial
      sendAdminMessage({ type: 'get_state' });
    };

    state.ws.onmessage = function (event) {
      try {
        const data = JSON.parse(event.data);
        handleIncomingMessage(data);
      } catch (e) {
        console.error('Erro ao processar mensagem recebida:', e);
      }
    };

    state.ws.onclose = function () {
      state.wsConnected = false;
      handleWebSocketFailure();
    };

    state.ws.onerror = function () {
      state.wsConnected = false;
      handleWebSocketFailure();
    };
  }

  function handleWebSocketFailure() {
    state.wsConnected = false;
    updateUI();
    startHttpPolling();

    // Exponential Backoff
    state.reconnectAttempts++;
    const delay = Math.min(
      CONFIG.reconnectMaxMs,
      CONFIG.reconnectMinMs * Math.pow(1.5, state.reconnectAttempts)
    );

    if (!state.reconnectTimer) {
      state.reconnectTimer = setTimeout(() => {
        state.reconnectTimer = null;
        connectWebSocket();
      }, delay);
    }
  }

  // --- HTTP Polling Fallback ---
  function startHttpPolling() {
    if (state.httpPollingTimer) return;
    state.httpPollingTimer = setInterval(pollServerState, CONFIG.httpPollIntervalMs);
    pollServerState();
  }

  function stopHttpPolling() {
    if (state.httpPollingTimer) {
      clearInterval(state.httpPollingTimer);
      state.httpPollingTimer = null;
    }
  }

  async function pollServerState() {
    if (state.wsConnected) {
      stopHttpPolling();
      return;
    }
    try {
      const res = await fetch(`${CONFIG.httpBase}/api/state`, { cache: 'no-store' });
      if (res.ok) {
        const json = await res.json();
        applyStateData(json);
      }
    } catch (err) {
      // Server is offline, update UI state
      state.godotConnected = false;
      updateUI();
    }
  }

  // --- Inbound Message Handler ---
  function handleIncomingMessage(msg) {
    if (!msg || typeof msg !== 'object') return;

    if (msg.type === 'state_update') {
      applyStateData(msg.state || msg);
    } else if (msg.type === 'telemetry_event') {
      appendLogEntry(
        msg.event_type || 'command',
        msg.user?.display_name || 'Anon',
        msg.action || JSON.stringify(msg.payload || '')
      );
      if (msg.metrics) {
        Object.assign(state.metrics, msg.metrics);
        updateUI();
      }
    } else if (msg.type === 'command_ack') {
      appendLogEntry(
        msg.status === 'ok' ? 'command' : 'error',
        'Backend',
        msg.message || `Comando ${msg.command}: ${msg.status}`
      );
    } else if (msg.type === 'pong') {
      if (msg.metrics) {
        Object.assign(state.metrics, msg.metrics);
        updateUI();
      }
    }
  }

  function applyStateData(data) {
    if (!data) return;

    if (data.race_state) state.raceState = data.race_state;
    if (typeof data.phase_timer_seconds === 'number') state.phaseTimer = data.phase_timer_seconds;
    if (typeof data.race_timer_seconds === 'number') state.raceTimer = data.race_timer_seconds;
    if (typeof data.godot_connected === 'boolean') state.godotConnected = data.godot_connected;
    else if (typeof data.godot_client_count === 'number') state.godotConnected = data.godot_client_count > 0;
    if (typeof data.platform === 'string') state.platform = data.platform;
    state.telemetryFresh = data.telemetry_fresh === true;

    if (data.metrics) {
      Object.assign(state.metrics, data.metrics);
    }

    if (Array.isArray(data.candidates)) {
      data.candidates.forEach((cand) => {
        const found = state.candidates.find((c) => c.slot === cand.slot);
        if (found) {
          Object.assign(found, cand);
        }
      });
    }

    updateUI();
  }

  // --- User Interaction & Button Wiring ---
  function wireEvents() {
    // 1. Reconnect Button
    if (dom.btnReconnect) {
      dom.btnReconnect.addEventListener('click', () => {
        appendLogEntry('command', 'Admin', 'Reconexão manual acionada.');
        if (state.ws) {
          try { state.ws.close(); } catch (e) {}
        }
        connectWebSocket();
      });
    }

    // 2. Match Control Buttons
    if (dom.btnStartRace) {
      dom.btnStartRace.addEventListener('click', () => {
        flashButton(dom.btnStartRace);
        sendAdminMessage({ type: 'admin_command', command: 'start_race' });
        appendLogEntry('command', 'Admin', 'Comando enviado: Iniciar Corrida');
        // Optimistic update
        state.raceState = 'COUNTDOWN';
        state.phaseTimer = 5.0;
        updateUI();
      });
    }

    if (dom.btnSkipLobby) {
      dom.btnSkipLobby.addEventListener('click', () => {
        flashButton(dom.btnSkipLobby);
        sendAdminMessage({ type: 'admin_command', command: 'skip_lobby' });
        appendLogEntry('command', 'Admin', 'Comando enviado: Pular Lobby');
        state.raceState = 'COUNTDOWN';
        state.phaseTimer = 3.0;
        updateUI();
      });
    }

    if (dom.btnRestartRace) {
      dom.btnRestartRace.addEventListener('click', () => {
        if (dom.modalRestart) dom.modalRestart.classList.add('active');
      });
    }

    if (dom.btnCancelRestart) {
      dom.btnCancelRestart.addEventListener('click', () => {
        if (dom.modalRestart) dom.modalRestart.classList.remove('active');
      });
    }

    if (dom.btnConfirmRestart) {
      dom.btnConfirmRestart.addEventListener('click', () => {
        if (dom.modalRestart) dom.modalRestart.classList.remove('active');
        flashButton(dom.btnRestartRace);
        sendAdminMessage({ type: 'admin_command', command: 'restart_race' });
        appendLogEntry('command', 'Admin', '⚠️ Partida reiniciada pelo Operador.');
        // Reset local optimistic state
        state.raceState = 'LOBBY_VOTACAO';
        state.phaseTimer = 20.0;
        state.raceTimer = 0.0;
        state.candidates.forEach((c) => {
          c.distance_meters = 0;
          c.progress_pct = 0;
          c.speed_mps = 10.0;
          c.status = { turbo: false, shield: false, stumble: false };
        });
        updateUI();
      });
    }

    if (dom.btnResetDedup) {
      dom.btnResetDedup.addEventListener('click', () => {
        flashButton(dom.btnResetDedup);
        sendAdminMessage({ type: 'admin_command', command: 'reset_dedup' });
        appendLogEntry('command', 'Admin', '🧹 Cache LRU de deduplicação limpo.');
        state.metrics.duplicates_dropped = 0;
        updateUI();
      });
    }

    // 3. Quick Actions on Candidate Cards (Delegation)
    const grid = document.getElementById('candidates-grid');
    if (grid) {
      grid.addEventListener('click', (e) => {
        const btn = e.target.closest('button[data-action]');
        if (!btn) return;
        const slot = parseInt(btn.getAttribute('data-slot'), 10);
        const action = btn.getAttribute('data-action');
        if (!slot || !action) return;

        const targetCand = state.candidates.find((c) => c.slot === slot);
        const oppSlot = slot === 1 ? 2 : 1;
        const oppCand = state.candidates.find((c) => c.slot === oppSlot);

        flashButton(btn);
        sendAdminMessage({
          type: 'candidate_action',
          action: action,
          candidate_slot: slot,
          target_slot: oppSlot
        });

        if (targetCand) {
          if (action === 'turbo') {
            targetCand.status.turbo = true;
            targetCand.speed_mps = Math.min(22.0, targetCand.speed_mps + 5.0);
            appendLogEntry('command', 'Admin', `⚡ Turbo manual aplicado a #${slot} ${targetCand.name}`);
            setTimeout(() => {
              targetCand.status.turbo = false;
              targetCand.speed_mps = Math.max(10.0, targetCand.speed_mps - 5.0);
              updateUI();
            }, 3500);
          } else if (action === 'shield') {
            targetCand.status.shield = true;
            appendLogEntry('command', 'Admin', `🛡️ Escudo manual aplicado a #${slot} ${targetCand.name}`);
            setTimeout(() => {
              targetCand.status.shield = false;
              updateUI();
            }, 5000);
          } else if (action === 'attack') {
            appendLogEntry('gift', 'Admin', `📄 #${slot} ${targetCand.name} atacou #${oppSlot} ${oppCand ? oppCand.name : ''} com Pilha de Processos!`);
            if (oppCand) {
              if (oppCand.status?.shield) {
                appendLogEntry('command', 'Defesa', `🛡️ #${oppSlot} ${oppCand.name} usou Escudo e absorveu a papelada!`);
              } else {
                oppCand.status.stumble = true;
                oppCand.speed_mps = Math.max(4.0, oppCand.speed_mps - 6.0);
                setTimeout(() => {
                  oppCand.status.stumble = false;
                  oppCand.speed_mps = Math.min(18.0, oppCand.speed_mps + 6.0);
                  updateUI();
                }, 2000);
              }
            }
          }
          updateUI();
        }
      });
    }

    // 4. Live Simulator Actions
    if (dom.btnSimVote) {
      dom.btnSimVote.addEventListener('click', () => {
        flashButton(dom.btnSimVote);
        const slot = parseInt(dom.simVoteCand?.value || '1', 10);
        const qty = parseInt(dom.simVoteQty?.value || '1', 10);
        const cand = state.candidates.find((c) => c.slot === slot);
        const candName = cand ? cand.name : `Candidato ${slot}`;

        sendAdminMessage({
          type: 'simulate_event',
          event_type: 'vote',
          data: {
            candidate_slot: slot,
            count: qty,
            user_id: `sim_voter_${Date.now() % 10000}`,
            display_name: `Torcedor #${slot}`
          }
        });

        if (cand) {
          cand.votes = (cand.votes || 0) + qty;
          state.metrics.received_total += qty;
          state.metrics.accepted_total += qty;
          appendLogEntry('vote', `Torcedor #${slot}`, `+${qty} voto(s) para #${slot} ${candName}`);
          updateUI();
        }
      });
    }

    // Likes buttons
    [dom.btnLike10, dom.btnLike50, dom.btnLike200].forEach((btn) => {
      if (!btn) return;
      btn.addEventListener('click', () => {
        flashButton(btn);
        const likes = parseInt(btn.getAttribute('data-likes') || '10', 10);
        const slot = parseInt(dom.simLikeCand?.value || '1', 10);
        const cand = state.candidates.find((c) => c.slot === slot);
        const candName = cand ? cand.name : `Candidato ${slot}`;

        sendAdminMessage({
          type: 'simulate_event',
          event_type: 'like',
          data: {
            candidate_slot: slot,
            count: likes,
            user_id: `sim_liker_${Date.now() % 10000}`,
            display_name: 'Super Fã'
          }
        });

        state.metrics.received_total += likes;
        state.metrics.accepted_total += likes;
        appendLogEntry('like', 'Super Fã', `+${likes} likes para #${slot} ${candName}`);
        updateUI();
      });
    });

    // Share button
    if (dom.btnSimShare) {
      dom.btnSimShare.addEventListener('click', () => {
        flashButton(dom.btnSimShare);
        const slot = parseInt(dom.simShareCand?.value || '1', 10);
        const cand = state.candidates.find((c) => c.slot === slot);
        const candName = cand ? cand.name : `Candidato ${slot}`;

        sendAdminMessage({
          type: 'simulate_event',
          event_type: 'share',
          data: {
            candidate_slot: slot,
            user_id: `sim_sharer_${Date.now() % 10000}`,
            display_name: 'Divulgador'
          }
        });

        state.metrics.received_total += 1;
        state.metrics.accepted_total += 1;
        appendLogEntry('share', 'Divulgador', `Compartilhou a live para #${slot} ${candName}`);
        updateUI();
      });
    }

    // Gift buttons (T1..T4)
    const giftButtons = document.querySelectorAll('.gift-button');
    giftButtons.forEach((btn) => {
      btn.addEventListener('click', () => {
        flashButton(btn);
        const tier = btn.getAttribute('data-tier') || 'T1';
        const giftName = btn.getAttribute('data-name') || 'Presente';
        const slot = parseInt(dom.simGiftCand?.value || '1', 10);
        const cand = state.candidates.find((c) => c.slot === slot);
        const candName = cand ? cand.name : `Candidato ${slot}`;

        sendAdminMessage({
          type: 'simulate_event',
          event_type: 'gift',
          data: {
            candidate_slot: slot,
            gift_tier: tier,
            gift_name: giftName,
            repeat_count: 1,
            user_id: `sim_gifter_${Date.now() % 10000}`,
            display_name: `Doador VIP`
          }
        });

        state.metrics.received_total += 1;
        state.metrics.accepted_total += 1;
        appendLogEntry('gift', 'Doador VIP', `${giftName} (${tier}) para #${slot} ${candName}`);

        if (cand) {
          if (tier === 'T1') {
            cand.status.turbo = true;
            cand.speed_mps += 3.5;
            setTimeout(() => { cand.status.turbo = false; cand.speed_mps = Math.max(10, cand.speed_mps - 3.5); updateUI(); }, 3500);
          } else if (tier === 'T2') {
            cand.status.shield = true;
            cand.speed_mps += 5.0;
            setTimeout(() => { cand.status.shield = false; cand.speed_mps = Math.max(10, cand.speed_mps - 5.0); updateUI(); }, 5000);
          } else if (tier === 'T3') {
            // Ataque no adversário direto com Pilha de Processos
            const oppSlot = slot === 1 ? 2 : 1;
            const oppCand = state.candidates.find((c) => c.slot === oppSlot);
            if (oppCand) {
              if (oppCand.status?.shield) {
                appendLogEntry('command', 'Defesa', `🛡️ #${oppSlot} ${oppCand.name} usou Escudo e bloqueou o ataque T3!`);
              } else {
                oppCand.status.stumble = true;
                oppCand.speed_mps = Math.max(4.0, oppCand.speed_mps - 6.0);
                appendLogEntry('gift', 'Ataque T3', `💥 #${oppSlot} ${oppCand.name} tropeçou na Pilha de Documentos!`);
                setTimeout(() => {
                  oppCand.status.stumble = false;
                  oppCand.speed_mps = Math.min(18.0, oppCand.speed_mps + 6.0);
                  updateUI();
                }, 2000);
              }
            }
          } else if (tier === 'T4') {
            cand.status.turbo = true;
            cand.status.shield = true;
            cand.speed_mps += 8.0;
            setTimeout(() => { cand.status.turbo = false; cand.status.shield = false; cand.speed_mps = Math.max(12.0, cand.speed_mps - 8.0); updateUI(); }, 8000);
          }
          updateUI();
        }
      });
    });

    // Burst Stress Test Button
    if (dom.btnBurst) {
      dom.btnBurst.addEventListener('click', () => {
        flashButton(dom.btnBurst);
        appendLogEntry('command', 'Admin', '💥 Rajada de Estresse iniciada (40 eventos)...');
        sendAdminMessage({
          type: 'simulate_event',
          event_type: 'burst',
          data: { count: 40 }
        });

        // Simulate local rapid burst
        for (let i = 0; i < 40; i++) {
          setTimeout(() => {
            const randSlot = Math.floor(Math.random() * 2) + 1;
            const randCand = state.candidates.find((c) => c.slot === randSlot);
            if (randCand) {
              randCand.votes += 1;
              state.metrics.received_total += 1;
              state.metrics.accepted_total += 1;
            }
            if (i % 8 === 0) {
              appendLogEntry('vote', `Bot_${i}`, `+1 voto rajada (#${randSlot})`);
            }
            updateUI();
          }, i * 35);
        }
      });
    }

    // Clear Feed Button
    if (dom.btnClearLog) {
      dom.btnClearLog.addEventListener('click', () => {
        if (dom.terminalLogBody) {
          dom.terminalLogBody.replaceChildren();
          appendLogEntry('command', 'Admin', 'Feed de eventos limpo.');
        }
      });
    }
  }

  // Visual button click feedback (prevents accidental spam)
  function flashButton(btn) {
    if (!btn) return;
    btn.disabled = true;
    setTimeout(() => {
      btn.disabled = false;
    }, 250);
  }

  // --- Local Tick Simulator (Smooth animation for offline or fallback demonstration) ---
  function startLocalSimulationLoop() {
    setInterval(() => {
      if (state.raceState === 'RACING') {
        state.raceTimer += 0.5;
        state.phaseTimer = Math.max(0, state.phaseTimer - 0.5);

        // Advance runners continuously in infinite track
        state.candidates.forEach((c) => {
          const delta = (c.speed_mps || 12.0) * 0.5;
          c.distance_meters = (c.distance_meters || 0) + delta;
        });

        // Recalculate positions based on distance
        const sorted = [...state.candidates].sort((a, b) => b.distance_meters - a.distance_meters);
        sorted.forEach((c, idx) => {
          c.position = idx + 1;
        });

        // Check match finish by timer (5 minutes / 300s)
        if (state.phaseTimer <= 0) {
          const winner = sorted[0];
          state.raceState = 'PODIO';
          state.phaseTimer = 15.0;
          appendLogEntry('command', 'RaceControl', `🏁 Fim do tempo de partida! Vencedor: #${winner.slot} ${winner.name} (${winner.distance_meters.toFixed(1)}m)!`);
        }
        updateUI();
      } else if (state.raceState === 'COUNTDOWN') {
        state.phaseTimer = Math.max(0, state.phaseTimer - 0.5);
        if (state.phaseTimer <= 0) {
          state.raceState = 'RACING';
          state.phaseTimer = 300.0; // 5 minutos de corrida infinita
          appendLogEntry('command', 'RaceControl', '🟢 Largada autorizada! Corrida infinita de 5 minutos iniciada!');
        }
        updateUI();
      } else if (state.raceState === 'PHOTO_FINISH') {
        state.phaseTimer = Math.max(0, state.phaseTimer - 0.5);
        if (state.phaseTimer <= 0) {
          state.raceState = 'PODIO';
          state.phaseTimer = 15.0;
          appendLogEntry('command', 'RaceControl', '🏆 Pódio e celebração dos vencedores!');
        }
        updateUI();
      } else if (state.raceState === 'PODIO') {
        state.phaseTimer = Math.max(0, state.phaseTimer - 0.5);
        if (state.phaseTimer <= 0) {
          state.raceState = 'LOBBY_VOTACAO';
          state.phaseTimer = 20.0;
          state.candidates.forEach((c) => {
            c.distance_meters = 0;
            c.speed_mps = 12.0;
            c.status = { turbo: false, shield: false, stumble: false };
          });
          appendLogEntry('command', 'RaceControl', '🔄 Novo ciclo: Lobby de Votação aberto!');
        }
        updateUI();
      } else if (state.raceState === 'LOBBY_VOTACAO') {
        state.phaseTimer = Math.max(0, state.phaseTimer - 0.5);
        if (state.phaseTimer <= 0) {
          state.raceState = 'COUNTDOWN';
          state.phaseTimer = 5.0;
          appendLogEntry('command', 'RaceControl', '🚦 3.. 2.. 1.. Contagem Regressiva iniciada!');
        }
        updateUI();
      }
    }, 500);
  }

  // --- App Initialization ---
  function init() {
    updateUI();
    wireEvents();
    connectWebSocket();
    startLocalSimulationLoop();
  }

  // Run on DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
