module tui

import codex_terminal_detection
import codex_tui.custom_terminal
import codex_tui.insert_history
import codex_tui.test_backend
import crossterm
import crossterm.cursor
import crossterm.style
import ratatui.layout
import ratatui.text

fn test_windows_terminal_uses_full_screen_unless_zellij_is_active() {
	mut terminal := codex_terminal_detection.TerminalInfo{
		name:         .windows_terminal
		term_program: none
		version:      none
		term:         none
		multiplexer:  none
	}
	mut strategy := ScrollbackStrategy.detect(&terminal)
	assert [strategy.history_insertion_mode(.pre_wrap), strategy.history_insertion_mode(.terminal)] == [
		insert_history.InsertHistoryMode.full_screen,
		.full_screen,
	]
	// The canonical V metadata fields are immutable; replace the owner to add the multiplexer.
	terminal = codex_terminal_detection.TerminalInfo{
		name:         .windows_terminal
		term_program: none
		version:      none
		term:         none
		multiplexer:  codex_terminal_detection.Multiplexer{ kind: .zellij, version: none }
	}
	strategy = ScrollbackStrategy.detect(&terminal)
	assert strategy == .zellij
}

fn test_zellij_only_uses_full_screen_insertion_for_terminal_wrapped_history() {
	assert [ScrollbackStrategy.zellij.history_insertion_mode(.pre_wrap),
		ScrollbackStrategy.zellij.history_insertion_mode(.terminal)] == [
		insert_history.InsertHistoryMode.standard,
		.full_screen,
	]
}

fn test_full_screen_history_insertion_preserves_terminal_scrollback() {
	width := u16(24)
	height := u16(6)
	backend := test_backend.VT100Backend.with_scrollback(width, height, /*scrollback_len*/
		32)
	mut terminal := custom_terminal.Terminal.with_options(backend) or { panic('terminal with scrollback: ${err}') }
	terminal.set_viewport_area(layout.Rect.new( /*x*/
	0, /*y*/
		height - 2, width, /*height*/
		2))
	for row, line in ['oldest-history-row', 'history-row-2', 'history-row-3', 'history-row-4',
		'stale-composer-1', 'stale-composer-2'] {
		mut writer := terminal.backend_mut()
		crossterm.queue_move_to(mut writer, cursor.MoveTo{ /*x*/
			x: 0
			y: u16(row)
		}) or { panic('seed terminal row: ${err}') }
		command := style.Print{ text: &line }
		crossterm.queue_print(mut writer, &command) or { panic('seed terminal row: ${err}') }
	}
	insert_history.insert_history_lines_with_mode_and_wrap_policy(mut terminal, [text.line_from('new-history-row')], ScrollbackStrategy.full_screen.history_insertion_mode(.pre_wrap), .pre_wrap) or { panic('insert history through the full screen: ${err}') }
	visible := terminal.backend().vt100().screen().contents()
	mut scrollback_screen := terminal.backend().vt100().screen().clone()
	scrollback_screen.set_scrollback( /*rows*/
	~usize(0))
	scrollback := scrollback_screen.contents()
	assert 'SCROLLBACK:\n${scrollback}\nVISIBLE:\n${visible}' == 'SCROLLBACK:\noldest-history-row\nhistory-row-2\nhistory-row-3\nhistory-row-4\nnew-history-row\nVISIBLE:\nhistory-row-2\nhistory-row-3\nhistory-row-4\nnew-history-row'
}

fn test_full_screen_viewport_growth_preserves_terminal_scrollback() {
	width := u16(24)
	height := u16(6)
	backend := test_backend.VT100Backend.with_scrollback(width, height, /*scrollback_len*/
		32)
	mut terminal := custom_terminal.Terminal.with_options(backend) or { panic('terminal with scrollback: ${err}') }
	terminal.set_viewport_area(layout.Rect.new( /*x*/
	0, /*y*/
		height - 2, width, /*height*/
		2))
	for row, line in ['oldest-history-row', 'history-row-2', 'history-row-3', 'history-row-4',
		'stale-composer-1', 'stale-composer-2'] {
		mut writer := terminal.backend_mut()
		crossterm.queue_move_to(mut writer, cursor.MoveTo{ /*x*/
			x: 0
			y: u16(row)
		}) or { panic('seed terminal row: ${err}') }
		command := style.Print{ text: &line }
		crossterm.queue_print(mut writer, &command) or { panic('seed terminal row: ${err}') }
	}
	ScrollbackStrategy.full_screen.grow_viewport(mut terminal, /*viewport_top*/
		height - 2, layout.Size.new(width, height), /*scroll_by*/
		2) or { panic('grow viewport through full-screen scrolling: ${err}') }
	visible := terminal.backend().vt100().screen().contents()
	mut scrollback_screen := terminal.backend().vt100().screen().clone()
	scrollback_screen.set_scrollback( /*rows*/
	~usize(0))
	scrollback := scrollback_screen.contents()
	assert 'SCROLLBACK:\n${scrollback}\nVISIBLE:\n${visible}' == 'SCROLLBACK:\noldest-history-row\nhistory-row-2\nhistory-row-3\nhistory-row-4\nVISIBLE:\nhistory-row-3\nhistory-row-4'
}

