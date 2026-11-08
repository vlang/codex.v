module codex_terminal_detection

import sync

// Named static owners adapt the source's borrowed test string literals.
const fixture_string_0 = 'TERM_PROGRAM'
const fixture_string_1 = 'iTerm.app'
const fixture_string_2 = 'TERM_PROGRAM_VERSION'
const fixture_string_3 = '3.5.0'
const fixture_string_4 = 'WEZTERM_VERSION'
const fixture_string_5 = '2024.2'
const fixture_string_6 = ''
const fixture_string_7 = 'ITERM_SESSION_ID'
const fixture_string_8 = 'w0t1p0'
const fixture_string_9 = 'Apple_Terminal'
const fixture_string_10 = 'TERM_SESSION_ID'
const fixture_string_11 = 'A1B2C3'
const fixture_string_12 = 'Ghostty'
const fixture_string_13 = 'TERM'
const fixture_string_14 = 'xterm-ghostty'
const fixture_string_15 = 'vscode'
const fixture_string_16 = '1.86.0'
const fixture_string_17 = 'WarpTerminal'
const fixture_string_18 = 'v0.2025.12.10.08.12.stable_03'
const fixture_string_19 = 'TMUX'
const fixture_string_20 = '/tmp/tmux-1000/default,123,0'
const fixture_string_21 = 'tmux'
const fixture_string_22 = '3.5a'
const fixture_string_23 = 'ZELLIJ'
const fixture_string_24 = '1'
const fixture_string_25 = 'ZELLIJ_VERSION'
const fixture_string_26 = '0.43.1'
const fixture_string_27 = 'WezTerm'
const fixture_string_28 = 'wezterm'
const fixture_string_29 = 'wezterm-mux'
const fixture_string_30 = 'KITTY_WINDOW_ID'
const fixture_string_31 = 'kitty'
const fixture_string_32 = '0.30.1'
const fixture_string_33 = 'xterm-kitty'
const fixture_string_34 = 'ALACRITTY_SOCKET'
const fixture_string_35 = '/tmp/alacritty'
const fixture_string_36 = 'Alacritty'
const fixture_string_37 = '0.13.2'
const fixture_string_38 = 'alacritty'
const fixture_string_39 = 'KONSOLE_VERSION'
const fixture_string_40 = '230800'
const fixture_string_41 = 'Konsole'
const fixture_string_42 = 'GNOME_TERMINAL_SCREEN'
const fixture_string_43 = 'gnome-terminal'
const fixture_string_44 = '3.50'
const fixture_string_45 = 'VTE_VERSION'
const fixture_string_46 = '7000'
const fixture_string_47 = 'VTE'
const fixture_string_48 = 'WT_SESSION'
const fixture_string_49 = 'WindowsTerminal'
const fixture_string_50 = '1.21'
const fixture_string_51 = 'xterm-256color'
const fixture_string_52 = 'dumb'
const fixture_string_53 = 'screen-256color'

// The source's HashMap-backed injectable environment owns its keys and values.
struct FakeEnvironment {
	vars map[string]string
}

fn FakeEnvironment.new() FakeEnvironment {
	return FakeEnvironment{ vars: map[string]string{} }
}

fn (env FakeEnvironment) with_var(key &string, value &string) FakeEnvironment {
	mut vars := env.vars
	vars[key.clone()] = value.clone()
	return FakeEnvironment{ vars: vars }
}

fn (env &FakeEnvironment) var(name &string) ?string {
	if *name in env.vars {
		return env.vars[*name].clone()
	}
	return none
}

// Source Option<&str> test inputs become owned optional V fixture strings; cloning here is
// the same ToString::to_string boundary as the Rust helper. No process environment is mutated.
fn fixture_terminal_info(name TerminalName, term_program ?string, version ?string, term ?string, multiplexer ?Multiplexer) TerminalInfo {
	return TerminalInfo{
		name:         name
		term_program: if value := term_program { ?string(value.clone()) } else { none }
		version:      if value := version { ?string(value.clone()) } else { none }
		term:         if value := term { ?string(value.clone()) } else { none }
		multiplexer:  multiplexer
	}
}

