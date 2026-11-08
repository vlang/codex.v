module shimmer

import codex_tui.color
import codex_tui.terminal_palette
import math
import ratatui.style
import ratatui.text
import std_time
import supports_color
import sync

// V has no OnceLock<Instant>, so one heap cell and mutex initialize the Copy
// instant exactly once and keep every caller on the same process-wide sweep.
@[heap]
struct ProcessStart {
mut:
	mutex       &sync.Mutex = sync.new_mutex()
	initialized bool
	start       std_time.Instant
}

// Rust's PROCESS_START. Allocating an empty cell does not read
// the clock; the first nonempty shimmer initializes the synchronized sweep.
const process_start = &ProcessStart{}

fn elapsed_since_start() std_time.Duration {
	mut state := unsafe { process_start }
	start := state.get_or_init()
	return start.elapsed()
}

// Rust's pub(super) is public here because V requires exported functions across
// the motion and shimmer modules. The input stays borrowed; each Unicode scalar
// becomes an owned Span string at the source's ch.to_string() boundary.
pub fn shimmer_spans(content &string) []text.Span {
	chars := content.runes()
	if chars.len == 0 {
		return []text.Span{}
	}
	// Use time-based sweep synchronized to process start.
	padding := usize(10)
	period := usize(chars.len) + padding * 2
	sweep_seconds := f32(2.0)
	pos := sweep_position(elapsed_since_start(), period, sweep_seconds)
	has_true_color := if level := supports_color.on_cached(.stdout) { level.has_16m } else { false }
	band_half_width := f32(5.0)
	mut spans := []text.Span{cap: chars.len}
	base_color := terminal_palette.default_fg() or { color.Rgb{128, 128, 128} }
	highlight_color := terminal_palette.default_bg() or { color.Rgb{255, 255, 255} }
	append_sweep_spans(mut spans, &chars, padding, pos, band_half_width, has_true_color,
		base_color, highlight_color)
	return spans
}

fn color_for_level(intensity f32) style.Style {
	// Tune fallback styling so the shimmer band reads even without RGB support.
	if intensity < 0.2 {
		return style.Style.default().add_modifier(.dim)
	}
	if intensity < 0.6 {
		return style.Style.default()
	}
	return style.Style.default().add_modifier(.bold)
}

// OnceLock::get_or_init returns a shared reference in Rust. Instant is Copy, so
// V copies the initialized value while holding the mutex, then reads elapsed
// time after releasing it, as the source does.
fn (mut state ProcessStart) get_or_init() std_time.Instant {
	state.mutex.lock()
	if !state.initialized {
		state.start = std_time.Instant.now()
		state.initialized = true
	}
	start := state.start
	state.mutex.unlock()
	return start
}

// The pure position calculation and rendering loop are extracted from
// shimmer_spans so deterministic tests can exercise the real sweep with known
// elapsed time, terminal capability, and palette values.
fn sweep_position(elapsed std_time.Duration, period usize, sweep_seconds f32) usize {
	// The divisor is an exact power of two; widening its f32 remainder to V's
	// f64 fmod and narrowing again preserves the Rust f32 remainder exactly.
	pos_f := f32(math.fmod(f64(elapsed.as_secs_f32()), f64(sweep_seconds))) / sweep_seconds * f32(period)
	return usize(pos_f)
}

fn append_sweep_spans(mut spans []text.Span, chars &[]rune, padding usize, pos usize, band_half_width f32, has_true_color bool, base_color color.Rgb, highlight_color color.Rgb) {
	for index, ch in chars {
		i_pos := isize(index) + isize(padding)
		dist := f32(math.abs(i_pos - isize(pos)))
		intensity := if dist <= band_half_width {
			x := f32(math.pi) * (dist / band_half_width)
			f32(0.5) * (f32(1.0) + math.cosf(x))
		} else {
			f32(0.0)
		}
		span_style := if has_true_color {
			highlight := f32(math.clamp(f64(intensity), 0.0, 1.0))
			rgb := color.blend(highlight_color, base_color, highlight * f32(0.9))
			// Allow custom RGB colors, as the implementation is thoughtfully
			// adjusting the level of the default foreground color.
			style.Style.default().fg(style.Color.rgb(rgb.r, rgb.g, rgb.b)).add_modifier(.bold)
		} else {
			color_for_level(intensity)
		}
		spans << text.span_styled((*ch).str(), span_style)
	}
}
