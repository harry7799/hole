shader_type canvas_item;

// 必須有這行才能讀取螢幕畫面
// WebGL/iOS Safari: screen texture does not provide mipmaps; mipmap filtering can return black.
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

// ----------------------------------------------------
// GDScript 傳遞的參數 (完美圓形/中心點/不穩定度)
// ----------------------------------------------------
uniform vec2 center = vec2(0.5, 0.5);   // 黑洞全局 UV 位置 (由 GDScript 傳遞)
uniform float aspect_ratio = 1.0;       // 【關鍵修正】螢幕長寬比 (高/寬) (由 GDScript 傳遞)
uniform float tint_intensity : hint_range(0.0, 2.0) = 0.0; // 不穩定紅光

// ----------------------------------------------------
// 可編輯的 Shader 參數
// ----------------------------------------------------
uniform float radius = 0.4;     // 扭曲範圍 (由 GDScript 動態調整)
uniform float strength = 0.05;  // 扭曲強度
uniform float aberration = 0.02; // 色差強度
uniform vec3 rim_color = vec3(0.0, 0.0, 0.0);  // 邊緣光暈顏色 (Phase 4B 視覺進化)
uniform float rim_intensity : hint_range(0.0, 1.5) = 0.0; // 邊緣光暈強度

void fragment() {
    vec2 uv = UV;
    vec2 diff = uv - center;
    
    // 【修正 1：長寬比修正】強制 Y 軸縮放來修正 Aspect Ratio (消除橢圓)
    vec2 corrected_diff = diff;
    corrected_diff.y *= aspect_ratio; 
    
    float d = length(corrected_diff); // 修正後的距離才是真正的圓形距離
    
    float mask = smoothstep(radius, radius - 0.1, d); // 讓邊緣柔和一點

    // 計算扭曲向量 (避免 normalize(0) 在部分 WebGL 實作產生 NaN)
    float diff_len = length(diff);
    vec2 dir = (diff_len > 0.00001) ? (diff / diff_len) : vec2(0.0);
    // 扭曲力度曲線 (中心越強，邊緣越弱)
    float distort_amt = (1.0 - d/radius) * strength * mask;
    
    // 【修正 2：去除方框】預設顏色為透明
    COLOR = vec4(0.0, 0.0, 0.0, 0.0); 
    
    // 如果在修正後的圓形半徑內，進行扭曲
    if (d < radius) {
        // 【色差特效核心】
        float r = texture(SCREEN_TEXTURE, SCREEN_UV - dir * distort_amt * (1.0 + aberration)).r;
        float g = texture(SCREEN_TEXTURE, SCREEN_UV - dir * distort_amt).g;
        float b = texture(SCREEN_TEXTURE, SCREEN_UV - dir * distort_amt * (1.0 - aberration)).b;
        
        vec3 twisted_color = vec3(r, g, b);
        
        // 不穩定紅光混合
        if (tint_intensity > 0.0) {
            vec3 red_tint = vec3(tint_intensity, 0.0, 0.0);
            twisted_color = mix(twisted_color, red_tint, tint_intensity * 0.5);
        }
        
        // 視覺進化：邊緣光暈 (Phase 4B)
        if (rim_intensity > 0.0) {
            // 邊緣區域 (d 接近 radius 時最強)
            float edge_factor = smoothstep(radius * 0.35, radius * 0.92, d);
            float rim_glow = edge_factor * rim_intensity;
            twisted_color = mix(twisted_color, rim_color, rim_glow);
        }
        
        COLOR.rgb = twisted_color;
        COLOR.a = 1.0; // 在圓形扭曲範圍內完全不透明
    }
}