shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 0.67, 0.0, 1.0);
uniform float outline_width : hint_range(0.5, 4.0) = 1.5;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	if (color.a > 0.01) {
		COLOR = color;
		return;
	}
	vec2 texel = outline_width / vec2(textureSize(TEXTURE, 0));
	float alpha = 0.0;
	alpha = max(alpha, texture(TEXTURE, UV + vec2( texel.x,       0.0)).a);
	alpha = max(alpha, texture(TEXTURE, UV + vec2(-texel.x,       0.0)).a);
	alpha = max(alpha, texture(TEXTURE, UV + vec2(      0.0,  texel.y)).a);
	alpha = max(alpha, texture(TEXTURE, UV + vec2(      0.0, -texel.y)).a);
	alpha = max(alpha, texture(TEXTURE, UV + vec2( texel.x,  texel.y)).a);
	alpha = max(alpha, texture(TEXTURE, UV + vec2(-texel.x,  texel.y)).a);
	alpha = max(alpha, texture(TEXTURE, UV + vec2( texel.x, -texel.y)).a);
	alpha = max(alpha, texture(TEXTURE, UV + vec2(-texel.x, -texel.y)).a);
	COLOR = vec4(outline_color.rgb, outline_color.a * alpha);
}
