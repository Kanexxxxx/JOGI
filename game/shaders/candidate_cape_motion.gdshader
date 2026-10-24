shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float normal_strength = 1.0;
uniform float roughness_strength = 1.0;
uniform float metallic_strength = 1.0;
uniform float specular_strength = 0.5;
uniform float cloth_phase = 0.0;
uniform float cloth_amplitude = 0.012;

void vertex() {
	// COLOR.r is baked from rest height: collar/shoulders exactly zero,
	// hem reaches one. COLOR.g carries rest width so folds never swim on skin.
	float depth = COLOR.r;
	float free_cloth = smoothstep(0.04, 1.0, depth);
	float width_phase = (COLOR.g - 0.5) * 11.0;
	float wave = sin(cloth_phase - depth * 6.5 + width_phase * 0.8);
	float secondary = sin(cloth_phase * 2.0 - depth * 11.0 - width_phase);
	float edge_wave = sin(cloth_phase - depth * 4.0 + width_phase * 1.6);
	// Model faces +Z in the approved GLB. Trail only toward -Z, away from legs.
	// Pinned collar, billowing middle and out-of-phase hem sections.
	// Integer time harmonics remain continuous on phase wrap.
	VERTEX.z -= cloth_amplitude * free_cloth * (0.95 + 0.60 * wave + 0.24 * secondary);
	VERTEX.x += cloth_amplitude * free_cloth * (0.24 * edge_wave + 0.11 * secondary);
	VERTEX.y += cloth_amplitude * free_cloth * (0.52 * wave + 0.19 * edge_wave);
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb * albedo_tint.rgb;
	vec3 orm = texture(orm_texture, UV).rgb;
	ROUGHNESS = orm.g * roughness_strength;
	METALLIC = orm.b * metallic_strength;
	SPECULAR = specular_strength;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
}
