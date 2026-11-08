module text_formatting

import os
import codex_tui.width

struct StringLike {
	text string
}

fn (item &StringLike) as_ref() &string {
	return &item.text
}

fn test_proper_join_accepts_borrowed_as_ref_strings() {
	mut items := [StringLike{ text: 'apple' }, StringLike{ text: 'banana' },
		StringLike{ text: 'cherry' }]
	$if ownership ? {
		items = [StringLike{ text: 'apple'.to_owned() }, StringLike{ text: 'banana'.to_owned() },
			StringLike{ text: 'cherry'.to_owned() }]
	}
	assert proper_join(&items) == 'apple, banana and cherry'
	assert proper_join(&items) == 'apple, banana and cherry'
	assert items[0].text == 'apple'
	assert items[2].text == 'cherry'
}

fn test_truncate_text() {
	text := 'Hello, world!'
	truncated := truncate_text(&text, /* max_graphemes */
		8)
	assert truncated == 'Hello...'
}

fn test_truncate_empty_string() {
	text := ''
	truncated := truncate_text(&text, /* max_graphemes */
		5)
	assert truncated == ''
}

fn test_truncate_max_graphemes_zero() {
	text := 'Hello'
	truncated := truncate_text(&text, /* max_graphemes */
		0)
	assert truncated == ''
}

fn test_truncate_max_graphemes_one() {
	text := 'Hello'
	truncated := truncate_text(&text, /* max_graphemes */
		1)
	assert truncated == 'H'
}

fn test_truncate_max_graphemes_two() {
	text := 'Hello'
	truncated := truncate_text(&text, /* max_graphemes */
		2)
	assert truncated == 'He'
}

fn test_truncate_max_graphemes_three_boundary() {
	text := 'Hello'
	truncated := truncate_text(&text, /* max_graphemes */
		3)
	assert truncated == '...'
}

fn test_truncate_text_shorter_than_limit() {
	text := 'Hi'
	truncated := truncate_text(&text, /* max_graphemes */
		10)
	assert truncated == 'Hi'
}

fn test_truncate_text_exact_length() {
	text := 'Hello'
	truncated := truncate_text(&text, /* max_graphemes */
		5)
	assert truncated == 'Hello'
}

fn test_truncate_emoji() {
	text := '👋🌍🚀✨💫'
	truncated := truncate_text(&text, /* max_graphemes */
		3)
	assert truncated == '...'
	truncated_longer := truncate_text(&text, /* max_graphemes */
		4)
	assert truncated_longer == '👋...'
}

fn test_truncate_unicode_combining_characters() {
	text := 'é́ñ̃' // Characters with combining marks
	truncated := truncate_text(&text, /* max_graphemes */
		2)
	assert truncated == 'é́ñ̃'
}

fn test_truncate_very_long_text() {
	text := 'a'.repeat(1000)
	truncated := truncate_text(&text, /* max_graphemes */
		10)
	assert truncated == 'aaaaaaa...'
	assert truncated.len == 10 // 7 'a's + 3 dots
}

fn test_format_json_compact_simple_object() {
	json := '{ "name": "John", "age": 30 }'
	result := format_json_compact(&json) or { panic('expected JSON') }
	assert result == '{"name": "John", "age": 30}'
}

fn test_format_json_compact_nested_object() {
	json := '{ "user": { "name": "John", "details": { "age": 30, "city": "NYC" } } }'
	result := format_json_compact(&json) or { panic('expected JSON') }
	assert result == '{"user": {"name": "John", "details": {"age": 30, "city": "NYC"}}}'
}

fn test_center_truncate_doesnt_truncate_short_path() {
	sep := os.path_separator
	path := '${sep}Users${sep}codex${sep}Public'
	truncated := center_truncate_path(&path, /* max_width */
		40)
	assert truncated == path
}

fn test_center_truncate_truncates_long_path() {
	sep := os.path_separator
	path := '~${sep}hello${sep}the${sep}fox${sep}is${sep}very${sep}fast'
	truncated := center_truncate_path(&path, /* max_width */
		24)
	assert truncated == '~${sep}hello${sep}the${sep}…${sep}very${sep}fast'
}

