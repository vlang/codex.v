module serde_json

fn test_number_integer_classification_preserves_signed_and_unsigned_ranges() ! {
	minimum_text := '-9223372036854775808'
	minimum := from_str(&minimum_text)!
	assert minimum.as_i64() or { panic('i64 minimum is an integer') } == i64(-9223372036854775807) - 1
	assert minimum.as_u64() == none
	maximum_text := '18446744073709551615'
	maximum := from_str(&maximum_text)!
	assert maximum.as_i64() == none
	assert maximum.as_u64() or { panic('u64 maximum is an integer') } == ~u64(0)
	for text in ['-9223372036854775809', '-18446744073709551616', '18446744073709551616', '1.0',
		'1e0', '-0'] {
		value := from_str(&text)!
		assert value.as_i64() == none, text
		assert value.as_u64() == none, text
	}
	for text in ['1e400', '-1e400'] {
		if _ := from_str(&text) {
			assert false, text
		}
	}
	for text, normalized in {
		'-9223372036854775809': '-9.223372036854776e+18'
		'18446744073709551616': '1.8446744073709552e+19'
		'1.25e2':               '125.0'
		'1e-6':                 '1e-6'
	} {
		value := from_str(&text)!
		assert value.to_string() == normalized, text
	}
}
