shader_type spatial;
// A full-screen pass that darkens the corners of the 3D view (and tints them a little),
// so the eye goes to the middle of the field. Strength follows the weather.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform float strength = 0.4;
uniform vec4 tint : source_color = vec4(0.05, 0.0, 0.01, 1.0);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.25, 1.0);
	float v = smoothstep(0.25, 0.85, length(d));
	ALBEDO = tint.rgb;
	ALPHA = v * strength;
}
