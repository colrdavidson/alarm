package main

import "base:runtime"

import "core:c"
import "core:c/libc"
import "core:sys/posix"

import "core:os"
import "core:fmt"
import "core:net"
import "core:slice"
import "core:strings"
import "core:strconv"
import "core:time"
import "core:time/datetime"
import "core:path/filepath"
import "core:encoding/json"

import "libs:curl"

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
	orig_ctm := libc.localtime(&cur_ctime)^
	ctm := libc.localtime(&cur_ctime)^
	
	ctm.tm_hour = i32(hour)
	ctm.tm_min = i32(minute)
	ctm.tm_sec = 0

	tmp_ctime := libc.mktime(&ctm)
	if libc.difftime(tmp_ctime, cur_ctime) > 0 {
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

get_start_of_day :: proc(start_time: time.Time) -> time.Time {
	cur_ctime := time_to_ctime(start_time)
	ctm := libc.localtime(&cur_ctime)^

	ctm.tm_hour = 0
	ctm.tm_min  = 0
	ctm.tm_sec  = 0

	ctm = normalize_tm(ctm)
	return ctime_to_time(libc.mktime(&ctm))
}

curl_write_func :: proc "c" (ptr: rawptr, size: c.size_t, num: c.size_t, b: ^strings.Builder) -> c.size_t {
	context = runtime.default_context()

	bcount := size * num

	arr := slice.bytes_from_ptr(ptr, int(bcount))
	strings.write_bytes(b, arr)
	return bcount
}

parse_ical_data :: proc(_data: string, tasks: ^[dynamic]Task, frontier: time.Time, redact: bool) {
	data := _data

	tmp_task := Task{}
	nil_time := time.Time{_nsec = 0}
	cal_name := ""

	in_event := false
	for line in strings.split_lines_iterator(&data) {
		if line == "BEGIN:VEVENT" {
			in_event = true
			continue
		} else if line == "END:VEVENT" {
			delta := time.diff(frontier, tmp_task.time)
			if tmp_task.time != nil_time && tmp_task.name != "" && delta >= 0 {
				if redact {
					tmp_task.name = fmt.aprintf("Event from %s", cal_name)
				} else {
					tmp_task.name = strings.clone(tmp_task.name)
				}
				append(tasks, tmp_task)
			}

			tmp_task = Task{}
			in_event = false
			continue
		} else if cal_name == "" {
			cal_name_prefix := "X-WR-CALNAME:"
			if strings.starts_with(line, cal_name_prefix) {
				cal_name = line[len(cal_name_prefix):]
			}
		}

		if in_event {
			summary_prefix := "SUMMARY:"
			dtstart_prefix := "DTSTART"

			if strings.starts_with(line, summary_prefix) {
				tmp_task.name = line[len(summary_prefix):]
			} else if strings.starts_with(line, dtstart_prefix) {
				time_str := line[len(dtstart_prefix)+1:]
				if time_str[0] != '2' || len(time_str) < 16 {
					continue
				}

				// only handling utc timestamps
				if time_str[15] != 'Z' {
					continue
				}

				year  := strconv.parse_int(time_str[:4], 10) or_else -1
				month := strconv.parse_int(time_str[4:6], 10) or_else -1
				day   := strconv.parse_int(time_str[6:8], 10) or_else -1

				hour   := strconv.parse_int(time_str[9:11], 10) or_else -1
				minute := strconv.parse_int(time_str[11:13], 10) or_else -1
				second := strconv.parse_int(time_str[13:15], 10) or_else -1

				start_time, ok := time.components_to_time(year, month, day, hour, minute, second, 0)
				if !ok { continue }

				tmp_task.time = start_time
			}
		}
	}
}

trunc_name :: proc(pt: ^Platform_State, name: string, max_chars: int, scale: FontSize, font_type: FontType) -> string {
	name_width := measure_text(pt, name, scale, font_type)
	ellipsis_width := measure_text(pt, "...", scale, font_type)
	approx_max_width := f64(max_chars) * pt.em

	if (name_width + ellipsis_width) > approx_max_width {
		str_end := min(len(name), max_chars+4)
		return fmt.tprintf("%s...", name[:str_end])
	} else {
		return fmt.tprintf(name)
	}
}

load_tasks :: proc(pt: ^Platform_State, task_list: ^[dynamic]Task, config_path: string, now: time.Time, start_time: time.Time) {
	config, ok := os.read_entire_file_from_filename(config_path)
	if !ok {
		// If we're a .app, try harder...
		when ODIN_OS == .Darwin {
			path_buf := [8192]u8{}
			app_path, ok2 := get_app_path(path_buf[:])
			if !ok2 {
				return
			}

			app_dir := filepath.dir(app_path)
			tmp_dir := filepath.join([]string{app_dir, "../../../.."})
			real_dir := filepath.clean(tmp_dir)
			second_try := filepath.join([]string{real_dir, config_path})
			config, ok = os.read_entire_file_from_filename(second_try)
			if !ok {
				fmt.printf("Unable to load calendar config @ %s\n", second_try)
				return
			}
		} else {
			fmt.printf("Unable to load calendar config @ %s\n", config_path)
			return
		}
	}

	File :: struct {
		path: string,
		redact: bool,
	}
	Url :: struct {
		path: string,
		redact: bool,
	}
	TaskExpr :: struct {
		kind: string,
		name: string,
		day: string,
		time: string,
		tz: string,
		started: string,
		modifiers: []string,
	}
	CalConfig :: struct {
		files: []File,
		urls:  []Url,
		tasks: []TaskExpr,
	}
	cal_config := CalConfig{}
	err := json.unmarshal(config, &cal_config)
	if err != nil {
		fmt.printf("%v\n", err)
		return
	}

	home_dir := os.get_env("HOME")
	for file in cal_config.files {
		path := ""
		if file.path[0] == '~' {
			path = fmt.tprintf("%s/%s", home_dir, file.path[1:])
		}

		out, ok2 := os.read_entire_file_from_filename(path)
		if !ok {
			fmt.printf("Unable to find ical data at %s\n", path)
			return
		}

		parse_ical_data(string(out), task_list, now, file.redact)
	}

	crl := curl.easy_init()
	header_b := strings.builder_make()
	body_b := strings.builder_make()
	for url in cal_config.urls {
		curl.easy_setopt(crl, curl.OPT_URL, url.path)
		curl.easy_setopt(crl, curl.OPT_NOPROGRESS, 1)
		curl.easy_setopt(crl, curl.OPT_WRITEFUNCTION, curl_write_func)
		curl.easy_setopt(crl, curl.OPT_WRITEDATA, &body_b)
		curl.easy_setopt(crl, curl.OPT_HEADERDATA, &header_b)

		curl.easy_perform(crl)
		cal_data := strings.to_string(body_b)
		parse_ical_data(cal_data, task_list, now, url.redact)

		strings.builder_reset(&header_b)
		strings.builder_reset(&body_b)
	}
	curl.easy_cleanup(crl)

	for task in cal_config.tasks {
		chunks := strings.fields(task.time)
		if len(chunks) == 0 {
			fmt.printf("Failed to parse task! %#v\n", task)
			return
		}

		min := 0
		hour_min := strings.split(chunks[0], ":")

		hour, ok := strconv.parse_int(hour_min[0], 10)
		if !ok {
			fmt.printf("Failed to parse task hour! %s\n", task.time)
			return
		}
		if len(hour_min) == 2 {
			min, ok = strconv.parse_int(hour_min[1], 10)
			if !ok {
				fmt.printf("Failed to parse task min! %s\n", task.time)
				return
			}
		}

		am_pm_str := chunks[len(chunks)-1]
		if am_pm_str == "PM" {
			hour += 12
		}

		weekday := -1
		switch task.day {
		case "all":      weekday = -1
		case "sunday":    weekday = 0
		case "monday":    weekday = 1
		case "tuesday":   weekday = 2
		case "wednesday": weekday = 3
		case "thursday":  weekday = 4
		case "friday":    weekday = 5
		case "saturday":  weekday = 6
		case:
			fmt.printf("Invalid task day! %s\n", task.day)
			return
		}

		switch task.kind {
		case "daily":
			append(task_list, Task{task.name, get_next_time(start_time, hour, min)})

		case "weekly":
			append(task_list, Task{task.name, get_next_day_and_time(start_time, weekday, hour, min)})

		case "monthly":
			found_last := false
			for mod in task.modifiers {
				if mod == "last" {
					found_last = true
					break
				}
			}
			if !found_last {
				fmt.printf("normal monthly not yet handled!\n")
				return
			}

			append(task_list, Task{task.name, get_next_last_day(start_time, weekday, hour, min)})

		case "biweekly":
			append(task_list, Task{task.name, get_next_day_and_time(start_time, weekday, hour, min)})
		case:
			fmt.printf("Invalid task kind! %s\n", task.kind)
			return
		}
	}
}


main :: proc() {
	now := time.now()
	start_time := get_start_of_day(now)

	task_list := make([dynamic]Task)

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

	load_tasks(&pt, &task_list, "cal.json", now, start_time)

	task_sort_proc :: proc(i, j: Task) -> bool {
		dur := time.diff(i.time, j.time)
		return dur > 0
	}
	slice.sort_by(task_list[:], task_sort_proc)

	fmt.printf("%v | NOW\n", now)
	fmt.printf("%v | WHEEL START\n", start_time)
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
		blit_clear(&pt, pt.colors.bg)

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

		task_chars := 20
		task_width := f64(task_chars) * pt.em
		if cur_task_idx >= 0 {
			start_idx := min(cur_task_idx + max_visible - 1, len(task_list) - 1)
			for i := start_idx; i >= cur_task_idx; i -= 1 {
				task := &task_list[i]

				total_sec := time.duration_seconds(time.diff(start_time, task.time))
				rem_sec := time.duration_seconds(time.diff(current_time, task.time))
				perc := rem_sec / total_sec

				color_idx := i % (len(pt.colors.active) - 1)

				ring_shrink := f64(cur_task_idx - i)
				radius := ((pt.em * ring_shrink) / 2) + side_min
				draw_circle(&pt, Vec2{pt.width / 2, pt.height / 2}, radius, perc, pt.colors.active[color_idx])

				blit_circle(&pt, 128 * 0.75, perc, pt.colors.active[color_idx])
			}

			inner_center := Vec2{pt.width / 2, pt.height / 2}
			inner_radius := side_min / 1.5
			draw_circle(&pt, inner_center, inner_radius, 1, pt.colors.bg2)
			blit_circle(&pt, 128.0 * 0.5, 1, pt.colors.bg2, true)
			set_window_icon(&pt)

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

				short_name := trunc_name(&pt, task.name, task_chars, .H1Size, .DefaultFont)
				draw_text(&pt, short_name, Vec2{pt.em * 1.3, text_y}, .H1Size, .DefaultFont, text_color)
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
