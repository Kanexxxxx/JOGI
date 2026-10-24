class_name StadiumWorld
extends Node3D
## Arena em profundidade: o percurso corre no eixo +X; Z separa as duas raias.
## Somente apresentação. A distância vem da simulação, sem alterar a física.

@export var build_lighting: bool = true
@export var grandstand_scene: PackedScene = null
@export_range(0, 1800, 60) var crowd_count: int = 1200

var world_environment: WorldEnvironment = null
var sky_material: ProceduralSkyMaterial = null
var sun: DirectionalLight3D = null
var fill_light: DirectionalLight3D = null
var road_material: ShaderMaterial = null
var _grass_material: ShaderMaterial = null
var _led_material: ShaderMaterial = null
var _crowd_material: ShaderMaterial = null
var _flag_material: ShaderMaterial = null
var _far_root: Node3D = null
var _stand_root: Node3D = null
var _opposite_stand: Node3D = null
var _near_root: Node3D = null
var _materials: Dictionary = {}
var _travel_distance: float = 0.0
var _render_layer: int = 1
var _distance_markers: Array[Node3D] = []
var _distance_labels: Array[Label3D] = []
var _race_progress: float = 0.0
var _sign_font: FontVariation = null
var _crest_plate_material: StandardMaterial3D = null
var _crest_trim_material: StandardMaterial3D = null
var _year_label_3d: Label3D = null


func _ready() -> void:
	name = "ArenaEsportiva"
	if build_lighting:
		_build_light()
	_build_shared_shaders()
	_build_track()
	_far_root = _group("PaisagemDistante")
	_stand_root = _group("ArquibancadaParalaxe")
	_near_root = _group("DetalhesProximos")
	_build_grandstands()
	_build_crowd()
	_build_skyline()
	_build_trackside()
	_merge_static_meshes(_stand_root)
	_opposite_stand = _stand_root.duplicate() as Node3D
	_opposite_stand.name = "ArquibancadaOposta"
	add_child(_opposite_stand)
	_opposite_stand.rotation.y = PI
	_build_monumental_horizon()
	_build_distance_markers()
	_merge_static_meshes(_far_root)
	_merge_static_meshes(_near_root)
	set_travel_distance(_travel_distance)
	set_render_layer(_render_layer)
	set_race_progress(_race_progress)


func set_race_progress(meters: float) -> void:
	# Real simulation metres in; only their projection is compressed to .18.
	# Six existing nodes are recycled, even after days of continuous running.
	if not is_finite(meters):
		return
	_race_progress = maxf(meters, .0)
	var first: int = int(floor(_race_progress / 50.0)) * 50
	for index: int in range(_distance_markers.size()):
		var mark: int = first + index * 50
		# O lado pertence à distância, não ao índice reciclado do pool.
		var side: float = -1.0 if (mark / 50) % 2 == 0 else 1.0
		(_distance_markers[index].get_node("Travessao") as Node3D).position.z = side * 3.65
		_distance_labels[index].position.z = side * 3.40
		_distance_markers[index].position.x = (float(mark) - _race_progress) * .18 - .35
		_distance_labels[index].text = str(mark) + " m"
		_distance_labels[index].pixel_size = minf(.007, 1.8 / (float(_distance_labels[index].text.length()) * 58.0))
		_distance_markers[index].visible = _distance_markers[index].position.x >= 3.0 and _distance_markers[index].position.x <= 48.0
		_distance_markers[index].set_meta("distance_m", mark)


func _get_sign_font() -> FontVariation:
	if _sign_font == null:
		_sign_font = FontVariation.new()
		_sign_font.base_font = preload("res://assets/fonts/nunito/Nunito-Variable.ttf")
		var weight_axis: int = TextServerManager.get_primary_interface().name_to_tag("wght")
		_sign_font.variation_opentype = {weight_axis: 850.0}
	return _sign_font


func _build_distance_markers() -> void:
	var ink: StandardMaterial3D = _material("SinalizacaoMetros", Color("a8eaff"))
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for index: int in range(6):
		var marker: Node3D = _group("MarcoReal_%s" % index)
		var side: float = -1.0 if index % 2 == 0 else 1.0
		_box(marker, "Travessao", Vector3(0, .007, side * 3.65), Vector3(.065, .01, 1.2), ink)
		var label: Label3D = Label3D.new()
		label.name = "DistanciaReal"
		label.font = _get_sign_font()
		label.font_size = 96
		label.pixel_size = .007
		label.outline_size = 5
		label.modulate = Color("d5f4ff")
		label.outline_modulate = Color("073777")
		label.no_depth_test = false
		label.position = Vector3(.85, .025, side * 3.40)
		# Right = +Z, top = +X, face = +Y: painted on the track, readable
		# from the rear camera rather than a floating billboard over runners.
		label.basis = Basis(Vector3.BACK, Vector3.RIGHT, Vector3.UP)
		marker.add_child(label)
		_distance_markers.append(marker)
		_distance_labels.append(label)


