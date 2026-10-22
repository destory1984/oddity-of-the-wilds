// Swaying grass / cattail tufts drawn as crossed quads in a MultiMesh.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D tex : source_color, filter_nearest;
uniform float strength = 0.12;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float s = sin(TIME * 1.7 + o.x * 0.6 + o.z * 0.4) + 0.4 * sin(TIME * 3.1 + o.x * 1.3);
	VERTEX.x += s * strength * VERTEX.y;
	VERTEX.z += s * strength * 0.5 * VERTEX.y;
	NORMAL = vec3(0.0, 1.0, 0.0); // even, soft lighting on both sides
}

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
