//+build linux
package main

import "core:c"
import "core:sys/unix"
import "core:os"
import "core:fmt"
import "core:strings"
import "core:time"
import "core:strconv"
import "core:slice"

import "vendor:x11/xlib"
import "vendor:egl"
import gl "vendor:OpenGL"

GFX_Context :: struct {
	x_display: ^xlib.Display,
	egl_display: egl.Display,
	root_win: xlib.Window,
	window: xlib.Window,
	surface: egl.Surface,

	wm_protos:    xlib.Atom,
	delete_win:   xlib.Atom,
	utf8_string:  xlib.Atom,
	net_wm_state: xlib.Atom,
	net_wm_state_fullscreen: xlib.Atom,
	net_wm_name:             xlib.Atom,
	net_wm_icon_name:        xlib.Atom,

	dnd_enter:     xlib.Atom,
	dnd_position:  xlib.Atom,
	dnd_selection: xlib.Atom,
	dnd_status:      xlib.Atom,
	dnd_finished:    xlib.Atom,
	dnd_action_copy: xlib.Atom,
	dnd_drop:        xlib.Atom,
	dnd_type_list:   xlib.Atom,
	text_uri_list:   xlib.Atom,

	clipboard: xlib.Atom,
	targets: xlib.Atom,
	clipboard_stash: cstring,

	dnd_version: int,
	dnd_src_window: xlib.Window,
	dnd_format: xlib.Atom,
}

default_cursor: xlib.Cursor
pointer_cursor: xlib.Cursor
text_cursor: xlib.Cursor

open_file_dialog :: proc() -> (string, bool) {
	buffer := [4096]u8{}
	fds := [2]os.Handle{}
	ret := unix.sys_pipe2(raw_data(&fds), 0)

	pid, err := os.fork()
	if err != os.ERROR_NONE {
		fmt.printf("App uses Zenity for file dialogs! Please install Zenity to use the file dialog\n")
		unix.sys_close(int(fds[0]))
		unix.sys_close(int(fds[1]))
		return "", false
	}

	if pid == 0 {
		unix.sys_dup2(int(fds[1]), 1)
		unix.sys_close(int(fds[1]))
		unix.sys_close(int(fds[0]))
		os.execvp("zenity", []string{"--file-selection"})
		os.exit(1)
	}
	unix.sys_close(int(fds[1]))

	for {
		ret_bytes := unix.sys_read(int(fds[0]), raw_data(buffer[:]), len(buffer))
		if ret_bytes > 0 {
			unix.sys_close(int(fds[0]))
			return strings.clone_from_bytes(buffer[:ret_bytes-1]), true
		} else {
			break
		}
	}

	unix.sys_close(int(fds[0]))
	return "", false
}

