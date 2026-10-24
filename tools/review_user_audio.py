"""Local speech transcription for review, never enables game clips automatically."""
from pathlib import Path
import json
import os

os.environ.setdefault('HF_HUB_DISABLE_XET', '1')
import truststore
truststore.inject_into_ssl()
from faster_whisper import WhisperModel

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'game/resources/audio/user_meme_manifest.json').read_text(encoding='utf-8'))
destination = ROOT / 'docs/evidencias/audio/user-memes-transcripts.json'
model = WhisperModel('small', device='cpu', compute_type='int8', cpu_threads=4,
                     download_root=str(ROOT / '.tools/audio-models'))
results = []
for clip in manifest['clips']:
    path = ROOT / 'game' / clip['clip_path'].removeprefix('res://')
    segments, info = model.transcribe(str(path), language='pt', beam_size=5,
                                     vad_filter=True, condition_on_previous_text=False)
    text = ' '.join(segment.text.strip() for segment in segments)
    row = {'id': clip['id'], 'source_names': clip['source_names'], 'duration': info.duration,
           'language_probability': info.language_probability, 'text': text,
           'review': 'automatic transcript only; music/rights not certified'}
    results.append(row)
    destination.write_text(json.dumps({'model': 'faster-whisper small int8 local CPU', 'clips': results},
                                      ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(row, ensure_ascii=True), flush=True)
