#+build darwin

package main

import "core:strings"
import NS "core:sys/darwin/Foundation"

platform_pre_init :: proc(pt: ^Platform_State) {
	pt.velocity_multiplier = -15
}
platform_post_init :: proc(pt: ^Platform_State) {
	user_defaults := NS.UserDefaults.standardUserDefaults()
	flag_str := NS.String.alloc()->initWithOdinString("AppleMomentumScrollSupported")
	user_defaults->setBoolForKey(true, flag_str)
}
platform_dpi_hack :: proc() -> f64 {
	return -1
}

open_file_dialog :: proc() -> (string, bool) {
	panel := NS.OpenPanel.openPanel()
	panel->setCanChooseFiles(true)
	panel->setResolvesAliases(true)
	panel->setCanChooseDirectories(false)
	panel->setAllowsMultipleSelection(false)

	if panel->runModal() == .OK {
		urls := panel->URLs()
		ret_count := urls->count()
		if ret_count != 1 {
			return "", false
		}

		url := urls->objectAs(0, ^NS.URL)
		return strings.clone_from_cstring(url->fileSystemRepresentation()), true
	}

	return "", false
}

get_app_path :: proc(buf: []u8) -> (string, bool) {
	size : u32 = u32(len(buf))
	ret := get_exe_path(raw_data(buf[:]), &size)
	return string(cstring(raw_data(buf[:size]))), ret == 0
}

foreign import libc "system:System.framework"
foreign libc {
	@(link_name="_NSGetExecutablePath") get_exe_path :: proc(buf: rawptr, size: ^u32) -> int ---
}