_normalize_key :: proc(v: xlib.KeySym) -> KeyType {
	#partial switch v {
	case .XK_a: return .A
	case .XK_b: return .B
	case .XK_c: return .C
	case .XK_d: return .D
	case .XK_e: return .E
	case .XK_f: return .F
	case .XK_g: return .G
	case .XK_h: return .H
	case .XK_i: return .I
	case .XK_j: return .J
	case .XK_k: return .K
	case .XK_l: return .L
	case .XK_m: return .M
	case .XK_n: return .N
	case .XK_o: return .O
	case .XK_p: return .P
	case .XK_q: return .Q
	case .XK_r: return .R
	case .XK_s: return .S
	case .XK_t: return .T
	case .XK_u: return .U
	case .XK_v: return .V
	case .XK_w: return .W
	case .XK_x: return .X
	case .XK_y: return .Y
	case .XK_z: return .Z

	case .XK_0: return ._0
	case .XK_1: return ._1
	case .XK_2: return ._2
	case .XK_3: return ._3
	case .XK_4: return ._4
	case .XK_5: return ._5
	case .XK_6: return ._6
	case .XK_7: return ._7
	case .XK_8: return ._8
	case .XK_9: return ._9

	case .XK_equal: return .Equal
	case .XK_minus: return .Minus
	case .XK_bracketright: return .RightBracket
	case .XK_bracketleft: return .LeftBracket
	case .XK_leftsinglequotemark: return .Quote
	case .XK_semicolon:  return .Semicolon
	case .XK_backslash:  return .Backslash
	case .XK_comma:      return .Comma
	case .XK_slash:      return .Slash
	case .XK_period:     return .Period
	case .XK_grave:      return .Grave
	case .XK_Return:     return .Return
	case .XK_Tab:        return .Tab
	case .XK_space:      return .Space
	case .XK_BackSpace:  return .Delete
	case .XK_Escape:     return .Escape
	case .XK_Caps_Lock:  return .CapsLock
	case .XK_function:   return .Function

	case .XK_Super_R:    return .RightSuper
	case .XK_Super_L:    return .LeftSuper
	case .XK_Shift_R:    return .RightShift
	case .XK_Shift_L:    return .LeftShift
	case .XK_Alt_R:      return .RightAlt
	case .XK_Alt_L:      return .LeftAlt
	case .XK_Control_R:  return .RightControl
	case .XK_Control_L:  return .LeftControl

	case .XK_F1:         return .F1
	case .XK_F2:         return .F2
	case .XK_F3:         return .F3
	case .XK_F4:         return .F4
	case .XK_F5:         return .F5
	case .XK_F6:         return .F6
	case .XK_F7:         return .F7
	case .XK_F8:         return .F8
	case .XK_F9:         return .F9
	case .XK_F10:        return .F10
	case .XK_F11:        return .F11
	case .XK_F12:        return .F12
	case .XK_F13:        return .F13
	case .XK_F14:        return .F14
	case .XK_F15:        return .F16
	case .XK_F16:        return .F16
	case .XK_F17:        return .F17
	case .XK_F18:        return .F18
	case .XK_F19:        return .F19
	case .XK_F20:        return .F20

	case .XK_Home:      return .Home
	case .XK_Page_Up:   return .PageUp
	case .XK_Page_Down: return .PageDown
	case .XK_Delete:    return .FwdDelete
	case .XK_End:       return .End

	case .XK_Left:  return .Left
	case .XK_Right: return .Right
	case .XK_Down:  return .Down
	case .XK_Up:    return .Up
	}

	return .None
}

_get_dpi :: proc(x_display: ^xlib.Display) -> f32 {
	dpi : f32 = 96
	rms := xlib.ResourceManagerString(x_display)
	if rms == nil {
		return dpi
	}

	db := xlib.XrmGetStringDatabase(rms)
	if db == nil {
		return dpi
	}

	type : cstring
	value := xlib.XrmValue{}
	if !xlib.XrmGetResource(db, "Xft.dpi", "Xft.Dpi", &type, &value) {
		return dpi
	}

	dpi_str := string(cstring(value.addr))
	dpi = f32(strconv.atof(dpi_str))
	if dpi == 0 {
		return 96
	}

	return dpi
}

_create_cursor :: proc(display: ^xlib.Display, name: cstring, theme: cstring, size: i32, fallback: xlib.CursorShape) -> xlib.Cursor {

	if theme != nil {
		img := xlib.cursorLibraryLoadImage(name, theme, size)
		if img != nil {
			cursor := xlib.cursorImageLoadCursor(display, img)
			xlib.cursorImageDestroy(img)
			return cursor
		}
	}

	return xlib.CreateFontCursor(display, fallback)
}

_create_cursors :: proc(display: ^xlib.Display) {
	theme := xlib.cursorGetTheme(display)
	size := xlib.cursorGetDefaultSize(display)
	default_cursor = _create_cursor(display, "default", theme, size, .XC_left_ptr)
	pointer_cursor = _create_cursor(display, "pointer", theme, size, .XC_hand2)
	text_cursor = _create_cursor(display, "text", theme, size, .XC_xterm)
}