fn test_detects_term_program() {
	{
		fake := FakeEnvironment.new()
			.with_var(&fixture_string_0, &fixture_string_1)
			.with_var(&fixture_string_2, &fixture_string_3)
			.with_var(&fixture_string_4, &fixture_string_5)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.iterm2, 'iTerm.app', '3.5.0', /*term*/
			none, /*multiplexer*/
			none), 'term_program_with_version_info'
		assert terminal.user_agent_token() == 'iTerm.app/3.5.0', 'term_program_with_version_user_agent'
	}
	{
		fake := FakeEnvironment.new()
			.with_var(&fixture_string_0, &fixture_string_1)
			.with_var(&fixture_string_2, &fixture_string_6)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.iterm2, 'iTerm.app', /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'term_program_without_version_info'
		assert terminal.user_agent_token() == 'iTerm.app', 'term_program_without_version_user_agent'
	}
	{
		fake := FakeEnvironment.new()
			.with_var(&fixture_string_0, &fixture_string_1)
			.with_var(&fixture_string_4, &fixture_string_5)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.iterm2, 'iTerm.app', /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'term_program_overrides_wezterm_info'
		assert terminal.user_agent_token() == 'iTerm.app', 'term_program_overrides_wezterm_user_agent'
	}
}

fn test_terminal_info_reports_is_zellij() {
	zellij := fixture_terminal_info(TerminalName.unknown, /*term_program*/
		none, /*version*/
		none, /*term*/
		none, Multiplexer{ kind: .zellij, version: none })
	assert zellij.is_zellij()
	non_zellij := fixture_terminal_info(TerminalName.unknown, /*term_program*/
		none, /*version*/
		none, /*term*/
		none, Multiplexer{ kind: .tmux, version: none })
	assert !non_zellij.is_zellij()
}

fn test_detects_iterm2() {
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_7, &fixture_string_8)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.iterm2, /*term_program*/
			none, /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'iterm_session_id_info'
		assert terminal.user_agent_token() == 'iTerm.app', 'iterm_session_id_user_agent'
	}
}

fn test_detects_apple_terminal() {
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_0, &fixture_string_9)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.apple_terminal, 'Apple_Terminal', /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'apple_term_program_info'
		assert terminal.user_agent_token() == 'Apple_Terminal', 'apple_term_program_user_agent'
	}
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_10, &fixture_string_11)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.apple_terminal, /*term_program*/
			none, /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'apple_term_session_id_info'
		assert terminal.user_agent_token() == 'Apple_Terminal', 'apple_term_session_id_user_agent'
	}
}

fn test_detects_ghostty() {
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_0, &fixture_string_12)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.ghostty, 'Ghostty', /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'ghostty_term_program_info'
		assert terminal.user_agent_token() == 'Ghostty', 'ghostty_term_program_user_agent'
	}
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_13, &fixture_string_14)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.ghostty, /*term_program*/
			none, /*version*/
			none, 'xterm-ghostty', /*multiplexer*/
			none), 'ghostty_term_info'
		assert terminal.user_agent_token() == 'xterm-ghostty', 'ghostty_term_user_agent'
	}
}

fn test_detects_vscode() {
	{
		fake := FakeEnvironment.new()
			.with_var(&fixture_string_0, &fixture_string_15)
			.with_var(&fixture_string_2, &fixture_string_16)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.vs_code, 'vscode', '1.86.0', /*term*/
			none, /*multiplexer*/
			none), 'vscode_term_program_info'
		assert terminal.user_agent_token() == 'vscode/1.86.0', 'vscode_term_program_user_agent'
	}
}

