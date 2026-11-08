module codex_utils_path

$if windows {
	#flag windows -lshell32
	#flag windows -lole32
	#flag windows -luuid
	#include <windows.h>
	#include <shlobj.h>
	#include <knownfolders.h>
	#include "@VMODROOT/codex_utils_path/keyboard_modes_native.h"
} $else {
	#include <stdlib.h>
}

// STUB: source system_commands.rs resolves ProgramFiles, ProgramFilesX86, and
// System directories via SHGetKnownFolderPath(KF_FLAG_DEFAULT_PATH), never env vars.
fn keyboard_windows_installation_roots() []string {
	mut roots := []string{}
	$if windows {
		for index in 0 .. 3 {
			mut path := &u16(unsafe { nil })
			if C.codex_keyboard_known_folder(i32(index), &path) != 0 || path == unsafe { nil } {
				continue
			}
			// The API owns the NUL-terminated UTF-16 allocation until CoTaskMemFree.
			directory := unsafe { string_from_wide(path) }
			C.CoTaskMemFree(path)
			canonical := keyboard_canonicalize(&directory) or { continue }
			roots << canonical
		}
	}
	return roots
}

// STUB: narrow Windows KnownFolderPath FFI, keeping GUIDs out of V's type surface.
fn C.codex_keyboard_known_folder(index i32, path &&u16) i32

// STUB: Windows frees SHGetKnownFolderPath's COM allocation after copying.
fn C.CoTaskMemFree(path voidptr)

// STUB: dunce::canonicalize's fallible native boundary; os.real_path falls back
// to the input on errors, so it cannot safely implement trusted helper discovery.
fn keyboard_canonicalize(path &string) ?string {
	$if windows {
		wide_path := path.to_wide()
		defer { unsafe { free(wide_path) } }
		canonical := C.codex_keyboard_canonical_windows(wide_path)
		if canonical == unsafe { nil } {
			return none
		}
		defer { unsafe { free(canonical) } }
		result := unsafe { string_from_wide(canonical) }
		if result.starts_with('\\\\?\\UNC\\') {
			return '\\\\${result[8..]}'
		}
		if result.starts_with('\\\\?\\') && result.len >= 6 && result[5] == `:` {
			return result[4..].clone()
		}
		return result
	} $else {
		canonical := C.realpath(path.str, unsafe { nil })
		if canonical == unsafe { nil } {
			return none
		}
		defer { unsafe { free(canonical) } }
		return unsafe { cstring_to_vstring(canonical) }
	}
}

// STUB: Windows GetFinalPathNameByHandleW canonicalization uses an allocated
// UTF-16 buffer and reports failure rather than returning an unresolved input.
fn C.codex_keyboard_canonical_windows(path &u16) &u16
