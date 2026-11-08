module keyboard_modes

import encoding.utf8.validate
import os

// std::env::var rejects non-Unicode values. Preserve raw Unix environment bytes
// until UTF-8 validation; validate Windows UTF-16 before V converts to UTF-8.
fn environment_var(name &string) ?string {
	$if windows {
		wide_name := name.to_wide()
		defer { unsafe { free(wide_name) } }
		wide_value := unsafe { &u16(C._wgetenv(wide_name)) }
		if wide_value == unsafe { nil } || !valid_environment_utf16(wide_value) {
			return none
		}
		return unsafe { string_from_wide(wide_value) }
	} $else {
		// V's environment API takes an owned key; this copy adapts that stdlib boundary.
		value := os.getenv_opt(name.clone()) or { return none }
		if !validate.utf8_data(value.str, value.len) {
			return none
		}
		return value
	}
}

fn valid_environment_utf16(value &u16) bool {
	mut index := 0
	unsafe {
		for value[index] != 0 {
			unit := value[index]
			if unit >= 0xd800 && unit <= 0xdbff {
				next := value[index + 1]
				if next < 0xdc00 || next > 0xdfff {
					return false
				}
				index += 2
			} else if unit >= 0xdc00 && unit <= 0xdfff {
				return false
			} else {
				index++
			}
		}
	}
	return true
}
