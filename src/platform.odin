package main

import "core:strings"
import "core:fmt"
import "core:math"
import "core:container/lru"
import "core:time"
import "core:unicode/utf8"

import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"

import stbtt "vendor:stb/truetype"

Vec2 :: [2]f64
FVec2 :: [2]f32

Vec3 :: [3]f64
FVec3 :: [3]f32

FVec4 :: [4]f32
BVec4 :: [4]u8

IRect :: struct {
	x: i32,
	y: i32,
	w: i32,
	h: i32,
}

Rect :: struct {
	x: f64,
	y: f64,
	w: f64,
	h: f64,
}

FontSize :: enum u8 {
	PSize = 0,
	H1Size,
	H2Size,
	LastSize,
}

FontType :: enum u8 {
	DefaultFont = 0,
	DefaultFontBold,
	MonoFont,
	IconFont,
	LastFont,
}

DrawRect :: struct #packed {
	pos: FVec4,
	color: BVec4,
	uv: FVec2,
}
TextRect :: struct {
	str: string,
	scale: FontSize,
	type: FontType,
	pos: FVec2,
	color: BVec4,
}
TextRectArr :: [dynamic]TextRect

LRU_Key :: struct #packed {
	size: FontSize,
	type: FontType,
	str: string,
}

LRU_Text :: struct {
	handle: u32,
	width: i32,
	height: i32,
}

AppError :: enum int {
	NoError = 0,
	OutOfMemory = 1,
	Bug = 2,
	InvalidFile = 3,
	InvalidFileVersion = 4,
	FileFailure = 5,
}

PlatformEventType :: enum {
	None,
	MouseUp,
	MouseDown,
	MouseMoved,
	Scroll,
	Zoom,
	Rotate,
	KeyDown,
	KeyUp,
	Resize,
	FocusGained,
	FocusLost,
	FileDropped,
	More,
	Exit,
}

KeyType :: enum u8 {
	None = 0,

	A, B, C, D, E, F, G, H, I, J, K, L, M,
	N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
	_0, _1, _2, _3, _4, _5, _6, _7, _8, _9,
	F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, 
	F12, F13, F14, F15, F16, F17, F18, F19, F20,

	LeftShift, LeftSuper, LeftControl, LeftAlt, 
	RightShift, RightSuper, RightControl, RightAlt,

	Function, Escape, CapsLock,
	Space, Tab, Return, Backspace, Delete, FwdDelete,

	PageUp, PageDown, Home, End,
	Minus, Equal, LeftBracket, RightBracket,
	Comma, Period, Backslash, Slash, Semicolon, Quote, Grave,

	Keypad_1, Keypad_2, Keypad_3, Keypad_4, Keypad_5, Keypad_6, Keypad_7, Keypad_8, Keypad_9, Keypad_0,
	Keypad_Period, Keypad_Multiply, Keypad_Plus, Keypad_Clear, Keypad_Divide, Keypad_Enter, Keypad_Minus, Keypad_Equal,
	Up, Down, Left, Right,

	VolumeUp, VolumeDown, Mute, Help,
}

MouseButtonType :: enum {
	Left,
	Right,
	Middle,
	None,
}

PlatformEvent :: struct {
	type: PlatformEventType,

	x: f64,
	y: f64,
	z: f64,

	w: f64,
	h: f64,

	key: KeyType,
	mouse: MouseButtonType,
	str: string,
}