func set_render_layer(mask: int) -> void:
	_render_layer = mask
	for node: Node in find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = 512 if node.has_meta("architectural_layer") else mask


func set_travel_distance(distance: float) -> void:
	_travel_distance = distance
	if road_material != null:
		road_material.set_shader_parameter("travel", fposmod(distance, 240.0))
	if _grass_material != null:
		_grass_material.set_shader_parameter("travel", fposmod(distance, 240.0))
	if _stand_root != null:
		_stand_root.position.x = -fposmod(distance * .18, 8.0)
	if _opposite_stand != null:
		_opposite_stand.position.x = -fposmod(distance * .18, 8.0)
	if _far_root != null:
		_far_root.position.x = -fposmod(distance * .065, 16.0)
	if _near_root != null:
		_near_root.position.x = -fposmod(distance, 8.0)


func set_round_metadata(metadata: Dictionary) -> void:
	if world_environment == null or sky_material == null:
		return
	# Atmosferas reais de iluminação: os nomes das 50 rodadas não fingem 50 mapas.
	var preset_id: int = clampi(int(metadata.get("preset_id", 2)), 1, 10)
	var night: bool = preset_id == 8 or preset_id == 9 or preset_id == 10
	var sunset: bool = preset_id == 6 or preset_id == 7
	var top: Color = Color("087be9")
	var horizon: Color = Color("a4e9ff")
	if night:
		top = Color("071d62")
		horizon = Color("2c69b5")
	elif sunset:
		top = Color("2789ef")
		horizon = Color("ffd094")
	sky_material.sky_top_color = top
	sky_material.sky_horizon_color = horizon
	sky_material.ground_horizon_color = horizon
	sun.light_color = Color("ffefcf") if sunset else Color("fff8ed")
	sun.light_energy = .7 if night else 1.05
	sun.rotation_degrees.x = -25.0 if sunset else -42.0
	fill_light.light_energy = .62 if night else .36
	world_environment.environment.ambient_light_energy = .43 if night else .36
	if _led_material != null:
		_led_material.set_shader_parameter("emission_strength", 1.3 if night else .55)
	if _crest_plate_material != null:
		_crest_plate_material.emission_energy_multiplier = 0.72 if night else 0.34
	if _crest_trim_material != null:
		_crest_trim_material.emission_energy_multiplier = 1.15 if night else 0.52
	if _year_label_3d != null:
		_year_label_3d.modulate = Color("fff07a") if night else Color("ffe34d")


func _build_light() -> void:
	world_environment = WorldEnvironment.new()
	world_environment.name = "AtmosferaDaArena"
	var environment: Environment = Environment.new()
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("087be9")
	sky_material.sky_horizon_color = Color("a4e9ff")
	sky_material.ground_horizon_color = Color("a4e9ff")
	sky_material.ground_bottom_color = Color("1b7848")
	sky_material.sun_angle_max = 4.0
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e8f5ff")
	environment.ambient_light_energy = .36
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = .82
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.08
	environment.adjustment_contrast = 1.06
	environment.ssao_enabled = false
	environment.fog_enabled = false
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "SolFrontalSuave"
	sun.rotation_degrees = Vector3(-42, -25, 0)
	sun.light_color = Color("fff8ed")
	sun.light_energy = 1.05
	sun.light_cull_mask = 1048063 # Todos os layers, exceto 512 (arquitetura).
	# Sombras dos personagens são configuradas pela apresentação, sem duplicar passes.
	sun.shadow_enabled = false
	add_child(sun)
	fill_light = DirectionalLight3D.new()
	fill_light.name = "PreenchimentoRostos"
	fill_light.rotation_degrees = Vector3(-25, 165, 0)
	fill_light.light_color = Color("d5edff")
	fill_light.light_energy = .36
	fill_light.light_cull_mask = 1048063
	add_child(fill_light)


