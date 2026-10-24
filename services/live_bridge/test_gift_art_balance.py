from __future__ import annotations

import asyncio
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import urlopen
import zlib

import websockets

from adapters.kwai_adapter import KwaiLiveAdapter
from adapters.tiktok_adapter import TikTokLiveAdapter
from gift_images import GiftImageCache, extract_gift_image, image_info, safe_gift_image_url, safe_icon_path
from protocol import ProtocolValidationError, build_admin_command_envelope, build_gift_envelope, gift_boost_for_total_coins, validate_envelope
from server import LiveBridgeServer


CDN_URL = 'https://p16-sign-va.tiktokcdn.com/gift/rose.webp?sig=example'


def png(width=2, height=2):
    def chunk(name, data):
        return struct.pack('>I', len(data)) + name + data + struct.pack('>I', zlib.crc32(name + data))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB',width,height,8,6,0,0,0)) + chunk(b'IDAT',zlib.compress((b'\0'+b'\xff\0\0\xff'*width)*height)) + chunk(b'IEND',b'')


class GiftBalanceAndURLTests(unittest.TestCase):
    def test_bracket_thresholds_symmetry_combo_and_zero_unknown(self):
        cases = ((0,0,0,0),(1,.6,3,5),(9,.6,3,5),(10,1.8,4,15),(99,1.8,4,15),
                 (100,4.2,5,35),(999,4.2,5,35),(1000,8.4,8,70),(9999,8.4,8,70),
                 (10000,18,10,150),(29999,18,10,150),(30000,24,10,200),(100000000,24,10,200))
        for total, amount, duration, percent in cases:
            with self.subTest(total=total):
                self.assertEqual(gift_boost_for_total_coins(total), (amount,duration,percent))
                for slot in (1,2):
                    gift = build_gift_envelope(user_id='u',display_name='U',candidate_slot=slot,unit_coin_value=min(total,100000))
                    expected = gift_boost_for_total_coins(min(total,100000))
                    self.assertEqual(tuple(gift['payload'][key] for key in ('boost_amount','boost_duration','boost_percent')),expected)
        combo = build_gift_envelope(user_id='u',display_name='U',candidate_slot=1,unit_coin_value=1,repeat_count=1000)
        self.assertEqual(combo['payload']['coin_value'],1000)
        self.assertEqual(combo['payload']['gift_tier'],'T1')
        self.assertEqual(combo['payload']['boost_amount'],8.4)
        self.assertEqual(combo['payload']['boost_percent'],70)
        top = build_gift_envelope(user_id='u',display_name='U',candidate_slot=2,gift_tier='T4')
        self.assertEqual(top['payload']['unit_coin_value'],1000)

    def test_url_allowlist_strict_and_unknown_metadata_nonfatal(self):
        self.assertEqual(extract_gift_image({'url_list':['http://bad',CDN_URL]}),CDN_URL)
        for url in ('http://p16.tiktokcdn.com/a','https://127.0.0.1/a','https://tiktokcdn.com.evil.test/a',
                    'https://evil-tiktokcdn.com/a','https://user:secret@p16.tiktokcdn.com/a',
                    'https://p16.tiktokcdn.com:8443/a','https://p16.tiktokcdn.com/a#x',
                    'https://p16.tiktokcdn.com/a\nX:1'):
            with self.subTest(url=url): self.assertIsNone(safe_gift_image_url(url))
        event = build_gift_envelope(user_id='u',display_name='U',candidate_slot=1,gift_image_url='https://evil.test/x')
        self.assertNotIn('gift_image_url',event['payload'])
        self.assertEqual(safe_icon_path('/gift-icons/'+'a'*64),'/gift-icons/'+'a'*64)
        for value in ('/gift-icons/../secret','http://localhost:8765/gift-icons/'+'a'*64,'/gift-icons/'+'a'*63):
            self.assertIsNone(safe_icon_path(value))

    def test_specific_goal_requires_identity_and_clears_for_other_goal(self):
        goal = build_admin_command_envelope(command='set_live_goal',goal_kind='gift_specific',goal_target=30,goal_label='Rosas',goal_gift_id='5655')
        self.assertEqual(goal['payload']['goal_gift_id'],'5655')
        for gift_id in (None,'','x'*65,'x\u202e'):
            with self.assertRaises(ProtocolValidationError):
                build_admin_command_envelope(command='set_live_goal',goal_kind='gift_specific',goal_target=30,goal_gift_id=gift_id)
        ordinary = build_admin_command_envelope(command='set_live_goal',goal_kind='likes',goal_target=30,goal_gift_id='5655')
        self.assertNotIn('goal_gift_id',ordinary['payload'])

    def test_image_type_and_dimension_guards(self):
        self.assertEqual(image_info(png()),('image/png',2,2))
        for image in (b'<html>'+b'a'*30,png(65535,1)):
            with self.assertRaises(ValueError): image_info(image)


