module bottom_pane

// Behavior: for ASCII input we "hold" the first fast char briefly. If no burst follows,
// that held char should eventually flush as normal typed input (not as a paste).
fn test_ascii_first_char_is_held_then_flushes_as_typed() {
	mut burst := PasteBurst{}
	t0 := i64(1000)
	assert burst.on_plain_char(`a`, t0).kind == .retain_first_char

	t1 := t0 + PasteBurst.recommended_flush_delay() + 1
	assert burst.flush_if_due(t1) == FlushResult{ kind: .typed, ch: `a` }
	assert !burst.is_active()
}

// Behavior: if two ASCII chars arrive quickly, we should start buffering without ever
// rendering the first one, then flush the whole buffered payload as a paste.
fn test_ascii_two_fast_chars_start_buffer_from_pending_and_flush_as_paste() {
	mut burst := PasteBurst{}
	t0 := i64(1000)
	assert burst.on_plain_char(`a`, t0).kind == .retain_first_char

	t1 := t0 + 1
	assert burst.on_plain_char(`b`, t1).kind == .begin_buffer_from_pending
	burst.append_char_to_buffer(`b`, t1)

	t2 := t1 + PasteBurst.recommended_active_flush_delay() + 1
	assert burst.flush_if_due(t2) == FlushResult{ kind: .paste, text: 'ab' }
}

// Behavior: when non-char input is about to be applied, we flush any transient burst state
// immediately (including a single pending ASCII char) so state doesn't leak across inputs.
fn test_flush_before_modified_input_includes_pending_first_char() {
	mut burst := PasteBurst{}
	t0 := i64(1000)
	assert burst.on_plain_char(`a`, t0).kind == .retain_first_char

	assert burst.flush_before_modified_input() or { panic('pending char should flush') } == 'a'
	assert !burst.is_active()
}

// Behavior: retro-grab buffering is only enabled when the already-inserted prefix looks
// paste-like (whitespace or "long enough") so short IME bursts don't get misclassified.
fn test_decide_begin_buffer_only_triggers_for_pastey_prefixes() {
	mut burst := PasteBurst{}
	now := i64(1000)
	short := 'ab'
	assert burst.decide_begin_buffer(now, &short, /*retro_chars*/
		2) == none
	assert !burst.is_active()

	prefix := 'a b'
	grab := burst.decide_begin_buffer(now, &prefix, /*retro_chars*/
		2) or {
		panic('whitespace should be considered paste-like')
	}
	assert grab.start_byte == 1
	assert grab.grabbed == ' b'
	assert burst.is_active()
}

// Behavior: after a paste-like burst, we keep an "enter suppression window" alive briefly so
// a slightly-late Enter still inserts a newline instead of submitting.
fn test_newline_suppression_window_outlives_buffer_flush() {
	mut burst := PasteBurst{}
	t0 := i64(1000)
	assert burst.on_plain_char(`a`, t0).kind == .retain_first_char

	t1 := t0 + 1
	assert burst.on_plain_char(`b`, t1).kind == .begin_buffer_from_pending
	burst.append_char_to_buffer(`b`, t1)

	t2 := t1 + PasteBurst.recommended_active_flush_delay() + 1
	assert burst.flush_if_due(t2) == FlushResult{ kind: .paste, text: 'ab' }
	assert !burst.is_active()

	assert burst.newline_should_insert_instead_of_submit(t2)
	t3 := t1 + paste_enter_suppress_window + 1
	assert !burst.newline_should_insert_instead_of_submit(t3)
}

// Borrowed prefixes remain usable after repeated classification and byte-boundary queries.
fn test_paste_burst_borrowed_prefix_remains_owned() {
	mut prefix := 'é λ🙂'
	$if ownership ? {
		prefix = 'é λ🙂'.to_owned()
	}
	mut burst := PasteBurst{}
	assert retro_start_index(&prefix, 3) == 2
	assert retro_start_index(&prefix, 2) == 3
	assert prefix == 'é λ🙂'
	for _ in 0 .. 2 {
		grab := burst.decide_begin_buffer(1000, &prefix, 3) or { panic('space triggers paste') }
		assert grab.start_byte == 2
		assert grab.grabbed == ' λ🙂'
		assert prefix == 'é λ🙂'
		burst.clear_after_explicit_paste()
	}
	assert prefix == 'é λ🙂'
}

