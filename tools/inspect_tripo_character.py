"""Inspect immutable Tripo Lula source/rig/run; write only QA JSON and renders."""
import hashlib
import json
import struct
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'docs/evidencias/personagens'
CHARACTER = sys.argv[sys.argv.index('--character') + 1] if '--character' in sys.argv else 'lula'
if CHARACTER not in ('lula', 'flavio'):
    raise ValueError('Unknown character')
PATHS = {'source': ROOT / f'assets/models/{CHARACTER}/{CHARACTER}_base_v1.glb'}
for step in ('rig', 'run'):
    found = list((ROOT / f'assets/models/{CHARACTER}/tripo-original-{step}').glob('**/model.glb'))
    if found:
        PATHS[step] = found[0]
ACTIVE = 'run' if 'run' in PATHS else 'rig'
PREFIX = f'tripo-{CHARACTER}' if ACTIVE == 'run' else f'tripo-{CHARACTER}-rig'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def inspect(path):
    raw = path.read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    data = json.loads(raw[20:20 + size])
    binary = raw[28 + size:]
    views = data.get('bufferViews', [])

    def view_bytes(index):
        view = views[index]
        start = view.get('byteOffset', 0)
        return binary[start:start + view['byteLength']]

    def accessor_bytes(index):
        accessor = data['accessors'][index]
        view = views[accessor['bufferView']]
        component = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}[accessor['componentType']]
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[accessor['type']] * component
        stride = view.get('byteStride', width)
        content = view_bytes(accessor['bufferView'])
        offset = accessor.get('byteOffset', 0)
        return b''.join(content[offset + i * stride:offset + i * stride + width] for i in range(accessor['count']))

    attrs = []
    tris = 0
    for mesh in data.get('meshes', []):
        for primitive in mesh['primitives']:
            attrs.append({name: {'count': data['accessors'][index]['count'], 'sha256': digest(accessor_bytes(index))}
                          for name, index in primitive['attributes'].items() if name in ('POSITION', 'NORMAL', 'TEXCOORD_0')})
            tris += data['accessors'][primitive['indices']]['count'] // 3
    durations = []
    for animation in data.get('animations', []):
        for sampler in animation['samplers']:
            accessor = data['accessors'][sampler['input']]
            durations.extend(accessor.get('max', []))
    return {'path': str(path.relative_to(ROOT)), 'file_sha256': digest(raw), 'triangles': tris,
            'attributes': attrs, 'joint_count': sum(len(s['joints']) for s in data.get('skins', [])),
            'images': [{'mime': im.get('mimeType'), 'bytes': len(view_bytes(im['bufferView'])),
                        'sha256': digest(view_bytes(im['bufferView']))} for im in data.get('images', [])],
            'animations': [a.get('name') for a in data.get('animations', [])],
            'duration_seconds': max(durations) if durations else 0}


report = {name: inspect(path) for name, path in PATHS.items()}
report['comparison'] = {}
for name in ('rig', 'run'):
    if name not in report:
        continue
    report['comparison'][name] = {
        'images_byte_identical': sorted(i['sha256'] for i in report['source']['images']) == sorted(i['sha256'] for i in report[name]['images']),
        'position_raw_identical': [a['POSITION'] for a in report['source']['attributes']] == [a['POSITION'] for a in report[name]['attributes']],
        'uv_raw_identical': [a.get('TEXCOORD_0') for a in report['source']['attributes']] == [a.get('TEXCOORD_0') for a in report[name]['attributes']],
    }

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(PATHS[ACTIVE]))
scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x, scene.render.resolution_y = 600, 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.world = bpy.data.worlds.new('NeutralQA')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.14, .14, .14, 1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = .6
rigs = [o for o in scene.objects if o.type == 'ARMATURE']
meshes = [o for o in scene.objects if o.type == 'MESH' and len(o.data.vertices) > 1000]
points = [o.matrix_world @ Vector(corner) for o in meshes for corner in o.bound_box]
low = Vector([min(p[i] for p in points) for i in range(3)])
high = Vector([max(p[i] for p in points) for i in range(3)])
center = (low + high) / 2
height = high.z - low.z
animation_fps = scene.render.fps
for rig in rigs:
    rig.animation_data_create()
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    if bpy.data.actions:
        action = next(iter(bpy.data.actions))
        rig.animation_data.action = action
        rig.animation_data.action_slot = next(s for s in action.slots if s.target_id_type == 'OBJECT')
