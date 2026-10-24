"""Inspect run clip seam without modifying the approved GLBs."""
import json
import math
import struct
from pathlib import Path

root = Path(__file__).resolve().parents[1]
for slug in ("lula", "flavio"):
    raw = (root / f"game/assets/characters/api-cape-v13/{slug}_run.glb").read_bytes()
    length = struct.unpack_from("<I", raw, 12)[0]
    data = json.loads(raw[20:20 + length])
    binary = raw[28 + length:]

    def values(index):
        accessor = data["accessors"][index]
        view = data["bufferViews"][accessor["bufferView"]]
        width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[accessor["type"]]
        stride = view.get("byteStride", width * 4)
        start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        return [struct.unpack_from("<" + "f" * width, binary, start + i * stride) for i in range(accessor["count"])]

    seams = []
    rotations = []
    for channel in data["animations"][0]["channels"]:
        sampler = data["animations"][0]["samplers"][channel["sampler"]]
        samples = values(sampler["output"])
        if channel["target"]["path"] == "rotation":
            if len(samples) > 20:
                rotations.append(samples)
            dot = abs(sum(a * b for a, b in zip(samples[0], samples[-1])))
            seams.append((math.degrees(2 * math.acos(min(1.0, dot))), data["nodes"][channel["target"]["node"]]["name"]))
    seams.sort(reverse=True)
    matching = []
    for frame in range(15, min(len(samples) for samples in rotations)):
        errors = [math.degrees(2 * math.acos(min(1.0, abs(sum(a * b for a, b in zip(samples[0], samples[frame])))))) for samples in rotations]
        matching.append((sum(errors) / len(errors), frame, max(errors)))
    matching.sort()
    print(json.dumps({"character": slug, "max_seam_degrees": seams[:5], "best_ending_frames": matching[:5]}))