fn test_detects_warp_terminal() {
	{
		fake := FakeEnvironment.new()
			.with_var(&fixture_string_0, &fixture_string_17)
			.with_var(&fixture_string_2, &fixture_string_18)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.warp_terminal, 'WarpTerminal', 'v0.2025.12.10.08.12.stable_03', /*term*/
			none, /*multiplexer*/
			none), 'warp_term_program_info'
		assert terminal.user_agent_token() == 'WarpTerminal/v0.2025.12.10.08.12.stable_03', 'warp_term_program_user_agent'
	}
}

fn test_detects_tmux_multiplexer() {
	{
		fake := FakeEnvironment.new()
			.with_var(&fixture_string_19, &fixture_string_20)
			.with_var(&fixture_string_0, &fixture_string_21)
			.with_var(&fixture_string_2, &fixture_string_22)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.unknown, /*term_program*/
			none, /*version*/
			none, /*term*/
			none, Multiplexer{ kind: .tmux, version: '3.5a'.clone() }), 'tmux_multiplexer_info'
		assert terminal.user_agent_token() == 'unknown', 'tmux_multiplexer_user_agent'
	}
}

fn test_detects_zellij_multiplexer() {
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_23, &fixture_string_24)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == TerminalInfo{ name: TerminalName.unknown, term_program: none, version: none, term: none, multiplexer: Multiplexer{ kind: .zellij, version: none } }, 'zellij_multiplexer'
	}
}

fn test_detects_zellij_multiplexer_version() {
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_25, &fixture_string_26)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.unknown, /*term_program*/
			none, /*version*/
			none, /*term*/
			none, Multiplexer{ kind: .zellij, version: '0.43.1'.clone() }), 'zellij_multiplexer_version'
	}
}

fn test_detects_wezterm() {
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_4, &fixture_string_5)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.wez_term, /*term_program*/
			none, '2024.2', /*term*/
			none, /*multiplexer*/
			none), 'wezterm_version_info'
		assert terminal.user_agent_token() == 'WezTerm/2024.2', 'wezterm_version_user_agent'
	}
	{
		fake := FakeEnvironment.new()
			.with_var(&fixture_string_0, &fixture_string_27)
			.with_var(&fixture_string_2, &fixture_string_5)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.wez_term, 'WezTerm', '2024.2', /*term*/
			none, /*multiplexer*/
			none), 'wezterm_term_program_info'
		assert terminal.user_agent_token() == 'WezTerm/2024.2', 'wezterm_term_program_user_agent'
	}
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_4, &fixture_string_6)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.wez_term, /*term_program*/
			none, /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'wezterm_empty_info'
		assert terminal.user_agent_token() == 'WezTerm', 'wezterm_empty_user_agent'
	}
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_13, &fixture_string_28)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.wez_term, /*term_program*/
			none, /*version*/
			none, 'wezterm', /*multiplexer*/
			none), 'wezterm_term_info'
		assert terminal.user_agent_token() == 'wezterm', 'wezterm_term_user_agent'
	}
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_13, &fixture_string_29)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.wez_term, /*term_program*/
			none, /*version*/
			none, 'wezterm-mux', /*multiplexer*/
			none), 'wezterm_mux_term_info'
		assert terminal.user_agent_token() == 'wezterm-mux', 'wezterm_mux_term_user_agent'
	}
}

fn test_detects_kitty() {
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_30, &fixture_string_24)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.kitty, /*term_program*/
			none, /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'kitty_window_id_info'
		assert terminal.user_agent_token() == 'kitty', 'kitty_window_id_user_agent'
	}
	{
		fake := FakeEnvironment.new()
			.with_var(&fixture_string_0, &fixture_string_31)
			.with_var(&fixture_string_2, &fixture_string_32)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.kitty, 'kitty', '0.30.1', /*term*/
			none, /*multiplexer*/
			none), 'kitty_term_program_info'
		assert terminal.user_agent_token() == 'kitty/0.30.1', 'kitty_term_program_user_agent'
	}
	{
		fake := FakeEnvironment.new()
			.with_var(&fixture_string_13, &fixture_string_33)
			.with_var(&fixture_string_34, &fixture_string_35)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.kitty, /*term_program*/
			none, /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'kitty_term_over_alacritty_info'
		assert terminal.user_agent_token() == 'kitty', 'kitty_term_over_alacritty_user_agent'
	}
}