Platform_State :: struct {
	// Basic Rendering State
	dpr:                      f64,
	width:                    f64,
	height:                   f64,

	rects:      [dynamic]DrawRect,
	text_rects: [dynamic]TextRect,

	frame_count:      int,
	last_frame_count: int,

	// Sleep State
	awake: bool,
	was_sleeping: bool,
	has_focus: bool,

	// Input State
	mouse_pos:      Vec2,
	last_mouse_pos: Vec2,
	clicked_pos:    Vec2,

	clicked_t: time.Tick,
	clicked:        bool,
	double_clicked: bool,
	is_mouse_down:  bool,
	was_mouse_down: bool,
	mouse_up_now:   bool,

	is_hovering:    bool,

	ctrl_down: bool,
	shift_down: bool,
	super_down: bool,
	alt_down: bool,

	scroll_val_y: f64,
	velocity_multiplier: f64,

	// Font + Text State
	standard_keymap: [256]u8,
	shift_keymap:    [256]u8,

	sans_font:      []u8,
	sans_font_bold: []u8,
	mono_font:      []u8,
	icon_font:      []u8,
	font_map:  [FontType.LastFont]stbtt.fontinfo,
	font_size: [FontSize.LastSize]f32,
	lru_text_cache: lru.Cache(LRU_Key, LRU_Text),

	p_height:  f64,
	h1_height: f64,
	h2_height: f64,
	em:        f64,

	// Color State
	colors: Colors,
	colormode: ColorMode,

	// Platform Specific GFX State
	gfx: GFX_Context,

	vao: u32,
	rect_deets_buffer: u32,
	u_dpr: i32,
	u_res: i32,
}

process_modifiers :: proc(pt: ^Platform_State, key: KeyType, is_down: bool) {
	#partial switch key {
	case .LeftShift:    pt.shift_down = is_down
	case .RightShift:   pt.shift_down = is_down
	case .LeftControl:  pt.ctrl_down = is_down
	case .RightControl: pt.ctrl_down = is_down
	case .LeftAlt:      pt.alt_down = is_down
	case .RightAlt:     pt.alt_down = is_down
	case .LeftSuper:    pt.super_down = is_down
	case .RightSuper:   pt.super_down = is_down
	}
}

assign_keys :: proc(pt: ^Platform_State, key: KeyType, a: u8, b: u8) {
	pt.standard_keymap[key] = a
	pt.shift_keymap[key] = b
}

init_keymap :: proc(pt: ^Platform_State) {
	pt.standard_keymap[0] = 0

	for i := 0; i < 26; i += 1 {
		map_slot := int(KeyType.A) + i
		pt.standard_keymap[map_slot] = u8(i + 'a')
		pt.shift_keymap[map_slot] = u8('A' + i)
	}

	for i := 0; i < 10; i += 1 {
		map_slot := int(KeyType._0) + i
		pt.standard_keymap[map_slot] = u8('0' + i)
	}
	pt.shift_keymap[KeyType._0] = ')'
	pt.shift_keymap[KeyType._1] = '!'
	pt.shift_keymap[KeyType._2] = '@'
	pt.shift_keymap[KeyType._3] = '#'
	pt.shift_keymap[KeyType._4] = '$'
	pt.shift_keymap[KeyType._5] = '%'
	pt.shift_keymap[KeyType._6] = '^'
	pt.shift_keymap[KeyType._7] = '&'
	pt.shift_keymap[KeyType._8] = '*'
	pt.shift_keymap[KeyType._9] = '('

	assign_keys(pt, .Minus,  '-', '_')
	assign_keys(pt, .Equal,  '=', '+')
	assign_keys(pt, .Backslash,  '\\', '|')
	assign_keys(pt, .Comma,  ',', '<')
	assign_keys(pt, .Period, '.', '>')
	assign_keys(pt, .Slash, '/', '?')
	assign_keys(pt, .LeftBracket, '[', '{')
	assign_keys(pt, .RightBracket, ']', '}')
	assign_keys(pt, .Quote, '\'', '"')
	assign_keys(pt, .Grave, '`', '~')
	assign_keys(pt, .Semicolon, ';', ':')

	assign_keys(pt, .Space, ' ', ' ')
	assign_keys(pt, .Tab, '\t', '\t')
}

capture_keys :: proc(pt: ^Platform_State, key: KeyType, buffer: []u8) -> string {
	if pt.shift_down {
		buffer[0] = pt.shift_keymap[key]
	} else {
		buffer[0] = pt.standard_keymap[key]
	}

	return string(cstring(raw_data(buffer)))
}

