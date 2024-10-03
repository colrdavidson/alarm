#+build darwin, windows, linux
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:slice"

import SDL "vendor:sdl2"
import gl "vendor:OpenGL"
import "core:math/linalg/glsl"

GFX_Context :: struct {
	default_cursor: ^SDL.Cursor,
	pointer_cursor: ^SDL.Cursor,
	text_cursor:    ^SDL.Cursor,

	icon: ^SDL.Surface,
	icon_width: int,
	icon_height: int,

	window: ^SDL.Window,
}

_resolve_key :: proc(code: SDL.Keycode) -> KeyType {
	#partial switch code {
		case .A: return .A
		case .B: return .B
		case .C: return .C
		case .D: return .D
		case .E: return .E
		case .F: return .F
		case .G: return .G
		case .H: return .H
		case .I: return .I
		case .J: return .J
		case .K: return .K
		case .L: return .L
		case .M: return .M
		case .N: return .N
		case .O: return .O
		case .P: return .P
		case .Q: return .Q
		case .R: return .R
		case .S: return .S
		case .T: return .T
		case .U: return .U
		case .V: return .V
		case .W: return .W
		case .X: return .X
		case .Y: return .Y
		case .Z: return .Z

		case .NUM0: return ._0
		case .NUM1: return ._1
		case .NUM2: return ._2
		case .NUM3: return ._3
		case .NUM4: return ._4
		case .NUM5: return ._5
		case .NUM6: return ._6
		case .NUM7: return ._7
		case .NUM8: return ._8
		case .NUM9: return ._9

		case .EQUALS:       return .Equal
		case .MINUS:        return .Minus
		case .LEFTBRACKET:  return .LeftBracket
		case .RIGHTBRACKET: return .RightBracket
		case .QUOTE:      return .Quote
		case .SEMICOLON:  return .Semicolon
		case .BACKSLASH:  return .Backslash
		case .COMMA:      return .Comma
		case .SLASH:      return .Slash
		case .PERIOD:     return .Period
		case .BACKQUOTE:  return .Grave
		case .RETURN:     return .Return
		case .TAB:        return .Tab
		case .SPACE:      return .Space
		case .BACKSPACE:  return .Backspace
		case .ESCAPE:     return .Escape
		case .CAPSLOCK:   return .CapsLock

		case .LALT:   return .LeftAlt
		case .RALT:   return .RightAlt
		case .LCTRL:  return .LeftControl
		case .RCTRL:  return .RightControl
		case .LGUI:   return .LeftSuper
		case .RGUI:   return .RightSuper
		case .LSHIFT: return .LeftShift
		case .RSHIFT: return .RightShift

		case .F1:  return .F1
		case .F2:  return .F2
		case .F3:  return .F3
		case .F4:  return .F4
		case .F5:  return .F5
		case .F6:  return .F6
		case .F7:  return .F7
		case .F8:  return .F8
		case .F9:  return .F9
		case .F10: return .F10
		case .F11: return .F11
		case .F12: return .F12

		case .HOME:     return .Home
		case .END:      return .End
		case .PAGEUP:   return .PageUp
		case .PAGEDOWN: return .PageDown
		case .DELETE:   return .FwdDelete

		case .LEFT:  return .Left
		case .RIGHT: return .Right
		case .DOWN:  return .Down
		case .UP:    return .Up
	}

	return .None
}

