module windows_replay

import codex_tui.color
import codex_tui.terminal_probe
import std_ops

fn preserved_input(input &[]u8) []u8 {
	ranges := terminal_color_response_ranges(input)
	mut preserved := []u8{}
	for index, byte in *input {
		mut within_response := false
		for response_range in ranges {
			if usize(index) >= response_range.start && usize(index) < response_range.end {
				within_response = true
				break
			}
		}
		if !within_response {
			preserved << byte
		}
	}
	return preserved
}

fn test_preserves_typeahead_before_between_and_after_terminal_color_replies() {
	input := 'before\x1b]10;rgb:5555/5757/5353\x1b\\between\x1b]11;rgb:ffff/ffff/ffff\x07after'.bytes()
	assert preserved_input(&input) == 'beforebetweenafter'.bytes()
}

fn test_preserves_unrelated_malformed_and_partial_osc_sequences() {
	input := '\x1b]52;clipboard\x07\x1b]10;not-a-color\x07typed\x1b]11;rgb:ffff/ffff'.bytes()
	assert preserved_input(&input) == input
}

fn test_preserves_terminal_color_response_that_exceeds_the_byte_limit() {
	mut input := 'prefix\x1b]10;'.bytes()
	input << []u8{len: max_terminal_color_response_bytes, init: `x`}
	input << '\x07suffix'.bytes()
	assert preserved_input(&input) == input
}

fn test_finds_terminal_color_replies_after_unrelated_escape_sequences() {
	input := '\x1b]52;clipboard\x07typed\x1b]11;rgba:ffff/eeee/dddd/ffff\x1b\\suffix'.bytes()
	assert preserved_input(&input) == '\x1b]52;clipboard\x07typedsuffix'.bytes()
}

fn test_consumes_one_and_three_digit_terminal_color_replies() {
	input := 'before\x1b]10;rgb:f/e/d\x07middle\x1b]11;rgb:fff/800/000\x1b\\after'.bytes()
	assert preserved_input(&input) == 'beforemiddleafter'.bytes()
	assert terminal_default_colors(&input) or { panic('expected default colors') } == terminal_probe.DefaultColors{
		fg: color.Rgb{ r: 255, g: 238, b: 221 }
		bg: color.Rgb{ r: 255, g: 127, b: 0 }
	}
}

fn test_preserves_complete_osc_looking_bracketed_paste() {
	input := 'before\x1b[200~\x1b]10;rgb:f/e/d\x07\x1b]11;rgb:fff/800/000\x07\x1b[201~after'.bytes()
	assert preserved_input(&input) == input
	assert terminal_default_colors(&input) == none
}

fn test_preserves_unfinished_osc_looking_bracketed_paste() {
	input := 'before\x1b[200~\x1b]10;rgb:f/e/d\x07\x1b]11;rgb:fff/800/000\x07'.bytes()
	assert preserved_input(&input) == input
	assert terminal_default_colors(&input) == none
}

fn test_parses_real_color_replies_around_bracketed_paste() {
	input := '\x1b]10;rgb:f/e/d\x07\x1b[200~\x1b]11;rgb:0/0/0\x07\x1b[201~\x1b]11;rgb:fff/800/000\x07'.bytes()
	assert preserved_input(&input) == '\x1b[200~\x1b]11;rgb:0/0/0\x07\x1b[201~'.bytes()
	assert terminal_default_colors(&input) or { panic('expected default colors') } == terminal_probe.DefaultColors{
		fg: color.Rgb{ r: 255, g: 238, b: 221 }
		bg: color.Rgb{ r: 255, g: 127, b: 0 }
	}
}

fn test_repeated_borrow_preserves_heap_owned_input_and_independent_ranges() {
	mut text := 'before\x1b]10;rgb:f/e/d\x07middle\x1b]11;rgb:fff/800/000\x1b\\after'
	$if ownership ? {
		text = text.to_owned()
	}
	input := text.bytes()
	mut first_ranges := terminal_color_response_ranges(&input)
	second_ranges := terminal_color_response_ranges(&input)
	assert first_ranges == second_ranges
	first_ranges[0].start = 0
	assert second_ranges[0].start == usize('before'.len)
	first_colors := terminal_default_colors(&input) or { panic('expected default colors') }
	second_colors := terminal_default_colors(&input) or { panic('expected default colors') }
	assert first_colors == second_colors
	assert input == text.bytes()
	assert text.ends_with('after')
}

fn test_terminal_color_response_limit_includes_terminator() {
	for response_length in [max_terminal_color_response_bytes, max_terminal_color_response_bytes + 1] {
		mut input := 'prefix\x1b]10;'.bytes()
		input << []u8{len: response_length - '\x1b]10;rgb:0/0/0\x07'.len, init: ` `}
		input << 'rgb:0/0/0\x07suffix'.bytes()
		if response_length == max_terminal_color_response_bytes {
			assert preserved_input(&input) == 'prefixsuffix'.bytes()
			assert terminal_color_response_ranges(&input) == [std_ops.Range[usize]{
				start: usize('prefix'.len)
				end:   usize('prefix'.len + max_terminal_color_response_bytes)
			}]
		} else {
			assert preserved_input(&input) == input
			assert terminal_color_response_ranges(&input).len == 0
		}
	}
}

fn test_first_valid_matching_colors_and_scan_after_invalid_responses() {
	input := '\x1b]10;bad\x07\x1b]11;rgb:0/0/0\x07\x1b]52;clipboard\x07\x1b]10;rgb:f/e/d\x07\x1b]10;rgb:0/0/0\x07\x1b]11;rgb:f/f/f\x07'.bytes()
	assert preserved_input(&input) == '\x1b]10;bad\x07\x1b]52;clipboard\x07'.bytes()
	assert terminal_default_colors(&input) or { panic('expected default colors') } == terminal_probe.DefaultColors{
		fg: color.Rgb{ r: 255, g: 238, b: 221 }
		bg: color.Rgb{ r: 0, g: 0, b: 0 }
	}
	foreground_only := '\x1b]10;rgb:f/e/d\x07'.bytes()
	background_only := '\x1b]11;rgb:f/e/d\x07'.bytes()
	assert terminal_default_colors(&foreground_only) == none
	assert terminal_default_colors(&background_only) == none
}
