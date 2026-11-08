module custom_terminal

import codex_tui.test_backend
import codex_tui.color
import codex_tui.terminal_palette
import crossterm.cursor
import ratatui.buffer
import ratatui.layout
import ratatui.style
import ratatui.widgets
import vt100

fn test_terminal_draw_repairs_styled_anchor_on_cursor_only_frames() {
	mut terminal := Terminal.with_options(test_backend.VT100Backend.new( /*width*/
	12, /*height*/
		2)) or { panic(err) }
	area := layout.Rect.new( /*x*/
	0, /*y*/
		1, /*width*/
		12, /*height*/
		1)
	terminal.set_viewport_area(area)
	mut frames := []string{}
	mut parser := vt100.Parser.new( /*rows*/
	2, /*cols*/
		12, /*scrollback_len*/
		0)
	positions := [u16(1), 4, 3, 1]
	styles := [cursor.CursorStyle.default_user_shape, .default_user_shape, .steady_bar, .steady_block]
	for index, x in positions {
		cursor_style := styles[index]
		terminal.backend_mut().clear_output()
		terminal.draw(fn [area, x, cursor_style] (mut frame Frame) {
			paragraph := widgets.Paragraph.new('ab  cd  ef').style(style.Style{}.bg(terminal_palette.rgb_color(color.Rgb{ r: 80, g: 80, b: 80 })).bold())
			mut buf := frame.buffer_mut()
			paragraph.render(area, mut buf)
			frame.set_cursor_style(cursor_style)
			frame.set_cursor_position(layout.Position{ x: x, y: 1 })
		}) or { panic(err) }
		output := terminal.backend().output()
		bytes := output.bytes()
		parser.process(&bytes)
		assert parser.screen().contents() == '\nab  cd  ef  '
		assert parser.screen().cursor_position() == layout.Position{ x: x, y: 1 }
		for column in 0 .. area.width {
			cell := parser.screen().cell(1, column) or { panic(err) }
			assert cell.bgcolor() == style.Color.rgb(80, 80, 80)
			assert cell.bold(), 'lost anchor or trailing-cell modifier at ${column}'
		}
		frames << cursor_escape_debug(&output)
	}
	assert frames.join('\n') == cursor_snapshot($embed_file('fixtures/codex_tui__custom_terminal__tests__cursor__cursor_style_styled_frames.snap').to_string())
}

fn test_terminal_draw_repairs_owned_wide_hyperlink_after_skipped_glyphs() {
	mut terminal := Terminal.with_options(test_backend.VT100Backend.new( /*width*/
	8, /*height*/
		1)) or { panic(err) }
	area := layout.Rect.new( /*x*/
	0, /*y*/
		0, /*width*/
		8, /*height*/
		1)
	terminal.set_viewport_area(area)
	mut frames := []string{}
	for _ in 0 .. 2 {
		terminal.backend_mut().clear_output()
		terminal.draw(fn (mut frame Frame) {
			mut buf := frame.buffer_mut()
			text := '中x界'
			buf.set_string(0, 0, &text, style.Style{}.bg(style.Color{ kind: .blue }))
			mut first := buf.cell_mut(layout.Position{ x: 0, y: 0 }) or { panic(err) }
			first.diff_option = buffer.CellDiffOption{ kind: .skip }
			mut second := buf.cell_mut(layout.Position{ x: 2, y: 0 }) or { panic(err) }
			second.diff_option = buffer.CellDiffOption{ kind: .skip }
			mut linked := buf.cell_mut(layout.Position{ x: 3, y: 0 }) or { panic(err) }
			text_link := '\x1b]8;;https://example.com\x07界\x1b]8;;\x07'
			linked.set_symbol(&text_link)
			linked.diff_option = buffer.CellDiffOption.forced_width( /*n*/
			2) or { panic(err) }
			frame.set_cursor_position(layout.Position{ x: 5, y: 0 })
		}) or { panic(err) }
		output := terminal.backend().output()
		frames << cursor_escape_debug(&output)
	}
	assert frames.join('\n') == cursor_snapshot($embed_file('fixtures/codex_tui__custom_terminal__tests__cursor__cursor_style_owned_wide_frames.snap').to_string())
}