dpi_hack_val := 0.0
create_context :: proc(pt: ^Platform_State, title: cstring, width, height: int) -> bool {
	pt.gfx = GFX_Context{}

	orig_window_width := i32(width)
	orig_window_height := i32(height)

	platform_pre_init(pt)

	dpi_hack_val = platform_dpi_hack()
	if dpi_hack_val > 0 {
		pt.dpr = dpi_hack_val
		orig_window_width = i32(f64(orig_window_width) * pt.dpr)
		orig_window_height = i32(f64(orig_window_height) * pt.dpr)
	}

	SDL.SetHint(SDL.HINT_MOUSE_FOCUS_CLICKTHROUGH, "1")
	SDL.SetHint(SDL.HINT_VIDEO_ALLOW_SCREENSAVER, "1")

	SDL.Init({.VIDEO})

	GL_VERSION_MAJOR :: 3
	GL_VERSION_MINOR :: 3
	SDL.GL_SetAttribute(.CONTEXT_PROFILE_MASK,  i32(SDL.GLprofile.CORE))
	SDL.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, GL_VERSION_MAJOR)
	SDL.GL_SetAttribute(.CONTEXT_MINOR_VERSION, GL_VERSION_MINOR)

	SDL.GL_SetAttribute(.MULTISAMPLEBUFFERS, 1)
	SDL.GL_SetAttribute(.MULTISAMPLESAMPLES, 2)
	SDL.GL_SetAttribute(SDL.GLattr.FRAMEBUFFER_SRGB_CAPABLE, 1)

	window := SDL.CreateWindow(title, SDL.WINDOWPOS_CENTERED, SDL.WINDOWPOS_CENTERED, i32(width), i32(height), {.OPENGL, .RESIZABLE, .ALLOW_HIGHDPI})
	if window == nil {
		fmt.eprintln("Failed to create window")
		os.exit(1)
	}

	platform_post_init(pt)

	pt.gfx.default_cursor = SDL.CreateSystemCursor(.ARROW)
	pt.gfx.pointer_cursor = SDL.CreateSystemCursor(.HAND)
	pt.gfx.text_cursor    = SDL.CreateSystemCursor(.IBEAM)

	pt.gfx.icon_width = 256
	pt.gfx.icon_height = 256
	pt.gfx.icon = SDL.CreateRGBSurfaceWithFormat(0, i32(pt.gfx.icon_width), i32(pt.gfx.icon_height), 32, u32(SDL.PixelFormatEnum.RGBA8888))

	gl_context := SDL.GL_CreateContext(window)
	if gl_context == nil {
		fmt.eprintln("Failed to create gl context!")
		os.exit(1)
	}

	gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, SDL.gl_set_proc_address)

	version_str := gl.GetString(gl.VERSION)
	if version_str == "1.1.0" {
		fmt.eprintf("GL version is too old! Got %s, needs at least %d.%d.0\n", version_str, GL_VERSION_MAJOR, GL_VERSION_MINOR)
		os.exit(1)
	}

	SDL.GL_SetSwapInterval(-1)

	real_window_width: i32
	real_window_height: i32
	pretend_window_width: i32
	pretend_window_height: i32
	SDL.GetWindowSize(window, &pretend_window_width, &pretend_window_height)
	SDL.GL_GetDrawableSize(window, &real_window_width, &real_window_height)
	width := f64(pretend_window_width)
	height := f64(pretend_window_height)

	// on certain platforms (windows) we need to grab the DPI explicitly, on certain (mac or linux)
	// we can infer it from the window size we got vs the window size we asked for (it scales it up
	// based on DPI).
	if dpi_hack_val < 0 {
		dpr_w := f64(real_window_width) / f64(pretend_window_width)
		dpr_h := f64(real_window_height) / f64(pretend_window_height)
		pt.dpr = dpr_w
		pt.width = width * pt.dpr
		pt.height = height * pt.dpr
	}

	pt.gfx.window = window
	pt.rects = make([dynamic]DrawRect)
	pt.text_rects = make([dynamic]TextRect)
	return true
}

