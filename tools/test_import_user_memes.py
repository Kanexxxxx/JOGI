"""Importação offline: fontes preservadas, cópias por hash e revisão obrigatória."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from tools import import_user_memes as importer


class UserMemeImportTests(unittest.TestCase):
    def test_plan_no_writes_and_duplicate_hash(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            body = b'ID3' + b'\0' * 200
            first, second = root/'first.mp3', root/'second.mp3'
            first.write_bytes(body)
            second.write_bytes(body)
            with patch.object(importer, 'DESTINATION', root/'cache'), patch.object(importer, 'MANIFEST', root/'manifest.json'):
                plan = importer.import_files([first, second])
            self.assertEqual((plan['unique_files'], plan['duplicates'], plan['enabled_clips']), (1, 1, 0))
            self.assertFalse((root/'cache').exists())
            self.assertEqual(first.read_bytes(), body)

    def test_execute_copies_preserves_source_and_never_enables_unreviewed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root/'source.mp3'
            original = b'ID3' + b'\0' * 200
            source.write_bytes(original)
            manifest = root/'manifest.json'
            with patch.object(importer, 'DESTINATION', root/'cache'), patch.object(importer, 'MANIFEST', manifest):
                report = importer.import_files([source], True)
                saved = json.loads(manifest.read_text())
                self.assertFalse(saved['enabled'])
                self.assertEqual(saved['clips'][0]['review_status'], 'pending')
                self.assertFalse(saved['clips'][0]['enabled'])
                self.assertEqual(source.read_bytes(), original)
                copied = next((root/'cache').glob('*.mp3'))
                copied.write_bytes(b'changed')
                with self.assertRaises(ValueError):
                    importer.import_files([source], True)
                self.assertEqual(report['network_requests'], 0)

    def test_reject_non_mp3_signature(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)/'fake.mp3'
            source.write_bytes(b'x'*300)
            with self.assertRaises(ValueError):
                importer.prepare([source])


if __name__ == '__main__':
    unittest.main()