create_context :: proc(title: cstring, width, height: int) -> (GFX_Context, f64, f64, f64) {
	gfx := GFX_Context{}
	velocity_multiplier = -100

	dpy := xlib.OpenDisplay(nil)
	if dpy == nil {
		fmt.printf("Failed to open X!\n")
		os.exit(1)
	}

	vis := xlib.DefaultVisual(dpy, 0)
	root_win := xlib.DefaultRootWindow(dpy)

	wattr := xlib.XSetWindowAttributes{}
	wattr.event_mask = {
		.ButtonPress, .ButtonRelease, .PointerMotion,
		.KeyPress, .KeyRelease, 
		.EnterWindow, .LeaveWindow,
		.StructureNotify,
	}

	wmask := xlib.WindowAttributeMask{}
	wmask = {.CWEventMask}

	window := xlib.CreateWindow(dpy, root_win, 0, 0, u32(width), u32(height), 0, 0, .InputOutput, vis, wmask, &wattr)

	wm_proto                := xlib.InternAtom(dpy, "WM_PROTOCOLS", false)
	delete_win              := xlib.InternAtom(dpy, "WM_DELETE_WINDOW", false)
	xlib.SetWMProtocols(dpy, window, &delete_win, 1)

	utf8_string             := xlib.InternAtom(dpy, "UTF8_STRING", false)
	clipboard               := xlib.InternAtom(dpy, "CLIPBOARD", false)
	targets                 := xlib.InternAtom(dpy, "TARGETS", false)
	net_wm_name             := xlib.InternAtom(dpy, "_NET_WM_NAME", false)
	net_wm_icon_name        := xlib.InternAtom(dpy, "_NET_WM_ICON_NAME", false)
	net_wm_state            := xlib.InternAtom(dpy, "_NET_WM_STATE", false)
	net_wm_state_fullscreen := xlib.InternAtom(dpy, "_NET_WM_STATE_FULLSCREEN", false)

	dnd_aware               := xlib.InternAtom(dpy, "XdndAware", false)
	dnd_enter               := xlib.InternAtom(dpy, "XdndEnter", false)
	dnd_position            := xlib.InternAtom(dpy, "XdndPosition", false)
	dnd_status              := xlib.InternAtom(dpy, "XdndStatus", false)
	dnd_action_copy         := xlib.InternAtom(dpy, "XdndActionCopy", false)
	dnd_drop                := xlib.InternAtom(dpy, "XdndDrop", false)
	dnd_finished            := xlib.InternAtom(dpy, "XdndFinished", false)
	dnd_selection           := xlib.InternAtom(dpy, "XdndSelection", false)
	dnd_type_list           := xlib.InternAtom(dpy, "XdndTypeList", false)
	text_uri_list           := xlib.InternAtom(dpy, "text/uri-list", false)

	xlib.StoreName(dpy, window, title)
	xlib.MapRaised(dpy, window)

	egl_display := egl.GetDisplay(egl.NativeDisplayType(dpy))
	if egl_display == egl.NO_DISPLAY {
		fmt.printf("Failed to get display!\n")
		os.exit(1)
	}

	{
		major : i32 = 0
		minor : i32 = 0
		if egl.Initialize(egl_display, &major, &minor) == 0 {
			fmt.printf("Failed to init EGL display!\n")
			os.exit(1)
		}

		if major < 1 || (major == 1 && minor < 4) {
			fmt.printf("EGL version 1.4 required, got %d.%d\n", major, minor)
			os.exit(1)
		}

		if egl.BindAPI(egl.OPENGL_API) == 0 {
			fmt.printf("Failed to select OpenGL API!\n")
			os.exit(1)
		}
	}

	config := egl.Config{}
	{
		attr := [?]i32{
			egl.SURFACE_TYPE,	   egl.WINDOW_BIT,
			egl.CONFORMANT,		   egl.OPENGL_BIT,
			egl.RENDERABLE_TYPE,   egl.OPENGL_BIT,
			egl.COLOR_BUFFER_TYPE, egl.RGB_BUFFER,

			egl.RED_SIZE,	   8,
			egl.GREEN_SIZE,    8,
			egl.BLUE_SIZE,	   8,
			egl.DEPTH_SIZE,   24,
			egl.STENCIL_SIZE,  8,

			egl.NONE,
		}

		count : i32 = 0
		if egl.ChooseConfig(egl_display, raw_data(&attr), &config, 1, &count) == 0 || count != 1 {
			fmt.printf("Can't choose provided EGL config\n")
			os.exit(1)
		}
	}

	surface := egl.Surface{}
	{
		attr := [?]i32{
			egl.GL_COLORSPACE, egl.GL_COLORSPACE_LINEAR,
			egl.RENDER_BUFFER, egl.BACK_BUFFER,
			egl.NONE,
		}

		surface = egl.CreateWindowSurface(egl_display, config, egl.NativeWindowType(uintptr(window)), raw_data(&attr))
		if surface == egl.NO_SURFACE {
			fmt.printf("Cannot create EGL surface!\n")
			os.exit(1)
		}
	}

	major_version := 3
	minor_version := 3
	ctx := egl.Context{}
	{
		attr := [?]i32{
			egl.CONTEXT_MAJOR_VERSION, i32(major_version),
			egl.CONTEXT_MINOR_VERSION, i32(minor_version),
			egl.CONTEXT_OPENGL_PROFILE_MASK, egl.CONTEXT_OPENGL_CORE_PROFILE_BIT,
			egl.NONE,
		}

		ctx = egl.CreateContext(egl_display, config, egl.NO_CONTEXT, raw_data(&attr))
		if ctx == egl.NO_CONTEXT {
			fmt.printf("Unable to create EGL context, OpenGL 3.3 not supported?\n")
			os.exit(1)
		}
	}
	gl.load_up_to(major_version, minor_version, egl.gl_set_proc_address)

	egl.MakeCurrent(egl_display, surface, surface, ctx)
	egl.SwapInterval(egl_display, 1)
	xlib.MapWindow(dpy, window)
	xlib.XrmInitialize()

	_create_cursors(dpy)

	version := 5
	xlib.ChangeProperty(dpy, window, dnd_aware, xlib.XA_ATOM, 32, xlib.PropModeReplace, rawptr(&version), 1)

	dpr := f64(_get_dpi(dpy) / 96.0)

	gfx.x_display = dpy
	gfx.egl_display = egl_display
	gfx.root_win = root_win
	gfx.window = window
	gfx.surface = surface

	gfx.delete_win = delete_win
	gfx.wm_protos = wm_proto

	gfx.dnd_enter     = dnd_enter
	gfx.dnd_position  = dnd_position
	gfx.dnd_selection = dnd_selection
	gfx.dnd_finished  = dnd_finished
	gfx.dnd_drop      = dnd_drop
	gfx.dnd_action_copy = dnd_action_copy
	gfx.dnd_type_list   = dnd_type_list
	gfx.text_uri_list   = text_uri_list

	gfx.utf8_string             = utf8_string
	gfx.net_wm_name             = net_wm_name
	gfx.net_wm_icon_name        = net_wm_icon_name
	gfx.net_wm_state            = net_wm_state
	gfx.net_wm_state_fullscreen = net_wm_state_fullscreen
	gfx.clipboard               = clipboard
	gfx.targets                 = targets

	gfx.rects = make([dynamic]DrawRect)
	gfx.text_rects = make([dynamic]TextRect)
	return gfx, dpr, f64(width), f64(height)
}

