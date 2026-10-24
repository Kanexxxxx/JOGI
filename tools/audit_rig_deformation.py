"""Read-only diagnostic: list edges severely stretched by the draft run clip."""
import json
import re
import sys
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parent.parent
VERSION = sys.argv[sys.argv.index("--version") + 1] if "--version" in sys.argv else "v4"
if not re.fullmatch(r"v[1-9][0-9]{0,3}", VERSION):
    raise ValueError("Version must be v1..v9999 without path separators")
report = {}
for slug in ("lula", "flavio"):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / f"assets/models/{slug}/rig-preview-{VERSION}/{slug}_rig_preview_{VERSION}.glb"))
    rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    rig.animation_data_create()
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    rest_edges = [(a, b, (mesh.data.vertices[a].co - mesh.data.vertices[b].co).length)
                  for edge in mesh.data.edges for a, b in [edge.vertices]]
    samples = []
    for clip, frames in (("corrida", range(1, 26, 3)), ("turbo", range(1, 20, 3))):
        action = next(a for a in bpy.data.actions if a.name.startswith(clip))
        rig.animation_data.action = action
        rig.animation_data.action_slot = next(s for s in action.slots if s.target_id_type == "OBJECT")
        for frame in frames:
            bpy.context.scene.frame_set(frame)
            bpy.context.view_layer.update()
            evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
            posed = evaluated.to_mesh()
            stretched = []
            for a, b, before in rest_edges:
                after = (posed.vertices[a].co - posed.vertices[b].co).length
                if after > .05 and after > before * 6:
                    stretched.append({"before": round(before, 4), "after": round(after, 4), "ends": [a, b]})
            samples.append({"clip": clip, "frame": frame, "severe_stretched_edges": len(stretched),
                            "worst": sorted(stretched, key=lambda item: item["after"], reverse=True)[:3]})
            evaluated.to_mesh_clear()
    report[slug] = {"version": VERSION, "criterion": "posed edge > .05 Blender units and > 6x rest length",
                    "samples": samples, "max_severe_edges": max(s["severe_stretched_edges"] for s in samples),
                    "note": "diagnostic only; does not certify joint, cloth, collision or aesthetic quality"}
    print("DEFORMATION_AUDIT " + json.dumps({"slug": slug, "samples": len(samples),
                                            "max_severe_edges": report[slug]["max_severe_edges"]}), flush=True)
(ROOT / f"docs/MODELOS_DEFORMACAO_{VERSION}.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
