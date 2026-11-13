shader_type spatial;
// Ink outlines (LookFx3D): dark hand-inked contour lines where the depth jumps (silhouettes of
// buildings, trees, units against the ground) and softer lines on creases (roof ridges,
// walls meeting the ground), like the outlined sprites of the main game.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
#include "res://src/ui/look/screen_pass.gdshaderinc"

uniform vec3 ink : source_color = vec3(0.05, 0.035, 0.03);
uniform float width_px = 1.0;
uniform float silhouette = 0.02;  // relative depth jump that counts as an outline
uniform float crease = 0.008;  // relative bend of the depth that counts as a crease
uniform float strength = 1.0;

void fragment() {
	// The same line weight on a high-DPI screen as on a 1080p one.
	vec2 px = width_px * max(1.0, VIEWPORT_SIZE.y / 1080.0) / VIEWPORT_SIZE;
	float c = -VIEW_POS(SCREEN_UV).z;
	float l = -VIEW_POS(SCREEN_UV - vec2(px.x, 0.0)).z;
	float r = -VIEW_POS(SCREEN_UV + vec2(px.x, 0.0)).z;
	float u = -VIEW_POS(SCREEN_UV - vec2(0.0, px.y)).z;
	float d = -VIEW_POS(SCREEN_UV + vec2(0.0, px.y)).z;
	float jump = max(max(abs(c - l), abs(c - r)), max(abs(c - u), abs(c - d))) / c;
	float sil = smoothstep(silhouette, silhouette * 2.0, jump);
	float lap = abs((l + r + u + d) - 4.0 * c) / c;
	float cr = smoothstep(crease, crease * 2.5, lap) * 0.65;
	float far_fade = 1.0 - smoothstep(120.0, 240.0, c);
	ALBEDO = ink;
	ALPHA = clamp(max(sil, cr) * strength * far_fade, 0.0, 1.0);
}
