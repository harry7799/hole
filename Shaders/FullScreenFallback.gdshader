shader_type canvas_item;

/*
Multi-layer Fullscreen Fallback

Features:
- Pseudo multi-layer radial waves (no SCREEN_TEXTURE sampling)
- Event Horizon (central dark core) with soft edge
- Chroma Split (RGB fringe simulated by offsetting wave layers)

Uniforms are exposed for runtime tuning on mobile.
*/

uniform vec2 center_uv : hint_range(0.0, 1.0) = vec2(0.5, 0.5);
uniform float radius : hint_range(0.0, 2.0) = 0.5;
uniform float strength : hint_range(0.0, 2.0) = 0.8;
uniform float speed : hint_range(0.0, 6.0) = 1.2;
uniform vec4 tint_color : hint_color = vec4(1.0, 0.7, 0.25, 0.5);

// Event horizon (central black core)
uniform float event_radius : hint_range(0.0, 1.0) = 0.12;
uniform float event_softness : hint_range(0.0, 0.5) = 0.06;
uniform float event_strength : hint_range(0.0, 1.0) = 1.0;

// Chroma split amount (simulated fringe)
uniform float chroma_amount : hint_range(0.0, 0.1) = 0.018;
uniform float edge_softness : hint_range(0.0, 0.5) = 0.08;

// Noise + layering controls
uniform float noise_scale : hint_range(0.1, 10.0) = 2.5;
uniform float layer_mix : hint_range(0.0, 1.0) = 0.6; // balance base vs detail

// Performance quality: 0.0 (low) .. 1.0 (high) - can be used by host to lower cost
uniform float perf_quality : hint_range(0.0, 1.0) = 1.0;

// Simple hash / noise helpers
float hash21(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float noise2(vec2 p){
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash21(i + vec2(0.0,0.0));
    float b = hash21(i + vec2(1.0,0.0));
    float c = hash21(i + vec2(0.0,1.0));
    float d = hash21(i + vec2(1.0,1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a)*u.y*(1.0 - u.x) + (d - b)*u.x*u.y;
}

// Radial wave function at a UV (used to create layered ripples)
float radial_wave(vec2 uv, float freq, float phase){
    float d = length(uv - center_uv);
    return (sin(d * freq - TIME * speed + phase) * 0.5 + 0.5);
}

void fragment(){
    vec2 uv = UV;
    vec2 diff = uv - center_uv;
    float dist = length(diff);
    vec2 dir = dist > 0.0001 ? diff / dist : vec2(0.0);

    // Falloff mask (1.0 at center, 0.0 outside radius)
    float fall = 1.0 - smoothstep(radius - edge_softness, radius, dist);

    // Noise perturbation scaled by performance quality
    float n = noise2(uv * noise_scale + TIME * 0.08) - 0.5;
    float noise_strength = 0.02 * (1.0 - perf_quality) + 0.01 * perf_quality;
    vec2 uv_pert = uv + dir * n * noise_strength;

    // Multi-layer waves (three layers blended)
    float l1 = radial_wave(uv_pert, 30.0, 0.0);
    float l2 = radial_wave(uv_pert, 60.0, 1.3) * 0.6;
    float l3 = radial_wave(uv_pert, 110.0, 2.9) * 0.35;
    float wave = mix(l1, l2, layer_mix) * 0.7 + l3 * 0.3;
    wave *= mix(1.0, 0.75, 1.0 - perf_quality);

    float base_intensity = clamp(wave * strength * fall, 0.0, 1.0);

    // Chroma split simulation: evaluate wave at small shifted UVs for R/G/B
    float chroma = chroma_amount;
    // scale chroma inversely with distance from center to keep fringe near edges
    float chroma_factor = chroma * (1.0 - smoothstep(0.0, radius, dist));
    vec2 shift = dir * chroma_factor;

    float r = radial_wave(uv_pert + shift * 0.9, 34.0, 0.1);
    float g = radial_wave(uv_pert, 44.0, 0.4);
    float b = radial_wave(uv_pert - shift * 0.9, 54.0, 0.9);

    // Combine base intensity with chroma channels
    float cr = clamp(base_intensity + (r - wave) * 0.8, 0.0, 1.0);
    float cg = clamp(base_intensity + (g - wave) * 0.6, 0.0, 1.0);
    float cb = clamp(base_intensity + (b - wave) * 0.8, 0.0, 1.0);

    vec3 tint_rgb = tint_color.rgb;
    vec3 final_rgb = vec3(cr * tint_rgb.r, cg * tint_rgb.g, cb * tint_rgb.b);

    // Event horizon: darken center strongly with a soft edge
    float core_mask = 1.0 - smoothstep(event_radius - event_softness, event_radius, dist);
    core_mask = clamp(core_mask, 0.0, 1.0);
    final_rgb *= (1.0 - core_mask * event_strength);

    // Final alpha blends tint presence; keep small base alpha so effect is translucent
    float alpha = tint_color.a * clamp(base_intensity * 1.1 + 0.02, 0.0, 1.0);

    COLOR = vec4(final_rgb, alpha);
}
