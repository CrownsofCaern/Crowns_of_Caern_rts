shader_type spatial;
// Ground of the 3D map: grass, dirt (roads, yards), rock (mounds, slopes, mountains),
// forest floor and ash, blended from a splat map with the textures' own height
// (albedo alpha) so edges look worn rather than smeared. Textures: ambientCG (CC0).
// Every biome has its own open ground and rock: layers of the texture arrays below,
// picked per biome slot by b_layer / b_rlayer. Only slots present at a pixel are sampled.

uniform sampler2DArray ground_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray ground_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray rock_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray rock_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float b_layer[5];
uniform float b_rlayer[5];
uniform float b_embers[5];  // glowing cracks in the open ground (ash lands)
uniform vec3 ember_color : source_color = vec3(1.0, 0.32, 0.06);
uniform sampler2D dirt_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
// Grading of the ground only (after biome tints): a little colour drained and the
// darkest ground pulled toward a dark brown, so units stand out on it.
uniform float grade_saturation = 0.85;
uniform float grade_gamma = 1.05;
uniform vec3 grade_shadow = vec3(0.15, 0.13, 0.13);
uniform sampler2D splat : filter_linear, repeat_disable;
uniform vec2 origin = vec2(0.0);
uniform vec2 size = vec2(1.0);
uniform sampler2D macro_noise : filter_linear, repeat_enable;
// Biomes: index 0 = base, 1-4 weighted by the biome map's R, G, B, A (the rest is the base).
uniform sampler2D biome_map : filter_linear, repeat_disable;
uniform vec3 b_grass[5];
uniform vec3 b_lush[5];
uniform vec3 b_dry[5];
uniform vec3 b_dirt[5];
uniform vec3 b_rock[5];
uniform vec3 b_moss[5];
uniform vec3 b_ash[5];
uniform float b_snow[5];
uniform float grass_scale = 0.22;
uniform float dirt_scale = 0.35;
uniform float rock_scale = 0.12;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hblend(float w, float h) {
	// Height-aware blend: the higher texture pokes through first.
	return smoothstep(0.38, 0.62, w + (h - 0.5) * 0.45 * step(0.01, w) * step(w, 0.99));
}

