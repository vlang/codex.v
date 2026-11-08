module uuid

import crypto.rand
import time

// STUB: uuid::Uuid::parse_str accepts simple, hyphenated, braced, and URN UUIDs
// with case-insensitive hexadecimal digits; formatting remains canonical lowercase.
pub fn Uuid.parse_str(value &string) !Uuid {
	mut start := 0
	mut end := value.len
	if value.len == 45 && value.starts_with('urn:uuid:') {
		start = 9
	} else if value.len == 38 && (*value)[0] == `{` && (*value)[37] == `}` {
		start = 1
		end = 37
	}
	length := end - start
	if length !in [32, 36] {
		return error('invalid UUID `${*value}`')
	}
	mut bytes := [16]u8{}
	mut digit_index := 0
	for offset in 0 .. length {
		character := (*value)[start + offset]
		if length == 36 && offset in [8, 13, 18, 23] {
			if character != `-` {
				return error('invalid UUID `${*value}`')
			}
			continue
		}
		digit := if character >= `0` && character <= `9` {
			character - `0`
		} else if character >= `a` && character <= `f` {
			character - `a` + 10
		} else if character >= `A` && character <= `F` {
			character - `A` + 10
		} else {
			return error('invalid UUID `${*value}`')
		}
		if digit_index % 2 == 0 {
			bytes[digit_index / 2] = digit << 4
		} else {
			bytes[digit_index / 2] |= digit
		}
		digit_index++
	}
	return Uuid{ bytes: bytes }
}

// STUB: uuid::Uuid::now_v7 fills the timestamp/version/variant fields with current
// milliseconds and OS entropy. The native uuid crate's monotonic context is absent.
pub fn Uuid.now_v7() Uuid {
	random := rand.bytes(16) or { panic('could not obtain UUID randomness: ${err}') }
	mut bytes := [16]u8{}
	for index in 0 .. 16 {
		bytes[index] = random[index]
	}
	timestamp := u64(time.now().unix_milli())
	for index in 0 .. 6 {
		bytes[index] = u8(timestamp >> (8 * (5 - index)))
	}
	bytes[6] = (bytes[6] & 0x0f) | 0x70
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	return Uuid{ bytes: bytes }
}
