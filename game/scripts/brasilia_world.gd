class_name BrasiliaWorld
extends Node3D
## Mundo visual compartilhado entre a prévia de arte e a corrida real.

const ARENA: PackedScene = preload("res://assets/environments/brasilia/arena_v1.glb")
@export var build_lighting: bool = true
var road_material: ShaderMaterial = null
var world_environment: WorldEnvironment = null
var sun: DirectionalLight3D = null
var fill_light: DirectionalLight3D = null
var sky_material: ProceduralSkyMaterial = null
var _water_material: ShaderMaterial = null
var _foliage_shader: Shader = null
var _foliage_materials: Dictionary = {}


func _ready() -> void:
	if build_lighting:
		_build_light()
	var arena: Node3D = ARENA.instantiate() as Node3D
	add_child(arena)
	_prepare_living_materials(arena)
	_build_track()


func set_render_layer(mask: int) -> void:
	for child: Node in find_children("*", "VisualInstance3D", true, false):
		(child as VisualInstance3D).layers = mask


func set_round_metadata(metadata: Dictionary) -> void:
	if world_environment == null or sky_material == null:
		return
	# Dez atmosferas visuais; iluminação frontal mantém os rostos legíveis à noite.
	var presets: Array[Dictionary] = [
		{"top": "6faed0", "horizon": "f5dfbe", "sun": "fff1d4", "energy": .95, "angle": -28.0},
		{"top": "3e8cbe", "horizon": "cfe4e8", "sun": "fff8eb", "energy": 1.0, "angle": -38.0},
		{"top": "569ac0", "horizon": "dae9ed", "sun": "fff7e8", "energy": .95, "angle": -34.0},
		{"top": "829faf", "horizon": "d6e1e2", "sun": "f3f5f2", "energy": .80, "angle": -42.0},
		{"top": "3386bb", "horizon": "d7e7e5", "sun": "fffbed", "energy": 1.05, "angle": -48.0},
		{"top": "739eb9", "horizon": "f5c785", "sun": "ffe6b5", "energy": .95, "angle": -27.0},
		{"top": "657fa7", "horizon": "f4b3a1", "sun": "ffe4d6", "energy": .88, "angle": -23.0},
		{"top": "334e7c", "horizon": "9db7cf", "sun": "d9e9ff", "energy": .85, "angle": -36.0},
		{"top": "142e53", "horizon": "4f6e96", "sun": "e0ecff", "energy": .85, "angle": -40.0},
		{"top": "284f79", "horizon": "d6c5a0", "sun": "ffefd8", "energy": .95, "angle": -32.0}
	]
	var preset: Dictionary = presets[clampi(int(metadata.get("preset_id", 2)) - 1, 0, 9)]
	sky_material.sky_top_color = Color(String(preset["top"]))
	sky_material.sky_horizon_color = Color(String(preset["horizon"]))
	sky_material.ground_horizon_color = Color(String(preset["horizon"]))
	world_environment.environment.fog_light_color = Color(String(preset["horizon"]))
	sun.light_color = Color(String(preset["sun"]))
	sun.light_energy = float(preset["energy"])
	sun.rotation_degrees.x = float(preset["angle"])


