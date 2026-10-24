"""Testes offline: transportes simulados, sem chave real e sem consumo."""
from __future__ import annotations

import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
import urllib.error

from tools import elevenlabs_audio as audio


class Response(io.BytesIO):
    headers = {"Content-Type": "audio/mpeg"}


class FakeClient:
    def __init__(self, interrupted=False):
        self.interrupted = interrupted
        self.posts = 0

    def voices(self):
        return [{"voice_id": "original_voice_" + role, "name": "Original " + role, "description": "Voz fictícia de locução.", "category": "generated"}
                for role in ("narrator", "team1", "team2")]

    def get_json(self, _path):
        return [{"model_id": "eleven_multilingual_v2", "can_do_text_to_speech": True}]

    def subscription(self):
        return {"remaining": 30000}

    def request(self, path, payload=None):
        assert path.startswith("/v1/text-to-speech/") and payload is not None
        self.posts += 1
        if self.interrupted:
            raise audio.AudioError("Teste de resposta interrompida.")
        return b"ID3" + b"\0" * 200, {}


class ElevenLabsTests(unittest.TestCase):
    def setUp(self):
        self.data = audio.read_manifest()
        # A conta pode estar configurada e o pacote real já gerado; os testes
        # usam sempre uma cópia vazia, sem depender desse estado local.
        for profile in self.data["voices"].values():
            profile["voice_id"] = ""
            profile["original_synthetic"] = False
        for clip in self.data["clips"]:
            clip["clip_path"] = ""
            clip.pop("cache_key", None)

    def configured(self, only_first=False):
        data = copy.deepcopy(self.data)
        for role in data["voices"]:
            data["voices"][role] = {"voice_id": "original_voice_" + role, "original_synthetic": True}
        if only_first:
            data["clips"] = data["clips"][:1]
        return data

    def test_manifest_budget_symmetry_and_dry_run_without_network(self):
        with patch.object(audio.Client, "request", side_effect=AssertionError("Rede proibida")):
            plan = audio.plan(self.data)
        self.assertEqual(plan["clip_count"], 38)
        self.assertLessEqual(plan["total_characters"], 2000)
        self.assertFalse(plan["ready_to_generate"])
        self.assertEqual(plan["network_requests"], 0)
        for kind in ("boost", "shield", "attack", "super_turbo", "podium", "vote", "overtake"):
            teams = [[c for c in self.data["clips"] if c["kind"] == kind and c["team"] == team] for team in (1, 2)]
            self.assertEqual(len(teams[0]), len(teams[1]))
            self.assertEqual({c["priority"] for c in teams[0]}, {c["priority"] for c in teams[1]})
            self.assertEqual({c["cooldown_seconds"] for c in teams[0]}, {c["cooldown_seconds"] for c in teams[1]})

    def test_hard_budget_and_missing_voice_block_posts(self):
        data = copy.deepcopy(self.data)
        data["clips"] *= 10
        with self.assertRaises(audio.AudioError):
            audio.plan(data)
        client = FakeClient()
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(audio.AudioError):
                audio.generate(self.data, client, Path(folder), Path(folder) / "manifest.json")
        self.assertEqual(client.posts, 0)

    def test_secret_configuration_hidden_and_preserves_other_settings(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / ".env.local"
            path.write_text("LIVE_MODE=simulator\nELEVENLABS_API_KEY=old_fake_key_value\n", encoding="utf-8")
            fake_key = "test_secret_only_0123456789"
            with patch.object(audio.sys.stdin, "isatty", return_value=True), patch.object(audio.getpass, "getpass", return_value=fake_key):
                report = audio.configure(path)
            self.assertNotIn(fake_key, json.dumps(report))
            self.assertEqual(audio.read_env(path)["LIVE_MODE"], "simulator")
            self.assertEqual(audio.read_env(path)["ELEVENLABS_API_KEY"], fake_key)
            self.assertEqual(path.read_text().count("ELEVENLABS_API_KEY="), 1)
            with patch.object(audio.sys.stdin, "isatty", return_value=False):
                with self.assertRaises(audio.AudioError):
                    audio.configure(path)

    def test_env_is_data_and_environment_takes_precedence(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / ".env.local"
            path.write_text("ELEVENLABS_API_KEY='fake_file_key_0123456789'\nOTHER=$(do_not_execute)\n")
            self.assertEqual(audio.read_env(path)["OTHER"], "$(do_not_execute)")
            with patch.dict(audio.os.environ, {"ELEVENLABS_API_KEY": "fake_env_key_0123456789"}):
                self.assertEqual(audio.load_key(path), "fake_env_key_0123456789")

    def test_read_only_transport_has_fixed_host_timeout_and_redacted_errors(self):
        opener = Mock()
        opener.open.return_value = Response(json.dumps({"tier": "starter", "status": "active", "character_count": 30, "character_limit": 30000,
                                                       "email": "private@example.invalid"}).encode())
        client = audio.Client("fake_key_for_tests_0123456789", opener=opener)
        report = client.subscription()
        request = opener.open.call_args.args[0]
        self.assertEqual(request.get_method(), "GET")
        self.assertEqual(request.full_url, "https://api.elevenlabs.io/v1/user/subscription")
        self.assertEqual(opener.open.call_args.kwargs["timeout"], 45.0)
        self.assertEqual(report["remaining"], 29970)
        self.assertNotIn("email", report)
        opener.open.side_effect = urllib.error.URLError("fake_key_for_tests_0123456789")
        with self.assertRaises(audio.AudioError) as caught:
            client.subscription()
        self.assertNotIn("fake_key", str(caught.exception))
        with self.assertRaises(audio.AudioError):
            client.request("//evil.invalid")

    def test_no_redirect_and_voice_pagination(self):
        self.assertIsNone(audio.NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.invalid"))
        client = audio.Client("fake_key_for_tests_0123456789", opener=Mock())
        client.get_json = Mock(side_effect=[{"voices": [{"voice_id": "voice123", "name": "Original", "category": "generated"}], "has_more": True, "next_page_token": "a b"},
                                                {"voices": [], "has_more": False}])
        self.assertEqual(len(client.voices()), 1)
        self.assertIn("next_page_token=a+b", client.get_json.call_args_list[1].args[0])

    def test_original_voice_guard(self):
        data, client = self.configured(), FakeClient()
        audio.validate_profiles(data, client.voices())
        voices = client.voices()
        voices[0]["description"] = "Imitação de Lula"
        with self.assertRaises(audio.AudioError):
            audio.validate_profiles(data, voices)
        voices = client.voices()
        voices[1]["category"] = "cloned"
        with self.assertRaises(audio.AudioError):
            audio.validate_profiles(data, voices)
        data["voices"]["team2"] = data["voices"]["team1"]
        with self.assertRaises(audio.AudioError):
            audio.validate_profiles(data, client.voices())

    def test_cache_keys_include_voice_text_and_model(self):
        digest = audio.cache_key("model", "voice", "texto", {})
        self.assertEqual(len(digest), 64)
        self.assertNotEqual(digest, audio.cache_key("other", "voice", "texto", {}))
        self.assertNotEqual(digest, audio.cache_key("model", "other", "texto", {}))
        self.assertNotEqual(digest, audio.cache_key("model", "voice", "outro", {}))

    def test_successful_cache_is_reused_and_not_overwritten(self):
        data, client = self.configured(only_first=True), FakeClient()
        with tempfile.TemporaryDirectory() as folder:
            cache, manifest = Path(folder) / "cache", Path(folder) / "manifest.json"
            first = audio.generate(data, client, cache, manifest)
            mp3 = next(cache.glob("*.mp3"))
            before = mp3.read_bytes()
            second = audio.generate(data, client, cache, manifest)
            self.assertEqual((first["created"], second["reused"], client.posts), (1, 1, 1))
            self.assertEqual(mp3.read_bytes(), before)
            mp3.write_bytes(b"tampered")
            with self.assertRaises(audio.AudioError):
                audio.generate(data, client, cache, manifest)
            self.assertEqual(client.posts, 1)

    def test_ambiguous_paid_post_is_never_repeated(self):
        data, client = self.configured(only_first=True), FakeClient(interrupted=True)
        with tempfile.TemporaryDirectory() as folder:
            cache, manifest = Path(folder) / "cache", Path(folder) / "manifest.json"
            for _ in range(2):
                with self.assertRaises(audio.AudioError):
                    audio.generate(data, client, cache, manifest)
            journal = json.loads((cache / "generation_journal.json").read_text())
            self.assertEqual(next(iter(journal["entries"].values()))["state"], "uncertain")
            self.assertEqual(client.posts, 1)

    def test_insufficient_included_quota_prevents_paid_request(self):
        client = FakeClient()
        client.subscription = lambda: {"remaining": 0}
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(audio.AudioError):
                audio.generate(self.configured(), client, Path(folder), Path(folder) / "manifest.json")
        self.assertEqual(client.posts, 0)

    def test_another_generator_blocks_without_paid_request(self):
        client = FakeClient()
        with tempfile.TemporaryDirectory() as folder:
            cache = Path(folder)
            (cache / ".generation.lock").write_text("123")
            with self.assertRaises(audio.AudioError):
                audio.generate(self.configured(), client, cache, cache / "manifest.json")
            self.assertTrue((cache / ".generation.lock").is_file())
        self.assertEqual(client.posts, 0)


if __name__ == "__main__":
    unittest.main()
