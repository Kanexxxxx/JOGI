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
      process.env.USERPROFILE || os.homedir(),
      '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright'
    ),
  ];
  for (const mod of candidates) {
    try {
      return require(mod);
    } catch (_) {}
  }
  throw new Error('Playwright nao encontrado no ambiente local Node.');
}

function findChromiumExecutable() {
  const installed = path.join(process.env.LOCALAPPDATA || '', 'ms-playwright');
  if (!installed || !fs.existsSync(installed)) return undefined;
  const dirs = fs
    .readdirSync(installed)
    .filter(name => /^chromium-\d+$/.test(name))
    .sort((a, b) => Number(b.split('-')[1]) - Number(a.split('-')[1]));
  for (const dir of dirs) {
    const exe = path.join(installed, dir, 'chrome-win64', 'chrome.exe');
    if (fs.existsSync(exe)) return exe;
  }
  return undefined;
}

class BoundedSet {
  constructor(limit = 10000) {
    this.limit = limit;
    this.map = new Map();
  }
  has(key) {
    return this.map.has(key);
  }
  add(key) {
    if (this.map.has(key)) this.map.delete(key);
    this.map.set(key, true);
    while (this.map.size > this.limit) {
      const oldest = this.map.keys().next().value;
      this.map.delete(oldest);
    }
  }
}

function makeEventId(prefix, parts) {
  const digest = crypto.createHash('sha256').update(parts.join('|')).digest('hex').slice(0, 28);
  return `kwai_${prefix}_${digest}`;
}

function normalizeFeedPayload(body) {
  const out = [];
  let liveHint = false;
  if (!body || typeof body !== 'object') return { events: out, liveHint };

  const root = body.data && typeof body.data === 'object' ? body.data : body;
  if (root.isLiving === true || root.liveStreamId || root.live_active === true) {
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
      });
    } else if (type === 'like' || type === 'like_batch' || type === 'heart') {
      const likeCount = Math.max(1, Math.min(50000, Math.trunc(Number(raw.like_count ?? raw.count ?? 1) || 1)));
      out.push({
        type: 'like',
        event_id: rawId ? String(rawId).slice(0, 120) : makeEventId('like', [userId, String(likeCount), String(raw.timestamp_ms || '')]),
        user_id: userId,
        display_name: displayName,
        like_count: likeCount,
      });
    } else if (type === 'share' || type === 'forward') {
      out.push({
        type: 'share',
        event_id: rawId ? String(rawId).slice(0, 120) : makeEventId('share', [userId, String(raw.timestamp_ms || '')]),
        user_id: userId,
        display_name: displayName,
      });
    } else if (type === 'follow' || type === 'new_follower') {
      out.push({
        type: 'follow',
        event_id: rawId ? String(rawId).slice(0, 120) : makeEventId('follow', [userId, String(raw.timestamp_ms || '')]),
        user_id: userId,
        display_name: displayName,
      });
    }
  };

  if (Array.isArray(root.events)) {
    liveHint = true;
    for (const item of root.events) pushEvent(item, item?.type);
  }
  const feedMappings = [
    ['commentFeeds', 'comment'],
    ['comments', 'comment'],
    ['giftFeeds', 'gift'],
    ['gifts', 'gift'],
    ['likeFeeds', 'like'],
    ['shareFeeds', 'share'],
    ['followFeeds', 'follow'],
  ];
  for (const [field, kind] of feedMappings) {
    if (Array.isArray(root[field])) {
      liveHint = true;
      for (const item of root[field]) pushEvent(item, kind);
    }
  }
  return { events: out, liveHint };
}

async function postWebhook(webhookUrl, payload) {
  const res = await fetch(webhookUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(4000),
  });
  return res.ok;
}

async function fetchTargetUrlFromBridge(bridgeBase, fallbackUrl, allowLocalTestUrl) {
  try {
    const res = await fetch(`${bridgeBase}/api/kwai-collector`, {
      method: 'GET',
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

  const seenIds = new BoundedSet(10000);
  let eventsForwarded = 0;
  let lastFeedLiveAt = 0;
  let stopping = false;
  let context = null;

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

  process.on('SIGINT', () => { stopping = true; });
  process.on('SIGTERM', () => { stopping = true; });

  try {
    context = await chromium.launchPersistentContext(args.profileDir, {
      headless: !args.headed,
      executablePath,
      viewport: { width: 1280, height: 800 },
      args: ['--disable-blink-features=AutomationControlled', '--mute-audio'],
    });

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
      const { events, liveHint } = normalizeFeedPayload({ events: [item] });
      if (liveHint) lastFeedLiveAt = Date.now();
      for (const ev of events) {
        await forwardEvent(ev);
      }
    });

    await context.addInitScript(() => {
      const seenDom = new Set();
      function scanNode(root) {
        if (!root || !root.querySelectorAll) return;
        const explicitNodes = root.querySelectorAll('[data-jogi-kwai-event]');
        for (const el of explicitNodes) {
          const rawJson = el.getAttribute('data-jogi-kwai-event');
          if (!rawJson || seenDom.has(rawJson)) continue;
          seenDom.add(rawJson);
          try {
            const parsed = JSON.parse(rawJson);
            if (typeof window.__jogiKwaiEmit === 'function') window.__jogiKwaiEmit(parsed);
          } catch (_) {}
        }
        const chatNodes = root.querySelectorAll(
          '[class*="chat-item"], [class*="comment-item"], [class*="barrage-item"]'
        );
        let idx = 0;
        for (const el of chatNodes) {
          idx += 1;
          const text = (el.textContent || '').replace(/\s+/g, ' ').trim();
          if (!text || text.length > 240) continue;
          const key = `${el.dataset?.id || ''}|${text}`;
          if (seenDom.has(key)) continue;
          seenDom.add(key);
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

    const page = context.pages()[0] || (await context.newPage());

    page.on('response', async response => {
      try {
        const ct = (response.headers()['content-type'] || '').toLowerCase();
        if (!ct.includes('json')) return;
        const body = await response.json();
        const { events, liveHint } = normalizeFeedPayload(body);
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
          const { events, liveHint } = normalizeFeedPayload(body);
          if (liveHint) lastFeedLiveAt = Date.now();
          for (const ev of events) {
            await forwardEvent(ev);
          }
        } catch (_) {}
      });
    });

    let activeTargetUrl = args.liveUrl
      ? defaultUrl
      : await fetchTargetUrlFromBridge(bridgeBase, defaultUrl, args.allowLocalTestUrl);
    let lastGotoAt = 0;

    const inspectPageStatus = async () => {
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

    while (!stopping) {
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
        } catch (navErr) {
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
    if (context) {
      await context.close().catch(() => {});
    }
  }
}

main().catch(err => {
  console.error('[kwai_live_collector]', err && err.message ? err.message : err);
  process.exit(1);
});
