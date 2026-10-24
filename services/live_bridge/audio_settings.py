"""Four per-instance audio switches, persisted only after an explicit local command."""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any
from protocol import build_admin_command_envelope

AUDIO_KEYS = ('voices_enabled', 'sfx_enabled', 'crowd_enabled', 'memes_enabled')


class AudioSettings:
    def __init__(self, path: Path | None) -> None:
        self.path = path
        self.configured = False
        self.value: dict[str, bool] = {'voices_enabled':True,'sfx_enabled':True,'crowd_enabled':True,'memes_enabled':False}
        if path is not None and path.exists():
            raw = json.loads(path.read_text(encoding='utf-8'))
            envelope = build_admin_command_envelope(command='set_audio_settings', **raw)
            self.value = {key:envelope['payload'][key] for key in AUDIO_KEYS}
            self.configured = True

    def update(self, envelope: dict[str, Any]) -> None:
        value = {key:envelope['payload'][key] for key in AUDIO_KEYS}
        if self.path is not None:
            temp = self.path.with_suffix('.tmp')
            with temp.open('w',encoding='utf-8') as handle:
                json.dump(value,handle)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temp,self.path)
        self.value = value
        self.configured = True

    def envelope(self) -> dict[str, Any]:
        return build_admin_command_envelope(command='set_audio_settings', **self.value)