report['blender'] = {'bounds_min': list(low), 'bounds_max': list(high),
                     'actions': [{'name': a.name, 'frame_range': list(a.frame_range)} for a in bpy.data.actions],
                     'images': [{'name': i.name, 'size': list(i.size)} for i in bpy.data.images if i.type == 'IMAGE']}
report['blender']['meshes'] = [{'name': o.name, 'vertices': len(o.data.vertices),
                                'matrix_world': [list(row) for row in o.matrix_world]} for o in meshes]
report['blender']['skeletons'] = [{'name': r.name, 'matrix_world': [list(row) for row in r.matrix_world],
    'bones': [{'name': b.name, 'parent': b.parent.name if b.parent else None,
               'head_local': list(b.head_local), 'tail_local': list(b.tail_local),
               'head_world': list(r.matrix_world @ b.head_local)} for b in r.data.bones]} for r in rigs]
lights = []
for name, pos, energy in [('Key', (-2, -3, 3), 700), ('Fill', (2, -2, 1.5), 400), ('Back', (0, 3, 2), 500)]:
    light = bpy.data.lights.new(name, 'AREA')
    light.energy, light.shape, light.size = energy, 'DISK', 3
    obj = bpy.data.objects.new(name, light)
    scene.collection.objects.link(obj)
    obj.location = center + Vector(pos) * height
    obj.rotation_euler = (center - obj.location).to_track_quat('-Z', 'Y').to_euler()
    lights.append((obj, Vector(pos)))
camera_data = bpy.data.cameras.new('QA')
camera = bpy.data.objects.new('QA', camera_data)
scene.collection.objects.link(camera)
camera_data.type, camera_data.ortho_scale = 'ORTHO', height * 1.45
scene.camera = camera
samples = [.2, .2 + report[ACTIVE]['duration_seconds'] / 2] if ACTIVE == 'run' else [0]
report['renders'] = []
for pose_index, seconds in enumerate(samples):
    frame = seconds * animation_fps
    scene.frame_set(int(frame), subframe=frame - int(frame))
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    points = []
    for obj in meshes:
        evaluated = obj.evaluated_get(depsgraph)
        posed = evaluated.to_mesh()
        coordinates = np.empty(len(posed.vertices) * 3, dtype=np.float32)
        posed.vertices.foreach_get('co', coordinates)
        coordinates = coordinates.reshape((-1, 3))
        matrix = np.array(evaluated.matrix_world)
        world = coordinates @ matrix[:3, :3].T + matrix[:3, 3]
        points.extend([Vector(world.min(axis=0)), Vector(world.max(axis=0))])
        evaluated.to_mesh_clear()
    low = Vector([min(p[i] for p in points) for i in range(3)])
    high = Vector([max(p[i] for p in points) for i in range(3)])
    center, height = (low + high) / 2, high.z - low.z
    report.setdefault('posed_bounds', []).append({'seconds': seconds, 'min': list(low), 'max': list(high)})
    camera_data.ortho_scale = max(height * 1.35, (high.x - low.x) * 1.7)
    for obj, pos in lights:
        obj.location = center + pos * height
        obj.rotation_euler = (center - obj.location).to_track_quat('-Z', 'Y').to_euler()
    for view, direction in [('frente', (0, -4, .15)), ('perfil', (4, 0, .15)), ('verso', (0, 4, .15))]:
        camera.location = center + Vector(direction) * height
        camera.rotation_euler = (center - camera.location).to_track_quat('-Z', 'Y').to_euler()
        path = OUT / f'{PREFIX}-{view}-pose{pose_index + 1}.png'
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        report['renders'].append({'path': str(path.relative_to(ROOT)), 'seconds': seconds})
OUT.mkdir(parents=True, exist_ok=True)
(OUT / f'{PREFIX}-inspection.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print('TRIPO_CHARACTER_QA ' + json.dumps({'comparison': report['comparison'], 'duration': report[ACTIVE]['duration_seconds']}), flush=True)
