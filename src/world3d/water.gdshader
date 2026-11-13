shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;
// Still water that reflects the red sky at grazing angles; in a lava biome the same
// plane glows as slow molten rock. Biome weights come from the field's biome map.

uniform vec3 b_deep[5];
uniform vec3 b_sky[5];
uniform float b_lava[5];
uniform sampler2D biome_map : filter_linear, repeat_disable;
uniform vec2 origin = vec2(0.0);
uniform vec2 size = vec2(1.0);
uniform sampler2D waves : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 bm = texture(biome_map, (wpos.xz - origin) / size);
	float b0 = max(0.0, 1.0 - bm.r - bm.g - bm.b - bm.a);
	vec3 deep = b_deep[0] * b0 + b_deep[1] * bm.r + b_deep[2] * bm.g + b_deep[3] * bm.b + b_deep[4] * bm.a;
	vec3 sky = b_sky[0] * b0 + b_sky[1] * bm.r + b_sky[2] * bm.g + b_sky[3] * bm.b + b_sky[4] * bm.a;
	float lava = clamp(b_lava[0] * b0 + b_lava[1] * bm.r + b_lava[2] * bm.g + b_lava[3] * bm.b + b_lava[4] * bm.a, 0.0, 1.0);
	vec3 n1 = texture(waves, wpos.xz * 0.07 + TIME * vec2(0.008, 0.013)).rgb;
	vec3 n2 = texture(waves, wpos.xz * 0.11 - TIME * vec2(0.011, 0.006)).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = mix(0.35, 0.8, lava);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 water = mix(deep, sky, clamp(fres * 0.9, 0.0, 0.6));
	// Lava: dark crust over glowing cracks, slowly churning.
	float crack = smoothstep(0.45, 0.7, texture(waves, wpos.xz * 0.05 + TIME * vec2(0.004, -0.003)).r);
	vec3 glow = mix(deep * 0.15, sky, crack);
	ALBEDO = mix(water, glow * 0.3, lava);
	EMISSION = glow * lava * 2.2;
	// Soft enough that a high sun gives a broad sheen, not a white hole in the pond.
	ROUGHNESS = mix(0.32, 0.8, lava);
	METALLIC = mix(0.05, 0.0, lava);
	SPECULAR = mix(0.4, 0.2, lava);
	ALPHA = mix(0.9, 1.0, lava);
}
