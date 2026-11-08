module exec_command

import codex_shell_command.parse_command
import dirs
import shlex
import std_path

pub fn escape_command(command &[]string) string {
	return shlex.try_join(command) or { (*command).join(' ') }
}

pub fn strip_bash_lc_and_escape(command &[]string) string {
	if extracted := parse_command.extract_shell_command(command) {
		return (*extracted.script).clone()
	}
	return escape_command(command)
}

pub fn split_command_string(command &string) []string {
	parts := shlex.split(command) or { return [(*command).clone()] }
	round_trip := shlex.try_join(&parts) or { return [(*command).clone()] }
	if round_trip == *command {
		return parts
	}
	if !(*command).contains(':\\') {
		if round_trip_parts := shlex.split(&round_trip) {
			if round_trip_parts == parts {
				return parts
			}
		}
	}
	return [(*command).clone()]
}

// If `path` is absolute and inside $HOME, return the part *after* the home
// directory; otherwise, return the path as-is. Note if `path` is the homedir,
// this will return an empty path.
// As in the Rust implementation, paths outside home actually return none.
// V represents owned PathBuf as a byte string, and Path as an allocation-free
// borrowed view. Generic strings, borrowed strings, and Path views are accepted;
// other path adapters implement `as_ref() std_path.Path`, preserving Rust's
// AsRef<Path> extension point without borrowing a temporary. Value arguments are
// consumed, while reference arguments retain their owners. Unix non-UTF-8 bytes
// remain intact; Windows uses UTF-8 instead of potentially unpaired UTF-16 units.
pub fn relativize_to_home[T](path T) ?string {
	borrowed_path := path_view(&path)
	if !borrowed_path.is_absolute() {
		// If the path is not absolute, we can’t do anything with it.
		return none
	}
	home := dirs.home_dir() or { return none }
	home_path := std_path.Path.new(&home)
	relative := borrowed_path.strip_prefix(&home_path) or { return none }
	return relative.to_path_buf()
}

fn path_view[T](path &T) std_path.Path {
	$if T is string {
		return std_path.Path.new(path)
	} $else $if T is &string {
		return std_path.Path.new(*path)
	} $else $if T is std_path.Path {
		return *path
	} $else $if T is &std_path.Path {
		return **path
	} $else $if T is $pointer {
		// Explicitly dereference a borrowed adapter: V's generic method call
		// otherwise forwards &T as a double pointer to the adapter's receiver.
		return (*path).as_ref()
	} $else {
		return path.as_ref()
	}
}
