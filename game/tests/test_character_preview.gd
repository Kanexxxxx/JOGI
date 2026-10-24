extends SceneTree
## Verifica o contrato dos GLBs importados no motor, sem aprovar qualidade visual.

var passed: bool = true


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		passed = false
		printerr(message)


func _run() -> void:
	for slug: String in ["lula", "flavio"]:
		var path: String = "res://assets/characters/preview-v7/%s_rig_preview_v7.glb" % slug
		var packed: PackedScene = load(path) as PackedScene
		_check(packed != null, slug + ": falha na importação")
		if packed == null:
			continue
		var model: Node3D = packed.instantiate() as Node3D
		root.add_child(model)
		var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var skeleton: Skeleton3D = _find_type(model, "Skeleton3D") as Skeleton3D
		var mesh_node: MeshInstance3D = _find_type(model, "MeshInstance3D") as MeshInstance3D
		_check(player != null and skeleton != null and mesh_node != null, slug + ": estrutura incompleta")
		if player != null and skeleton != null and mesh_node != null:
			_check(skeleton.get_bone_count() == 19, slug + ": número de ossos incorreto")
			_check(mesh_node.skin != null, slug + ": malha sem vínculo ao esqueleto")
			var triangles: int = 0
			for surface: int in range(mesh_node.mesh.get_surface_count()):
				var index_count: int = mesh_node.mesh.surface_get_array_index_len(surface)
				triangles += int(float(index_count if index_count > 0 else mesh_node.mesh.surface_get_array_len(surface)) / 3.0)
			_check(triangles > 0 and triangles <= 60000, slug + ": fora do limite experimental de 60 mil triângulos")
			var material: StandardMaterial3D = mesh_node.mesh.surface_get_material(0) as StandardMaterial3D
			_check(material != null, slug + ": material ausente")
			if material != null:
				_check(material.albedo_texture != null, slug + ": textura de cor ausente")
				_check(material.normal_texture != null, slug + ": textura normal ausente")
				if material.albedo_texture != null:
					_check(material.albedo_texture.get_width() == 2048, slug + ": cor não está em 2K")
				if material.normal_texture != null:
					_check(material.normal_texture.get_width() == 2048, slug + ": normal não está em 2K")
			for clip: String in ["espera", "corrida", "turbo"]:
				_check(player.has_animation(clip), slug + ": animação ausente " + clip)
				if player.has_animation(clip):
					_check(player.get_animation(clip).length > .4, slug + ": animação vazia " + clip)
			if player.has_animation("corrida"):
				var thigh: int = skeleton.find_bone("thigh_L")
				_check(thigh >= 0, slug + ": osso da perna ausente")
				if thigh >= 0:
					player.play("corrida")
					player.seek(0.0, true)
					var start_rotation: Quaternion = skeleton.get_bone_pose_rotation(thigh)
					player.seek(.2, true)
					var end_rotation: Quaternion = skeleton.get_bone_pose_rotation(thigh)
					_check(start_rotation.angle_to(end_rotation) > .2, slug + ": perna sem movimento real")
					player.seek(player.get_animation("corrida").length, true)
					_check(start_rotation.angle_to(skeleton.get_bone_pose_rotation(thigh)) < .02, slug + ": corrida não fecha o ciclo da perna")
		model.free()
	await process_frame
	_check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0, "Nós órfãos após liberar modelos")
	print("CHARACTER_PREVIEW_CONTRACT_", "PASSED" if passed else "FAILED")
	quit(0 if passed else 1)


func _find_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child: Node in node.get_children():
		var found: Node = _find_type(child, type_name)
		if found != null:
			return found
	return null