mouse_down :: proc(pt: ^Platform_State, x, y: f64) {
	pt.is_mouse_down = true
	pt.mouse_pos = Vec2{x, y}

	if pt.frame_count != pt.last_frame_count {
		pt.last_mouse_pos = pt.mouse_pos
		pt.last_frame_count = pt.frame_count
	}

	pt.clicked = true
	pt.clicked_pos = pt.mouse_pos

	cur_time := time.tick_now()
	time_diff := time.tick_diff(pt.clicked_t, cur_time)
	click_window := time.duration_milliseconds(time_diff)
	double_click_window_ms := 400.0

	if click_window < double_click_window_ms {
		pt.double_clicked = true
	} else {
		pt.double_clicked = false
	}
	pt.clicked_t = cur_time
}

mouse_up :: proc(pt: ^Platform_State, x, y: f64) {
	pt.is_mouse_down = false
	pt.was_mouse_down = true
	pt.mouse_up_now = true

	if pt.frame_count != pt.last_frame_count {
		pt.last_mouse_pos = pt.mouse_pos
		pt.last_frame_count = pt.frame_count
	}

	pt.mouse_pos = Vec2{x, y}
}

mouse_moved :: proc(pt: ^Platform_State, x, y: f64) {
	if pt.frame_count != pt.last_frame_count {
		pt.last_mouse_pos = pt.mouse_pos
		pt.last_frame_count = pt.frame_count
	}

	pt.mouse_pos = Vec2{x, y}
}

mouse_scroll :: proc(pt: ^Platform_State, y: f64) {
	y_dist := y * pt.velocity_multiplier
	if pt.ctrl_down {
		y_dist *= 10
	}
	pt.scroll_val_y += y_dist
}

draw_circle :: proc(pt: ^Platform_State, center: Vec2, radius: f64, percentage: f64, color: BVec4) {
	append(&pt.rects, DrawRect{FVec4{f32(center.x), f32(center.y), f32(radius), f32(percentage)}, color, FVec2{-3, -3}})
}

draw_rect :: proc(pt: ^Platform_State, rect: Rect, color: BVec4) {
	append(&pt.rects, DrawRect{FVec4{f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h)}, color, FVec2{-2, 0.0}})
}

draw_line :: proc(pt: ^Platform_State, start, end: Vec2, width: f64, color: BVec4) {
	start, end := start, end
	if start.x > end.x {
		end, start = start, end
	}

	append(&pt.rects, DrawRect{FVec4{f32(start.x), f32(start.y), f32(end.x), f32(end.y)}, color, FVec2{f32(width), -2}})
}

draw_rect_outline :: proc(pt: ^Platform_State, rect: Rect, width: f64, color: BVec4) {
	x1 := rect.x
	y1 := rect.y
	x2 := rect.x + rect.w
	y2 := rect.y + rect.h

	draw_line(pt, Vec2{x1, y1}, Vec2{x2, y1}, width, color)
	draw_line(pt, Vec2{x1, y1}, Vec2{x1, y2}, width, color)
	draw_line(pt, Vec2{x2, y1}, Vec2{x2, y2}, width, color)
	draw_line(pt, Vec2{x1, y2}, Vec2{x2, y2}, width, color)
}

draw_rect_inline :: proc(pt: ^Platform_State, rect: Rect, width: f64, color: BVec4) {
	x1 := rect.x + width
	y1 := rect.y + width
	x2 := rect.x + rect.w - width
	y2 := rect.y + rect.h - width

	draw_line(pt, Vec2{x1, y1}, Vec2{x2, y1}, width, color)
	draw_line(pt, Vec2{x1, y1}, Vec2{x1, y2}, width, color)
	draw_line(pt, Vec2{x2, y1}, Vec2{x2, y2}, width, color)
	draw_line(pt, Vec2{x1, y2}, Vec2{x2, y2}, width, color)
}

get_text_height :: proc(pt: ^Platform_State, scale: FontSize, font: FontType) -> f64 { 
	#partial switch scale {
	case .PSize: return pt.p_height
	case .H1Size: return pt.h1_height
	case .H2Size: return pt.h2_height
	case:
		panic("Invalid heights?\n")
	}
}