fn test_detects_alacritty() {
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_34, &fixture_string_35)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.alacritty, /*term_program*/
			none, /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'alacritty_socket_info'
		assert terminal.user_agent_token() == 'Alacritty', 'alacritty_socket_user_agent'
	}
	{
		fake := FakeEnvironment.new()
			.with_var(&fixture_string_0, &fixture_string_36)
			.with_var(&fixture_string_2, &fixture_string_37)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.alacritty, 'Alacritty', '0.13.2', /*term*/
			none, /*multiplexer*/
			none), 'alacritty_term_program_info'
		assert terminal.user_agent_token() == 'Alacritty/0.13.2', 'alacritty_term_program_user_agent'
	}
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_13, &fixture_string_38)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.alacritty, /*term_program*/
			none, /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'alacritty_term_info'
		assert terminal.user_agent_token() == 'Alacritty', 'alacritty_term_user_agent'
	}
}

fn test_detects_konsole() {
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_39, &fixture_string_40)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.konsole, /*term_program*/
			none, '230800', /*term*/
			none, /*multiplexer*/
			none), 'konsole_version_info'
		assert terminal.user_agent_token() == 'Konsole/230800', 'konsole_version_user_agent'
	}
	{
		fake := FakeEnvironment.new()
			.with_var(&fixture_string_0, &fixture_string_41)
			.with_var(&fixture_string_2, &fixture_string_40)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.konsole, 'Konsole', '230800', /*term*/
			none, /*multiplexer*/
			none), 'konsole_term_program_info'
		assert terminal.user_agent_token() == 'Konsole/230800', 'konsole_term_program_user_agent'
	}
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_39, &fixture_string_6)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.konsole, /*term_program*/
			none, /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'konsole_empty_info'
		assert terminal.user_agent_token() == 'Konsole', 'konsole_empty_user_agent'
	}
}

fn test_detects_gnome_terminal() {
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_42, &fixture_string_24)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.gnome_terminal, /*term_program*/
			none, /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'gnome_terminal_screen_info'
		assert terminal.user_agent_token() == 'gnome-terminal', 'gnome_terminal_screen_user_agent'
	}
	{
		fake := FakeEnvironment.new()
			.with_var(&fixture_string_0, &fixture_string_43)
			.with_var(&fixture_string_2, &fixture_string_44)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.gnome_terminal, 'gnome-terminal', '3.50', /*term*/
			none, /*multiplexer*/
			none), 'gnome_terminal_term_program_info'
		assert terminal.user_agent_token() == 'gnome-terminal/3.50', 'gnome_terminal_term_program_user_agent'
	}
}

fn test_detects_vte() {
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_45, &fixture_string_46)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.vte, /*term_program*/
			none, '7000', /*term*/
			none, /*multiplexer*/
			none), 'vte_version_info'
		assert terminal.user_agent_token() == 'VTE/7000', 'vte_version_user_agent'
	}
	{
		fake := FakeEnvironment.new()
			.with_var(&fixture_string_0, &fixture_string_47)
			.with_var(&fixture_string_2, &fixture_string_46)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.vte, 'VTE', '7000', /*term*/
			none, /*multiplexer*/
			none), 'vte_term_program_info'
		assert terminal.user_agent_token() == 'VTE/7000', 'vte_term_program_user_agent'
	}
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_45, &fixture_string_6)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.vte, /*term_program*/
			none, /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'vte_empty_info'
		assert terminal.user_agent_token() == 'VTE', 'vte_empty_user_agent'
	}
}