// A zero timestamp is valid, and expiration is strictly later than the timeout.
fn test_paste_burst_zero_timestamp_and_strict_flush_threshold() {
	mut burst := PasteBurst{}
	assert burst.on_plain_char(`a`, 0).kind == .retain_first_char
	assert burst.flush_if_due(paste_burst_char_interval).kind == .no_flush
	assert burst.is_active()
	assert burst.flush_if_due(paste_burst_char_interval + 1) == FlushResult{
		kind: .typed
		ch:   `a`
	}
	assert !burst.is_active()
}

// Burst counting saturates as Rust u16::saturating_add does, including retro-capture payloads.
fn test_paste_burst_no_hold_count_saturates() {
	mut burst := PasteBurst{
		last_plain_char_time:         i64(1000)
		consecutive_plain_char_burst: u16(0xffff)
	}
	decision := burst.on_plain_char_no_hold(1001) or { panic('three or more chars start a burst') }
	assert decision == CharDecision{ kind: .begin_buffer, retro_chars: u16(0xfffe) }
	assert burst.consecutive_plain_char_burst == u16(0xffff)
	assert !burst.is_active()
	burst.clear_window_after_non_char()
	assert burst.on_plain_char_no_hold(1002) == none
	assert burst.consecutive_plain_char_burst == 1
}

// Enter promotes a pending ASCII char but does not reset the last plain-char timestamp.
fn test_paste_burst_newline_promotes_pending_and_preserves_plain_char_time() {
	mut burst := PasteBurst{}
	assert !burst.append_newline_if_active(999)
	assert burst.on_plain_char(`a`, 1000).kind == .retain_first_char
	assert burst.append_newline_if_active(1001)
	assert burst.last_plain_char_time or { panic('plain char records time') } == 1000
	assert burst.buffer == 'a\n'
	assert burst.flush_if_due(1000 + PasteBurst.recommended_active_flush_delay()) == FlushResult{
		kind: .paste
		text: 'a\n'
	}
}

// Direct insertion has its own recent-char check, and its Enter window includes the endpoint.
fn test_paste_burst_direct_insert_newline_and_extended_window() {
	mut burst := PasteBurst{}
	assert !burst.direct_insert_newline_should_insert(1000)
	assert burst.on_plain_char_no_hold(1000) == none
	assert !burst.newline_should_insert_instead_of_submit(1001)
	assert burst.direct_insert_newline_should_insert(1000 + paste_burst_char_interval)
	assert !burst.direct_insert_newline_should_insert(1000 + paste_burst_char_interval + 1)
	burst.extend_window(1010)
	assert burst.newline_should_insert_instead_of_submit(1010 + paste_enter_suppress_window)
	assert !burst.newline_should_insert_instead_of_submit(1011 + paste_enter_suppress_window)
}

// Clearing the classification window preserves buffered text; flushing active empty state is Some("").
fn test_paste_burst_clearing_window_preserves_buffer_and_flushes_empty_active_state() {
	mut burst := PasteBurst{}
	assert !burst.try_append_char_if_active(`x`, 1000)
	burst.begin_with_retro_grabbed('buffered', 1000)
	assert burst.try_append_char_if_active(`é`, 1001)
	assert burst.flush_if_due(2000).kind == .no_flush
	burst.clear_window_after_non_char()
	assert burst.is_active()
	assert burst.flush_if_due(3000).kind == .no_flush
	assert burst.flush_before_modified_input() or { panic('buffer should flush') } == 'bufferedé'
	assert !burst.is_active()
	burst.begin_with_retro_grabbed('', 4000)
	assert burst.flush_before_modified_input() or { panic('active empty state returns Some') } == ''
	assert !burst.is_active()
}

// A flushed owned payload remains usable when the detector receives and clears a later burst.
fn test_paste_burst_owned_flush_payload_survives_detector_reuse() {
	mut text := 'old payload'
	$if ownership ? {
		text = 'old payload'.to_owned()
	}
	mut burst := PasteBurst{}
	burst.begin_with_retro_grabbed(text, 1000)
	flushed := burst.flush_before_modified_input() or { panic('active payload should flush') }
	assert flushed == 'old payload'
	assert burst.on_plain_char(`n`, 1001).kind == .retain_first_char
	assert burst.on_plain_char(`e`, 1002).kind == .begin_buffer_from_pending
	burst.append_char_to_buffer(`e`, 1002)
	burst.clear_after_explicit_paste()
	assert !burst.is_active()
	assert flushed == 'old payload'
}
