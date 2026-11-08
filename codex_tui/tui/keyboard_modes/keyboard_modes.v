// Terminal keyboard enhancement setup and teardown helpers.
//
// The TUI uses crossterm's keyboard enhancement stack while it owns the terminal, but
// process exit gets a stronger reset so the parent shell does not inherit enhanced key
// reporting if a terminal misses the normal stack pop.
module keyboard_modes

import codex_terminal_detection
import codex_tui.clipboard_paste
import codex_utils_path
import crossterm
import crossterm.event
import encoding.utf8.validate
import os
import std_io
import std_process
import strings
import sync

const disable_keyboard_enhancement_env_var = 'CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT'

// A Copy borrowed wrapper preserves Rust Option<&str> without owning its string.
// V cannot reliably express &?string or ?&string; absent values never dereference value.
struct BorrowedString {
	present bool
	value   &string = unsafe { nil }
}

fn BorrowedString.some(value &string) BorrowedString {
	return BorrowedString{ present: true, value: value }
}

// This container adapts Rust Option<String>::as_deref while keeping the optional
// owner in place across repeated borrowed calls. Only from_option consumes the value.
struct EnvironmentValue {
	present bool
	value   string
}

fn EnvironmentValue.from_option(value ?string) EnvironmentValue {
	if text := value {
		return EnvironmentValue{ present: true, value: text }
	}
	return EnvironmentValue{}
}

fn (value &EnvironmentValue) as_deref() BorrowedString {
	return BorrowedString{ present: value.present, value: &value.value }
}

pub fn keyboard_enhancement_disabled() bool {
	disable_env := EnvironmentValue.from_option(environment_var(&disable_keyboard_enhancement_env_var))
	is_wsl := running_in_wsl()
	is_vscode_terminal := is_wsl && running_in_vscode_terminal()
	return keyboard_enhancement_disabled_for(disable_env.as_deref(), is_wsl, is_vscode_terminal)
}

fn keyboard_enhancement_disabled_for(disable_env BorrowedString, is_wsl bool, is_vscode_terminal bool) bool {
	if disabled := parse_bool_env(disable_env) {
		return disabled
	}

	// VS Code running a WSL shell can hide TERM_PROGRAM from the Linux process
	// environment, so `running_in_vscode_terminal` also probes the Windows-side
	// environment through WSL interop.
	return is_wsl && is_vscode_terminal
}

// Rust str::trim uses the Unicode White_Space set, including non-ASCII scalars.
const unicode_whitespace = '\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000'

fn parse_bool_env(value BorrowedString) ?bool {
	if !value.present {
		return none
	}
	// V trim returns an owned string where Rust temporarily borrows a slice.
	trimmed := value.value.trim(unicode_whitespace)
	if trimmed == '1' || ascii_eq_ignore_case(&trimmed, &literal_true)
		|| ascii_eq_ignore_case(&trimmed, &literal_yes) {
		return true
	}
	if trimmed == '0' || ascii_eq_ignore_case(&trimmed, &literal_false)
		|| ascii_eq_ignore_case(&trimmed, &literal_no) {
		return false
	}
	return none
}

const literal_true = 'true'
const literal_yes = 'yes'
const literal_false = 'false'
const literal_no = 'no'
const literal_vscode = 'vscode'
const literal_term_program = 'TERM_PROGRAM'
const literal_cmd_exe = 'cmd.exe'
const literal_tmux = 'tmux'
const literal_tmux_env = 'TMUX'
const literal_tmux_pane = 'TMUX_PANE'
const literal_path = 'PATH'
const literal_csi_u = 'csi-u'

// Rust eq_ignore_ascii_case folds only ASCII, retaining non-ASCII byte identity.
fn ascii_eq_ignore_case(left &string, right &string) bool {
	if left.len != right.len {
		return false
	}
	for index in 0 .. left.len {
		left_byte := (*left)[index]
		right_byte := (*right)[index]
		folded_left := if left_byte >= `A` && left_byte <= `Z` { left_byte + 32 } else { left_byte }
		folded_right := if right_byte >= `A` && right_byte <= `Z` {
			right_byte + 32
		} else {
			right_byte
		}
		if folded_left != folded_right {
			return false
		}
	}
	return true
}

fn running_in_wsl() bool {
	$if linux {
		return clipboard_paste.is_probably_wsl()
	} $else {
		return false
	}
}

pub fn running_in_vscode_terminal() bool {
	first_term_program := EnvironmentValue.from_option(environment_var(&literal_term_program))
	if term_program_is_vscode(first_term_program.as_deref()) {
		return true
	}
	linux_term_program := EnvironmentValue.from_option(environment_var(&literal_term_program))
	windows_program := EnvironmentValue.from_option(windows_term_program())
	return vscode_terminal_detected(linux_term_program.as_deref(), windows_program.as_deref())
}

