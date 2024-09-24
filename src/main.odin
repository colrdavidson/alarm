package main

import "core:os"
import "core:fmt"
import "core:time"

Task :: struct {
	name: string,
	time: time.Time,
}

main :: proc() {
	pt := Platform_State{}
	pt.p_height = 14
	pt.h1_height = 18
	pt.h2_height = 16
	pt.em = pt.p_height

	init_keymap(&pt)
	set_color_mode(&pt, false, true)

	create_context(&pt, "alarm", 1280, 720)
	if !setup_graphics(&pt) { return }

	stored_height := pt.height
	stored_width  := pt.width

	start_time := time.now()
	task_list := []Task{
		{"HMN Admin Meeting",          time.time_add(start_time, (10 * time.Second))},
		{"Handmade Co-Working Meetup", time.time_add(start_time, (1  * time.Minute))},
		{"Handmade Cities Meetup",     time.time_add(start_time, (2  * time.Minute))},
		{"Handmade Third Place",       time.time_add(start_time, (5  * time.Minute))},
		{"Pay Bills",                  time.time_add(start_time, (10 * time.Minute))},
		{"Eat Hot Chip and Lie",       time.time_add(start_time, (30 * time.Minute))},
	}
	max_visible := 4
	list_max    := 5

	ev := PlatformEvent{}
	main_loop: for {
		event_loop: for {
			ev = get_next_event(&pt, !pt.has_focus)
			if ev.type == .None {
				break event_loop
			}
			if !pt.awake {
				pt.was_sleeping = true
				pt.awake = true
			}

			#partial switch ev.type {
			case .Exit:
				break main_loop
			case .Resize:
				stored_height = ev.h
				stored_width  = ev.w
			case .FocusGained:
				pt.has_focus = true
			case .FocusLost:
				pt.has_focus = false
			}
		}

		setup_frame(&pt, int(stored_height), int(stored_width))

		current_time := time.now()

		side_min := min(pt.width / 2.5, pt.height / 2.5)
		x_pos, y_pos := center_xy(pt.width, pt.height, side_min, side_min)

		cur_task_idx := -1
		#reverse for task, idx in task_list {
			rem_sec := time.duration_seconds(time.diff(current_time, task.time))
			if rem_sec <= 0 {
				continue
			}

			cur_task_idx = idx
		}

		task_width := 0.0
		if cur_task_idx >= 0 {
			start_idx := min(cur_task_idx + max_visible - 1, len(task_list) - 1)
			for i := start_idx; i >= cur_task_idx; i -= 1 {
				task := &task_list[i]

				total_sec := time.duration_seconds(time.diff(start_time, task.time))
				rem_sec := time.duration_seconds(time.diff(current_time, task.time))
				perc := rem_sec / total_sec

				color_idx := i % (len(pt.colors.active) - 1)
				radius := ((pt.em * f64(cur_task_idx - i)) / 2) + side_min
				draw_circle(&pt, Vec2{pt.width / 2, pt.height / 2}, radius, perc, pt.colors.active[color_idx])

				task_width = max(measure_text(&pt, task.name, .H1Size, .DefaultFont), task_width)
			}

			inner_center := Vec2{pt.width / 2, pt.height / 2}
			inner_radius := side_min / 1.5
			draw_circle(&pt, inner_center, inner_radius, 1, pt.colors.bg2)

			container := Rect{x_pos, y_pos, side_min, side_min}

			cur_task := &task_list[cur_task_idx]
			h_1 := get_text_height(&pt, .H1Size, .DefaultFontBold)
			h_2 := get_text_height(&pt, .H1Size, .DefaultFont)
			h_gap := (pt.em / 2)
			total_h := h_1 + h_gap + h_2

			y := center_x(container.h, total_h)

			wheel_text := "Up Next:"
			up_next_width := measure_text(&pt, wheel_text, .H1Size, .DefaultFontBold)
			task_name_width := measure_text(&pt, cur_task.name, .H1Size, .DefaultFont)
			max_width := max(up_next_width, task_name_width)

			name := fmt.ctprintf("Alarm | Up Next: %s\n", cur_task.name)

			if max_width < (inner_radius * 2) {
				x := center_x(inner_radius * 2, max_width)
				draw_text(&pt, wheel_text, Vec2{(inner_center.x - inner_radius) + x, container.y + y}, .H1Size, .DefaultFontBold, pt.colors.text)
				draw_text(&pt, cur_task.name, Vec2{(inner_center.x - inner_radius) + x, container.y + y + h_1 + h_gap}, .H1Size, .DefaultFont, pt.colors.text)
			} else {
				name = fmt.ctprintf("%s\n", cur_task.name)
			}

			set_window_title(&pt, name)
		} else {
			set_window_title(&pt, "Alarm")
		}

		if pt.width >= 1000 {
			next_y :: proc(pt: ^Platform_State, y: ^f64, height: f64) -> f64 {
				cur_y := y^
				y^ = cur_y + height + (pt.em * .4)
				return cur_y
			}

			list_y := pt.em
			header_height := get_text_height(&pt, .H1Size, .DefaultFontBold)
			draw_text(&pt, "Upcoming Tasks", Vec2{pt.em, next_y(&pt, &list_y, header_height)}, .H1Size, .DefaultFontBold, pt.colors.text)
			list_y += (pt.em * 0.1)

			idx := cur_task_idx
			for i := 0; i < list_max; i += 1 {
				task_height := get_text_height(&pt, .H1Size, .DefaultFont)
				padded_height := task_height + pt.em
				y_start := next_y(&pt, &list_y, padded_height)
				text_y := y_start + center_x(list_y - y_start, padded_height)

				if idx >= len(task_list) || idx < 0 {
					continue
				}

				task := &task_list[idx]

				text_color := pt.colors.dark_text
				if idx < (cur_task_idx + max_visible) {
					color_idx := idx % (len(pt.colors.active) - 1)
					draw_rect(&pt, Rect{pt.em, y_start, task_width + (pt.em * .5), padded_height}, pt.colors.active[color_idx])
				} else {
					text_color = pt.colors.text
				}

				draw_text(&pt, task.name, Vec2{pt.em * 1.3, text_y}, .H1Size, .DefaultFont, text_color)
				idx += 1
			}

			list_y += pt.em
			header_height = get_text_height(&pt, .H1Size, .DefaultFontBold)
			draw_text(&pt, "Prior Tasks", Vec2{pt.em, next_y(&pt, &list_y, header_height)}, .H1Size, .DefaultFontBold, pt.colors.text)
			list_y += (pt.em * 0.1)

			idx = cur_task_idx - 1
			if cur_task_idx < 0 {
				idx = len(task_list) - 1
			}

			for i := list_max; i >= 0; i -= 1 {
				task_height := get_text_height(&pt, .H1Size, .DefaultFont)
				padded_height := task_height + pt.em
				y_start := next_y(&pt, &list_y, padded_height)
				text_y := y_start + center_x(list_y - y_start, padded_height)

				if idx >= len(task_list) || idx < 0 {
					continue
				}

				task := &task_list[idx]
				draw_text(&pt, task.name, Vec2{pt.em * 1.3, text_y}, .H1Size, .DefaultFont, pt.colors.text)
				idx -= 1
			}
		}

		flush_rects(&pt)
		finish_frame(&pt)

		free_all(context.temp_allocator)
	}
}
