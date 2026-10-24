"""Reproject original appearance onto independent 15k / 2K evaluation copies.

Run with Blender --background --python tools/bake_character_textures.py.
Does not modify source exports or previous experiments. Not a rigging step.
"""
import json
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent


def light(name, pos, energy):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.shape, data.size = energy, "DISK", 3
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = pos
    obj.rotation_euler = (Vector((0, 0, .5)) - obj.location).to_track_quat("-Z", "Y").to_euler()


report = {}
for slug in ("lula", "flavio"):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    output = ROOT / "assets/models" / slug / "derived-v3"
    if output.exists():
        raise RuntimeError(f"Refusing to overwrite {output}")
    output.mkdir()
    bpy.ops.import_scene.gltf(filepath=str(ROOT / f"assets/models/{slug}/{slug}_base_v1.glb"))
    original = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    original.name = "SourceHigh"
    bpy.ops.import_scene.gltf(filepath=str(ROOT / f"assets/models/{slug}/derived-v2/{slug}_lod15k_v2.glb"))
    low = next(o for o in bpy.context.scene.objects if o.type == "MESH" and o != original)
    low.name = f"{slug}_lod15k_v3"
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.151917, island_margin=.004, margin_method="FRACTION")
    bpy.ops.object.mode_set(mode="OBJECT")
    material = bpy.data.materials.new(f"{slug}_baked2k")
    material.use_nodes = True
    low.data.materials.clear()
    low.data.materials.append(material)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes.get("Principled BSDF")
    shader.inputs["Metallic"].default_value = 0
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.render.threads_mode, scene.render.threads = "FIXED", 8
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.cage_extrusion = .003
    scene.render.bake.max_ray_distance = .02
    scene.render.bake.margin = 8
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.use_pass_color = True
    original.select_set(True)
    textures = {}
    for label, bake_type in (("basecolor", "DIFFUSE"), ("roughness", "ROUGHNESS"), ("normal", "NORMAL")):
        image = bpy.data.images.new(f"{slug}_{label}_2k", width=2048, height=2048, alpha=False)
        if label != "basecolor":
            image.colorspace_settings.name = "Non-Color"
        node = nodes.new("ShaderNodeTexImage")
        node.image = image
        nodes.active = node
        print(f"BAKE_START {slug} {label}", flush=True)
        bpy.ops.object.bake(type=bake_type)
        image.filepath_raw = str(output / f"{label}_2k.png")
        image.file_format = "PNG"
        image.save()
        textures[label] = node
    links.new(textures["basecolor"].outputs["Color"], shader.inputs["Base Color"])
    links.new(textures["roughness"].outputs["Color"], shader.inputs["Roughness"])
    normal = nodes.new("ShaderNodeNormalMap")
    links.new(textures["normal"].outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], shader.inputs["Normal"])
    original.select_set(False)
    target = output / f"{slug}_lod15k_2k_v3.glb"
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", use_selection=True)
    low.data.calc_loop_triangles()
    report[slug] = {"output": str(target.relative_to(ROOT)), "triangles": len(low.data.loop_triangles),
                    "bytes": target.stat().st_size, "textures": "2048x2048 rebaked", "rigged": False,
                    "status": "evaluation only; visual and deformation checks pending"}
    original.location.x -= .56
    low.location.x += .56
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 1400, 900
    scene.render.resolution_percentage = 100
    scene.world = bpy.data.worlds.new("Studio")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (.19, .19, .19, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = .7
    light("Key", (-2, -3, 3), 180)
    light("Fill", (2, -2, 1.5), 100)
    light("Back", (0, 3, 2), 150)
    data = bpy.data.cameras.new("Comparison")
    camera = bpy.data.objects.new("Comparison", data)
    bpy.context.collection.objects.link(camera)
    data.type, data.ortho_scale = "ORTHO", 2.3
    scene.camera = camera
    for view, y in (("frente", -4), ("verso", 4)):
        camera.location = (0, y, .52)
        camera.rotation_euler = (Vector((0, 0, .49)) - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(output / f"comparacao-{view}.png")
        bpy.ops.render.render(write_still=True)
    print("REBAKE_PREPARED " + json.dumps(report[slug]), flush=True)
(ROOT / "docs/MODELOS_REBAKE_v3.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print("REBAKE_COMPLETED", flush=True)