_resolve_key :: proc(x_display: ^xlib.Display, keycode: u8) -> KeyType {
	dummy: i32
	keysyms := xlib.GetKeyboardMapping(x_display, u8(keycode), 1, &dummy)
	sym := slice.from_ptr(keysyms, 1)[0]
	key := _normalize_key(sym)
	xlib.Free(keysyms)
	return key
}

_x11_get_window_property :: proc(gfx: ^GFX_Context, window: xlib.Window, property: xlib.Atom, type: xlib.Atom, val: ^rawptr) -> uint {
	data : rawptr
	actual_type: xlib.Atom
	actual_fmt: i32
	item_count, bytes_after: uint

	xlib.GetWindowProperty(
		gfx.x_display,
		window, 
		property,
		0, 
		max(int),
		false,
		type,
		&actual_type,
		&actual_fmt,
		&item_count, 
		&bytes_after,
		&data,
	)

	val^ = data
	return item_count
}

_parse_dropped_files_list :: proc(data: cstring) -> string {
	file_list := strings.clone_from_cstring(data)
	files_iter := file_list
	path: string
	for str in strings.split_lines_iterator(&files_iter) {
		prefix := "file://"
		if !strings.has_prefix(str, prefix) {
			fmt.printf("Invalid file path?\n")
			os.exit(1)
		}

		path = strings.clone(str[len(prefix):])
		break
	}

	delete(file_list)
	return path
}