func _build_shared_shaders() -> void:
	road_material = _shader_material("""shader_type spatial;
uniform float travel = 0.0;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    float x = world_pos.x + travel;
    float z = world_pos.z;
    float grain = fract(sin(dot(vec2(x, z) * 150.0, vec2(12.9898, 78.233))) * 43758.5453);
    // Cobalto separa as capas vermelha e verde do piso, inclusive na tela pequena.
    vec3 track = mix(vec3(.018, .085, .25), vec3(.026, .12, .32), step(0.0, z));
    track += (grain - .5) * .007;
    float lines = 1.0 - smoothstep(.045, .065, abs(z));
    lines = max(lines, 1.0 - smoothstep(.045, .065, abs(abs(z) - 4.4)));
    // Travessões de referência sempre se deslocam para a esquerda.
    float marker = (1.0 - smoothstep(.025, .05, abs(mod(x + 3.0, 8.0) - 4.0))) * step(3.9, abs(z));
    ALBEDO = mix(track, vec3(.98, .98, .94), max(lines, marker));
    ROUGHNESS = .89;
}
""")
	_grass_material = _shader_material("""shader_type spatial;
uniform float travel = 0.0;
varying vec3 p;
void vertex() { p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    float x = p.x + travel;
    float stripe = step(4.0, mod(x, 8.0));
    float grain = fract(sin(dot(vec2(x, p.z) * 80.0, vec2(13.1, 78.2))) * 43758.5);
    ALBEDO = mix(vec3(.012, .16, .022), vec3(.025, .25, .035), stripe) + (grain - .5) * .012;
    ROUGHNESS = 1.0;
}
""")
	_led_material = _shader_material("""shader_type spatial;
render_mode unshaded;
uniform float emission_strength = .55;
void fragment() {
    float x = UV.x * 20.0 - TIME * .65;
    float arrow = step(.63, fract(x + abs(UV.y - .5) * .85));
    float grid = .87 + .13 * step(.3, fract(UV.x * 460.0)) * step(.3, fract(UV.y * 12.0));
    vec3 c = mix(vec3(.012, .20, .98), vec3(.16, .95, 1.0), arrow) * grid;
    ALBEDO = c;
    EMISSION = c * emission_strength;
}
""")
	_flag_material = _shader_material("""shader_type spatial;
render_mode cull_disabled;
void vertex() {
    VERTEX.z += sin(TIME * 3.0 + UV.x * 7.0) * UV.x * .11;
    VERTEX.y += cos(TIME * 2.2 + UV.x * 8.0) * UV.x * .035;
}
void fragment() {
    vec2 p = UV - vec2(.5);
    vec3 c = vec3(.012, .49, .11);
    float diamond = 1.0 - step(.42, abs(p.x) + abs(p.y) * .85);
    c = mix(c, vec3(1.0, .82, .015), diamond);
    c = mix(c, vec3(.015, .12, .65), 1.0 - step(.16, length(p)));
    float band = (1.0 - step(.015, abs(p.y + p.x * .22))) * (1.0 - step(.145, length(p)));
    c = mix(c, vec3(.96), band);
    ALBEDO = c;
    ROUGHNESS = .8;
}
""")
	_crowd_material = _shader_material("""shader_type spatial;
render_mode cull_disabled;
varying vec3 shirt;
varying float clothing;
varying float shade;
varying float hair;
varying float skin_tone;
void vertex() {
    shirt = INSTANCE_CUSTOM.rgb;
    clothing = COLOR.r;
    hair = COLOR.b;
    skin_tone = fract(INSTANCE_CUSTOM.a * 13.17);
    shade = .84 + .16 * sin(INSTANCE_CUSTOM.a * 6.28318);
    float phase = TIME * (1.35 + fract(INSTANCE_CUSTOM.a * 7.0) * .65) + INSTANCE_CUSTOM.a * 41.0;
    if (COLOR.g > .5) {
        float side = sign(VERTEX.x);
        vec2 pivot = vec2(side * .145, .425);
        vec2 arm = VERTEX.xy - pivot;
        // Rotate an intact arm around the shoulder; do not squash its length.
        float pose = fract(INSTANCE_CUSTOM.a * 23.0);
        float angle = side * (.12 + .47 * smoothstep(.1, .95, sin(phase + side * 1.1)));
        angle *= mix(.35, 1.0, step(.43, pose));
        float c = cos(angle); float s = sin(angle);
        VERTEX.xy = pivot + mat2(vec2(c, s), vec2(-s, c)) * arm;
    }
    VERTEX.y += sin(phase) * .008 * max(0.0, VERTEX.y);
    VERTEX.x += sin(phase * .7) * .009 * max(0.0, VERTEX.y);
}
void fragment() {
    vec3 skin = mix(vec3(.24, .095, .045), vec3(.81, .48, .23), skin_tone);
    ALBEDO = mix(mix(skin, shirt, clothing), vec3(.025, .018, .012), hair) * shade;
    ROUGHNESS = .93;
}
""")


