module test_support

import codex_tui.tui
import ratatui.layout

// STUB: crate::tui::test_support::make_test_tui. The untranslated native backend and stderr guard
// are replaced by the same 80x24 screen-size override as the Rust test terminal.
pub fn make_test_tui() !tui.Tui {
	return tui.Tui.screen_size_fixture(layout.Size.new(80, 24))
}