rm_text_cache :: proc(key: LRU_Key, value: LRU_Text, udata: rawptr) {
	handle := value.handle

	delete(key.str)
	gl.DeleteTextures(1, &handle)
}


alpha_blit :: proc(dst, src: IRect, src_stride: i32, output: []u8, input: []u8) {
	for i : i32 = 0; i < src.h; i += 1 {
		for j : i32 = 0; j < src.w; j += 1 {
			output[(i+dst.y) * dst.w + (j+dst.x)] += input[(i+src.y) * src_stride + (j+src.x)]
		}
	}
}

get_text_cache :: proc(pt: ^Platform_State, str: string, scale: FontSize, font_type: FontType) -> LRU_Text {
	text_blob, ok := lru.get(&pt.lru_text_cache, LRU_Key{ scale, font_type, str })
	if !ok {
		long_str := strings.clone(str)

		width : i32 = 0
		height : i32 = 0
		pen := FVec2{0, 0}
		pixel_height := pt.font_size[scale]
		fontinfo := &pt.font_map[font_type]

		sf := stbtt.ScaleForMappingEmToPixels(fontinfo, pixel_height)
		runes := utf8.string_to_runes(str)
		for ch, i in runes {
			adv, lsb : i32
			stbtt.GetCodepointHMetrics(fontinfo, ch, &adv, &lsb)

			x0, y0, x1, y1 : i32
			stbtt.GetCodepointBox(fontinfo, ch, &x0, &y0, &x1, &y1)
			width += adv 

			if i < len(runes)-1 {
				width += stbtt.GetCodepointKernAdvance(fontinfo, ch, runes[i+1])
			}
		}

		width = i32(f32(width) * sf)
		width += 2

		ascent, descent, line_gap : i32
		stbtt.GetFontVMetrics(fontinfo, &ascent, &descent, &line_gap)
		height += i32(f32(ascent - descent) * sf + 2)

		baseline := i32(f32(ascent) * sf) + 1
		output   := make([]u8,  width * height)
		output32 := make([]u32, width * height)

		font_temp := [256*256]u8{}
		for ch, i in runes {
			adv, lsb : i32
			stbtt.GetCodepointHMetrics(fontinfo, ch, &adv, &lsb)
			subpixel := pen.x - math.floor(pen.x)

			ix0, iy0, ix1, iy1 : i32
			stbtt.GetCodepointBitmapBoxSubpixel(fontinfo, ch, sf, sf, subpixel, 0, &ix0, &iy0, &ix1, &iy1)

			x0, y0, x1, y1 : i32
			stbtt.GetCodepointBox(fontinfo, ch, &x0, &y0, &x1, &y1)
			stbtt.MakeGlyphBitmapSubpixel(fontinfo, raw_data(font_temp[:]), ix1 - ix0, iy1 - iy0, 256, sf, sf, subpixel, 0, stbtt.FindGlyphIndex(fontinfo, ch))

			src := IRect { 0, 0, ix1 - ix0, iy1 - iy0 }
			dst := IRect { i32(pen.x + f32(lsb) * sf), baseline + iy0, width, height }

			alpha_blit(dst, src, 256, output, font_temp[:])

			if i < len(runes)-1 {
				pen.x += sf * f32(stbtt.GetCodepointKernAdvance(fontinfo, ch, runes[i+1]))
			}

			pen.x += f32(adv) * sf
		}

		for i := 0; i < len(output); i += 1 {
			o := u32(output[i])
			output32[i] = o << 24 | o << 8 | o << 16 | o
		}

		handle : u32 = 0
		gl.GenTextures(1, &handle)
		gl.ActiveTexture(gl.TEXTURE0)
		gl.BindTexture(gl.TEXTURE_2D, handle)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
		gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(output32))

		delete(output)
		delete(output32)

		text_blob = LRU_Text{ handle, width, height }
		lru.set(&pt.lru_text_cache, LRU_Key{ scale, font_type, long_str }, text_blob)
	}

	return text_blob
}

