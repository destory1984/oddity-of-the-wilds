// Cave stone: three close slate tones picked per 0.25 m cell in world space,
// darker toward the foot of each block so walls read as stacked stone.
shader_type spatial;

uniform vec3 c0 : source_color = vec3(0.063, 0.106, 0.188); // #101B30
uniform vec3 c1 : source_color = vec3(0.078, 0.149, 0.255); // #142641
uniform vec3 c2 : source_color = vec3(0.098, 0.200, 0.294); // #19334B
uniform float lift = 1.6; // the palette is very dark; lift it so ambient light can show it

varying vec3 wpos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cell = floor(wpos * 4.0);
	float h = hash(cell);
	vec3 col = h < 0.34 ? c0 : (h < 0.67 ? c1 : c2);
	float foot = clamp(fract(wpos.y) * 1.5 + 0.35, 0.65, 1.0);
	ALBEDO = col * lift * COLOR.rgb * foot;
	ROUGHNESS = 0.9;
}
