"""Normalize and simplify only a new stadium asset, preserving the API original."""
import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

root = Path(__file__).resolve().parents[1]
source = root / "assets/environments/stadium/tripo-grandstand-v1/model.glb"
out = root / "assets/environments/stadium/derived-grandstand-v2"
target = out / "grandstand_100k.glb"
if target.exists():
    raise FileExistsError(target)
out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(source))
bpy.context.view_layer.update()
objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
points = [obj.matrix_world @ Vector(point) for obj in objects for point in obj.bound_box]
minimum = Vector(tuple(min(p[i] for p in points) for i in range(3)))
maximum = Vector(tuple(max(p[i] for p in points) for i in range(3)))
report = {"source": str(source.relative_to(root)), "bounds_blender": [list(minimum), list(maximum)], "source_triangles": 0}
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 512
scene.render.resolution_y = 384
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = True
world = bpy.data.worlds.new("PreviewWorld")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (.25, .25, .25, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = .7
scene.world = world
center = (minimum + maximum) * .5
for index, location in enumerate(((2, -1, 2), (-2, -1, 2))):
    data = bpy.data.lights.new(f"Key{index}", "AREA")
    data.energy = 180
    data.shape = "DISK"
    data.size = 3
    lamp = bpy.data.objects.new(data.name, data)
    scene.collection.objects.link(lamp)
    lamp.location = location
    lamp.rotation_euler = (center - lamp.location).to_track_quat("-Z", "Y").to_euler()
camera_data = bpy.data.cameras.new("Camera")
camera = bpy.data.objects.new("Camera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.type = "ORTHO"
camera_data.ortho_scale = 1.22
for sign in (1, -1):
    camera.location = center + Vector((sign * 3, .0, .65))
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(out / ("source-plus-x.png" if sign == 1 else "source-minus-x.png"))
    bpy.ops.render.render(write_still=True)
for obj in objects:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    obj.data.calc_loop_triangles()
    report["source_triangles"] += len(obj.data.loop_triangles)
    # Front is evaluated by the two reference renders; original axis +X is
    # rotated into Blender -Y (Godot +Z), module width becomes X.
    # Preserve the importer's Y-up conversion before rotating into the stage.
    baked = Matrix.Rotation(-math.pi * .5, 4, "Z") @ obj.matrix_world.copy()
    obj.data.transform(baked)
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)
    obj.data.update()
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=.00001)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.data.calc_loop_triangles()
    decimate = obj.modifiers.new("StadiumLOD100k", "DECIMATE")
    decimate.ratio = min(1.0, 100000 / max(1, len(obj.data.loop_triangles)))
    decimate.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    obj.select_set(False)
points = [vertex.co.copy() for obj in objects for vertex in obj.data.vertices]
low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
factor = 8.0 / (high.x - low.x)
base_center = Vector(((low.x + high.x) * .5, (low.y + high.y) * .5, low.z))
for obj in objects:
    obj.data.transform(Matrix.Scale(factor, 4) @ Matrix.Translation(-base_center))
    obj.data.update()
    obj.select_set(True)
bpy.context.view_layer.update()
dimensions = (high - low) * factor
report["dimensions_godot_xyz"] = [dimensions.x, dimensions.z, dimensions.y]
assert 2.0 < dimensions.z < 5.0, report
assert 2.0 < dimensions.y < 4.0, report
bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
report["output"] = str(target.relative_to(root))
report["width_meters"] = 8.0
report["triangles"] = sum(len(obj.data.polygons) for obj in objects)
(out / "manifest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print("STADIUM_DERIVED", json.dumps(report))
