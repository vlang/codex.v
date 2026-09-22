module num_format

// STUB: Locale-sensitive formatting will be translated with num_format.rs.
pub fn format_with_separators(value i64) string {
	negative := value < 0
	digits := if negative { (-value).str() } else { value.str() }
	mut groups := []string{}
	mut end := digits.len
	for end > 3 {
		groups.prepend(digits[end - 3..end])
		end -= 3
	}
	groups.prepend(digits[..end])
	formatted := groups.join(',')
	return if negative { '-${formatted}' } else { formatted }
}