fn test_detects_windows_terminal() {
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_48, &fixture_string_24)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.windows_terminal, /*term_program*/
			none, /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'wt_session_info'
		assert terminal.user_agent_token() == 'WindowsTerminal', 'wt_session_user_agent'
	}
	{
		fake := FakeEnvironment.new()
			.with_var(&fixture_string_0, &fixture_string_49)
			.with_var(&fixture_string_2, &fixture_string_50)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.windows_terminal, 'WindowsTerminal', '1.21', /*term*/
			none, /*multiplexer*/
			none), 'windows_terminal_term_program_info'
		assert terminal.user_agent_token() == 'WindowsTerminal/1.21', 'windows_terminal_term_program_user_agent'
	}
}

fn test_detects_term_fallbacks() {
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_13, &fixture_string_51)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.unknown, /*term_program*/
			none, /*version*/
			none, 'xterm-256color', /*multiplexer*/
			none), 'term_fallback_info'
		assert terminal.user_agent_token() == 'xterm-256color', 'term_fallback_user_agent'
	}
	{
		fake := FakeEnvironment.new().with_var(&fixture_string_13, &fixture_string_52)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.dumb, /*term_program*/
			none, /*version*/
			none, 'dumb', /*multiplexer*/
			none), 'dumb_term_info'
		assert terminal.user_agent_token() == 'dumb', 'dumb_term_user_agent'
	}
	{
		fake := FakeEnvironment.new()
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal == fixture_terminal_info(TerminalName.unknown, /*term_program*/
			none, /*version*/
			none, /*term*/
			none, /*multiplexer*/
			none), 'unknown_info'
		assert terminal.user_agent_token() == 'unknown', 'unknown_user_agent'
	}
}

// Named counterpart of the source's (variable, value, name, version) tuples.
struct UnderlyingTerminalCase {
	variable string
	value    string
	name     TerminalName
	version  ?string
}

fn test_tmux_preserves_safe_underlying_terminal_identifiers() {
	cases := [
		UnderlyingTerminalCase{'WEZTERM_VERSION', '2024.2', .wez_term, '2024.2'},
		UnderlyingTerminalCase{'ITERM_SESSION_ID', 'w0t1p0', .iterm2, none},
		UnderlyingTerminalCase{'KITTY_WINDOW_ID', '1', .kitty, none},
		UnderlyingTerminalCase{'WT_SESSION', 'session', .windows_terminal, none},
		UnderlyingTerminalCase{'ALACRITTY_SOCKET', '/tmp/alacritty', .alacritty, none},
		UnderlyingTerminalCase{'GHOSTTY_RESOURCES_DIR', '/Applications/Ghostty.app/Contents/Resources/ghostty', .ghostty, none},
	]
	for index in 0 .. cases.len {
		entry := &cases[index]
		fake := FakeEnvironment.new()
			.with_var(&fixture_string_19, &fixture_string_20)
			.with_var(&fixture_string_0, &fixture_string_21)
			.with_var(&fixture_string_2, &fixture_string_22)
			.with_var(&fixture_string_13, &fixture_string_53)
			.with_var(&entry.variable, &entry.value)
		env := Environment(&fake)
		version := if value := entry.version { ?string(value.clone()) } else { none }
		assert detect_terminal_info_from_env(&env) == fixture_terminal_info(entry.name,
			/*term_program*/
			none, version, /*term*/
			none,
			Multiplexer{ kind: .tmux, version: '3.5a'.clone() }), entry.variable
	}
}

