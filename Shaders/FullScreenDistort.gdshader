shader_type canvas_item;
render_mode unshaded;

// Single screen-reading pass. Distances use viewport-height UV units, keeping
// the lens circular on ultrawide phones without a second viewport copy.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;

uniform vec2 center_uv = vec2(0.5);
uniform float lens_radius : hint_range(0.0, 1.25) = 0.0;
uniform float lens_strength : hint_range(0.0, 0.12) = 0.0;
uniform float effect_opacity : hint_range(0.0, 1.0) = 0.0;
uniform float animation_speed : hint_range(0.0, 2.0) = 0.35;
uniform float motion_scale : hint_range(0.0, 1.0) = 1.0;
uniform int quality : hint_range(0, 2) = 1;

// Compatibility controls for GachaScene, which intentionally reuses this
// shader as a soft full-screen ripple. Gameplay keeps these at zero and uses
// the transparent lens controls above. Keeping the branch here avoids turning
// the gacha reveal into the player sphere or breaking its existing scripts.
uniform float distort_radius : hint_range(0.0, 1.25) = 0.0;
uniform float distort_strength : hint_range(0.0, 0.12) = 0.0;
uniform float distort_speed : hint_range(0.0, 2.0) = 0.0;
uniform float distort_frequency : hint_range(0.5, 10.0) = 5.0;

// The wave field displaces the sampled scene itself; it is not a luminous
// overlay. This keeps the sphere transparent while making gravity visibly
// travel through the glass. The envelope below keeps motion away from both
// the event horizon and the outer silhouette to prevent nausea and UV seams.
uniform float gravity_wave_strength : hint_range(0.0, 0.22) = 0.185;
uniform float gravity_wave_frequency : hint_range(12.0, 52.0) = 19.5;
uniform float gravity_wave_speed : hint_range(1.0, 7.0) = 1.45;
uniform float gravity_wave_twist : hint_range(0.0, 4.0) = 1.75;
uniform float high_quality_chroma_px : hint_range(0.0, 1.25) = 0.72;

uniform float event_horizon_ratio : hint_range(0.08, 0.42) = 0.17;
uniform float event_horizon_softness : hint_range(0.01, 0.12) = 0.045;
uniform float photon_arc_ratio : hint_range(0.12, 0.55) = 0.235;
uniform float photon_arc_width : hint_range(0.003, 0.05) = 0.012;
uniform float photon_arc_energy : hint_range(0.0, 1.5) = 0.58;
uniform vec3 glass_color : source_color = vec3(0.12, 0.78, 0.94);
uniform vec3 cold_arc_color : source_color = vec3(0.28, 0.88, 1.0);
uniform vec3 warm_arc_color : source_color = vec3(1.0, 0.82, 0.46);
uniform vec3 core_color : source_color = vec3(0.0015, 0.004, 0.012);

const float EPSILON = 0.00001;

