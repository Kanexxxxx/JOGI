"""Create non-destructive 15k-triangle candidates and render comparisons in Blender.

Original exports are read-only. This is simplification, not retopology or rigging.
"""
import json
import re
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
TARGET = int(sys.argv[sys.argv.index("--triangles") + 1]) if "--triangles" in sys.argv else 15_000
WELD = "--weld" in sys.argv
VERSION = sys.argv[sys.argv.index("--version") + 1] if "--version" in sys.argv else ("v2" if WELD else "v1")
if not re.fullmatch(r"v[1-9][0-9]{0,3}", VERSION):
    raise ValueError("Version must be v1..v9999 without path separators")
if not 1000 <= TARGET <= 100000:
    raise ValueError("Evaluation triangle target must be 1000..100000")
LOD = f"lod{TARGET // 1000}k"
REPORT = {}


def bounds(obj):
    points = [obj.matrix_world @ Vector(p) for p in obj.bound_box]
    return ([min(p[i] for p in points) for i in range(3)],
            [max(p[i] for p in points) for i in range(3)])


def components(mesh):
    parents = list(range(len(mesh.vertices)))

    def find(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    for edge in mesh.edges:
        a, b = map(find, edge.vertices)
        if a != b:
            parents[b] = a
    groups = {}
    for vert in mesh.vertices:
        groups.setdefault(find(vert.index), []).append(vert)
    summaries = []
    for group in groups.values():
        summaries.append({
            "vertices": len(group),
            "min": [min(v.co[i] for v in group) for i in range(3)],
            "max": [max(v.co[i] for v in group) for i in range(3)],
        })
    return sorted(summaries, key=lambda item: item["vertices"], reverse=True)


def area(name, location, energy, size):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.shape, data.size = energy, "DISK", size
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((0, 0, .5)) - obj.location).to_track_quat("-Z", "Y").to_euler()


for slug in ("lula", "flavio"):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    source = ROOT / "assets" / "models" / slug / f"{slug}_base_v1.glb"
    output = ROOT / "assets" / "models" / slug / f"derived-{VERSION}"
    if not output.resolve().is_relative_to((ROOT / "assets/models" / slug).resolve()):
        raise ValueError("Derived output escaped character folder")
    output.mkdir(parents=True, exist_ok=True)
    target_file = output / f"{slug}_{LOD}_{VERSION}.glb"
    if target_file.exists():
        raise RuntimeError(f"Refusing to overwrite {target_file}")
    bpy.ops.import_scene.gltf(filepath=str(source))
    original = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    original.name = f"{slug}_original"
    low = original.copy()
    low.data = original.data.copy()
    bpy.context.collection.objects.link(low)
    low.name = f"{slug}_{LOD}"
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    if WELD:
        weld = low.modifiers.new("JoinCoincidentSeams", "WELD")
        weld.merge_threshold = 0.000005
        bpy.ops.object.modifier_apply(modifier=weld.name)
    modifier = low.modifiers.new("Simplify", "DECIMATE")
    modifier.ratio = TARGET / len(low.data.polygons)
    modifier.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    low.data.calc_loop_triangles()
    triangles = len(low.data.loop_triangles)
    if triangles > TARGET + 10:
        raise RuntimeError(f"Unexpected triangle count: {triangles}")
    REPORT[slug] = {
        "source": str(source.relative_to(ROOT)),
        "output": str(target_file.relative_to(ROOT)),
        "source_triangles": len(original.data.polygons),
        "output_triangles": triangles,
        "source_bounds": bounds(original),
        "output_bounds": bounds(low),
        "uv_layers": len(low.data.uv_layers),
        "components": components(low.data),
        "texture_sizes": [list(i.size) for i in bpy.data.images if i.type == "IMAGE"],
        "rigged": False,
        "method": "Blender collapse decimation; not deformation-ready retopology",
        "weld_threshold": 0.000005 if WELD else None,
    }
    bpy.ops.export_scene.gltf(filepath=str(target_file), export_format="GLB", use_selection=True)
    REPORT[slug]["output_bytes"] = target_file.stat().st_size
    # Comparison cameras use the same materials/light for original (left) and LOD (right).
    original.location.x -= .56
    low.location.x += .56
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 1400, 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world = bpy.data.worlds.new("NeutralStudio")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (.19, .19, .19, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = .7
    area("Key", (-2, -3, 3), 180, 3)
    area("Fill", (2, -2, 1.5), 100, 3)
    area("Back", (0, 3, 2), 150, 3)
    camera_data = bpy.data.cameras.new("Comparison")
    camera = bpy.data.objects.new("Comparison", camera_data)
    bpy.context.collection.objects.link(camera)
    camera_data.type, camera_data.ortho_scale = "ORTHO", 2.3
    scene.camera = camera
    for view, y in (("frente", -4), ("verso", 4)):
        camera.location = (0, y, .52)
        camera.rotation_euler = (Vector((0, 0, .49)) - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(output / f"comparacao-{view}.png")
        bpy.ops.render.render(write_still=True)
    print("LOD_PREPARED " + json.dumps({"character": slug, "triangles": triangles,
          "components": len(REPORT[slug]["components"]),
          "bytes": REPORT[slug]["output_bytes"]}), flush=True)

(ROOT / "docs" / f"MODELOS_{LOD.upper()}_{VERSION}.json").write_text(json.dumps(REPORT, indent=2), encoding="utf-8")
print("LOD_PREPARATION_PASSED", flush=True)
