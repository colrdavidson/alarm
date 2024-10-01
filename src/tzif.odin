package main

import "base:intrinsics"
import "core:fmt"
import "core:time"
import "core:strings"

// Implementing RFC8536 [https://datatracker.ietf.org/doc/html/rfc8536]

TZIF_MAGIC :: u32be(0x545A6966) // 'TZif'
TZif_Version :: enum u8 {
	V1 =  0,
	V2 = '2',
	V3 = '3',
	V4 = '4',
}
BIG_BANG_ISH :: -0x800000000000000

TZif_Header :: struct #packed {
	magic:           u32be,
	version:  TZif_Version,
	reserved:       [15]u8,
	isutcnt:         u32be,
	isstdcnt:        u32be,
	leapcnt:         u32be,
	timecnt:         u32be,
	typecnt:         u32be,
	charcnt:         u32be,
}

Sun_Shift :: enum u8 {
	Standard = 0,
	DST = 1,
}

Local_Time_Type :: struct #packed {
	utoff:    i32be,
	dst:  Sun_Shift,
	idx:         u8,
}

Leapsecond_Record :: struct #packed {
	occur: i64be,
	corr:  i32be,
}

Timechange_Record :: struct {
	time:         time.Time,
	utc_offset:   i64,

	shortname: string,
	dst:         bool,
}

TZ_Region :: struct {
	name:                 string,
	records: []Timechange_Record,
	shortnames:         []string,
}

slice_to_type :: proc(buf: []u8, $T: typeid) -> (T, bool) #optional_ok {
    if len(buf) < size_of(T) {
        return {}, false
    }

    return intrinsics.unaligned_load((^T)(raw_data(buf))), true
}

tzif_data_block_size :: proc(hdr: ^TZif_Header, version: TZif_Version) -> (block_size: int, ok: bool) {
	time_size : int

	if version == .V1 {
		time_size = 4
	} else if version == .V2 || version == .V3 || version == .V4 {
		time_size = 8
	} else {
		return
	}

	return (int(hdr.timecnt) * time_size)              +
		   int(hdr.timecnt)                            +
		   int(hdr.typecnt * size_of(Local_Time_Type)) +
		   int(hdr.charcnt)                            +
		   (int(hdr.leapcnt) * (time_size + 4))        +
		   int(hdr.isstdcnt)                           +
		   int(hdr.isutcnt), true
}

region_destroy :: proc(region: TZ_Region) {
	for name in region.shortnames {
		delete(name)
	}
	delete(region.records)
	delete(region.name)
}