get_next_event :: proc(gfx: ^GFX_Context, wait: bool) -> PlatformEvent {
	if xlib.Pending(gfx.x_display) == 0 && !wait {
		return PlatformEvent{type = .None}
	}

	event: xlib.XEvent
	xlib.NextEvent(gfx.x_display, &event)
	#partial switch event.type {
	case .ClientMessage:
		switch event.xclient.message_type {
		case gfx.wm_protos:
			protocol := event.xclient.data.l[0]
			if xlib.Atom(protocol) == gfx.delete_win {
				return PlatformEvent{type = .Exit}
			}

		case gfx.dnd_enter:
			// New drag-and-drop event just entered the window
			src_win := xlib.Window(event.xclient.data.l[0])
			is_list := 0 != (event.xclient.data.l[1] & 0b1)
			version := event.xclient.data.l[1] >> 24
			gfx.dnd_format = 0

			fmts: rawptr
			count: uint
			if is_list {
				count = _x11_get_window_property(gfx, src_win, gfx.dnd_type_list, xlib.XA_ATOM, &fmts)
			} else {
				count = 3
				fmts = rawptr(&event.xclient.data.l[2])
			}

			if fmts != nil {
				raw_fmts_arr := slice.bytes_from_ptr(fmts, size_of(xlib.Atom))
				fmts_arr := transmute([]xlib.Atom)raw_fmts_arr
				for format in fmts_arr {
					if format == gfx.text_uri_list {
						gfx.dnd_format = format
						break
					}
				}
			}

			if is_list && fmts != nil {
				xlib.Free(fmts)
			}

			gfx.dnd_src_window = src_win
			gfx.dnd_version = version

		case gfx.dnd_position:
			// Confirm Position Update
			reply := xlib.XEvent{}
			reply.type = .ClientMessage
			reply.xclient.window = gfx.dnd_src_window
			reply.xclient.message_type = gfx.dnd_status
			reply.xclient.format = 32
			reply.xclient.data.l[0] = int(gfx.window)
			if gfx.dnd_format != 0 {
				reply.xclient.data.l[1] = 1
				reply.xclient.data.l[4] = int(gfx.dnd_action_copy)
			}
			xlib.SendEvent(gfx.x_display, gfx.dnd_src_window, false, {}, &reply)
			xlib.Flush(gfx.x_display)

		case gfx.dnd_drop:
			time := xlib.Time(event.xclient.data.l[2])
			xlib.ConvertSelection(gfx.x_display, gfx.dnd_selection, gfx.text_uri_list, gfx.dnd_selection, gfx.window, time)

			// Confirm Drop
			reply := xlib.XEvent{}
			reply.type = .ClientMessage
			reply.xclient.window = gfx.dnd_src_window
			reply.xclient.message_type = gfx.dnd_finished
			reply.xclient.format = 32
			reply.xclient.data.l[0] = int(gfx.window)
			reply.xclient.data.l[1] = 0
			reply.xclient.data.l[2] = 0
			xlib.SendEvent(gfx.x_display, gfx.dnd_src_window, false, {}, &reply)
			xlib.Flush(gfx.x_display)
		}

	case .SelectionNotify:
		if event.xselection.property == gfx.dnd_selection {

			data: rawptr
			result := _x11_get_window_property(gfx, event.xselection.requestor, event.xselection.property, event.xselection.target, &data)

			path := _parse_dropped_files_list(cstring(data))

			// Confirm Successful Transfer from Drop
			reply := xlib.XEvent{}
			reply.type = .ClientMessage
			reply.xclient.window = gfx.dnd_src_window
			reply.xclient.message_type = gfx.dnd_finished
			reply.xclient.format = 32
			reply.xclient.data.l[0] = int(gfx.window)
			reply.xclient.data.l[1] = int(result)
			reply.xclient.data.l[2] = int(gfx.dnd_action_copy)
			xlib.SendEvent(gfx.x_display, gfx.dnd_src_window, false, {}, &reply)
			xlib.Flush(gfx.x_display)

			return PlatformEvent{type = .FileDropped, str = path}
		}

	case .SelectionRequest:
		request := event.xselectionrequest
		is_selection_owner := xlib.GetSelectionOwner(gfx.x_display, gfx.clipboard) == gfx.window
		if is_selection_owner && request.selection == gfx.clipboard {

			send_event: xlib.XEvent
			send_event.xany.type            = .SelectionNotify
			send_event.xselection.selection = request.selection
			send_event.xselection.target    = 0
			send_event.xselection.property  = 0
			send_event.xselection.requestor = request.requestor
			send_event.xselection.time      = request.time

			if request.target == gfx.targets {
				xlib.ChangeProperty(gfx.x_display, request.requestor, request.property, xlib.XA_ATOM,
				32, xlib.PropModeReplace, &gfx.utf8_string, 1)

				send_event.xselection.property = request.property
				send_event.xselection.target = gfx.targets
			} else if request.target == gfx.utf8_string {
				xlib.ChangeProperty(gfx.x_display, request.requestor, request.property, request.target,
				8, xlib.PropModeReplace, rawptr(gfx.clipboard_stash), i32(len(gfx.clipboard_stash)))
				send_event.xselection.property = request.property
				send_event.xselection.target = request.target
			}

			xlib.SendEvent(gfx.x_display, request.requestor, false, {}, &send_event)
			xlib.Flush(gfx.x_display)
		}

	case .ButtonPress:
		type := MouseButtonType.None
		#partial switch event.xbutton.button {
		case .Button1: type = .Left
		case .Button2: type = .Middle
		case .Button3: type = .Right
		case:
			switch int(event.xbutton.button) {
			case 4: return PlatformEvent{type = .Scroll, x =  0, y =  1}
			case 5: return PlatformEvent{type = .Scroll, x =  0, y = -1}
			case 6: return PlatformEvent{type = .Scroll, x =  1, y =  0}
			case 7: return PlatformEvent{type = .Scroll, x = -1, y =  0}
			}
		}
		x := f64(event.xbutton.x) / dpr
		y := f64(event.xbutton.y) / dpr
		return PlatformEvent{type = .MouseDown, mouse = type, x = x, y = y}

	case .ButtonRelease:
		type := MouseButtonType.None
		#partial switch event.xbutton.button {
		case .Button1: type = .Left
		case .Button2: type = .Middle
		case .Button3: type = .Right
		}
		x := f64(event.xbutton.x) / dpr
		y := f64(event.xbutton.y) / dpr
		return PlatformEvent{type = .MouseUp, mouse = type, x = x, y = y}

	case .MotionNotify:
		x := f64(event.xmotion.x) / dpr
		y := f64(event.xmotion.y) / dpr
		return PlatformEvent{type = .MouseMoved, x = x, y = y}

	case .KeyPress:
		key := _resolve_key(gfx.x_display, u8(event.xkey.keycode))
		return PlatformEvent{type = .KeyDown, key = key}

	case .KeyRelease:
		key := _resolve_key(gfx.x_display, u8(event.xkey.keycode))
		return PlatformEvent{type = .KeyUp, key = key}

	case .ConfigureNotify:
		w := f64(event.xconfigure.width)
		h := f64(event.xconfigure.height)
		return PlatformEvent{type = .Resize, w = w, h = h}
	}
	return PlatformEvent{type = .More}
}

