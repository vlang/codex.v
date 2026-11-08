module unicode_width

// STUB: UnicodeWidthStr::width. Unicode 16.0.0, ambiguous characters narrow;
// scans backwards to preserve ligatures, emoji selectors, modifiers, tags and ZWJ sequences.
pub fn width(text &string) usize {
	runes := text.runes()
	mut sum := usize(0)
	mut state := u32(0)
	for i := runes.len - 1; i >= 0; i-- {
		add, info := width_in_str(runes[i], state)
		if add < 0 {
			sum -= usize(-add)
		} else {
			sum += usize(add)
		}
		state = info
	}
	return sum
}

// STUB: UnicodeWidthChar::width, preserving the optional width for control scalars.
pub fn char_width(value rune) ?usize {
	if value < 0x20 || (value >= 0x7f && value < 0xa0) {
		return none
	}
	return usize((lookup(value) >> 16) & 15)
}

// STUB: unicode-width's generated lookup-width and predicate tables, packed locally.
fn lookup(value rune) u32 {
	mut lo := 0
	mut hi := width_ranges.len / 20
	for lo < hi {
		mid := lo + (hi - lo) / 2
		start := mid * 20
		lower := hex_value(start, 6)
		upper := hex_value(start + 6, 6)
		if u32(value) < lower {
			hi = mid
		} else if u32(value) > upper {
			lo = mid + 1
		} else {
			return hex_value(start + 12, 8)
		}
	}
	return 1 << 16
}

// STUB: generated property-record hexadecimal decoding.
fn hex_value(start int, count int) u32 {
	mut result := u32(0)
	for i in start .. start + count {
		ch := width_ranges[i]
		result = result << 4 | u32(if ch <= `9` { ch - `0` } else { ch - `a` + 10 })
	}
	return result
}

// STUB: unicode-width::tables::WidthInfo::is_ligature_transparent.
fn ligature_transparent(state u32) bool {
	return state & 0x800 == 0x800
}

// STUB: unicode-width::tables::WidthInfo::set_emoji_presentation.
fn set_emoji(state u32) u32 {
	return if state & 0x2000 == 0x2000 || state & 0x9000 == 0x1000 {
		state | (0x8000 & ~u32(0x4000) & ~u32(0x200))
	} else {
		0x8000
	}
}

// STUB: unicode-width::tables::WidthInfo::set_text_presentation.
fn set_text(state u32) u32 {
	return if state & 0x2000 == 0x2000 {
		state | (0x4000 & ~u32(0x8000) & ~u32(0x200))
	} else {
		0x4000
	}
}

// STUB: unicode-width::tables::WidthInfo::set_vs1_2.
fn set_vs1_2(state u32) u32 {
	return if state & 0x2000 == 0x2000 {
		state | (0x200 & ~u32(0x4000) & ~u32(0x8000))
	} else {
		0x200
	}
}

// STUB: unicode-width::tables::is_ligature_transparent for non-Arabic ligatures.
fn is_ligature_transparent(value rune) bool {
	return value in [rune(0x34f), 0x17b4, 0x17b5, 0x180b, 0x180c, 0x180d, 0x180f, 0x200d]
		|| (value >= 0xfe00 && value <= 0xfe0f) || (value >= 0xe0100 && value <= 0xe01ef)
}