measure_text :: proc(pt: ^Platform_State, str: string, scale: FontSize, font_type: FontType) -> f64 {
	if len(str) == 0 {
		return 0
	}

	text_blob := get_text_cache(pt, str, scale, font_type)
	return f64(text_blob.width) / pt.dpr
}

draw_text :: proc(pt: ^Platform_State, str: string, pos: Vec2, scale: FontSize, font_type: FontType, color: BVec4) {
	if len(str) == 0 {
		return
	}

	text_blob := get_text_cache(pt, str, scale, font_type)
	gl.BindTexture(gl.TEXTURE_2D, text_blob.handle)

	x_pos := f32(math.round(pos.x * pt.dpr) / pt.dpr)
	y_pos := f32(math.round(pos.y * pt.dpr) / pt.dpr)
	w := f32(f64(text_blob.width) / pt.dpr)
	h := f32(f64(text_blob.height) / pt.dpr)
	append(&pt.rects, DrawRect{FVec4{x_pos, y_pos, w, h}, color, FVec2{0.0, 0.0}})
	flush_rects(pt)
}
batch_text :: proc(pt: ^Platform_State, str: string, pos: Vec2, scale: FontSize, font_type: FontType, color: BVec4) {
	if len(str) == 0 {
		return
	}

	x_pos := f32(math.round(pos.x * pt.dpr) / pt.dpr)
	y_pos := f32(math.round(pos.y * pt.dpr) / pt.dpr)
	append(&pt.text_rects, TextRect{
		str = str,
		scale = scale,
		type = font_type,
		pos = FVec2{x_pos, y_pos},
		color = color,
	})
}

flush_text_batch :: proc(pt: ^Platform_State) {
	for rect in pt.text_rects {
		text_blob := get_text_cache(pt, rect.str, rect.scale, rect.type)
		gl.BindTexture(gl.TEXTURE_2D, text_blob.handle)

		w := f32(f64(text_blob.width) / pt.dpr)
		h := f32(f64(text_blob.height) / pt.dpr)
		draw_rect := DrawRect{FVec4{rect.pos.x, rect.pos.y, w, h}, rect.color, FVec2{0.0, 0.0}}
		gl.BufferData(gl.ARRAY_BUFFER, size_of(draw_rect), &draw_rect, gl.DYNAMIC_DRAW)
		gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, 1)
	}

	non_zero_resize(&pt.text_rects, 0)
}

flush_rects :: proc(pt: ^Platform_State) {
	gl.BufferData(gl.ARRAY_BUFFER, len(pt.rects)*size_of(pt.rects[0]), raw_data(pt.rects[:]), gl.DYNAMIC_DRAW)
	gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, i32(len(pt.rects)))
	non_zero_resize(&pt.rects, 0)
}

get_system_color :: proc() -> bool { return false }
get_session_storage :: proc(key: string) { }
set_session_storage :: proc(key, val: string) { }

setup_fonts :: proc(pt: ^Platform_State) {
	stbtt.InitFont(&pt.font_map[FontType.DefaultFont], raw_data(pt.sans_font), 0)
	stbtt.InitFont(&pt.font_map[FontType.DefaultFontBold], raw_data(pt.sans_font_bold), 0)
	stbtt.InitFont(&pt.font_map[FontType.MonoFont], raw_data(pt.mono_font), 0)
	stbtt.InitFont(&pt.font_map[FontType.IconFont], raw_data(pt.icon_font), 0)

	pt.font_size[FontSize.PSize]  = f32(pt.p_height  * pt.dpr)
	pt.font_size[FontSize.H1Size] = f32(pt.h1_height * pt.dpr)
	pt.font_size[FontSize.H2Size] = f32(pt.h2_height * pt.dpr)
}

