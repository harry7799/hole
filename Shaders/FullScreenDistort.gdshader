shader_type canvas_item;

// Safer FullScreenDistort for WebGL / Safari: avoid out-of-range sampling and reduce dependency on mipmaps.
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

// Parameters controlled from GDScript
uniform vec2 center_uv = vec2(0.5, 0.5);
uniform float distort_radius : hint_range(0.0, 1.0) = 0.0;
uniform float distort_strength : hint_range(0.0, 0.1) = 0.0;
uniform float distort_speed : hint_range(0.0, 2.0) = 0.0;
uniform float distort_frequency : hint_range(0.5, 10.0) = 5.0;

void fragment() {
    vec2 uv = UV;

    vec4 original = texture(SCREEN_TEXTURE, uv);
    vec4 out_col = original;

    // Fast-path: if radius is effectively zero just sample normally
    if (distort_radius > 0.0001) {

        // Compute aspect safely
        float aspect = 1.0;
        if (SCREEN_PIXEL_SIZE.y > 0.0) {
            aspect = SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y;
        }

        vec2 diff_uv = uv - center_uv;
        vec2 diff_corrected = diff_uv;
        diff_corrected.x *= aspect;

        float dist = length(diff_corrected);

        // Wave and falloff (kept conservative)
        float wave = sin(max(dist, 0.0) * max(distort_frequency, 0.0) - TIME * max(distort_speed, 0.0));
        float distort_range_start = distort_radius * 0.6;
        float radius_falloff = 1.0 - smoothstep(distort_range_start, distort_radius, dist);

        float offset_mag = wave * distort_strength * radius_falloff;
        vec2 offset_dir_corrected = (dist > 0.00001) ? (diff_corrected / dist) : vec2(0.0);
        vec2 final_offset = offset_dir_corrected * offset_mag;
        final_offset.x /= aspect;

        vec2 sample_uv = uv + final_offset;

        // Clamp sample_uv inside a safe interior region to avoid sampling outside the screen
        sample_uv = clamp(sample_uv, vec2(0.002), vec2(0.998));

        // Primary sample and a soft blend back to original to reduce edge artifacts
        vec4 sampled = texture(SCREEN_TEXTURE, sample_uv);
        float blend = clamp(radius_falloff * 3.0, 0.0, 1.0); // small blending factor
        out_col = mix(original, sampled, blend);
    }

    COLOR = out_col;
}