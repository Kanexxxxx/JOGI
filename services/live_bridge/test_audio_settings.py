from __future__ import annotations
import asyncio
import json
from pathlib import Path
import tempfile
import unittest
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import urlopen
import websockets
from protocol import ProtocolValidationError, build_admin_command_envelope, validate_envelope
from server import LiveBridgeServer

FLAGS = {'voices_enabled':False,'sfx_enabled':True,'crowd_enabled':False,'memes_enabled':False}


class AudioSettingsTests(unittest.IsolatedAsyncioTestCase):
    async def test_atomic_flags_require_strict_booleans_and_scoped_command(self):
        envelope=build_admin_command_envelope(command='set_audio_settings',**FLAGS)
        self.assertEqual(envelope['payload']['action_id'],'admin_set_audio_settings')
        for changes in ({'voices_enabled':1},{'sfx_enabled':'true'},{'crowd_enabled':None}):
            with self.assertRaises(ProtocolValidationError):
                build_admin_command_envelope(command='set_audio_settings',**{**FLAGS,**changes})
        with self.assertRaises(ProtocolValidationError):
            validate_envelope({**envelope,'payload':{**envelope['payload'],'command':'pause_race'}})

    async def test_http_settings_restart_latest_only_and_confirmed_telemetry(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'tiktok.sqlite3'
            first=LiveBridgeServer(port=0,platform='tiktok',outbox_path=path)
            await first.start()
            base=f'http://127.0.0.1:{first.bound_port}'
            query=urlencode({'command':'set_audio_settings',**{key:str(value).lower() for key,value in FLAGS.items()}})
            response=await asyncio.to_thread(urlopen,base+'/api/admin/command?'+query)
            self.assertEqual(json.loads(response.read())['status'],'ok')
            self.assertEqual(first.audio_settings.value,FLAGS)
            self.assertFalse(first._build_admin_state_payload()['audio_settings_applied'])
            with self.assertRaises(HTTPError):
                await asyncio.to_thread(urlopen,base+'/api/admin/command?command=set_audio_settings&voices_enabled=true')
            await first.stop()
            second=LiveBridgeServer(port=0,platform='tiktok',outbox_path=path)
            await second.start()
            try:
                # Stale offline settings are discarded; only the newest configuration wins on reconnect.
                for value in (True,False):
                    second.enqueue_envelope(build_admin_command_envelope(command='set_audio_settings',**{**FLAGS,'voices_enabled':value},event_id=f'audio-{value}'))
                async with websockets.connect(f'ws://127.0.0.1:{second.bound_port}/ws/godot') as ws:
                    self.assertEqual(json.loads(await ws.recv())['event_type'],'system_status')
                    saved=json.loads(await ws.recv())
                    self.assertEqual(saved['payload']['command'],'set_audio_settings')
                    self.assertFalse(saved['payload']['voices_enabled'])
                    await ws.send(json.dumps({'type':'telemetry','audio':FLAGS}))
                    await asyncio.sleep(.05)
                    self.assertTrue(second._build_admin_state_payload()['audio_settings_applied'])
                    self.assertEqual(second.p0_queue.qsize(),0)
                self.assertEqual(second.audio_settings.value,FLAGS)
            finally:
                await second.stop()

    async def test_ws_bad_params_does_not_close_admin_and_settings_are_isolated(self):
        server=LiveBridgeServer(port=0,platform='kwai')
        await server.start()
        other=LiveBridgeServer(port=0,platform='tiktok')
        try:
            async with websockets.connect(f'ws://127.0.0.1:{server.bound_port}/ws/admin') as ws:
                await ws.recv()
                await ws.send(json.dumps({'type':'admin_command','command':'set_audio_settings','params':[]}))
                self.assertEqual(json.loads(await ws.recv())['status'],'error')
                await ws.send(json.dumps({'type':'admin_command','command':'set_audio_settings','params':FLAGS}))
                while True:
                    message=json.loads(await ws.recv())
                    if message.get('type')=='command_ack':
                        self.assertEqual(message['status'],'ok');break
                self.assertEqual(server.audio_settings.value,FLAGS)
                self.assertFalse(other.audio_settings.configured)
        finally:
            await server.stop(); await other.stop()


if __name__=='__main__':unittest.main()
