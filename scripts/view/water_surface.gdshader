shader_type canvas_item;
render_mode unshaded;

uniform sampler2D cell_state : filter_nearest, repeat_disable;
uniform vec2 grid_size;
uniform vec2 half_tile = vec2(12.0, 6.0);
uniform float height_scale = 9.0;
uniform bool show_flow = true;
uniform bool show_settlement = false;
uniform sampler2D settlement_mask : filter_nearest, repeat_disable;

void vertex() {
	// Negative UV.x: water top/bottom (1,2), arrow (3), ground/wall (4,5,6).
	if (UV.x < -1.0) {
		float kind = floor(-UV.x);
		vec2 cell_uv = vec2(fract(-UV.x), UV.y);
		vec4 state = texture(cell_state, cell_uv);
		float depth = state.r;
		float z = state.a;
		if (kind >= 4.0) {
			if (kind >= 5.0) {
				vec2 next_uv = cell_uv + (kind < 6.0 ? vec2(1.0 / grid_size.x, 0.0) : vec2(0.0, 1.0 / grid_size.y));
				float neighbour = any(greaterThan(next_uv, vec2(1.0))) ? -3.0 : texture(cell_state, next_uv).a;
				z = min(z, neighbour);
			}
			VERTEX.y -= z * height_scale;
			vec3 ground = mix(vec3(0.34, 0.48, 0.30), vec3(0.29, 0.42, 0.29), clamp(state.a / 12.0, 0.0, 1.0));
			ground = mix(ground, vec3(0.55, 0.57, 0.48), clamp((state.a - 15.0) / 10.0, 0.0, 1.0));
			ground = mix(ground, vec3(0.88, 0.90, 0.83), clamp((state.a - 27.0) / 4.0, 0.0, 1.0));
			COLOR.rgb *= ground;
			if (show_settlement && kind < 5.0 && texture(settlement_mask, cell_uv).r > 0.001) {
				COLOR.rgb = mix(COLOR.rgb, vec3(0.92, 0.57, 0.26), 0.28);
			}
		} else if (kind < 3.0) {
			VERTEX.y -= (z + (kind < 2.0 ? depth : 0.0)) * height_scale;
			COLOR.rgb *= mix(vec3(0.24, 0.64, 0.70), vec3(0.08, 0.32, 0.54), clamp(depth / 2.0, 0.0, 1.0));
			COLOR.a = smoothstep(0.0, 0.04, depth) * clamp(0.10 + depth * 1.8, 0.10, 0.9);
		} else {
			vec2 cell = floor(cell_uv * grid_size);
			vec2 center = vec2((cell.x - cell.y) * half_tile.x, (cell.x + cell.y) * half_tile.y);
			vec2 offset = VERTEX - center;
			vec2 flow = state.gb;
			vec2 projected_flow = vec2(flow.x - flow.y, (flow.x + flow.y) * 0.5);
			float magnitude = length(projected_flow);
			vec2 direction = magnitude > 0.0 ? projected_flow / magnitude : vec2(1.0, 0.0);
			VERTEX = center + vec2(direction.x * offset.x - direction.y * offset.y, direction.y * offset.x + direction.x * offset.y);
			VERTEX.y -= (z + depth) * height_scale;
			COLOR.a *= smoothstep(0.02, 0.08, depth) * smoothstep(0.001, 0.008, length(flow));
			if (!show_flow) {
				COLOR.a = 0.0;
			}
		}
		UV = vec2(0.0);
	}
}