func _build_track() -> void:
	_box(self, "GramadoListrado", Vector3(0, -.14, -1), Vector3(160, .2, 58), _grass_material)
	_box(self, "PistaTartanDuasRaias", Vector3(0, -.047, 0), Vector3(160, .085, 9.2), road_material)
	var white: StandardMaterial3D = _material("BordaBranca", Color("fffceb"))
	var blue: StandardMaterial3D = _material("AzulArena", Color("0439ba"), .47)
	var yellow: StandardMaterial3D = _material("AmareloBrasil", Color("ffcf00"), .5)
	for side: float in [-1.0, 1.0]:
		_box(self, "CanaletaBranca", Vector3(0, -.005, side * 4.69), Vector3(160, .075, .15), white)
		_box(self, "FaixaAzulBorda", Vector3(0, -.022, side * 4.9), Vector3(160, .055, .26), blue)
		_box(self, "FioAmareloBorda", Vector3(0, .012, side * 5.07), Vector3(160, .025, .055), yellow)


func _build_grandstands() -> void:
	var concrete: StandardMaterial3D = _material("ConcretoPerola", Color("c8d7e5"))
	var structure: StandardMaterial3D = _material("EstruturaAzulProfundo", Color("042878"), .48)
	var roof: StandardMaterial3D = _material("CoberturaAzulEletrico", Color("0754ec"), .43)
	var white: StandardMaterial3D = _material("MetalBranco", Color("f7fbff"), .42)
	var cyan: StandardMaterial3D = _material("DetalhesTurquesa", Color("05c5dc"), .45)
	for section: int in range(-3, 5):
		var section_root: Node3D = _group("ModuloArquibancada_%s" % section, _stand_root)
		section_root.position.x = float(section) * 8.0
		if grandstand_scene != null:
			var imported: Node3D = grandstand_scene.instantiate() as Node3D
			section_root.add_child(imported)
			imported.position = Vector3(0, 0, -8.5)
			for mesh_node: Node in imported.find_children("*", "MeshInstance3D", true, false):
				mesh_node.set_meta("preserve_instancing", true)
			continue
		for row: int in range(8):
			var row_y: float = .35 + float(row) * .38
			var row_z: float = -7.0 - float(row) * .75
			_box(section_root, "Degrau_%s" % row, Vector3(0, row_y * .5, row_z), Vector3(8, row_y, .77), concrete)
			_box(section_root, "Assentos_%s" % row, Vector3(-.35, row_y + .08, row_z), Vector3(6.88, .13, .38), cyan if row % 2 == 0 else roof)
		# Uma escada de circulação atravessa cada bloco e quebra o padrão dos assentos.
		for row: int in range(8):
			_box(section_root, "Escada_%s" % row, Vector3(3.45, .37 + float(row) * .38, -7.0 - float(row) * .75), Vector3(.85, .08, .77), white)
		_box(section_root, "VigaFrontal", Vector3(0, 4.7, -7.25), Vector3(8, .25, .24), cyan)
		_box(section_root, "FaixaLuminosa", Vector3(0, 1.0, -6.6), Vector3(8, .42, .10), _led_material)
		_box(section_root, "GuardaCorpoBase", Vector3(0, .52, -6.58), Vector3(8, .42, .20), structure)
		for support_x: float in [-3.85, 3.85]:
			_cylinder(section_root, "ColunaTubular", Vector3(support_x, 2.5, -12.9), .10, .14, 5.0, white)
			_beam(section_root, "TiranteCobertura", Vector3(support_x, 4.65, -7.2), Vector3(support_x, 5.15, -13), .07, white)
			_beam(section_root, "DiagonalCobertura", Vector3(support_x, 3.9, -12.9), Vector3(support_x, 4.65, -7.4), .065, white)
		var panel: MeshInstance3D = _box(section_root, "CoberturaCurva", Vector3(0, 4.98, -10.2), Vector3(8, .16, 6.7), roof)
		panel.rotation_degrees.x = -5
		for rib: int in range(5):
			_box(section_root, "NervuraCobertura_%s" % rib, Vector3(-3.8 + float(rib) * 1.9, 5.08, -10.2), Vector3(.045, .045, 6.7), cyan)
		_build_flag(section_root, Vector3(2.6, 3.6, -12.0))


