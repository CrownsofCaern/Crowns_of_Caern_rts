shader_type spatial;
// Lit battle sprite for SpriteUnit: a camera-facing billboard that takes the scene's
// sun, ambient light, fog and shadows like the 3D models, so the flat painted art
// sits in the dark world instead of glowing. The normal leans between "towards the
// camera" and "up", and the wrapped diffuse keeps a sun from behind from blacking it out.
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D sheet : source_color, filter_nearest;
// 1 = always face the camera; 0 = keep the node's own orientation (a corpse lying flat).
uniform float billboard = 1.0;
// How far the normal tips up from facing the camera (0 = flat card, 1 = lit from the sky).
uniform float normal_up = 0.55;
// Overall brightness of the art under the scene light.
uniform float exposure = 1.0;
// Ascendant (veteran level 5) only, on its own material (SpriteUnit.set_ascendant):
// aura = strength of a pulsing glowing outline one texel wide round the figure;
// dissolve = 0..1 while it falls: pixels burn away in light (bright rim on the edge).
uniform float aura = 0.0;
uniform float dissolve = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.8, 0.38);
// A dark one-texel ink outline round the figure (the art bible's outlined sprites);
// SpriteUnit.set_ink() turns it off with the "Ink outlines" setting.
uniform float ink = 1.0;
uniform vec3 ink_color : source_color = vec3(0.04, 0.03, 0.025);

float pixel_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	if (billboard > 0.5) {
		mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		bb = bb * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * bb;
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec4 c = texture(sheet, UV) * COLOR;
	float rim = 0.0;
	if (c.a < 0.5) {
		if (aura <= 0.0 && ink <= 0.0) {
			discard;
		}
		vec2 ts = 1.0 / vec2(textureSize(sheet, 0));
		float n = max(max(texture(sheet, UV + vec2(ts.x, 0.0)).a, texture(sheet, UV - vec2(ts.x, 0.0)).a),
			max(texture(sheet, UV + vec2(0.0, ts.y)).a, texture(sheet, UV - vec2(0.0, ts.y)).a));
		if (n < 0.5) {
			discard;
		}
		rim = 1.0;
	}
	vec3 glow = vec3(0.0);
	if (aura > 0.0) {
		float pulse = 0.65 + 0.35 * sin(TIME * 2.6);
		glow = glow_color * (rim * 1.4 * pulse + 0.06) * aura;
	}
	if (dissolve > 0.0) {
		vec2 px = floor(UV * vec2(textureSize(sheet, 0)));
		float h = pixel_hash(px);
		if (h < dissolve) {
			discard;
		}
		glow += glow_color * (h < dissolve + 0.14 ? 3.0 : dissolve * 1.2);
	}
	EMISSION = (rim > 0.5 && aura <= 0.0) ? vec3(0.0) : glow;
	ALBEDO = rim > 0.5 ? (aura > 0.0 ? glow_color * 0.4 : ink_color) : c.rgb * exposure;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	if (billboard > 0.5) {
		vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		NORMAL = normalize(mix(vec3(0.0, 0.0, 1.0), up, normal_up));
	}
}