fn test_terminal_draw_repairs_single_column_without_scrolling() {
	mut terminal := Terminal.with_options(test_backend.VT100Backend.new( /*width*/
	1, /*height*/
		1)) or { panic(err) }
	area := layout.Rect.new( /*x*/
	0, /*y*/
		0, /*width*/
		1, /*height*/
		1)
	terminal.set_viewport_area(area)
	mut frames := []string{}
	mut parser := vt100.Parser.new( /*rows*/
	1, /*cols*/
		1, /*scrollback_len*/
		1)
	for _ in 0 .. 3 {
		terminal.backend_mut().clear_output()
		terminal.draw(fn [area] (mut frame Frame) {
			paragraph := widgets.Paragraph.new('x').style(style.Style{}.bg(style.Color{ kind: .blue }))
			mut buf := frame.buffer_mut()
			paragraph.render(area, mut buf)
			frame.set_cursor_position(layout.Position{ x: 0, y: 0 })
		}) or { panic(err) }
		output := terminal.backend().output()
		bytes := output.bytes()
		parser.process(&bytes)
		assert parser.screen().contents() == 'x'
		assert parser.screen().cursor_position() == layout.Position{ x: 0, y: 0 }
		frames << cursor_escape_debug(&output)
	}
	parser.screen_mut().set_scrollback( /*rows*/
	1)
	assert parser.screen().scrollback() == 0
	assert frames.join('\n') == cursor_snapshot($embed_file('fixtures/codex_tui__custom_terminal__tests__cursor__cursor_style_single_column_frames.snap').to_string())
}

fn test_terminal_draw_omits_cursor_style_without_an_owned_glyph() {
	mut terminal := Terminal.with_options(test_backend.VT100Backend.new( /*width*/
	2, /*height*/
		1)) or { panic(err) }
	for width in [u16(0), 2] {
		terminal.set_viewport_area(layout.Rect.new( /*x*/
		0, /*y*/
			0, width, /*height*/
			1))
		for mut buf in terminal.buffers {
			for mut cell in buf.cells {
				cell.diff_option = buffer.CellDiffOption{ kind: .skip }
			}
		}
		terminal.backend_mut().clear_output()
		terminal.draw(fn (mut frame Frame) {
			mut buf := frame.buffer_mut()
			for mut cell in buf.cells {
				cell.diff_option = buffer.CellDiffOption{ kind: .skip }
			}
			frame.set_cursor_style(.steady_bar)
			frame.set_cursor_position(layout.Position{ x: 1, y: 0 })
		}) or { panic(err) }
		assert terminal.backend().output() == '\x1b[39m\x1b[49m\x1b[0m\x1b[1;2H\x1b[?25h'
	}
	terminal.set_viewport_area(layout.Rect{})
	terminal.backend_mut().clear_output()
	terminal.draw(fn (mut frame Frame) {}) or { panic(err) }
	assert terminal.backend().output() == '\x1b[39m\x1b[49m\x1b[0m\x1b[?25l'
}

// The copied Rust snapshots remain the exact local byte-output oracle.
fn cursor_snapshot(snapshot string) string {
	return snapshot.split_into_lines()[4..].join('\n')
}

fn cursor_escape_debug(value &string) string {
	mut escaped := ''
	for character in value.runes() {
		escaped += match character {
			27 { '\\u{1b}' }
			7 { '\\u{7}' }
			`\n` { '\\n' }
			`\r` { '\\r' }
			`\t` { '\\t' }
			`\\` { '\\\\' }
			else { character.str() }
		}
	}
	return escaped
}

fn test_cursor_repair_restores_actual_jediterm_glyph_style_and_hyperlink() {
	mut terminal := Terminal.with_options(test_backend.VT100Backend.new(8, 1)) or { panic(err) }
	area := layout.Rect.new(0, 0, 8, 1)
	terminal.set_viewport_area(area)
	terminal.backend_mut().fixture_enable_jediterm_damage()
	for _ in 0 .. 2 {
		terminal.draw(fn (mut frame Frame) {
			mut buf := frame.buffer_mut()
			text := '中x界'
			buf.set_string(0, 0, &text, style.Style{}.bg(style.Color.rgb(80, 80, 80)).bold())
			mut first := buf.cell_mut(layout.Position{ x: 0 }) or { panic(err) }
			first.diff_option = buffer.CellDiffOption{ kind: .skip }
			mut second := buf.cell_mut(layout.Position{ x: 2 }) or { panic(err) }
			second.diff_option = buffer.CellDiffOption{ kind: .skip }
			mut linked := buf.cell_mut(layout.Position{ x: 3 }) or { panic(err) }
			symbol := '\x1b]8;;https://example.com\x07界\x1b]8;;\x07'
			linked.set_symbol(&symbol)
			linked.diff_option = buffer.CellDiffOption.forced_width(2) or { panic(err) }
			frame.set_cursor_position(layout.Position{ x: 5 })
		}) or { panic(err) }
		cell := terminal.backend().vt100().screen().cell(0, 3) or { panic(err) }
		assert cell.contents() == '界'
		assert cell.bgcolor() == style.Color.rgb(80, 80, 80)
		assert cell.bold()
		assert cell.hyperlink_destination() == 'https://example.com'
		assert terminal.backend().vt100().screen().cursor_position() == layout.Position{ x: 5 }
	}
	// Prove the parser models the old-terminal bug when the redraw is omitted.
	mut parser := vt100.Parser.new(1, 8, 0)
	parser.fixture_enable_jediterm_damage()
	bytes := '\x1b[1;4H\x1b[1m\x1b[48;2;80;80;80m\x1b]8;;https://example.com\x07界\x1b]8;;\x07\x1b[0m\x1b[1;4H\x1b[0 q'.bytes()
	parser.process(&bytes)
	damaged := parser.screen().cell(0, 3) or { panic(err) }
	assert damaged.contents() == ' '
	assert damaged.bgcolor() == style.Color{}
	assert !damaged.bold()
	assert damaged.hyperlink_destination() == ''
}