void fragment() {
	vec2 screen_uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, EPSILON);
	vec2 delta_uv = screen_uv - center_uv;
	vec2 delta_iso = vec2(delta_uv.x * aspect, delta_uv.y);
	float safe_radius = max(lens_radius, EPSILON);
	vec2 sphere_xy = delta_iso / safe_radius;
	float normalized_radius = length(sphere_xy);

	vec4 output_color = vec4(0.0);
	if (lens_radius > EPSILON && normalized_radius < 1.035 && effect_opacity > EPSILON) {
		float sphere_mask = 1.0 - smoothstep(0.965, 1.015, normalized_radius);
		float sphere_depth = sqrt(max(1.0 - normalized_radius * normalized_radius, 0.0));
		vec3 sphere_normal = normalize(vec3(sphere_xy, max(sphere_depth, EPSILON)));
		vec2 direction_iso = sphere_xy / max(normalized_radius, EPSILON);
		vec2 direction_uv = vec2(direction_iso.x / aspect, direction_iso.y);
		float polar_angle = atan(sphere_xy.y, sphere_xy.x);

		// The r*z term behaves like a glass sphere normal. A bounded near-core
		// term adds gravitational lensing without the radial singularity that made
		// the previous effect look like a flat, exploding ring.
		float horizon_guard = smoothstep(
			event_horizon_ratio * 0.72,
			event_horizon_ratio + event_horizon_softness * 1.6,
			normalized_radius
		);
		float glass_curve = normalized_radius * sphere_depth;
		float gravity_curve = (event_horizon_ratio + 0.17) /
			max(normalized_radius, event_horizon_ratio + 0.035);
		gravity_curve *= 1.0 - smoothstep(0.62, 0.98, normalized_radius);
		float glass_bend = -lens_strength * glass_curve * 0.72;
		float gravity_bend = lens_strength * gravity_curve * horizon_guard * 0.22;

		// Two coherent SIN layers form a travelling gravitational wave instead of
		// merely modulating the static bend. A third, fine harmonic is reserved for
		// High quality. All layers affect UV displacement only, so they cannot form
		// the opaque purple ring used by the legacy sprite.
		float wave_inner_edge = event_horizon_ratio + event_horizon_softness * 0.65;
		float wave_inner_fade = event_horizon_ratio + 0.145;
		float wave_envelope = smoothstep(
			wave_inner_edge,
			wave_inner_fade,
			normalized_radius
		);
		wave_envelope *= 1.0 - smoothstep(0.72, 0.955, normalized_radius);
		wave_envelope *= sphere_mask;

		float wave_time = TIME * animation_speed * gravity_wave_speed;
		float primary_wave = sin(
			normalized_radius * gravity_wave_frequency - wave_time
		);
		float twisted_wave = sin(
			normalized_radius * gravity_wave_frequency * 1.78
			+ polar_angle * gravity_wave_twist
			- wave_time * 1.37
			+ 1.25
		);
		float wave_field = primary_wave + twisted_wave * 0.32;
		if (quality >= 2) {
			float fine_harmonic = sin(
				normalized_radius * gravity_wave_frequency * 2.62
				- polar_angle * 2.4
				- wave_time * 1.73
				+ 2.35
			);
			wave_field += fine_harmonic * 0.14;
		}

		float wave_bend = lens_strength * gravity_wave_strength;
		wave_bend *= wave_field * wave_envelope * motion_scale;
		float radial_bend = (glass_bend + gravity_bend) * sphere_mask + wave_bend;
		radial_bend = clamp(radial_bend, -safe_radius * 0.10, safe_radius * 0.10);
		vec2 tangent_iso = vec2(-direction_iso.y, direction_iso.x);
		float swirl_bend = lens_strength * gravity_wave_strength * 0.24;
		swirl_bend *= twisted_wave * wave_envelope * motion_scale;
		vec2 offset_iso = direction_iso * radial_bend + tangent_iso * swirl_bend;
		vec2 offset_uv = vec2(offset_iso.x / aspect, offset_iso.y);

		vec2 warped_uv = clamp(
			screen_uv + offset_uv,
			SCREEN_PIXEL_SIZE * 0.5,
			vec2(1.0) - SCREEN_PIXEL_SIZE * 0.5
		);

		// Low/medium quality use one screen lookup; high quality uses three.
		// Chromatic separation follows the refracted background, is strongest only
		// inside the moving wave envelope, and remains below a configurable pixel
		// cap so it reads as optics rather than a neon outline.
		vec3 warped_color;
		if (quality >= 2) {
			float max_pixel_size = max(SCREEN_PIXEL_SIZE.x, SCREEN_PIXEL_SIZE.y);
			float pixel_cap = high_quality_chroma_px * max_pixel_size;
			float wave_chroma = abs(wave_field) * wave_envelope;
			float chroma_offset = length(offset_uv) * 0.028;
			chroma_offset += max_pixel_size * high_quality_chroma_px * wave_chroma * 0.24;
			chroma_offset = min(chroma_offset, pixel_cap);
			vec2 chroma_uv = direction_uv * chroma_offset;
			warped_color.r = texture(screen_texture, clamp(warped_uv + chroma_uv, vec2(0.0), vec2(1.0))).r;
			warped_color.g = texture(screen_texture, warped_uv).g;
			warped_color.b = texture(screen_texture, clamp(warped_uv - chroma_uv, vec2(0.0), vec2(1.0))).b;
		} else {
			warped_color = texture(screen_texture, warped_uv).rgb;
		}

		// Reconstructing a sphere normal gives the transparent lens real 2.5D
		// volume. The rim is deliberately dim and asymmetric: no uniform purple
		// donut, only a cold glass crescent and a small upper-left glint.
		float fresnel = pow(clamp(1.0 - sphere_normal.z, 0.0, 1.0), 3.2) * sphere_mask;
		vec3 light_direction = normalize(vec3(-0.52, -0.62, 0.78));
		float specular = pow(max(dot(sphere_normal, light_direction), 0.0), 52.0);
		float sharp_glint = pow(max(dot(sphere_normal, light_direction), 0.0), 110.0);
		float cold_crescent = fresnel * pow(max(dot(direction_iso, normalize(vec2(-0.72, -0.69))), 0.0), 2.8);
		float shaded_limb = fresnel * pow(max(dot(direction_iso, normalize(vec2(0.68, 0.74))), 0.0), 2.0);
		float pixel_aa = max(1.5 * SCREEN_PIXEL_SIZE.y / safe_radius, 0.003);
		float outer_rim = 1.0 - smoothstep(
			pixel_aa,
			pixel_aa + 0.018,
			abs(normalized_radius - 0.972)
		);
		float warm_outer_arc = outer_rim * pow(max(dot(direction_iso, normalize(vec2(-0.78, -0.62))), 0.0), 6.0);
		float cold_outer_arc = outer_rim * pow(max(dot(direction_iso, normalize(vec2(0.78, 0.62))), 0.0), 10.0);

		float event_horizon = 1.0 - smoothstep(
			event_horizon_ratio * 0.72,
			event_horizon_ratio + event_horizon_softness,
			normalized_radius
		);
		float core_halo = 1.0 - smoothstep(
			event_horizon_ratio,
			event_horizon_ratio + event_horizon_softness * 2.6,
			normalized_radius
		);

		float arc_distance = abs(normalized_radius - photon_arc_ratio);
		float photon_arc = 1.0 - smoothstep(photon_arc_width * 0.28, photon_arc_width, arc_distance);
		float warm_facing = pow(max(dot(direction_iso, normalize(vec2(-0.82, -0.57))), 0.0), 5.0);
		float cold_facing = pow(max(dot(direction_iso, normalize(vec2(0.74, 0.67))), 0.0), 4.0);
		float broken_arc = photon_arc * (warm_facing + cold_facing * 0.46);
		float arc_mix = warm_facing / max(warm_facing + cold_facing, EPSILON);
		vec3 arc_color = mix(cold_arc_color, warm_arc_color, arc_mix);
		float shimmer = 1.0 + sin(TIME * animation_speed * 4.8) * 0.055 * motion_scale;

		vec3 lens_color = warped_color;
		float light_wrap = clamp(dot(sphere_normal, light_direction) * 0.5 + 0.5, 0.0, 1.0);
		lens_color *= mix(0.92, 1.025, light_wrap);
		lens_color *= 1.0 - fresnel * 0.13 - shaded_limb * 0.08;
		lens_color = mix(lens_color, lens_color * glass_color * 1.18, fresnel * 0.08);
		lens_color *= mix(1.0, 0.23, event_horizon);
		lens_color += core_color * event_horizon * 0.35;
		lens_color += glass_color * core_halo * (1.0 - event_horizon) * 0.035;
		lens_color += glass_color * cold_crescent * 0.18;
		lens_color += mix(glass_color, vec3(0.92, 0.98, 1.0), 0.72) * specular * 0.11;
		lens_color += vec3(1.0, 0.98, 0.91) * sharp_glint * 0.22;
		lens_color += warm_arc_color * warm_outer_arc * 0.30;
		lens_color += cold_arc_color * cold_outer_arc * 0.22;
		lens_color += arc_color * broken_arc * photon_arc_energy * shimmer;

		float glass_alpha = mix(0.72, 0.94, fresnel);
		float alpha = clamp(sphere_mask * effect_opacity * glass_alpha, 0.0, 1.0);
		output_color = vec4(lens_color, alpha);
	} else if (distort_radius > EPSILON) {
		// Legacy full-screen reveal ripple. Its outside alpha is deliberately zero,
		// so the shared shader never lays an invisible opaque quad over HUD content.
		vec2 legacy_delta = screen_uv - center_uv;
		vec2 legacy_iso = vec2(legacy_delta.x * aspect, legacy_delta.y);
		float legacy_distance = length(legacy_iso);
		if (legacy_distance < distort_radius) {
			float legacy_falloff = 1.0 - smoothstep(
				distort_radius * 0.60,
				distort_radius,
				legacy_distance
			);
			float legacy_wave = sin(
				legacy_distance * distort_frequency - TIME * distort_speed
			);
			vec2 legacy_direction_iso = legacy_iso / max(legacy_distance, EPSILON);
			vec2 legacy_direction_uv = vec2(legacy_direction_iso.x / aspect, legacy_direction_iso.y);
			vec2 legacy_uv = clamp(
				screen_uv + legacy_direction_uv * legacy_wave * distort_strength * legacy_falloff,
				SCREEN_PIXEL_SIZE * 0.5,
				vec2(1.0) - SCREEN_PIXEL_SIZE * 0.5
			);
			output_color = vec4(texture(screen_texture, legacy_uv).rgb, legacy_falloff);
		}
	}

	COLOR = output_color;
}
