module tui

import codex_tui.custom_terminal
import codex_tui.insert_history
import codex_tui.terminal_hyperlinks
import codex_tui.test_backend
import codex_tui.tui.frame_requester
import ratatui.layout
import ratatui.text

fn test_replacing_visible_history_tail_preserves_existing_terminal_scrollback() {
	width := u16(52)
	height := u16(8)
	backend := test_backend.VT100Backend.with_scrollback(width, height, /*scrollback_len*/
		32)
	mut terminal := custom_terminal.Terminal.with_options(backend) or { panic('terminal: ${err}') }
	for line in ['shell history that predates Codex', 'shell output one', 'shell output two',
		'shell output three', 'shell output four', 'shell output five', 'shell output six',
		'shell output seven'] {
		mut writer := terminal.backend_mut()
		data := '${line}\r\n'.bytes()
		writer.write(&data) or { panic('seed shell history: ${err}') }
	}
	terminal.set_viewport_area(layout.Rect.new( /*x*/
	0, /*y*/
		height - 2, width, /*height*/
		2))
	insert_history.insert_history_lines(mut terminal, [text.line_from('/status'),
		text.line_from('Account: business'), text.line_from('old closing border')]) or { panic('insert initial status card: ${err}') }
	previous_lines := terminal_hyperlinks.plain_hyperlink_lines([text.line_from('old closing border')])
	replacement := terminal_hyperlinks.plain_hyperlink_lines([
		text.line_from('Thread usage: 50 credits'),
		text.line_from('new closing border'),
	])
	assert replace_visible_terminal_history_tail(mut terminal, &previous_lines, &replacement, .standard, .pre_wrap) or { panic('replace status-card tail: ${err}') }
	contents := terminal.backend().vt100().screen().contents()
	assert contents.contains('/status'), contents
	assert contents.contains('Account: business'), contents
	assert contents.contains('Thread usage: 50 credits'), contents
	assert !contents.contains('old closing border'), contents
	mut screen_with_scrollback := terminal.backend().vt100().screen().clone()
	screen_with_scrollback.set_scrollback( /*rows*/
	~usize(0))
	scrollback := screen_with_scrollback.contents()
	assert scrollback.contains('shell history that predates Codex'), 'existing terminal scrollback was discarded: ${scrollback}'
}

fn test_inaccessible_history_tail_is_preserved_for_non_destructive_append() {
	width := u16(36)
	height := u16(6)
	backend := test_backend.VT100Backend.with_scrollback(width, height, /*scrollback_len*/
		16)
	mut terminal := custom_terminal.Terminal.with_options(backend) or { panic('terminal: ${err}') }
	terminal.set_viewport_area(layout.Rect.new( /*x*/
	0, /*y*/
		1, width, /*height*/
		height - 1))
	before := terminal.backend().vt100().screen().contents()
	previous_lines := terminal_hyperlinks.plain_hyperlink_lines([
		text.line_from('first line'),
		text.line_from('second line'),
	])
	replacement := terminal_hyperlinks.plain_hyperlink_lines([text.line_from('Thread usage: 50 credits')])
	assert !(replace_visible_terminal_history_tail(mut terminal, &previous_lines, &replacement, .standard, .pre_wrap) or { panic('leave inaccessible history untouched: ${err}') })
	assert terminal.backend().vt100().screen().contents() == before
}

fn test_replacing_soft_wrapped_history_counts_physical_terminal_rows() {
	width := u16(12)
	height := u16(8)
	backend := test_backend.VT100Backend.new(width, height)
	mut terminal := custom_terminal.Terminal.with_options(backend) or { panic('terminal: ${err}') }
	terminal.set_viewport_area(layout.Rect.new( /*x*/
	0, /*y*/
		height - 2, width, /*height*/
		2))
	previous_lines := terminal_hyperlinks.plain_hyperlink_lines([text.line_from('old-long-line-spanning-two-rows')])
	screen_size := terminal.last_known_screen_size
	insert_history.insert_history_hyperlink_lines_with_mode_and_wrap_policy(mut terminal, &previous_lines, .standard, .terminal, screen_size) or { panic('insert soft-wrapped history: ${err}') }
	replacement := terminal_hyperlinks.plain_hyperlink_lines([text.line_from('new billing')])
	assert replace_visible_terminal_history_tail(mut terminal, &previous_lines, &replacement, .standard, .terminal) or { panic('replace physically wrapped rows: ${err}') }
	contents := terminal.backend().vt100().screen().contents()
	assert contents.contains('new billing'), contents
	assert !contents.contains('old-long'), contents
	assert !contents.contains('spanning'), contents
}

fn test_history_tail_repeated_borrows_preserve_heap_owned_text_and_terminal() {
	old := $if ownership ? { 'old closing border'.to_owned() } $else { 'old closing border'.clone() }
	new := $if ownership ? { 'new closing border'.to_owned() } $else { 'new closing border'.clone() }
	previous_lines := terminal_hyperlinks.plain_hyperlink_lines([text.line_from(old)])
	replacement := terminal_hyperlinks.plain_hyperlink_lines([text.line_from(new)])
	mut terminal := custom_terminal.Terminal.with_options(test_backend.VT100Backend.new(36, 8)) or { panic(err) }
	terminal.set_viewport_area(layout.Rect.new(0, 6, 36, 2))
	for _ in 0 .. 2 {
		assert replace_visible_terminal_history_tail(mut terminal, &previous_lines, &replacement, .standard, .pre_wrap) or { panic(err) }
	}
	assert previous_lines[0].line.spans[0].text == 'old closing border'
	assert replacement[0].line.spans[0].text == 'new closing border'
	assert terminal.backend().vt100().screen().contents().contains('new closing border')
}

