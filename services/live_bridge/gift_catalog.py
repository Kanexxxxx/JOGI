"""Observed gift metadata and explicit per-gift mechanics; never a fabricated official catalog."""
from __future__ import annotations
import json
from pathlib import Path
import sqlite3
import time
from typing import Any
from protocol import gift_tier_for_unit_coins

ACTIONS = {'boost': ('T1', 'gift_t1_turbo'), 'shield': ('T2', 'gift_t2_shield_or_obstacle'),
           'attack': ('T3', 'gift_t3_attack'), 'super_turbo': ('T4', 'gift_t4_super_rally')}
DEFAULTS = {'T1':'boost','T2':'shield','T3':'attack','T4':'super_turbo'}


class GiftCatalog:
    def __init__(self, connection: sqlite3.Connection) -> None:
        self.db = connection
        with self.db:
            self.db.execute('''CREATE TABLE IF NOT EXISTS gift_catalog (
                source TEXT NOT NULL, gift_id TEXT NOT NULL, name TEXT NOT NULL,
                unit_value INTEGER NOT NULL, last_seen_ms INTEGER NOT NULL,
                action_override TEXT, PRIMARY KEY(source,gift_id))''')

    def observe(self, envelope: dict[str, Any]) -> None:
        payload = envelope['payload']
        if not payload.get('gift_id'):
            return
        with self.db:
            self.db.execute('''INSERT INTO gift_catalog(source,gift_id,name,unit_value,last_seen_ms)
                VALUES(?,?,?,?,?) ON CONFLICT(source,gift_id) DO UPDATE SET
                name=excluded.name,unit_value=excluded.unit_value,last_seen_ms=excluded.last_seen_ms''',
                (envelope['source'],payload['gift_id'],payload.get('gift_name','Presente'),
                 payload.get('unit_coin_value',0),int(time.time()*1000)))

    def apply(self, envelope: dict[str, Any]) -> dict[str, Any]:
        payload = envelope['payload']
        if not payload.get('gift_id'):
            return envelope
        row = self.db.execute('SELECT action_override FROM gift_catalog WHERE source=? AND gift_id=?',
                              (envelope['source'],payload['gift_id'])).fetchone()
        if not row or not row[0]:
            return envelope
        tier, action = ACTIONS[row[0]]
        clean = {**payload, 'action_id':action}
        if envelope['source'] != 'tiktok':
            clean['gift_tier'] = tier
        # Overrides change only the mechanic; price, delta and total remain actual.
        # A former attack must never carry an attack target into a shield/boost.
        if row[0] != 'attack':
            clean.pop('target_slot', None)
            clean.pop('obstacle_type', None)
        elif clean.get('candidate_slot') in (1, 2):
            clean.update(target_slot=3-clean['candidate_slot'], obstacle_type='pilha_documentos')
        return {**envelope, 'payload':clean}

    def set_action(self, source: str, gift_id: str, action: str) -> None:
        if action not in (*ACTIONS, 'default') or not isinstance(gift_id,str) or not 1 <= len(gift_id) <= 64:
            raise ValueError('Ação ou gift_id inválido.')
        with self.db:
            cursor = self.db.execute('UPDATE gift_catalog SET action_override=? WHERE source=? AND gift_id=?',
                                    (None if action == 'default' else action,source,gift_id))
            if not cursor.rowcount:
                raise LookupError('Presente ainda não observado nesta fonte/plataforma.')

    def listing(self, limit: int = 200, offset: int = 0) -> dict[str, Any]:
        limit = max(1,min(limit,200)); offset=max(0,min(offset,1_000_000))
        rows = self.db.execute('SELECT source,gift_id,name,unit_value,last_seen_ms,action_override FROM gift_catalog ORDER BY last_seen_ms DESC,source,gift_id LIMIT ? OFFSET ?',
                               (limit,offset)).fetchall()
        entries = []
        for source,gift_id,name,unit,last_seen,override in rows:
            default = DEFAULTS[gift_tier_for_unit_coins(unit)]
            entries.append({'source':source,'gift_id':gift_id,'gift_name':name,'unit_coin_value':unit,
                'last_seen_ms':last_seen,'default_action':default,'action':override or default,
                'override':bool(override)})
        total = self.db.execute('SELECT COUNT(*) FROM gift_catalog').fetchone()[0]
        return {'entries':entries,'total':total,'offset':offset,'limit':limit,'official_catalog_complete':False}

    def showcase(self, account: str) -> list[dict[str, Any]]:
        path=Path(__file__).resolve().parents[2]/"game/assets/catalogs/tiktok_gift_showcase.json"
        try:
            value=json.loads(path.read_text(encoding="utf-8"))
            if value.get("platform") != "tiktok" or value.get("account") != account:
                return []
            return value.get("entries", [])[:4]
        except (OSError,ValueError,TypeError):
            return []