void fragment() {
	vec2 xz = wpos.xz;
	vec4 sp = texture(splat, (xz - origin) / size);
	vec4 bm = texture(biome_map, (xz - origin) / size);
	float b0 = max(0.0, 1.0 - bm.r - bm.g - bm.b - bm.a);
	vec3 grass_tint = b_grass[0] * b0 + b_grass[1] * bm.r + b_grass[2] * bm.g + b_grass[3] * bm.b + b_grass[4] * bm.a;
	vec3 lush_tint = b_lush[0] * b0 + b_lush[1] * bm.r + b_lush[2] * bm.g + b_lush[3] * bm.b + b_lush[4] * bm.a;
	vec3 dry_tint = b_dry[0] * b0 + b_dry[1] * bm.r + b_dry[2] * bm.g + b_dry[3] * bm.b + b_dry[4] * bm.a;
	vec3 dirt_tint = b_dirt[0] * b0 + b_dirt[1] * bm.r + b_dirt[2] * bm.g + b_dirt[3] * bm.b + b_dirt[4] * bm.a;
	vec3 rock_tint = b_rock[0] * b0 + b_rock[1] * bm.r + b_rock[2] * bm.g + b_rock[3] * bm.b + b_rock[4] * bm.a;
	vec3 moss_tint = b_moss[0] * b0 + b_moss[1] * bm.r + b_moss[2] * bm.g + b_moss[3] * bm.b + b_moss[4] * bm.a;
	vec3 ash_tint = b_ash[0] * b0 + b_ash[1] * bm.r + b_ash[2] * bm.g + b_ash[3] * bm.b + b_ash[4] * bm.a;
	// Two scales of the same texture hide the repeat; large noise patches of dry
	// and lush grass and darker hollows keep open ground from looking like a carpet.
	float bw[5] = float[5](b0, bm.r, bm.g, bm.b, bm.a);
	vec3 bl = pow(abs(wnrm), vec3(4.0));
	bl /= (bl.x + bl.y + bl.z);
	vec4 g = vec4(0.0);
	vec4 r = vec4(0.0);
	vec3 ng = vec3(0.0);
	vec3 nr = vec3(0.0);
	float embers = 0.0;
	for (int i = 0; i < 5; i++) {
		if (bw[i] > 0.003) {
			float gl = b_layer[i];
			float rl = b_rlayer[i];
			g += bw[i] * mix(texture(ground_alb, vec3(xz * grass_scale, gl)),
				texture(ground_alb, vec3(xz * grass_scale * 0.37 + vec2(0.13, 0.61), gl)), 0.4);
			ng += bw[i] * texture(ground_nrm, vec3(xz * grass_scale, gl)).rgb;
			r += bw[i] * (texture(rock_alb, vec3(wpos.zy * rock_scale, rl)) * bl.x
				+ texture(rock_alb, vec3(xz * rock_scale, rl)) * bl.y + texture(rock_alb, vec3(wpos.xy * rock_scale, rl)) * bl.z);
			nr += bw[i] * texture(rock_nrm, vec3(xz * rock_scale, rl)).rgb;
			embers += bw[i] * b_embers[i];
		}
	}
	float n1 = texture(macro_noise, xz * 0.012).r;
	float n2 = texture(macro_noise, xz * 0.05 + vec2(0.4, 0.2)).r;
	vec3 tint = mix(lush_tint, grass_tint, smoothstep(0.3, 0.55, n1));
	tint = mix(tint, dry_tint, smoothstep(0.58, 0.8, n1 * 0.7 + n2 * 0.3));
	float hollow = clamp(-wpos.y * 0.25, 0.0, 0.3);
	vec3 grass = g.rgb * tint * mix(0.8, 1.15, n2) * (1.0 - hollow);
	vec4 d = texture(dirt_alb, xz * dirt_scale + vec2(0.5));
	vec3 dirt = d.rgb * dirt_tint;
	vec3 rock = r.rgb * rock_tint;
	float slope = 1.0 - wnrm.y;
	float rock_w = clamp(max(sp.g, smoothstep(0.22, 0.42, slope)), 0.0, 1.0);

	vec3 col = mix(grass, grass * moss_tint / max(grass_tint, vec3(0.01)), sp.b * 0.8);
	col = mix(col, g.rgb * ash_tint, sp.a * 0.8);
	float dw = hblend(sp.r, d.a);
	col = mix(col, dirt, dw);
	float rw = hblend(rock_w, r.a);
	col = mix(col, rock, rw);
	// Snow: the ground texture's own light and shade in white, thinner on steep rock
	// and in trampled dirt, with the macro noise leaving a few bare patches.
	float snow = clamp(b_snow[0] * b0 + b_snow[1] * bm.r + b_snow[2] * bm.g + b_snow[3] * bm.b + b_snow[4] * bm.a, 0.0, 1.0);
	float lum = dot(mix(g.rgb, r.rgb, rw), vec3(0.3, 0.59, 0.11));
	vec3 snow_col = vec3(0.5, 0.53, 0.6) * (0.65 + lum * 0.9) * mix(0.85, 1.05, n2);
	float cover = snow * (1.0 - rw * 0.55) * (1.0 - dw * 0.6) * smoothstep(0.2, 0.45, n1 * 0.8 + n2 * 0.4);
	col = mix(col, snow_col, cover);
	float grey = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(vec3(grey), col, grade_saturation);
	col = pow(max(col, vec3(0.0)), vec3(grade_gamma));
	col = mix(col * grade_shadow / 0.16, col, smoothstep(0.0, 0.25, grey));
	ALBEDO = col;
	// Ash lands: the deepest cracks of the open ground glow like cooling embers, in
	// slow-breathing patches (none on roads, rock or snow).
	if (embers > 0.01) {
		float crack = smoothstep(0.38, 0.12, g.a);
		float patch = smoothstep(0.5, 0.75, n1 * 0.6 + n2 * 0.6);
		float breathe = 0.75 + 0.25 * sin(TIME * 0.9 + n1 * 12.0);
		EMISSION = ember_color * 3.2 * embers * crack * patch * breathe * (1.0 - dw) * (1.0 - rw) * (1.0 - cover);
	}

	vec3 nd = texture(dirt_nrm, xz * dirt_scale + vec2(0.5)).rgb;
	vec3 n = mix(mix(ng, nd, dw), nr, rw);
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = mix(0.95, 0.85, rw);
}
