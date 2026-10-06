module shimmer

import codex_tui.color
import codex_tui.terminal_palette
import math
import ratatui.style
import ratatui.text as terminal_text
import std_time
import supports_color
import sync

// Rust's OnceLock initializes the monotonic process origin on first use. A
// mutex guards the same lazy initialization; the Instant itself is Copy-equivalent.
@[heap]
struct ProcessStart {
mut:
	mutex       &sync.Mutex = sync.new_mutex()
	initialized bool
	start       std_time.Instant
}

const process_start = &ProcessStart{}

fn elapsed_since_start() std_time.Duration {
	mut state := unsafe { process_start }
	state.mutex.lock()
	if !state.initialized {
		state.start = std_time.Instant.now()
		state.initialized = true
	}
	start := state.start
	state.mutex.unlock()
	return start.elapsed()
}

// The borrowed UTF-8 owner remains reusable; each returned span owns its rune's
// string, matching Rust's ch.to_string() and Span<'static> allocation boundary.
pub fn shimmer_spans(text &string) []terminal_text.Span {
	chars := text.runes()
	if chars.len == 0 {
		return []terminal_text.Span{}
	}
	elapsed := elapsed_since_start()
	has_true_color := if level := supports_color.on_cached(.stdout) { level.has_16m } else { false }
	base_color := terminal_palette.default_fg() or { color.Rgb{128, 128, 128} }
	highlight_color := terminal_palette.default_bg() or { color.Rgb{255, 255, 255} }
	return shimmer_spans_at(&chars, elapsed, has_true_color, base_color, highlight_color)
}

// Extracted rendering body permits deterministic clock/capability/palette
// assertions without changing the public API's process-wide clock or terminal state.
fn shimmer_spans_at(chars &[]rune, elapsed std_time.Duration, has_true_color bool, base_color color.Rgb, highlight_color color.Rgb) []terminal_text.Span {
	if chars.len == 0 { return []terminal_text.Span{} }
	// Use time-based sweep synchronized to process start.
	padding := usize(10)
	period := usize(chars.len) + padding * 2
	sweep_seconds := f32(2.0)
	// V disallows float %, so use fmod with an f32 result. Explicit f32
	// rounding retains Rust's single-precision sweep and cosine intermediates.
	phase := f32(math.fmod(f64(elapsed.as_secs_f32()), f64(sweep_seconds)))
	pos_f := f32(f32(phase / sweep_seconds) * f32(period))
	// Rust uses isize for signed distance. V arrays use 32-bit int indices;
	// widen before adding padding so a legal large index cannot overflow.
	pos := i64(pos_f)
	band_half_width := f32(5.0)
	mut spans := []terminal_text.Span{cap: chars.len}
	for i, ch in *chars {
		i_pos := i64(i) + i64(padding)
		dist := f32(if i_pos >= pos { i_pos - pos } else { pos - i_pos })
		t := if dist <= band_half_width {
			x := f32(f32(math.pi) * f32(dist / band_half_width))
			f32(f32(0.5) * f32(f32(1.0) + math.cosf(x)))
		} else {
			f32(0.0)
		}
		span_style := if has_true_color {
			highlight := f32(math.clamp(f64(t), 0.0, 1.0))
			rgb := color.blend(highlight_color, base_color, f32(highlight * f32(0.9)))
			// Allow custom RGB colors, as the implementation is thoughtfully
			// adjusting the level of the default foreground color.
			style.Style.default().fg(style.Color.rgb(rgb.r, rgb.g, rgb.b)).add_modifier(.bold)
		} else {
			color_for_level(t)
		}
		spans << terminal_text.Span.styled(ch.str(), span_style)
	}
	return spans
}

fn color_for_level(intensity f32) style.Style {
	// Tune fallback styling so the shimmer band reads even without RGB support.
	if intensity < f32(0.2) {
		return style.Style.default().add_modifier(.dim)
	} else if intensity < f32(0.6) {
		return style.Style.default()
	}
	return style.Style.default().add_modifier(.bold)
}
