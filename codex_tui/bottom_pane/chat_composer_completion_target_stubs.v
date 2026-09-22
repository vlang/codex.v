module bottom_pane

// V modules are directory-scoped, while Rust's completion_target child imports ChatComposer's
// private TextArea and mention helpers. Keeping this shim in bottom_pane avoids a module cycle;
// the filename preserves its eventual `chat_composer/completion_target.rs` owner.

// STUB: `chat_composer/completion_target.rs::prefixed_candidate_range` result adapted from
// `(Range<usize>, String)` because V has no standard owned range payload.
struct CompletionCandidate {
	valid bool
	start int
	end   int
	query string
}

// STUB: `chat_composer/completion_target.rs::prefixed_candidate_range`; narrows a whitespace token
// to the editable segment around the cursor while treating atomic elements as hard boundaries.
fn completion_candidate(textarea &TextArea, start int, end int, anchor int, prefix rune,
	allow_empty bool) CompletionCandidate {
	if start >= end {
		return CompletionCandidate{}
	}
	text := textarea.text()
	mut segment_start := start
	mut segment_end := end
	mut has_element_boundary := false
	clamped_anchor := clamp_int(anchor, start, end)
	for element in textarea.text_elements() {
		if !ranges_overlap(start, end, element.byte_range.start, element.byte_range.end) {
			continue
		}
		has_element_boundary = true
		if element.byte_range.end <= clamped_anchor {
			segment_start = element.byte_range.end
			continue
		}
		if clamped_anchor <= element.byte_range.start {
			segment_end = element.byte_range.start
		} else {
			segment_start = clamped_anchor
			segment_end = clamped_anchor
		}
		break
	}
	if segment_start >= segment_end {
		return CompletionCandidate{}
	}
	segment := text[segment_start..segment_end]
	runes := segment.runes()
	if runes.len == 0 || runes[0] != prefix {
		// With no atomic boundary the complete whitespace-delimited token is authoritative.
		// When an element divided it, a non-prefixed editable segment is not a candidate.
		return CompletionCandidate{ valid: false }
	}
	query := runes[1..].string()
	if query.len == 0 && !allow_empty {
		// `current_at_token` retains the historical bare-@ result except while the cursor is on
		// separator whitespace; its caller handles that arbitration below.
		if prefix != `@` {
			return CompletionCandidate{}
		}
	}
	if !has_element_boundary && !starts_plaintext_at_mention(&text, start) {
		return CompletionCandidate{}
	}
	return CompletionCandidate{
		valid: true
		start: segment_start
		end:   segment_end
		query: query
	}
}

// STUB: `chat_composer/completion_target.rs` horizontal-separator predicate.
fn is_horizontal_completion_space(value rune) bool {
	return rune_is_space(value) && value !in [`\n`, `\r`, `\v`, `\f`, `\u0085`, `\u2028`, `\u2029`]
}

// STUB: byte-offset rune lookup used by `chat_composer/completion_target.rs`.
fn rune_at_byte(text &string, position int) ?rune {
	if position < 0 || position >= text.len {
		return none
	}
	next := next_char_boundary(text, position)
	runes := (*text)[position..next].runes()
	return if runes.len > 0 { runes[0] } else { none }
}

// STUB: `chat_composer/completion_target.rs::current_prefixed_token_range`.
fn current_prefixed_token_range(textarea &TextArea, prefix rune, allow_empty bool) ?(int, int, string) {
	return current_prefixed_token_range_with_dollar_predicate(textarea, prefix, allow_empty, dollar_query_can_complete)
}

