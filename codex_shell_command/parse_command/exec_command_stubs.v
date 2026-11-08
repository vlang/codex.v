module parse_command

// STUB: codex_shell_command::parse_command::extract_shell_command's borrowed
// (&str, &str) tuple; pointers retain the input argument owners without clones.
pub struct ExtractedShellCommand {
pub:
	shell  &string
	script &string
}

// STUB: codex_shell_command::parse_command::extract_shell_command. This implements
// the bash/zsh/sh and PowerShell wrapper boundary only; script AST parsing and the
// rest of the shell-command crate remain untranslated.
pub fn extract_shell_command(command &[]string) ?ExtractedShellCommand {
	if command.len < 3 {
		return none
	}
	shell := &(*command)[0]
	name := shell_name(shell)
	if command.len == 3 && (*command)[1] in ['-lc', '-c'] && name in ['bash', 'zsh', 'sh'] {
		return ExtractedShellCommand{shell, &(*command)[2]}
	}
	if name !in ['powershell', 'pwsh'] {
		return none
	}
	mut index := 1
	for index + 1 < command.len {
		flag := (*command)[index].to_lower()
		if flag !in ['-nologo', '-noprofile', '-command', '-c'] {
			return none
		}
		if flag in ['-command', '-c'] {
			return ExtractedShellCommand{shell, &(*command)[index + 1]}
		}
		index++
	}
	return none
}

// STUB: codex_shell_command::shell_detect::detect_shell_type's name recognition.
// Rust recursively strips Path::file_stem, so bash.ext.ext is recognized too.
fn shell_name(path &string) string {
	mut end := path.len
	mut start := 0
	for end > 0 {
		for end > 0 && shell_path_separator((*path)[end - 1]) {
			end--
		}
		start = end
		for start > 0 && !shell_path_separator((*path)[start - 1]) {
			start--
		}
		if (*path)[start..end] == '.' {
			end = start
			continue
		}
		break
	}
	mut name := (*path)[start..end].clone()
	for name !in ['zsh', 'bash', 'sh', 'pwsh', 'powershell', 'cmd'] {
		mut dot := -1
		for index in 1 .. name.len {
			if name[index] == `.` {
				dot = index
			}
		}
		if dot < 0 {
			return ''
		}
		name = name[..dot].clone()
	}
	return name
}

// STUB: std::path::Path's native separator rule used by shell detection.
fn shell_path_separator(character u8) bool {
	$if windows {
		return character in [`/`, `\\`]
	} $else {
		return character == `/`
	}
}
