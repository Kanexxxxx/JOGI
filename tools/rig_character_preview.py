"""Local evaluation rig and reusable clips; originals never modified.

Spatial skin weights are a first pass, not artist-approved deformation topology.
"""
import json
import math
import re
import sys
import struct
from array import array
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector

ROOT = Path(__file__).resolve().parent.parent
VERSION = sys.argv[sys.argv.index("--version") + 1] if "--version" in sys.argv else "v1"
if not re.fullmatch(r"v[1-9][0-9]{0,3}", VERSION):
    raise ValueError("Version must be v1..v9999 without path separators")


def distance(point, start, end):
    axis = end - start
    t = max(0, min(1, (point - start).dot(axis) / axis.length_squared))
    return (point - start - t * axis).length


report = {}
for slug in ("lula", "flavio"):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    output = ROOT / f"assets/models/{slug}/rig-preview-{VERSION}"
    if not output.resolve().is_relative_to((ROOT / "assets/models" / slug).resolve()):
        raise ValueError("Rig output escaped character folder")
    if output.exists():
        raise RuntimeError(f"Refusing to overwrite {output}")
    output.mkdir()
    bpy.ops.import_scene.gltf(filepath=str(ROOT / f"assets/models/{slug}/derived-v4/{slug}_lod60k_v4.glb"))
    mesh = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # glTF splits vertices at UV seams. Reconnect coincident points before
    # smoothing skin weights so both sides of a seam deform identically.
    weld = mesh.modifiers.new("ReconnectImportedUVSeams", "WELD")
    weld.merge_threshold = .000005
    bpy.ops.object.modifier_apply(modifier=weld.name)
    mesh.name = f"{slug}_body"
    # Texture copies only; the original 4K images/exports remain untouched.
    for image in bpy.data.images:
        if image.type == "IMAGE" and image.size[0] > 2048:
            image.scale(2048, 2048)
            image.pack()
    definitions = {
        "hips": ((0, 0, .36), (0, 0, .46), None),
        "spine": ((0, 0, .46), (0, 0, .59), "hips"),
        "chest": ((0, 0, .59), (0, 0, .67), "spine"),
        "neck": ((0, 0, .67), (0, 0, .72), "chest"),
        "head": ((0, 0, .72), (0, 0, .94), "neck"),
        "cape_top": ((0, .07, .65), (0, .10, .44), "chest"),
        "cape_tip": ((0, .10, .44), (0, .13, .23), "cape_top"),
    }
    for side, sign in (("L", 1), ("R", -1)):
        elbow_z, wrist_z, hand_z = (.61, .58, .565) if slug == "lula" else (.65, .65, .65)
        definitions.update({
            f"upper_arm_{side}": ((sign * .13, 0, .65), (sign * .28, 0, elbow_z), "chest"),
            f"forearm_{side}": ((sign * .28, 0, elbow_z), (sign * .41, -.005, wrist_z), f"upper_arm_{side}"),
            f"hand_{side}": ((sign * .41, -.005, wrist_z), (sign * .47, -.015, hand_z), f"forearm_{side}"),
            f"thigh_{side}": ((sign * .085, 0, .37), (sign * .085, 0, .21), "hips"),
            f"shin_{side}": ((sign * .085, 0, .21), (sign * .085, 0, .065), f"thigh_{side}"),
            f"foot_{side}": ((sign * .085, 0, .065), (sign * .085, -.10, .035), f"shin_{side}"),
        })
    data = bpy.data.armatures.new(f"{slug}_skeleton")
    rig = bpy.data.objects.new("CharacterRig", data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (start, end, parent) in definitions.items():
        bone = data.edit_bones.new(name)
        bone.head, bone.tail = start, end
        if parent:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    groups = {name: mesh.vertex_groups.new(name=name) for name in definitions}
    segments = {name: (Vector(start), Vector(end)) for name, (start, end, _) in definitions.items()}
    # Color + depth distinguish cape flanks from sleeves at the same height.
    material = mesh.data.materials[0]
    shader = next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    base_image = shader.inputs["Base Color"].links[0].from_node.image
    pixels = array("f", [0.0]) * len(base_image.pixels)
    base_image.pixels.foreach_get(pixels)
    width, height = base_image.size
    vertex_uv = {}
    uv_data = mesh.data.uv_layers.active.data
    for loop in mesh.data.loops:
        vertex_uv.setdefault(loop.vertex_index, tuple(uv_data[loop.index].uv))

    def cape_vertex(vertex):
        x, y, z = vertex.co
        if not (.17 < z < .71) or abs(x) > .15 + .43 * (.68 - z):
            return False
        u, v = vertex_uv[vertex.index]
        offset = (min(height - 1, max(0, int(v * height))) * width + min(width - 1, max(0, int(u * width)))) * 4
        r, g, b = pixels[offset:offset + 3]
        signature = (g < r * .35 and b < r * .35) if slug == "lula" else (g > r * 1.15 and g > b * 1.1)
        return (signature and y > -.025) or (y > .065 and .17 < z < .65)

    counts = {"head": 0, "cape": 0, "limbs_body": 0}
    for vertex in mesh.data.vertices:
        x, y, z = vertex.co
        side = "L" if x >= 0 else "R"
        if z >= .72:
            candidates = ["head"]
            counts["head"] += 1
        elif cape_vertex(vertex):
            candidates = ["cape_top", "cape_tip"]
            counts["cape"] += 1
        elif abs(x) > .155 and z > .48:
            candidates = [f"upper_arm_{side}", f"forearm_{side}", f"hand_{side}"]
            counts["limbs_body"] += 1
        elif z < .36:
            candidates = [f"thigh_{side}", f"shin_{side}", f"foot_{side}"]
            if z > .28:
                candidates.append("hips")
                if abs(x) < .05:
                    candidates += ["thigh_R" if side == "L" else "thigh_L"]
            counts["limbs_body"] += 1
        else:
            candidates = ["hips", "spine", "chest", "neck", "head"]
            if z < .41:
                candidates += [f"thigh_{side}"]
            if z > .59 and abs(x) > .10:
                candidates += [f"upper_arm_{side}"]
            counts["limbs_body"] += 1
        weights = sorted(((1 / (.006 + distance(vertex.co, *segments[n])) ** 4, n)
                          for n in candidates), reverse=True)[:4]
        total = sum(w for w, _ in weights)
        for weight, name in weights:
            groups[name].add([vertex.index], weight / total, "REPLACE")
    # Smooth anatomical region transitions over connected surface neighbors.
    # This fixes abrupt shoulder/crotch boundaries without changing source geometry.
    neighbors = [[] for _ in mesh.data.vertices]
    for edge in mesh.data.edges:
        a, b = edge.vertices
        neighbors[a].append(b)
        neighbors[b].append(a)
    skin = [{g.group: g.weight for g in vertex.groups} for vertex in mesh.data.vertices]
    for iteration in range(8):
        updated = []
        for index, weights in enumerate(skin):
            adjacent = neighbors[index]
            if not adjacent or mesh.data.vertices[index].co.z > .75:
                updated.append(weights)
                continue
            mixed = {bone: weight * .5 for bone, weight in weights.items()}
            for neighbor in adjacent:
                for bone, weight in skin[neighbor].items():
                    mixed[bone] = mixed.get(bone, 0) + weight * .5 / len(adjacent)
            best = sorted(mixed.items(), key=lambda item: item[1], reverse=True)[:4]
            total = sum(weight for _, weight in best)
            updated.append({bone: weight / total for bone, weight in best})
        skin = updated
    indices = list(range(len(mesh.data.vertices)))
    for group in mesh.vertex_groups:
        group.remove(indices)
    for index, weights in enumerate(skin):
        for bone, weight in weights.items():
            mesh.vertex_groups[bone].add([index], weight, "REPLACE")
    modifier = mesh.modifiers.new("PreviewSkin", "ARMATURE")
    modifier.object = rig
    mesh.parent = rig
    scene = bpy.context.scene
    scene.render.fps = 30
    for bone in rig.pose.bones:
        bone.rotation_mode = "QUATERNION"

    def rotate(name, axis, angle):
        bone = rig.pose.bones[name]
        basis = bone.bone.matrix_local.to_quaternion()
        bone.rotation_quaternion = basis.inverted() @ Quaternion(axis, angle) @ basis

    def pose(clip, phase):
        for bone in rig.pose.bones:
            bone.rotation_quaternion = Quaternion()
            bone.location = (0, 0, 0)
        running = clip in ("corrida", "turbo")
        amp = .62 if clip == "corrida" else .88
        for side, sign in (("L", 1), ("R", -1)):
            down = sign * math.radians(72)
            swing = sign * math.sin(phase) * (.48 if running else .025)
            bone = rig.pose.bones[f"upper_arm_{side}"]
            basis = bone.bone.matrix_local.to_quaternion()
            bone.rotation_quaternion = basis.inverted() @ (Quaternion((1, 0, 0), swing) @ Quaternion((0, 1, 0), down)) @ basis
            rotate(f"forearm_{side}", (0, 0, 1), sign * -.65)
            if running:
                rotate(f"thigh_{side}", (1, 0, 0), -sign * math.sin(phase) * amp)
                rotate(f"shin_{side}", (1, 0, 0), max(0, sign * math.sin(phase)) * 1.05)
                rotate(f"foot_{side}", (1, 0, 0), -.12)
        rotate("cape_top", (1, 0, 0), -.08 + math.sin(phase) * .035)
        rotate("cape_tip", (1, 0, 0), math.sin(phase - .7) * .06)
        if running:
            rig.pose.bones["hips"].location.y = abs(math.sin(phase)) * .018
            rotate("chest", (1, 0, 0), .10 if clip == "corrida" else .18)
        else:
            rig.pose.bones["chest"].location.y = math.sin(phase) * .002

    rig.animation_data_create()
    actions = []
    for clip, frames in (("espera", 60), ("corrida", 24), ("turbo", 18)):
        rig.animation_data.action = None
        for frame in range(1, frames + 2, 2):
            scene.frame_set(frame)
            pose(clip, (frame - 1) / frames * math.tau)
            for bone in rig.pose.bones:
                bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone.name)
                bone.keyframe_insert("location", frame=frame, group=bone.name)
        rig.animation_data.action.name = clip
        rig.animation_data.action.use_fake_user = True
        actions.append((clip, rig.animation_data.action, rig.animation_data.action_slot))
    pose("espera", 0)
    rig.animation_data.action = None
    for clip, action, slot in actions:
        track = rig.animation_data.nla_tracks.new()
        track.name = clip
        strip = track.strips.new(clip, 1, action)
        strip.action_slot = slot
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    scene.frame_start, scene.frame_end = 1, 61
    target = output / f"{slug}_rig_preview_{VERSION}.glb"
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", use_selection=True,
                             export_animations=True, export_animation_mode="NLA_TRACKS",
                             export_force_sampling=True)
    raw = target.read_bytes()
    payload = json.loads(raw[20:20 + struct.unpack_from("<I", raw, 12)[0]])
    clips = [item.get("name") for item in payload.get("animations", [])]
    if set(clips) != {"espera", "corrida", "turbo"}:
        raise RuntimeError(f"Missing exported animations: {clips}")
    report[slug] = {"path": str(target.relative_to(ROOT)), "bones": len(definitions),
                    "clips": clips, "weight_regions": counts,
                    "textures": "2048x2048", "bytes": target.stat().st_size,
                    "status": "experimental spatial weights; cape and joints require visual QA"}
    print("RIG_PREVIEW_EXPORTED " + json.dumps(report[slug]), flush=True)
(ROOT / f"docs/MODELOS_RIG_PREVIEW_{VERSION}.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