get_next_event :: proc(pt: ^Platform_State, wait: bool) -> PlatformEvent {
	event: SDL.Event = ---
	ret: bool
	if wait {
		ret = bool(SDL.WaitEventTimeout(&event, 2000))
	} else {
		ret = bool(SDL.PollEvent(&event))
	}
	if !ret {
		return PlatformEvent{type = .None}
	}

	#partial switch event.type {
		case .QUIT: return PlatformEvent{type = .Exit}
		case .MOUSEMOTION: {
			x := f64(event.motion.x)
			y := f64(event.motion.y)
			if dpi_hack_val > 0 {
				x /= pt.dpr
				y /= pt.dpr
			}

			return PlatformEvent{type = .MouseMoved, x = x, y = y}
		}
		case .MOUSEBUTTONUP: {
			type := MouseButtonType.None
			switch event.button.button {
			case SDL.BUTTON_LEFT: type = .Left
			case SDL.BUTTON_RIGHT: type = .Right
			}
			if type != .None {
				x := f64(event.button.x)
				y := f64(event.button.y)
				if dpi_hack_val > 0 {
					x /= pt.dpr
					y /= pt.dpr
				}

				return PlatformEvent{type = .MouseUp, mouse = type, x = x, y = y}
			}
		}
		case .MOUSEBUTTONDOWN: {
			type := MouseButtonType.None
			switch event.button.button {
			case SDL.BUTTON_LEFT: type = .Left
			case SDL.BUTTON_RIGHT: type = .Right
			}
			if type != .None {
				x := f64(event.button.x)
				y := f64(event.button.y)
				if dpi_hack_val > 0 {
					x /= pt.dpr
					y /= pt.dpr
				}

				return PlatformEvent{type = .MouseDown, mouse = type, x = x, y = y}
			}
		}
		case .MOUSEWHEEL: {
			return PlatformEvent{type = .Scroll, y = f64(event.wheel.y)}
		}
		case .KEYDOWN: {
			key := _resolve_key(event.key.keysym.sym)
			return PlatformEvent{type = .KeyDown, key = key}
		}
		case .KEYUP: {
			key := _resolve_key(event.key.keysym.sym)
			return PlatformEvent{type = .KeyUp, key = key}
		}
		case .DROPFILE: {
			file_name := strings.clone_from_cstring(event.drop.file)
			SDL.free(rawptr(event.drop.file))
			return PlatformEvent{type = .FileDropped, str = file_name}
		}
		case .DROPTEXT: {
			SDL.free(rawptr(event.drop.file))
		}
		case .WINDOWEVENT: {
			#partial switch event.window.event {
				case .RESIZED: {
					w := f64(event.window.data1)
					h := f64(event.window.data2)
					if dpi_hack_val < 0 {
						w *= pt.dpr
						h *= pt.dpr
					}

					return PlatformEvent{type = .Resize, w = w, h = h}
				}
				case .FOCUS_GAINED: {
					return PlatformEvent{type = .FocusGained}
				}
				case .FOCUS_LOST: {
					return PlatformEvent{type = .FocusLost}
				}
			}
		}
	}

	return PlatformEvent{type = .More}
}

swap_buffers :: proc(gfx: ^GFX_Context) {
	SDL.GL_SwapWindow(gfx.window)
}

set_fullscreen :: proc(gfx: ^GFX_Context, fullscreen: bool) -> (int, int) {
	if fullscreen {
		SDL.SetWindowFullscreen(gfx.window, SDL.WINDOW_FULLSCREEN_DESKTOP)
	} else {
		SDL.SetWindowFullscreen(gfx.window, SDL.WindowFlags{})
	}
	iw : i32
	ih : i32
	SDL.GetWindowSize(gfx.window, &iw, &ih)
	return int(iw), int(ih)
}

set_cursor :: proc(pt: ^Platform_State, type: string) {
	switch type {
	case "auto":    SDL.SetCursor(pt.gfx.default_cursor)
	case "pointer": SDL.SetCursor(pt.gfx.pointer_cursor)
	case "text":    SDL.SetCursor(pt.gfx.text_cursor)
	}
	pt.is_hovering = true
}
reset_cursor :: proc(pt: ^Platform_State) { 
	set_cursor(pt, "auto") 
	pt.is_hovering = false
}

get_clipboard :: proc(gfx: ^GFX_Context) -> string {
	return string(SDL.GetClipboardText())
}
set_clipboard :: proc(gfx: ^GFX_Context, text: string) {
	cstr_text := strings.clone_to_cstring(text, context.temp_allocator)
	SDL.SetClipboardText(cstr_text)
}

