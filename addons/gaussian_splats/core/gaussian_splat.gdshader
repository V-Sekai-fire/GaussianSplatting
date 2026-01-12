shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;

uniform vec3 scale; // log scale, so actual_scale = exp(scale)
uniform float opacity;
uniform vec3 sh_0; // degree 0 coef
uniform float max_scale;

void vertex() {
	// Billboard quad, size based on scale
	vec3 actual_scale = exp(scale);
	float max_scale_val = max(actual_scale.x, max(actual_scale.y, actual_scale.z));
	
	// Billboard rotation to face camera
	mat4 model_view = VIEW_MATRIX * MODEL_MATRIX;
	vec3 right = normalize(vec3(model_view[0][0], model_view[1][0], model_view[2][0]));
	vec3 up = normalize(vec3(model_view[0][1], model_view[1][1], model_view[2][1]));
	vec3 pos = (right * VERTEX.x + up * VERTEX.y) * max_scale_val * 10.0;
	VERTEX = pos;
}

void fragment() {
	vec2 local_pos = VERTEX.xy / (max_scale * 10.0);
	float dist_sq = dot(local_pos, local_pos);
	float gauss = exp(-0.5 * dist_sq);
	
	float alpha = opacity * gauss;
	if (alpha < 0.001) discard;
	
	// Color
	vec3 color = sh_0 * 0.282095 + 0.5;
	color = clamp(color, 0.0, 1.0);
	
	ALBEDO = color;
	ALPHA = alpha;
}