// Terminal detection utilities.
//
// This module feeds terminal metadata into OpenTelemetry user-agent logging and into
// terminal-specific configuration choices in the TUI. Detection only reads the
// environment; it must not execute helpers selected by an untrusted PATH.
module codex_terminal_detection

import strings
import sync
import tracing

// Named static string owners adapt Rust borrowed string literals to V references.
const terminal_literal_apple_terminal = 'Apple_Terminal'
const terminal_literal_ghostty = 'Ghostty'
const terminal_literal_iterm_app = 'iTerm.app'
const terminal_literal_warpterminal = 'WarpTerminal'
const terminal_literal_vscode = 'vscode'
const terminal_literal_wezterm = 'WezTerm'
const terminal_literal_konsole = 'Konsole'
const terminal_literal_vte = 'VTE'
const terminal_literal_term_program = 'TERM_PROGRAM'
const terminal_literal_term_program_version = 'TERM_PROGRAM_VERSION'
const terminal_literal_ghostty_resources_dir = 'GHOSTTY_RESOURCES_DIR'
const terminal_literal_wezterm_version = 'WEZTERM_VERSION'
const terminal_literal_iterm_session_id = 'ITERM_SESSION_ID'
const terminal_literal_iterm_profile = 'ITERM_PROFILE'
const terminal_literal_iterm_profile_name = 'ITERM_PROFILE_NAME'
const terminal_literal_term_session_id = 'TERM_SESSION_ID'
const terminal_literal_term = 'TERM'
const terminal_literal_kitty_window_id = 'KITTY_WINDOW_ID'
const terminal_literal_alacritty_socket = 'ALACRITTY_SOCKET'
const terminal_literal_konsole_version = 'KONSOLE_VERSION'
const terminal_literal_gnome_terminal_screen = 'GNOME_TERMINAL_SCREEN'
const terminal_literal_vte_version = 'VTE_VERSION'
const terminal_literal_wt_session = 'WT_SESSION'
const terminal_literal_tmux = 'TMUX'
const terminal_literal_tmux_pane = 'TMUX_PANE'
const terminal_literal_zellij = 'ZELLIJ'
const terminal_literal_zellij_session_name = 'ZELLIJ_SESSION_NAME'
const terminal_literal_zellij_version = 'ZELLIJ_VERSION'

// Structured terminal identification data.
pub struct TerminalInfo {
pub:
	// The detected terminal name category.
	name TerminalName
	// The `TERM_PROGRAM` value when provided by the terminal.
	term_program ?string
	// The terminal version string when available.
	version ?string
	// The `TERM` value when falling back to capability strings.
	term ?string
	// Multiplexer metadata when a terminal multiplexer is active.
	multiplexer ?Multiplexer
}

// Known terminal name categories derived from environment variables.
pub enum TerminalName {
	// Apple Terminal (Terminal.app).
	apple_terminal
	// Ghostty terminal emulator.
	ghostty
	// iTerm2 terminal emulator.
	iterm2
	// Warp terminal emulator.
	warp_terminal
	// Visual Studio Code integrated terminal.
	vs_code
	// WezTerm terminal emulator.
	wez_term
	// kitty terminal emulator.
	kitty
	// Alacritty terminal emulator.
	alacritty
	// KDE Konsole terminal emulator.
	konsole
	// GNOME Terminal emulator.
	gnome_terminal
	// VTE backend terminal.
	vte
	// Windows Terminal emulator.
	windows_terminal
	// Dumb terminal (TERM=dumb).
	dumb
	// Unknown or missing terminal identification.
	unknown
}

// V's explicit tag carries the two Rust enum variants, which share the same payload shape.
pub enum MultiplexerKind {
	// tmux terminal multiplexer.
	tmux
	// zellij terminal multiplexer.
	zellij
}

// Detected terminal multiplexer metadata.
pub struct Multiplexer {
pub:
	// The tag selects either tmux or Zellij.
	kind MultiplexerKind
	// tmux version string when `TERM_PROGRAM=tmux` is available.
	//
	// This is derived from `TERM_PROGRAM_VERSION`.
	// Zellij version string when ZELLIJ_VERSION is available.
	version ?string
}

// Rust derives Clone; optional resource fields need explicit owned copies in V.
pub fn (terminal &TerminalInfo) clone() TerminalInfo {
	return TerminalInfo{
		name:         terminal.name
		term_program: if program := terminal.term_program { ?string(program.clone()) } else { none }
		version:      if version := terminal.version { ?string(version.clone()) } else { none }
		term:         if term := terminal.term { ?string(term.clone()) } else { none }
		multiplexer:  if mux := terminal.multiplexer { ?Multiplexer(mux.clone()) } else { none }
	}
}

