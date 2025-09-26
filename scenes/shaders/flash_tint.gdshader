shader_type canvas_item;

uniform vec4 tint : source_color = vec4(1.0);
uniform float desaturate : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color = vec3(1.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float g = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	col.rgb = mix(col.rgb, vec3(g), desaturate);
	col.rgb *= tint.rgb;
	col.rgb = mix(col.rgb, flash_color, flash);
	col.a *= opacity;
	COLOR = col;
}
