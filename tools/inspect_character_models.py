"""Read-only Blender import audit for the original exported characters.

Run with Blender --background --python tools/inspect_character_models.py.
Only writes a JSON report under docs; never rewrites source models.
"""
import json
from pathlib import Path

import bpy
from mathutils import Vector


root = Path(__file__).resolve().parent.parent
results = {}
for slug in ("lula", "flavio"):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    model_path = root / "assets" / "models" / slug / f"{slug}_base_v1.glb"
    bpy.ops.import_scene.gltf(filepath=str(model_path))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    low = [min(point[axis] for point in points) for axis in range(3)]
    high = [max(point[axis] for point in points) for axis in range(3)]
    results[slug] = {
        "imported": True,
        "mesh_objects": len(meshes),
        "polygons": sum(len(obj.data.polygons) for obj in meshes),
        "vertices": sum(len(obj.data.vertices) for obj in meshes),
        "armatures": sum(obj.type == "ARMATURE" for obj in bpy.context.scene.objects),
        "actions": len(bpy.data.actions),
        "bounds_min": low,
        "bounds_max": high,
        "images": [{"name": image.name, "size": list(image.size),
                    "packed": image.packed_file is not None}
                   for image in bpy.data.images if image.type == "IMAGE"],
        "material_names": [material.name for material in bpy.data.materials],
    }
    print("CHARACTER_IMPORT_AUDIT " + json.dumps({slug: results[slug]}))

report_path = root / "docs" / "MODELOS_BLENDER_IMPORT.json"
report_path.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
print("CHARACTER_IMPORT_AUDIT_PASSED")
