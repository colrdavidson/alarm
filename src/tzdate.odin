package main

import "base:runtime"

import "core:fmt"
import "core:os"
import "core:time"
import "core:time/datetime"
import "core:path/filepath"
import "core:strings"

TZ_Context :: struct {
	db_path:               string,
	local_name:            string,
	regions: map[string]TZ_Region,

	allocator: runtime.Allocator,
}

_DateTime :: struct {
	using date: datetime.Date,
	using time: datetime.Time,
	tz: string,
}

tzdb_init :: proc(db_path: string, local_path: string, allocator := context.allocator) -> (tz_ctx: TZ_Context, success: bool) {
	path, err := os.absolute_path_from_relative(local_path)
	if err != nil {
		return
	}
	tzone_base := filepath.base(path)

	tmp_path := filepath.join([]string{path, ".."})
	cleaned_path := filepath.clean(tmp_path)
	delete(tmp_path)

	parent_dir := filepath.base(cleaned_path)
	tzone_name := filepath.join([]string{parent_dir, tzone_base})
	delete(cleaned_path)

	return TZ_Context{
		db_path = strings.clone(db_path, allocator), 
		local_name = tzone_name, 
		regions = make(map[string]TZ_Region, 8, allocator),
		allocator = allocator,
	}, true
}

tzdb_destroy :: proc(tzdb: ^TZ_Context) {
	for key, val in tzdb.regions {
		region_destroy(val)
		delete(key)
	}
	delete(tzdb.regions)
	delete(tzdb.db_path)
	delete(tzdb.local_name)
}

tzdb_get_region :: proc(tzdb: ^TZ_Context, _reg_str: string) -> (out_reg: TZ_Region, success: bool) {
	reg_str := _reg_str

	region, ok := tzdb.regions[reg_str]
	if !ok {
		if reg_str == "local" {
			reg_str = tzdb.local_name
		}

		region_path := filepath.join([]string{tzdb.db_path, reg_str}, tzdb.allocator)
		defer delete(region_path)

		tzif_region, ok := load_tzif_file(region_path, reg_str)
		if !ok {
			return
		}

		tzdb.regions["local"] = tzif_region
		region = tzif_region
	}

	return region, true
}

datetime_to_utc :: proc(tz_ctx: ^TZ_Context, _dt: _DateTime) -> (out: _DateTime, success: bool) #optional_ok {
	if _dt.tz == "UTC" {
		return _dt, true
	}

	region := tzdb_get_region(tz_ctx, _dt.tz) or_return

	dt := datetime.DateTime{_dt.date, _dt.time}
	tm, _ := time.datetime_to_time(dt)
	record := region_get_nearest(region, tm)

	secs := time.time_to_unix(tm)
	adj_time := time.unix(secs - record.utc_offset, 0)
	adj_dt, _ := time.time_to_datetime(adj_time)
	return _DateTime{adj_dt.date, adj_dt.time, "UTC"}, true
}

datetime_to_local :: proc(tz_ctx: ^TZ_Context, _dt: _DateTime) -> (out: _DateTime, success: bool) #optional_ok {
	region := tzdb_get_region(tz_ctx, "local") or_return

	dt := datetime.DateTime{_dt.date, _dt.time}
	tm, _ := time.datetime_to_time(dt)
	record := region_get_nearest(region, tm)

	secs := time.time_to_unix(tm)
	adj_time := time.unix(secs + record.utc_offset, 0)
	adj_dt, _ := time.time_to_datetime(adj_time)
	return _DateTime{adj_dt.date, adj_dt.time, region.name}, true
}

datetime_to_str :: proc(tz_ctx: ^TZ_Context, _dt: _DateTime) -> string {
	if _dt.tz == "UTC" {
		dt := datetime.DateTime{_dt.date, _dt.time}
		tm, _ := time.datetime_to_time(dt)
		return fmt.tprintf("%02d-%02d-%04d @ %02d:%02d:%02d UTC", dt.month, dt.day, dt.year, dt.hour, dt.minute, dt.second)

	} else {
		region, _ := tzdb_get_region(tz_ctx, _dt.tz)
		dt := datetime.DateTime{_dt.date, _dt.time}
		tm, _ := time.datetime_to_time(dt)
		record := region_get_nearest(region, tm)

		am_pm_str := "AM"
		if dt.hour > 12 {
			am_pm_str = "PM"
			dt.hour -= 12
		}

		return fmt.tprintf("%02d-%02d-%04d @ %02d:%02d:%02d %s %s", dt.month, dt.day, dt.year, dt.hour, dt.minute, dt.second, am_pm_str, record.shortname)
	}
}
