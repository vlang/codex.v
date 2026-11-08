module startup_replay

fn test_startup_replay_bounds_oversized_osc_without_exposing_its_payload() {
	mut input := 'typed\x1b]10;'.bytes()
	input << []u8{len: max_replayed_osc_bytes, init: `x`}
	input << '1\r'.bytes()
	assert startup_replay_input(&input) == input[..'typed'.len + max_replayed_osc_bytes]

	input << u8(0x07)
	input << 'suffix'.bytes()
	assert startup_replay_input(&input) == 'typedsuffix'.bytes()
	partial := 'typed\x1b]10;partial\x1b'.bytes()
	assert startup_replay_input(&partial) == partial
}

fn test_startup_replay_preserves_osc_looking_bracketed_paste() {
	mut input := 'prefix\x1b[200~\x1b]10;'.bytes()
	input << []u8{len: 2048, init: `x`}
	input << '\x1b[201~suffix'.bytes()
	assert startup_replay_input(&input) == input
}

fn test_startup_replay_omits_terminal_color_replies_interleaved_with_bracketed_paste() {
	input := 'prefix\x1b[200~hello\x1b]10;rgb:eeee/eeee/eeee\x07 \x1b]11;rgb:1111/1111/1111\x1b\\world\x1b[201~suffix'.bytes()
	assert startup_replay_input(&input) == 'prefix\x1b[200~hello world\x1b[201~suffix'.bytes()
	unfinished_paste := '\x1b[200~hello\x1b]10;rgb:eeee/eeee/eeee\x07 world'.bytes()
	assert startup_replay_input(&unfinished_paste) == '\x1b[200~hello world'.bytes()
	unrelated_osc := '\x1b[200~\x1b]52;preserve me\x07\x1b[201~'.bytes()
	assert startup_replay_input(&unrelated_osc) == unrelated_osc
	response_after_paste := '\x1b[200~\x1b]10;unfinished\x1b[201~suffix\x07'.bytes()
	assert startup_replay_input(&response_after_paste) == response_after_paste
}

fn test_repeated_borrow_preserves_heap_owned_paste_and_output_is_independent() {
	mut text := '\x1b[200~text\x1b]10;RGB:f/e/d\x07\x1b[201~suffix'
	$if ownership ? {
		text = text.to_owned()
	}
	input := text.bytes()
	mut first := startup_replay_input(&input)
	second := startup_replay_input(&input)
	assert first == second
	first[0] = `x`
	assert second[0] == 0x1b
	assert input == text.bytes()
	assert text.ends_with('suffix')
}

fn test_color_validation_and_first_terminator_preserve_pasted_text() {
	for payload in ['rgb:ff/80/00', 'rgba:f/e/d/1', '\u2003RGB:0/0/0\u0085', 'rgb:+f/e/d'] {
		input := '\x1b[200~left\x1b]10;${payload}\aright\x1b[201~'.bytes()
		assert startup_replay_input(&input) == '\x1b[200~leftright\x1b[201~'.bytes()
	}
	for payload in ['rgb:fffff/0/0', 'rgb:0/0', 'rgba:f/e/d/x', 'rgb:0/0/0/0', 'rgb:\xff/0/0'] {
		input := '\x1b[200~left\x1b]10;${payload}\aright\x1b[201~'.bytes()
		assert startup_replay_input(&input) == input
	}
}

fn test_empty_plain_input_and_completed_noncolor_osc_outside_paste() {
	empty := []u8{}
	assert startup_replay_input(&empty).len == 0
	plain := 'typed\r\x1b[A'.bytes()
	assert startup_replay_input(&plain) == plain
	completed := 'left\x1b]52;clipboard\x1b\\right'.bytes()
	assert startup_replay_input(&completed) == 'leftright'.bytes()
}

fn test_pasted_color_reply_must_finish_within_replay_bound() {
	// The same valid response is filtered at the limit, then retained when its
	// terminator moves one byte beyond it. This preserves incomplete paste framing.
	for length in [max_replayed_osc_bytes, max_replayed_osc_bytes + 1] {
		mut response := '\x1b]10;'.bytes()
		response << []u8{len: length - '\x1b]10;rgb:0/0/0\x07'.len, init: ` `}
		response << 'rgb:0/0/0\x07'.bytes()
		mut input := '\x1b[200~'.bytes()
		input << response
		input << '\x1b[201~'.bytes()
		if length == max_replayed_osc_bytes {
			assert startup_replay_input(&input) == '\x1b[200~\x1b[201~'.bytes()
		} else {
			assert startup_replay_input(&input) == input
		}
	}
}