// STUB: `chat_composer/completion_target.rs::current_prefixed_token_range_with_dollar_predicate`.
// V represents Rust's generic `impl Fn(&str) -> bool` as an ordinary function value.
fn current_prefixed_token_range_with_dollar_predicate(textarea &TextArea, prefix rune,
	allow_empty bool, dollar_predicate fn (&string) bool) ?(int, int, string) {
	text := textarea.text()
	if text.len == 0 {
		return none
	}
	cursor := ChatComposer.clamp_to_char_boundary(&text, textarea.cursor())
	at_whitespace := if current := rune_at_byte(&text, cursor) {
		rune_is_space(current)
	} else {
		false
	}
	previous_position := previous_char_boundary(&text, cursor)
	after_horizontal_whitespace := if cursor > 0 {
		if previous := rune_at_byte(&text, previous_position) {
			is_horizontal_completion_space(previous)
		} else {
			false
		}
	} else {
		false
	}

	// Resolve separator affinity before the ordinary token scan. A cursor just after separator
	// whitespace belongs to the token on its right; on separator whitespace an @ token on the
	// right wins, otherwise a non-empty token on the left is retained.
	if at_whitespace || after_horizontal_whitespace {
		mut left_end := cursor
		for left_end > 0 {
			previous := previous_char_boundary(&text, left_end)
			value := rune_at_byte(&text, previous) or { break }
			if !is_horizontal_completion_space(value) {
				break
			}
			left_end = previous
		}
		mut left_start := left_end
		for left_start > 0 {
			previous := previous_char_boundary(&text, left_start)
			value := rune_at_byte(&text, previous) or { break }
			if rune_is_space(value) {
				break
			}
			left_start = previous
		}
		mut right_start := cursor
		for right_start < text.len {
			value := rune_at_byte(&text, right_start) or { break }
			if !is_horizontal_completion_space(value) {
				break
			}
			right_start = next_char_boundary(&text, right_start)
		}
		mut right_end := right_start
		for right_end < text.len {
			value := rune_at_byte(&text, right_end) or { break }
			if rune_is_space(value) {
				break
			}
			right_end = next_char_boundary(&text, right_end)
		}
		left := completion_candidate(textarea, left_start, left_end, cursor, prefix, allow_empty)
		right := completion_candidate(textarea, right_start, right_end, right_start, prefix, allow_empty)
		if after_horizontal_whitespace && !at_whitespace {
			if right.valid {
				return right.start, right.end, right.query
			}
			// If the token beginning at the cursor is already atomic (or begins with an atomic
			// mention followed by a suffix), keep the editable token on the left.
			for element in textarea.text_elements() {
				if element.byte_range.start == right_start && element.byte_range.end <= right_end && left.valid {
					return left.start, left.end, left.query
				}
			}
			return none
		}
		if prefix == `@` && right.valid {
			return right.start, right.end, right.query
		}
		if at_whitespace && after_horizontal_whitespace && right_start < right_end {
			right_first := rune_at_byte(&text, right_start) or { rune(0) }
			if right_first !in [`$`, `@`] {
				return none
			}
		}
		if prefix == `$` && left.valid && right.valid
			&& !dollar_predicate(&left.query) && dollar_predicate(&right.query) {
			return right.start, right.end, right.query
		}
		if left.valid && (left.query.len > 0 || allow_empty) {
			return left.start, left.end, left.query
		}
		if right.valid {
			return right.start, right.end, right.query
		}
		return none
	}
	// Adjacent sigils start a new completion. Preserve the editable fragment immediately to the
	// left of the cursor (`$` or `$r`) instead of treating the whole `$$existing` token as one query.
	prefix_text := prefix.str()
	if allow_empty && text[cursor..].starts_with(prefix_text) {
		mut fragment_start := cursor
		for fragment_start > 0 {
			previous := previous_char_boundary(&text, fragment_start)
			value := rune_at_byte(&text, previous) or { break }
			if rune_is_space(value) {
				break
			}
			fragment_start = previous
		}
		fragment := text[fragment_start..cursor]
		if fragment.starts_with(prefix_text) {
			query := fragment[prefix_text.len..]
			mut editable := true
			for element in textarea.text_elements() {
				if ranges_overlap(fragment_start, cursor, element.byte_range.start, element.byte_range.end) {
					editable = false
					break
				}
			}
			if editable && query.bytes().all(is_mention_name_char(it))
				&& (query.len == 0 || prefix == `$`) {
				return fragment_start, cursor, query
			}
		}
	}
	mut token_start := cursor
	for token_start > 0 {
		previous := previous_char_boundary(&text, token_start)
		rune_value := text[previous..token_start].runes()[0]
		if rune_is_space(rune_value) {
			break
		}
		token_start = previous
	}
	mut token_end := cursor
	for token_end < text.len {
		next := next_char_boundary(&text, token_end)
		rune_value := text[token_end..next].runes()[0]
		if rune_is_space(rune_value) {
			break
		}
		token_end = next
	}
	candidate := completion_candidate(textarea, token_start, token_end, cursor, prefix, allow_empty)
	if !candidate.valid {
		return none
	}
	return candidate.start, candidate.end, candidate.query
}

// STUB: `chat_composer/completion_target.rs::DollarQueryKind`.
enum DollarQueryKind {
	completable
	ambiguous_shell_parameter
	shell_variable
	definite_shell_parameter
	invalid
}

// STUB: `chat_composer/completion_target.rs::dollar_query_is_completable`; ambiguous spellings
// remain eligible until the loaded mention catalog can resolve them.
fn dollar_query_can_complete(query &string) bool {
	return dollar_query_kind(query) in [.completable, .ambiguous_shell_parameter]
}

// STUB: `chat_composer/completion_target.rs::dollar_query_kind`.
fn dollar_query_kind(query &string) DollarQueryKind {
	if query.len == 0 {
		return .completable
	}
	if *query == '-' || *query == '_' || query.bytes().all(it.is_digit()) {
		return .definite_shell_parameter
	}
	name := query.all_before(':')
	if query.to_upper() == *query && is_common_environment_variable(&name) {
		return .shell_variable
	}
	if (*query)[0].is_digit() || query.starts_with('-') {
		return .ambiguous_shell_parameter
	}
	return if query.bytes().all(is_mention_name_char(it) || it == `:`) {
		.completable
	} else {
		.invalid
	}
}

// STUB: `crate::mention_codec::is_common_env_var` used by completion_target.
fn is_common_environment_variable(name &string) bool {
	return *name == 'HOME' || *name == 'PATH' || *name == 'USER' || *name == 'SHELL'
		|| *name == 'PWD' || *name == 'OLDPWD' || *name == 'TMPDIR' || *name == 'LANG'
		|| *name == 'TERM' || *name == 'EDITOR' || *name == 'VISUAL'
}
