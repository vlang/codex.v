module chrono

import time

// STUB: chrono::DateTime::<Utc>::UNIX_EPOCH is a Copy instant.
pub fn DateTimeUtc.unix_epoch() DateTimeUtc {
	return DateTimeUtc{}
}

// STUB: chrono's serde UTC timestamp decoder, including its relaxed FromStr
// syntax, offset conversion, extended years, and retained leap-second nanos.
// Other chrono parser/format/calendar APIs remain untranslated.
pub fn DateTimeUtc.from_serde_string(source &string) !DateTimeUtc {
	mut parser := TimestampParser{ source: source }
	parser.space()
	mut sign := 1
	mut year_width := 4
	if parser.peek() in [`+`, `-`] {
		if parser.peek() == `-` {
			sign = -1
		}
		parser.position++
		year_width = source.len
	}
	year := parser.number(year_width, false)! * sign
	parser.space()
	parser.literal(`-`)!
	month := parser.number(2, true)!
	parser.space()
	parser.literal(`-`)!
	day := parser.number(2, true)!
	if parser.peek() !in [`T`, `t`, ` `] {
		return error('invalid timestamp separator')
	}
	parser.position++
	hour := parser.number(2, true)!
	parser.space()
	parser.literal(`:`)!
	minute := parser.number(2, true)!
	parser.space()
	parser.literal(`:`)!
	second := parser.number(2, true)!
	mut nanos := u32(0)
	if parser.peek() == `.` {
		parser.position++
		start := parser.position
		mut count := 0
		for parser.peek() >= `0` && parser.peek() <= `9` {
			if count < 9 {
				nanos = nanos * 10 + u32(parser.peek() - `0`)
			}
			count++
			parser.position++
		}
		if parser.position == start {
			return error('empty timestamp fraction')
		}
		for _ in count .. 9 {
			nanos *= 10
		}
	}
	parser.space()
	mut offset := 0
	utc_token := 'UTC'
	minus_token := '−'
	if parser.peek() in [`Z`, `z`] {
		parser.position++
	} else if parser.matches_ascii(&utc_token) {
		parser.position += 3
	} else {
		mut offset_sign := 1
		if parser.peek() == `-` {
			offset_sign = -1
			parser.position++
		} else if parser.peek() == `+` {
			parser.position++
		} else if parser.matches(&minus_token) {
			offset_sign = -1
			parser.position += 3
		} else {
			return error('missing timestamp offset')
		}
		offset_hour := parser.fixed_pair()!
		for {
			old := parser.position
			parser.space()
			if parser.peek() == `:` { parser.position++ }
			if parser.position == old {
				break
			}
		}
		offset_minute := parser.fixed_pair()!
		if offset_hour > 23 || offset_minute > 59 {
			return error('timestamp offset out of range')
		}
		offset = offset_sign * (offset_hour * 3600 + offset_minute * 60)
	}
	parser.space()
	if parser.position != source.len {
		return error('trailing timestamp characters')
	}
	if year < -262143 || year > 262142 || month < 1 || month > 12
		|| hour > 23 || minute > 59 || second > 60 {
		return error('timestamp component out of range')
	}
	month_days := time.days_in_month(month, year)!
	if day < 1 || day > month_days {
		return error('invalid timestamp date')
	}
	seconds := timestamp_days(year, month, day) * 86400 + i64(hour * 3600 + minute * 60 +
		if second == 60 { 59 } else { second }) - i64(offset)
	if second == 60 {
		nanos += 1_000_000_000
	}
	min_seconds := timestamp_days(-262143, 1, 1) * 86400
	max_seconds := timestamp_days(262142, 12, 31) * 86400 + 86399
	if seconds < min_seconds || seconds > max_seconds {
		return error('UTC timestamp out of range')
	}
	return DateTimeUtc{ seconds: seconds, nanoseconds: nanos }
}

// STUB: chrono's serde serializer uses UTC Z, signed years outside 0000..9999,
// and AutoSi fractional precision (0, 3, 6, or 9 digits), including leap seconds.
pub fn (timestamp DateTimeUtc) to_serde_string() !string {
	if timestamp.nanoseconds >= 2_000_000_000 {
		return error('timestamp nanoseconds out of range')
	}
	min_seconds := timestamp_days(-262143, 1, 1) * 86400
	max_seconds := timestamp_days(262142, 12, 31) * 86400 + 86399
	if timestamp.seconds < min_seconds || timestamp.seconds > max_seconds {
		return error('UTC timestamp out of range')
	}
	year, month, day, second_of_day := timestamp_calendar(timestamp.seconds)
	hour := second_of_day / 3600
	minute := second_of_day % 3600 / 60
	second := second_of_day % 60 + int(timestamp.nanoseconds / 1_000_000_000)
	if timestamp.nanoseconds >= 1_000_000_000 && second_of_day % 60 != 59 {
		return error('invalid leap-second timestamp')
	}
	year_text := if year < 0 {
		'-${-year:04}'
	} else if year > 9999 {
		'+${year}'
	} else {
		'${year:04}'
	}
	nanos := timestamp.nanoseconds % 1_000_000_000
	fraction := if nanos == 0 {
		''
	} else if nanos % 1_000_000 == 0 {
		'.${nanos / 1_000_000:03}'
	} else if nanos % 1000 == 0 {
		'.${nanos / 1000:06}'
	} else {
		'.${nanos:09}'
	}
	return '${year_text}-${month:02}-${day:02}T${hour:02}:${minute:02}:${second:02}${fraction}Z'
}

