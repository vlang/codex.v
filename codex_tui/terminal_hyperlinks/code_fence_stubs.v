module terminal_hyperlinks

import ratatui.text
import std_ops

// STUB: terminal_hyperlinks.rs TerminalHyperlink's typed column range and destination kind.
// OSC 8 destination validation and terminal-buffer application remain untranslated.
enum DestinationKind {
	web
	trusted_file
}

// STUB: terminal_hyperlinks.rs TerminalHyperlink with its existing typed Range<usize> owner.
pub struct TerminalHyperlink {
	destination_kind DestinationKind
pub:
	columns     std_ops.Range[usize]
	destination string
}

// STUB: terminal_hyperlinks.rs HyperlinkLine, keeping semantic links separate from text.
pub struct HyperlinkLine {
pub:
	line       text.Line
	hyperlinks []TerminalHyperlink
}

// STUB: terminal_hyperlinks.rs HyperlinkLine::new consumes a line and adds no annotations.
pub fn HyperlinkLine.new(line text.Line) HyperlinkLine {
	return HyperlinkLine{ line: line, hyperlinks: []TerminalHyperlink{} }
}
