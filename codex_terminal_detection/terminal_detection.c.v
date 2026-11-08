module codex_terminal_detection

import encoding.utf8.validate
import os
import tracing

fn valid_environment_utf8(value &string) bool {
	return validate.utf8_data(value.str, value.len)
}

// std::env::var rejects non-Unicode values. Unix environment bytes are checked in
// ProcessEnvironment.var; Windows UTF-16 must be checked before V converts it to UTF-8.
fn process_environment_var(name &string) ?string {
	$if windows {
		wide_name := name.to_wide()
		defer { unsafe { free(wide_name) } }
		wide_value := unsafe { &u16(C._wgetenv(wide_name)) }
		if wide_value == unsafe { nil } {
			return none
		}
		if !valid_environment_utf16(wide_value) {
			message := 'failed to read env var ${*name}: value not valid UTF-8'
			tracing.warn(&message)
			return none
		}
		return unsafe { string_from_wide(wide_value) }
	} $else {
		// V's standard-library environment API takes an owned key; this copy adapts that
		// boundary while the translated Environment.var API retains its borrowed input.
		return os.getenv_opt(name.clone())
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
