module shimmer

import codex_tui.color
import math
import ratatui.style
import ratatui.text as terminal_text
import std_time

fn shimmer_owned(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn test_empty_text_and_empty_runes_produce_no_spans() {
	owner := shimmer_owned('')
	assert shimmer_spans(&owner).len == 0
	assert shimmer_spans(&owner).len == 0
	chars := []rune{}
	assert shimmer_spans_at(&chars, std_time.duration_zero, true, color.Rgb{}, color.Rgb{}).len == 0
	assert owner == ''
}

fn test_public_render_keeps_unicode_and_borrowed_owner_reusable() {
	owner := shimmer_owned('Aé🙂e\u0301')
	for _ in 0 .. 2 {
		spans := shimmer_spans(&owner)
		assert spans.len == 5
		mut restored := ''
		for index in 0 .. spans.len {
			restored += spans[index].text
		}
		assert restored == owner
	}
	assert owner == 'Aé🙂e\u0301'
}

fn test_fallback_levels_keep_exact_thresholds_and_uncolored_styles() {
	assert color_for_level(f32(0.199999)) == style.Style.default().add_modifier(.dim)
	assert color_for_level(f32(0.2)) == style.Style.default()
	assert color_for_level(f32(0.599999)) == style.Style.default()
	assert color_for_level(f32(0.6)) == style.Style.default().add_modifier(.bold)
	assert color_for_level(f32(1.0)) == style.Style.default().add_modifier(.bold)
}

fn test_sweep_padding_and_period_preserve_initial_dim_and_two_second_repeat() {
	owner := shimmer_owned('abc')
	chars := owner.runes()
	base := color.Rgb{128, 128, 128}
	highlight := color.Rgb{255, 255, 255}
	initial := shimmer_spans_at(&chars, std_time.duration_zero, false, base, highlight)
	expected := [terminal_text.Span.styled('a'.clone(), color_for_level(0)),
		terminal_text.Span.styled('b'.clone(), color_for_level(0)),
		terminal_text.Span.styled('c'.clone(), color_for_level(0))]
	assert initial == expected
	assert shimmer_spans_at(&chars, std_time.Duration.from_secs(2), false, base, highlight) == expected
	assert owner == 'abc'
}

fn test_centered_sweep_matches_cosine_band_and_fallback_thresholds() {
	owner := shimmer_owned('01234567890')
	chars := owner.runes()
	// At one second, the 31-position period places the band at floor(15.5).
	spans := shimmer_spans_at(&chars, std_time.Duration.from_secs(1), false, color.Rgb{}, color.Rgb{})
	assert spans.len == 11
	assert spans[0].style == color_for_level(0)
	assert spans[1].style == style.Style.default().add_modifier(.dim)
	assert spans[2].style == style.Style.default()
	assert spans[3].style == style.Style.default().add_modifier(.bold)
	assert spans[4].style == style.Style.default().add_modifier(.bold)
	assert spans[5].style == style.Style.default().add_modifier(.bold)
	for index in 0 .. spans.len {
		assert spans[index].style == spans[spans.len - 1 - index].style
	}
	assert owner == '01234567890'
}

fn test_rgb_sweep_uses_terminal_defaults_without_palette_quantization() {
	owner := shimmer_owned('01234567890')
	chars := owner.runes()
	base := color.Rgb{10, 20, 30}
	highlight := color.Rgb{210, 220, 230}
	spans := shimmer_spans_at(&chars, std_time.Duration.from_secs(1), true, base, highlight)
	assert spans[0].style == style.Style.default().fg(style.Color.rgb(10, 20, 30)).add_modifier(.bold)
	assert spans[5].style == style.Style.default().fg(style.Color.rgb(190, 200, 210)).add_modifier(.bold)
	for index in 0 .. spans.len {
		assert spans[index].style.fg != none
		assert spans[index].style.add_modifier == .bold
	}
	assert owner == '01234567890'
}

fn test_duration_float_seconds_and_monotonic_origin_are_reused() {
	assert std_time.Duration.new(1, 500_000_000).as_secs_f32() == f32(1.5)
	assert math.is_inf(f64(std_time.duration_max.as_secs_f32()), 0) == false
	first := elapsed_since_start()
	second := elapsed_since_start()
	assert second >= first
}
