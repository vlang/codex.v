module chrono

import time

// STUB: chrono::DateTime<Local> retains its UTC instant and resolved local offset.
// DateTime is Copy; offset discovery and timezone databases remain untranslated.
pub struct DateTimeLocal {
pub:
	timestamp      DateTimeUtc
	offset_seconds int
}

// STUB: chrono::NaiveDate's equality-relevant local calendar fields.
pub struct NaiveDate {
pub:
	year  int
	month int
	day   int
}

// STUB: chrono::DateTime::date_naive projects the retained instant through the
// stored offset, preserving date changes across local midnight.
pub fn (dt DateTimeLocal) date_naive() NaiveDate {
	local := time.unix(dt.timestamp.seconds + i64(dt.offset_seconds))
	return NaiveDate{ year: local.year, month: local.month, day: local.day }
}

// STUB: chrono::DateTime::format boundary. Only the two format strings observed
// by status/helpers.rs are implemented; other chrono directives are unavailable.
pub fn (dt DateTimeLocal) format(pattern &string) string {
	local := time.unix(dt.timestamp.seconds + i64(dt.offset_seconds))
	if *pattern == '%H:%M' {
		return '${local.hour:02}:${local.minute:02}'
	}
	if *pattern == '%-d %b' {
		months := ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov',
			'Dec']
		return '${local.day} ${months[local.month - 1]}'
	}
	panic('untranslated chrono format directive: ${*pattern}')
}