func _build_crowd() -> void:
	if crowd_count <= 0:
		return
	var mesh: ArrayMesh = _crowd_mesh()
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = crowd_count
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 10242026
	var colors: Array[Color] = [Color("ffd51b"), Color("10c257"), Color("106ae8"), Color("f7fcff"), Color("ff3830"), Color("00c8dc"), Color("ff8b17")]
	for index: int in range(crowd_count):
		var rows: int = 6 if grandstand_scene != null else 8
		var row: int = index % rows
		var column: int = index / rows
		# Dezenove lugares por fileira, sem sobrepor pessoas para desviar da escada.
		var block: int = column / 19
		var seat: int = column % 19
		var x: float = -27.2 + float(block) * 8.0 + float(seat) * .35
		var y: float = .44 + float(row) * .38
		var z: float = -7.0 - float(row) * .75
		if grandstand_scene != null:
			block = column / 16
			seat = column % 16
			var local_x: float = -3.2 + float(seat) * .36 if seat < 8 else .68 + float(seat - 8) * .36
			x = -24.0 + float(block) * 8.0 + local_x
			y = .84 + float(row) * .40
			z = -7.35 - float(row) * .44
		var height: float = rng.randf_range(.86, 1.12)
		var transform_value: Transform3D = Transform3D(Basis.IDENTITY.scaled(Vector3(.98, height * 1.16, .98)), Vector3(x, y, z))
		multimesh.set_instance_transform(index, transform_value)
		var shirt: Color = colors[rng.randi_range(0, colors.size() - 1)].srgb_to_linear()
		multimesh.set_instance_custom_data(index, Color(shirt.r, shirt.g, shirt.b, rng.randf()))
	var crowd: MultiMeshInstance3D = MultiMeshInstance3D.new()
	crowd.name = "TorcidaAnimada1200"
	crowd.multimesh = multimesh
	crowd.material_override = _crowd_material
	crowd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stand_root.add_child(crowd)


func _crowd_mesh() -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Volumes 3D arredondados, com pele/camisa/cabelo e braços articulados pelo
	# shader. Cada pessoa compartilha a mesma malha; cores e fase variam por instância.
	var body: CylinderMesh = CylinderMesh.new()
	body.top_radius = .12
	body.bottom_radius = .135
	body.height = .30
	body.radial_segments = 8
	body.rings = 1
	_append_crowd_shape(surface, body, Transform3D(Basis.IDENTITY, Vector3(0, .30, 0)), Color.RED)
	var head: SphereMesh = SphereMesh.new()
	head.radius = .105
	head.height = .24
	head.radial_segments = 8
	head.rings = 4
	_append_crowd_shape(surface, head, Transform3D(Basis.IDENTITY, Vector3(0, .565, 0)), Color.BLACK)
	var hair: SphereMesh = SphereMesh.new()
	hair.radius = .108
	hair.height = .12
	hair.radial_segments = 8
	hair.rings = 3
	_append_crowd_shape(surface, hair, Transform3D(Basis.IDENTITY, Vector3(0, .645, 0)), Color.BLUE)
	for side: float in [-1.0, 1.0]:
		var arm: CylinderMesh = CylinderMesh.new()
		arm.top_radius = .034
		arm.bottom_radius = .042
		arm.height = .24
		arm.radial_segments = 5
		arm.rings = 1
		var basis: Basis = Basis(Vector3.FORWARD, side * -.38)
		_append_crowd_shape(surface, arm, Transform3D(basis, Vector3(side * .19, .50, .0)), Color.GREEN)
	return surface.commit()


func _append_crowd_shape(surface: SurfaceTool, mesh: PrimitiveMesh, transform_value: Transform3D, marker: Color) -> void:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index: int in indices:
		surface.set_color(marker)
		surface.set_normal((transform_value.basis * normals[index]).normalized())
		surface.add_vertex(transform_value * vertices[index])


