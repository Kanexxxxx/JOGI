class_name StadiumRunner
extends HeroRunner
## A simulação mantém distância/colisões reais; a apresentação ocupa a raia lateral.

@export var stage_position: Vector3 = Vector3.ZERO
@export var stage_facing_y: float = -PI * .5
@export var stage_lod_bias: float = 3.0


func _build_visuals_and_collision() -> void:
	super._build_visuals_and_collision()
	# O estádio possui VFX próprios; o protótipo antigo usava anéis opacos
	# grandes demais para a câmera próxima e uma segunda esfera de escudo.
	if _boost_ring != null:
		_boost_ring.layers = 0
	if _shield_sphere != null:
		_shield_sphere.layers = 0
	if presentation != null and presentation.model != null:
		for node: Node in presentation.model.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).lod_bias = stage_lod_bias
	_reset_procedural_transform()


func _reset_procedural_transform() -> void:
	if _visual_root != null:
		_visual_root.top_level = true
		_visual_root.global_transform = Transform3D(Basis(Vector3.UP, stage_facing_y), stage_position)


func reset_runner(p_start_pos: Vector3) -> void:
	super.reset_runner(p_start_pos)
	_reset_procedural_transform()
