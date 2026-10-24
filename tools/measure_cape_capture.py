"""Compare GPU screenshots using Blender's bundled image reader/numpy."""
import json
import argparse
import sys
from pathlib import Path
import bpy
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument('--prefix', default='capas-mesma-pose-')
parser.add_argument('--report', default='capas-movimento-gpu.json')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
folder = Path(__file__).resolve().parent.parent / 'docs/evidencias/estadio'
frames = []
for index in range(3):
    image = bpy.data.images.load(str(folder / f'{args.prefix}{index}.png'), check_existing=False)
    pixels = np.empty(len(image.pixels), dtype=np.float32)
    image.pixels.foreach_get(pixels)
    frames.append(pixels.reshape((image.size[1], image.size[0], 4)))
    bpy.data.images.remove(image)
motion = np.any(np.abs(frames[0][:, :, :3] - frames[1][:, :, :3]) > 1 / 255, axis=2)
pause = np.any(np.abs(frames[1][:, :, :3] - frames[2][:, :, :3]) > 1 / 255, axis=2)
rows, columns = np.nonzero(motion)
report = {'capture': 'identical skeleton and camera; only explicit cloth phase differs',
    'resolution': list(frames[0].shape[:2]), 'phase_changed_pixels': int(motion.sum()),
    'pause_changed_pixels': int(pause.sum()),
    'head_region_changed_pixels': int(motion[-430:, :].sum()),
    'phase_bbox_pixels_top_left': [int(columns.min()), int(frames[0].shape[0] - 1 - rows.max()),
                                  int(columns.max()), int(frames[0].shape[0] - 1 - rows.min())],
    'pause_exact_rgba_match': bool(np.array_equal(frames[1], frames[2]))}
assert report['phase_changed_pixels'] > 1000
assert report['pause_exact_rgba_match']
assert report['head_region_changed_pixels'] == 0
(folder / args.report).write_text(json.dumps(report, indent=2), encoding='utf-8')
print('CAPE_GPU_COMPARISON ' + json.dumps(report), flush=True)