func _build_skyline() -> void:
	var cloud: StandardMaterial3D = _material("NuvensBrancas", Color("f9fdff"))
	for cloud_index: int in range(8):
		var cloud_root: Node3D = _group("Nuvem_%s" % cloud_index, _far_root)
		cloud_root.position = Vector3(-24.0 + float(cloud_index) * 16.0, 9.0 + float(cloud_index % 3) * 2.4, -17.0 if cloud_index % 2 == 0 else 18.0)
		for puff: int in range(4):
			var ball: SphereMesh = SphereMesh.new()
			ball.radial_segments = 10
			ball.rings = 4
			ball.radius = .75
			ball.height = 1.5
			var node: MeshInstance3D = _mesh(cloud_root, "VolumeNuvem", ball, cloud)
			node.position = Vector3(float(puff) * .9, sin(float(puff) * 1.7) * .25, 0)
			node.scale = Vector3(1.3, .72, .7)
	var pole: StandardMaterial3D = _material("PostesCinzaAzul", Color("aac5de"), .35)
	var lamp: StandardMaterial3D = _material("RefletoresBrancos", Color("f5feff"), .3)
	lamp.emission_enabled = true
	lamp.emission = Color("bde9ff")
	lamp.emission_energy_multiplier = .7
	for index: int in range(-2, 4):
		var x: float = float(index) * 16.0 + 4
		_cylinder(_far_root, "TorreRefletor", Vector3(x, 1.5, -12), .09, .13, 3.0, pole)
		_box(_far_root, "PainelRefletores", Vector3(x, 2.95, -11.9), Vector3(1.8, .65, .18), _material("MolduraRefletor", Color("164383"), .4))
		for row: int in range(2):
			for column: int in range(5):
				_box(_far_root, "LenteRefletor", Vector3(x - .69 + float(column) * .34, 2.8 + float(row) * .29, -11.78), Vector3(.25, .20, .05), lamp)
	for index: int in range(-2, 4):
		_build_palm(_far_root, Vector3(float(index) * 16.0 - 3.0, -1.4, -12.5))
	for side: float in [-1.0, 1.0]:
		for flag_index: int in range(3):
			var hero_flag: Node3D = _group("BandeiraMonumental", _far_root)
			hero_flag.position = Vector3(12 + flag_index * 16, 2.5, side * 13)
			hero_flag.scale = Vector3.ONE * 2.6
			_build_flag(hero_flag, Vector3.ZERO)


func _build_trackside() -> void:
	var white: StandardMaterial3D = _material("MetalBranco", Color("f7fbff"), .42)
	var blue: StandardMaterial3D = _material("AzulArena", Color("0439ba"), .47)
	var yellow: StandardMaterial3D = _material("AmareloBrasil", Color("ffcf00"), .5)
	for index: int in range(-4, 6):
		var x: float = float(index) * 8.0
		# Placas, cordão e chanfros dão referência de velocidade sem cobrir os pés.
		var board: MeshInstance3D = _box(_near_root, "PlacaLateralAzul", Vector3(x, .34, -5.65), Vector3(2.8, .62, .10), blue)
		board.rotation_degrees.x = -8
		_box(_near_root, "ListraPlacaAmarela", Vector3(x - 1.15, .34, -5.57), Vector3(.10, .48, .025), yellow)
		_box(_near_root, "ListraPlacaBranca", Vector3(x - .96, .34, -5.57), Vector3(.055, .48, .025), white)
		for stripe: int in range(3):
			var bar: MeshInstance3D = _box(_near_root, "SetaDirecao", Vector3(x + .4 + float(stripe) * .28, .34, -5.56), Vector3(.11, .37, .025), white)
			bar.rotation_degrees.z = -24
		# Guias amarelas no primeiro plano criam a camada de paralaxe mais rápida.
		_box(_near_root, "GuiaVelocidade", Vector3(x, -.005, 5.45), Vector3(.85, .025, .10), yellow)
		_build_flag(_near_root, Vector3(x + 2.0, .1, -5.7))
		_build_flag(_near_root, Vector3(x + 2.0, .1, 5.7))
	# A segunda lateral compartilha os materiais e acompanha a mesma rolagem.
	var sideboards: Node3D = _group("PlacasOpostas", _near_root)
	for node: Node in _near_root.get_children():
		if node is MeshInstance3D and node.name.begins_with("Placa"):
			var opposite: MeshInstance3D = node.duplicate() as MeshInstance3D
			sideboards.add_child(opposite)
			opposite.position.z = -opposite.position.z


