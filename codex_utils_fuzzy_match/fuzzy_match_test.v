module codex_utils_fuzzy_match

fn test_ascii_basic_indices() {
	haystack := 'hello'
	needle := 'hl'
	matched := fuzzy_match(&haystack, &needle) or { panic('expected a match') }
	assert matched.indices == [0, 2]
	// 'h' at 0, 'l' at 2 -> window 1; start-of-string bonus applies (-100)
	assert matched.score == -99
}

fn test_unicode_dotted_i_istanbul_highlighting() {
	haystack := 'İstanbul'
	needle := 'is'
	matched := fuzzy_match(&haystack, &needle) or { panic('expected a match') }
	assert matched.indices == [0, 1]
	// Matches at lowered positions 0 and 2 -> window 1; start-of-string bonus applies
	assert matched.score == -99
}

fn test_unicode_german_sharp_s_casefold() {
	haystack := 'straße'
	needle := 'strasse'
	assert fuzzy_match(&haystack, &needle) == none
}

fn test_prefer_contiguous_match_over_spread() {
	contiguous := 'abc'
	spread := 'a-b-c'
	needle := 'abc'
	matched_a := fuzzy_match(&contiguous, &needle) or { panic('expected a match') }
	matched_b := fuzzy_match(&spread, &needle) or { panic('expected a match') }
	// Contiguous window -> 0; start-of-string bonus -> -100
	assert matched_a.score == -100
	// Spread over 5 chars for 3-letter needle -> window 2; with bonus -> -98
	assert matched_b.score == -98
	assert matched_a.score < matched_b.score
}

fn test_start_of_string_bonus_applies() {
	prefix := 'file_name'
	infix := 'my_file_name'
	needle := 'file'
	matched_a := fuzzy_match(&prefix, &needle) or { panic('expected a match') }
	matched_b := fuzzy_match(&infix, &needle) or { panic('expected a match') }
	// Start-of-string contiguous -> window 0; bonus -> -100
	assert matched_a.score == -100
	// Non-prefix contiguous -> window 0; no bonus -> 0
	assert matched_b.score == 0
	assert matched_a.score < matched_b.score
}

fn test_empty_needle_matches_with_max_score_and_no_indices() {
	haystack := 'anything'
	needle := ''
	matched := fuzzy_match(&haystack, &needle) or { panic('empty needle should match') }
	assert matched.indices.len == 0
	assert matched.score == 0x7fffffff
}

fn test_case_insensitive_matching_basic() {
	haystack := 'FooBar'
	needle := 'foO'
	matched := fuzzy_match(&haystack, &needle) or { panic('expected a match') }
	assert matched.indices == [0, 1, 2]
	// Contiguous prefix match (case-insensitive) -> window 0 with bonus
	assert matched.score == -100
}

fn test_indices_are_deduped_for_multichar_lowercase_expansion() {
	needle := 'i\u0307' // "i" + combining dot above
	haystack := 'İ'
	matched := fuzzy_match(&haystack, &needle) or { panic('expected a match') }
	assert matched.indices == [0]
	// Lowercasing 'İ' expands to two chars; contiguous prefix -> window 0 with bonus
	assert matched.score == -100
}

fn test_borrowed_fuzzy_match_inputs_remain_reusable() {
	mut haystack := 'İstanbul'
	mut needle := 'is'
	$if ownership ? {
		haystack = 'İstanbul'.to_owned()
		needle = 'is'.to_owned()
	}
	for _ in 0 .. 2 {
		matched := fuzzy_match(&haystack, &needle) or { panic('expected a match') }
		assert matched == FuzzyMatch{ indices: [0, 1], score: -99 }
		assert haystack == 'İstanbul'
		assert needle == 'is'
	}
	assert haystack == 'İstanbul'
	assert needle == 'is'
}

// Rust lowercases the haystack per char and the needle as a string, preserving Final_Sigma.
fn test_contextual_needle_sigma_matches_rust_lowercase_behavior() {
	haystack := 'ΟΣ'
	needle := 'ΟΣ'
	assert fuzzy_match(&haystack, &needle) == none
	lowercase_haystack := 'ος'
	matched := fuzzy_match(&lowercase_haystack, &needle) or { panic('final sigma should match') }
	assert matched == FuzzyMatch{ indices: [0, 1], score: -100 }
	interior_needle := 'ΟΣΑ'
	interior_haystack := 'ΟΣΑ'
	interior_match := fuzzy_match(&interior_haystack, &interior_needle) or {
		panic('interior sigma lowercases normally')
	}
	assert interior_match == FuzzyMatch{ indices: [0, 1, 2], score: -100 }
	with_ignorable := 'Ο\u0307Σ\u0307'
	assert lowercase_string(&with_ignorable).string() == 'ο\u0307ς\u0307'
	after_ignorable := 'ΟΣ\u0307Α'
	assert lowercase_string(&after_ignorable).string() == 'οσ\u0307α'
}

// These Rust Unicode 17 mappings are absent from older one-scalar Unicode tables.
fn test_unicode17_lowercase_mappings_and_original_character_positions() {
	haystack := 'x\uA7CB\U00010D50'
	needle := '\u0264\U00010D70'
	matched := fuzzy_match(&haystack, &needle) or { panic('Unicode 17 letters should match') }
	assert matched == FuzzyMatch{ indices: [1, 2], score: 0 }
}