fn test_normalization_sanitization_and_unicode_whitespace() {
	program := '\u3000i.T-e_r.m app\u00a0'
	assert terminal_name_from_term_program(&program) == ?TerminalName(TerminalName.iterm2)
	assert sanitize_header_value(program.clone()) == '_i.T-e_r.m_app_'
	non_ascii_upper := 'İTerm'
	assert terminal_name_from_term_program(&non_ascii_upper) == none
	internal_tab := 'i\tTerm'
	assert terminal_name_from_term_program(&internal_tab) == none
	unknown := 'future😀\r\nterminal'
	assert sanitize_header_value(unknown.clone()) == 'future___terminal'

	whitespace := '\u0085\u00a0\u1680\u2000\u2028\u2029\u202f\u205f\u3000\t\n'
	assert none_if_whitespace(whitespace.clone()) == none
	padded := '\u00a0 value \u3000'
	assert none_if_whitespace(padded.clone()) == ?string(padded)
	zero_width := '\u200b'
	assert none_if_whitespace(zero_width.clone()) == ?string(zero_width)
}

fn test_env_presence_empty_values_and_mux_precedence() {
	{
		wezterm_key := 'WEZTERM_VERSION'
		windows_key := 'WT_SESSION'
		empty := ''
		fake := FakeEnvironment.new().with_var(&wezterm_key, &empty).with_var(&windows_key, &empty)
		env := Environment(&fake)
		assert detect_terminal_info_from_env(&env) == TerminalInfo{ name: .wez_term }
	}
	{
		ghostty_key := 'GHOSTTY_RESOURCES_DIR'
		windows_key := 'WT_SESSION'
		whitespace := '\u00a0\t'
		empty := ''
		fake := FakeEnvironment.new().with_var(&ghostty_key, &whitespace).with_var(&windows_key, &empty)
		env := Environment(&fake)
		assert detect_terminal_info_from_env(&env) == TerminalInfo{ name: .windows_terminal }
	}
	{
		tmux_key := 'TMUX_PANE'
		zellij_key := 'ZELLIJ_VERSION'
		tmux_pane := '%0'
		zellij_version := '0.43.1'
		fake := FakeEnvironment.new().with_var(&tmux_key, &tmux_pane).with_var(&zellij_key, &zellij_version)
		env := Environment(&fake)
		assert detect_terminal_info_from_env(&env) == TerminalInfo{
			name:        .unknown
			multiplexer: Multiplexer{ kind: .tmux, version: none }
		}
	}
	{
		program_key := 'TERM_PROGRAM'
		version_key := 'TERM_PROGRAM_VERSION'
		windows_key := 'WT_SESSION'
		program := 'FutureTerminal'
		version := ' 1😀 '
		empty := ''
		fake := FakeEnvironment.new().with_var(&program_key, &program).with_var(&version_key, &version).with_var(&windows_key, &empty)
		env := Environment(&fake)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal.name == .unknown
		assert terminal.user_agent_token() == 'FutureTerminal/_1__'
	}
}

struct NameTokenCase {
	name  TerminalName
	token string
}

fn test_from_name_user_agent_uses_version_only_for_supported_categories() {
	cases := [
		NameTokenCase{.apple_terminal, 'Apple_Terminal/1.2'},
		NameTokenCase{.ghostty, 'Ghostty/1.2'},
		NameTokenCase{.iterm2, 'iTerm.app/1.2'},
		NameTokenCase{.warp_terminal, 'WarpTerminal/1.2'},
		NameTokenCase{.vs_code, 'vscode/1.2'},
		NameTokenCase{.wez_term, 'WezTerm/1.2'},
		NameTokenCase{.kitty, 'kitty'},
		NameTokenCase{.alacritty, 'Alacritty'},
		NameTokenCase{.konsole, 'Konsole/1.2'},
		NameTokenCase{.gnome_terminal, 'gnome-terminal'},
		NameTokenCase{.vte, 'VTE/1.2'},
		NameTokenCase{.windows_terminal, 'WindowsTerminal'},
		NameTokenCase{.dumb, 'dumb'},
		NameTokenCase{.unknown, 'unknown'},
	]
	for index in 0 .. cases.len {
		entry := &cases[index]
		terminal := TerminalInfo.from_name(entry.name, '1.2', none)
		assert terminal.user_agent_token() == entry.token
	}
	terminal := TerminalInfo{
		name:    .ghostty
		version: '1.2'
		term:    ''
	}
	assert terminal.user_agent_token() == 'Ghostty/1.2'
	empty_program := TerminalInfo{
		name:         .ghostty
		term_program: ''
		version:      '1.2'
		term:         'dumb'
	}
	assert empty_program.user_agent_token() == '/1.2'
}

