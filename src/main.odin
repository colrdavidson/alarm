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

TaskDay :: enum {
	Sunday    = 0,
	Monday    = 1,
	Tuesday   = 2,
	Wednesday = 3,
	Thursday  = 4,
	Friday    = 5,
	Saturday  = 6,

	None = 7,
}
TaskMonth :: enum {
	January   = 0,
	February  = 1,
	March     = 2,
	April     = 3,
	June      = 4,
	July      = 5,
	August    = 6,
	September = 7,
	October   = 9,
	November  = 10,
	December  = 11,
}

TaskFreq :: enum {
	Once = 0,
	Secondly,
	Minutely,
	Hourly,
	Daily,
	Weekly,
	Monthly,
	Yearly,
}

TaskDayPos :: struct {
	day: TaskDay,
	pos: int,
}

Task :: struct {
	name:                 string,
	calendar:             string,
	redact:                 bool,

	start_time:        time.Time,
	start_tz:            cstring,

	until_time:        time.Time,

	freq:               TaskFreq,
	day_pos: [dynamic]TaskDayPos,
	months:          []TaskMonth,

	interval:                int,
	count:                   int,
}

Event :: struct {
	name:    string,
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

set_tz :: proc(tz: cstring) {
	if tz == "float" {
		unsetenv("TZ")
		tzset()
	} else {
		setenv("TZ", tz, 1)
		tzset()
	}
}
reset_tz :: proc() {
	unsetenv("TZ")
	tzset()
}

to_local_time :: proc(t: time.Time) -> time.Time {
	cur_ctime := time_to_ctime(t)
	ctm := libc.localtime(&cur_ctime)^
	return ctm_to_time(ctm)
}
time_to_str :: proc(t: time.Time) -> string {
	year, month, day := time.date(t)
	hour, minute, second := time.clock_from_time(t)

	am_pm_str := "AM"
	if hour > 12 {
		am_pm_str = "PM"
		hour -= 12
	}

	return fmt.tprintf("%02d-%02d-%04d @ %02d:%02d %s local", month, day, year, hour, minute, am_pm_str)
}

//  1 == d1 < d2
//  0 == d1 == d2
// -1 == d1 > d2
datetime_compare :: proc(d1: datetime.DateTime, d2: datetime.DateTime) -> int {
	ord1, _ := datetime.date_to_ordinal(d1)
	ord2, _ := datetime.date_to_ordinal(d2)

	if ord1 < ord2 {
		return 1
	} else if ord1 > ord2 {
		return -1
	}

	sec1 := i64(d1.hour) * 3600 + i64(d1.minute) * 60 + i64(d1.second)
	sec2 := i64(d2.hour) * 3600 + i64(d2.minute) * 60 + i64(d2.second)

	if sec1 > sec2 {
		return 1
	} else if sec1 < sec2 {
		return -1
	}

	return 0
}
time_compare :: proc(t1: time.Time, t2: time.Time) -> int {
	if t1._nsec > t2._nsec {
		return 1
	} else if t1._nsec < t2._nsec {
		return -1
	} else {
		return 0
	}
}

set_time :: proc(today: time.Time, task: Task) -> time.Time {
	set_tz(task.start_tz)
	hour, min, _ := time.clock_from_time(task.start_time)

	cur_ctime := time_to_ctime(today)
	ctm := libc.gmtime(&cur_ctime)^
	
	ctm.tm_hour = i32(hour)
	ctm.tm_min = i32(min)
	ctm.tm_sec = 0
	ctm.tm_isdst = -1

	next_event := ctime_to_time(libc.mktime(&ctm))

	reset_tz()
	return next_event
}

get_weekly :: proc(today: time.Time, task: Task, next: bool) -> time.Time {
	set_tz(task.start_tz)

	task_ctime := time_to_ctime(task.start_time)
	task_ctm := libc.gmtime(&task_ctime)^
	task_ctm.tm_isdst = -1
	task_time := ctime_to_time(libc.mktime(&task_ctm))

	task_dt, _ := time.time_to_datetime(task_time)
	task_ord, _ := datetime.date_to_ordinal(task_dt.date)

	reset_tz()

	today_dt, _ := time.time_to_datetime(today)
	today_ord, _ := datetime.date_to_ordinal(today_dt.date)

	week_skip := i64(7 * task.interval)
	date_dt := today_ord - task_ord
	closest_before_delta := date_dt / week_skip
	rem_before_delta := date_dt %% week_skip

	closest_task_ord := task_ord + (closest_before_delta * week_skip)
	closest_date, _ := datetime.ordinal_to_date(closest_task_ord)
	closest_dt, _ := datetime.components_to_datetime(closest_date.year, closest_date.month, closest_date.day, task_dt.hour, task_dt.minute, task_dt.second)

	if datetime_compare(closest_dt, today_dt) > 0 && next {
		closest_task_ord := task_ord + ((closest_before_delta + 1) * week_skip)
		closest_date, _ := datetime.ordinal_to_date(closest_task_ord)
		closest_dt, _ = datetime.components_to_datetime(closest_date.year, closest_date.month, closest_date.day, task_dt.hour, task_dt.minute, task_dt.second)
	}
	closest_time, _ := time.datetime_to_time(closest_dt)
	//fmt.printf("%v | unadjusted: %v | source: %v -- closest: %v\n", task.name, task.start_time, task_time, closest_time)
	return closest_time
}

get_monthly :: proc(today: time.Time, task: Task, daypos: TaskDayPos, next: bool) -> (out: time.Time, ok: bool) {
	set_tz(task.start_tz)

	task_ctime := time_to_ctime(task.start_time)
	task_ctm := libc.gmtime(&task_ctime)^
	task_ctm.tm_isdst = -1
	task_time := ctime_to_time(libc.mktime(&task_ctm))

	task_dt, _ := time.time_to_datetime(task_time)
	reset_tz()

	today_dt, _ := time.time_to_datetime(today)

	task_mord := i64(task_dt.year * 12) + i64(task_dt.month)
	today_mord := i64(today_dt.year * 12) + i64(today_dt.month)
	mord_dt := today_mord - task_mord

	month_skip := i64(task.interval)
	closest_before_delta := mord_dt / month_skip
	if next {
		closest_before_delta += 1
	}

	closest_mord := task_mord + (closest_before_delta * month_skip)
	closest_year := closest_mord / 12
	closest_month := closest_mord %% 12
	closest_day, _ := datetime.last_day_of_month(closest_year, closest_month)
	closest_task_date, _ := datetime.components_to_datetime(closest_year, closest_month, 1, task_dt.hour, task_dt.minute, task_dt.second)

	ord, _ := datetime.date_to_ordinal(closest_task_date.date)
	week_pos := datetime.day_of_week(ord)

	next_dt: datetime.DateTime
	err: datetime.Error
	if daypos.pos == -1 {
		last_ord, _ := datetime.components_to_ordinal(closest_task_date.year, closest_task_date.month, closest_day)
		last_weekday_pos := datetime.day_of_week(last_ord)

		d_pos := (i64(last_weekday_pos) - i64(daypos.day)) %% 7
		mday := i32(i64(closest_day) - d_pos)
		next_dt, _ = datetime.components_to_datetime(closest_task_date.year, closest_task_date.month, mday, task_dt.hour, task_dt.minute, task_dt.second)
	} else {
		d_pos := (i64(daypos.day) - i64(week_pos)) %% 7
		mday := i32(((i64(daypos.pos - 1) * 7) + d_pos) + 1)
		next_dt, err = datetime.components_to_datetime(closest_task_date.year, closest_task_date.month, mday, task_dt.hour, task_dt.minute, task_dt.second)
		if err != nil {
			return today, false
		}
	}

	next_event, _ := time.datetime_to_time(next_dt)
	return next_event, true
}

get_start_of_day :: proc(start_time: time.Time) -> time.Time {
	cur_ctime := time_to_ctime(start_time)
	ctm := libc.localtime(&cur_ctime)^

	ctm.tm_hour = 0
	ctm.tm_min  = 0
	ctm.tm_sec  = 0

	l_ctime := libc.mktime(&ctm)
	ctm = libc.localtime(&l_ctime)^
	return ctime_to_time(libc.mktime(&ctm))
}

curl_write_func :: proc "c" (ptr: rawptr, size: c.size_t, num: c.size_t, b: ^strings.Builder) -> c.size_t {
	context = runtime.default_context()

	bcount := size * num

	arr := slice.bytes_from_ptr(ptr, int(bcount))
	strings.write_bytes(b, arr)
	return bcount
}

parse_ical_ts :: proc(ts_str: string) -> (out_ts: time.Time, tz: string, ok: bool) {
	time_str := ""
	tz_str := ""

	if ts_str[0] == ';' {
		prop_str := ts_str[1:]

		prop_eq := strings.index_rune(prop_str, '=')
		prop_end := strings.index_rune(prop_str, ':')

		time_str = prop_str[prop_end+1:]
		prop_type := prop_str[:prop_eq]
		tz_str = prop_str[prop_eq+1:prop_end]

		if prop_type != "TZID" {
			return
		}
	} else {
		if ts_str[0] == ':' {
			time_str = ts_str[1:]
		} else {
			time_str = ts_str
		}

		if len(time_str) < 16 || time_str[15] != 'Z' {
			return
		}
		tz_str = "UTC"
	}

	if len(time_str) < 15 {
		return
	}

	year  := strconv.parse_int(time_str[:4], 10) or_return
	month := strconv.parse_int(time_str[4:6], 10) or_return
	day   := strconv.parse_int(time_str[6:8], 10) or_return

	hour   := strconv.parse_int(time_str[9:11], 10) or_return
	minute := strconv.parse_int(time_str[11:13], 10) or_return
	second := strconv.parse_int(time_str[13:15], 10) or_return

	ts := time.components_to_time(year, month, day, hour, minute, second, 0) or_return
	return ts, tz_str, true
}

parse_ical_rrule :: proc(task: ^Task, rrule: string) -> (ok: bool) {
	task.day_pos = make([dynamic]TaskDayPos)

	rule_chunks := strings.split(rrule, ";")
	for mod in rule_chunks {
		mod_chunks := strings.split(mod, "=")
		key := mod_chunks[0]
		val := mod_chunks[1]

		switch key {
		case "FREQ":
			switch val {
			case "DAILY":   task.freq = .Daily
			case "WEEKLY":  task.freq = .Weekly
			case "MONTHLY": task.freq = .Monthly
			case:
				fmt.printf("Unhandled freq: %v\n", val)
				return
			}

		case "UNTIL":
			ts, tz, ok := parse_ical_ts(val)
			if !ok {
				fmt.printf("Invalid ts: %v\n", val)
				return
			}
			if tz != "UTC" {
				fmt.printf("TODO: Handle non-UTC UNTIL: %v\n", val)
				return
			}

			task.until_time = ts

		case "BYDAY":
			new_day := TaskDayPos{}
			switch val {
			case "SU": new_day.day = .Sunday
			case "MO": new_day.day = .Monday
			case "TU": new_day.day = .Tuesday
			case "WE": new_day.day = .Wednesday
			case "TH": new_day.day = .Thursday
			case "FR": new_day.day = .Friday
			case "SA": new_day.day = .Saturday
			case:
				fmt.printf("Unhandled byday: %v\n", val)
				return
			}

			append(&task.day_pos, new_day)

		case "INTERVAL":
			interval := strconv.parse_int(val, 10) or_return
			task.interval = interval

		case "WKST":
			// TODO: Eh, whatever
		case:
			fmt.printf("Unhandled key: %v\n", key)
			return
		}
	}

	return true
}

CalEvent :: struct {
	summary:       string,
	dtstart:       string,
	dtend:         string,
	rrule:         string,
	recurrence_id: string,
	sequence:         int,
	uid:           string,
}

parse_ical_data :: proc(_data: string, tasks: ^[dynamic]Task, redact: bool) {
	data := _data

	cal_name := ""
	cal_events := make([dynamic]CalEvent)
	ev := CalEvent{}

	in_event := false
	for line in strings.split_lines_iterator(&data) {
		if line == "BEGIN:VEVENT" {
			in_event = true
			ev = CalEvent{sequence = -1}
			continue
		} else if line == "END:VEVENT" {
			append(&cal_events, ev)
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
			dtend_prefix := "DTEND"
			rrule_prefix := "RRULE:"
			recurrence_id_prefix := "RECURRENCE-ID"
			sequence_prefix := "SEQUENCE:"
			uid_prefix := "UID:"

			if strings.starts_with(line, summary_prefix) {
				ev.summary = line[len(summary_prefix):]

			} else if strings.starts_with(line, dtstart_prefix) {
				ev.dtstart = line[len(dtstart_prefix):]

			} else if strings.starts_with(line, dtend_prefix) {
				ev.dtend = line[len(dtend_prefix):]

			} else if strings.starts_with(line, rrule_prefix) {
				ev.rrule = line[len(rrule_prefix):]

			} else if strings.starts_with(line, sequence_prefix) {
				seq_str := line[len(sequence_prefix):]
				seq, ok := strconv.parse_int(seq_str, 10)
				if !ok {
					fmt.printf("Invalid sequence! %s\n", seq_str)
					return
				}
				ev.sequence = seq

			} else if strings.starts_with(line, uid_prefix) {
				ev.uid = line[len(uid_prefix):]
			} else if strings.starts_with(line, recurrence_id_prefix) {
				ev.recurrence_id = line[len(recurrence_id_prefix):]
			}
		}
	}
	calendar_name := strings.clone(cal_name)

	// Make a recurrence set chain, so we can refer to parents for event tweaks
	uid_map := make(map[string][dynamic]CalEvent)
	for ev, idx in cal_events {
		_, ok := uid_map[ev.uid]
		if !ok {
			uid_map[ev.uid] = make([dynamic]CalEvent)
		}

		cal_arr, _ := &uid_map[ev.uid]
		append(cal_arr, ev)
	}

	latest_events := make([dynamic]CalEvent)
	for _, cal_arr in uid_map {
		append(&latest_events, cal_arr[len(cal_arr)-1])
	}

	// Chug through and parse out timestamps and rules
	for cur_ev in latest_events {
		ev := cur_ev

		if ev.recurrence_id != "" {
			cal_arr := uid_map[ev.uid]
			orig_ev := cal_arr[0]
			ev.rrule = orig_ev.rrule
			ev.dtstart = orig_ev.dtstart
			ev.dtend = orig_ev.dtend
		}

		start_time, tz_str, ok := parse_ical_ts(ev.dtstart)
		if !ok {
			//fmt.printf("Failed to parse %v - %v\n", ev.summary, ev.dtstart)
			continue
		}

		task := Task{
			name = ev.summary,
			calendar = calendar_name,
			redact = redact,

			start_time = start_time,
			start_tz = strings.clone_to_cstring(tz_str),

			interval = 1,
			count = 0,
		}

		if ev.rrule != "" && !parse_ical_rrule(&task, ev.rrule) {
			fmt.printf("failed to parse rrule: %v - %v\n", ev.summary, ev.rrule)
			continue
		}

		append(tasks, task)
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

load_tasks :: proc(task_list: ^[dynamic]Task, config_path: string) {
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
	ExprByDay :: struct {
		pos: string,
		day: string,
	}
	TaskExpr :: struct {
		name:            string,
		start_time:      string,
		freq:            string,
		days:       []ExprByDay,
		tz:              string,
		interval:           int,
		count:              int,
		modifiers:     []string,
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

		parse_ical_data(string(out), task_list, file.redact)
	}

/*
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
		parse_ical_data(cal_data, task_list, url.redact)

		strings.builder_reset(&header_b)
		strings.builder_reset(&body_b)
	}
	curl.easy_cleanup(crl)
*/

	for task in cal_config.tasks {
		chunks := strings.split(task.start_time, "@")
		if len(chunks) != 2 {
			fmt.printf("Failed to parse task! %#v\n", task)
			return
		}

		year := 1900
		month := 1
		day := 1
		ymd := strings.split(chunks[0], "-")
		if len(ymd) != 3 && len(ymd) != 1 {
			fmt.printf("Invalid date format! %s\n", chunks[0])
			return
		}
		if len(ymd) == 3 {
			year_str  := strings.trim_left(strings.trim_space(ymd[0]), "0")
			month_str := strings.trim_left(strings.trim_space(ymd[1]), "0")
			day_str   := strings.trim_left(strings.trim_space(ymd[2]), "0")
			ok := false

			year, ok = strconv.parse_int(year_str, 10)
			if !ok {
				fmt.printf("Failed to parse task year! %s\n", year_str)
				return
			}
			month, ok = strconv.parse_int(month_str, 10)
			if !ok {
				fmt.printf("Failed to parse task month! %s\n", month_str)
				return
			}
			day, ok = strconv.parse_int(day_str, 10)
			if !ok {
				fmt.printf("Failed to parse task day! %s\n", day_str)
				return
			}
		}

		time_chunks := strings.fields(chunks[1])

		min := 0
		hour_min := strings.split(time_chunks[0], ":")

		hour, ok4 := strconv.parse_int(hour_min[0], 10)
		if !ok4 {
			fmt.printf("Failed to parse task hour! %s\n", task.start_time)
			return
		}
		if len(hour_min) == 2 {
			min, ok = strconv.parse_int(hour_min[1], 10)
			if !ok {
				fmt.printf("Failed to parse task min! %s\n", task.start_time)
				return
			}
		}

		am_pm_str := time_chunks[len(time_chunks)-1]
		if am_pm_str == "PM" {
			hour += 12
		}

		start_time, ok5 := time.components_to_time(year, month, day, hour, min, 0, 0)
		if !ok5 {
			fmt.printf("Invalid time! %v %v %v %v %v\n", year, month, day, hour, min)
			return
		}

		day_pos := make([dynamic]TaskDayPos)
		for daypos, idx in task.days {
			new_day := TaskDayPos{}
			switch daypos.pos {
			case "first":  new_day.pos = 1
			case "second": new_day.pos = 2
			case "third":  new_day.pos = 3
			case "fourth": new_day.pos = 4
			case "fifth":  new_day.pos = 5
			case "last":   new_day.pos = -1
			case "":       new_day.pos = 0
			case:
				fmt.printf("Invalid day pos! %s\n", daypos.pos)
				return
			}

			switch daypos.day {
			case "sun": new_day.day = .Sunday
			case "mon": new_day.day = .Monday
			case "tue": new_day.day = .Tuesday
			case "wed": new_day.day = .Wednesday
			case "thu": new_day.day = .Thursday
			case "fri": new_day.day = .Friday
			case "sat": new_day.day = .Saturday
			case:
				fmt.printf("Invalid task day! %s\n", daypos.day)
				return
			}
			append(&day_pos, new_day)
		}

		freq := TaskFreq.Once
		switch task.freq {
		case "once":    freq = .Once
		case "daily":   freq = .Daily
		case "weekly":  freq = .Weekly
		case "monthly": freq = .Monthly
		case "yearly":  freq = .Yearly
		case:
			fmt.printf("Invalid task freq %s\n", task.freq)
		}

		interval := task.interval
		if interval == 0 {
			interval = 1
		}

		tz_str := strings.clone_to_cstring(task.tz)
		months := []TaskMonth{}
		cur_task := Task{
			name       = task.name,
			start_time = start_time,
			start_tz   = tz_str,
			freq       = freq,
			day_pos    = day_pos,
			months     = months,

			interval = interval,
			count    = task.count,
		}
		append(task_list, cur_task)
	}
}

generate_events :: proc(task_list: []Task, now: time.Time) -> []Event {
	yesterday := get_start_of_day(time.time_add(now, -(24 * time.Hour)))
	today := get_start_of_day(now)
	tomorrow := get_start_of_day(time.time_add(now, (24 * time.Hour)))

	event_list := make([dynamic]Event)
	defer {
		unsetenv("TZ")
		tzset()
	}

	for &task, idx in task_list {

		task_name := task.name
		if task.redact {
			task_name = fmt.aprintf("Event from %s", task.calendar)
		}

		#partial switch task.freq {
		case .Once:
			append(&event_list, Event{task_name, task.start_time})
		case .Daily:
			append(&event_list, Event{task_name, set_time(yesterday, task)})
			append(&event_list, Event{task_name, set_time(today,     task)})
			append(&event_list, Event{task_name, set_time(tomorrow,  task)})
		case .Weekly:
			for daypos in task.day_pos {
				early_ev := Event{task_name, get_weekly(today, task, false)}
				late_ev  := Event{task_name, get_weekly(today, task, true)}

				if task.until_time._nsec == 0 || time_compare(early_ev.time, task.until_time) < 0 {
					append(&event_list, early_ev)
				}

				if task.until_time._nsec == 0 || time_compare(late_ev.time, task.until_time) < 0 {
					append(&event_list, late_ev)
				}
			}
		case .Monthly:
			for daypos in task.day_pos {
				tm, ok := get_monthly(today, task, daypos, false)
				if !ok {
					fmt.printf("failed to apply rule\n")
					continue
				}
				early_ev := Event{task_name, tm}

				tm, ok = get_monthly(today, task, daypos, true)
				if !ok {
					fmt.printf("failed to apply rule\n")
					continue
				}
				late_ev := Event{task_name, tm}

				if task.until_time._nsec == 0 || time_compare(early_ev.time, task.until_time) < 0 {
					append(&event_list, early_ev)
				}

				if task.until_time._nsec == 0 || time_compare(late_ev.time, task.until_time) < 0 {
					append(&event_list, late_ev)
				}
			}
		}
	}

	return event_list[:]
}

main :: proc() {
/*
	tz_ctx, ok := tzdb_init("/usr/share/zoneinfo", "/etc/localtime")
	if !ok {
		return
	}
	dt, _ := datetime.components_to_datetime(2024, 10, 1, 11, 46, 0)
	r_dt := _DateTime{dt.date, dt.time, "local"}
	l_dt := datetime_to_local(&tz_ctx, r_dt)
	u_dt := datetime_to_utc(&tz_ctx, l_dt)
	fmt.printf("%v\n", datetime_to_str(&tz_ctx, l_dt))
	fmt.printf("%v\n", datetime_to_str(&tz_ctx, u_dt))

	if true { return }
*/
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

	load_tasks(&task_list, "cal.json")
	event_list := generate_events(task_list[:], now)

	event_sort_proc :: proc(i, j: Event) -> bool {
		dur := time.diff(i.time, j.time)
		return dur > 0
	}
	slice.sort_by(event_list[:], event_sort_proc)

/*
	fmt.printf("%v | NOW\n", now)
	fmt.printf("%v | WHEEL START\n", start_time)
	for event, idx in event_list {
		fmt.printf("%v | %s\n", time_to_str(to_local_time(event.time)), event.name)
	}
*/

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

		cur_event_idx := -1
		#reverse for event, idx in event_list {
			rem_sec := time.duration_seconds(time.diff(current_time, event.time))
			if rem_sec <= 0 {
				continue
			}

			cur_event_idx = idx
		}

		event_chars := 20
		event_width := f64(event_chars) * pt.em
		if cur_event_idx >= 0 {
			start_idx := min(cur_event_idx + max_visible - 1, len(event_list) - 1)
			for i := start_idx; i >= cur_event_idx; i -= 1 {
				event := &event_list[i]

				total_sec := time.duration_seconds(time.diff(start_time, event.time))
				rem_sec := time.duration_seconds(time.diff(current_time, event.time))
				perc := rem_sec / total_sec

				color_idx := i % (len(pt.colors.active) - 1)

				ring_shrink := f64(cur_event_idx - i)
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

			cur_event := &event_list[cur_event_idx]
			h_1 := get_text_height(&pt, .H1Size, .DefaultFontBold)
			h_2 := get_text_height(&pt, .H1Size, .DefaultFont)
			h_3 := get_text_height(&pt, .H1Size, .MonoFont)
			h_gap := (pt.em / 2)
			total_h := h_1 + h_gap + h_2 + h_gap + h_3

			rem_time := time.duration_round(time.diff(current_time, cur_event.time), time.Second)
			buf := [time.MIN_HMS_LEN]u8{}
			rem_time_str := fmt.tprintf("%v", time.duration_to_string_hms(rem_time, buf[:]))

			y := center_x(container.h, total_h)

			wheel_text := "Up Next:"
			up_next_width := measure_text(&pt, wheel_text, .H1Size, .DefaultFontBold)
			event_name_width := measure_text(&pt, cur_event.name, .H1Size, .DefaultFont)
			rem_time_width := measure_text(&pt, rem_time_str, .H1Size, .MonoFont)
			max_width := max(up_next_width, event_name_width, rem_time_width)

			name := fmt.ctprintf("Alarm | Up Next: %s\n", cur_event.name)

			inner_diam := inner_radius * 2
			if max_width < inner_diam {
				x := center_x(inner_diam, max_width)
				draw_text(&pt, wheel_text, Vec2{(inner_center.x - inner_radius) + x, container.y + y}, .H1Size, .DefaultFontBold, pt.colors.text)

				short_name := trunc_name(&pt, cur_event.name, event_chars, .H1Size, .DefaultFont)
				draw_text(&pt, short_name, Vec2{(inner_center.x - inner_radius) + x, container.y + y + h_1 + h_gap}, .H1Size, .DefaultFont, pt.colors.text)

				rem_str_x := center_x(inner_diam, rem_time_width)
				draw_text(&pt, rem_time_str, Vec2{(inner_center.x - inner_radius) + rem_str_x, container.y + y + h_1 + h_gap + h_2 + h_gap}, .H1Size, .MonoFont, pt.colors.text)
			} else {
				name = fmt.ctprintf("%s\n", cur_event.name)
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
			draw_text(&pt, "Upcoming Events", Vec2{pt.em, next_y(&pt, &list_y, header_height)}, .H1Size, .DefaultFontBold, pt.colors.text)
			list_y += (pt.em * 0.1)

			idx := cur_event_idx
			for i := 0; i < list_max; i += 1 {
				event_height := get_text_height(&pt, .H1Size, .DefaultFont)
				padded_height := event_height + pt.em
				y_start := next_y(&pt, &list_y, padded_height)
				text_y := y_start + center_x(list_y - y_start, padded_height)

				if idx >= len(event_list) || idx < 0 {
					continue
				}

				event := &event_list[idx]

				text_color := pt.colors.dark_text
				if idx < (cur_event_idx + max_visible) {
					color_idx := idx % (len(pt.colors.active) - 1)
					draw_rect(&pt, Rect{pt.em, y_start, event_width + (pt.em * .5), padded_height}, pt.colors.active[color_idx])
				} else {
					text_color = pt.colors.text
				}

				short_name := trunc_name(&pt, event.name, event_chars, .H1Size, .DefaultFont)
				draw_text(&pt, short_name, Vec2{pt.em * 1.3, text_y}, .H1Size, .DefaultFont, text_color)
				idx += 1
			}

			list_y += pt.em
			header_height = get_text_height(&pt, .H1Size, .DefaultFontBold)
			draw_text(&pt, "Prior Events", Vec2{pt.em, next_y(&pt, &list_y, header_height)}, .H1Size, .DefaultFontBold, pt.colors.text)
			list_y += (pt.em * 0.1)

			idx = cur_event_idx - 1
			if cur_event_idx < 0 {
				idx = len(event_list) - 1
			}

			for i := list_max; i >= 0; i -= 1 {
				event_height := get_text_height(&pt, .H1Size, .DefaultFont)
				padded_height := event_height + pt.em
				y_start := next_y(&pt, &list_y, padded_height)
				text_y := y_start + center_x(list_y - y_start, padded_height)

				if idx >= len(event_list) || idx < 0 {
					continue
				}

				event := &event_list[idx]
				short_name := trunc_name(&pt, event.name, event_chars, .H1Size, .DefaultFont)
				draw_text(&pt, short_name, Vec2{pt.em * 1.3, text_y}, .H1Size, .DefaultFont, pt.colors.text)
				idx -= 1
			}
		}

		flush_rects(&pt)
		finish_frame(&pt)

		free_all(context.temp_allocator)
	}
}
