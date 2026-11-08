// Pipe-table holdback scanner for source-backed agent streams.
//
// Agent streams with markdown tables keep the active table as mutable tail so
// adding a row can reflow earlier table rows instead of committing a stale
// render to scrollback.
//
// The scanner is intentionally conservative: it only looks for enough
// structure to decide where the mutable tail should start. It does not try to
// validate an entire table or predict final layout. Rendering remains the job
// of the markdown renderer.
module table_holdback

import codex_tui.table_detect
import std_time
import tracing

// Rust str::trim uses Unicode White_Space rather than V's ASCII trim_space.
const unicode_whitespace = '\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000'

// An allocation-free tag preserves Rust's Copy enum with two usize payloads.
pub enum TableHoldbackKind {
	none
	pending_header
	confirmed
}

// Result of scanning accumulated raw source for pipe-table patterns.
pub struct TableHoldbackState {
pub:
	// No table detected -- all rendered lines can flow into the stable queue.
	// The none tag has no payload.
	kind TableHoldbackKind
	// The last non-blank line looks like a table header row but no delimiter
	// row has followed yet. Hold back in case the next delta is a delimiter.
	header_start usize
	// A header + delimiter pair was found -- the source contains a confirmed
	// table. Content from the table header onward stays mutable.
	table_start usize
}

// Rust derives Clone, Copy, PartialEq, Eq, and Debug for the active variant.
pub fn (state TableHoldbackState) clone() TableHoldbackState {
	return state
}

pub fn (left TableHoldbackState) == (right TableHoldbackState) bool {
	if left.kind != right.kind {
		return false
	}
	return match left.kind {
		.none { true }
		.pending_header { left.header_start == right.header_start }
		.confirmed { left.table_start == right.table_start }
	}
}

pub fn (state TableHoldbackState) str() string {
	return match state.kind {
		.none { 'None' }
		.pending_header { 'PendingHeader { header_start: ${state.header_start} }' }
		.confirmed { 'Confirmed { table_start: ${state.table_start} }' }
	}
}

// Facts remembered about the previous committed source line.
//
// The scanner only needs one-line lookbehind because a table is confirmed by
// a header row immediately followed by a delimiter row.
struct PreviousLineState {
	source_start usize
	fence_kind   table_detect.FenceKind
	is_header    bool
}

// Incremental scanner for table holdback state on append-only source streams.
//
// push_source_chunk must receive source in the same order it will be
// appended to the stream. The scanner stores byte offsets into that logical
// source buffer, so feeding chunks out of order would make later tail
// boundaries point at the wrong rendered region.
pub struct TableHoldbackScanner {
mut:
	source_offset         usize
	fence_tracker         table_detect.FenceTracker
	previous_line         ?PreviousLineState
	pending_header_start  ?usize
	confirmed_table_start ?usize
}

pub fn TableHoldbackScanner.new() TableHoldbackScanner {
	return TableHoldbackScanner{
		source_offset:         0
		fence_tracker:         table_detect.new_fence_tracker()
		previous_line:         none
		pending_header_start:  none
		confirmed_table_start: none
	}
}

pub fn (mut scanner TableHoldbackScanner) reset() {
	scanner = TableHoldbackScanner.new()
}

// Return the current holdback decision for the committed source prefix.
//
// PendingHeader means the newest non-blank line looks like a table
// header but the delimiter row has not arrived yet, so callers should
// optimistically keep that region mutable. Confirmed means the header
// and delimiter pair has been seen and all subsequent body rows remain in
// the live tail until finalization.
pub fn (scanner &TableHoldbackScanner) state() TableHoldbackState {
	if table_start := scanner.confirmed_table_start {
		return TableHoldbackState{ kind: .confirmed, table_start: table_start }
	} else if header_start := scanner.pending_header_start {
		return TableHoldbackState{ kind: .pending_header, header_start: header_start }
	}
	return TableHoldbackState{ kind: .none }
}

// Advance the scanner with newly committed source.
//
// Chunks are expected to contain only source that is now safe to commit
// into raw_source, typically newline-terminated lines from the
// streaming collector. Partial rows are intentionally excluded so the
// scanner never treats an unfinished table row as a stable structural
// signal.
pub fn (mut scanner TableHoldbackScanner) push_source_chunk(source_chunk &string) {
	if source_chunk.len == 0 {
		return
	}

	scan_start := std_time.Instant.now()
	mut lines := usize(0)
	mut start := 0
	for index in 0 .. source_chunk.len {
		if (*source_chunk)[index] == `\n` {
			// V slices own their text; retain Rust split_inclusive's exact LF
			// boundaries and byte offsets without constructing an array of rows.
			source_line := (*source_chunk)[start..index + 1]
			lines++
			scanner.push_line(&source_line)
			start = index + 1
		}
	}
	if start < source_chunk.len {
		source_line := (*source_chunk)[start..]
		lines++
		scanner.push_line(&source_line)
	}
	tracing.trace_table_holdback_incremental_scan(tracing.TableHoldbackIncrementalScan{
		bytes:      usize(source_chunk.len)
		lines:      lines
		state:      scanner.state()
		elapsed_us: scan_start.elapsed().as_micros()
	})
}

// Fold one committed source line into the scanner state machine.
fn (mut scanner TableHoldbackScanner) push_line(source_line &string) {
	line := if source_line.ends_with('\n') {
		(*source_line)[..source_line.len - 1]
	} else {
		source_line.clone()
	}
	source_start := scanner.source_offset
	fence_kind := scanner.fence_tracker.kind()

	candidate_text := if fence_kind == .other { ?string(none) } else { table_candidate_text(&line) }
	is_header := if text := candidate_text {
		table_detect.is_table_header_line(&text)
	} else {
		false
	}
	is_delimiter := if text := candidate_text {
		table_detect.is_table_delimiter_line(&text)
	} else {
		false
	}

	if scanner.confirmed_table_start == none {
		if previous_line := scanner.previous_line {
			if previous_line.fence_kind != .other && fence_kind != .other
				&& previous_line.is_header && is_delimiter {
				scanner.confirmed_table_start = previous_line.source_start
				scanner.pending_header_start = none
			}
		}
	}

	if scanner.confirmed_table_start == none && line.trim(unicode_whitespace).len != 0 {
		if fence_kind != .other && is_header {
			scanner.pending_header_start = source_start
		} else {
			scanner.pending_header_start = none
		}
	}

	scanner.previous_line = PreviousLineState{
		source_start: source_start
		fence_kind:   fence_kind
		is_header:    is_header
	}

	scanner.fence_tracker.advance(&line)
	scanner.source_offset = saturating_add(scanner.source_offset, usize(source_line.len))
}

// Strip blockquote prefixes and return the trimmed text if it contains
// pipe-table segments, or none otherwise.
//
// Table holdback treats quoted tables as real tables, but it still requires a
// pipe-table shape after the quote markers are removed.
// Rust returns a borrowed slice. V returns an owned string while retaining the
// input owner; all positions still refer to bytes of the original source.
fn table_candidate_text(line &string) ?string {
	stripped := table_detect.strip_blockquote_prefix(line).trim(unicode_whitespace)
	if _ := table_detect.parse_table_segments(&stripped) {
		return stripped
	}
	return none
}

// Rust usize::saturating_add retains the platform-sized unsigned range.
fn saturating_add(left usize, right usize) usize {
	return if right > ~usize(0) - left { ~usize(0) } else { left + right }
}