parse_tzif :: proc(_buffer: []u8, region_name: string, allocator := context.allocator) -> (out: TZ_Region, ok: bool) {
	buffer := _buffer

	// TZif is crufty. Skip the initial header.

	v1_hdr := slice_to_type(buffer, TZif_Header) or_return
	if v1_hdr.magic != TZIF_MAGIC {
		return
	}
	if v1_hdr.typecnt == 0 || v1_hdr.charcnt == 0 {
		return
	}
	if v1_hdr.isutcnt != 0 && v1_hdr.isutcnt != v1_hdr.typecnt {
		return
	}
	if v1_hdr.isstdcnt != 0 && v1_hdr.isstdcnt != v1_hdr.typecnt {
		return
	}

	// We don't bother supporting v1, it uses u32 timestamps
	if v1_hdr.version == .V1 {
		return
	}
	// We only support v2 and v3
	if v1_hdr.version != .V2 && v1_hdr.version != .V3 {
		return
	}

	// Skip the initial v1 block too.
	first_block_size, _ := tzif_data_block_size(&v1_hdr, .V1)
	if len(buffer) <= size_of(v1_hdr) + first_block_size {
		return
	}
	buffer = buffer[size_of(v1_hdr)+first_block_size:]

	// Ok, time to parse real things
	real_hdr := slice_to_type(buffer, TZif_Header) or_return
	if real_hdr.magic != TZIF_MAGIC {
		return
	}
	if real_hdr.typecnt == 0 || real_hdr.charcnt == 0 {
		return
	}
	if real_hdr.isutcnt != 0 && real_hdr.isutcnt != real_hdr.typecnt {
		return
	}
	if real_hdr.isstdcnt != 0 && real_hdr.isstdcnt != real_hdr.typecnt {
		return
	}

	// Grab the real data block
	real_block_size, _ := tzif_data_block_size(&real_hdr, v1_hdr.version)
	if len(buffer) <= size_of(real_hdr) + real_block_size {
		return
	}
	buffer = buffer[size_of(real_hdr):]

	time_size := 8
	transition_times := transmute([]i64be)buffer[:int(real_hdr.timecnt)]
	for time in transition_times {
		if time < BIG_BANG_ISH {
			return
		}
	}
	buffer = buffer[int(real_hdr.timecnt)*time_size:]

	transition_types := transmute([]u8)buffer[:int(real_hdr.timecnt)]
	for type in transition_types {
		if int(type) > int(real_hdr.typecnt - 1) {
			return
		}
	}
	buffer = buffer[int(real_hdr.timecnt):]

	local_time_types := transmute([]Local_Time_Type)buffer[:int(real_hdr.typecnt)]
	for ltt in local_time_types {
		// UT offset should be > -25 hours and < 26 hours
		if int(ltt.utoff) < -89999 || int(ltt.utoff) > 93599 {
			return
		}

		if ltt.dst != .DST && ltt.dst != .Standard {
			return
		}

		if int(ltt.idx) > int(real_hdr.charcnt - 1) {
			fmt.printf("%v\n", ltt.idx)
			return
		}
	}

	buffer = buffer[int(real_hdr.typecnt) * size_of(Local_Time_Type):]
	timezone_string_table := buffer[:real_hdr.charcnt]
	buffer = buffer[real_hdr.charcnt:]

	leapsecond_records := transmute([]Leapsecond_Record)buffer[:int(real_hdr.leapcnt)]
	if len(leapsecond_records) > 0 {
		if leapsecond_records[0].occur < 0 {
			return
		}
	}
	buffer = buffer[(int(real_hdr.leapcnt) * size_of(Leapsecond_Record)):]

	standard_wall_tags := transmute([]u8)buffer[:int(real_hdr.isstdcnt)]
	buffer = buffer[int(real_hdr.isstdcnt):]

	ut_tags := transmute([]u8)buffer[:int(real_hdr.isutcnt)]

	for stdwall_tag, idx in standard_wall_tags {
		ut_tag := ut_tags[idx]

		if (stdwall_tag != 0 && stdwall_tag != 1) {
			return
		}
		if (ut_tag != 0 && ut_tag != 1) {
			return
		}

		if ut_tag == 1 && stdwall_tag != 1 {
			return
		}
	}
	buffer = buffer[int(real_hdr.isutcnt):]

	// Start of footer
	if buffer[0] != '\n' {
		return
	}
	buffer = buffer[1:]

	if buffer[0] == ':' {
		return
	}

	end_idx := 0
	for ch in buffer {
		if ch == '\n' {
			break
		}

		if ch == 0 {
			return
		}
		end_idx += 1
	}

	footer_str := string(buffer[:end_idx])
	fmt.printf("%v\n", footer_str)

	ltt_names := make([dynamic]string)
	for ltt in local_time_types {
		name := cstring(raw_data(timezone_string_table[ltt.idx:]))
		append(&ltt_names, strings.clone_from_cstring_bounded(name, len(timezone_string_table)))
	}

	records := make([dynamic]Timechange_Record)
	for trans_time, idx in transition_times {
		trans_idx := transition_types[idx]
		ltt := local_time_types[trans_idx]
		stdwall_tag := standard_wall_tags[trans_idx]
		ut_tag := ut_tags[trans_idx]

		tm := time.unix(i64(trans_time), 0)
		append(&records, Timechange_Record{
			time       = time.unix(i64(trans_time), 0),
			utc_offset = i64(ltt.utoff),
			shortname  = ltt_names[trans_idx],
			dst        = bool(ltt.dst),
		})
		//fmt.printf("%v | %v %v %v\n", tm, designation, ltt.utoff, ltt.dst)
	}

	return TZ_Region{
		name = strings.clone(region_name),
		records = records[:],
		shortnames = ltt_names[:],
	}, true
}
