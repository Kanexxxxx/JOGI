"""Add a cloth-only primitive and its pinned-shoulder mask to derived GLBs.

Run with local Blender. No API calls. Original files and their embedded image,
position, normal, UV, joint, weight and animation buffers remain byte-for-byte.
Only cape faces receive duplicated, identical attributes plus COLOR_0 motion mask.
"""
import hashlib
import json
import struct
import tempfile
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / 'game/assets/characters/cape-motion-v1'
DEST.mkdir(parents=True, exist_ok=True)


def prepare(name):
    source = ROOT / f'game/assets/characters/api-cape-v13/{name}_run.glb'
    raw = source.read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    data = json.loads(raw[20:20 + size])
    binary = bytearray(raw[28 + size:28 + size + data['buffers'][0]['byteLength']])
    original_binary = bytes(binary)
    widths = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
    types = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}

    def read(index):
        item = data['accessors'][index]
        view = data['bufferViews'][item['bufferView']]
        dtype = np.dtype(types[item['componentType']])
        width = widths[item['type']]
        return np.ndarray((item['count'], width), dtype=dtype, buffer=original_binary,
            offset=view.get('byteOffset', 0) + item.get('byteOffset', 0),
            strides=(view.get('byteStride', dtype.itemsize * width), dtype.itemsize)).copy()

    def append(array, template=None, color=False):
        while len(binary) % 4:
            binary.append(0)
        offset = len(binary)
        payload = np.ascontiguousarray(array).tobytes()
        binary.extend(payload)
        view = len(data['bufferViews'])
        data['bufferViews'].append({'buffer': 0, 'byteOffset': offset, 'byteLength': len(payload)})
        if color:
            item = {'componentType': 5121, 'normalized': True, 'type': 'VEC4', 'count': len(array)}
        elif template is None:
            item = {'componentType': 5125, 'type': 'SCALAR', 'count': int(array.size)}
        else:
            item = {k: v for k, v in data['accessors'][template].items()
                    if k not in ('bufferView', 'byteOffset', 'min', 'max', 'sparse')}
            item['count'] = len(array)
            if item['type'] == 'VEC3':
                item['min'], item['max'] = array.min(axis=0).tolist(), array.max(axis=0).tolist()
        item['bufferView'] = view
        index = len(data['accessors'])
        data['accessors'].append(item)
        return index

    primitives = data['meshes'][0]['primitives']
    if name == 'lula':
        primitive = primitives[0]
        attributes = primitive['attributes']
        coordinates = read(attributes['POSITION'])
        uv = read(attributes['TEXCOORD_0'])
        image = data['images'][data['textures'][data['materials'][0]['pbrMetallicRoughness']['baseColorTexture']['index']]['source']]
        view = data['bufferViews'][image['bufferView']]
        with tempfile.TemporaryDirectory(prefix='jogi-cape-mask-') as temp:
            path = Path(temp) / 'albedo.jpg'
            path.write_bytes(original_binary[view.get('byteOffset', 0):view.get('byteOffset', 0) + view['byteLength']])
            texture = bpy.data.images.load(str(path), check_existing=False)
            width, height = texture.size
            pixels = np.empty(len(texture.pixels), dtype=np.float32)
            texture.pixels.foreach_get(pixels)
            pixels = pixels.reshape((height, width, 4))
            u = np.clip((uv[:, 0] * width).astype(np.int32), 0, width - 1)
            v = np.clip(((1 - uv[:, 1]) * height).astype(np.int32), 0, height - 1)
            r, g, b = pixels[v, u, :3].T
            bpy.data.images.remove(texture)
        x, z, negative_back = coordinates.T
        y = -negative_back  # Same Blender Z-up semantic mask as fix_tripo_cape.py.
        red = (r > .025) & (r > g * 1.3) & (r > b * .8) & ((g - b) < (r - np.minimum(g, b)) * .35)
        white = (np.minimum(np.minimum(r, g), b) > .45) & (np.maximum(np.maximum(r, g), b) < np.minimum(np.minimum(r, g), b) * 1.35)
        region = (z > .17) & (z < .715) & (y > -.075) & (np.abs(x) < .15 + .43 * (.68 - z))
        mask = region & ((red & ((y > .015) | (z > .48) | (np.abs(x) > .20))) | (white & (y > .015)) | (y > .075))
        mask &= ~((z < .38) & (np.abs(x) < .14) & (y < .045))
        _, inverse = np.unique(np.round(coordinates, 6), axis=0, return_inverse=True)
        combined = np.zeros(inverse.max() + 1, dtype=bool)
        np.logical_or.at(combined, inverse, mask)
        mask = combined[inverse]
        triangles = read(primitive['indices']).reshape((-1, 3))
        cape_faces = mask[triangles].sum(axis=1) >= 2
        vertices, indices = np.unique(triangles[cape_faces], return_inverse=True)
        body = dict(primitive)
        body['indices'] = append(triangles[~cape_faces].astype(np.uint32).ravel())
        cape = dict(primitive)
        cape['attributes'] = {key: append(read(index)[vertices], index) for key, index in attributes.items()}
        cape['indices'] = append(indices.astype(np.uint32))
        primitives[:] = [body, cape]
        cape_positions = coordinates[vertices]
    else:
        assert len(primitives) == 2, 'Expected already isolated, approved Flavio cape'
        cape = primitives[1]
        cape_positions = read(cape['attributes']['POSITION'])
    # COLOR.r is a semantic free-cloth mask, unrelated to the original albedo.
    # All vertices at/above the shoulder transition remain strictly pinned.
    free_length = np.clip((.655 - cape_positions[:, 1]) / .435, 0, 1)
    color = np.zeros((len(cape_positions), 4), dtype=np.uint8)
    color[:, 0] = np.rint(free_length * 255).astype(np.uint8)
    color[:, 1] = np.rint(np.clip(cape_positions[:, 0] + .5, 0, 1) * 255).astype(np.uint8)
    color[:, 3] = 255
    cape['attributes']['COLOR_0'] = append(color, color=True)
    data['buffers'][0]['byteLength'] = len(binary)
    assert bytes(binary[:len(original_binary)]) == original_binary
    text = json.dumps(data, separators=(',', ':')).encode()
    text += b' ' * (-len(text) % 4)
    binary += b'\x00' * (-len(binary) % 4)
    output = struct.pack('<4sII', b'glTF', 2, 28 + len(text) + len(binary)) + struct.pack('<I4s', len(text), b'JSON') + text + struct.pack('<I4s', len(binary), b'BIN\x00') + binary
    destination = DEST / f'{name}_run.glb'
    if destination.exists():
        raise RuntimeError(f'Refusing to overwrite {destination}')
    destination.write_bytes(output)
    return {'character': name, 'source': str(source.relative_to(ROOT)), 'output': str(destination.relative_to(ROOT)),
        'source_sha256': hashlib.sha256(raw).hexdigest(), 'output_sha256': hashlib.sha256(output).hexdigest(),
        'original_binary_prefix_unchanged': True, 'cape_surface': 1, 'cape_vertices': len(cape_positions),
        'free_vertices': int(np.count_nonzero(color[:, 0])), 'shoulder_vertices_pinned': int(np.count_nonzero(color[:, 0] == 0)),
        'cape_bounds_min': cape_positions.min(axis=0).tolist(), 'cape_bounds_max': cape_positions.max(axis=0).tolist(),
        'total_triangles': sum(data['accessors'][p['indices']]['count'] // 3 for p in primitives)}


report = {'method': 'cape-only primitive; COLOR_0 red free-cloth mask, green rest-width phase; originals never overwritten',
          'characters': [prepare(name) for name in ('lula', 'flavio')]}
(DEST / 'manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print('CAPE_MOTION_ASSETS ' + json.dumps(report), flush=True)
