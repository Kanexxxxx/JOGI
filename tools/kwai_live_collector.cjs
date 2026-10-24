#!/usr/bin/env node
/* Local Zero-CORS Playwright collector for Kwai LIVE -> KwaiLiveAdapter loopback webhook (127.0.0.1:8786).
 * Never starts a broadcast, never uses cloud credentials, and never navigates outside kwai.com (except explicit local test fixture).
 */
'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

function parseArgs(argv) {
  const out = {
    account: 'mentalista..',
    bridge: 'http://127.0.0.1:8766',
    webhook: 'http://127.0.0.1:8786/webhook/kwai',
    liveUrl: '',
    profileDir: path.join(
      process.env.LOCALAPPDATA || path.join(os.homedir(), '.local'),
      'JOGI',
      'live_bridge',
      'kwai',
      'browser_profile'
    ),
    headed: false,
    once: false,
    allowLocalTestUrl: false,
    heartbeatMs: 6000,
    refreshMs: 25000,
  };
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--headed') out.headed = true;
    else if (arg === '--once') out.once = true;
    else if (arg === '--allow-local-test-url') out.allowLocalTestUrl = true;
    else if (arg === '--account' && argv[i + 1]) out.account = String(argv[++i]).replace(/^@+/, '').slice(0, 64);
    else if (arg === '--bridge' && argv[i + 1]) out.bridge = String(argv[++i]);
    else if (arg === '--webhook' && argv[i + 1]) out.webhook = String(argv[++i]);
    else if (arg === '--live-url' && argv[i + 1]) out.liveUrl = String(argv[++i]);
    else if (arg === '--profile-dir' && argv[i + 1]) out.profileDir = String(argv[++i]);
    else if (arg === '--heartbeat-ms' && argv[i + 1]) out.heartbeatMs = Math.max(500, Number(argv[++i]) || 6000);
  }
  return out;
}

function assertLoopbackHttpUrl(rawUrl, label) {
  const parsed = new URL(rawUrl);
  if (
    parsed.protocol !== 'http:' ||
    (parsed.hostname !== '127.0.0.1' && parsed.hostname !== 'localhost') ||
    parsed.username ||
    parsed.password
  ) {
    throw new Error(`${label} deve apontar exclusivamente para loopback HTTP (127.0.0.1).`);
  }
  return parsed.toString().replace(/\/+$/, '');
}

function isAllowedNavigationUrl(rawUrl, allowLocalTestUrl = false) {
  try {
    const parsed = new URL(String(rawUrl || '').trim());
    if (parsed.username || parsed.password || parsed.hash) return false;
    const host = parsed.hostname.toLowerCase();
    if (allowLocalTestUrl && parsed.protocol === 'http:' && (host === '127.0.0.1' || host === 'localhost')) {
      return true;
    }
    if (parsed.protocol !== 'https:') return false;
    if (parsed.port && parsed.port !== '443') return false;
    return host === 'kwai.com' || host.endsWith('.kwai.com');
  } catch (_) {
    return false;
  }
}

function loadPlaywright() {
  const candidates = [
    'playwright',
    path.join(
      process.env.APPDATA || '',
      'npm',
      'node_modules',
      '@playwright',
      'cli',
      'node_modules',
      'playwright'
    ),
    path.join(
      os.homedir(),
      '.cache',
      'codex-runtimes',
      'codex-primary-runtime',
      'dependencies',
      'node',
      'node_modules',
      'playwright'
    ),
  ];
  for (const mod of candidates) {
    try {
      return require(mod);
    } catch (_) {}
  }
  throw new Error('Playwright nao encontrado para o coletor local do Kwai.');
}

function findChromiumExecutable() {
  const base = path.join(process.env.LOCALAPPDATA || '', 'ms-playwright');
  try {
    for (const entry of fs.readdirSync(base).sort().reverse()) {
      if (!entry.startsWith('chromium-')) continue;
      for (const sub of ['chrome-win64', 'chrome-win']) {
        const exe = path.join(base, entry, sub, 'chrome.exe');
        if (fs.existsSync(exe)) return exe;
      }
    }
  } catch (_) {}
  return undefined;
}

