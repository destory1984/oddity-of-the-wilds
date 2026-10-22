// Glowing cave pool: deep teal with a slowly drifting cell pattern that shimmers.
shader_type spatial;
render_mode unshaded;

uniform vec3 deep : source_color = vec3(0.031, 0.494, 0.588);  // #087E96
uniform vec3 glow : source_color = vec3(0.145, 0.863, 0.910);  // #25DCE8

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz * 3.0 + vec2(TIME * 0.24, TIME * 0.1);
	float n = hash(floor(p)) * 0.6 + hash(floor(p * 0.5 + 7.0)) * 0.4;
	float shimmer = 0.85 + 0.15 * sin(TIME * 1.7 + n * 6.28);
	ALBEDO = mix(deep, glow, n * 0.6) * shimmer * 1.2;
}
