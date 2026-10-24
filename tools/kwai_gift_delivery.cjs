'use strict';

// Paid events survive collector/bridge restarts. No credentials or avatar URLs
// enter this database; optional artwork is retained in bounded RAM only.
const fs = require('node:fs');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');

class DurableGiftDelivery {
  constructor(filename, { send, now = Date.now, account = 'kwai', maxPending = 10000 } = {}) {
    if (typeof send !== 'function') throw new TypeError('Gift delivery requires a sender.');
    if (filename !== ':memory:') fs.mkdirSync(path.dirname(filename), { recursive: true });
    this.db = new DatabaseSync(filename);
    this.db.exec('PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=1000;');
    this.db.exec(`CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS pending(event_id TEXT PRIMARY KEY,payload TEXT NOT NULL,
        created_ms INTEGER NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,due_ms INTEGER NOT NULL DEFAULT 0,last_code TEXT NOT NULL DEFAULT '');
      CREATE TABLE IF NOT EXISTS acknowledged(event_id TEXT PRIMARY KEY,acknowledged_ms INTEGER NOT NULL);
      CREATE INDEX IF NOT EXISTS pending_due ON pending(due_ms,created_ms);
      CREATE INDEX IF NOT EXISTS ack_time ON acknowledged(acknowledged_ms);`);
    const previous = this.db.prepare("SELECT value FROM metadata WHERE key='account'").get();
    if (previous && previous.value !== String(account)) {
      this.db.close();
      throw new Error('Fila de presentes pertence a outra conta Kwai. Preserve a pasta e escolha outra sessão.');
    }
    this.db.prepare("INSERT OR IGNORE INTO metadata(key,value) VALUES('account',?)").run(String(account));
    this.db.exec('UPDATE pending SET due_ms=0;');
    this.send = send;
    this.now = now;
    this.maxPending = Math.max(1, Math.min(10000, Math.trunc(maxPending)));
    this.artwork = new Map();
    this.attention = '';
    this.lastError = '';
    this.forwarded = 0;
    this.closing = false;
    this._pump = null;
    this._ackedSincePrune = 0;
    this._pruneAcked();
  }

  pendingCount() { return this.db.prepare('SELECT COUNT(*) AS n FROM pending').get().n; }

  accept(event) {
    if (this.closing) throw new Error('Coletor em encerramento.');
    const id = String(event?.event_id || '');
    if (!id || id.length > 128 || !['gift', 'present'].includes(event.type)) throw new Error('Identidade de presente inválida.');
    if (this.db.prepare('SELECT 1 FROM acknowledged WHERE event_id=?').get(id)) return 'duplicate';
    if (this.db.prepare('SELECT 1 FROM pending WHERE event_id=?').get(id)) return 'pending';
    if (this.pendingCount() >= this.maxPending) {
      this.attention = 'queue_full';
      throw new Error('Fila durável cheia: presentes anteriores preservados; intervenção do operador necessária.');
    }
    const payload = {};
    for (const key of ['type', 'event_id', 'user_id', 'display_name', 'gift_id', 'gift_name', 'coin_value', 'repeat_count', 'gift_tier']) {
      if (event[key] !== undefined) payload[key] = event[key];
    }
    const serialized = JSON.stringify(payload);
    if (Buffer.byteLength(serialized) > 65536) throw new Error('Presente excede o limite de armazenamento.');
    this.db.prepare('INSERT INTO pending(event_id,payload,created_ms) VALUES(?,?,?)').run(id, serialized, this.now());
    const artwork = {};
    for (const key of ['avatar_url', 'gift_image_url']) {
      if (typeof event[key] === 'string' && event[key].length <= 2048) artwork[key] = event[key];
    }
    this.artwork.set(id, artwork);
    return 'pending';
  }

  async flushDue() {
    if (this.closing || this._pump) return this._pump;
    this._pump = this._flush().finally(() => { this._pump = null; });
    return this._pump;
  }

  async _flush() {
    // A bounded batch leaves room for browser observation and heartbeats.
    for (let count = 0; count < 16 && !this.closing; count += 1) {
      const row = this.db.prepare('SELECT * FROM pending WHERE due_ms<=? ORDER BY created_ms,rowid LIMIT 1').get(this.now());
      if (!row) break;
      let result;
      try {
        result = await this.send({ ...JSON.parse(row.payload), ...(this.artwork.get(row.event_id) || {}) });
      } catch (_) {
        result = { acknowledged: false, code: 'network_error' };
      }
      if (result?.acknowledged === true && result.raw_event_id === row.event_id && ['accepted', 'duplicate'].includes(result.delivery_status)) {
        this.db.exec('BEGIN IMMEDIATE;');
        try {
          this.db.prepare('INSERT OR IGNORE INTO acknowledged(event_id,acknowledged_ms) VALUES(?,?)').run(row.event_id, this.now());
          this.db.prepare('DELETE FROM pending WHERE event_id=?').run(row.event_id);
          this.db.exec('COMMIT;');
        } catch (error) {
          this.db.exec('ROLLBACK;');
          throw error;
        }
        this.artwork.delete(row.event_id);
        this.forwarded += 1;
        this.lastError = '';
        if (this.attention !== 'queue_full') this.attention = '';
        this._ackedSincePrune += 1;
        if (this._ackedSincePrune >= 100) { this._pruneAcked(); this._ackedSincePrune = 0; }
      } else {
        const code = String(result?.code || 'missing_durable_ack').slice(0, 40);
        const attempts = row.attempts + 1;
        const delay = Math.min(30000, 1000 * 2 ** Math.min(attempts - 1, 5));
        this.db.prepare('UPDATE pending SET attempts=?,due_ms=?,last_code=? WHERE event_id=?').run(attempts, this.now() + delay, code, row.event_id);
        this.lastError = code;
        if (code === '401' || code === '403') this.attention = 'authorization_required';
      }
    }
  }

  _pruneAcked() {
    this.db.exec('DELETE FROM acknowledged WHERE event_id IN (SELECT event_id FROM acknowledged ORDER BY acknowledged_ms DESC LIMIT -1 OFFSET 10000);');
  }

  stats() {
    return { pending: this.pendingCount(), forwarded: this.forwarded,
      requires_attention: Boolean(this.attention), attention: this.attention,
      retrying: Boolean(this.lastError), last_error: this.lastError, capacity: this.maxPending };
  }

  async close() {
    this.closing = true;
    if (this._pump) await this._pump;
    this.db.close();
  }
}

module.exports = { DurableGiftDelivery };