fn test_scrollback_detection_handles_absent_empty_and_present_windows_terminal_sessions() {
	terminal := codex_terminal_detection.TerminalInfo{ name: .unknown }
	assert ScrollbackStrategy.detect_with_windows_terminal_session(&terminal, fn () ?string {
		return none
	}) == .standard
	assert ScrollbackStrategy.detect_with_windows_terminal_session(&terminal, fn () ?string {
		return ''
	}) == .full_screen
	assert ScrollbackStrategy.detect_with_windows_terminal_session(&terminal, fn () ?string {
		return 'windows-session'
	}) == .full_screen
	windows_terminal := codex_terminal_detection.TerminalInfo{ name: .windows_terminal }
	assert ScrollbackStrategy.detect_with_windows_terminal_session(&windows_terminal, fn () ?string {
		panic('Windows terminal detection must short circuit the environment read')
	}) == .full_screen
	zellij_terminal := codex_terminal_detection.TerminalInfo{ name: .windows_terminal, multiplexer: codex_terminal_detection.Multiplexer{ kind: .zellij } }
	assert ScrollbackStrategy.detect_with_windows_terminal_session(&zellij_terminal, fn () ?string {
		panic('Zellij detection must short circuit the environment read')
	}) == .zellij
}

fn test_scrollback_detection_reuses_heap_owned_terminal_metadata() {
	program := $if ownership ? { 'WindowsTerminal'.to_owned() } $else { 'WindowsTerminal'.clone() }
	version := $if ownership ? { '1.0'.to_owned() } $else { '1.0'.clone() }
	mux_version := $if ownership ? { '0.43'.to_owned() } $else { '0.43'.clone() }
	terminal := &codex_terminal_detection.TerminalInfo{ name: .windows_terminal, term_program: program, version: version, multiplexer: codex_terminal_detection.Multiplexer{ kind: .zellij, version: mux_version } }
	for _ in 0 .. 2 {
		assert ScrollbackStrategy.detect(terminal) == .zellij
		assert terminal.is_zellij()
	}
	assert (terminal.term_program or { panic('missing program') }) == 'WindowsTerminal'
	assert (terminal.version or { panic('missing version') }) == '1.0'
	multiplexer := terminal.multiplexer or { panic('missing multiplexer') }
	assert (multiplexer.version or { panic('missing multiplexer version') }) == '0.43'
}

fn test_full_screen_viewport_growth_saturates_zero_screen_height() {
	mut terminal := custom_terminal.Terminal.with_options(test_backend.VT100Backend.new(24, 6)) or { panic(err) }
	terminal.set_viewport_area(layout.Rect.new(0, 4, 24, 2))
	ScrollbackStrategy.full_screen.grow_viewport(mut terminal, 4, layout.Size.new(24, 0), 0) or { panic(err) }
	assert terminal.backend().vt100().screen().cursor_position() == layout.Position{ x: 0, y: 0 }
	assert terminal.viewport_area == layout.Rect.new(0, 4, 24, 2)
}

fn test_standard_and_zellij_viewport_growth_scroll_only_the_history_region() {
	for strategy in [ScrollbackStrategy.standard, .zellij] {
		mut terminal := custom_terminal.Terminal.with_options(test_backend.VT100Backend.with_scrollback(24, 6, 32)) or { panic(err) }
		terminal.set_viewport_area(layout.Rect.new(0, 4, 24, 2))
		for row, line in ['history-1', 'history-2', 'history-3', 'history-4', 'composer-1', 'composer-2'] {
			mut writer := terminal.backend_mut()
			crossterm.queue_move_to(mut writer, cursor.MoveTo{ x: 0, y: u16(row) }) or { panic(err) }
			command := style.Print{ text: &line }
			crossterm.queue_print(mut writer, &command) or { panic(err) }
		}
		strategy.grow_viewport(mut terminal, 4, layout.Size.new(24, 6), 2) or { panic(err) }
		assert terminal.backend().vt100().screen().contents() == 'history-3\nhistory-4\n\n\ncomposer-1\ncomposer-2'
		assert terminal.viewport_area == layout.Rect.new(0, 4, 24, 2)
	}
}

fn test_viewport_growth_propagates_each_backend_write_failure() {
	for successful_writes in 0 .. 5 {
		mut terminal := custom_terminal.Terminal.with_options(test_backend.VT100Backend.new(24, 6)) or { panic(err) }
		terminal.set_viewport_area(layout.Rect.new(0, 4, 24, 2))
		mut writer := terminal.backend_mut()
		writer.fixture_fail_write_after(successful_writes)
		if _ := ScrollbackStrategy.full_screen.grow_viewport(mut terminal, 4, layout.Size.new(24, 6), 2) {
			assert false, 'full-screen write failure must propagate'
		} else {
			assert err.msg() == 'terminal write failed'
		}
		assert terminal.viewport_area == layout.Rect.new(0, 4, 24, 2)
	}
	for strategy in [ScrollbackStrategy.standard, .zellij] {
		mut terminal := custom_terminal.Terminal.with_options(test_backend.VT100Backend.new(24, 6)) or { panic(err) }
		mut writer := terminal.backend_mut()
		writer.fixture_fail_write_after(0)
		if _ := strategy.grow_viewport(mut terminal, 4, layout.Size.new(24, 6), 2) {
			assert false, 'scroll-region write failure must propagate'
		} else {
			assert err.msg() == 'terminal write failed'
		}
	}
}
