"""Pin candidate cape weights and fix constant horizontal animation origin.

No geometry, normals, UV or image bytes change. Existing animation changes only
by its constant horizontal Hips offset; vertical and relative motion survive.
Buffers are patched directly without re-export. No API calls.
"""
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
CHARACTER = sys.argv[sys.argv.index('--character') + 1] if '--character' in sys.argv else 'lula'
if CHARACTER not in ('lula', 'flavio'):
    raise ValueError('Unknown character')
SOURCE = next((ROOT / f'assets/models/{CHARACTER}/tripo-original-run').glob('**/model.glb'))
VERSION = sys.argv[sys.argv.index('--version') + 1] if '--version' in sys.argv else ('v13' if CHARACTER == 'lula' else 'v1')
if not VERSION.startswith('v') or not VERSION[1:].isdigit():
    raise ValueError('Version must be v followed by digits')
DEST = ROOT / f'assets/models/{CHARACTER}/tripo-cape-fixed-{VERSION}/model.glb'
EVIDENCE = ROOT / 'docs/evidencias/personagens'
if DEST.exists():
    raise RuntimeError('Refusing to overwrite existing fixed GLB')
raw = bytearray(SOURCE.read_bytes())
json_size = struct.unpack_from('<I', raw, 12)[0]
data = json.loads(raw[20:20 + json_size])
bin_start = 28 + json_size
types = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
widths = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def accessor(index):
    item = data['accessors'][index]
    view = data['bufferViews'][item['bufferView']]
    dtype = np.dtype(types[item['componentType']])
    width = widths[item['type']]
    return np.ndarray((item['count'], width), dtype=dtype, buffer=raw,
        offset=bin_start + view.get('byteOffset', 0) + item.get('byteOffset', 0),
        strides=(view.get('byteStride', dtype.itemsize * width), dtype.itemsize))


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
mesh = next(o for o in bpy.context.scene.objects if o.type == 'MESH' and len(o.data.vertices) > 1000)
primitive = data['meshes'][0]['primitives'][0]
attrs = primitive['attributes']
count = data['accessors'][attrs['POSITION']]['count']
assert count == len(mesh.data.vertices)
coordinates = np.empty(count * 3, dtype=np.float32)
mesh.data.vertices.foreach_get('co', coordinates)
coordinates = coordinates.reshape((-1, 3))
uv = accessor(attrs['TEXCOORD_0'])
shader = next(n for n in mesh.data.materials[0].node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
image = shader.inputs['Base Color'].links[0].from_node.image
pixels = np.empty(len(image.pixels), dtype=np.float32)
image.pixels.foreach_get(pixels)
width, height = image.size
pixels = pixels.reshape((height, width, 4))
u = np.clip((uv[:, 0] * width).astype(np.int32), 0, width - 1)
v = np.clip(((1 - uv[:, 1]) * height).astype(np.int32), 0, height - 1)
color = pixels[v, u, :3]
x, y, z = coordinates.T
r, g, b = color.T
red = (r > .025) & (r > g * 1.3) & (r > b * .8) & ((g - b) < (r - np.minimum(g, b)) * .35)
white = (np.minimum(np.minimum(r, g), b) > .45) & (np.maximum(np.maximum(r, g), b) < np.minimum(np.minimum(r, g), b) * 1.35)
# The cape lies behind the torso. Its white star must follow the red cloth.
# Front sash (negative Y), skin, sleeves and trousers are excluded.
region = (z > .17) & (z < .715) & (y > -.075) & (np.abs(x) < .15 + .43 * (.68 - z))
mask = region & ((red & ((y > .015) | (z > .48) | (np.abs(x) > .20))) | (white & (y > .015)) | (y > .075))
if CHARACTER == 'flavio':
    green = (g > .035) & (g > r * 1.12) & (g > b * 1.12)
    mask = region & ((green & ((y > -.015) | (z > .48) | (np.abs(x) > .15))) | (y > .075) | ((y > .015) & (z < .58)))
leg_ceiling = .42 if CHARACTER == 'flavio' else .38
mask &= ~((z < leg_ceiling) & (np.abs(x) < .14) & (y < .045))
# Synchronize coincident UV-seam duplicates without welding any geometry.
_, first, inverse = np.unique(np.round(coordinates, 6), axis=0, return_index=True, return_inverse=True)
group_mask = np.zeros(inverse.max() + 1, dtype=bool)
np.logical_or.at(group_mask, inverse, mask)
mask = group_mask[inverse]
joint_names = [data['nodes'][node].get('name') for node in data['skins'][0]['joints']]
chest_index = joint_names.index('mixamorig:Spine2')
joints = accessor(attrs['JOINTS_0'])
weights = accessor(attrs['WEIGHTS_0'])
assert weights.dtype == np.float32, 'Inspect normalized integer weights before patching'
before_joints, before_weights = joints.copy(), weights.copy()
selected = np.flatnonzero(mask)
canonical = first[inverse[selected]]
blend = np.clip((.715 - z[canonical]) / .065, 0, 1)
mixed_joints = np.column_stack((before_joints[canonical], np.full(len(selected), chest_index)))
mixed_weights = np.column_stack((before_weights[canonical] * (1 - blend[:, None]), np.zeros(len(selected))))
has_chest = (mixed_joints[:, :4] == chest_index).any(axis=1)
chest_slot = np.where(has_chest, (mixed_joints[:, :4] == chest_index).argmax(axis=1), 4)
mixed_weights[np.arange(len(selected)), chest_slot] += blend
top = np.argsort(-mixed_weights, axis=1)[:, :4]
weights[mask] = np.take_along_axis(mixed_weights, top, axis=1)
weights[mask] /= weights[mask].sum(axis=1)[:, None]
joints[mask] = np.take_along_axis(mixed_joints, top, axis=1)
assert np.array_equal(joints[~mask], before_joints[~mask])
assert np.array_equal(weights[~mask], before_weights[~mask])
# Prove changes are confined to selected JOINTS_0/WEIGHTS_0 buffer bytes.
allowed = np.zeros(len(raw), dtype=bool)
for name in ('JOINTS_0', 'WEIGHTS_0'):
    item = data['accessors'][attrs[name]]
    view = data['bufferViews'][item['bufferView']]
    dtype = np.dtype(types[item['componentType']])
    offset = bin_start + view.get('byteOffset', 0) + item.get('byteOffset', 0)
    stride = view.get('byteStride', dtype.itemsize * widths[item['type']])
    for byte in range(dtype.itemsize * widths[item['type']]):
        allowed[offset + np.flatnonzero(mask) * stride + byte] = True
# Fix constant horizontal origin drift in the API's in-place clip. glTF is Y-up.
origin_fixes = []
for animation in data.get('animations', []):
    for channel in animation['channels']:
        target = channel['target']
        node = data['nodes'][target['node']]
        if target['path'] != 'translation' or node.get('name') != 'mixamorig:Hips':
            continue
        output_index = animation['samplers'][channel['sampler']]['output']
        samples = accessor(output_index)
        rest = np.array(node.get('translation', [0, 0, 0]))
        offset_xz = samples[0, [0, 2]].copy() - rest[[0, 2]]
        samples[:, 0] -= offset_xz[0]
        samples[:, 2] -= offset_xz[1]
        item = data['accessors'][output_index]
        view = data['bufferViews'][item['bufferView']]
        start = bin_start + view.get('byteOffset', 0) + item.get('byteOffset', 0)
        stride = view.get('byteStride', 12)
        for axis in (0, 2):
            for byte in range(4):
                allowed[start + np.arange(item['count']) * stride + axis * 4 + byte] = True
        origin_fixes.append({'bone': node['name'], 'subtracted_gltf_xz': offset_xz.tolist(),
                              'vertical_track_unchanged': True})
source_bytes = np.frombuffer(SOURCE.read_bytes(), dtype=np.uint8)
changed = np.frombuffer(raw, dtype=np.uint8) != source_bytes
assert not np.any(changed & ~allowed)
split_faces = '--split-faces' in sys.argv
split_stats = None
if split_faces:
    # Give the cape its own skin attributes at shared boundaries. Triangles and
    # their POSITION/NORMAL/UV values remain exactly those of the API export.
    triangles = accessor(primitive['indices']).reshape((-1, 3)).copy()
    cape_faces = mask[triangles].sum(axis=1) >= 2
    cape_vertices, cape_indices = np.unique(triangles[cape_faces], return_inverse=True)
    canonical = first[inverse[cape_vertices]]
    blend = np.clip((.65 - z[canonical]) / .06, 0, 1)
    cj = np.column_stack((before_joints[canonical], np.full(len(cape_vertices), chest_index)))
    cw = np.column_stack((before_weights[canonical] * (1 - blend[:, None]), np.zeros(len(cape_vertices))))
    found = (cj[:, :4] == chest_index).any(axis=1)
    slot = np.where(found, (cj[:, :4] == chest_index).argmax(axis=1), 4)
    cw[np.arange(len(cape_vertices)), slot] += blend
    order = np.argsort(-cw, axis=1)[:, :4]
    cape_weights = np.take_along_axis(cw, order, axis=1)
    cape_weights /= cape_weights.sum(axis=1)[:, None]
    cape_joints = np.take_along_axis(cj, order, axis=1).astype(joints.dtype)
    # All body vertices recover their original API weights.
    joints[:] = before_joints
    weights[:] = before_weights
    cape_attributes = {name: accessor(index)[cape_vertices].copy() for name, index in attrs.items()}
    cape_attributes['JOINTS_0'] = cape_joints
    cape_attributes['WEIGHTS_0'] = cape_weights.astype(np.float32)
    binary = bytearray(raw[bin_start:bin_start + data['buffers'][0]['byteLength']])

    def append_attribute(array, template=None, element_type=None):
        while len(binary) % 4:
            binary.append(0)
        offset = len(binary)
        array = np.ascontiguousarray(array)
        payload = array.tobytes()
        binary.extend(payload)
        view_index = len(data['bufferViews'])
        data['bufferViews'].append({'buffer': 0, 'byteOffset': offset, 'byteLength': len(payload)})
        if template is None:
            item = {'componentType': 5125, 'type': 'SCALAR', 'count': int(array.size)}
        else:
            item = {k: v for k, v in data['accessors'][template].items()
                    if k not in ('bufferView', 'byteOffset', 'min', 'max', 'sparse')}
            item['count'] = len(array)
            if item['type'] == 'VEC3' and template == attrs['POSITION']:
                item['min'], item['max'] = array.min(axis=0).tolist(), array.max(axis=0).tolist()
        item['bufferView'] = view_index
        index = len(data['accessors'])
        data['accessors'].append(item)
        return index

    body = dict(primitive)
    body['indices'] = append_attribute(triangles[~cape_faces].astype(np.uint32).ravel())
    cape = dict(primitive)
    cape['attributes'] = {name: append_attribute(array, attrs[name]) for name, array in cape_attributes.items()}
    cape['indices'] = append_attribute(cape_indices.astype(np.uint32))
    data['meshes'][0]['primitives'] = [body, cape]
    data['buffers'][0]['byteLength'] = len(binary)
    text = json.dumps(data, separators=(',', ':')).encode('utf-8')
    text += b' ' * (-len(text) % 4)
    binary += b'\x00' * (-len(binary) % 4)
    raw = bytearray(struct.pack('<4sII', b'glTF', 2, 28 + len(text) + len(binary)) +
        struct.pack('<I4s', len(text), b'JSON') + text +
        struct.pack('<I4s', len(binary), b'BIN\x00') + binary)
    split_stats = {'cape_triangles': int(cape_faces.sum()), 'body_triangles': int((~cape_faces).sum()),
                   'total_triangles_unchanged': int(len(triangles)), 'cape_vertex_copies': int(len(cape_vertices)),
                   'body_weights_restored_to_api': True, 'face_assignment': 'majority of semantic cape vertices',
                   'position_normal_uv_values_copied_without_arithmetic': True}
DEST.parent.mkdir(parents=True)
DEST.write_bytes(raw)
report = {'source': str(SOURCE.relative_to(ROOT)), 'output': str(DEST.relative_to(ROOT)),
    'cape_vertices': int(mask.sum()), 'all_vertices': count, 'chest_bone': joint_names[chest_index],
    'modified_bytes': int(changed.sum()), 'only_selected_skin_and_hips_xz_bytes_changed': True,
    'geometry_normals_uv_images_bytes_untouched': True,
    'animation_unchanged_except_horizontal_hips_origin': origin_fixes,
    'selected_rest_bounds': {'min': coordinates[mask].min(axis=0).tolist(), 'max': coordinates[mask].max(axis=0).tolist()},
    'source_sha256': hashlib.sha256(source_bytes).hexdigest(), 'output_sha256': hashlib.sha256(raw).hexdigest(),
    'method': 'rigid chest pin below z .65; collar blend .65-.715; approximate semantic mask; no cloth simulation'}
if split_faces:
    report['split_faces'] = split_stats
    report['geometry_normals_uv_images_bytes_untouched'] = 'Original buffers preserved; cape primitive duplicates original attribute values'
    report['only_selected_skin_and_hips_xz_bytes_changed'] = False
    report['modified_bytes'] = None
    report['method'] = 'split cape/body skin boundaries; chest pin below .59, collar follows original API above .65'
print('CAPE_PATCH ' + json.dumps(report), flush=True)

# Re-import the actual patched file, render motion in two opposite phases.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(DEST))
scene = bpy.context.scene
meshes = [o for o in scene.objects if o.type == 'MESH' and len(o.data.vertices) > 1000]
rig = next(o for o in scene.objects if o.type == 'ARMATURE')
for track in rig.animation_data.nla_tracks:
    track.mute = True
action = next(iter(bpy.data.actions))
rig.animation_data.action = action
rig.animation_data.action_slot = next(s for s in action.slots if s.target_id_type == 'OBJECT')
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x, scene.render.resolution_y = 600, 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.world = bpy.data.worlds.new('QA')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.14, .14, .14, 1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = .6
lights = []
for name, pos, energy in [('Key', (-2, -3, 3), 700), ('Fill', (2, -2, 1.5), 400), ('Back', (0, 3, 2), 500)]:
    light = bpy.data.lights.new(name, 'AREA')
    light.energy, light.shape, light.size = energy, 'DISK', 3
    obj = bpy.data.objects.new(name, light)
    scene.collection.objects.link(obj)
    lights.append((obj, Vector(pos)))
camera_data = bpy.data.cameras.new('QA')
camera_data.type = 'ORTHO'
camera = bpy.data.objects.new('QA', camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
report['renders'] = []
if split_faces:
    coordinates = np.empty(len(meshes[0].data.vertices) * 3, dtype=np.float32)
    meshes[0].data.vertices.foreach_get('co', coordinates)
    coordinates = coordinates.reshape((-1, 3))
edges = np.empty(len(meshes[0].data.edges) * 2, dtype=np.int32)
meshes[0].data.edges.foreach_get('vertices', edges)
edges = edges.reshape((-1, 2))
rest_lengths = np.linalg.norm(coordinates[edges[:, 0]] - coordinates[edges[:, 1]], axis=1)
report['boundary_diagnostics'] = []
for index, seconds in enumerate([.2, .8333333333333333]):
    frame = seconds * scene.render.fps
    scene.frame_set(int(frame), subframe=frame - int(frame))
    bpy.context.view_layer.update()
    evaluated = meshes[0].evaluated_get(bpy.context.evaluated_depsgraph_get())
    posed = evaluated.to_mesh()
    co = np.empty(len(posed.vertices) * 3, dtype=np.float32)
    posed.vertices.foreach_get('co', co)
    matrix = np.array(evaluated.matrix_world)
    co = co.reshape((-1, 3)) @ matrix[:3, :3].T + matrix[:3, 3]
    low, high = Vector(co.min(axis=0)), Vector(co.max(axis=0))
    posed_lengths = np.linalg.norm(co[edges[:, 0]] - co[edges[:, 1]], axis=1)
    bad = np.flatnonzero((posed_lengths > .015) & (posed_lengths > rest_lengths * 5))
    worst = bad[np.argsort(-posed_lengths[bad])[:30]]
    report['boundary_diagnostics'].append({'seconds': seconds, 'edges': [
        {'rest_length': float(rest_lengths[i]), 'posed_length': float(posed_lengths[i]),
         'endpoints': [{'index': int(j), 'rest': coordinates[j].tolist(),
                        'color': color[j].tolist() if not split_faces else None,
                        'selected': bool(mask[j]) if not split_faces else None} for j in edges[i]]} for i in worst]})
    evaluated.to_mesh_clear()
    center, height = (low + high) / 2, high.z - low.z
    camera_data.ortho_scale = height * 1.35
    for obj, pos in lights:
        obj.location = center + pos * height
        obj.rotation_euler = (center - obj.location).to_track_quat('-Z', 'Y').to_euler()
    for view, direction in [('frente', (0, -4, .15)), ('perfil', (4, 0, .15)), ('verso', (0, 4, .15))]:
        camera.location = center + Vector(direction) * height
        camera.rotation_euler = (center - camera.location).to_track_quat('-Z', 'Y').to_euler()
        path = EVIDENCE / f'tripo-{CHARACTER}-cape-fixed-{VERSION}-{view}-pose{index + 1}.png'
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        report['renders'].append(str(path.relative_to(ROOT)))
(EVIDENCE / f'tripo-{CHARACTER}-cape-fixed-{VERSION}.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print('CAPE_FIXED_QA_COMPLETE', flush=True)
