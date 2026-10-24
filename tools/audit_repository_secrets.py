"""Scan tracked text without ever printing candidate credential values."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RULES = {
    'tripo_key': re.compile(r'tsk_[A-Za-z0-9_\-]{24,}'),
    'openai_key': re.compile(r'sk-(?:proj-|svcacct-)?[A-Za-z0-9_\-]{32,}'),
    'elevenlabs_key': re.compile(r'sk_[A-Za-z0-9]{24,}'),
    'github_token': re.compile(r'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})'),
    'private_key': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'aws_access_key': re.compile(r'AKIA[A-Z0-9]{16}'),
}
TEXT = {'.py', '.gd', '.gdshader', '.json', '.md', '.txt', '.js', '.cjs', '.html', '.css',
        '.toml', '.yaml', '.yml', '.cmd', '.ps1', '.example', '.tscn', '.tres', '.cfg'}


def findings(content: str, name: str) -> list[dict]:
    result = []
    for line_number, line in enumerate(content.splitlines(), 1):
        for kind, pattern in RULES.items():
            for match in pattern.finditer(line):
                # Obvious fixture/redaction values are not real account credentials.
                value = match.group(0)
                if any(word in value.lower() for word in ('example', 'placeholder', 'dummy', 'fake', 'redacted')):
                    continue
                if len(set(value.split('_')[-1])) < 4:
                    continue
                result.append({'file': name, 'line': line_number, 'rule': kind})
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--history', action='store_true')
    args = parser.parse_args()
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode('utf-8').split('\0')
    result = []
    inspected = 0
    for name in tracked:
        path = ROOT / name
        if path.suffix.lower() not in TEXT or not path.is_file() or path.stat().st_size > 4_000_000:
            continue
        inspected += 1
        result.extend(findings(path.read_text(encoding='utf-8', errors='replace'), name))
    history_blobs = 0
    if args.history:
        objects = subprocess.check_output(['git', 'rev-list', '--objects', '--all'], cwd=ROOT).decode('utf-8').splitlines()
        for item in objects:
            parts = item.split(' ', 1)
            if len(parts) != 2 or Path(parts[1]).suffix.lower() not in TEXT:
                continue
            kind = subprocess.check_output(['git', 'cat-file', '-t', parts[0]], cwd=ROOT).strip()
            if kind != b'blob':
                continue
            content = subprocess.check_output(['git', 'cat-file', '-p', parts[0]], cwd=ROOT)
            if len(content) > 4_000_000:
                continue
            history_blobs += 1
            result.extend(findings(content.decode('utf-8', errors='replace'), 'history:' + parts[0][:10] + ':' + parts[1]))
    print(json.dumps({'scope': 'known credential patterns; not a guarantee against all secrets',
                      'tracked_text_files': inspected, 'history_text_blobs': history_blobs,
                      'candidates': result, 'candidate_values_printed': False}, ensure_ascii=False, indent=2))
    return 1 if result else 0


if __name__ == '__main__':
    raise SystemExit(main())