fn vscode_terminal_detected(linux_term_program BorrowedString, windows_term_program BorrowedString) bool {
	return term_program_is_vscode(linux_term_program) || term_program_is_vscode(windows_term_program)
}

fn term_program_is_vscode(value BorrowedString) bool {
	return value.present && ascii_eq_ignore_case(value.value, &literal_vscode)
}

// Rust's Linux OnceLock<Option<String>> is a synchronized lazy owner here. Keeping
// a presence tag separate avoids consuming a cached optional resource in V.
@[heap]
struct WindowsTermProgramCache {
mut:
	mutex       &sync.Mutex = sync.new_mutex()
	initialized bool
	present     bool
	value       string
}

const windows_term_program_cache = &WindowsTermProgramCache{}

fn (mut cache WindowsTermProgramCache) get_or_init() ?string {
	cache.mutex.lock()
	defer { cache.mutex.unlock() }
	if !cache.initialized {
		if value := read_windows_term_program() {
			cache.present = true
			cache.value = value
		}
		cache.initialized = true
	}
	if cache.present {
		return cache.value.clone()
	}
	return none
}

fn windows_term_program() ?string {
	$if linux {
		mut cache := unsafe { windows_term_program_cache }
		return cache.get_or_init()
	} $else {
		return none
	}
}

fn read_windows_term_program() ?string {
	if !running_in_wsl() {
		return none
	}
	executable := codex_utils_path.system_executable(&literal_cmd_exe) or { return none }
	mut command := std_process.Command.new_owned(executable)
	command.args(['/d', '/s', '/c', 'set TERM_PROGRAM'])
	command.stdin(.null)
	command.stderr(.null)
	output := command.output() or { return none }
	if !output.status.success() {
		return none
	}
	return windows_term_program_from_stdout(&output.stdout)
}

// The original find_map closure is named to keep its native byte parsing testable.
fn windows_term_program_from_stdout(stdout &string) ?string {
	decoded := from_utf8_lossy(stdout)
	// Rust lines() splits LF/CRLF; a bare CR inside a value stays in that value.
	for line in decoded.split('\n') {
		trimmed := line.trim_right('\r')
		if trimmed.starts_with('TERM_PROGRAM=') {
			value := trimmed['TERM_PROGRAM='.len..].clone()
			if value.trim(unicode_whitespace).len == 0 {
				return none
			}
			return value
		}
	}
	return none
}

pub fn enable_keyboard_enhancement() {
	if keyboard_enhancement_disabled() {
		return
	}
	running_in_tmux := running_in_tmux_session()
	tmux_extended_keys_format := EnvironmentValue.from_option(if running_in_tmux {
		read_tmux_extended_keys_format()
	} else {
		none
	})
	mut output := os.stdout()
	crossterm.execute_commands(mut output, [
		crossterm.Command(DisableModifyOtherKeys{}),
		crossterm.Command(event.PushKeyboardEnhancementFlags{
			flags: keyboard_enhancement_flags(codex_terminal_detection.terminal_info().name, running_in_tmux,
				tmux_extended_keys_format.as_deref())
		}),
	]) or {}
	if tmux_should_enable_modify_other_keys_for(running_in_tmux,
		tmux_extended_keys_format.as_deref()) {
		crossterm.execute_commands(mut output, [crossterm.Command(EnableModifyOtherKeys{})]) or {}
	}
}

fn keyboard_enhancement_flags(terminal_name codex_terminal_detection.TerminalName, running_in_tmux_session bool, tmux_extended_keys_format BorrowedString) event.KeyboardEnhancementFlags {
	flags := event.keyboard_disambiguate_escape_codes | event.keyboard_report_alternate_keys

	// iTerm and Ghostty can leak shortcut release events that the terminal consumes.
	// tmux's xterm key format also loses Shift-Enter when event types are
	// reported. An unavailable/unrecognized tmux probe must take the same safe
	// fallback. Preserve repeat classification on confirmed csi-u transports.
	if terminal_name in [.ghostty, .iterm2]
		|| (running_in_tmux_session && !(tmux_extended_keys_format.present
			&& *tmux_extended_keys_format.value == literal_csi_u)) {
		return flags
	}
	return flags | event.keyboard_report_event_types
}

fn running_in_tmux_session() bool {
	tmux := EnvironmentValue.from_option(environment_var(&literal_tmux_env))
	tmux_pane := EnvironmentValue.from_option(environment_var(&literal_tmux_pane))
	return tmux_session_detected(tmux.as_deref(), tmux_pane.as_deref())
}

fn tmux_session_detected(tmux BorrowedString, tmux_pane BorrowedString) bool {
	return tmux.present || tmux_pane.present
}

