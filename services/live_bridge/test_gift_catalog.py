import asyncio
import json
from pathlib import Path
import tempfile
import unittest
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import urlopen

from protocol import ProtocolValidationError, build_gift_envelope, validate_envelope
from server import LiveBridgeServer


def gift(event_id, value=42, source='tiktok'):
    return build_gift_envelope(user_id='u',display_name='U',candidate_slot=1,
        event_id=event_id,gift_id='rose-99',gift_name='Rosa',unit_coin_value=value,
        gift_tier='T2',source=source)


class GiftSchemaTests(unittest.TestCase):
    def test_optional_metadata_and_total_consistency(self):
        event = gift('evt_catalog_schema')
        self.assertEqual(event['payload']['gift_id'],'rose-99')
        self.assertEqual(event['payload']['unit_coin_value'],42)
        legacy = {**event,'payload':{key:value for key,value in event['payload'].items() if key not in ('gift_id','unit_coin_value')}}
        validate_envelope(legacy)
        for changes in ({'gift_id':'x'*65},{'unit_coin_value':True},{'coin_value':84}):
            with self.assertRaises(ProtocolValidationError):
                validate_envelope({**event,'payload':{**event['payload'],**changes}})


class GiftCatalogTests(unittest.IsolatedAsyncioTestCase):
    async def test_mapping_persists_and_keeps_old_pending_events_and_real_values(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'gifts.sqlite3'
            first=LiveBridgeServer(port=0,platform='tiktok',outbox_path=path)
            first.enqueue_envelope(gift('evt_catalog_first'))
            first.gift_catalog.set_action('tiktok','rose-99','attack')
            first.enqueue_envelope(gift('evt_catalog_second',50))
            rows=first.outbox.db.execute('SELECT envelope FROM gifts ORDER BY rowid').fetchall()
            old,new=(json.loads(row[0]) for row in rows)
            self.assertEqual(old['payload']['gift_tier'],'T2')
            self.assertEqual(new['payload']['gift_tier'],'T3')
            self.assertEqual(new['payload']['action_id'],'gift_t3_attack')
            self.assertEqual(new['payload']['coin_value'],50)
            self.assertEqual(new['payload']['unit_coin_value'],50)
            await first.stop()
            second=LiveBridgeServer(port=0,platform='tiktok',outbox_path=path)
            row=second.gift_catalog.listing()['entries'][0]
            self.assertEqual(row['action'],'attack')
            self.assertTrue(row['override'])
            self.assertEqual(row['unit_coin_value'],50)
            await second.stop()

    async def test_source_isolation_and_duplicate_does_not_overwrite_metadata(self):
        bridge=LiveBridgeServer(port=0)
        bridge.enqueue_envelope(gift('evt_catalog_source'))
        bridge.gift_catalog.set_action('tiktok','rose-99','super_turbo')
        self.assertEqual(bridge.enqueue_envelope(gift('evt_catalog_source',99)),'duplicate')
        bridge.enqueue_envelope(gift('evt_catalog_kwai',42,'kwai'))
        kwai=json.loads(bridge.outbox.db.execute("SELECT envelope FROM gifts WHERE event_id='evt_catalog_kwai'").fetchone()[0])
        self.assertEqual(kwai['payload']['gift_tier'],'T2')
        entries={row['source']:row for row in bridge.gift_catalog.listing()['entries']}
        self.assertEqual(entries['tiktok']['unit_coin_value'],42)
        self.assertFalse(entries['kwai']['override'])
        await bridge.stop()

    async def test_catalog_http_read_edit_restore_and_validation(self):
        bridge=LiveBridgeServer(port=0,platform='tiktok')
        await bridge.start()
        base=f'http://127.0.0.1:{bridge.bound_port}'
        async def request(route):
            response=await asyncio.to_thread(urlopen,base+route)
            return json.loads(response.read())
        try:
            initial=await request('/api/gifts')
            self.assertEqual(initial['total'],0)
            self.assertFalse(initial['official_catalog_complete'])
            bridge.enqueue_envelope(gift('evt_http_catalog'))
            query=urlencode({'source':'tiktok','gift_id':'rose-99','action':'shield'})
            result=await request('/api/admin/gift?'+query)
            self.assertEqual(result['entries'][0]['action'],'shield')
            self.assertTrue(result['entries'][0]['override'])
            result=await request('/api/admin/gift?'+query.replace('shield','default'))
            self.assertFalse(result['entries'][0]['override'])
            with self.assertRaises(HTTPError) as error:
                await request('/api/admin/gift?source=tiktok&gift_id=missing&action=boost')
            self.assertEqual(error.exception.code,404)
            with self.assertRaises(HTTPError) as error:
                await request('/api/admin/gift?source=tiktok&gift_id=rose-99&action=arbitrary')
            self.assertEqual(error.exception.code,400)
        finally:
            await bridge.stop()


if __name__=='__main__':unittest.main()
