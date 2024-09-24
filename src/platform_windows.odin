//+build windows
package main

import "core:strings"
import "core:sys/windows"

foreign import user32 "system:User32.lib"
foreign user32 {
    GetDpiForSystem :: proc() -> u32 ---
}

platform_pre_init :: proc() {
	velocity_multiplier = -100
	windows.SetProcessDpiAwarenessContext(windows.DPI_AWARENESS_CONTEXT_SYSTEM_AWARE)

}
platform_post_init :: proc() { }

platform_dpi_hack :: proc() -> f64 {
    return f64(GetDpiForSystem()) / 96.0
}

open_file_dialog :: proc() -> (string, bool) {
	path_buf := make([]u16, windows.MAX_PATH_WIDE)
	if path_buf == nil {
		push_fatal(AppError.OutOfMemory)
	}
	defer delete(path_buf)

	filters := []string{"All Files", "*.*"}
	filter: string
	filter = strings.join(filters, "\u0000", context.temp_allocator)
	filter = strings.concatenate({filter, "\u0000"}, context.temp_allocator)

	title := "Select tracefile to open"
	dir := "."
	default_ext := ""

	ofn := windows.OPENFILENAMEW{
		lStructSize     = size_of(windows.OPENFILENAMEW),
		lpstrFile       = windows.wstring(&path_buf[0]),
		nMaxFile        = windows.MAX_PATH_WIDE,
		lpstrTitle      = windows.utf8_to_wstring(title, context.temp_allocator),
		lpstrFilter     = windows.utf8_to_wstring(filter, context.temp_allocator),
		lpstrInitialDir = windows.utf8_to_wstring(dir, context.temp_allocator),
		nFilterIndex    = 1,
		lpstrDefExt     = windows.utf8_to_wstring(default_ext, context.temp_allocator),
		Flags           = windows.OPEN_FLAGS,
	}

	ok := windows.GetOpenFileNameW(&ofn)
	if !ok {
		return "", false
	}

	file_name, _ := windows.utf16_to_utf8(path_buf[:], context.temp_allocator)
	trimmed_name := strings.trim_right_null(file_name)
	path := strings.clone(trimmed_name)
	return path, true
}

// we don't actually demangle on Windows, because Windows.
demangle_symbol :: proc(name: string, tmp_buffer: []u8) -> (string, bool) {
	return name, true
}

spawn_child :: proc(name: string, args: []string) -> bool {
	return false
}