fn test_center_truncate_truncates_long_windows_path() {
	sep := os.path_separator
	path := 'C:${sep}Users${sep}codex${sep}Projects${sep}super${sep}long${sep}windows${sep}path${sep}file.txt'
	truncated := center_truncate_path(&path, /* max_width */
		36)
	expected := 'C:${sep}Users${sep}codex${sep}…${sep}path${sep}file.txt'
	assert truncated == expected
}

fn test_center_truncate_handles_long_segment() {
	sep := os.path_separator
	path := '~${sep}supercalifragilisticexpialidocious'
	truncated := center_truncate_path(&path, /* max_width */
		18)
	assert truncated == '~${sep}…cexpialidocious'
}

fn test_format_json_compact_array() {
	json := '[ 1, 2, { "key": "value" }, "string" ]'
	result := format_json_compact(&json) or { panic('expected JSON') }
	assert result == '[1, 2, {"key": "value"}, "string"]'
}

fn test_format_json_compact_already_compact() {
	json := '{"compact":true}'
	result := format_json_compact(&json) or { panic('expected JSON') }
	assert result == '{"compact": true}'
}

fn test_format_json_compact_with_whitespace() {
	json := '
        {
            "name": "John",
            "hobbies": [
                "reading",
                "coding"
            ]
        }
        '
	result := format_json_compact(&json) or { panic('expected JSON') }
	assert result == '{"name": "John", "hobbies": ["reading", "coding"]}'
}

fn test_format_json_compact_invalid_json() {
	invalid_json := '{"invalid": json syntax}'
	result := format_json_compact(&invalid_json)
	assert result == none
}

fn test_format_json_compact_empty_object() {
	json := '{}'
	result := format_json_compact(&json) or { panic('expected JSON') }
	assert result == '{}'
}

fn test_format_json_compact_empty_array() {
	json := '[]'
	result := format_json_compact(&json) or { panic('expected JSON') }
	assert result == '[]'
}

fn test_format_json_compact_primitive_values() {
	literal_1 := '42'
	assert format_json_compact(&literal_1)? == '42'
	literal_2 := 'true'
	assert format_json_compact(&literal_2)? == 'true'
	literal_3 := 'false'
	assert format_json_compact(&literal_3)? == 'false'
	literal_4 := 'null'
	assert format_json_compact(&literal_4)? == 'null'
	literal_5 := '"string"'
	assert format_json_compact(&literal_5)? == '"string"'
}

fn test_proper_join() {
	empty := []string{}
	assert proper_join(&empty) == ''
	assert proper_join(&['apple']) == 'apple'
	assert proper_join(&['apple', 'banana']) == 'apple and banana'
	assert proper_join(&['apple', 'banana', 'cherry']) == 'apple, banana and cherry'
	assert proper_join(&['apple', 'banana', 'cherry', 'date']) == 'apple, banana, cherry and date'
}

fn test_borrowed_formatting_owners_remain_reusable() {
	mut text := 'ßeta'
	mut path := '/界/👩‍👩‍👧‍👦/very_long_name.txt'
	mut json := '{"a":"quote \\" and \\\\","b":2}'
	mut items := ['apple', 'banana', 'cherry']
	$if ownership ? {
		text = 'ßeta'.to_owned()
		path = '/界/👩‍👩‍👧‍👦/very_long_name.txt'.to_owned()
		json = '{"a":"quote \\" and \\\\","b":2}'.to_owned()
		items = ['apple'.to_owned(), 'banana'.to_owned(), 'cherry'.to_owned()]
	}
	assert capitalize_first(&text) == 'SSeta'
	assert capitalize_first(&text) == 'SSeta'
	assert text == 'ßeta'
	assert center_truncate_path(&path, 12) == center_truncate_path(&path, 12)
	assert path == '/界/👩‍👩‍👧‍👦/very_long_name.txt'
	assert format_json_compact(&json)? == format_json_compact(&json)?
	assert format_and_truncate_tool_result(&json, 2, 12) == format_and_truncate_tool_result(&json, 2, 12)
	assert json == '{"a":"quote \\" and \\\\","b":2}'
	assert proper_join(&items) == proper_join(&items)
	assert items == ['apple', 'banana', 'cherry']
	assert truncate_text(&text, 1) == 'ß'
	assert truncate_text(&text, 2) == 'ße'
	assert text == 'ßeta'
}