swap_buffers :: proc(gfx: ^GFX_Context) {
	egl.SwapBuffers(gfx.egl_display, gfx.surface)
}

_x11_send_event :: proc(gfx: ^GFX_Context, type: xlib.Atom, a, b, c, d, e: int) {
	event := xlib.XEvent{}
	event.type = .ClientMessage
	event.xclient.window = gfx.window
	event.xclient.format = 32
	event.xclient.message_type = type
	event.xclient.data.l[0] = a
	event.xclient.data.l[1] = b
	event.xclient.data.l[2] = c
	event.xclient.data.l[3] = d
	event.xclient.data.l[4] = e

	xlib.SendEvent(gfx.x_display, gfx.root_win, false, xlib.EventMask{.SubstructureNotify, .SubstructureRedirect}, &event)
}

set_fullscreen :: proc(gfx: ^GFX_Context, fullscreen: bool) -> (int, int) {
	if fullscreen {
		_x11_send_event(gfx, gfx.net_wm_state, 1, int(gfx.net_wm_state_fullscreen), 0, 1, 0)
	} else {
		_x11_send_event(gfx, gfx.net_wm_state, 0, int(gfx.net_wm_state_fullscreen), 0, 1, 0)
	}

	xlib.Flush(gfx.x_display)
	return 0, 0
}

