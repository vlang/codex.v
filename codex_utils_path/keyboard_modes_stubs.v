module codex_utils_path

import os
import std_path

// STUB: codex_utils_path::system_executable uses the owner's trusted installation
// search; ambient PATH and the working directory never select an automatic helper.
pub fn system_executable(name &string) ?std_path.PathBuf {
	if name.len == 0 || *name in ['.', '..'] || name.contains('/') || name.contains('\x00') {
		return none
	}
	$if windows {
		if name.contains('\\') || name.contains(':') {
			return none
		}
	}
	directories := keyboard_system_directories()
	roots := keyboard_installation_roots()
	suffix := $if windows { '.exe' } $else { '' }
	for directory in directories {
		candidate := os.join_path_single(directory, '${*name}${suffix}')
		executable := keyboard_canonicalize(&candidate) or { continue }
		mut installed := false
		for root in directories {
			if keyboard_path_within(&executable, &root) {
				installed = true
				break
			}
		}
		if !installed {
			for root in roots {
				if keyboard_path_within(&executable, &root) {
					installed = true
					break
				}
			}
		}
		// V's os helpers consume their string inputs; copies adapt Rust's borrowed
		// filesystem queries while the canonical path owner remains reusable.
		if !installed || !os.is_file(executable.clone()) {
			continue
		}
		$if !windows {
			// Rust checks any execute permission bit, rather than the current user's access.
			mode := os.stat(executable.clone()) or { continue }
			if mode.mode & 0o111 == 0 {
				continue
			}
		}
		return std_path.PathBuf.from(executable)
	}
	return none
}

// STUB: codex_utils_path::system_path returns the trusted helper child PATH.
// V strings preserve native Unix OsString bytes; Windows paths use UTF-8 storage.
pub fn system_path() !string {
	directories := keyboard_system_directories()
	if directories.len == 0 {
		return error('no trusted executable directories')
	}
	$if windows {
		mut joined := []string{cap: directories.len}
		for directory in directories {
			if directory.contains('"') {
				return error('path segment contains quote')
			}
			joined << if directory.contains(';') { '"${directory}"' } else { directory.clone() }
		}
		return joined.join(';')
	} $else {
		for directory in directories {
			if directory.contains(':') {
				return error('path segment contains separator')
			}
		}
		return directories.join(':')
	}
}

// STUB: system_commands.rs's Path::starts_with compares native path components.
fn keyboard_path_within(path &string, root &string) bool {
	path_view := std_path.Path.new(path)
	root_view := std_path.Path.new(root)
	path_view.strip_prefix(&root_view) or { return false }
	return true
}

// STUB: system_commands.rs's conventional OS/package-manager installation roots.
fn keyboard_installation_roots() []string {
	$if windows {
		return keyboard_windows_installation_roots()
	} $else {
		return ['/usr/bin', '/bin', '/usr/sbin', '/sbin', '/usr/local', '/opt/homebrew', '/opt/local',
			'/Library/Developer/CommandLineTools', '/Applications/Xcode.app/Contents/Developer',
			'/nix/store', '/mnt/c/Windows/System32']
	}
}

// STUB: system_commands.rs canonicalizes and filters the owner's ordered directories.
fn keyboard_system_directories() []string {
	roots := keyboard_installation_roots()
	mut candidates := []string{}
	$if windows {
		for root in roots {
			// Each Rust root.join constructs an owned result from the borrowed root.
			candidates << os.join_path_single(root.clone(), 'Git/cmd')
			candidates << os.join_path_single(root.clone(), 'Git/mingw64/bin')
			candidates << os.join_path_single(root.clone(), 'Git/usr/bin')
			candidates << root
		}
	} $else {
		candidates = ['/opt/homebrew/bin', '/usr/local/bin', '/opt/local/bin',
			'/Library/Developer/CommandLineTools/usr/bin',
			'/Applications/Xcode.app/Contents/Developer/usr/bin', '/usr/bin', '/bin', '/usr/sbin',
			'/sbin']
		$if linux {
			if keyboard_path_utils_is_wsl() {
				candidates << '/mnt/c/Windows/System32'
			}
		}
	}
	mut directories := []string{}
	for candidate in candidates {
		canonical := keyboard_canonicalize(&candidate) or { continue }
		for root in roots {
			if keyboard_path_within(&canonical, &root) {
				directories << canonical
				break
			}
		}
	}
	return directories
}

// STUB: codex_utils_path::is_wsl has its own source probe, distinct from clipboard_paste.
fn keyboard_path_utils_is_wsl() bool {
	$if linux {
		if os.getenv_opt('WSL_DISTRO_NAME') != none {
			return true
		}
		version := os.read_file('/proc/version') or { return false }
		return version.to_lower().contains('microsoft')
	} $else {
		return false
	}
}
