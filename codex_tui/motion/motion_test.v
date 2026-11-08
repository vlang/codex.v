module motion

import ratatui.text
import std_time

fn test_reduced_motion_activity_indicator_uses_explicit_fallback() {
	assert activity_indicator( /*start_time*/
	none, .reduced, .hidden) == none
	assert activity_indicator( /*start_time*/
	none, .reduced, .static_bullet) == ?text.Span(text.Span{ text: '•' }.dim())
}

fn test_reduced_motion_shimmer_text_is_plain_text() {
	loading := 'Loading'
	empty := ''
	assert shimmer_text(&loading, .reduced) == [text.Span{ text: 'Loading' }]
	assert shimmer_text(&empty, .reduced) == []text.Span{}
}

fn test_motion_mode_follows_animation_setting() {
	assert MotionMode.from_animations_enabled(true) == .animated
	assert MotionMode.from_animations_enabled(false) == .reduced
}

fn test_animated_indicator_without_start_has_zero_elapsed_and_ignores_reduced_fallback() {
	assert activity_indicator(none, .animated, .hidden) == ?text.Span(text.Span{ text: '•' })
	assert activity_indicator(none, .animated, .static_bullet) == ?text.Span(text.Span{ text: '•' })
}

fn test_animated_indicator_switches_every_six_hundred_milliseconds() {
	start := std_time.Instant.now().sub(std_time.Duration.from_millis(900))
	assert activity_indicator(start, .animated, .hidden) == ?text.Span(text.Span{ text: '◦' }.dim())
	older_start := std_time.Instant.now().sub(std_time.Duration.from_millis(1500))
	assert activity_indicator(older_start, .animated, .hidden) == ?text.Span(text.Span{ text: '•' })
	assert start < older_start.add(std_time.Duration.from_millis(1000))
}

fn test_reduced_motion_ignores_elapsed_time_and_keeps_copy_start_reusable() {
	start := std_time.Instant.now().sub(std_time.Duration.from_millis(900))
	assert activity_indicator(start, .reduced, .hidden) == none
	assert activity_indicator(start, .reduced, .static_bullet) == ?text.Span(text.Span{ text: '•' }.dim())
	assert start < std_time.Instant.now()
}

fn test_animated_blink_preserves_full_u128_millisecond_parity() {
	// Unix's signed-second clock permits this past instant. On Windows the
	// unsigned QPC origin may not have enough elapsed range to construct it.
	if start := std_time.Instant.now().checked_sub(std_time.Duration.new(9_000_000_000_000_000_000, 900_000_000)) {
		assert activity_indicator(start, .animated, .hidden) == ?text.Span(text.Span{ text: '◦' }.dim())
	}
}

fn test_borrowed_shimmer_text_can_be_reused_in_both_modes() {
	owner := $if ownership ? { 'Loading 界é'.to_owned() } $else { 'Loading 界é'.clone() }
	first := shimmer_text(&owner, .reduced)
	second := shimmer_text(&owner, .reduced)
	assert first == [text.Span{ text: 'Loading 界é' }]
	assert second == first
	animated_first := shimmer_text(&owner, .animated)
	animated_second := shimmer_text(&owner, .animated)
	assert animated_first.len == owner.runes().len
	assert animated_second.len == owner.runes().len
	assert animated_first[0].text == 'L'
	assert animated_second[0].text == 'L'
	assert owner == 'Loading 界é'
}
