// Copyright (c) 2018-2019 dirs-rs contributors.
// Licensed under Apache-2.0 or MIT; see LICENSE-APACHE and LICENSE-MIT.

module dirs

import os

#include "@VMODROOT/dirs/exec_command_native.h"

$if windows {
	#flag -lshell32
	#flag -lole32
}

// STUB: Native dirs-sys home-directory lookup used by dirs::home_dir.
fn C.codex_exec_command_native_home() &char

// STUB: Free the temporary native buffer allocated by the home-directory lookup.
fn C.codex_exec_command_free_native_home(&char)

// STUB: dirs 6.0.0 home_dir's observed Option<PathBuf> API. The Unix implementation
// follows dirs-sys 0.5.0's nonempty HOME then getpwuid_r fallback, while Windows
// uses FOLDERID_Profile. Other dirs APIs remain untranslated. V owns a byte-string
// PathBuf; Windows UTF-16 paths are represented in UTF-8.
pub fn home_dir() ?string {
	$if !windows {
		home := os.getenv('HOME')
		if home.len > 0 {
			return home
		}
	}
	native := C.codex_exec_command_native_home()
	if native == unsafe { nil } {
		return none
	}
	result := unsafe { cstring_to_vstring(native) }
	C.codex_exec_command_free_native_home(native)
	return result
}
