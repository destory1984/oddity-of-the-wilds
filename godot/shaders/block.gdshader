// Terrain block: textured, tinted top face; plain earth on the sides.
shader_type spatial;

uniform sampler2D top_tex : source_color, filter_nearest;
uniform vec3 side_color : source_color = vec3(0.54, 0.42, 0.24);

varying float up;

void vertex() {
	up = NORMAL.y;
}

void fragment() {
	vec3 top = texture(top_tex, UV * 3.0).rgb * COLOR.rgb;
	ALBEDO = up > 0.5 ? top : side_color;
	ROUGHNESS = 1.0;
}