fn test_tui_replacement_flushes_pending_batches_and_schedules_only_after_success() {
	mut terminal := custom_terminal.Terminal.with_options(test_backend.VT100Backend.new(52, 10)) or { panic(err) }
	terminal.set_viewport_area(layout.Rect.new(0, 8, 52, 2))
	mut terminal_ui := Tui{
		terminal:              terminal
		frame_requester:       frame_requester.FrameRequester.test_dummy()
		pending_history_lines: [PendingHistoryLines{
			lines:       terminal_hyperlinks.plain_hyperlink_lines([
				text.line_from('older pending line'),
				text.line_from('old closing border'),
			])
			wrap_policy: .pre_wrap
		}]
	}
	defer { terminal_ui.frame_requester.close() }
	previous_lines := terminal_hyperlinks.plain_hyperlink_lines([text.line_from('old closing border')])
	replacement := terminal_hyperlinks.plain_hyperlink_lines([text.line_from('replacement')])
	cloned := terminal_ui.pending_history_lines_for_test()
	assert cloned.len == 2
	assert cloned[0].line.spans[0].text == 'older pending line'
	assert cloned[1].line.spans[0].text == 'old closing border'
	assert terminal_ui.replace_visible_history_tail(&previous_lines, &replacement, .pre_wrap) or { panic(err) }
	assert terminal_ui.pending_history_lines_for_test().len == 0
	assert terminal_ui.frame_requester.fixture_request_count() == 1
	contents := terminal_ui.terminal.backend().vt100().screen().contents()
	assert contents.contains('older pending line'), contents
	assert contents.contains('replacement'), contents
	assert !contents.contains('old closing border'), contents
	assert terminal_ui.terminal.fixture_viewport_invalidation_count() == 1
	empty := []terminal_hyperlinks.HyperlinkLine{}
	assert !(terminal_ui.replace_visible_history_tail(&empty, &replacement, .pre_wrap) or { panic(err) })
	assert terminal_ui.frame_requester.fixture_request_count() == 1
}

fn test_history_tail_errors_preserve_source_order_and_do_not_schedule_frames() {
	mut terminal := custom_terminal.Terminal.with_options(test_backend.VT100Backend.new(36, 8)) or { panic(err) }
	terminal.set_viewport_area(layout.Rect.new(0, 6, 36, 2))
	mut terminal_ui := Tui{ terminal: terminal, frame_requester: frame_requester.FrameRequester.test_dummy(), pending_history_lines: [PendingHistoryLines{ lines: terminal_hyperlinks.plain_hyperlink_lines([text.line_from('pending old tail')]), wrap_policy: .pre_wrap }] }
	defer { terminal_ui.frame_requester.close() }
	previous_lines := terminal_hyperlinks.plain_hyperlink_lines([text.line_from('pending old tail')])
	replacement := terminal_hyperlinks.plain_hyperlink_lines([text.line_from('new tail')])
	mut writer := terminal_ui.terminal.backend_mut()
	writer.fixture_fail_write_after(0)
	if _ := terminal_ui.replace_visible_history_tail(&previous_lines, &replacement, .pre_wrap) {
		assert false, 'flush failure must propagate'
	} else {
		assert err.msg() == 'terminal write failed'
	}
	assert terminal_ui.pending_history_lines_for_test().len == 1
	assert terminal_ui.terminal.viewport_area.y == 6
	assert terminal_ui.terminal.fixture_viewport_invalidation_count() == 0
	assert terminal_ui.frame_requester.fixture_request_count() == 0
	writer.fixture_allow_writes()
	Tui.flush_pending_history_lines(mut terminal_ui.terminal, mut terminal_ui.pending_history_lines, terminal_ui.scrollback, terminal_ui.terminal.last_known_screen_size) or { panic(err) }
	assert terminal_ui.pending_history_lines_for_test().len == 0
	writer.fixture_fail_write_after(0)
	if _ := terminal_ui.replace_visible_history_tail(&previous_lines, &replacement, .pre_wrap) {
		assert false, 'clear failure must propagate'
	}
	assert terminal_ui.terminal.viewport_area.y == 6
	assert terminal_ui.terminal.fixture_viewport_invalidation_count() == 0
	writer.fixture_allow_writes()
	// Cursor positioning and clearing succeed before insertion fails. The source has
	// already moved and invalidated the viewport when the insertion error propagates.
	writer.fixture_fail_write_after(2)
	if _ := terminal_ui.replace_visible_history_tail(&previous_lines, &replacement, .pre_wrap) {
		assert false, 'insertion failure must propagate'
	}
	assert terminal_ui.terminal.viewport_area.y == 5
	assert terminal_ui.terminal.fixture_viewport_invalidation_count() == 1
	assert terminal_ui.frame_requester.fixture_request_count() == 0
}

fn test_history_tail_rejects_u16_row_overflow_without_changing_terminal() {
	value := 'x'.repeat(65536)
	previous_lines := terminal_hyperlinks.plain_hyperlink_lines([text.line_from(value)])
	replacement := []terminal_hyperlinks.HyperlinkLine{}
	mut terminal := custom_terminal.Terminal.with_options(test_backend.VT100Backend.new(1, 8)) or { panic(err) }
	terminal.set_viewport_area(layout.Rect.new(0, 6, 0, 2))
	before := terminal.backend().vt100().screen().contents()
	assert !(replace_visible_terminal_history_tail(mut terminal, &previous_lines, &replacement, .standard, .terminal) or { panic(err) })
	assert terminal.viewport_area == layout.Rect.new(0, 6, 0, 2)
	assert terminal.backend().vt100().screen().contents() == before
	assert terminal.fixture_viewport_invalidation_count() == 0
	assert previous_lines[0].line.spans[0].text.len == 65536
}
