package main

import "core:os"
import "core:fmt"
import "core:slice"
import "core:c/libc"
import "core:time"

Task :: struct {
	name: string,
	time: time.Time,
}

time_to_ctm :: proc(tm: time.Time) -> libc.tm {
	dtm, _ := time.time_to_datetime(tm)
	ctm := libc.tm{
		tm_sec  = i32(dtm.time.second),
		tm_min  = i32(dtm.time.minute),
		tm_hour = i32(dtm.time.hour),
		tm_mday = i32(dtm.date.day),
		tm_mon  = i32(dtm.date.month - 1),
		tm_year = i32(dtm.date.year - 1900),
		tm_isdst = 0,
	}
	return ctm
}
time_to_ctime :: proc(tm: time.Time) -> libc.time_t {
	return libc.time_t(time.to_unix_seconds(tm))
}
ctm_to_time :: proc(_ctm: libc.tm) -> time.Time {
	ctm := _ctm
	tm, _ := time.components_to_time(
		ctm.tm_year + 1900,
		ctm.tm_mon + 1,
		ctm.tm_mday,
		ctm.tm_hour,
		ctm.tm_min,
		ctm.tm_sec,
	)
	return tm
}
ctime_to_time :: proc(_ctime: libc.time_t) -> time.Time {
	ctime := _ctime
	ctm := libc.gmtime(&ctime)^
	return ctm_to_time(ctm)
}

get_next_time :: proc(start_time: time.Time, hour: int, minute: int) -> time.Time {
	cur_ctime := time_to_ctime(start_time)
	ctm := libc.localtime(&cur_ctime)^
	
	ctm.tm_hour = i32(hour)
	ctm.tm_min = i32(minute)
	ctm.tm_sec = 0

	tmp_ctime := libc.mktime(&ctm)
	if libc.difftime(tmp_ctime, cur_ctime) < 0 {
		ctm.tm_mday += 1
	}

	next_event := ctime_to_time(libc.mktime(&ctm))

	return next_event
}

get_next_day_and_time :: proc(start_time: time.Time, weekday: int, hour: int, minute: int) -> time.Time {
	cur_ctime := time_to_ctime(start_time)
	ctm := libc.localtime(&cur_ctime)^

	ctm.tm_hour = i32(hour)
	ctm.tm_min = i32(minute)
	ctm.tm_sec = 0

	day_delta := i32(weekday) - ctm.tm_wday
	if day_delta == 0 {
		tmp_ctime := libc.mktime(&ctm)
		if libc.difftime(tmp_ctime, cur_ctime) < 0 {
			ctm.tm_mday += 7
		}
	} else if day_delta < 0 {
		ctm.tm_mday += (7 + day_delta)
	} else {
		ctm.tm_mday += day_delta
	}

	next_event := ctime_to_time(libc.mktime(&ctm))
	return next_event
}

normalize_tm :: proc(_tm: libc.tm) -> libc.tm {
	tm := _tm
	l_ctime := libc.mktime(&tm)
	return libc.localtime(&l_ctime)^
}

