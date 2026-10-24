"""Small per-instance goal configuration, atomically persisted without credentials.

Supports both:
- Legacy single-goal configuration (`set_live_goal` -> `live_goal.json`) for 100% backward compatibility.
- Simultaneous 3-goal configuration (`set_live_goals` -> `live_goals.json`) for Likes, Gifts/Coins/Specific-ID,
  and Followers (default target 10,000, with optional operator-supplied `follower_baseline`).
"""

from __future__ import annotations

import copy
import json
import os
from pathlib import Path
from typing import Any

from protocol import build_admin_command_envelope, validate_live_goals_spec


def default_live_goals() -> dict[str, dict[str, Any]]:
    return {
        "likes": {
            "goal_kind": "likes",
            "goal_target": 1000,
            "goal_label": "Meta de curtidas",
        },
        "gifts": {
            "goal_kind": "gifts",
            "goal_target": 500,
            "goal_label": "Meta de presentes",
        },
        "follows": {
            "goal_kind": "follows",
            "goal_target": 10000,
            "goal_label": "Meta de seguidores",
            "follower_baseline": None,
            "baseline_updated_at": None,
        },
    }


def _atomic_write_json(target: Path, payload: dict[str, Any]) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    temp = target.with_suffix(target.suffix + ".tmp")
    with temp.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp, target)


def _slot_for_goal_kind(kind: str) -> str:
    if kind == "likes":
        return "likes"
    if kind == "follows":
        return "follows"
    return "gifts"


class LiveGoalSettings:
    def __init__(self, path: Path | None) -> None:
        self.path = path
        self.multi_path: Path | None = (path.parent / "live_goals.json") if path is not None else None
        self.configured = False
        self.multi_configured = False
        self.value: dict[str, Any] = {
            "goal_kind": "likes",
            "goal_target": 1000,
            "goal_label": "Meta de curtidas",
        }
        self.goals: dict[str, dict[str, Any]] = default_live_goals()

        if path is not None and path.exists():
            raw = json.loads(path.read_text(encoding="utf-8"))
            env = build_admin_command_envelope(command="set_live_goal", **raw)
            self.value = {
                key: env["payload"][key]
                for key in ("goal_kind", "goal_target", "goal_label", "goal_gift_id")
                if key in env["payload"]
            }
            self.configured = True
            self._sync_single_into_multi(self.value)

        if self.multi_path is not None and self.multi_path.exists():
            raw_multi = json.loads(self.multi_path.read_text(encoding="utf-8"))
            raw_goals = raw_multi.get("live_goals", raw_multi) if isinstance(raw_multi, dict) else raw_multi
            env_multi = build_admin_command_envelope(command="set_live_goals", live_goals=raw_goals)
            self.goals = copy.deepcopy(env_multi["payload"]["live_goals"])
            self.multi_configured = True

    def _sync_single_into_multi(self, single: dict[str, Any]) -> None:
        slot = _slot_for_goal_kind(str(single.get("goal_kind", "likes")))
        updated_slot: dict[str, Any] = {
            "goal_kind": single["goal_kind"],
            "goal_target": int(single["goal_target"]),
            "goal_label": str(single["goal_label"]),
        }
        if single.get("goal_kind") == "gift_specific" and single.get("goal_gift_id"):
            updated_slot["goal_gift_id"] = str(single["goal_gift_id"])
        if slot == "follows":
            prev_follows = self.goals.get("follows", {})
            updated_slot["follower_baseline"] = prev_follows.get("follower_baseline")
            updated_slot["baseline_updated_at"] = prev_follows.get("baseline_updated_at")
        merged = copy.deepcopy(self.goals)
        merged[slot] = updated_slot
        self.goals = validate_live_goals_spec(merged)

    def update(self, envelope: dict[str, Any]) -> None:
        value = {
            key: envelope["payload"][key]
            for key in ("goal_kind", "goal_target", "goal_label", "goal_gift_id")
            if key in envelope["payload"]
        }
        self._sync_single_into_multi(value)
        if self.path is not None:
            _atomic_write_json(self.path, value)
        if self.multi_configured and self.multi_path is not None:
            _atomic_write_json(self.multi_path, {"live_goals": self.goals})
        self.value = value
        self.configured = True

    def update_goals(self, envelope: dict[str, Any]) -> None:
        validated = validate_live_goals_spec(envelope["payload"].get("live_goals"))
        if self.multi_path is not None:
            _atomic_write_json(self.multi_path, {"live_goals": validated})
        self.goals = copy.deepcopy(validated)
        self.multi_configured = True

    def snapshot_goals(self) -> dict[str, dict[str, Any]]:
        return copy.deepcopy(self.goals)

    def envelope(self) -> dict[str, Any]:
        return build_admin_command_envelope(command="set_live_goal", **self.value)

    def multi_envelope(self) -> dict[str, Any]:
        return build_admin_command_envelope(command="set_live_goals", live_goals=self.snapshot_goals())
