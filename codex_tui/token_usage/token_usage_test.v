module token_usage

import json2

fn token_usage_owned_text(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn test_raw_total_is_independent_of_blended_display_and_zero() {
	mut usage := TokenUsage{
		input_tokens:            18000
		cached_input_tokens:     15000
		output_tokens:           700
		reasoning_output_tokens: 400
		total_tokens:            26000
	}
	assert usage.cached_input() == 15000
	assert usage.non_cached_input() == 3000
	assert usage.blended_total() == 3700
	assert usage.tokens_in_context_window() == 26000
	assert !usage.is_zero()
	usage.total_tokens = 0
	assert usage.is_zero()
	assert usage.blended_total() == 3700
	assert usage.tokens_in_context_window() == 0
}

fn test_negative_usage_clamps_accounting_but_retains_raw_fields() {
	usage := TokenUsage{
		input_tokens:            -80
		cached_input_tokens:     -100
		output_tokens:           -20
		reasoning_output_tokens: -10
		total_tokens:            -200
	}
	assert usage.cached_input() == 0
	assert usage.non_cached_input() == 0
	assert usage.blended_total() == 0
	assert usage.tokens_in_context_window() == -200
	assert !usage.is_zero()
	assert usage.str() == 'Token usage: total=0 input=0 output=-20'
	assert usage.percent_of_context_window_remaining(30000) == 100
}

fn test_display_preserves_minimum_i64_output_with_one_minus_sign() {
	usage := TokenUsage{ output_tokens: i64(-9223372036854775807) - 1 }
	assert usage.blended_total() == 0
	assert usage.str() == 'Token usage: total=0 input=0 output=-9,223,372,036,854,775,808'
}

fn test_cached_input_larger_than_input_does_not_hide_output() {
	usage := TokenUsage{
		input_tokens:        50
		cached_input_tokens: 70
		output_tokens:       30
		total_tokens:        80
	}
	assert usage.non_cached_input() == 0
	assert usage.blended_total() == 30
	assert usage.str() == 'Token usage: total=30 input=0 (+ 70 cached) output=30'
}

fn test_context_window_baseline_limits_and_percentage() {
	for window in [i64(-1), 0, 11999, 12000] {
		assert (TokenUsage{ total_tokens: 9000 }).percent_of_context_window_remaining(window) == 0
	}
	for total in [i64(-100), 0, 9000, 12000] {
		assert (TokenUsage{ total_tokens: total }).percent_of_context_window_remaining(22000) == 100
	}
	assert (TokenUsage{ total_tokens: 14500 }).percent_of_context_window_remaining(22000) == 75
	assert (TokenUsage{ total_tokens: 19500 }).percent_of_context_window_remaining(22000) == 25
	assert (TokenUsage{ total_tokens: 22000 }).percent_of_context_window_remaining(22000) == 0
	assert (TokenUsage{ total_tokens: 50000 }).percent_of_context_window_remaining(22000) == 0
	// A window one token above baseline still has a meaningful effective capacity.
	assert (TokenUsage{ total_tokens: 12000 }).percent_of_context_window_remaining(12001) == 100
	assert (TokenUsage{ total_tokens: 12001 }).percent_of_context_window_remaining(12001) == 0
}

fn test_context_percentage_rounds_ties_away_from_zero() {
	// Effective capacity 200 makes each remaining token exactly half a percent.
	assert (TokenUsage{ total_tokens: 12067 }).percent_of_context_window_remaining(12200) == 67
	assert (TokenUsage{ total_tokens: 12199 }).percent_of_context_window_remaining(12200) == 1
	assert (TokenUsage{ total_tokens: 12001 }).percent_of_context_window_remaining(12200) == 100
	assert (TokenUsage{ total_tokens: 12004 }).percent_of_context_window_remaining(12300) == 99
}

fn test_display_formats_uncached_total_cache_and_reasoning_suffixes() {
	mut usage := TokenUsage{
		input_tokens:            15000
		cached_input_tokens:     10000
		output_tokens:           2500
		reasoning_output_tokens: 1200
		total_tokens:            17500
	}
	assert usage.str() == 'Token usage: total=7,500 input=5,000 (+ 10,000 cached) output=2,500 (reasoning 1,200)'
	usage.cached_input_tokens = -1
	usage.reasoning_output_tokens = 0
	assert usage.str() == 'Token usage: total=17,500 input=15,000 output=2,500'
	usage.reasoning_output_tokens = -3
	assert usage.str() == 'Token usage: total=17,500 input=15,000 output=2,500'
}

fn test_derived_clone_default_equality_and_debug_preserve_fields() {
	mut usage := TokenUsage{
		input_tokens:            1
		cached_input_tokens:     2
		output_tokens:           3
		reasoning_output_tokens: 4
		total_tokens:            5
	}
	cloned := usage.clone()
	assert cloned == usage
	assert cloned.debug() == 'TokenUsage { input_tokens: 1, cached_input_tokens: 2, output_tokens: 3, reasoning_output_tokens: 4, total_tokens: 5 }'
	usage.total_tokens = 8
	assert cloned != usage
	usage = TokenUsage.default()
	assert usage.is_zero()
	assert usage.str() == 'Token usage: total=0 input=0 output=0'
}

fn test_usage_json_wire_fields_order_and_roundtrip_with_i64_bounds() {
	usage := TokenUsage{
		input_tokens:            i64(-9223372036854775807) - 1
		cached_input_tokens:     9223372036854775807
		output_tokens:           -3
		reasoning_output_tokens: 4
		total_tokens:            5
	}
	encoded := usage.serialize()
	assert encoded == '{"input_tokens":-9223372036854775808,"cached_input_tokens":9223372036854775807,"output_tokens":-3,"reasoning_output_tokens":4,"total_tokens":5}'
	assert TokenUsage.deserialize(&encoded)! == usage
	assert json2.encode(usage) == encoded
}

fn test_usage_json_requires_all_fields_without_using_default_derive() {
	for missing in ['input_tokens', 'cached_input_tokens', 'output_tokens', 'reasoning_output_tokens',
		'total_tokens'] {
		mut fields := []string{}
		for name in ['input_tokens', 'cached_input_tokens', 'output_tokens', 'reasoning_output_tokens',
			'total_tokens'] {
			if name != missing {
				fields << '"${name}":0'
			}
		}
		encoded := '{' + fields.join(',') + '}'
		TokenUsage.deserialize(&encoded) or {
			assert err.msg() == 'missing field `${missing}`'
			continue
		}
		assert false, 'missing field ${missing} was accepted'
	}
}

fn test_usage_json_rejects_wrong_integer_types_and_out_of_range_values() {
	for invalid in ['null', 'true', '"2"', '1.0', '1e0', '-0', '[]', '{}', '9223372036854775808',
		'-9223372036854775809'] {
		encoded := '{"input_tokens":${invalid},"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":0}'
		TokenUsage.deserialize(&encoded) or {
			assert err.msg().starts_with('invalid ')
			continue
		}
		assert false, 'invalid integer ${invalid} was accepted'
	}
}

fn test_usage_json_ignores_unknown_fields_and_decodes_escaped_names() {
	encoded := r'{"ignored":{"nested":[1,{"input_tokens":null}],"total_tokens":"ignored","huge_number":1e9999},"input_\u0074okens":1,"cached_input_tokens":2,"output_tokens":3,"reasoning_output_tokens":4,"total_tokens":5,"ignored":false}'
	assert TokenUsage.deserialize(&encoded)! == TokenUsage{
		input_tokens:            1
		cached_input_tokens:     2
		output_tokens:           3
		reasoning_output_tokens: 4
		total_tokens:            5
	}
}

fn test_ignored_json_strings_and_nested_keys_allow_lone_surrogates() {
	usage := TokenUsage{ input_tokens: 1, total_tokens: 1 }
	for ignored in [r'"\uD800"', r'"\uDC00"',
		r'{"\uD800":"\uDC00","nested":["\uD800",{"\uDC00":"\uD800"}]}'] {
		encoded := '{"unknown":${ignored},${usage.serialize()[1..]}'
		assert TokenUsage.deserialize(&encoded)! == usage
	}
	info := TokenUsageInfo{ total_token_usage: usage, last_token_usage: usage }
	encoded := '{"unknown":' + r'{"\uD800":["\uDC00"]}' + ',${info.serialize()[1..]}'
	assert TokenUsageInfo.deserialize(&encoded)! == info
}

fn test_actual_json_struct_keys_require_valid_surrogate_pairs() {
	usage := TokenUsage{}.serialize()
	for invalid_key in [r'\uD800', r'\uDC00', r'\uD800\u0041', r'prefix\uD800suffix'] {
		encoded := '{"${invalid_key}":null,${usage[1..]}'
		TokenUsage.deserialize(&encoded) or {
			assert err.msg().contains('surrogate')
			continue
		}
		assert false, 'invalid surrogate struct key was accepted'
	}
	for invalid_key in [r'\uD800', r'\uDC00'] {
		encoded := '{"${invalid_key}":null,"total_token_usage":${usage},"last_token_usage":${usage}}'
		TokenUsageInfo.deserialize(&encoded) or {
			assert err.msg().contains('surrogate')
			continue
		}
		assert false, 'invalid surrogate info key was accepted'
	}
	// Struct fields nested inside known TokenUsageInfo values still require Unicode keys.
	nested := '{"total_token_usage":{' + r'"\uD800":null,' + '${usage[1..]},"last_token_usage":${usage}}'
	TokenUsageInfo.deserialize(&nested) or {
		assert err.msg().contains('surrogate')
		return
	}
	assert false, 'invalid surrogate key in known nested struct was accepted'
}

fn test_valid_paired_surrogate_unknown_struct_keys_are_ignored() {
	usage := TokenUsage{ input_tokens: 7, total_tokens: 11 }
	encoded := '{' + r'"\uD83D\uDE00":null,' + usage.serialize()[1..]
	assert TokenUsage.deserialize(&encoded)! == usage
	info := TokenUsageInfo{ total_token_usage: usage, last_token_usage: usage }
	info_encoded := '{' + r'"\uD83D\uDE00":{"\uD800":"\uDC00"},' + info.serialize()[1..]
	assert TokenUsageInfo.deserialize(&info_encoded)! == info
}

fn test_ignored_unicode_escapes_still_require_four_hex_digits() {
	usage := TokenUsage{}.serialize()
	for ignored in [r'"\uD80G"', r'"\uD80"', r'"\u"', r'{"\uDC0Z":null}'] {
		encoded := '{"unknown":${ignored},${usage[1..]}'
		TokenUsage.deserialize(&encoded) or {
			assert err.msg().contains('unicode escape')
			continue
		}
		assert false, 'malformed ignored unicode escape was accepted'
	}
}

fn test_usage_json_rejects_duplicate_recognized_and_escaped_fields() {
	for duplicate in ['input_tokens', r'input_\u0074okens'] {
		encoded := '{"input_tokens":0,"${duplicate}":1,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":0}'
		TokenUsage.deserialize(&encoded) or {
			assert err.msg() == 'duplicate field `input_tokens`'
			continue
		}
		assert false, 'duplicate field was accepted'
	}
}

fn test_usage_json_accepts_serde_positional_sequence() {
	encoded := '[11,12,13,14,15]'
	assert TokenUsage.deserialize(&encoded)! == TokenUsage{
		input_tokens:            11
		cached_input_tokens:     12
		output_tokens:           13
		reasoning_output_tokens: 14
		total_tokens:            15
	}
	for invalid in ['[]', '[1,2]', '[1,2,3,4]', '[1,2,3,4,5,6]'] {
		TokenUsage.deserialize(&invalid) or {
			assert err.msg().starts_with('invalid length')
			continue
		}
		assert false, 'sequence with invalid length was accepted'
	}
}

fn test_info_json_optional_window_required_nested_values_and_roundtrip() {
	usage := TokenUsage{ input_tokens: 30, cached_input_tokens: 20, output_tokens: 4, total_tokens: 34 }
	last := TokenUsage{ input_tokens: 7, total_tokens: 7 }
	mut info := TokenUsageInfo{ total_token_usage: usage, last_token_usage: last }
	encoded := info.serialize()
	assert encoded == '{"total_token_usage":${usage.serialize()},"last_token_usage":${last.serialize()},"model_context_window":null}'
	assert TokenUsageInfo.deserialize(&encoded)! == info
	assert json2.encode(info) == encoded
	missing_optional := '{"total_token_usage":${usage.serialize()},"last_token_usage":${last.serialize()}}'
	assert TokenUsageInfo.deserialize(&missing_optional)! == info
	info.model_context_window = 128000
	with_window := info.serialize()
	assert TokenUsageInfo.deserialize(&with_window)! == info
	assert info.clone() == info
	assert info.debug().ends_with('model_context_window: Some(128000) }')
	info.model_context_window = none
	assert info.debug().ends_with('model_context_window: None }')
	for missing in ['total_token_usage', 'last_token_usage'] {
		remaining := if missing == 'total_token_usage' {
			'last_token_usage'
		} else {
			'total_token_usage'
		}
		invalid := '{"${remaining}":${usage.serialize()}}'
		TokenUsageInfo.deserialize(&invalid) or {
			assert err.msg() == 'missing field `${missing}`'
			continue
		}
		assert false, 'missing nested usage was accepted'
	}
}

fn test_info_json_rejects_duplicate_null_window_and_invalid_nested_values() {
	usage := TokenUsage{}.serialize()
	for invalid in ['null', '{}', '"usage"'] {
		encoded := '{"total_token_usage":${invalid},"last_token_usage":${usage}}'
		TokenUsageInfo.deserialize(&encoded) or {
			assert err.msg().starts_with('invalid ') || err.msg().starts_with('missing field')
			continue
		}
		assert false, 'invalid nested usage was accepted'
	}
	duplicate := '{"total_token_usage":${usage},"last_token_usage":${usage},"model_context_window":null,"model_context_window":null}'
	TokenUsageInfo.deserialize(&duplicate) or {
		assert err.msg() == 'duplicate field `model_context_window`'
		return
	}
	assert false, 'duplicate null optional field was accepted'
}

fn test_info_json_rejects_non_integer_window_and_duplicate_nested_fields() {
	usage := TokenUsage{}.serialize()
	for invalid in ['true', '"32000"', '32000.0', '32e3', '-0', '9223372036854775808',
		'-9223372036854775809'] {
		encoded := '{"total_token_usage":${usage},"last_token_usage":${usage},"model_context_window":${invalid}}'
		TokenUsageInfo.deserialize(&encoded) or {
			assert err.msg().starts_with('invalid ')
			continue
		}
		assert false, 'invalid context window was accepted'
	}
	for duplicate in ['total_token_usage', 'last_token_usage'] {
		encoded := '{"total_token_usage":${usage},"last_token_usage":${usage},"${duplicate}":${usage}}'
		TokenUsageInfo.deserialize(&encoded) or {
			assert err.msg() == 'duplicate field `${duplicate}`'
			continue
		}
		assert false, 'duplicate nested usage was accepted'
	}
}

fn test_info_json_accepts_sequences_and_ignores_unknown_fields() {
	encoded := '[[1,2,3,4,5],[6,7,8,9,10],null]'
	info := TokenUsageInfo.deserialize(&encoded)!
	assert info == TokenUsageInfo{
		total_token_usage: TokenUsage{ input_tokens: 1, cached_input_tokens: 2, output_tokens: 3, reasoning_output_tokens: 4, total_tokens: 5 }
		last_token_usage:  TokenUsage{ input_tokens: 6, cached_input_tokens: 7, output_tokens: 8, reasoning_output_tokens: 9, total_tokens: 10 }
	}
	unknown := '{"unknown":[{"a":null}],"total_token_usage":[1,2,3,4,5],"last_token_usage":[6,7,8,9,10]}'
	assert TokenUsageInfo.deserialize(&unknown)! == info
	for invalid in ['[]', '[[1,2,3,4,5]]', '[[1,2,3,4,5],[1,2,3,4,5]]',
		'[[1,2,3,4,5],[1,2,3,4,5],null,null]'] {
		TokenUsageInfo.deserialize(&invalid) or {
			assert err.msg().starts_with('invalid length')
			continue
		}
		assert false, 'sequence with invalid length was accepted'
	}
}

fn test_json_rejects_syntax_errors_and_trailing_data() {
	for encoded in ['[1,2,3,4,5] true', '[1,2,3,4,5,]', '{"input_tokens":01}', '{"input_tokens":NaN}',
		'{"input_tokens":0,}', ''] {
		TokenUsage.deserialize(&encoded) or { continue }
		assert false, 'invalid JSON was accepted'
	}
}

fn test_borrowed_json_input_and_model_owners_remain_reusable() {
	encoded := token_usage_owned_text('{"input_tokens":15000,"cached_input_tokens":10000,"output_tokens":2500,"reasoning_output_tokens":1200,"total_tokens":17500}')
	usage := TokenUsage.deserialize(&encoded)!
	assert TokenUsage.deserialize(&encoded)! == usage
	assert encoded.starts_with('{"input_tokens":15000')
	first_display := usage.str()
	assert usage.str() == first_display
	assert usage.serialize() == encoded
	assert usage.clone() == usage
	assert usage.total_tokens == 17500
	info_text := token_usage_owned_text('{"total_token_usage":${encoded},"last_token_usage":${encoded},"model_context_window":128000}')
	info := TokenUsageInfo.deserialize(&info_text)!
	assert TokenUsageInfo.deserialize(&info_text)! == info
	assert info.serialize() == info_text
	assert info.clone() == info
	assert info.model_context_window or { i64(0) } == 128000
	assert info_text.ends_with('128000}')
}