// Rust derives Clone; the active tag is Copy while its optional version is owned.
pub fn (mux &Multiplexer) clone() Multiplexer {
	return Multiplexer{
		kind:    mux.kind
		version: if version := mux.version { ?string(version.clone()) } else { none }
	}
}

// Creates terminal metadata from detected fields.
fn TerminalInfo.new(name TerminalName, term_program ?string, version ?string, term ?string, multiplexer ?Multiplexer) TerminalInfo {
	return TerminalInfo{ name: name, term_program: term_program, version: version, term: term, multiplexer: multiplexer }
}

// Creates terminal metadata from a `TERM_PROGRAM` match.
fn TerminalInfo.from_term_program(name TerminalName, term_program string, version ?string, multiplexer ?Multiplexer) TerminalInfo {
	return TerminalInfo.new(name, term_program, version, /*term*/
		none, multiplexer)
}

// Creates terminal metadata from a known terminal name and optional version.
fn TerminalInfo.from_name(name TerminalName, version ?string, multiplexer ?Multiplexer) TerminalInfo {
	return TerminalInfo.new(name, /*term_program*/
		none, version, /*term*/
		none, multiplexer)
}

// Creates terminal metadata from a `TERM` capability value.
fn TerminalInfo.from_term(term string, multiplexer ?Multiplexer) TerminalInfo {
	name := match term {
		'dumb' { TerminalName.dumb }
		'xterm-ghostty' { TerminalName.ghostty }
		'wezterm', 'wezterm-mux' { TerminalName.wez_term }
		else { TerminalName.unknown }
	}
	return TerminalInfo.new(name, /*term_program*/
		none, /*version*/
		none, term, multiplexer)
}

// Creates terminal metadata for unknown terminals.
fn TerminalInfo.unknown(multiplexer ?Multiplexer) TerminalInfo {
	return TerminalInfo.new(.unknown, /*term_program*/
		none, /*version*/
		none, /*term*/
		none, multiplexer)
}

// Formats the terminal info as a User-Agent token.
fn (terminal &TerminalInfo) user_agent_token() string {
	mut raw := ''
	if program := terminal.term_program {
		if version := terminal.version {
			raw = if version.len > 0 { '${program}/${version}' } else { program.clone() }
		} else {
			raw = program.clone()
		}
	} else if term := terminal.term {
		if term.len > 0 {
			raw = term.clone()
		} else {
			raw = terminal.token_from_name()
		}
	} else {
		raw = terminal.token_from_name()
	}
	return sanitize_header_value(raw)
}

// This helper holds the original name match, shared by the absent and empty TERM cases.
fn (terminal &TerminalInfo) token_from_name() string {
	return match terminal.name {
		.apple_terminal { format_terminal_version(&terminal_literal_apple_terminal, terminal) }
		.ghostty { format_terminal_version(&terminal_literal_ghostty, terminal) }
		.iterm2 { format_terminal_version(&terminal_literal_iterm_app, terminal) }
		.warp_terminal { format_terminal_version(&terminal_literal_warpterminal, terminal) }
		.vs_code { format_terminal_version(&terminal_literal_vscode, terminal) }
		.wez_term { format_terminal_version(&terminal_literal_wezterm, terminal) }
		.kitty { 'kitty' }
		.alacritty { 'Alacritty' }
		.konsole { format_terminal_version(&terminal_literal_konsole, terminal) }
		.gnome_terminal { 'gnome-terminal' }
		.vte { format_terminal_version(&terminal_literal_vte, terminal) }
		.windows_terminal { 'WindowsTerminal' }
		.dumb { 'dumb' }
		.unknown { 'unknown' }
	}
}

// Returns whether the active terminal multiplexer is Zellij.
pub fn (terminal &TerminalInfo) is_zellij() bool {
	if mux := terminal.multiplexer {
		return mux.kind == .zellij
	}
	return false
}

// Rust OnceLock stores one detection result and clones it for every caller. This V heap cache
// is created eagerly, but only its mutex is initialized; environment reads remain lazy. Holding
// the mutex across initialization and cloning publishes one complete value to concurrent callers.
@[heap]
struct TerminalInfoCache {
mut:
	mutex       &sync.Mutex = sync.new_mutex()
	initialized bool
	value       TerminalInfo
}

const terminal_info_cache = &TerminalInfoCache{}

