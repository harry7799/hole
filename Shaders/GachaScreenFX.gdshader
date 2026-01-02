shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

uniform vec2 center_uv = vec2(0.5, 0.5);
uniform float radial_blur_strength = 0.0; // 0..1
uniform float chroma_aberration = 0.0;    // 0..1
uniform vec4 tint = vec4(1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - center_uv;
	float dist = length(d);
	vec2 dir = (dist > 0.0001) ? (d / dist) : vec2(0.0);

	// Radial blur: small number of taps for mobile.
	float s = clamp(radial_blur_strength, 0.0, 1.0);
	vec2 step_uv = dir * (0.012 * s);
	vec4 col = vec4(0.0);
	col += texture(screen_texture, uv);
	col += texture(screen_texture, uv - step_uv * 1.0);
	col += texture(screen_texture, uv - step_uv * 2.0);
	col += texture(screen_texture, uv - step_uv * 3.0);
	col += texture(screen_texture, uv - step_uv * 4.0);
	col *= (1.0 / 5.0);

	// Chromatic aberration: subtle offset growing with distance.
	float ca = clamp(chroma_aberration, 0.0, 1.0);
	vec2 ca_off = dir * (0.0035 * ca) * smoothstep(0.0, 0.8, dist);
	float r = texture(screen_texture, uv + ca_off).r;
	float g = col.g;
	float b = texture(screen_texture, uv - ca_off).b;

	COLOR = vec4(r, g, b, 1.0) * tint;
}