class GiftCacheAndAPItests(unittest.IsolatedAsyncioTestCase):
    async def test_sdk_and_kwai_image_metadata_and_no_price_double_count(self):
        adapter = TikTokLiveAdapter()
        gift = await adapter.handle_gift_event({'event_id':'image-t','user':{'id':'1'},'gift':{'id':42,'name':'Rosa','diamond_count':1,'image':{'url_list':[CDN_URL]}},'repeat_count':1})
        self.assertEqual(gift['payload']['gift_image_url'],CDN_URL)
        kwai = await KwaiLiveAdapter().ingest_raw_event({'type':'gift','event_id':'image-k','user_id':'1','gift_id':42,'coins':10,'count':3,'gift_image_url':'https://p1.kwimgs.com/gift.png'})
        self.assertEqual(kwai['payload']['gift_image_url'],'https://p1.kwimgs.com/gift.png')
        self.assertEqual(kwai['payload']['coin_value'],30)

    async def test_cache_optional_nonblocking_hashed_local_route_and_disk_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'gifts.sqlite3'
            server = LiveBridgeServer(runtime_mode="development", port=0,platform='tiktok',outbox_path=path)
            await server.start()
            data=png(); metadata={'source_url':CDN_URL,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'content_type':'image/png','width':2,'height':2}
            gate=asyncio.Event()
            async def slow_download(key,url):
                await gate.wait()
                server.gift_images.ready[key]=metadata
                (server.gift_images.directory/key).write_bytes(data)
                (server.gift_images.directory/(key+'.json')).write_text(json.dumps(metadata),'utf-8')
                server.gift_images.pending.discard(key)
            with patch.object(server.gift_images,'_download',side_effect=slow_download):
                event=build_gift_envelope(user_id='u',display_name='U',candidate_slot=1,gift_id='rose',gift_image_url=CDN_URL,source='tiktok')
                self.assertEqual(server.enqueue_envelope(event),'accepted')
                pending=server.outbox.next_due()
                route=pending['payload']['gift_icon_path']
                self.assertEqual(route,'/gift-icons/'+hashlib.sha256(CDN_URL.encode()).hexdigest())
                self.assertEqual(server.outbox.pending_count(),1) # Art is not a prerequisite for durable acceptance.
                self.assertIsNone(server.gift_images.get(route))
                gate.set(); await asyncio.gather(*server.gift_images.tasks)
                response=await asyncio.to_thread(urlopen,f'http://127.0.0.1:{server.bound_port}'+route)
                self.assertEqual(response.read(),data)
                self.assertEqual(response.headers['Content-Type'],'image/png')
                self.assertEqual(response.headers['X-Content-Type-Options'],'nosniff')
            await server.stop()
            restored=GiftImageCache(Path(directory)/'gift-icons')
            self.assertEqual(restored.get(route),(data,'image/png'))
            (Path(directory)/'gift-icons'/route.rsplit('/',1)[1]).write_bytes(b'bad')
            self.assertIsNone(restored.get(route))
            await restored.stop()

    async def test_failed_image_does_not_reject_gift_and_attempt_budget_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            cache=GiftImageCache(Path(directory))
            with patch('gift_images.download_image',side_effect=ValueError('unavailable')):
                for index in range(300): cache.request(f'https://p16.tiktokcdn.com/{index}.png')
                self.assertLessEqual(len(cache.tasks),256)
                self.assertLessEqual(len(cache.attempted),256)
                await cache.stop()
            self.assertEqual(len(cache.tasks),0)

    async def test_specific_goal_http_ws_persist_and_platform_isolation(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'tiktok.sqlite3'
            server=LiveBridgeServer(runtime_mode="development", port=0,platform='tiktok',outbox_path=path)
            other=LiveBridgeServer(runtime_mode="development", port=0,platform='kwai')
            await server.start()
            base=f'http://127.0.0.1:{server.bound_port}'
            query=urlencode({'command':'set_live_goal','goal_kind':'gift_specific','goal_gift_id':'5655','goal_target':100,'goal_label':'Rosas'})
            response=await asyncio.to_thread(urlopen,base+'/api/admin/command?'+query)
            self.assertEqual(json.loads(response.read())['status'],'queued')
            self.assertEqual(server.live_goal.value['goal_gift_id'],'5655')
            self.assertEqual(other.live_goal.value['goal_kind'],'likes')
            async with websockets.connect(f'ws://127.0.0.1:{server.bound_port}/ws/admin') as ws:
                await ws.recv()
                await ws.send(json.dumps({'type':'admin_command','command':'set_live_goal','params':{'goal_kind':'gift_specific','goal_gift_id':'9999','goal_target':50,'goal_label':'Outro presente'}}))
                for _ in range(6):
                    message=json.loads(await ws.recv())
                    if message.get('type')=='command_ack':
                        self.assertEqual(message['status'],'queued'); break
                self.assertEqual(server.live_goal.value['goal_gift_id'],'9999')
            await server.stop(); await other.stop()
            restored=LiveBridgeServer(runtime_mode="development", port=0,platform='tiktok',outbox_path=path)
            self.assertEqual(restored.live_goal.value['goal_gift_id'],'9999')
            await restored.stop()


if __name__=='__main__': unittest.main()
