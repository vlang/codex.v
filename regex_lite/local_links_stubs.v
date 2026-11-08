module regex_lite

// STUB: regex_lite::Regex supports only the two exact location patterns used by
// tui/src/markdown_render/local_links.rs. Other expressions fail explicitly.
// regex-lite's Perl digit class is ASCII, and both patterns anchor at input end.
pub struct Regex {
	kind LocationPattern
}

// STUB: Internal compiled alternatives for the untranslated regex-lite engine.
enum LocationPattern {
	colon
	hash
}

// STUB: regex_lite::Regex::new validates the requested source expressions.
pub fn Regex.new(pattern &string) !Regex {
	return match *pattern {
		r':\d+(?::\d+)?(?:[-–]\d+(?::\d+)?)?$' { Regex{ kind: .colon } }
		r'^L\d+(?:C\d+)?(?:-L\d+(?:C\d+)?)?$' { Regex{ kind: .hash } }
		else { error('unsupported regex-lite expression') }
	}
}

// STUB: regex_lite::Match is a Copy-equivalent borrowed haystack and byte range.
pub struct Match {
	text         &string
	start_offset int
	end_offset   int
}

// STUB: regex_lite::Match::end returns the matched exclusive byte offset.
pub fn (matched &Match) end() int {
	return matched.end_offset
}

// STUB: Match::as_str cannot return a V borrowed string slice. The owned string
// copies just the matched borrowed bytes at the source's later to_string boundary.
pub fn (matched &Match) as_str() string {
	return (*matched.text)[matched.start_offset..matched.end_offset].clone()
}

// STUB: regex_lite::Regex::is_match preserves the observed boolean API.
pub fn (regex &Regex) is_match(text &string) bool {
	regex.find(text) or { return false }
	return true
}

// STUB: regex_lite::Regex::find returns the first leftmost matching byte range.
pub fn (regex &Regex) find(text &string) ?Match {
	if regex.kind == .hash {
		mut offset := location_hash_point_end(text, 0) or { return none }
		if offset < text.len && (*text)[offset] == `-` {
			offset = location_hash_point_end(text, offset + 1) or { return none }
		}
		return if offset == text.len { Match{ text: text, end_offset: offset } } else { none }
	}
	for start in 0 .. text.len {
		if (*text)[start] != `:` {
			continue
		}
		mut offset := location_digits_end(text, start + 1) or { continue }
		if offset < text.len && (*text)[offset] == `:` {
			offset = location_digits_end(text, offset + 1) or { continue }
		}
		if offset < text.len {
			if (*text)[offset] == `-` {
				offset++
			} else if (*text)[offset..].starts_with('–') {
				offset += '–'.len
			} else {
				continue
			}
			offset = location_digits_end(text, offset) or { continue }
			if offset < text.len && (*text)[offset] == `:` {
				offset = location_digits_end(text, offset + 1) or { continue }
			}
		}
		if offset == text.len {
			return Match{ text: text, start_offset: start, end_offset: offset }
		}
	}
	return none
}

// STUB: The two observed regex grammars require one or more ASCII digits.
fn location_digits_end(text &string, start int) ?int {
	mut offset := start
	for offset < text.len && (*text)[offset] >= `0` && (*text)[offset] <= `9` {
		offset++
	}
	return if offset > start { offset } else { none }
}

// STUB: The observed hash expression's L<digits>[C<digits>] point grammar.
fn location_hash_point_end(text &string, start int) ?int {
	if start >= text.len || (*text)[start] != `L` {
		return none
	}
	mut offset := location_digits_end(text, start + 1) or { return none }
	if offset < text.len && (*text)[offset] == `C` {
		offset = location_digits_end(text, offset + 1) or { return none }
	}
	return offset
}