// STUB: chrono parser cursor borrows the complete serde string without cloning.
struct TimestampParser {
	source &string
mut:
	position int
}

// STUB: chrono scanner's end-safe current byte.
fn (parser &TimestampParser) peek() u8 {
	return if parser.position < parser.source.len { (*parser.source)[parser.position] } else { 0 }
}

// STUB: chrono scanner's exact UTF-8 token comparison.
fn (parser &TimestampParser) matches(token &string) bool {
	return parser.position + token.len <= parser.source.len
		&& (*parser.source)[parser.position..parser.position + token.len] == *token
}

// STUB: chrono accepts ASCII-insensitive UTC as a timezone name.
fn (parser &TimestampParser) matches_ascii(token &string) bool {
	if parser.position + token.len > parser.source.len {
		return false
	}
	for i in 0 .. token.len {
		if ((*parser.source)[parser.position + i] | 32) != ((*token)[i] | 32) {
			return false
		}
	}
	return true
}

// STUB: Rust trim_start's Unicode White_Space set, used between chrono components.
fn (mut parser TimestampParser) space() {
	for parser.position < parser.source.len {
		mut width := 0
		for token in ['\t', '\n', '\x0b', '\x0c', '\r', ' ', '\u0085', '\u00a0', '\u1680', '\u2000',
			'\u2001', '\u2002', '\u2003', '\u2004', '\u2005', '\u2006', '\u2007', '\u2008', '\u2009',
			'\u200a', '\u2028', '\u2029', '\u202f', '\u205f', '\u3000'] {
			if parser.matches(&token) {
				width = token.len
				break
			}
		}
		if width == 0 {
			break
		}
		parser.position += width
	}
}

// STUB: chrono Numeric scanner respects field widths and signed-year overflow.
fn (mut parser TimestampParser) number(width int, leading_space bool) !int {
	if leading_space { parser.space() }
	start := parser.position
	mut value := 0
	for parser.position - start < width && parser.peek() >= `0` && parser.peek() <= `9` {
		digit := int(parser.peek() - `0`)
		if value > (i64(9223372036854775807) - digit) / 10 {
			return error('timestamp number overflow')
		}
		value = value * 10 + digit
		parser.position++
	}
	if parser.position == start {
		return error('expected timestamp number')
	}
	return value
}

// STUB: chrono offset fields require exactly two adjacent ASCII digits.
fn (mut parser TimestampParser) fixed_pair() !int {
	start := parser.position
	value := parser.number(2, false)!
	if parser.position - start != 2 {
		return error('short timestamp offset')
	}
	return value
}

// STUB: chrono scanner's exact literal separators.
fn (mut parser TimestampParser) literal(expected u8) ! {
	if parser.peek() != expected {
		return error('invalid timestamp separator')
	}
	parser.position++
}

// STUB: proleptic Gregorian civil-date projection with floor division for BCE.
fn timestamp_days(year int, month int, day int) i64 {
	y := year - if month <= 2 { 1 } else { 0 }
	era := if y >= 0 { y / 400 } else { (y - 399) / 400 }
	yoe := y - era * 400
	month_index := month + if month > 2 { -3 } else { 9 }
	doy := (153 * month_index + 2) / 5 + day - 1
	return i64(era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468)
}

// STUB: inverse Gregorian projection supports chrono's complete UTC year range.
fn timestamp_calendar(seconds i64) (int, int, int, int) {
	days := if seconds >= 0 { seconds / 86400 } else { (seconds - 86399) / 86400 }
	z := days + 719468
	era := if z >= 0 { z / 146097 } else { (z - 146096) / 146097 }
	doe := z - era * 146097
	yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	mp := (5 * doy + 2) / 153
	day := doy - (153 * mp + 2) / 5 + 1
	month := mp + if mp < 10 { 3 } else { -9 }
	year := yoe + era * 400 + if month <= 2 { 1 } else { 0 }
	return int(year), int(month), int(day), int(seconds - days * 86400)
}
