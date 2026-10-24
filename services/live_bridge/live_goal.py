"""Small per-instance goal configuration, atomically persisted without credentials."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from protocol import build_admin_command_envelope


class LiveGoalSettings:
    def __init__(self, path: Path | None) -> None:
        self.path = path
        self.configured = False
        self.value: dict[str, Any] = {"goal_kind": "likes", "goal_target": 1000, "goal_label": "Meta de curtidas"}
        if path is not None and path.exists():
            raw = json.loads(path.read_text(encoding="utf-8"))
            env = build_admin_command_envelope(command="set_live_goal", **raw)
            self.value = {key: env["payload"][key] for key in ("goal_kind", "goal_target", "goal_label", "goal_gift_id") if key in env["payload"]}
            self.configured = True

    def update(self, envelope: dict[str, Any]) -> None:
        value = {key: envelope["payload"][key] for key in ("goal_kind", "goal_target", "goal_label", "goal_gift_id") if key in envelope["payload"]}
        if self.path is not None:
            temp = self.path.with_suffix(".tmp")
            with temp.open("w", encoding="utf-8") as handle:
                json.dump(value, handle, ensure_ascii=False)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temp, self.path)
        self.value = value
        self.configured = True

    def envelope(self) -> dict[str, Any]:
        return build_admin_command_envelope(command="set_live_goal", **self.value)
