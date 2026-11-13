shader_type spatial;
// Fog of war as a full-screen pass: rebuilds each pixel's ground position from the
// depth buffer and darkens it by the player's fog texture (alpha: 1 unexplored,
// about 0.55 explored, 0 in sight). Works with the Compatibility renderer, which has no decals.
// The fog texture has one texel per 2 m vision cell; a small blur and slow drifting
// noise turn its steps into a soft, smoky edge, and the dark is a cool night blue
// rather than flat black, so the hidden land still reads as land.
// Skirmish fog marks land never explored with grey texels (red > 0): there the picture
// is shown greyed out (desaturated and dimmed) instead of dark; the view hides what stands on it.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D fog : filter_linear, repeat_disable;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float grey_ref = 0.376;  // the red of a grey (never explored) texel, Skirmish.FOG_GREY
uniform float grey_light = 0.62;  // brightness of the greyed land
uniform vec2 map_size = vec2(100.0);  // metres covered by the fog texture, from world (0, 0)
uniform bool gl_depth = true;  // OpenGL depth runs -1..1 in NDC
uniform float edge_m = 3.0;  // blur radius of the fog edge, metres
uniform vec3 shade : source_color = vec3(0.012, 0.016, 0.03);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

void fragment() {
	float d = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = gl_depth ? vec3(SCREEN_UV, d) * 2.0 - 1.0 : vec3(SCREEN_UV * 2.0 - 1.0, d);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	float a = 0.0;
	float g = 0.0;
	// Scenery beyond the map's edge takes the fog of the nearest edge cell, so a home in a
	// corner is not framed by a lit forest around a black field.
	if (d < 0.99999) {
		// Drifting smoke bends the edge a little before the blur.
		vec2 drift = vec2(noise(world.xz * 0.12 + TIME * 0.05), noise(world.xz * 0.12 - TIME * 0.04 + 17.0)) - 0.5;
		vec2 c = clamp((world.xz + drift * 2.5) / map_size, vec2(0.0), vec2(1.0));
		vec2 r = vec2(edge_m) / map_size;
		vec4 f = texture(fog, c) * 0.2;
		f += texture(fog, c + vec2(r.x, 0.0)) * 0.1;
		f += texture(fog, c - vec2(r.x, 0.0)) * 0.1;
		f += texture(fog, c + vec2(0.0, r.y)) * 0.1;
		f += texture(fog, c - vec2(0.0, r.y)) * 0.1;
		f += texture(fog, c + r * 0.7) * 0.1;
		f += texture(fog, c - r * 0.7) * 0.1;
		f += texture(fog, c + vec2(r.x, -r.y) * 0.7) * 0.1;
		f += texture(fog, c + vec2(-r.x, r.y) * 0.7) * 0.1;
		float smoke = noise(world.xz * 0.35 + TIME * vec2(0.06, 0.03));
		g = clamp(f.r / grey_ref, 0.0, 1.0);
		// A grey texel's own alpha stands for "fully greyed", not for darkness.
		a = clamp(mix(f.a, 1.0, g) * (0.92 + 0.16 * smoke * (1.0 - g)), 0.0, 1.0);
	}
	vec3 under = textureLod(screen, SCREEN_UV, 0.0).rgb;
	float luma = dot(under, vec3(0.299, 0.587, 0.114));
	vec3 grey = vec3(luma) * grey_light * vec3(0.96, 0.98, 1.04) + shade;
	ALBEDO = mix(shade, grey, a > 0.001 ? clamp(g / a, 0.0, 1.0) : 0.0);
	ALPHA = a;
}