fn test_cursor_repair_checks_width_row_fit_row_order_and_keeps_requested_restore_outside_helper() {
	mut terminal := Terminal.with_options(test_backend.VT100Backend.new(5, 3)) or { panic(err) }
	terminal.set_viewport_area(layout.Rect.new(1, 1, 3, 2))
	{
		mut buf := &terminal.buffers[terminal.current]
		for mut cell in buf.cells {
			cell.diff_option = buffer.CellDiffOption{ kind: .skip }
		}
		empty := ''
		buf.cells[0].set_symbol(&empty)
		buf.cells[0].diff_option = buffer.CellDiffOption{}
		buf.cells[1].diff_option = buffer.CellDiffOption.forced_width(3) or { panic(err) }
		text := 'z'
		buf.cells[3].set_symbol(&text)
		buf.cells[3].diff_option = buffer.CellDiffOption{}
	}
	terminal.set_cursor_style_with_repair(.steady_bar) or { panic(err) }
	assert terminal.backend().output().starts_with('\x1b[3;2H\x1b[6 q\x1b[3;2Hz')
	assert terminal.last_known_cursor_pos == layout.Position{ x: 1, y: 2 }
}

fn test_cursor_repair_propagates_each_native_call_error_and_preserves_borrowed_buffer_owners() {
	mut symbol := '界'
	mut linked_symbol := '\x1b]8;;https://example.com\x07界\x1b]8;;\x07'
	$if ownership ? {
		symbol = symbol.to_owned()
		linked_symbol = linked_symbol.to_owned()
	}
	mut terminal := Terminal.with_options(test_backend.VT100Backend.new(3, 1)) or { panic(err) }
	terminal.set_viewport_area(layout.Rect.new(0, 0, 3, 1))
	{
		mut buf := &terminal.buffers[terminal.current]
		buf.set_string(0, 0, &symbol, style.Style{}.bg(style.Color{ kind: .blue }))
		buf.set_string(0, 0, &symbol, style.Style{}.bg(style.Color{ kind: .blue }))
		buf.cells[0].set_symbol(&linked_symbol)
		buf.cells[0].set_symbol(&linked_symbol)
		buf.cells[0].diff_option = buffer.CellDiffOption.forced_width(2) or { panic(err) }
	}
	for successful_calls in 0 .. 8 {
		terminal.backend_mut().clear_output()
		terminal.backend_mut().fixture_fail_write_after(successful_calls)
		terminal.set_cursor_style_with_repair(.steady_bar) or {
			assert err.msg() == 'terminal write failed'
			output := terminal.backend().output()
			assert output.count('\x1b[6 q') == if successful_calls > 1 { 1 } else { 0 }
			terminal.backend_mut().fixture_allow_writes()
			continue
		}
		assert false, 'expected native I/O failure at write ${successful_calls}'
	}
	terminal.backend_mut().clear_output()
	terminal.set_cursor_style_with_repair(.steady_bar) or { panic(err) }
	terminal.set_cursor_style_with_repair(.default_user_shape) or { panic(err) }
	assert symbol == '界'
	assert linked_symbol == '\x1b]8;;https://example.com\x07界\x1b]8;;\x07'
	assert terminal.buffers[terminal.current].cells[0].symbol == linked_symbol
}