// STUB: unicode-width::tables::width_in_str, the complete non-CJK state transition.
fn width_in_str(value rune, next_info u32) (int, u32) {
	mut state := next_info
	data := lookup(value)
	if state & 0x8000 == 0x8000 {
		if data & (1 << 20) != 0 {
			return if state & 0xb000 == 0x9000 { 0 } else { 2 }, emoji_presentation
		}
		state = if state & 0x2000 == 0x2000 { state & ~u32(0x8000) } else { 0 }
	}
	if value <= 0xa0 {
		if value == `\n` {
			return 1, line_feed
		}
		if value == `\r` && state == line_feed {
			return 0, default
		}
		return 1, default
	}
	if state != default {
		if value == 0xfe0f {
			return 0, set_emoji(state)
		}
		if value == 0xfe01 {
			return 0, set_vs1_2(state)
		}
		if value == 0xfe0e {
			return 0, set_text(state)
		}
		if state & 0x4000 == 0x4000 {
			if data & (1 << 21) != 0 {
				return 1, default
			}
			state &= ~u32(0x4000)
		} else if state & 0x200 == 0x200 {
			if value in [rune(0x2018), 0x2019, 0x201c, 0x201d] {
				return 2, default
			}
			state &= ~u32(0x200)
		}
		if ligature_transparent(state) {
			if value == 0x200d {
				return 0, state | 0x400
			}
			if is_ligature_transparent(value) {
				return 0, state
			}
		}
		// Arabic Lam-Alef ligature.
		if state == joining_group_alef {
			if value in [rune(0x644), 0x76a, 0x8a6, 0x8c7] || (value >= 0x6b5 && value <= 0x6b8) {
				return 0, default
			}
			if data & (1 << 23) != 0 {
				return 0, joining_group_alef
			}
		}
		// Hebrew Alef-ZWJ-Lamed ligature.
		if state == zwj_hebrew_letter_lamed && value == 0x5d0 {
			return 0, default
		}
		// Khmer coeng signs.
		if state == khmer_coeng_eligible_letter && value == 0x17d2 {
			return -1, default
		}
		// Buginese <a, -i> ZWJ ya ligature.
		if state == zwj_buginese_letter_ya && value == 0x1a17 {
			return 0, buginese_vowel_sign_i_zwj_letter_ya
		}
		if state == buginese_vowel_sign_i_zwj_letter_ya && value == 0x1a15 {
			return 0, default
		}
		// Tifinagh bi-consonants.
		if state in [tifinagh_consonant, zwj_tifinagh_consonant] && value == 0x2d7f {
			return 1, tifinagh_joiner_consonant
		}
		if (value >= 0x2d31 && value <= 0x2d65) || value == 0x2d6f {
			if state == zwj_tifinagh_consonant {
				return 0, default
			}
			if state == tifinagh_joiner_consonant {
				return -1, default
			}
		}
		// Lisu tone letter combinations.
		if state == lisu_tone_letter_mya_na_jeu && value >= 0xa4f8 && value <= 0xa4fb {
			return 0, default
		}
		// Old Turkic ligature.
		if state == zwj_old_turkic_letter_orkhon_i && value == 0x10c32 {
			return 0, default
		}
		// Emoji modifier.
		if state == emoji_modifier && data & (1 << 22) != 0 {
			return 0, emoji_presentation
		}
		is_regional := value >= 0x1f1e6 && value <= 0x1f1ff
		// Regional indicator.
		if state in [regional_indicator, several_regional_indicator] && is_regional {
			return 1, several_regional_indicator
		}
		// ZWJ emoji.
		if state in [emoji_presentation, several_regional_indicator,
			even_regional_indicator_zwj_presentation, odd_regional_indicator_zwj_presentation,
			emoji_modifier] && value == 0x200d {
			return 0, zwj_emoji_presentation
		}
		if state == zwj_emoji_presentation && value == 0x20e3 {
			return 0, keycap_zwj_emoji_presentation
		}
		if state == vs16_zwj_emoji_presentation && data & (1 << 20) != 0 {
			return 0, emoji_presentation
		}
		if state == vs16_keycap_zwj_emoji_presentation && (value in [`#`, `*`] || (value >= `0` && value <= `9`)) {
			return 0, emoji_presentation
		}
		if state == zwj_emoji_presentation && is_regional {
			return 1, regional_indicator_zwj_presentation
		}
		if state in [regional_indicator_zwj_presentation, odd_regional_indicator_zwj_presentation] && is_regional {
			return -1, even_regional_indicator_zwj_presentation
		}
		if state == even_regional_indicator_zwj_presentation && is_regional {
			return 3, odd_regional_indicator_zwj_presentation
		}
		if state == zwj_emoji_presentation && value >= 0x1f3fb && value <= 0x1f3ff {
			return 0, emoji_modifier
		}
		if state == zwj_emoji_presentation && value == 0xe007f {
			return 0, tag_end_zwj_emoji_presentation
		}
		if value >= 0xe0061 && value <= 0xe007a {
			if state == tag_end_zwj_emoji_presentation {
				return 0, tag_a1_end_zwj_emoji_presentation
			}
			if state >= tag_a1_end_zwj_emoji_presentation && state < tag_a6_end_zwj_emoji_presentation {
				return 0, state + 1
			}
		}
		if value >= 0xe0030 && value <= 0xe0039 {
			if state in [tag_end_zwj_emoji_presentation, tag_a1_end_zwj_emoji_presentation,
				tag_a2_end_zwj_emoji_presentation, tag_a3_end_zwj_emoji_presentation,
				tag_a4_end_zwj_emoji_presentation] {
				return 0, tag_d1_end_zwj_emoji_presentation
			}
			if state in [tag_d1_end_zwj_emoji_presentation, tag_d2_end_zwj_emoji_presentation] {
				return 0, state + 1
			}
		}
		if state in [tag_a3_end_zwj_emoji_presentation, tag_a4_end_zwj_emoji_presentation,
			tag_a5_end_zwj_emoji_presentation, tag_a6_end_zwj_emoji_presentation,
			tag_d3_end_zwj_emoji_presentation] && value == 0x1f3f4 {
			return 0, emoji_presentation
		}
		if state == zwj_emoji_presentation && data & 0xffff == emoji_presentation {
			return 0, emoji_presentation
		}
		if state == kirat_rai_vowel_sign_e {
			if value in [rune(0x16d63), 0x16d69] {
				return 0, default
			}
			if value == 0x16d67 {
				return 0, kirat_rai_vowel_sign_ai
			}
			if value == 0x16d68 {
				return 1, kirat_rai_vowel_sign_e
			}
		}
		if state == kirat_rai_vowel_sign_ai && value == 0x16d63 {
			return 0, default
		}
	}
	return int((data >> 16) & 15), data & 0xffff
}

