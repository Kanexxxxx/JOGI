"""Mock de SFX: nenhum segredo real, rede ou consumo."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from tools import elevenlabs_sfx as sfx
from tools.elevenlabs_audio import AudioError


class FakeClient:
    def __init__(self, fail=False, remaining=40000):
        self.fail, self.remaining, self.posts = fail, remaining, 0

    def subscription(self):
        return {"remaining":self.remaining,"used":self.posts*40}

    def request(self, path, payload):
        self.posts += 1
        assert path == "/v1/sound-generation?output_format=mp3_44100_128"
        assert payload["loop"] is False and .5 <= payload["duration_seconds"] <= 3.0
        if self.fail:
            raise AudioError("Mock de interrupção")
        return b"ID3" + b"\0"*200, {"character-cost":"40"}


class SFXTests(unittest.TestCase):
    def test_ambience_is_single_bounded_loop_and_separate_manifest(self):
        data = sfx.read_manifest(sfx.AMBIENCE_MANIFEST)
        prepared = sfx.plan(data)
        self.assertEqual((len(prepared["clips"]), prepared["total_seconds"], prepared["estimated_credit_ceiling"]), (1, 10.0, 400))
        self.assertIs(prepared["clips"][0]["request"]["loop"], True)
        self.assertEqual(prepared["network_requests"], 0)
        data["clips"][0]["duration_seconds"] = 31
        with self.assertRaises(AudioError):
            sfx.plan(data)

    def test_dry_plan_duration_credit_budget(self):
        plan = sfx.plan(sfx.read_manifest())
        self.assertEqual((len(plan["clips"]),plan["total_seconds"],plan["estimated_credit_ceiling"]),(4,6.0,800))
        self.assertEqual(plan["network_requests"],0)
        too_long = copy.deepcopy(sfx.read_manifest())
        for clip in too_long["clips"]:
            clip["duration_seconds"] = 3.0
        with self.assertRaises(AudioError):
            sfx.plan(too_long)

    def test_complete_cache_is_reused_without_post(self):
        client, data = FakeClient(), sfx.read_manifest()
        with tempfile.TemporaryDirectory() as folder:
            cache, manifest = Path(folder)/"cache", Path(folder)/"manifest.json"
            first = sfx.generate(data,client,cache,manifest)
            second = sfx.generate(data,client,cache,manifest)
            self.assertEqual((first["generated"],second["reused"],client.posts),(4,4,4))
            next(cache.glob("*.mp3")).write_bytes(b"modified")
            with self.assertRaises(AudioError):
                sfx.generate(data,client,cache,manifest)
            self.assertEqual(client.posts,4)

    def test_uncertain_post_is_blocked_and_journaled(self):
        client = FakeClient(fail=True)
        with tempfile.TemporaryDirectory() as folder:
            cache, manifest = Path(folder)/"cache", Path(folder)/"manifest.json"
            for _ in range(2):
                with self.assertRaises(AudioError):
                    sfx.generate(sfx.read_manifest(),client,cache,manifest)
            journal = json.loads((cache/"generation_journal.json").read_text())
            self.assertEqual(next(iter(journal["entries"].values()))["state"],"uncertain")
        self.assertEqual(client.posts,1)

    def test_included_quota_and_process_lock_prevent_post(self):
        for occupied in (False,True):
            client = FakeClient(remaining=0)
            with tempfile.TemporaryDirectory() as folder:
                cache = Path(folder)
                if occupied:
                    (cache/".generation.lock").write_text("123")
                with self.assertRaises(AudioError):
                    sfx.generate(sfx.read_manifest(),client,cache,cache/"manifest.json")
            self.assertEqual(client.posts,0)


if __name__ == "__main__":
    unittest.main()
