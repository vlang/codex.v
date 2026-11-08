module width

import codex_tui.line_truncation
import ratatui.text

fn test_display_width_matches_ratatui_halfwidth_sound_marks_without_overflow() {
	voiced_and_semi_voiced := 'ｶﾞﾊﾟ'
	repeated_sound_marks := 'ｶﾞﾞ'
	wide_with_sound_mark := '界ﾞ'
	assert display_width(&voiced_and_semi_voiced) == 4
	assert display_width(&repeated_sound_marks) == 3
	assert display_width(&wide_with_sound_mark) == 3
	assert char_width(rune(0xff9e)) == 1
	assert char_width(rune(0xff9f)) == 1

	long_text := 'a'.repeat(65_536)
	assert display_width(&long_text) == 65_536
	line := text.line_from(long_text)
	assert line_truncation.line_width(&line) == 65_536
}

fn test_usable_content_width_returns_none_when_reserved_exhausts_width() {
	assert usable_content_width( /* total_width */
	0, /* reserved_cols */
		0) == none
	assert usable_content_width( /* total_width */
	2, /* reserved_cols */
		2) == none
	assert usable_content_width( /* total_width */
	3, /* reserved_cols */
		4) == none
	assert usable_content_width( /* total_width */
	5, /* reserved_cols */
		4)? == 1
}

fn test_usable_content_width_u16_matches_usize_variant() {
	assert usable_content_width_u16( /* total_width */
	2, /* reserved_cols */
		2) == none
	assert usable_content_width_u16( /* total_width */
	5, /* reserved_cols */
		4)? == 1
}

fn test_display_width_borrows_owned_string_repeatedly() {
	owner := $if ownership ? {
		'ｶﾞ界👩‍💻'.to_owned()
	} $else {
		'ｶﾞ界👩‍💻'.clone()
	}
	assert display_width(&owner) == 6
	assert display_width(&owner) == 6
	assert owner == 'ｶﾞ界👩‍💻'
}