class BoundedSet {
  constructor(limit = 10000) {
    this.limit = limit;
    this.set = new Set();
  }
  has(key) {
    return this.set.has(key);
  }
  add(key) {
    if (this.set.has(key)) return;
    if (this.set.size >= this.limit) {
      const oldest = this.set.values().next().value;
      if (oldest !== undefined) this.set.delete(oldest);
    }
    this.set.add(key);
  }
}

function makeEventId(prefix, parts) {
  const digest = crypto.createHash('sha256').update(parts.join('|')).digest('hex').slice(0, 28);
  return `kwai_${prefix}_${digest}`;
}

function isLiveApiUrl(rawUrl) {
  return /\/live\/|liveStream|webcast|live\/feed/i.test(String(rawUrl || ''));
}

function normalizeFeedPayload(body, options = {}) {
  const out = [];
  let liveHint = false;
  if (!body || typeof body !== 'object') return { events: out, liveHint };

  const root = body.data && typeof body.data === 'object' ? body.data : body;
  if (root.isLiving === false || root.live_active === false) {
    return { events: out, liveHint: false };
  }

  const explicitLive = Boolean(root.isLiving === true || root.liveStreamId || root.live_active === true);
  if (explicitLive) {
    liveHint = true;
  }

  const pushEvent = (raw, fallbackType) => {
    if (!raw || typeof raw !== 'object') return;
    const type = String(raw.type || raw.event_type || fallbackType || '').toLowerCase();
    if (!type) return;
    const userObj = raw.user && typeof raw.user === 'object' ? raw.user : {};
    const userId = String(raw.user_id || userObj.user_id || userObj.id || userObj.principalId || 'anon_kwai').slice(0, 64);
    const displayName = String(
      raw.display_name || raw.username || userObj.userName || userObj.user_name || userObj.name || 'Espectador Kwai'
    ).slice(0, 64);
    const rawAvatar = raw.avatar_url || raw.headUrl || userObj.headUrl || userObj.avatar || userObj.avatar_url;
    const avatarUrl = typeof rawAvatar === 'string' && rawAvatar.startsWith('https://') ? rawAvatar.slice(0, 1024) : undefined;
    const rawId = raw.event_id || raw.id || raw.feedId || raw.comboKey || '';

    if (type === 'comment' || type === 'chat' || type === 'vote') {
      const comment = String(raw.comment || raw.content || raw.text || '').trim();
      if (!comment) return;
      out.push({
        type: 'comment',
        event_id: rawId ? String(rawId).slice(0, 120) : makeEventId('cmt', [userId, comment, String(raw.timestamp_ms || raw.time || '')]),
        user_id: userId,
        display_name: displayName,
        comment,
        ...(avatarUrl ? { avatar_url: avatarUrl } : {}),
      });
    } else if (type === 'gift' || type === 'present') {
      const giftId = String(raw.gift_id ?? raw.giftId ?? 'kwai_gift').slice(0, 64);
      const giftName = String(raw.gift_name || raw.giftName || 'Presente Kwai').slice(0, 64);
      const coinValue = Math.max(0, Math.trunc(Number(raw.coin_value ?? raw.unit_coin_value ?? raw.coins ?? raw.price ?? 0) || 0));
      const repeatCount = Math.max(1, Math.min(1000, Math.trunc(Number(raw.repeat_count ?? raw.batchSize ?? raw.count ?? 1) || 1)));
      const giftImage = raw.gift_image_url || raw.giftUrl || raw.picUrl || undefined;
      out.push({
        type: 'gift',
        event_id: rawId
          ? String(rawId).slice(0, 120)
          : makeEventId('gift', [userId, giftId, String(repeatCount), String(raw.comboCount || raw.timestamp_ms || '')]),
        user_id: userId,
        display_name: displayName,
        gift_id: giftId,
        gift_name: giftName,
        coin_value: coinValue,
        repeat_count: repeatCount,
        gift_image_url: typeof giftImage === 'string' ? giftImage : undefined,
        ...(avatarUrl ? { avatar_url: avatarUrl } : {}),
      });
    } else if (type === 'like' || type === 'like_batch' || type === 'heart') {
      const likeCount = Math.max(1, Math.min(50000, Math.trunc(Number(raw.like_count ?? raw.count ?? 1) || 1)));
      out.push({
        type: 'like',
        event_id: rawId ? String(rawId).slice(0, 120) : makeEventId('like', [userId, String(likeCount), String(raw.timestamp_ms || '')]),
        user_id: userId,
        display_name: displayName,
        like_count: likeCount,
        ...(avatarUrl ? { avatar_url: avatarUrl } : {}),
      });
    } else if (type === 'share' || type === 'forward') {
      out.push({
        type: 'share',
        event_id: rawId ? String(rawId).slice(0, 120) : makeEventId('share', [userId, String(raw.timestamp_ms || '')]),
        user_id: userId,
        display_name: displayName,
        ...(avatarUrl ? { avatar_url: avatarUrl } : {}),
      });
    } else if (type === 'follow' || type === 'new_follower') {
      out.push({
        type: 'follow',
        event_id: rawId ? String(rawId).slice(0, 120) : makeEventId('follow', [userId, String(raw.timestamp_ms || '')]),
        user_id: userId,
        display_name: displayName,
        ...(avatarUrl ? { avatar_url: avatarUrl } : {}),
      });
    }
  };

  // Specific live webcast feed arrays (never present on recorded VOD APIs)
  const liveSpecificMappings = [
    ['commentFeeds', 'comment'],
    ['giftFeeds', 'gift'],
    ['likeFeeds', 'like'],
    ['shareFeeds', 'share'],
    ['followFeeds', 'follow'],
  ];
  for (const [field, kind] of liveSpecificMappings) {
    if (Array.isArray(root[field]) && root[field].length > 0) {
      liveHint = true;
      for (const item of root[field]) pushEvent(item, kind);
    }
  }

  // Generic keys (`events`, `comments`, `gifts`) are accepted ONLY when backed by explicit live room metadata or a trusted live source
  const allowGenericKeys = explicitLive || Boolean(options.trustedLiveSource);
  if (allowGenericKeys) {
    if (Array.isArray(root.events)) {
      if (root.events.length > 0 && Boolean(options.allowHintFromGeneric)) liveHint = true;
      for (const item of root.events) pushEvent(item, item?.type);
    }
    for (const [field, kind] of [
      ['comments', 'comment'],
      ['gifts', 'gift'],
    ]) {
      if (Array.isArray(root[field])) {
        if (root[field].length > 0 && Boolean(options.allowHintFromGeneric)) liveHint = true;
        for (const item of root[field]) pushEvent(item, kind);
      }
    }
  }

  return { events: out, liveHint };
}