// A separate initialized flag keeps the cached owner in place: destructuring an optional field
// through a mutable V receiver consumes that field under -ownership. OnceLock never consumes it.
fn (mut cache TerminalInfoCache) get_or_init(env &Environment) TerminalInfo {
	cache.mutex.lock()
	defer { cache.mutex.unlock() }
	if !cache.initialized {
		cache.value = detect_terminal_info_from_env(env)
		cache.initialized = true
	}
	return cache.value.clone()
}

// Environment variable access used by terminal detection.
//
// This trait exists to allow faking the environment in tests.
interface Environment {
	// Returns an environment variable when set.
	var(name &string) ?string
}

// Returns whether an environment variable is set.
fn (env &Environment) has(name &string) bool {
	if _ := env.var(name) {
		return true
	}
	return false
}

// Returns a non-empty environment variable.
fn (env &Environment) var_non_empty(name &string) ?string {
	value := env.var(name) or { return none }
	return none_if_whitespace(value)
}

// Returns whether an environment variable is set and non-empty.
fn (env &Environment) has_non_empty(name &string) bool {
	if _ := env.var_non_empty(name) {
		return true
	}
	return false
}

// Reads environment variables from the running process.
struct ProcessEnvironment {}

fn (env &ProcessEnvironment) var(name &string) ?string {
	value := process_environment_var(name) or { return none }
	if !valid_environment_utf8(&value) {
		message := 'failed to read env var ${*name}: value not valid UTF-8'
		tracing.warn(&message)
		return none
	}
	return value
}

// Returns a sanitized terminal identifier for User-Agent strings.
pub fn user_agent() string {
	terminal := terminal_info()
	return terminal.user_agent_token()
}

// Returns structured terminal metadata for the current process.
pub fn terminal_info() TerminalInfo {
	process_env := ProcessEnvironment{}
	env := Environment(&process_env)
	mut cache := unsafe { terminal_info_cache }
	return cache.get_or_init(&env)
}

// Detects structured terminal metadata from an injectable environment.
//
// Detection order favors explicit identifiers before falling back to capability strings:
// - `TERM_PROGRAM` (plus `TERM_PROGRAM_VERSION`) drives the detected terminal name,
//   except when it identifies tmux rather than the underlying terminal.
//   This means `TERM_PROGRAM` can mask later probes (for example `WT_SESSION`).
// - Next, terminal-specific variables (WEZTERM, iTerm2, Apple Terminal, kitty, etc.) are checked.
// - Finally, `TERM` is used as the capability fallback.
fn detect_terminal_info_from_env(env &Environment) TerminalInfo {
	multiplexer := detect_multiplexer(env)
	if term_program := env.var_non_empty(&terminal_literal_term_program) {
		if !is_tmux_term_program(&term_program) {
			version := env.var_non_empty(&terminal_literal_term_program_version)
			name := terminal_name_from_term_program(&term_program) or { TerminalName.unknown }
			return TerminalInfo.from_term_program(name, term_program, version, multiplexer)
		}
	}
	if env.has_non_empty(&terminal_literal_ghostty_resources_dir) {
		return TerminalInfo.from_name(.ghostty, /*version*/
			none, multiplexer)
	}
	if env.has(&terminal_literal_wezterm_version) {
		version := env.var_non_empty(&terminal_literal_wezterm_version)
		return TerminalInfo.from_name(.wez_term, version, multiplexer)
	}
	if env.has(&terminal_literal_iterm_session_id) || env.has(&terminal_literal_iterm_profile) || env.has(&terminal_literal_iterm_profile_name) {
		return TerminalInfo.from_name(.iterm2, /*version*/
			none, multiplexer)
	}
	if env.has(&terminal_literal_term_session_id) {
		return TerminalInfo.from_name(.apple_terminal, /*version*/
			none, multiplexer)
	}
	mut is_kitty := env.has(&terminal_literal_kitty_window_id)
	if !is_kitty {
		term_for_kitty := env.var(&terminal_literal_term) or { '' }
		is_kitty = term_for_kitty.contains('kitty')
	}
	if is_kitty {
		return TerminalInfo.from_name(.kitty, /*version*/
			none, multiplexer)
	}
	mut is_alacritty := env.has(&terminal_literal_alacritty_socket)
	if !is_alacritty {
		term_for_alacritty := env.var(&terminal_literal_term) or { '' }
		is_alacritty = term_for_alacritty == 'alacritty'
	}
	if is_alacritty {
		return TerminalInfo.from_name(.alacritty, /*version*/
			none, multiplexer)
	}
	if env.has(&terminal_literal_konsole_version) {
		version := env.var_non_empty(&terminal_literal_konsole_version)
		return TerminalInfo.from_name(.konsole, version, multiplexer)
	}
	if env.has(&terminal_literal_gnome_terminal_screen) {
		return TerminalInfo.from_name(.gnome_terminal, /*version*/
			none, multiplexer)
	}
	if env.has(&terminal_literal_vte_version) {
		version := env.var_non_empty(&terminal_literal_vte_version)
		return TerminalInfo.from_name(.vte, version, multiplexer)
	}
	if env.has(&terminal_literal_wt_session) {
		return TerminalInfo.from_name(.windows_terminal, /*version*/
			none, multiplexer)
	}
	if term := env.var_non_empty(&terminal_literal_term) {
		return TerminalInfo.from_term(term, multiplexer)
	}
	return TerminalInfo.unknown(multiplexer)
}

