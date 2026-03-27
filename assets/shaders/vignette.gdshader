shader_type canvas_item;

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;
uniform float vignette_radius   : hint_range(0.1, 1.0) = 0.72;
uniform float vignette_softness : hint_range(0.01, 0.5) = 0.3;

void fragment() {
	vec2 uv = UV - vec2(0.5, 0.5);
	float dist = length(uv);
	float vignette = smoothstep(vignette_radius - vignette_softness, vignette_radius, dist);
	COLOR = vec4(0.0, 0.0, 0.0, vignette * vignette_strength);
}
