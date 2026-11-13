shader_type spatial;
// Rain, snow or falling ash as one MultiMesh of small quads. Nothing is simulated:
// each instance's transform origin is a fixed point in a unit box, and the vertex shader
// turns it into a drop that falls with TIME and wraps round a box that follows the camera.
// Cheap on every renderer (Compatibility included) and on phones.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 center = vec3(0.0);  // middle of the box, world space (follows the camera target)
uniform vec3 box = vec3(60.0, 26.0, 60.0);  // metres
uniform float speed = 14.0;  // fall speed, m/s
uniform vec2 wind = vec2(1.5, 0.6);  // sideways drift, m/s (x, z)
uniform float drop_length = 0.9;  // streak length (rain) or flake size (snow, ash)
uniform float drop_width = 0.025;
uniform bool streak = true;  // true: streaks along the fall; false: round flakes facing the camera
uniform float sway = 0.0;  // flakes drift side to side, metres
uniform vec4 tint : source_color = vec4(0.62, 0.66, 0.74, 0.32);
uniform vec4 ember : source_color = vec4(1.0, 0.35, 0.08, 0.0);  // a few glowing flakes (ash); alpha 0 = none
uniform float flash = 0.0;  // lightning lights the drops up

varying float v_fade;
varying float v_ember;

void vertex() {
	vec3 u = MODEL_MATRIX[3].xyz;  // 0..1, fixed per instance
	float h1 = fract(u.x * 31.71 + u.z * 17.13);
	float h2 = fract(u.y * 23.37 + u.x * 11.91);
	float t = TIME * (0.8 + 0.4 * h1);
	vec3 p;
	p.y = mod(u.y * box.y - t * speed, box.y);
	p.x = u.x * box.x + wind.x * t + sin(TIME * 1.3 + h2 * 40.0) * sway;
	p.z = u.z * box.z + wind.y * t + cos(TIME * 1.1 + h1 * 40.0) * sway;
	// Wrap round the camera: world positions stay put while the box slides over them.
	vec3 base = center - box * 0.5;
	p.x = base.x + mod(p.x - base.x, box.x);
	p.z = base.z + mod(p.z - base.z, box.z);
	p.y = base.y + p.y;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 along;
	vec3 side;
	if (streak) {
		along = -normalize(vec3(wind.x, -speed, wind.y));
		side = normalize(cross(along, cam - p));
	} else {
		along = INV_VIEW_MATRIX[1].xyz;
		side = INV_VIEW_MATRIX[0].xyz;
	}
	float w = streak ? drop_width : drop_length;
	vec3 world = p + side * VERTEX.x * w + along * VERTEX.y * drop_length;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
	// Fade in at the top and out near the edges of the box, so wrapping never pops.
	float fy = (p.y - base.y) / box.y;
	vec2 fxz = abs((p.xz - center.xz) / (box.xz * 0.5));
	v_fade = smoothstep(0.0, 0.08, fy) * smoothstep(1.0, 0.8, fy) * smoothstep(1.0, 0.75, max(fxz.x, fxz.y));
	v_ember = step(h2, 0.08) * ember.a;
}

void fragment() {
	float a;
	if (streak) {
		a = 1.0 - abs(UV.x * 2.0 - 1.0);
		a *= smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.6, UV.y);
	} else {
		a = clamp(1.0 - length(UV * 2.0 - 1.0), 0.0, 1.0) * 1.6;
	}
	vec3 c = mix(tint.rgb, ember.rgb * 2.5, v_ember) + vec3(0.7, 0.75, 0.9) * flash;
	ALBEDO = c;
	ALPHA = clamp(a * mix(tint.a, 0.9, v_ember) * v_fade * (1.0 + flash), 0.0, 1.0);
}