fn detect_multiplexer(env &Environment) ?Multiplexer {
	if env.has_non_empty(&terminal_literal_tmux) || env.has_non_empty(&terminal_literal_tmux_pane) {
		return Multiplexer{ kind: .tmux, version: tmux_version_from_env(env) }
	}
	if env.has_non_empty(&terminal_literal_zellij) || env.has_non_empty(&terminal_literal_zellij_session_name) || env.has_non_empty(&terminal_literal_zellij_version) {
		return Multiplexer{ kind: .zellij, version: env.var_non_empty(&terminal_literal_zellij_version) }
	}
	return none
}

fn is_tmux_term_program(value &string) bool {
	return value.len == 4 && ((*value)[0] == `t` || (*value)[0] == `T`) && ((*value)[1] == `m` || (*value)[1] == `M`) && ((*value)[2] == `u` || (*value)[2] == `U`) && ((*value)[3] == `x` || (*value)[3] == `X`)
}

fn tmux_version_from_env(env &Environment) ?string {
	term_program := env.var(&terminal_literal_term_program) or { return none }
	if !is_tmux_term_program(&term_program) {
		return none
	}
	return env.var_non_empty(&terminal_literal_term_program_version)
}

// Sanitizes a terminal token for use in User-Agent headers.
//
// Invalid header characters are replaced with underscores.
fn sanitize_header_value(value string) string {
	mut result := strings.new_builder(value.len)
	for ch in value.runes_iterator() {
		if is_valid_header_value_char(ch) { result.write_rune(ch) } else { result.write_u8(`_`) }
	}
	return result.str()
}

// Returns whether a character is allowed in User-Agent header values.
fn is_valid_header_value_char(ch rune) bool {
	return (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`) || ch == `-` || ch == `_` || ch == `.` || ch == `/`
}

// Rust str::trim follows Unicode White_Space, including non-ASCII characters.
const terminal_unicode_whitespace = '\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000'

fn terminal_name_from_term_program(value &string) ?TerminalName {
	trimmed := value.trim(terminal_unicode_whitespace)
	mut normalized := strings.new_builder(trimmed.len)
	for ch in trimmed.runes_iterator() {
		if ch in [` `, `-`, `_`, `.`] {
			continue
		}
		normalized.write_rune(if ch >= `A` && ch <= `Z` { ch + 32 } else { ch })
	}
	name := normalized.str()
	return match name {
		'appleterminal' { ?TerminalName(TerminalName.apple_terminal) }
		'ghostty' { ?TerminalName(TerminalName.ghostty) }
		'iterm', 'iterm2', 'itermapp' { ?TerminalName(TerminalName.iterm2) }
		'warp', 'warpterminal' { ?TerminalName(TerminalName.warp_terminal) }
		'vscode' { ?TerminalName(TerminalName.vs_code) }
		'wezterm' { ?TerminalName(TerminalName.wez_term) }
		'kitty' { ?TerminalName(TerminalName.kitty) }
		'alacritty' { ?TerminalName(TerminalName.alacritty) }
		'konsole' { ?TerminalName(TerminalName.konsole) }
		'gnometerminal' { ?TerminalName(TerminalName.gnome_terminal) }
		'vte' { ?TerminalName(TerminalName.vte) }
		'windowsterminal' { ?TerminalName(TerminalName.windows_terminal) }
		'dumb' { ?TerminalName(TerminalName.dumb) }
		else { none }
	}
}

// V cannot safely borrow &?string. Borrowing its containing TerminalInfo preserves the Rust
// &Option<String> lifetime and lets this helper inspect the same optional version without a copy.
fn format_terminal_version(name &string, version &TerminalInfo) string {
	if text := version.version {
		if text.len > 0 {
			return '${*name}/${text}'
		}
	}
	return name.clone()
}

fn none_if_whitespace(value string) ?string {
	if value.trim(terminal_unicode_whitespace).len == 0 {
		return none
	}
	return value
}