// This boundary implements the UnicodeWidthStr::width non-CJK API consumed by
// text_formatting; CJK APIs and the upstream table generator remain untranslated.

// STUB: unicode-width 0.2.1 reverse-scanning width state.
const default = u32(0)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const line_feed = u32(0b0000000000000001)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const emoji_modifier = u32(0b0000000000000010)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const regional_indicator = u32(0b0000000000000011)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const several_regional_indicator = u32(0b0000000000000100)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const emoji_presentation = u32(0b0000000000000101)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const zwj_emoji_presentation = u32(0b0001000000000110)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const vs16_zwj_emoji_presentation = u32(0b1001000000000110)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const keycap_zwj_emoji_presentation = u32(0b0001000000000111)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const vs16_keycap_zwj_emoji_presentation = u32(0b1001000000000111)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const regional_indicator_zwj_presentation = u32(0b0000000000001001)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const even_regional_indicator_zwj_presentation = u32(0b0000000000001010)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const odd_regional_indicator_zwj_presentation = u32(0b0000000000001011)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const tag_end_zwj_emoji_presentation = u32(0b0000000000010000)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const tag_d1_end_zwj_emoji_presentation = u32(0b0000000000010001)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const tag_d2_end_zwj_emoji_presentation = u32(0b0000000000010010)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const tag_d3_end_zwj_emoji_presentation = u32(0b0000000000010011)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const tag_a1_end_zwj_emoji_presentation = u32(0b0000000000011001)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const tag_a2_end_zwj_emoji_presentation = u32(0b0000000000011010)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const tag_a3_end_zwj_emoji_presentation = u32(0b0000000000011011)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const tag_a4_end_zwj_emoji_presentation = u32(0b0000000000011100)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const tag_a5_end_zwj_emoji_presentation = u32(0b0000000000011101)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const tag_a6_end_zwj_emoji_presentation = u32(0b0000000000011110)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const kirat_rai_vowel_sign_e = u32(0b0000000000100000)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const kirat_rai_vowel_sign_ai = u32(0b0000000000100001)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const variation_selector_1_or_2 = u32(0b0000001000000000)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const variation_selector_15 = u32(0b0100000000000000)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const variation_selector_16 = u32(0b1000000000000000)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const joining_group_alef = u32(0b0011000011111111)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const hebrew_letter_lamed = u32(0b0011100000000000)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const zwj_hebrew_letter_lamed = u32(0b0011110000000000)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const buginese_letter_ya = u32(0b0011100000000001)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const zwj_buginese_letter_ya = u32(0b0011110000000001)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const buginese_vowel_sign_i_zwj_letter_ya = u32(0b0011110000000010)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const tifinagh_consonant = u32(0b0011100000000011)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const zwj_tifinagh_consonant = u32(0b0011110000000011)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const tifinagh_joiner_consonant = u32(0b0011110000000100)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const lisu_tone_letter_mya_na_jeu = u32(0b0011110000000101)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const old_turkic_letter_orkhon_i = u32(0b0011100000000110)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const zwj_old_turkic_letter_orkhon_i = u32(0b0011110000000110)
// STUB: unicode-width 0.2.1 reverse-scanning width state.
const khmer_coeng_eligible_letter = u32(0b0011110000000111)
