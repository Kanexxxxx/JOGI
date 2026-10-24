"""Build an original, stylized Brasilia arena; no paid services or external textures.

Blender Z is up. Blender -Y becomes Godot +Z (the distant skyline).
Run: blender --background --python tools/build_brasilia_arena.py
The source and exported deliverables are additive and never overwrite assets.
"""
from __future__ import annotations

import json
import math
import random
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/environments/brasilia/arena-v1"
GAME = ROOT / "game/assets/environments/brasilia/arena_v1.glb"
BLEND = OUT / "brasilia_arena_v1.blend"
GLB = OUT / "brasilia_arena_v1.glb"
if any(p.exists() for p in (BLEND, GLB, GAME)):
    raise FileExistsError("Arena v1 already exists; create a new version instead of overwriting.")
OUT.mkdir(parents=True, exist_ok=True)
GAME.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
random.seed(20261023)


def material(name: str, color: tuple, roughness: float = 0.5, metallic: float = 0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = next(node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


M = {
    "ivory": material("Concreto marfim acetinado", (0.81, 0.80, 0.72), 0.42),
    "white": material("Ceramica branca", (0.93, 0.92, 0.85), 0.36),
    "shadow": material("Recuos azul petroleo", (0.026, 0.083, 0.11), 0.32),
    "gold": material("Detalhes ouro brasileiro", (0.94, 0.57, 0.075), 0.3, 0.38),
    "green": material("Verde arena", (0.045, 0.28, 0.14), 0.5),
    "water": material("Espelho dagua azul", (0.04, 0.39, 0.53), 0.19, 0.34),
    "sand": material("Pedra clara das pracas", (0.64, 0.60, 0.46), 0.8),
    "grass": material("Jardins do cerrado", (0.22, 0.37, 0.10), 0.9),
    "leaf": material("Copas verde cerrado", (0.13, 0.28, 0.085), 0.85),
    "leaf_light": material("Folhas iluminadas", (0.32, 0.44, 0.13), 0.85),
    "trunk": material("Tronco de ipe", (0.19, 0.12, 0.065), 0.9),
    "flower_yellow": material("Ipe amarelo", (1.0, 0.66, 0.075), 0.8),
    "flower_pink": material("Ipe rosa", (0.64, 0.18, 0.38), 0.8),
}


def finish(obj, name: str, mat, bevel: float = 0.0):
    obj.name = name
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("Arestas suaves", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod = obj.modifiers.new("Normais ponderadas", "WEIGHTED_NORMAL")
        mod.keep_sharp = True
    return obj


def box(name: str, loc, size, mat, bevel: float = 0.05):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, bevel)


def tube(name: str, points, radius: float, mat, resolution: int = 3):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 16
    curve.bevel_depth = radius
    curve.bevel_resolution = resolution
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, xyz in zip(spline.points, points):
        point.co = (*xyz, 1)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def cylinder(name: str, loc, radius: float, depth: float, mat, vertices: int = 24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    return finish(bpy.context.object, name, mat, 0.035)


def sphere(name: str, loc, scale, mat, subdivisions: int = 2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1, location=loc)
    obj = bpy.context.object
    obj.scale = scale
    finish(obj, name, mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def dish(name: str, center, radius: float, depth: float, up: bool):
    """A solid low profile rotational bowl, reinterpreting the Congress domes."""
    rings, segments = 12, 64
    vertices, faces = [], []
    for j in range(rings + 1):
        r = radius * j / rings
        height = depth * (r / radius) ** 2 if up else depth * (1 - (r / radius) ** 2)
        for i in range(segments):
            angle = math.tau * i / segments
            vertices.append((center[0] + r * math.cos(angle), center[1] + r * math.sin(angle), center[2] + height))
    for j in range(rings):
        for i in range(segments):
            a = j * segments + i
            b = j * segments + (i + 1) % segments
            faces.append((a, b, b + segments, a + segments))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(M["white"])
    for p in mesh.polygons:
        p.use_smooth = True
    solid = obj.modifiers.new("Espessura arquitetonica", "SOLIDIFY")
    solid.thickness = 0.22
    return obj


# Axis landmark: a readable skyline at broadcast scale, not a literal replica.
box("Plataforma monumental", (0, -67, 0.45), (40, 15, 0.9), M["ivory"], 0.16)
box("Lamina sombra da plataforma", (0, -66.7, 1.18), (37, 12, 0.52), M["shadow"], 0.1)
box("Cobertura suspensa", (0, -66.8, 1.72), (40, 14, 0.38), M["white"], 0.12)
for x in (-3.4, 3.4):
    box("Torre do horizonte", (x, -70, 14), (3.4, 4.1, 24), M["white"], 0.16)
    box("Vidro longitudinal da torre", (x, -67.91, 14), (1.35, 0.07, 22.3), M["shadow"], 0.025)
    for z in (4.1, 8.6, 13.1, 17.6, 22.1):
        box("Brise horizontal", (x, -67.82, z), (3.1, 0.16, 0.12), M["ivory"], 0.025)
box("Passarela alta entre torres", (0, -70, 22.9), (4, 2.2, 0.48), M["white"], 0.08)
dish("Cupula convexa", (-12, -65, 2.0), 6.2, 3.6, False)
dish("Taca concava", (12, -65, 2.0), 6.5, 4.0, True)
cylinder("Pedestal da taca", (12, -65, 1.7), 3.2, 1.0, M["ivory"])

# Cathedral crown set to the side: sculptural ribs and an aqua inner volume.
cylinder("Praca da catedral", (29, -48, 0.2), 10.0, 0.4, M["sand"], 64)
cylinder("Base escura da catedral", (29, -48, 0.58), 7.1, 0.4, M["shadow"], 64)
for i in range(12):
    angle = math.tau * i / 12
    points = []
    for j in range(25):
        t = j / 24
        r = 7.0 - 5.5 * math.sin(t * math.pi * 0.8)
        z = 0.7 + t * 12.8
        points.append((29 + r * math.cos(angle), -48 + r * math.sin(angle), z))
    tube("Costela da catedral", points, 0.25, M["white"])
cylinder("Luz azul da catedral", (29, -48, 3.3), 3.2, 5.0, M["water"], 48)

# Long reflecting pools frame, rather than occupy, the playable corridor.
for side in (-1, 1):
    x = side * 13.5
    box("Deck do espelho dagua", (x, -17, 0.12), (10.0, 38.0, 0.24), M["ivory"], 0.12)
    box("Agua serena", (x, -17, 0.265), (8.8, 36.8, 0.12), M["water"], 0.12)
    for y in (-0.4, -12.0, -23.6, -35.2):
        box("Passarela sobre agua", (x, y, 0.44), (10, 0.52, 0.28), M["white"], 0.05)
    box("Filete dourado lateral", (side * 8.4, -17, 0.32), (0.13, 38, 0.12), M["gold"], 0.025)
    # Three stepped seating terraces: no noisy crowd geometry.
    for row in range(4):
        sx = side * (24 + row * 1.15)
        box("Arquibancada concreto", (sx, -13, 0.6 + row * 0.65), (1.18, 29, 0.58 + row * 1.3), M["ivory"], 0.12)
        box("Assento continuo verde", (sx, -13, 0.96 + row * 1.3), (0.72, 28, 0.18), M["green"], 0.06)
    box("Faixa dourada arquibancada", (side * 28.1, -13, 5.65), (0.2, 29.5, 0.24), M["gold"], 0.05)
    # Canopies float above the stands on slim supports.
    box("Marquise da arena", (side * 26, -13, 7.6), (8.2, 31, 0.32), M["white"], 0.2)
    for y in (-25, -13, -1):
        cylinder("Pilar da marquise", (side * 29.2, y, 3.8), 0.18, 7.6, M["ivory"], 16)
    box("Jardim junto a agua", (side * 20.3, -16, 0.11), (2.4, 37, 0.22), M["grass"], 0.3)

# Two aerodynamic gateway ribs, high above the open central corridor.
for y, height in ((-31, 10.8), (-43, 9.3)):
    points = []
    for i in range(49):
        a = math.pi * i / 48
        points.append((8.2 * math.cos(a), y, 0.5 + height * math.sin(a)))
    tube("Arco branco da arena", points, 0.24, M["white"])
    tube("Linha ouro do arco", [(x, yy + 0.27, z) for x, yy, z in points], 0.075, M["gold"], 2)


def tree(x: float, y: float, size: float, blossom: str | None = None):
    cylinder("Tronco de ipe", (x, y, size * 1.6), size * 0.13, size * 3.2, M["trunk"], 10)
    for i in range(4):
        a = i * math.tau / 4 + 0.4
        end = (x + math.cos(a) * size * 0.9, y + math.sin(a) * size * 0.9, size * 3.7)
        tube("Galho de ipe", [(x, y, size * 2.2), end], size * 0.055, M["trunk"], 1)
        color = M[blossom] if blossom else M["leaf" if i % 2 else "leaf_light"]
        sphere("Copa florida" if blossom else "Copa cerrado", (end[0], end[1], size * 3.7), (size * 1.35, size * 1.12, size * 1.15), color)
    cylinder("Anel do canteiro", (x, y, 0.18), size * 1.5, 0.26, M["ivory"], 32)


for side in (-1, 1):
    for i, y in enumerate((6, -3, -14, -25, -37)):
        tree(side * (20.2 + (0.3 if i % 2 else -0.2)), y, 0.85 + random.random() * 0.16,
             "flower_yellow" if i % 3 != 1 else "flower_pink")
    for i in range(5):
        tree(side * (36 + random.random() * 4), -20 - i * 10, 1.2 + random.random() * 0.35)

# Deliberate horizon terraces and low landscape, leaving a generous clear center.
for side in (-1, 1):
    box("Patamar dos jardins", (side * 19, -48, 0.14), (13, 11, 0.28), M["sand"], 0.3)
    for x in (side * 18, side * 23):
        sphere("Massa vegetal baixa", (x, -44, 0.65), (2.0, 1.4, 0.9), M["leaf_light"])
    # Flag-shaped sculptural fins; no campaign marks in the neutral environment.
    for j in range(3):
        obj = box("Aleta brasileira", (side * (8.5 + j * 1.2), -52, 2.8 + j * 0.35), (0.17, 2.8, 5.6 + j * 0.7), M["gold"] if j == 1 else M["green"], 0.08)
        obj.rotation_euler[1] = side * -0.15

# Count evaluated production meshes before adding rendering-only staging.
depsgraph = bpy.context.evaluated_depsgraph_get()
objects = [o for o in bpy.context.scene.objects if o.type in {"MESH", "CURVE"}]
triangles = 0
for obj in objects:
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    mesh.calc_loop_triangles()
    triangles += len(mesh.loop_triangles)
    evaluated.to_mesh_clear()
bpy.ops.object.select_all(action="DESELECT")
for obj in objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
bpy.ops.export_scene.gltf(filepath=str(GLB), export_format="GLB", use_selection=True,
                          export_cameras=False, export_lights=False, export_yup=True,
                          export_apply=True)
GAME.write_bytes(GLB.read_bytes())

# Beauty staging is saved in the .blend, not exported into the game GLB.
box("RENDER_ONLY solo neutro", (0, -30, -0.24), (170, 180, 0.3), M["sand"], 0)
box("RENDER_ONLY corredor demonstrativo", (0, -24, -0.045), (15.8, 120, 0.12), M["shadow"], 0)
for x in (-4, 0, 4):
    box("RENDER_ONLY linha da pista", (x, -24, 0.025), (0.065, 118, 0.02), M["ivory"], 0)
world = bpy.data.worlds.new("Ceu azul Brasilia")
bpy.context.scene.world = world
world.use_nodes = True
background = next(node for node in world.node_tree.nodes if node.type == "BACKGROUND")
background.inputs["Color"].default_value = (0.32, 0.56, 0.82, 1)
background.inputs["Strength"].default_value = 0.6
bpy.ops.object.light_add(type="SUN", location=(0, 0, 40))
sun = bpy.context.object
sun.name = "RENDER_ONLY sol de Brasilia"
sun.rotation_euler = (math.radians(28), math.radians(-22), math.radians(-32))
sun.data.energy = 3.0
sun.data.angle = math.radians(8)
bpy.ops.object.light_add(type="AREA", location=(0, 0, 35))
bpy.context.object.data.energy = 1800
bpy.context.object.data.shape = "DISK"
bpy.context.object.data.size = 45
bpy.ops.object.camera_add(location=(54, 39, 35))
camera = bpy.context.object
camera.name = "RENDER_ONLY camera de composicao"
bpy.context.scene.camera = camera
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.view_settings.view_transform = "AgX"
scene.render.image_settings.file_format = "PNG"


def render(name: str, position, target, lens: float, width: int, height: int):
    camera.location = position
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = lens
    camera.data.clip_end = 350
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.filepath = str(OUT / name)
    bpy.ops.render.render(write_still=True)


render("arena-perspectiva.png", (63, 40, 39), (0, -29, 3.0), 43, 1500, 1100)
render("arena-eixo-vertical.png", (0, 20, 9), (0, -37, 7), 31, 1000, 1600)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
report = {
    "name": "Brasilia estilizada - Arena v1",
    "source": str(BLEND), "glb": str(GLB), "game_copy": str(GAME),
    "triangles_evaluated": triangles, "objects": len(objects), "materials": len(M),
    "glb_bytes": GLB.stat().st_size, "external_textures": 0,
    "coordinate_contract": "Blender -Y = Godot +Z; Blender Z = Godot Y; corridor x[-4,4] clear",
    "render_only": "Beauty renders include a demonstrative road and ground; GLB excludes these, lights and camera.",
    "limitations": "Static stylized architecture; no collision, LODs, crowds, production FPS measurement or animation.",
}
(OUT / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print("ARENA_BUILT " + json.dumps(report, ensure_ascii=False), flush=True)