fn tmux_should_enable_modify_other_keys_for(running_in_tmux_session bool, extended_keys_format BorrowedString) bool {
	// Only request mode 2 when tmux confirms csi-u formatting. Older tmux
	// versions do not expose this option and may emit xterm-style sequences,
	// which crossterm does not parse consistently for modified keys.
	return running_in_tmux_session && extended_keys_format.present
		&& *extended_keys_format.value == literal_csi_u
}

fn read_tmux_extended_keys_format() ?string {
	executable := codex_utils_path.system_executable(&literal_tmux) or { return none }
	path := codex_utils_path.system_path() or { return none }
	for args in [
		['display-message', '-p', '#{extended-keys-format}'],
		['show-options', '-gqv', 'extended-keys-format'],
	] {
		mut command := std_process.Command.new(&executable)
		command.env(&literal_path, &path)
		command.args(args)
		command.stdin(.null)
		command.stderr(.null)
		output := command.output() or { return none }
		if !output.status.success() {
			continue
		}
		if !validate.utf8_data(output.stdout.str, output.stdout.len) {
			continue
		}
		// V trim allocates the source trim().to_string() owned result directly.
		value := output.stdout.trim(unicode_whitespace)
		if value.len > 0 {
			return value
		}
	}
	return none
}

pub fn restore_keyboard_enhancement_stack() {
	mut output := os.stdout()
	crossterm.execute_commands(mut output, [
		crossterm.Command(event.PopKeyboardEnhancementFlags{}),
		crossterm.Command(DisableModifyOtherKeys{}),
	]) or {}
}

pub fn reset_keyboard_reporting_after_exit() {
	mut output := os.stdout()
	crossterm.execute_commands(mut output, [
		crossterm.Command(event.PopKeyboardEnhancementFlags{}),
		crossterm.Command(ResetKeyboardEnhancementFlags{}),
		crossterm.Command(DisableModifyOtherKeys{}),
	]) or {}
}

struct ResetKeyboardEnhancementFlags {}

fn (command &ResetKeyboardEnhancementFlags) write_ansi(mut output strings.Builder) ! {
	output.write_string('\x1b[<u')
}

// V's Command interface requires the Windows methods on every platform; they
// retain Rust's Unsupported result and support flag whenever Windows invokes them.
fn (command &ResetKeyboardEnhancementFlags) execute_winapi() ! {
	return std_io.Error.new(.unsupported,
		'keyboard enhancement reset is not implemented for the legacy Windows API')
}

fn (command &ResetKeyboardEnhancementFlags) is_ansi_code_supported() bool {
	return false
}

struct EnableModifyOtherKeys {}

fn (command &EnableModifyOtherKeys) write_ansi(mut output strings.Builder) ! {
	output.write_string('\x1b[>4;2m')
}

fn (command &EnableModifyOtherKeys) execute_winapi() ! {
	return std_io.Error.new(.unsupported,
		'modifyOtherKeys enable is not implemented for the legacy Windows API')
}

fn (command &EnableModifyOtherKeys) is_ansi_code_supported() bool {
	return false
}

struct DisableModifyOtherKeys {}

fn (command &DisableModifyOtherKeys) write_ansi(mut output strings.Builder) ! {
	output.write_string('\x1b[>4;0m')
}

fn (command &DisableModifyOtherKeys) execute_winapi() ! {
	return std_io.Error.new(.unsupported,
		'modifyOtherKeys reset is not implemented for the legacy Windows API')
}

fn (command &DisableModifyOtherKeys) is_ansi_code_supported() bool {
	return false
}

// String::from_utf8_lossy groups a valid prefix of an invalid sequence into one
// replacement scalar. Native process bytes remain borrowed; the result is owned.
fn from_utf8_lossy(input &string) string {
	mut result := strings.new_builder(input.len)
	mut index := 0
	for index < input.len {
		first := (*input)[index]
		if first < 0x80 {
			result.write_u8(first)
			index++
			continue
		}
		width := if first >= 0xc2 && first <= 0xdf {
			2
		} else if first >= 0xe0 && first <= 0xef {
			3
		} else if first >= 0xf0 && first <= 0xf4 {
			4
		} else {
			0
		}
		mut valid := 1
		for valid < width && index + valid < input.len {
			next := (*input)[index + valid]
			if next < 0x80 || next > 0xbf || (valid == 1 && ((first == 0xe0 && next < 0xa0)
				|| (first == 0xed && next >= 0xa0) || (first == 0xf0 && next < 0x90)
				|| (first == 0xf4 && next > 0x8f))) {
				break
			}
			valid++
		}
		if width > 0 && valid == width {
			for offset in 0 .. width {
				result.write_u8((*input)[index + offset])
			}
		} else {
			result.write_string('\ufffd')
		}
		index += valid
	}
	return result.str()
}