function localAuthHeaders(extra = {}) {
  const raw = String(process.env.LIVE_BRIDGE_PRODUCER_TOKEN || process.env.LIVE_BRIDGE_LOCAL_TOKEN || '').trim();
  const headers = { ...extra };
  if (raw && raw !== 'change_me_local_random_token') {
    headers['X-JOGI-Token'] = raw;
  }
  return headers;
}

async function postWebhook(webhookUrl, payload) {
  const res = await fetch(webhookUrl, {
    method: 'POST',
    headers: localAuthHeaders({ 'Content-Type': 'application/json' }),
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(4000),
  });
  return res.ok;
}

async function fetchTargetUrlFromBridge(bridgeBase, fallbackUrl, allowLocalTestUrl) {
  try {
    const res = await fetch(`${bridgeBase}/api/kwai-collector`, {
      method: 'GET',
      headers: localAuthHeaders(),
      signal: AbortSignal.timeout(2500),
    });
    if (!res.ok) return fallbackUrl;
    const data = await res.json();
    const candidate = data?.kwai_collector?.target_url || '';
    if (candidate && isAllowedNavigationUrl(candidate, allowLocalTestUrl)) {
      return candidate;
    }
  } catch (_) {}
  return fallbackUrl;
}

function isPidAlive(pid) {
  const num = Number(pid);
  if (!Number.isInteger(num) || num <= 0) return false;
  try {
    process.kill(num, 0);
    return true;
  } catch (err) {
    return Boolean(err && err.code === 'EPERM');
  }
}