func _build_monumental_horizon() -> void:
	var palace: Node3D = preload("res://assets/environments/planalto/planalto_v2.glb").instantiate() as Node3D
	palace.name = "PalacioDoPlanalto"
	palace.position = Vector3(48.0, 0.0, 0.0)
	add_child(palace)
	# Placa cênica arquitetônica acima da platibanda do Planalto: garante contraste
	# nítido para "2027" tanto no céu diurno claro quanto nas rodadas noturnas,
	# sem encobrir as colunas nem a rampa presidencial.
	var crest: Node3D = _group("BrasaoPlanalto2027")
	crest.position = Vector3(47.35, 9.85, 0.0)
	_crest_plate_material = StandardMaterial3D.new()
	_crest_plate_material.resource_name = "PlacaAzulPlanalto2027"
	_crest_plate_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crest_plate_material.albedo_color = Color("061844")
	_crest_plate_material.emission_enabled = true
	_crest_plate_material.emission = Color("0a2a73")
	_crest_plate_material.emission_energy_multiplier = 0.34
	_crest_trim_material = StandardMaterial3D.new()
	_crest_trim_material.resource_name = "FrisoOuroPlanalto2027"
	_crest_trim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crest_trim_material.albedo_color = Color("ffcf26")
	_crest_trim_material.emission_enabled = true
	_crest_trim_material.emission = Color("ffcf26")
	_crest_trim_material.emission_energy_multiplier = 0.52
	_box(crest, "MolduraDourada", Vector3(0.08, 0.0, 0.0), Vector3(0.18, 3.62, 12.6), _crest_trim_material)
	_box(crest, "FundoMarinho", Vector3(0.0, 0.0, 0.0), Vector3(0.24, 3.36, 12.24), _crest_plate_material)
	var subtitle: Label3D = Label3D.new()
	subtitle.name = "LegendaPlanalto"
	subtitle.text = "BRASÍLIA · PLANALTO"
	subtitle.font = _get_sign_font()
	subtitle.font_size = 64
	subtitle.pixel_size = 0.0115
	subtitle.outline_size = 8
	subtitle.modulate = Color("eef7ff")
	subtitle.outline_modulate = Color("041137")
	subtitle.position = Vector3(-0.22, 1.02, 0.0)
	subtitle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	crest.add_child(subtitle)
	var year: Label3D = Label3D.new()
	year.name = "AnoCenografico2027"
	year.text = "2027"
	year.font = _get_sign_font()
	year.font_size = 184
	year.pixel_size = 0.0168
	year.outline_size = 16
	year.modulate = Color("ffe34d")
	year.outline_modulate = Color("030e2e")
	year.position = Vector3(47.06, 9.32, 0.0)
	year.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(year)
	_year_label_3d = year
	# Luz com sombra restrita à arquitetura: preserva o relevo das lâminas
	# sem renderizar novamente as malhas densas dos dois personagens.
	for node: Node in palace.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		mesh.layers = 512
		mesh.set_meta("architectural_layer", true)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var architectural_light: DirectionalLight3D = DirectionalLight3D.new()
	architectural_light.name = "LuzDaColunata"
	architectural_light.rotation_degrees = Vector3(-37, -55, 0)
	architectural_light.light_cull_mask = 512
	architectural_light.shadow_caster_mask = 512
	architectural_light.light_energy = .75
	architectural_light.shadow_enabled = true
	architectural_light.directional_shadow_max_distance = 90.0
	add_child(architectural_light)


func _build_flag(parent: Node3D, base: Vector3) -> void:
	var pole: StandardMaterial3D = _material("MetalBranco", Color("f7fbff"), .42)
	_cylinder(parent, "MastroBrasil", base + Vector3(0, .9, 0), .025, .025, 1.8, pole)
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(1.0, .65)
	plane.orientation = PlaneMesh.FACE_Z
	plane.subdivide_width = 10
	plane.subdivide_depth = 3
	var flag: MeshInstance3D = _mesh(parent, "BandeiraBrasilAoVento", plane, _flag_material)
	flag.position = base + Vector3(.49, 1.43, .035)


