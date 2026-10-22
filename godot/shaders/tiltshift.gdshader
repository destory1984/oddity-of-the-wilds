// Full-screen pass: tilt-shift blur away from a horizontal focus band,
// a warm grade, a little extra saturation and a soft vignette.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float focus = 0.45;
uniform float amount = 6.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float r = smoothstep(0.12, 0.5, abs(uv.y - focus)) * amount;
	vec4 c = vec4(0.0);
	for (int i = 0; i < 24; i++) {
		float a = float(i) * 2.39996;
		float rr = sqrt(float(i) / 24.0);
		c += texture(screen_tex, uv + vec2(cos(a), sin(a)) * rr * r * SCREEN_PIXEL_SIZE);
	}
	c /= 24.0;
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(vec3(l), c.rgb, 1.18);
	c.rgb *= vec3(1.04, 1.0, 0.93);
	vec2 v = uv - 0.5;
	c.rgb *= 1.0 - dot(v, v) * 0.45;
	COLOR = vec4(c.rgb, 1.0);
}