get_clipboard :: proc(gfx: ^GFX_Context) -> string {
	return ""
}
set_clipboard :: proc(gfx: ^GFX_Context, text: string) {
	if gfx.clipboard_stash != "" {
		delete(gfx.clipboard_stash)
	}
	xlib.SetSelectionOwner(gfx.x_display, gfx.clipboard, gfx.window, xlib.CurrentTime)
	gfx.clipboard_stash = strings.clone_to_cstring(text)
}

set_window_title :: proc(gfx: ^GFX_Context, title: cstring) {
	xlib.utf8SetWMProperties(gfx.x_display, gfx.window, title, title, nil, 0, nil, nil, nil)
	xlib.ChangeProperty(gfx.x_display, gfx.window, gfx.net_wm_name, gfx.utf8_string, 8, xlib.PropModeReplace, rawptr(title), i32(len(title)))
	xlib.ChangeProperty(gfx.x_display, gfx.window, gfx.net_wm_icon_name, gfx.utf8_string, 8, xlib.PropModeReplace, rawptr(title), i32(len(title)))
	xlib.Flush(gfx.x_display)
}

set_cursor :: proc(gfx: ^GFX_Context, type: string) {
	switch type {
	case "auto":    xlib.DefineCursor(gfx.x_display, gfx.window, default_cursor)
	case "pointer": xlib.DefineCursor(gfx.x_display, gfx.window, pointer_cursor)
	case "text":    xlib.DefineCursor(gfx.x_display, gfx.window, text_cursor)
	}
	xlib.Flush(gfx.x_display)
	is_hovering = true
}
reset_cursor :: proc(gfx: ^GFX_Context) { 
	set_cursor(gfx, "auto") 
	is_hovering = false
}