get_next_last_day :: proc(start_time: time.Time, weekday, hour, minute: int) -> time.Time {
	cur_ctime := time_to_ctime(start_time)
	ctm := libc.localtime(&cur_ctime)^

	ctm.tm_hour = i32(hour)
	ctm.tm_min = i32(minute)
	ctm.tm_sec = 0
	ctm.tm_mday = 0
	ctm.tm_mon += 1
	ctm = normalize_tm(ctm)

	day_delta := i32(weekday) - ctm.tm_wday
	day_off := 7 - day_delta - 1
	if day_delta > 0 {
		day_off *= -1
	}
	ctm.tm_mday += day_off
	ctm = normalize_tm(ctm)

	tmp_ctime := libc.mktime(&ctm)
	if libc.difftime(tmp_ctime, cur_ctime) < 0 {
		ctm.tm_mday = 0
		ctm.tm_mon += 2
		ctm = normalize_tm(ctm)

		day_delta := i32(weekday) - ctm.tm_wday
		day_off := 7 - day_delta - 1
		if day_delta > 0 {
			day_off *= -1
		}

		ctm.tm_mday += day_off
		ctm = normalize_tm(ctm)
	}

	next_event := ctime_to_time(libc.mktime(&ctm))
	return next_event
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
	fmt.printf("%v | NOW\n", start_time)

	task_list := []Task{
		{"Wake Up",                    get_next_time(start_time, 11, 0)},
		{"Bed Time",                   get_next_time(start_time, 2, 0)},
		{"HMN Admin Meeting",          get_next_day_and_time(start_time, 1, 15, 0)},
		{"Handmade Co-Working Meetup", get_next_day_and_time(start_time, 3, 15, 0)},
		{"Handmade Cities Meetup",     get_next_last_day(start_time, 6, 15, 0)},
	}

/*
	wakeup := get_next_time(start_time, 6, 0)
	task_list := []Task{
		{"Wake Up",                    wakeup},
		{"Read My Blogs",              time.time_add(wakeup, 1 * time.Hour)},
		{"Hop over to Ground Central", time.time_add(wakeup, (2 * time.Hour) + (30 * time.Minute))},
		{"Time for Standup",           time.time_add(wakeup, (4 * time.Hour))},
		{"News Blast",                 time.time_add(wakeup, (5 * time.Hour) + (30 * time.Minute))},
		{"Vegan Bolognese",            time.time_add(wakeup, (6 * time.Hour))},
		{"Call it a Day",              time.time_add(wakeup, (14 * time.Hour) + (30 * time.Minute))},
		{"Happy Hour",                 time.time_add(wakeup, (15 * time.Hour))},
		{"Back In Bed",                time.time_add(wakeup, (25 * time.Hour) + (37 * time.Minute))},
	}
*/

	task_sort_proc :: proc(i, j: Task) -> bool {
		dur := time.diff(i.time, j.time)
		return dur > 0
	}
	slice.sort_by(task_list[:], task_sort_proc)
	for task, idx in task_list {
		fmt.printf("%v | %s\n", task.time, task.name)
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
			h_3 := get_text_height(&pt, .H1Size, .MonoFont)
			h_gap := (pt.em / 2)
			total_h := h_1 + h_gap + h_2 + h_gap + h_3

			rem_time := time.duration_round(time.diff(current_time, cur_task.time), time.Second)
			buf := [time.MIN_HMS_LEN]u8{}
			rem_time_str := fmt.tprintf("%v", time.duration_to_string_hms(rem_time, buf[:]))

			y := center_x(container.h, total_h)

			wheel_text := "Up Next:"
			up_next_width := measure_text(&pt, wheel_text, .H1Size, .DefaultFontBold)
			task_name_width := measure_text(&pt, cur_task.name, .H1Size, .DefaultFont)
			rem_time_width := measure_text(&pt, rem_time_str, .H1Size, .MonoFont)
			max_width := max(up_next_width, task_name_width, rem_time_width)

			name := fmt.ctprintf("Alarm | Up Next: %s\n", cur_task.name)

			inner_diam := inner_radius * 2
			if max_width < inner_diam {
				x := center_x(inner_diam, max_width)
				draw_text(&pt, wheel_text, Vec2{(inner_center.x - inner_radius) + x, container.y + y}, .H1Size, .DefaultFontBold, pt.colors.text)
				draw_text(&pt, cur_task.name, Vec2{(inner_center.x - inner_radius) + x, container.y + y + h_1 + h_gap}, .H1Size, .DefaultFont, pt.colors.text)

				rem_str_x := center_x(inner_diam, rem_time_width)
				draw_text(&pt, rem_time_str, Vec2{(inner_center.x - inner_radius) + rem_str_x, container.y + y + h_1 + h_gap + h_2 + h_gap}, .H1Size, .MonoFont, pt.colors.text)
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
