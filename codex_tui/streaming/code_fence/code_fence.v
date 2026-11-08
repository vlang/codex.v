// A conservative fast path for one open, top-level, language-tagged code fence.
module code_fence

import codex_tui.render.highlight
import codex_tui.terminal_hyperlinks
import ratatui.text

// An append-only fence whose original source is identical to pulldown-cmark's code text.
pub struct OpenCodeFence {
mut:
	marker         u8
	marker_len     usize
	language       string
	content_start  usize
	source_len     usize
	theme_revision u64
	// Initialized only if another chunk arrives, avoiding duplicate work on one-shot fences.
	highlighter ?highlight.StreamingCodeHighlighter
}

// Recognize the final mutable top-level block after its canonical render.
//
// source is the final block's suffix, while source_len includes the entire committed
// Markdown source and anchors the retained fence within it.
//
// Indentation, CR/NUL normalization, and escaped info strings stay on the canonical path.
// Any line that could end the fence also stays there, including deliberately conservative
// false positives, so this fast path need not duplicate CommonMark's closing-fence grammar.
pub fn OpenCodeFence.detect(source &string, source_len usize, theme_revision u64) ?OpenCodeFence {
	if source.len == 0 {
		return none
	}
	marker := (*source)[0]
	if marker != `\`` && marker != `~` {
		return none
	}
	opening, code := source.split_once('\n')?
	mut marker_len := 0
	for marker_len < opening.len && opening[marker_len] == marker {
		marker_len++
	}
	if marker_len < 3 || !source.ends_with('\n')
		|| theme_revision != highlight.syntax_theme_revision() || source.contains('\r')
		|| source.contains('\x00') {
		return none
	}
	// Rust borrows its intermediate slices; V string slices own their text.
	// Only the bounded language token is retained in the returned fence.
	info := opening[marker_len..].trim(' \t\v\f')
	if info.contains('&') || info.contains('\\') || (marker == `\`` && info.contains('`')) {
		return none
	}
	mut language_end := 0
	for language_end < info.len && info[language_end] !in [`,`, ` `, `\t`] {
		language_end++
	}
	if language_end == 0 {
		return none
	}
	// Retain at most one bounded language token, never the streamed code itself.
	if usize(language_end) > highlight.max_highlight_line_bytes
		|| has_possible_closing_line(&code, marker, usize(marker_len)) {
		return none
	}
	if usize(code.len) > source_len {
		return none
	}
	return OpenCodeFence{
		marker:         marker
		marker_len:     usize(marker_len)
		language:       info[..language_end]
		content_start:  source_len - usize(code.len)
		source_len:     source_len
		theme_revision: theme_revision
		highlighter:    none
	}
}

// Append code only while the caller's newline-committed source extends this same fence.
//
// Returning none consumes the retained state and requires a canonical whole-fence render.
// Successful lines include the empty indent span expected by the canonical Markdown writer.
pub fn (fence OpenCodeFence) append(raw_source &string, committed_source &string) ?(OpenCodeFence, []terminal_hyperlinks.HyperlinkLine) {
	if usize(committed_source.len) > ~usize(0) - fence.source_len
		|| fence.source_len + usize(committed_source.len) != usize(raw_source.len)
		|| !raw_source.ends_with(*committed_source) || committed_source.contains('\r')
		|| committed_source.contains('\x00')
		|| has_possible_closing_line(committed_source, fence.marker, fence.marker_len)
		|| fence.theme_revision != highlight.syntax_theme_revision() {
		return none
	}
	highlighter := if existing := fence.highlighter {
		// Reading the owned optional payload consumes it. Reconstruct the returned
		// fence below instead of clearing this option: V's ownership C generation
		// otherwise frees the extracted resource when the old option is reset.
		existing
	} else {
		// The borrowed replay slice is an owned temporary in V; the highlighter
		// receives a borrow, and the retained state never owns the source text.
		code := (*raw_source)[int(fence.content_start)..int(fence.source_len)]
		highlight.StreamingCodeHighlighter.new(&code, &fence.language, fence.theme_revision)?
	}
	next_highlighter, lines := highlighter.append(committed_source)?
	mut rendered := []terminal_hyperlinks.HyperlinkLine{cap: lines.len}
	for line in lines {
		mut canonical_line := line
		// The canonical writer installs an empty indent span for top-level fences.
		canonical_line.spans.insert(0, text.Span{})
		rendered << terminal_hyperlinks.HyperlinkLine.new(canonical_line)
	}
	return OpenCodeFence{
		marker:         fence.marker
		marker_len:     fence.marker_len
		language:       fence.language
		content_start:  fence.content_start
		source_len:     usize(raw_source.len)
		theme_revision: fence.theme_revision
		highlighter:    next_highlighter
	}, rendered
}

// Conservatively detect any line that might close the fence.
//
// False positives intentionally fall back to CommonMark instead of duplicating its closer rules.
fn has_possible_closing_line(source &string, marker u8, marker_len usize) bool {
	mut start := 0
	for start < source.len {
		mut end := start
		for end < source.len && (*source)[end] != `\n` {
			end++
		}
		mut index := start
		for index < end && (*source)[index] in [` `, `\t`] {
			index++
		}
		marker_start := index
		for index < end && (*source)[index] == marker {
			index++
		}
		if usize(index - marker_start) >= marker_len {
			return true
		}
		start = end + 1
	}
	return false
}