func _prepare_living_materials(arena: Node3D) -> void:
	_water_material = ShaderMaterial.new()
	var water_shader: Shader = Shader.new()
	water_shader.code = """shader_type spatial;
varying vec3 water_world;
void vertex() {
    water_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    if (NORMAL.y > .5) {
        float a = water_world.x * 2.0 + TIME * .7;
        float b = water_world.z * 2.5 - TIME * .5;
        VERTEX.y += sin(a) * .008 + cos(b) * .006;
        NORMAL = normalize(vec3(-cos(a) * .016, 1.0, sin(b) * .015));
    }
}
void fragment() {
    float shimmer = sin(water_world.x * 3.0 + water_world.z * 2.0 + TIME * .45) * .018;
    ALBEDO = vec3(.035, .30, .39) + shimmer;
    ROUGHNESS = .22;
    METALLIC = .22;
}
"""
	_water_material.shader = water_shader
	_foliage_shader = Shader.new()
	_foliage_shader.code = """shader_type spatial;
uniform vec4 leaf_color : source_color = vec4(.3, .5, .1, 1.0);
void vertex() {
    vec3 origin = MODEL_MATRIX[3].xyz;
    float phase = origin.x * .17 + origin.z * .23;
    VERTEX.x += sin(TIME * 1.15 + phase) * .018;
    VERTEX.z += cos(TIME * .8 + phase) * .010;
}
void fragment() { ALBEDO = leaf_color.rgb; ROUGHNESS = .85; }
"""
	for node: Node in arena.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface: int in range(mesh_node.mesh.get_surface_count()):
			var material: StandardMaterial3D = mesh_node.get_active_material(surface) as StandardMaterial3D
			if material == null:
				continue
			if String(node.name).begins_with("Agua serena"):
				mesh_node.set_surface_override_material(surface, _water_material)
			elif String(node.name).begins_with("Copa "):
				var key: String = material.resource_name
				if not _foliage_materials.has(key):
					var leaf: ShaderMaterial = ShaderMaterial.new()
					leaf.shader = _foliage_shader
					leaf.set_shader_parameter("leaf_color", material.albedo_color)
					_foliage_materials[key] = leaf
				mesh_node.set_surface_override_material(surface, _foliage_materials[key] as ShaderMaterial)


func set_travel_distance(meters: float) -> void:
	if road_material != null:
		road_material.set_shader_parameter("travel", fposmod(meters, 400.0))


func _build_light() -> void:
	world_environment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("3e8cbe")
	sky_material.sky_horizon_color = Color("cfe4e8")
	sky_material.ground_horizon_color = Color("cfe4e8")
	sky_material.ground_bottom_color = Color("a7b4a0")
	sky_material.sun_angle_max = 12.0
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e1edf1")
	environment.ambient_light_energy = .30
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.fog_enabled = true
	environment.fog_light_color = Color("cfe4e8")
	environment.fog_density = .0015
	environment.fog_sky_affect = 0.0
	environment.ssao_enabled = true
	environment.ssao_radius = .8
	environment.ssao_intensity = .8
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 145, 0)
	sun.light_color = Color("fff8eb")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100.0
	add_child(sun)
	fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-25, -28, 0)
	fill_light.light_color = Color("c0e3ff")
	fill_light.light_energy = .2
	add_child(fill_light)


func _flat_material(color: Color, roughness: float = .8) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _box(position_value: Vector3, dimensions: Vector3, material: Material) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position_value
	add_child(instance)


func _build_track() -> void:
	_box(Vector3(0, -.22, 30), Vector3(240, .3, 240), _flat_material(Color("d2d2b9")))
	var road_shader: Shader = Shader.new()
	road_shader.code = """shader_type spatial;
uniform float travel = 0.0;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    float x = abs(world_position.x);
    float z = world_position.z + travel;
    vec3 surface = vec3(0.024, 0.055, 0.072);
    float grain = fract(sin(dot(world_position.xz * 90.0, vec2(12.9898, 78.233))) * 43758.5453);
    surface += (grain - .5) * .003;
    float edge = step(3.24, x) * (1.0 - step(3.30, x));
    float center = (1.0 - step(.035, x)) * step(2.1, mod(z, 4.0));
    surface = mix(surface, vec3(.86, .88, .78), max(edge, center));
    float line = step(3.37, x);
    surface = mix(surface, vec3(.66, .51, .17), line);
    ALBEDO = surface;
    ROUGHNESS = .82;
}
"""
	road_material = ShaderMaterial.new()
	road_material.shader = road_shader
	_box(Vector3(0, -.055, 30), Vector3(7.0, .10, 190), road_material)
	var concrete: StandardMaterial3D = _flat_material(Color("e9e6d5"))
	var gold: StandardMaterial3D = _flat_material(Color("d7b95c"), .4)
	for sign_value: float in [-1.0, 1.0]:
		_box(Vector3(sign_value * 3.74, -.015, 30), Vector3(.40, .18, 190), concrete)
		_box(Vector3(sign_value * 3.98, .09, 30), Vector3(.055, .04, 190), gold)


