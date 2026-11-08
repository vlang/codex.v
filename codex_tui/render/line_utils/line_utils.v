module line_utils

import ratatui.text

// V's owned array parameters are immutable bindings. This local container makes
// the consumed array mutable without constructing a borrowed mutable alias.
struct ConsumedLines {
mut:
	values []text.Line
}

// Create a ratatui `Line` that borrows the contents of another line.
// V represents Rust's Line<'a> using BorrowedLine because the existing Line's
// strings are owned. Both representations are accepted through specialization;
// neither branch clones content. The owner must outlive the returned view.
pub fn line_to_borrowed[T](line &T) text.BorrowedLine {
	mut spans := []text.BorrowedSpan{cap: line.spans.len}
	for index in 0 .. line.spans.len {
		$if T is text.Line {
			spans << text.BorrowedSpan{
				style: line.spans[index].style
				text:  &line.spans[index].text
			}
		} $else $if T is text.BorrowedLine {
			spans << text.BorrowedSpan{
				style: line.spans[index].style
				text:  line.spans[index].text
			}
		} $else {
			$compile_error('line_to_borrowed requires ratatui.text.Line or BorrowedLine')
		}
	}
	return text.BorrowedLine{
		style:     line.style
		alignment: line.alignment
		spans:     spans
	}
}

// Clone a borrowed ratatui `Line` into an owned `'static` line.
// The generic parameter only bridges owned Line and its borrowed view; each
// content clone is at the source's Cow::Owned(content.to_string()) boundary.
pub fn line_to_static[T](line &T) text.Line {
	mut spans := []text.Span{cap: line.spans.len}
	for index in 0 .. line.spans.len {
		$if T is text.Line || T is text.BorrowedLine {
			spans << text.Span{
				style: line.spans[index].style
				text:  line.spans[index].text.clone()
			}
		} $else {
			$compile_error('line_to_static requires ratatui.text.Line or BorrowedLine')
		}
	}
	return text.Line{
		style:     line.style
		alignment: line.alignment
		spans:     spans
	}
}

// Append owned copies of borrowed lines to `out`.
pub fn push_owned_lines[T](src &[]T, mut out []text.Line) {
	for index in 0 .. src.len {
		out << line_to_static(&(*src)[index])
	}
}

// Consider a line blank if it has no spans or only spans whose contents are
// empty or consist solely of spaces (no tabs/newlines).
// Rust exposes this helper only under cfg(test). V cannot conditionally remove
// an exported declaration, so the same test utility remains available here.
pub fn is_blank_line_spaces_only[T](line &T) bool {
	if line.spans.len == 0 {
		return true
	}
	for index in 0 .. line.spans.len {
		$if T is text.Line {
			for character in line.spans[index].text.runes() {
				if character != ` ` {
					return false
				}
			}
		} $else $if T is text.BorrowedLine {
			for character in (*line.spans[index].text).runes() {
				if character != ` ` {
					return false
				}
			}
		} $else {
			$compile_error('is_blank_line_spaces_only requires ratatui.text.Line or BorrowedLine')
		}
	}
	return true
}

// Prefix each line with `initial_prefix` for the first line and
// `subsequent_prefix` for following lines. Returns a new Vec of owned lines.
pub fn prefix_lines(lines []text.Line, initial_prefix text.Span, subsequent_prefix text.Span) []text.Line {
	mut output := []text.Line{cap: lines.len}
	// V's value iteration clones resource-owning elements, while indexed moves are
	// rejected across loop iterations. Reverse the consumed array in place and pop
	// its elements to retain Rust's into_iter order without cloning any span text.
	mut remaining := ConsumedLines{ values: lines }
	remaining.values.reverse_in_place()
	line_count := remaining.values.len
	for index in 0 .. line_count {
		line := remaining.values.pop()
		mut spans := []text.Span{cap: line.spans.len + 1}
		spans << if index == 0 { initial_prefix.clone() } else { subsequent_prefix.clone() }
		spans << line.spans
		// V's ownership checker requires an intermediate for this consuming call chain.
		owned_line := text.line_from_spans(spans)
		output << owned_line.style(line.style)
	}
	return output
}