@[heap]
struct EnvironmentReads {
mut:
	mutex &sync.Mutex = sync.new_mutex()
	names []string
}

struct RecordingEnvironment {
	vars  map[string]string
	reads &EnvironmentReads
}

fn (env &RecordingEnvironment) var(name &string) ?string {
	mut reads := unsafe { env.reads }
	reads.mutex.lock()
	reads.names << name.clone()
	reads.mutex.unlock()
	if *name in env.vars {
		return env.vars[*name].clone()
	}
	return none
}

fn test_probe_order_and_short_circuit_reads() {
	{
		reads := &EnvironmentReads{}
		recorded := RecordingEnvironment{
			vars:  {
				'KITTY_WINDOW_ID': ''
			}
			reads: reads
		}
		env := Environment(&recorded)
		assert detect_terminal_info_from_env(&env).name == .kitty
		assert reads.names == ['TMUX', 'TMUX_PANE', 'ZELLIJ', 'ZELLIJ_SESSION_NAME', 'ZELLIJ_VERSION',
			'TERM_PROGRAM', 'GHOSTTY_RESOURCES_DIR', 'WEZTERM_VERSION', 'ITERM_SESSION_ID',
			'ITERM_PROFILE', 'ITERM_PROFILE_NAME', 'TERM_SESSION_ID', 'KITTY_WINDOW_ID']
	}
	{
		reads := &EnvironmentReads{}
		recorded := RecordingEnvironment{ vars: map[string]string{}, reads: reads }
		env := Environment(&recorded)
		assert detect_terminal_info_from_env(&env).name == .unknown
		assert reads.names == ['TMUX', 'TMUX_PANE', 'ZELLIJ', 'ZELLIJ_SESSION_NAME', 'ZELLIJ_VERSION',
			'TERM_PROGRAM', 'GHOSTTY_RESOURCES_DIR', 'WEZTERM_VERSION', 'ITERM_SESSION_ID',
			'ITERM_PROFILE', 'ITERM_PROFILE_NAME', 'TERM_SESSION_ID', 'KITTY_WINDOW_ID', 'TERM',
			'ALACRITTY_SOCKET', 'TERM', 'KONSOLE_VERSION', 'GNOME_TERMINAL_SCREEN', 'VTE_VERSION',
			'WT_SESSION', 'TERM']
	}
	{
		reads := &EnvironmentReads{}
		recorded := RecordingEnvironment{
			vars:  {
				'TMUX':                 'mux'
				'TERM_PROGRAM':         'TmUx'
				'TERM_PROGRAM_VERSION': '3.5'
			}
			reads: reads
		}
		env := Environment(&recorded)
		terminal := detect_terminal_info_from_env(&env)
		assert terminal.multiplexer == ?Multiplexer(Multiplexer{ kind: .tmux, version: '3.5' })
		assert reads.names[..4] == ['TMUX', 'TERM_PROGRAM', 'TERM_PROGRAM_VERSION', 'TERM_PROGRAM']
	}
}

fn cache_thread_read(cache &TerminalInfoCache, env &Environment) TerminalInfo {
	mut shared_cache := unsafe { cache }
	return shared_cache.get_or_init(env)
}

