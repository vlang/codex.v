module motion

// Centralized motion primitives for the TUI.
//
// Callers choose an explicit reduced-motion fallback here instead of reaching
// directly for time-varying spinner or shimmer helpers.

import codex_tui.motion.shimmer
import ratatui.text
import std_time
import supports_color

pub enum MotionMode {
	animated
	reduced
}

pub fn MotionMode.from_animations_enabled(animations_enabled bool) MotionMode {
	return if animations_enabled { .animated } else { .reduced }
}

pub enum ReducedMotionIndicator {
	hidden
	static_bullet
}

pub fn activity_indicator(start_time ?std_time.Instant, motion_mode MotionMode, reduced_motion_indicator ReducedMotionIndicator) ?text.Span {
	match motion_mode {
		.animated {
			return animated_activity_indicator(start_time)
		}
		.reduced {
			match reduced_motion_indicator {
				.hidden { return none }
				.static_bullet { return text.Span{ text: '•' }.dim() }
			}
		}
	}
}

pub fn shimmer_text(content &string, motion_mode MotionMode) []text.Span {
	match motion_mode {
		.animated {
			return shimmer.shimmer_spans(content)
		}
		.reduced {
			if content.len == 0 {
				return []text.Span{}
			}
			return [text.Span{ text: content.clone() }]
		}
	}
}

fn animated_activity_indicator(start_time ?std_time.Instant) text.Span {
	elapsed := if start := start_time { start.elapsed() } else { std_time.duration_zero }
	has_true_color := if level := supports_color.on_cached(.stdout) { level.has_16m } else { false }
	if has_true_color {
		bullet := '•'
		spans := shimmer.shimmer_spans(&bullet)
		if spans.len > 0 {
			return spans[0]
		}
		return text.Span{ text: '•' }
	}
	intervals, _ := elapsed.as_millis().quo_rem_64(600)
	blink_on := intervals.mod_64(2) == 0
	return if blink_on { text.Span{ text: '•' } } else { text.Span{ text: '◦' }.dim() }
}
