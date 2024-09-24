package main

import "core:fmt"
import "core:mem"
import "core:hash"
import "core:math/rand"
import "core:math/linalg/glsl"

Colors :: struct {
	bg:          BVec4,

	bg2:         BVec4,
	text:        BVec4,
	dark_text:   BVec4,
	error:       BVec4,

	active: [5]BVec4,
}

ColorMode :: enum {
	Dark,
	Light,
	Auto,
}

default_colors :: proc "contextless" (pt: ^Platform_State, is_dark: bool) {
	colors := &pt.colors

	colors.active[0] = BVec4{0xe7, 0x6f, 0x51, 255}
	colors.active[1] = BVec4{0xF4, 0xa2, 0x61, 255}
	colors.active[2] = BVec4{0xe9, 0xc4, 0x6a, 255}
	colors.active[3] = BVec4{0x2a, 0x9d, 0x8f, 255}
	colors.active[4] = BVec4{0x26, 0x46, 0x53, 255}

	colors.error     = BVec4{0xFF, 0x3F, 0x83, 255}
	colors.dark_text = BVec4{   3,    3,    3, 255}

	// dark mode
	if is_dark {
		colors.bg        = BVec4{  3,   3,   3, 255}
		colors.bg2       = BVec4{ 28,  28,  28, 255}
		colors.text      = BVec4{255, 255, 255, 255}

	// light mode
	} else {
		colors.bg         = BVec4{254, 252, 248, 255}
		colors.bg2        = BVec4{254, 252, 248, 255}
		colors.text       = BVec4{20,   20,  20, 255}
	}
}

set_color_mode :: proc(pt: ^Platform_State, auto: bool, is_dark: bool) {
	default_colors(pt, is_dark)

	if auto {
		pt.colormode = ColorMode.Auto
	} else {
		pt.colormode = is_dark ? ColorMode.Dark : ColorMode.Light
	}
}

hsv2rgb :: proc(c: FVec3) -> FVec3 {
	K := glsl.vec3{1.0, 2.0 / 3.0, 1.0 / 3.0}
	sum := glsl.vec3{c.x, c.x, c.x} + K.xyz
	p := glsl.abs_vec3(glsl.fract(sum) * 6.0 - glsl.vec3{3,3,3})
	result := glsl.vec3{c.z, c.z, c.z} * glsl.mix(K.xxx, glsl.clamp(p - K.xxx, 0.0, 1.0), glsl.vec3{c.y, c.y, c.y})
	return FVec3{result.x, result.y, result.z}
}

hex_to_bvec :: proc "contextless" (v: u32) -> BVec4 {
	a := u8(v >> 24)
	r := u8(v >> 16)
	g := u8(v >> 8)
	b := u8(v >> 0)

	return BVec4{r, g, b, a}
}

bvec_to_flat_fvec4 :: proc "contextless" (c: BVec4) -> FVec4 {
	return FVec4{f32(c.x) / 255, f32(c.y) / 255, f32(c.z) / 255, f32(c.w) / 255}
}

bvec_to_fvec :: proc "contextless" (c: BVec4) -> FVec3 {
	return FVec3{f32(c.r), f32(c.g), f32(c.b)}
}

greyscale :: proc "contextless" (c: FVec3) -> FVec3 {
	return (c.x * 0.299) + (c.y * 0.587) + (c.z * 0.114)
}
