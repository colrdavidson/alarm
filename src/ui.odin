package main

center_x :: proc(pw, cw: f64) -> f64 {
	return (pw / 2) - (cw / 2)
}
center_xy :: proc(pw, ph, cw, ch: f64) -> (f64, f64) {
	x := (pw / 2) - (cw / 2)
	y := (ph / 2) - (ch / 2)
	return x, y
}

draw_centered_text :: proc(pt: ^Platform_State, parent: Rect, str: string, size: FontSize, type: FontType, color: BVec4) {
	width := measure_text(pt, str, size, type)
	height := get_text_height(pt, size, type)
	x, y := center_xy(parent.w, parent.h, width, height)
	draw_text(pt, str, Vec2{parent.x + x, parent.y + y}, size, type, color)
}