fn test_unicode_extended_clusters_and_case_expansions() {
	literal_6 := 'ﬃle'
	assert capitalize_first(&literal_6) == 'FFIle'
	literal_7 := ''
	assert capitalize_first(&literal_7) == ''
	literal_8 := '👩‍👩‍👧‍👦xy'
	assert truncate_text(&literal_8, 1) == '👩‍👩‍👧‍👦'
	literal_9 := '🇺🇸🇬🇧x'
	assert truncate_text(&literal_9, 1) == '🇺🇸'
	literal_10 := 'क्‍षxy'
	assert truncate_text(&literal_10, 1) == 'क्‍ष'
	literal_11 := '\r\nxy'
	assert truncate_text(&literal_11, 1) == '\r\n'
	// U+1E4EC is a Unicode 15 combining mark, absent from the compiler's Unicode 13 tables.
	literal_12 := 'a\U0001e4ecxy'
	assert truncate_text(&literal_12, 1) == 'a\U0001e4ec'
}

fn test_path_truncation_uses_unicode_cell_width() {
	literal_13 := '👩‍👩‍👧‍👦'
	assert width.display_width(&literal_13) == 2
	literal_14 := '界ﾞ'
	assert width.display_width(&literal_14) == 3
	literal_15 := 'ｶﾞﾊﾟ'
	assert width.display_width(&literal_15) == 4
	literal_16 := '界界界'
	assert center_truncate_path(&literal_16, 4) == '…界'
	literal_17 := 'abc'
	assert center_truncate_path(&literal_17, 0) == ''
	literal_18 := 'abc'
	assert center_truncate_path(&literal_18, 1) == '…'
	literal_19 := '/👩‍👩‍👧‍👦/abc'
	assert center_truncate_path(&literal_19, 6) == '/👩‍👩‍👧‍👦/…c'
}

fn test_tool_result_formats_then_truncates_with_saturating_budget() {
	literal_20 := '{"a":1}'
	assert format_and_truncate_tool_result(&literal_20, 1, 10) == '{"a": 1}'
	literal_21 := 'abcdef'
	assert format_and_truncate_tool_result(&literal_21, 1, 6) == 'ab...'
	literal_22 := 'abcdef'
	assert format_and_truncate_tool_result(&literal_22, 2, 0) == ''
}

fn test_json_compaction_preserves_escapes_order_numbers_and_validation() {
	literal_23 := '{"z":1,"a":2,"z":3}'
	assert format_json_compact(&literal_23)? == '{"z": 3, "a": 2}'
	literal_24 := '[18446744073709551615,-9223372036854775808,1.0,-0]'
	assert format_json_compact(&literal_24)? == '[18446744073709551615, -9223372036854775808, 1.0, -0.0]'
	literal_25 := '{"s":"\\uD83D\\uDE80"}'
	assert format_json_compact(&literal_25)? == '{"s": "🚀"}'
	literal_26 := '[01]'
	assert format_json_compact(&literal_26) == none
	literal_27 := '[1,]'
	assert format_json_compact(&literal_27) == none
	literal_28 := '"\\uD800"'
	assert format_json_compact(&literal_28) == none
	literal_29 := '1e400'
	assert format_json_compact(&literal_29) == none
}

fn test_json_float_rounding_matches_source_parser() {
	// serde_json's default parser uses a u64 mantissa and decimal division, so these
	// values intentionally differ from correctly rounded atof64 parsing.
	decimal := '-1.1317271002667658e+72'
	assert format_json_compact(&decimal)? == '-1.131727100266766e+72'
	underflow := '1e-400'
	assert format_json_compact(&underflow)? == '0.0'
	integer_overflow := '18446744073709551616'
	assert format_json_compact(&integer_overflow)? == '1.8446744073709552e+19'
}