func _build_palm(parent: Node3D, base: Vector3) -> void:
	var trunk_material: StandardMaterial3D = _material("TroncoPalmeira", Color("967146"))
	var palm_root: Node3D = _group("PalmeiraBrasileira", parent)
	palm_root.position = base
	for segment: int in range(5):
		var height: float = float(segment) * .84 + .42
		var trunk: MeshInstance3D = _cylinder(palm_root, "SegmentoTronco", Vector3(sin(float(segment) * .35) * .25, height, 0), .11, .16, .86, trunk_material)
		trunk.rotation_degrees.z = -5
	var leaf: StandardMaterial3D = _material("FolhasPalmeira", Color("08a948"))
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for frond: int in range(9):
		var angle: float = float(frond) * TAU / 9.0
		var outward: Vector3 = Vector3(cos(angle), 0, sin(angle))
		var tangent: Vector3 = Vector3(-sin(angle), 0, cos(angle))
		for segment: int in range(4):
			var start: float = float(segment) / 4.0
			var finish: float = float(segment + 1) / 4.0
			var a: Vector3 = outward * start * 1.9 + Vector3(0, sin(start * PI) * .42 - start * .75, 0)
			var b: Vector3 = outward * finish * 1.9 + Vector3(0, sin(finish * PI) * .42 - finish * .75, 0)
			var width_a: float = sin(start * PI) * .23 + .025
			var width_b: float = sin(finish * PI) * .23 + .005
			_quad(surface, a - tangent * width_a, a + tangent * width_a, b + tangent * width_b, b - tangent * width_b, Color.WHITE)
	surface.generate_normals()
	var crown: MeshInstance3D = _mesh(palm_root, "CoroaFolhasCurvas", surface.commit(), leaf)
	crown.position = Vector3(.25, 4.1, 0)


func _group(node_name: String, parent: Node3D = self) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = node_name
	parent.add_child(node)
	return node


func _shader_material(code: String) -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = code
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	return material


func _merge_static_meshes(group: Node3D) -> void:
	# Cada camada de paralaxe conserva sua transformação. Dentro dela, materiais
	# compartilhados viram uma superfície, reduzindo centenas de submissões à GPU.
	var batches: Dictionary = {}
	var sources: Array[MeshInstance3D] = []
	for child: Node in group.find_children("*", "MeshInstance3D", true, false):
		var source: MeshInstance3D = child as MeshInstance3D
		if source.mesh == null or source.skin != null or source.has_meta("preserve_instancing"):
			continue
		var transform_value: Transform3D = group.global_transform.affine_inverse() * source.global_transform
		for surface_index: int in range(source.mesh.get_surface_count()):
			var material: Material = source.get_active_material(surface_index)
			if material == null:
				continue
			var key: int = material.get_instance_id()
			if not batches.has(key):
				var builder: SurfaceTool = SurfaceTool.new()
				builder.begin(Mesh.PRIMITIVE_TRIANGLES)
				batches[key] = {"builder": builder, "material": material}
			(batches[key]["builder"] as SurfaceTool).append_from(source.mesh, surface_index, transform_value)
		sources.append(source)
	for key: int in batches:
		var material: Material = batches[key]["material"] as Material
		var builder: SurfaceTool = batches[key]["builder"] as SurfaceTool
		var merged: ArrayMesh = builder.commit()
		_mesh(group, "Lote_%s" % material.resource_name if not material.resource_name.is_empty() else "LoteEfeito", merged, material)
	for source: MeshInstance3D in sources:
		source.free()


func get_visual_budget() -> Dictionary:
	var triangles: int = 0
	var surfaces: int = 0
	for child: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (child as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
				indices = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			surfaces += 1
	var crowd_mesh: ArrayMesh = _crowd_mesh()
	var crowd_triangles: int = (crowd_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3 * crowd_count
	return {"static_triangles": triangles, "crowd_triangles": crowd_triangles, "triangles_total": triangles + crowd_triangles, "static_surfaces": surfaces, "crowd_draws": 1 if crowd_count > 0 else 0, "crowd_instances": crowd_count}


func _material(key: String, color: Color, roughness: float = .82) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = key
	material.albedo_color = color
	material.roughness = roughness
	_materials[key] = material
	return material


func _mesh(parent: Node3D, node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _box(parent: Node3D, node_name: String, position_value: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	var instance: MeshInstance3D = _mesh(parent, node_name, mesh, material)
	instance.position = position_value
	return instance


func _cylinder(parent: Node3D, node_name: String, position_value: Vector3, top_radius: float, bottom_radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	var instance: MeshInstance3D = _mesh(parent, node_name, mesh, material)
	instance.position = position_value
	return instance


func _beam(parent: Node3D, node_name: String, start: Vector3, finish: Vector3, radius: float, material: Material) -> void:
	var instance: MeshInstance3D = _cylinder(parent, node_name, (start + finish) * .5, radius, radius, start.distance_to(finish), material)
	var direction: Vector3 = (finish - start).normalized()
	instance.quaternion = Quaternion(Vector3.UP, direction)


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(a)
	surface.set_color(color)
	surface.add_vertex(b)
	surface.set_color(color)
	surface.add_vertex(c)


func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_triangle(surface, a, b, c, color)
	_triangle(surface, a, c, d, color)
