// Pixel water with a slowly drifting pattern.
shader_type spatial;
render_mode cull_back;

uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform float tiles = 16.0;

void fragment() {
	vec2 uv = UV * tiles + vec2(TIME * 0.24, TIME * 0.16);
	ALBEDO = texture(tex, uv).rgb;
	ALPHA = 0.88;
	ROUGHNESS = 0.6;
}