set_window_title :: proc(pt: ^Platform_State, title: cstring) {
	SDL.SetWindowTitle(pt.gfx.window, title)
}

message_box :: proc(pt: ^Platform_State, title: cstring, message: cstring) {
	SDL.ShowSimpleMessageBox(SDL.MESSAGEBOX_ERROR, title, message, pt.gfx.window)
}

blit_clear :: proc(pt: ^Platform_State, color: BVec4) {
	icon_buffer_bytes := slice.bytes_from_ptr(pt.gfx.icon.pixels, pt.gfx.icon_width * pt.gfx.icon_height * 4)
	icon_buffer := transmute([]u32)(icon_buffer_bytes)

	for x := 0; x < pt.gfx.icon_width; x += 1 {
		for y := 0; y < pt.gfx.icon_height; y += 1 {
			pixel := color

			flat_pixel := u32(pixel.r) << 24 | u32(pixel.g) << 16 | u32(pixel.b) << 8 | 0
			icon_buffer[(y * pt.gfx.icon_width) + x] = flat_pixel
		}
	}
}

bvec4_to_dvec3 :: proc(color: BVec4) -> glsl.dvec3 {
	return glsl.dvec3{f64(color.r), f64(color.g), f64(color.b)}
}

bvec4_to_dvec4 :: proc(color: BVec4) -> glsl.dvec4 {
	return glsl.dvec4{f64(color.r), f64(color.g), f64(color.b), f64(color.a)}
}

blit_circle :: proc(pt: ^Platform_State, radius: f64, fill_perc: f64, color: BVec4, cut: bool = false) {
	icon_buffer_bytes := slice.bytes_from_ptr(pt.gfx.icon.pixels, pt.gfx.icon_width * pt.gfx.icon_height * 4)
	icon_buffer := transmute([]u32)(icon_buffer_bytes)

	center := glsl.dvec2{f64(pt.gfx.icon_width / 2), f64(pt.gfx.icon_height / 2)}
	for x := 0; x < pt.gfx.icon_width; x += 1 {
		for y := 0; y < pt.gfx.icon_height; y += 1 {
			cur_flat_pix := icon_buffer[(y * pt.gfx.icon_width) + x]
			old_pixel := BVec4{
				u8((cur_flat_pix >> 24) & 0xFF),
				u8((cur_flat_pix >> 16) & 0xFF),
				u8((cur_flat_pix >> 8) & 0xFF),
				u8((cur_flat_pix >> 0) & 0xFF),
			}
			pixel := color

			width := radius * pt.dpr
			frag_coord := glsl.dvec2{f64(x), f64(y)}
			pos := (frag_coord - center) / width

			angle := (glsl.atan2(pos.y, pos.x) / glsl.PI) * 0.5 + 0.5
			angle = glsl.mod(angle + 0.75, 1.0)

			alpha := 1.0 - glsl.step(0.5, glsl.length(pos))
			alpha = (1.0 - glsl.step(fill_perc, angle)) * alpha

			alpha_vec := glsl.dvec3{alpha, alpha, alpha}
			vc := ((1.0 - alpha) * bvec4_to_dvec3(old_pixel)) + alpha*bvec4_to_dvec3(pixel)
			vc = glsl.clamp(vc, 0, 255)
			
			a := ((1.0 - alpha) * f64(old_pixel.a)) + (255.0 * alpha)
			if cut {
				a = f64(old_pixel.a) * (255.0 * (1.0 - alpha))
			}
			a = glsl.clamp(a, 0, 255)

			icon_buffer[(y * pt.gfx.icon_width) + x] = u32(vc.r) << 24 | u32(vc.g) << 16 | u32(vc.b) << 8 | u32(a)
		}
	}
}

set_window_icon :: proc(pt: ^Platform_State) {
	SDL.SetWindowIcon(pt.gfx.window, pt.gfx.icon)
}
