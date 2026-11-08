module urlencoding

import encoding.utf8

// STUB: urlencoding::decode decodes percent escapes exactly once, leaves malformed
// escapes literal, preserves plus signs, and rejects decoded invalid UTF-8. V
// lacks Cow<str>; this result owns its bytes even when no decoding is necessary.
pub fn decode(text &string) !string {
	mut bytes := []u8{cap: text.len}
	mut offset := 0
	for offset < text.len {
		if (*text)[offset] == `%` && offset + 2 < text.len {
			high := local_links_hex((*text)[offset + 1])
			low := local_links_hex((*text)[offset + 2])
			if high >= 0 && low >= 0 {
				bytes << u8(high * 16 + low)
				offset += 3
				continue
			}
		}
		bytes << (*text)[offset]
		offset++
	}
	result := bytes.bytestr()
	if !utf8.validate_str(result) {
		return error('invalid UTF-8')
	}
	return result
}

// STUB: urlencoding's percent escape digit decoder for the observed decode API.
fn local_links_hex(value u8) int {
	if value >= `0` && value <= `9` {
		return int(value - `0`)
	}
	if value >= `a` && value <= `f` {
		return int(value - `a`) + 10
	}
	if value >= `A` && value <= `F` {
		return int(value - `A`) + 10
	}
	return -1
}
