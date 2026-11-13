shader_type spatial;
// Living land (LookFx3D): wisps of mist pooling in the low ground and drifting slowly,
// lit warm on top by the sun. Thin enough to read the units through.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
#include "res://src/ui/look/screen_pass.gdshaderinc"

uniform vec3 mist : source_color = vec3(0.72, 0.74, 0.8);
uniform float top_m = 0.8;  // mist lies below this height
uniform float strength = 0.26;

void fragment() {
	vec3 v = VIEW_POS(SCREEN_UV);
	vec3 w = (INV_VIEW_MATRIX * vec4(v, 1.0)).xyz;
	float n = fbm(w.xz * 0.06 + vec2(TIME * 0.02, TIME * 0.008));
	float wisps = smoothstep(0.48, 0.8, n);
	float low = 1.0 - smoothstep(top_m - 1.5, top_m, w.y);
	ALBEDO = mist;
	ALPHA = wisps * low * strength * (texture(depth_texture, SCREEN_UV).r < 0.99999 ? 1.0 : 0.0);
}
