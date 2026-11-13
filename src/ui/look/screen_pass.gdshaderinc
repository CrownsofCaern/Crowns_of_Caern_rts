// Shared bits of the full-screen look passes (LookFx3D): a quad that covers the screen and
// the world position / view depth of the pixel underneath (from the depth buffer).
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform bool gl_depth = true;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// The depth texture can only be read inside fragment() on the Compatibility renderer
// (helper functions are also compiled into the vertex stage), hence the macro.
#define VIEW_POS(uv) view_from_depth(uv, texture(depth_texture, uv).r, INV_PROJECTION_MATRIX)

vec3 view_from_depth(vec2 uv, float d, mat4 inv_proj) {
	vec3 ndc = gl_depth ? vec3(uv, d) * 2.0 - 1.0 : vec3(uv * 2.0 - 1.0, d);
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += vnoise(p) * a;
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return s;
}
