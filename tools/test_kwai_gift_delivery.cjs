'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { DurableGiftDelivery } = require('./kwai_gift_delivery.cjs');
const { postGiftWebhook } = require('./kwai_live_collector.cjs');
const http = require('node:http');

const gift = id => ({ type: 'gift', event_id: id, user_id: 'u', display_name: 'Teste',
  gift_id: 'rose', coin_value: 1, repeat_count: 3,
  avatar_url: 'https://p16-sign-va.tiktokcdn.com/private-avatar.png',
  gift_image_url: 'https://p16-sign-va.tiktokcdn.com/gift.png' });
const ack = event => ({ acknowledged: true, raw_event_id: event.event_id, delivery_status: 'accepted' });

async function withDatabase(run) {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'jogi-kwai-delivery-test-'));
  assert.equal(path.dirname(path.resolve(folder)), path.resolve(os.tmpdir()));
  try { await run(path.join(folder, 'pending.sqlite3')); }
  finally { fs.rmSync(folder, { recursive: true, force: true, maxRetries: 4, retryDelay: 50 }); }
}

test('401, 503 and timeout retain exact paid IDs until a durable ACK', async () => {
  await withDatabase(async filename => {
    let now = 1000;
    const seen = [];
    let attempt = 0;
    const delivery = new DurableGiftDelivery(filename, { now: () => now, send: async event => {
      seen.push(event.event_id); attempt += 1;
      if (attempt === 1) return { acknowledged: false, code: '401' };
      if (attempt === 2) return { acknowledged: false, code: '503' };
      if (attempt === 3) throw new Error('timeout');
      return ack(event);
    }});
    try {
      delivery.accept(gift('gift-retry-0001'));
      for (let index = 0; index < 3; index += 1) {
        await delivery.flushDue();
        assert.equal(delivery.pendingCount(), 1);
        assert.equal(delivery.forwarded, 0);
        now += 31000;
      }
      await delivery.flushDue();
      assert.equal(delivery.pendingCount(), 0);
      assert.equal(delivery.forwarded, 1);
      assert.deepEqual(seen, Array(4).fill('gift-retry-0001'));
      assert.equal(delivery.accept(gift('gift-retry-0001')), 'duplicate');
      await delivery.flushDue();
      assert.equal(seen.length, 4);
    } finally { await delivery.close(); }
  });
});

test('restart recovers paid data without storing avatar URLs or credentials', async () => {
  await withDatabase(async filename => {
    const first = new DurableGiftDelivery(filename, { send: async () => ({ acknowledged: false, code: '503' }) });
    first.accept(gift('gift-restart-0002'));
    await first.flushDue();
    const stored = first.db.prepare('SELECT payload FROM pending').get().payload;
    assert(!stored.includes('avatar_url') && !stored.includes('gift_image_url') && !stored.includes('Token'));
    await first.close();
    let received;
    const second = new DurableGiftDelivery(filename, { send: async event => { received = event; return ack(event); } });
    try {
      assert.equal(second.pendingCount(), 1);
      await second.flushDue();
      assert.equal(second.pendingCount(), 0);
      assert.equal(received.event_id, 'gift-restart-0002');
      assert.equal(received.coin_value, 1);
      assert.equal(received.repeat_count, 3);
    } finally { await second.close(); }
  });
});

test('HTTP success alone, incorrect ID and unconfirmed payload never acknowledge', async () => {
  const responses = [true, { acknowledged: true, raw_event_id: 'wrong', delivery_status: 'accepted' },
    { acknowledged: true, raw_event_id: 'gift-invalid-0003', delivery_status: 'unconfirmed' }];
  let now = 0;
  const delivery = new DurableGiftDelivery(':memory:', { now: () => now, send: async () => responses.shift() });
  try {
    delivery.accept(gift('gift-invalid-0003'));
    for (let index = 0; index < 3; index += 1) {
      await delivery.flushDue(); now += 31000;
      assert.equal(delivery.pendingCount(), 1);
      assert.equal(delivery.forwarded, 0);
    }
  } finally { await delivery.close(); }
});

test('capacity is explicit, previous gifts remain pending, concurrent flush sends once', async () => {
  const delivery = new DurableGiftDelivery(':memory:', { maxPending: 1, send: async event => ack(event) });
  try {
    delivery.accept(gift('gift-bounded-0004'));
    assert.throws(() => delivery.accept(gift('gift-overflow-0005')), /cheia/);
    assert.equal(delivery.pendingCount(), 1);
    assert.equal(delivery.stats().requires_attention, true);
    await Promise.all([delivery.flushDue(), delivery.flushDue(), delivery.flushDue()]);
    assert.equal(delivery.forwarded, 1);
    assert.equal(delivery.pendingCount(), 0);
  } finally { await delivery.close(); }
});

test('actual loopback HTTP transport retries 401/503 and validates the webhook ACK', async () => {
  let attempt = 0;
  const received = [];
  const server = http.createServer(async (request, response) => {
    let body = '';
    for await (const chunk of request) body += chunk;
    const event = JSON.parse(body);
    received.push(event.event_id);
    attempt += 1;
    const status = attempt === 1 ? 401 : attempt === 2 ? 503 : 200;
    response.writeHead(status, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify(status === 200 ? ack(event) : { status: 'busy' }));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let now = 0;
  const delivery = new DurableGiftDelivery(':memory:', {
    now: () => now,
    send: event => postGiftWebhook(`http://127.0.0.1:${server.address().port}/webhook/kwai`, event),
  });
  try {
    delivery.accept(gift('gift-http-0006'));
    await delivery.flushDue();
    assert.equal(delivery.stats().attention, 'authorization_required');
    now += 31000;
    await delivery.flushDue();
    assert.equal(delivery.pendingCount(), 1);
    now += 31000;
    await delivery.flushDue();
    assert.equal(delivery.pendingCount(), 0);
    assert.equal(delivery.forwarded, 1);
    assert.deepEqual(received, Array(3).fill('gift-http-0006'));
  } finally {
    await delivery.close();
    await new Promise(resolve => server.close(resolve));
  }
});
