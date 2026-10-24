"""Copia MP3 explicitamente selecionados, sem alterar Downloads nem ativar clipes.

Plano offline por padrão. --execute grava cópias SHA256 e manifesto pendente.
Não envia arquivos para serviços externos nem extrai credenciais.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
if __package__ in (None, ''):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.elevenlabs_audio import atomic_json

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / 'game/assets/audio/user-memes'
MANIFEST = ROOT / 'game/resources/audio/user_meme_manifest.json'


def prepare(paths: list[Path]) -> list[dict]:
    entries = {}
    for source in paths:
        source = source.resolve(strict=True)
        if source.suffix.lower() != '.mp3' or not source.is_file() or not 128 <= source.stat().st_size <= 10_000_000:
            raise ValueError('Somente arquivos MP3 locais de 128 bytes a 10 MB.')
        body = source.read_bytes()
        if not (body.startswith(b'ID3') or (body[0] == 0xff and body[1] & 0xe0 == 0xe0)):
            raise ValueError('Arquivo sem assinatura MP3 reconhecível.')
        digest = hashlib.sha256(body).hexdigest()
        if digest not in entries:
            entries[digest] = {'id': digest, 'source_names': [], 'source_path': str(source), 'bytes': len(body),
                'clip_path': 'res://assets/audio/user-memes/' + digest + '.mp3', 'enabled': False,
                'review_status': 'pending', 'review_notes': '', 'kind': 'unassigned', 'team': 0,
                'duration_seconds': None, 'cooldown_seconds': 60}
        entries[digest]['source_names'].append(source.name)
    return list(entries.values())


def import_files(paths: list[Path], execute: bool = False) -> dict:
    entries = prepare(paths)
    if execute:
        previous = json.loads(MANIFEST.read_text(encoding='utf-8')) if MANIFEST.exists() else {}
        old = {item['id']: item for item in previous.get('clips', [])}
        DESTINATION.mkdir(parents=True, exist_ok=True)
        for entry in entries:
            target = DESTINATION / (entry['id'] + '.mp3')
            if target.exists():
                if hashlib.sha256(target.read_bytes()).hexdigest() != entry['id']:
                    raise ValueError('Cache alterado; nenhum arquivo será sobrescrito.')
            else:
                shutil.copyfile(entry['source_path'], target)
            entry.pop('source_path')
            if entry['id'] in old:
                for field in ('enabled', 'review_status', 'review_notes', 'kind', 'team', 'duration_seconds', 'cooldown_seconds'):
                    entry[field] = old[entry['id']].get(field, entry[field])
        atomic_json(MANIFEST, {'schema_version': 1, 'enabled': previous.get('enabled', False),
            'policy': 'Imported user files remain disabled until content/listening review. Filenames do not authorize playback.',
            'clips': entries})
    return {'dry_run': not execute, 'input_files': len(paths), 'unique_files': len(entries),
        'duplicates': len(paths)-len(entries), 'network_requests': 0, 'credits_spent': 0,
        'enabled_clips': sum(item['enabled'] is True for item in entries),
        'files': [{k:v for k,v in item.items() if k != 'source_path'} for item in entries]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', nargs='+', type=Path)
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    print(json.dumps(import_files(args.files, args.execute), ensure_ascii=True, indent=2))


if __name__ == '__main__':
    main()
