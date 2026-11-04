shader_type canvas_item;

// 角色外侧的纯色描边，原图叠在上面。
// UV 是 draw_texture_rect_region 传来的贴图坐标。
// src_uv：源区域在整张贴图上的 xy 起点和 zw 大小（0–1）。
// 绘制矩形比角色大出 radius_px（左、上、右）。底边贴着裁切线，不沿那条边描。

uniform vec4 outline_color : source_color = vec4(0.231, 0.435, 0.714, 1.0);
uniform float radius_px = 2.0;
uniform vec2 dest_size = vec2(220.0, 290.0);
uniform vec4 src_uv = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	vec2 quad = (UV - src_uv.xy) / src_uv.zw;
	vec2 inset = vec2(radius_px) / max(dest_size, vec2(1.0));
	vec2 inner = vec2(max(1.0 - inset.x * 2.0, 0.01), max(1.0 - inset.y, 0.01));
	vec2 img = (quad - vec2(inset.x, inset.y)) / inner;

	vec4 base = vec4(0.0);
	if (img.x >= 0.0 && img.x <= 1.0 && img.y >= 0.0 && img.y <= 1.0) {
		vec2 tuv = src_uv.xy + img * src_uv.zw;
		if (tuv.x >= 0.0 && tuv.x <= 1.0 && tuv.y >= 0.0 && tuv.y <= 1.0) {
			base = texture(TEXTURE, tuv);
		}
	}

	float nearest = radius_px + 1.6;
	for (int i = 0; i < 16; i++) {
		float ang = 6.28318530718 * float(i) / 16.0;
		vec2 dir = vec2(cos(ang), sin(ang));
		for (int k = 1; k <= 6; k++) {
			float rr = radius_px * float(k) / 6.0;
			vec2 q2 = quad + dir * rr / dest_size;
			vec2 img2 = (q2 - vec2(inset.x, inset.y)) / inner;
			float sa = 0.0;
			// 源区域和贴图之外不当作透明邻居，裁切线下面不会多出一条直边。
			if (img2.x >= 0.0 && img2.x <= 1.0 && img2.y >= 0.0 && img2.y <= 1.0) {
				vec2 tuv2 = src_uv.xy + img2 * src_uv.zw;
				if (tuv2.x >= 0.0 && tuv2.x <= 1.0 && tuv2.y >= 0.0 && tuv2.y <= 1.0) {
					sa = texture(TEXTURE, tuv2).a;
				}
			}
			if (sa > 0.4 && rr < nearest) {
				nearest = rr;
			}
		}
	}

	float outline_a = (1.0 - smoothstep(radius_px - 1.15, radius_px + 0.35, nearest)) * (1.0 - smoothstep(0.02, 0.5, base.a));
	vec3 rgb = mix(outline_color.rgb, base.rgb, base.a);
	float a = outline_color.a * outline_a * (1.0 - base.a) + base.a;
	COLOR = vec4(rgb, a);
}
