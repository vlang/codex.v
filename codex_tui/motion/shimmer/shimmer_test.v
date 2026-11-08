module shimmer

import codex_tui.color
import ratatui.style
import ratatui.text
import std_time

// Supply deterministic dependencies to the same position calculation and
// rendering loop used by shimmer_spans, without changing the process clock.
fn spans_for_sweep(chars &[]rune, elapsed std_time.Duration, has_true_color bool, base_color color.Rgb, highlight_color color.Rgb) []text.Span {
	if chars.len == 0 {
		return []text.Span{}
	}
	padding := usize(10)
	period := usize(chars.len) + padding * 2
	pos := sweep_position(elapsed, period, f32(2.0))
	mut spans := []text.Span{cap: chars.len}
	append_sweep_spans(mut spans, chars, padding, pos, f32(5.0), has_true_color,
		base_color, highlight_color)
	return spans
}

// This is the first test in this binary: V executes test functions in source
// order, so the empty-input call must leave the global OnceLock uninitialized.
fn test_empty_shimmer_leaves_process_clock_untouched() {
	mut state := unsafe { process_start }
	state.mutex.lock()
	initialized_before := state.initialized
	start_before := state.start
	state.mutex.unlock()
	assert !initialized_before
	assert start_before == std_time.Instant{}
	empty := $if ownership ? { ''.to_owned() } $else { ''.clone() }
	assert shimmer_spans(&empty) == []text.Span{}
	assert empty.len == 0
	state.mutex.lock()
	initialized_after := state.initialized
	start_after := state.start
	state.mutex.unlock()
	assert initialized_after == initialized_before
	assert start_after == start_before
}

fn test_fallback_thresholds_preserve_dim_plain_and_bold_styles() {
	assert color_for_level(0) == style.Style.default().dim()
	assert color_for_level(0.199) == style.Style.default().dim()
	assert color_for_level(0.2) == style.Style.default()
	assert color_for_level(0.599) == style.Style.default()
	assert color_for_level(0.6) == style.Style.default().bold()
	assert color_for_level(1) == style.Style.default().bold()
}

fn test_sweep_styles_each_unicode_scalar_including_combining_marks() {
	content := 'Aé界e\u0301'
	chars := content.runes()
	spans := spans_for_sweep(&chars, std_time.Duration.from_millis(800), false,
		color.Rgb{128, 128, 128}, color.Rgb{255, 255, 255})
	assert spans == [
		text.span_styled('A', style.Style.default().bold()),
		text.span_styled('é', style.Style.default().bold()),
		text.span_styled('界', style.Style.default().bold()),
		text.span_styled('e', style.Style.default()),
		text.span_styled('\u0301', style.Style.default().dim()),
	]
}

fn test_true_color_sweep_blends_terminal_palette_and_adds_bold() {
	content := 'Aé界e\u0301'
	chars := content.runes()
	spans := spans_for_sweep(&chars, std_time.Duration.from_millis(800), true,
		color.Rgb{10, 20, 30}, color.Rgb{110, 120, 130})
	assert spans.len == 5
	assert spans[0] == text.span_styled('A', style.Style.default().fg(style.Color.rgb(100, 110, 120)).bold())
	assert spans[4].style.add_modifier.has(.bold)
	assert spans[4].style.fg != none
}

fn test_shimmer_borrows_owner_and_empty_input_stays_empty() {
	owner := $if ownership ? { 'Aé界'.to_owned() } $else { 'Aé界'.clone() }
	first := shimmer_spans(&owner)
	second := shimmer_spans(&owner)
	assert first.len == 3
	assert second.len == 3
	assert first[1].text == 'é'
	assert second[2].text == '界'
	assert owner == 'Aé界'
	empty := ''
	assert shimmer_spans(&empty) == []text.Span{}
}

fn test_process_start_remains_synchronized_across_calls() {
	content := 'Loading'
	shimmer_spans(&content)
	mut state := unsafe { process_start }
	state.mutex.lock()
	before := state.start
	state.mutex.unlock()
	shimmer_spans(&content)
	state.mutex.lock()
	after := state.start
	initialized := state.initialized
	state.mutex.unlock()
	assert initialized
	assert before == after
}

fn initialize_shared_start(state &ProcessStart, barrier chan bool) std_time.Instant {
	_ := <-barrier
	mut shared_state := unsafe { state }
	return shared_state.get_or_init()
}

fn test_process_start_is_lazy_and_shared_across_concurrent_first_calls() {
	mut state := &ProcessStart{}
	assert !state.initialized
	assert state.start == std_time.Instant{}
	before := std_time.Instant.now()
	barrier := chan bool{cap: 12}
	mut readers := []thread std_time.Instant{}
	for _ in 0 .. 12 {
		readers << spawn initialize_shared_start(state, barrier)
	}
	for _ in 0 .. 12 {
		barrier <- true
	}
	starts := readers.wait()
	after := std_time.Instant.now()
	assert state.initialized
	assert before <= state.start
	assert state.start <= after
	assert starts.len == 12
	for start in starts {
		assert start == state.start
	}
	assert state.get_or_init() == state.start
}

fn test_owned_output_survives_replacing_the_borrowed_owner() {
	mut owner := $if ownership ? { 'Aé界'.to_owned() } $else { 'Aé界'.clone() }
	first := shimmer_spans(&owner)
	owner = $if ownership ? { 'New'.to_owned() } $else { 'New'.clone() }
	second := shimmer_spans(&owner)
	assert first.len == 3
	assert first[0].text == 'A'
	assert first[1].text == 'é'
	assert first[2].text == '界'
	assert second.len == 3
	assert second[0].text == 'N'
	assert owner == 'New'
}

fn test_sweep_wraps_after_two_seconds_and_preserves_f32_rounding() {
	assert sweep_position(std_time.Duration.from_millis(800), 25, 2) == 10
	assert sweep_position(std_time.Duration.from_millis(2800), 25, 2) == 9
	assert sweep_position(std_time.Duration.from_millis(2000), 25, 2) == 0
	assert sweep_position(std_time.Duration.from_millis(1999), 25, 2) == 24
	assert sweep_position(std_time.Duration.from_secs(16_777_217), 25, 2) == 0
}