function isHeadedLoginActive(lockPath) {
  try {
    if (!fs.existsSync(lockPath)) return false;
    const raw = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
    if (raw && isPidAlive(raw.pid)) return true;
    fs.unlinkSync(lockPath);
  } catch (_) {}
  return false;
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function main() {
  const args = parseArgs(process.argv);
  const bridgeBase = assertLoopbackHttpUrl(args.bridge, '--bridge');
  const webhookUrl = assertLoopbackHttpUrl(args.webhook, '--webhook');
  const defaultUrl = args.liveUrl || `https://www.kwai.com/@${args.account}`;

  if (!isAllowedNavigationUrl(defaultUrl, args.allowLocalTestUrl)) {
    throw new Error(`URL inicial nao permitida para o coletor Kwai: ${defaultUrl}`);
  }

  const { chromium } = loadPlaywright();
  const executablePath = findChromiumExecutable();
  fs.mkdirSync(args.profileDir, { recursive: true });
  const headedLockPath = path.join(path.dirname(args.profileDir), 'headed_login.lock');

  const seenIds = new BoundedSet(10000);
  let eventsForwarded = 0;
  let lastFeedLiveAt = 0;
  let stopping = false;
  let context = null;
  let page = null;
  let activeTargetUrl = '';
  let lastGotoAt = 0;

  const forwardEvent = async rawEvent => {
    if (!rawEvent || typeof rawEvent !== 'object') return;
    const id = String(rawEvent.event_id || '');
    if (!id || seenIds.has(id)) return;
    seenIds.add(id);
    try {
      const ok = await postWebhook(webhookUrl, rawEvent);
      if (ok) eventsForwarded += 1;
    } catch (_) {}
  };

  const cleanupLock = () => {
    if (!args.headed) return;
    try {
      if (fs.existsSync(headedLockPath)) {
        const raw = JSON.parse(fs.readFileSync(headedLockPath, 'utf8'));
        if (!raw || Number(raw.pid) === process.pid) fs.unlinkSync(headedLockPath);
      }
    } catch (_) {}
  };

  process.on('SIGINT', () => { stopping = true; });
  process.on('SIGTERM', () => { stopping = true; });
  process.on('exit', cleanupLock);

  if (args.headed) {
    fs.writeFileSync(headedLockPath, JSON.stringify({ pid: process.pid, started_at: Date.now() }), 'utf8');
  }

  const closeContext = async () => {
    if (context) {
      await context.close().catch(() => {});
      context = null;
      page = null;
      lastGotoAt = 0;
    }
  };

  const ensureBrowserOpen = async () => {
    if (context && page) return true;
    const maxAttempts = args.headed ? 8 : 2;
    for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        context = await chromium.launchPersistentContext(args.profileDir, {
          headless: !args.headed,
          executablePath,
          viewport: { width: 1280, height: 800 },
          args: ['--disable-blink-features=AutomationControlled', '--mute-audio'],
        });
        break;
      } catch (err) {
        if (attempt === maxAttempts) {
          if (args.headed) {
            throw new Error(
              `Perfil do navegador Kwai ocupado. Aguarde 3s ou feche ABRIR_KWAI.cmd / ABRIR_DUAS_LIVES.cmd antes do login: ${err.message || err}`
            );
          }
          return false;
        }
        await sleep(800);
      }
    }

    await context.route('**/*', async route => {
      const req = route.request();
      if (req.isNavigationRequest() && req.frame() === req.frame().page()?.mainFrame()) {
        if (!isAllowedNavigationUrl(req.url(), args.allowLocalTestUrl)) {
          await route.abort('blockedbyclient');
          return;
        }
      }
      await route.continue();
    });

    await context.exposeBinding('__jogiKwaiEmit', async (_source, item) => {
      if (!item || typeof item !== 'object') return;
      const isExplicit = item.__jogiExplicit === true;
      const { events } = normalizeFeedPayload(
        { events: [item] },
        { trustedLiveSource: true, allowHintFromGeneric: false }
      );
      if (isExplicit) {
        lastFeedLiveAt = Date.now();
      }
      for (const ev of events) {
        await forwardEvent(ev);
      }
    });

    await context.addInitScript(() => {
      const seenDom = new Set();
      function rememberDom(key) {
        if (seenDom.has(key)) return false;
        if (seenDom.size >= 5000) seenDom.clear();
        seenDom.add(key);
        return true;
      }
      function isLiveDomRoom() {
        if (document.querySelector('[data-jogi-live-active="true"]') !== null) return true;
        if (!/\/live\/|liveStream/i.test(window.location.href)) return false;
        const videos = Array.from(document.querySelectorAll('video'));
        return videos.some(v => v.readyState >= 2 && !v.ended && v.videoWidth > 0);
      }
      function scanNode(root) {
        if (!root || !root.querySelectorAll) return;
        const explicitNodes = root.querySelectorAll('[data-jogi-kwai-event]');
        for (const el of explicitNodes) {
          const rawJson = el.getAttribute('data-jogi-kwai-event');
          if (!rawJson || !rememberDom(rawJson)) continue;
          try {
            const parsed = JSON.parse(rawJson);
            if (parsed && typeof parsed === 'object' && typeof window.__jogiKwaiEmit === 'function') {
              window.__jogiKwaiEmit({ ...parsed, __jogiExplicit: true });
            }
          } catch (_) {}
        }
        if (!isLiveDomRoom()) return;
        const chatNodes = root.querySelectorAll('[class*="chat-item"], [class*="barrage-item"]');
        let idx = 0;
        for (const el of chatNodes) {
          idx += 1;
          const text = (el.textContent || '').replace(/\s+/g, ' ').trim();
          if (!text || text.length > 240) continue;
          const key = `${el.dataset?.id || ''}|${text}`;
          if (!rememberDom(key)) continue;
          const userEl = el.querySelector('[class*="name"], [class*="user"], [class*="author"]');
          const contentEl = el.querySelector('[class*="content"], [class*="text"], [class*="msg"]');
          const displayName = (userEl ? userEl.textContent : 'Espectador Kwai').replace(/[:：]\s*$/, '').trim();
          const comment = (contentEl ? contentEl.textContent : text).trim();
          if (typeof window.__jogiKwaiEmit === 'function') {
            window.__jogiKwaiEmit({
              type: 'comment',
              id: el.dataset?.id || undefined,
              user_id: displayName.toLowerCase().replace(/[^a-z0-9_.-]+/g, '_').slice(0, 48) || `dom_${idx}`,
              display_name: displayName || 'Espectador Kwai',
              comment,
            });
          }
        }
      }
      const startObserver = () => {
        scanNode(document);
        const obs = new MutationObserver(mutations => {
          for (const m of mutations) {
            for (const added of m.addedNodes) {
              if (added && added.nodeType === 1) scanNode(added);
            }
          }
          scanNode(document);
        });
        if (document.documentElement) {
          obs.observe(document.documentElement, { childList: true, subtree: true });
        }
      };
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', startObserver, { once: true });
      } else {
        startObserver();
      }
    });

    page = context.pages()[0] || (await context.newPage());

    page.on('response', async response => {
      try {
        const ct = (response.headers()['content-type'] || '').toLowerCase();
        if (!ct.includes('json')) return;
        const body = await response.json();
        const trustedLiveApi = isLiveApiUrl(response.url());
        const { events, liveHint } = normalizeFeedPayload(body, {
          trustedLiveSource: trustedLiveApi,
          allowHintFromGeneric: trustedLiveApi,
        });
        if (liveHint) lastFeedLiveAt = Date.now();
        for (const ev of events) {
          await forwardEvent(ev);
        }
      } catch (_) {}
    });

    page.on('websocket', ws => {
      ws.on('framereceived', async frame => {
        try {
          if (typeof frame.payload !== 'string' || !frame.payload.startsWith('{')) return;
          const body = JSON.parse(frame.payload);
          const trustedWs = isLiveApiUrl(ws.url());
          const { events, liveHint } = normalizeFeedPayload(body, {
            trustedLiveSource: trustedWs,
            allowHintFromGeneric: trustedWs,
          });
          if (liveHint) lastFeedLiveAt = Date.now();
          for (const ev of events) {
            await forwardEvent(ev);
          }
        } catch (_) {}
      });
    });

    return true;
  };

  const inspectPageStatus = async () => {
    if (!page) {
      return {
        status: 'waiting_room',
        detail: 'Aguardando disponibilidade do perfil do navegador Kwai',
        liveUrl: activeTargetUrl || defaultUrl,
      };
    }
    try {
      const probe = await page.evaluate(() => {
        const explicitActive = document.querySelector('[data-jogi-live-active="true"]') !== null;
        const loginWall =
          document.querySelector('[class*="login-modal"], [class*="captcha"], [id*="captcha"]') !== null;
        const videos = Array.from(document.querySelectorAll('video'));
        const activeVideo = videos.some(v => v.readyState >= 2 && !v.ended && v.videoWidth > 0);
        const isLiveRoute = /\/live\/|liveStream/i.test(window.location.href);
        return {
          explicitActive,
          loginWall,
          activeVideo,
          isLiveRoute,
          href: window.location.href,
        };
      });
      const feedRecent = Date.now() - lastFeedLiveAt < 30000;
      if (probe.explicitActive || feedRecent || (probe.isLiveRoute && probe.activeVideo)) {
        return {
          status: 'connected',
          detail: `Sala Kwai LIVE ativa (${eventsForwarded} eventos encaminhados)`,
          liveUrl: probe.href || activeTargetUrl,
        };
      }
      if (probe.loginWall) {
        return {
          status: 'login_required',
          detail: 'Kwai solicitou login/verificação; use ABRIR_NAVEGADOR_KWAI.cmd uma vez.',
          liveUrl: probe.href || activeTargetUrl,
        };
      }
      return {
        status: 'waiting_room',
        detail: `Aguardando LIVE ativa em ${activeTargetUrl}`,
        liveUrl: probe.href || activeTargetUrl,
      };
    } catch (err) {
      return {
        status: 'waiting_room',
        detail: `Verificando página Kwai (${String(err.message || err).slice(0, 72)})`,
        liveUrl: activeTargetUrl,
      };
    }
  };

  try {
    activeTargetUrl = args.liveUrl
      ? defaultUrl
      : await fetchTargetUrlFromBridge(bridgeBase, defaultUrl, args.allowLocalTestUrl);

    while (!stopping) {
      if (!args.headed && isHeadedLoginActive(headedLockPath)) {
        await closeContext();
        await postWebhook(webhookUrl, {
          type: 'collector_status',
          status: 'waiting_room',
          detail: 'Navegador visível Kwai aberto para login; feche-o ao concluir para retomar a coleta automática.',
          live_url: activeTargetUrl || defaultUrl,
          events_forwarded: eventsForwarded,
        }).catch(() => {});
        if (args.once) break;
        await sleep(1200);
        continue;
      }

      const browserReady = await ensureBrowserOpen();
      if (!browserReady) {
        await postWebhook(webhookUrl, {
          type: 'collector_status',
          status: 'waiting_room',
          detail: 'Perfil do navegador Kwai temporariamente ocupado; tentando novamente...',
          live_url: activeTargetUrl || defaultUrl,
          events_forwarded: eventsForwarded,
        }).catch(() => {});
        if (args.once) break;
        await sleep(args.heartbeatMs);
        continue;
      }

      const desiredUrl = args.liveUrl
        ? defaultUrl
        : await fetchTargetUrlFromBridge(bridgeBase, defaultUrl, args.allowLocalTestUrl);

      const needReload =
        desiredUrl !== activeTargetUrl ||
        lastGotoAt === 0 ||
        (Date.now() - lastGotoAt >= args.refreshMs && Date.now() - lastFeedLiveAt >= 20000);

      if (needReload && isAllowedNavigationUrl(desiredUrl, args.allowLocalTestUrl)) {
        activeTargetUrl = desiredUrl;
        lastGotoAt = Date.now();
        try {
          await page.goto(activeTargetUrl, { waitUntil: 'domcontentloaded', timeout: 15000 });
        } catch (_) {
          await postWebhook(webhookUrl, {
            type: 'collector_status',
            status: 'waiting_room',
            detail: `Aguardando conexão com ${activeTargetUrl}`,
            live_url: activeTargetUrl,
            events_forwarded: eventsForwarded,
          }).catch(() => {});
        }
      }

      if (args.once) {
        await sleep(350);
      }

      const state = await inspectPageStatus();
      await postWebhook(webhookUrl, {
        type: 'collector_status',
        status: state.status,
        detail: state.detail,
        live_url: state.liveUrl,
        events_forwarded: eventsForwarded,
      }).catch(() => {});

      if (args.once) break;
      await sleep(args.heartbeatMs);
    }
  } finally {
    await closeContext();
    cleanupLock();
  }
}

main().catch(err => {
  console.error('[kwai_live_collector]', err && err.message ? err.message : err);
  process.exit(1);
});