setup_graphics :: proc(pt: ^Platform_State) -> (ok: bool) {
	lru.init(&pt.lru_text_cache, 1000)
	pt.lru_text_cache.on_remove = rm_text_cache

	// Load statically packed fonts
	pt.sans_font      = #load("../fonts/Montserrat-Regular.ttf")
	pt.sans_font_bold = #load("../fonts/Montserrat-Bold.ttf")
	pt.mono_font      = #load("../fonts/FiraMono-Regular.ttf")
	pt.icon_font      = #load("../fonts/fontawesome-webfont.ttf")
	setup_fonts(pt)

	idx_pos := [?]glm.vec2{
		{0.0, 0.0},
		{1.0, 0.0},
		{0.0, 1.0},
		{1.0, 1.0},
	}

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
	gl.Enable(gl.MULTISAMPLE)
	gl.Enable(gl.FRAMEBUFFER_SRGB)

	rect_program, rect_prog_ok := gl.load_shaders_source(rect_vert_src, rect_frag_src)
	if !rect_prog_ok {
		fmt.eprintln("Failed to create rect shader")
		return
	}

	rect_uniforms := gl.get_uniforms_from_program(rect_program)
	gl.UseProgram(rect_program)
	pt.u_dpr = rect_uniforms["u_dpr"].location
	pt.u_res = rect_uniforms["u_resolution"].location

	gl.GenVertexArrays(1, &pt.vao)
	gl.BindVertexArray(pt.vao)

	// Set up dynamic rect buffer
	gl.GenBuffers(1, &pt.rect_deets_buffer)
	gl.BindBuffer(gl.ARRAY_BUFFER, pt.rect_deets_buffer)

	gl.EnableVertexAttribArray(u32(VertAttrs.RectPos))
	gl.VertexAttribPointer(u32(VertAttrs.RectPos), 4, gl.FLOAT, false, size_of(DrawRect), offset_of(DrawRect, pos))
	gl.VertexAttribDivisor(u32(VertAttrs.RectPos), 1)

	gl.EnableVertexAttribArray(u32(VertAttrs.Color))
	gl.VertexAttribPointer(u32(VertAttrs.Color), 4, gl.UNSIGNED_BYTE, true, size_of(DrawRect), offset_of(DrawRect, color))
	gl.VertexAttribDivisor(u32(VertAttrs.Color), 1)

	gl.EnableVertexAttribArray(u32(VertAttrs.UV))
	gl.VertexAttribPointer(u32(VertAttrs.UV), 2, gl.FLOAT, false, size_of(DrawRect), offset_of(DrawRect, uv))
	gl.VertexAttribDivisor(u32(VertAttrs.UV), 1)

	// Set up rect points buffer
	rect_points_buffer: u32
	gl.GenBuffers(1, &rect_points_buffer)
	gl.BindBuffer(gl.ARRAY_BUFFER, rect_points_buffer)
	gl.BufferData(gl.ARRAY_BUFFER, len(idx_pos)*size_of(idx_pos[0]), raw_data(idx_pos[:]), gl.STATIC_DRAW)
	gl.EnableVertexAttribArray(u32(VertAttrs.IdxPos))
	gl.VertexAttribPointer(u32(VertAttrs.IdxPos), 2, gl.FLOAT, false, 0, 0)

	return true
}

setup_frame :: proc(pt: ^Platform_State, height, width: int) {
	gl.Viewport(0, 0, i32(width), i32(height))
	gl.Uniform1f(pt.u_dpr, f32(pt.dpr))
	gl.Uniform2f(pt.u_res, f32(width), f32(height))
	gl.BindBuffer(gl.ARRAY_BUFFER, pt.rect_deets_buffer)
	gl.BindVertexArray(pt.vao)

	bg := bvec_to_flat_fvec4(pt.colors.bg)
	gl.ClearColor(bg.r, bg.g, bg.b, bg.a)
	gl.Clear(gl.COLOR_BUFFER_BIT)

	pt.height = f64(height) / f64(pt.dpr)
	pt.width  = f64(width) / f64(pt.dpr)
}

finish_frame :: proc(pt: ^Platform_State) {
	gl.Finish()
	swap_buffers(&pt.gfx)
	gl.Finish()
}