fn test_lazy_cache_initializes_once_and_clones_for_concurrent_callers() {
	reads := &EnvironmentReads{}
	recorded := RecordingEnvironment{
		vars:  {
			'TERM_PROGRAM':         'Ghostty'
			'TERM_PROGRAM_VERSION': '1.2'
		}
		reads: reads
	}
	env := Environment(&recorded)
	cache := &TerminalInfoCache{}
	mut workers := []thread TerminalInfo{cap: 12}
	for _ in 0 .. 12 {
		workers << spawn cache_thread_read(cache, &env)
	}
	results := workers.wait()
	assert results.len == 12
	for index in 0 .. results.len {
		terminal := &results[index]
		assert terminal == &TerminalInfo{
			name:         .ghostty
			term_program: 'Ghostty'
			version:      '1.2'
		}
	}
	assert reads.names == ['TMUX', 'TMUX_PANE', 'ZELLIJ', 'ZELLIJ_SESSION_NAME', 'ZELLIJ_VERSION',
		'TERM_PROGRAM', 'TERM_PROGRAM_VERSION']
	first_program := results[0].term_program or { panic('missing program') }
	second_program := results[1].term_program or { panic('missing program') }
	assert first_program == second_program
	assert first_program.str != second_program.str

	other_fake := FakeEnvironment.new()
	other_env := Environment(&other_fake)
	mut reusable_cache := unsafe { cache }
	assert reusable_cache.get_or_init(&other_env).name == .ghostty
}

fn test_borrowed_helpers_and_environment_owners_remain_reusable() {
	mut key := 'TERM_PROGRAM'
	mut program := 'Ghostty'
	mut version := '1.2'
	$if ownership ? {
		key = 'TERM_PROGRAM'.to_owned()
		program = 'Ghostty'.to_owned()
		version = '1.2'.to_owned()
	}
	version_key := 'TERM_PROGRAM_VERSION'
	fake := FakeEnvironment.new().with_var(&key, &program).with_var(&version_key, &version)
	env := Environment(&fake)
	first := detect_terminal_info_from_env(&env)
	second := detect_terminal_info_from_env(&env)
	assert first == second
	assert first.user_agent_token() == 'Ghostty/1.2'
	assert first.user_agent_token() == 'Ghostty/1.2'
	assert !first.is_zellij()
	assert !first.is_zellij()
	assert terminal_name_from_term_program(&program) == ?TerminalName(TerminalName.ghostty)
	assert terminal_name_from_term_program(&program) == ?TerminalName(TerminalName.ghostty)
	assert !is_tmux_term_program(&program)
	assert fake.var(&key) == ?string('Ghostty')
	assert fake.var(&key) == ?string('Ghostty')
	assert key == 'TERM_PROGRAM'
	assert program == 'Ghostty'
	assert version == '1.2'
	assert fake.vars['TERM_PROGRAM'] == 'Ghostty'
	assert first.term_program == ?string('Ghostty')
	assert format_terminal_version(&program, &first) == 'Ghostty/1.2'
	assert format_terminal_version(&program, &first) == 'Ghostty/1.2'
	assert first.version == ?string('1.2')
}

fn test_native_environment_unicode_validation() {
	ascii := 'TERM'
	unicode := '😀é'
	invalid := [u8(0xed), 0xa0, 0x80].bytestr()
	assert valid_environment_utf8(&ascii)
	assert valid_environment_utf8(&unicode)
	assert !valid_environment_utf8(&invalid)
	valid_units := [u16(0x41), 0xd83d, 0xde00, 0]
	assert valid_environment_utf16(&valid_units[0])
	lone_high := [u16(0xd800), 0]
	assert !valid_environment_utf16(&lone_high[0])
	lone_low := [u16(0xdc00), 0]
	assert !valid_environment_utf16(&lone_low[0])
	wrong_pair := [u16(0xd800), 0x41, 0]
	assert !valid_environment_utf16(&wrong_pair[0])
}

fn test_process_cache_user_agent_and_owned_clones_remain_reusable() {
	first := terminal_info()
	second := terminal_info()
	assert first == second
	assert user_agent() == first.user_agent_token()
	assert user_agent() == second.user_agent_token()
	assert first == second
}
