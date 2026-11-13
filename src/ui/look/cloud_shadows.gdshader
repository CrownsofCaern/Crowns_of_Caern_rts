shader_type spatial;
// Living land (LookFx3D): shadows of clouds drifting over the land (world-space noise
// projected along the sun), so the light moves across the map like a real afternoon.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
#include "res://src/ui/look/screen_pass.gdshaderinc"

uniform float scale = 0.022;
uniform vec2 wind = vec2(0.9, 0.35);
uniform float cover = 0.44;
uniform float strength = 0.5;  // set by LookFx3D (less under an overcast sky)
uniform vec3 shade : source_color = vec3(0.02, 0.03, 0.08);

void fragment() {
	vec3 v = VIEW_POS(SCREEN_UV);
	vec3 w = (INV_VIEW_MATRIX * vec4(v, 1.0)).xyz;
	vec2 p = (w.xz + w.y * vec2(0.7, 0.6)) * scale + wind * TIME * 0.04;
	float n = fbm(p);
	float k = smoothstep(cover, cover + 0.12, n) * strength;
	ALBEDO = shade;
	ALPHA = k * (texture(depth_texture, SCREEN_UV).r < 0.99999 ? 1.0 : 0.0);
}
