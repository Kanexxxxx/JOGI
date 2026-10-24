"""Palácio do Planalto estilizado, modelado localmente a partir de fotos oficiais.

Blender: --background --python tools/build_planalto_palace.py -- --version v1
Contrato GLB/Godot: frente -X, altura Y, largura Z; origem no centro do chão.
Cada versão é aditiva. Nenhuma imagem de referência é usada como textura.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--version", default="v1")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
if not re.fullmatch(r"v[1-9][0-9]{0,2}", args.version):
    raise ValueError("Version must be v1..v999")
OUT = ROOT / "assets/environments/planalto" / args.version
GLB = OUT / ("planalto_" + args.version + ".glb")
BLEND = OUT / ("planalto_" + args.version + ".blend")
GAME = ROOT / "game/assets/environments/planalto" / GLB.name
if any(path.exists() for path in (GLB, BLEND, GAME)):
    raise FileExistsError("Deliverable exists. Use a new version; approved assets are preserved.")
OUT.mkdir(parents=True, exist_ok=True)
GAME.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)


def g(position):
    """Godot conceptual XYZ to Blender XYZ; GLTF Y-up export reverses this."""
    return (position[0], -position[2], position[1])


def material(name, color, roughness=.5, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    principled = mat.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (*color, 1)
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = metallic
    return mat


M = {
    "marble": material("Marmore branco quente", (.91, .925, .90), .32),
    "underside": material("Concreto claro sob a marquise", (.74, .79, .78), .55),
    "stone": material("Pedra do embasamento", (.62, .67, .63), .66),
    "frame": material("Perfis aluminio champagne", (.42, .52, .56), .26, .60),
    "glass": material("Vidro azul principal", (.055, .22, .32), .17, .48),
    "glass_sky": material("Vidro azul ceu refletido", (.10, .35, .47), .20, .42),
    "glass_shadow": material("Vidro azul profundo", (.028, .115, .17), .22, .42),
    "glass_warm": material("Reflexo suave dos ambientes", (.26, .36, .33), .28, .35),
    "water": material("Espelho dagua turquesa", (.025, .35, .46), .10, .55),
    "dark": material("Sombra dos pilotis", (.025, .052, .065), .65),
    "green": material("Gramado do jardim", (.07, .29, .095), .9),
    "flowers": material("Flores brasileiras discretas", (.65, .065, .16), .8),
}
PRODUCTION = []


def finish(obj, name, mat, bevel=0.0, segments=2):
    obj.name = name
    obj.data.materials.append(mat)
    if bevel:
        modifier = obj.modifiers.new("Arestas arquitetonicas suaves", "BEVEL")
        modifier.width = bevel
        modifier.segments = segments
        modifier.limit_method = "ANGLE"
        modifier.angle_limit = .20
        modifier = obj.modifiers.new("Normais ponderadas", "WEIGHTED_NORMAL")
        modifier.keep_sharp = True
    PRODUCTION.append(obj)
    return obj


def box(name, position, dimensions, mat, bevel=.025, segments=2):
    bpy.ops.mesh.primitive_cube_add(size=1, location=g(position))
    obj = bpy.context.object
    obj.scale = (dimensions[0], dimensions[2], dimensions[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, bevel, segments)


def mesh_object(name, vertices, faces, mat, bevel=0.0, smooth=False, segments=2):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([g(vertex) for vertex in vertices], [], faces)
    mesh.update()
    # Closed architectural volumes need outward normals on BOTH ramp sides.
    # The original ramp top was wound downward and disappeared with backface
    # culling. Recalculate consistently before beveling/export, never hide it
    # by turning the whole palace double sided.
    topology = bmesh.new()
    topology.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(topology, faces=list(topology.faces))
    topology.to_mesh(mesh)
    topology.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    finish(obj, name, mat, bevel, segments)
    if smooth:
        for polygon in mesh.polygons:
            polygon.use_smooth = True
    return obj


def cubic(a, b, c, d, count):
    points = []
    for index in range(count):
        t = index / count
        u = 1 - t
        points.append((u**3*a[0] + 3*u*u*t*b[0] + 3*u*t*t*c[0] + t**3*d[0],
                       u**3*a[1] + 3*u*u*t*b[1] + 3*u*t*t*c[1] + t**3*d[1]))
    return points


def sculptural_column(z, front=True, serial=0):
    # Silhueta em lâmina: ponta fina no chão/teto e duas curvas que se abrem
    # para a laje intermediária. As colunas ficam separadas da caixa de vidro.
    # Vista em perfil X/Y, como nas fotografias da Fundação Oscar Niemeyer.
    profile = [(-5.02, .17), (-5.02, 7.91), (-4.84, 7.91)]
    profile += cubic((-4.84, 7.91), (-4.74, 4.12), (-4.39, 2.98), (-.42, 2.70), 56)
    profile += cubic((-.42, 2.70), (.10, 2.68), (.72, 2.67), (1.20, 2.67), 12)
    profile += [(1.20, 2.49)]
    profile += cubic((1.20, 2.49), (-1.65, 2.50), (-3.38, 1.45), (-5.02, .17), 56)
    profile = [point for index, point in enumerate(profile) if index == 0 or point != profile[index-1]]
    n = len(profile)
    vertices = []
    for side in (-1, 1):
        for x, y in profile:
            # A lâmina é fina frontalmente e ganha espessura junto à laje.
            thickness = .14 + .045 * math.exp(-((y - 2.6) / 1.9)**2)
            xx = x if front else -x
            vertices.append((xx, y, z + side * thickness))
    faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2*n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, j+n, i+n))
    return mesh_object(("ColunaCurvaFrontal" if front else "ColunaCurvaPosterior") + f"_{serial:02d}", vertices, faces, M["marble"], .012, segments=1)


def rounded_pool(name, center_z):
    box(name + "Borda", (-10.5, .10, center_z), (7.8, .20, 13.4), M["marble"], .16, 3)
    # Malha ondulada milimétrica; não usa transparência nem textura de fotografia.
    vertices, faces = [], []
    nx, nz = 64, 24
    for ix in range(nx + 1):
        for iz in range(nz + 1):
            x = -14.12 + 7.24 * ix / nx
            z = center_z - 6.40 + 12.80 * iz / nz
            wave = .004 * math.sin(ix * .54 + iz * .3) + .002 * math.sin(ix * .2 - iz * .72)
            vertices.append((x, .213 + wave, z))
    for ix in range(nx):
        for iz in range(nz):
            a = ix*(nz+1) + iz
            faces.append((a, a+nz+1, a+nz+2, a+1))
    mesh_object(name + "Agua", vertices, faces, M["water"], smooth=True)
    # Filete junto ao bordo, facilita leitura em plano distante.
    box(name + "InteriorEscuro", (-10.5, .14, center_z), (7.35, .10, 12.95), M["dark"], .13)


# Volumetria horizontal: caixa de vidro recuada e cobertura em balanço fina.
box("EmbasamentoPrincipal", (0, .09, 0), (11.5, .18, 39.4), M["stone"], .10, 3)
box("LajeIntermediaria", (.10, 2.48, 0), (10.4, .27, 38.0), M["marble"], .055, 3)
box("FrisoSombraLaje", (.10, 2.33, 0), (10.1, .045, 37.7), M["underside"], .015)
box("CoberturaEmBalanco", (0, 8.02, 0), (10.5, .30, 38.4), M["marble"], .055, 3)
box("ForroBrancoRecuado", (0, 7.84, 0), (10.10, .08, 38.0), M["underside"], .02)
box("CaixaInteriorRecuada", (.45, 5.09, 0), (6.10, 5.06, 34.3), M["glass_shadow"], .015)

# Nove lâminas em cada frente longa, repetindo a linguagem estrutural do palácio.
for index in range(9):
    z = -17.6 + 4.4 * index
    sculptural_column(z, True, index + 1)
    sculptural_column(z, False, index + 1)

# Pilotis visíveis sob o volume principal, preservando o vazio horizontal.
for x in (-1.8, 2.4):
    for z in (-13.2, -8.8, -4.4, 0, 4.4, 8.8, 13.2):
        box("PilarPilotis", (x, 1.30, z), (.20, 2.25, .22), M["underside"], .025)

# Panos de vidro: três faixas de pavimento, perfis verticais e travessas finas.
glass_palette = [M["glass"], M["glass_sky"], M["glass"], M["glass_shadow"], M["glass_sky"]]
pane_count = 48
pane_width = 34.0 / pane_count
for side in (-1, 1):
    x = -2.64 if side < 0 else 3.54
    for index in range(pane_count):
        z = -17.0 + (index + .5) * pane_width
        for floor in range(3):
            y = 3.35 + floor * 1.52
            mat = M["glass_warm"] if floor == 2 and index % 11 in (3, 4) else glass_palette[(index + floor*2) % len(glass_palette)]
            box("PainelVidroFrontal" if side < 0 else "PainelVidroPosterior", (x, y, z), (.055, 1.43, pane_width - .035), mat, 0)
        box("MontanteVertical", (x + side*.045, 5.11, z - pane_width*.5), (.075, 4.95, .035), M["frame"], 0)
    for y in (2.60, 4.13, 5.65, 7.18, 7.66):
        box("TravessaHorizontal", (x + side*.045, y, 0), (.085, .055, 34.05), M["frame"], .006, 1)
    for y in (4.22, 5.74):
        box("FaixaDosPavimentos", (x + side*.035, y, 0), (.09, .12, 34.03), M["underside"], .01)

# As fachadas laterais continuam a trama do vidro; não terminam em caixote opaco.
for side in (-1, 1):
    z = side * 17.22
    for ix in range(9):
        x = -2.60 + (ix + .5) * (6.10 / 9)
        for floor in range(3):
            box("VidroLateral", (x, 3.35 + floor*1.52, z), (6.10/9 - .035, 1.43, .045), glass_palette[(ix+floor) % 5], 0)
        box("MontanteLateral", (x - 6.10/18, 5.11, z + side*.035), (.035, 4.95, .07), M["frame"], 0)
    for y in (2.60, 4.13, 5.65, 7.18, 7.66):
        box("TravessaLateral", (.45, y, z + side*.035), (6.15, .055, .075), M["frame"], .006, 1)

# Rampa cívica entre duas colunas: centro ligeiramente deslocado para manter o vão.
ramp_z = -2.2
steps = 64
vertices, faces = [], []
for i in range(steps + 1):
    t = i / steps
    x = -15.1 + t * 11.55
    y = .22 + 2.38 * (t*t*(3-2*t))
    for z_offset, y_offset in ((-1.60, 0), (1.60, 0), (-1.60, -.16), (1.60, -.16)):
        vertices.append((x, y + y_offset, ramp_z + z_offset))
for i in range(steps):
    a, b = i*4, (i+1)*4
    faces += [(a, b, b+1, a+1), (a+2, a+3, b+3, b+2), (a, a+2, b+2, b), (a+1, b+1, b+3, a+3)]
faces += [(0,1,3,2), (steps*4,steps*4+2,steps*4+3,steps*4+1)]
mesh_object("RampaDeAcessoCurva", vertices, faces, M["marble"], .018)
for side in (-1, 1):
    vertices, faces = [], []
    for i in range(steps + 1):
        t = i / steps
        x = -15.1 + t * 11.55
        y = .22 + 2.38 * (t*t*(3-2*t))
        z = ramp_z + side*1.61
        vertices += [(x,y,z-.035),(x,y,z+.035),(x,y+.27,z-.035),(x,y+.27,z+.035)]
    for i in range(steps):
        a,b = i*4,(i+1)*4
        faces += [(a,b,b+1,a+1),(a+2,a+3,b+3,b+2),(a,a+2,b+2,b),(a+1,b+1,b+3,a+3)]
    faces += [(0,1,3,2),(steps*4,steps*4+2,steps*4+3,steps*4+1)]
    mesh_object("GuardaCorpoRampa", vertices, faces, M["marble"], .012)

# Continuous landing: the previous last ramp segment stopped .91 m before
# the recessed glass facade, creating the apparent missing access section.
box("PatamarContinuoRampa", (-3.04, 2.53, ramp_z), (1.16, .16, 3.2), M["marble"], .025)

# The user's arena includes a second visible ceremonial access opposite the
# ramp. This stair is set decoration, not a claim that the real building has
# two identical civic ramps. The original curved ramp remains asymmetric.
stair_z, stair_width, stair_count = 2.2, 2.4, 14
for index in range(stair_count):
    fraction = (index + 1) / stair_count
    height = .22 + 2.38 * fraction
    run = 11.55 / stair_count
    box("EscadariaCenograficaDireita_%02d" % index,
        (-15.1 + (index + .5)*run, height*.5, stair_z),
        (run + .008, height, stair_width), M["marble"], .018, 1)
box("PatamarContinuoEscadaria", (-3.04, 2.53, stair_z), (1.16, .16, stair_width), M["marble"], .025)

# Parlatório lateral pequeno, destacado da entrada principal como nas referências.
box("ParlatorioPlataforma", (-5.9, 2.52, 10.0), (2.6, .24, 4.0), M["marble"], .07, 3)
box("ParlatorioPeitoril", (-7.10, 2.93, 10.0), (.12, .72, 3.8), M["marble"], .06, 3)
box("ParlatorioParedeLateralA", (-5.9, 2.93, 8.1), (2.4, .72, .12), M["marble"], .06, 3)
box("ParlatorioParedeLateralB", (-5.9, 2.93, 11.9), (2.4, .72, .12), M["marble"], .06, 3)

# Espelhos d'água partidos pela passarela frontal; jardim e flores em escala discreta.
rounded_pool("EspelhoEsquerdo", -11.2)
rounded_pool("EspelhoDireito", 10.2)
box("PassarelaFrontal", (-15.55, .07, 0), (.85, .14, 38.0), M["stone"], .10)
for side in (-1, 1):
    box("JardimLongitudinal", (-5.62, .12, side*11.4), (.70, .14, 12.4), M["green"], .09)
    for index in range(28):
        box("FlorDoJardim", (-5.65 + .13*math.sin(index*1.7), .22, side*11.4 - 5.6 + index*.42), (.18, .12, .21), M["flowers"], .04, 1)

# Materializar modificadores e transforms antes de exportar ou medir.
bpy.context.view_layer.update()
depsgraph = bpy.context.evaluated_depsgraph_get()
baked = []
for obj in list(PRODUCTION):
    evaluated = obj.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
    mesh.transform(obj.matrix_world)
    replacement = bpy.data.objects.new(obj.name + "_Baked", mesh)
    bpy.context.collection.objects.link(replacement)
    replacement.matrix_world = Matrix.Identity(4)
    baked.append(replacement)
    bpy.data.objects.remove(obj, do_unlink=True)
bpy.context.view_layer.update()

# Agrupar objetos por material para poucos draw calls sem alterar a geometria.
merged = []
groups = {mat.name: [] for mat in M.values()}
for obj in baked:
    if obj.data.materials:
        groups[obj.data.materials[0].name].append(obj)
for mat in M.values():
    group = groups[mat.name]
    if not group:
        continue
    bpy.ops.object.select_all(action="DESELECT")
    for obj in group:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = group[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = "Planalto_" + mat.name.replace(" ", "_")
    merged.append(obj)

triangles = 0
points = []
for obj in merged:
    obj.data.calc_loop_triangles()
    triangles += len(obj.data.loop_triangles)
    points.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
minimum = [min(point[axis] for point in points) for axis in range(3)]
maximum = [max(point[axis] for point in points) for axis in range(3)]
godot_min = [minimum[0], minimum[2], -maximum[1]]
godot_max = [maximum[0], maximum[2], -minimum[1]]
assert 36 < godot_max[2] - godot_min[2] < 41, (godot_min, godot_max)
assert abs(godot_min[1]) < .001 and 7.8 < godot_max[1] < 8.5, (godot_min, godot_max)
assert triangles <= 55000, triangles
bpy.ops.object.select_all(action="DESELECT")
for obj in merged:
    obj.select_set(True)
bpy.context.view_layer.objects.active = merged[0]
bpy.ops.export_scene.gltf(filepath=str(GLB), export_format="GLB", use_selection=True, export_yup=True,
                          export_apply=True, export_cameras=False, export_lights=False)
GAME.write_bytes(GLB.read_bytes())

# Estúdio de apresentação, excluído do GLB por ser criado depois da exportação.
PRODUCTION.clear()
floor = box("RENDER_ONLY_Solo", (-3,-.14,0), (110,.20,100), M["green"], 0)
world = bpy.data.worlds.new("CeuAzulBrasilia")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (.28, .48, .75, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = .55
scene = bpy.context.scene
scene.world = world
sun_data = bpy.data.lights.new("RENDER_ONLY_Sol", "SUN")
sun_data.energy = 2.5
sun_data.angle = math.radians(8)
sun = bpy.data.objects.new(sun_data.name, sun_data)
scene.collection.objects.link(sun)
sun.rotation_euler = (math.radians(35), math.radians(-15), math.radians(-45))
area_data = bpy.data.lights.new("RENDER_ONLY_Preenchimento", "AREA")
area_data.energy = 1900
area_data.shape = "DISK"
area_data.size = 35
area = bpy.data.objects.new(area_data.name, area_data)
scene.collection.objects.link(area)
area.location = g((-18,18,0))
area.rotation_euler = (Vector(g((0,3,0))) - area.location).to_track_quat("-Z", "Y").to_euler()
camera_data = bpy.data.cameras.new("RENDER_ONLY_Camera")
camera = bpy.data.objects.new(camera_data.name, camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.lens = 48
camera_data.clip_end = 250
scene.render.engine = "BLENDER_EEVEE"
scene.eevee.taa_render_samples = 64
scene.render.resolution_x = 1600
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "AgX"


def render(name, position, target, lens):
    camera.location = g(position)
    camera.rotation_euler = (Vector(g(target)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = lens
    scene.render.filepath = str(OUT / name)
    bpy.ops.render.render(write_still=True)


render("planalto-perspectiva.png", (-42,16,38), (-2,2.4,0), 47)
render("planalto-frente.png", (-60,8.5,0), (-1,3.0,0), 45)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
report = {
    "name": "Palacio do Planalto estilizado",
    "version": args.version,
    "source": str(BLEND.relative_to(ROOT)), "glb": str(GLB.relative_to(ROOT)), "game_copy": str(GAME.relative_to(ROOT)),
    "triangles": triangles, "meshes": len(merged), "surfaces": len(merged), "materials": len(merged),
    "bounds_godot_min": godot_min, "bounds_godot_max": godot_max,
    "dimensions_godot_xyz": [godot_max[i] - godot_min[i] for i in range(3)],
    "building_body_xyz": [10.5,8.17,38.4], "front_direction": "-X", "up_axis": "Y", "width_axis": "Z",
    "origin": "center of building at ground level; ramp and reflecting pools extend toward -X",
    "front_columns": 9, "rear_columns": 9,
    "glb_bytes": GLB.stat().st_size, "sha256": hashlib.sha256(GLB.read_bytes()).hexdigest(),
    "external_textures": 0,
    "sources": [
        "https://www.gov.br/casacivil/pt-br/assuntos/centrais-de-conteudo/imagens/destaques-area-de-imprensa/fotos-do-palacio-do-planalto",
        "https://www.oscarniemeyer.org.br/obra/pro081/"
    ],
    "modeling_notes": "Stylized architectural reconstruction from official photographs, not a measured survey. Outward closed-volume normals correct the disappearing ramp. Continuous landings join the civic ramp and a user-requested opposite scenic stair to the facade. The opposite stair is arena scenery, not a measured feature of the real palace.",
    "render_only": "Preview grass floor, lights and camera are saved in .blend but excluded from game GLB.",
    "limitations": "Static architectural set; no collision, automatic reflection probes, LOD or production FPS claim. Water is opaque reflective PBR, without runtime waves.",
}
(OUT / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print("PLANALTO_BUILT " + json.dumps(report, ensure_ascii=False), flush=True)
