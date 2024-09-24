package main

VertAttrs :: enum u32 {
	IdxPos = 0,
	RectPos = 1,
	Color = 2,
	UV = 3,
}

rect_vert_src := `#version 330 core

// idx_pos  {x, y}
layout(location=0) in vec2 idx_pos;

// rect_pos {x, y, width, height}
layout(location=1) in vec4 in_rect_pos;
layout(location=2) in vec4 color;
layout(location=3) in vec2 uv;

uniform float u_dpr;
uniform vec2  u_resolution;

out vec4 v_color;
out vec2 v_uv;
out vec4 v_rect_pos;
out vec2 v_idx_pos;

void main() {
	vec4 rect_pos = in_rect_pos * u_dpr;

	// if line
	if (uv.y < 0 && uv.y > -3) {
		float width = (uv.x / 2) * u_dpr;
		vec2 a = rect_pos.xy;
		vec2 b = rect_pos.zw;
		vec2 center = mix(a, b, 0.5);
		vec2 fwd = normalize(b - a);
		vec2 norm = vec2(-fwd.y, fwd.x) * width;

		vec2 p0 = a - fwd + norm;
		vec2 p1 = b + fwd - norm;
		vec2 s = -2.0 * norm;
		vec2 t = p1 - p0 - s;

		vec2 xy = p0 + (idx_pos.x * s) + (idx_pos.y * t);
		gl_Position = vec4((xy / u_resolution) * 2.0 - 1.0, 0.0, 1.0);
		gl_Position.y = -gl_Position.y;

	// if circle
	} else if (uv.x < -2 && uv.y < -2) {
		float radius = rect_pos.z;
		float top_x = rect_pos.x - radius;
		float top_y = rect_pos.y + radius;
		vec2 xy = vec2(top_x, top_y) + (idx_pos * 2.0 * vec2(radius, -radius));
		gl_Position = vec4((xy / u_resolution) * 2.0 - 1.0, 0.0, 1.0);
		gl_Position.y = -gl_Position.y;

	// if rect
	} else {
		vec2 xy = vec2(rect_pos.x, rect_pos.y) + (idx_pos * vec2(rect_pos.z, rect_pos.w));

		gl_Position = vec4((xy / u_resolution) * 2.0 - 1.0, 0.0, 1.0);
		gl_Position.y = -gl_Position.y;
	}

	v_rect_pos = rect_pos;
	v_color = color;
	v_uv = uv;
	v_idx_pos = idx_pos;
}
`

rect_frag_src := `#version 330 core
in vec4 v_color;
in vec4 v_rect_pos;
in vec2 v_uv;
in vec2 v_idx_pos;
out vec4 out_color;

uniform float u_dpr;
uniform vec2  u_resolution;
uniform sampler2D font_tex;

float sdSegment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p-a, ba = b-a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - (ba * h));
}

float sdOrientedBox(in vec2 p, in vec2 a, in vec2 b, float thick) {
    float l = length(b - a)+0.5;
    vec2  d = (b - a) / l;
    vec2  q = p - (a + b) * 0.5;
          q = mat2(d.x, -d.y, d.y, d.x) * q;
          q = abs(q) - vec2(l * 0.5, thick);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);    
}

float fromLinear(float linearRGB)
{
    bool cutoff = (linearRGB < float(0.0031308));
    float higher = float(1.055)*pow(linearRGB, float(1.0/2.4)) - float(0.055);
    float lower = linearRGB * float(12.92);

    return mix(higher, lower, cutoff);
}
float toLinear(float sRGB)
{
    bool cutoff = (sRGB < float(0.04045));
    float higher = pow((sRGB + float(0.055))/float(1.055), float(2.4));
    float lower = sRGB/float(12.92);

    return mix(higher, lower, cutoff);
}
vec3 fromLinear3(vec3 linearRGB)
{
    bvec3 cutoff = lessThan(linearRGB, vec3(0.0031308));
    vec3 higher = vec3(1.055)*pow(linearRGB, vec3(1.0/2.4)) - vec3(0.055);
    vec3 lower = linearRGB * vec3(12.92);

    return mix(higher, lower, cutoff);
}
vec3 toLinear3(vec3 sRGB)
{
    bvec3 cutoff = lessThan(sRGB, vec3(0.04045));
    vec3 higher = pow((sRGB + vec3(0.055))/vec3(1.055), vec3(2.4));
    vec3 lower = sRGB/vec3(12.92);

    return mix(higher, lower, cutoff);
}

void main() {
	// if line
	if (v_uv.y < -1 && v_uv.y > -3) {
		float width = v_uv.x * u_dpr;
		vec2 a = v_rect_pos.xy;
		vec2 b = v_rect_pos.zw;

		vec2 pos = vec2(gl_FragCoord.x, u_resolution.y - gl_FragCoord.y);

		float d = sdOrientedBox(pos, a, b, width);
		float alpha = 1.0 - smoothstep(-min(2.0, width - 0.5), 0.0, d); 
		out_color = vec4(v_color.rgb, v_color.a * alpha);

		out_color.rgb = toLinear3(out_color.rgb);
		out_color.rgb *= out_color.a;

	// if rect
	} else if (v_uv.x < -1 && v_uv.x > -3) {
		out_color = v_color;

		out_color.rgb = toLinear3(out_color.rgb);
		out_color.rgb *= out_color.a;

	// if circle
	} else if (v_uv.x < -2 && v_uv.y < -2) {
		out_color = v_color;
		float fill_perc = v_rect_pos.w / 2;

		float width = v_rect_pos.z * u_dpr;
		vec2 pos = (vec2(gl_FragCoord.x, u_resolution.y - gl_FragCoord.y) - v_rect_pos.xy) / width;

		float edge_width = 1 / width;
		float l = length(pos);
		float alpha = 1.0 - smoothstep(0.5 - edge_width, 0.5 + edge_width, l);

		const float PI = 3.14159265;
		float angle = (atan(pos.y, pos.x)/PI) * 0.5 + 0.5;
		angle = mod(angle + 0.75, 1.0);

		float z = 1.0 / (2.0 * PI * l * width);
		alpha = (1.0 - smoothstep(angle + z, angle - z, fill_perc)) * alpha;

		out_color = vec4(v_color.rgb, v_color.a * alpha);
		out_color.rgb = toLinear3(out_color.rgb);
		out_color.rgb *= out_color.a;

	// if textured rect
	} else {
		vec2 scaled_idx = v_idx_pos / textureSize(font_tex, 0);
		scaled_idx.x *= v_rect_pos.z;
		scaled_idx.y *= v_rect_pos.w;
		vec2 uv_pos = scaled_idx;
		out_color = vec4(v_color.rgb, v_color.a * texture(font_tex, uv_pos).a);

		// Hack to increase the font weight of dark text.
		// It may be mitigating this: https://en.wikipedia.org/wiki/Irradiation_illusion
		float avg = (v_color.r + v_color.g + v_color.b) / 3;
		out_color.a = mix(fromLinear(out_color.a), out_color.a, avg);

		out_color.rgb *= out_color.a;

	}
}
`
