// TUI token usage models and display formatting.
module token_usage

import codex_protocol.num_format
import json2
import math
import serde_json
import strconv

const baseline_tokens = i64(12000)

pub struct TokenUsage {
pub mut:
	input_tokens            i64
	cached_input_tokens     i64
	output_tokens           i64
	reasoning_output_tokens i64
	total_tokens            i64
}

pub fn (usage &TokenUsage) is_zero() bool {
	return usage.total_tokens == 0
}

pub fn (usage &TokenUsage) cached_input() i64 {
	return math.max(usage.cached_input_tokens, i64(0))
}

pub fn (usage &TokenUsage) non_cached_input() i64 {
	return math.max(usage.input_tokens - usage.cached_input(), i64(0))
}

pub fn (usage &TokenUsage) blended_total() i64 {
	return math.max(usage.non_cached_input() + math.max(usage.output_tokens, i64(0)), i64(0))
}

// Returns the raw `total_tokens` value. For `last_token_usage`, this is the latest active
// context size; for `total_token_usage`, this is the accumulated session total.
pub fn (usage &TokenUsage) tokens_in_context_window() i64 {
	return usage.total_tokens
}

pub fn (usage &TokenUsage) percent_of_context_window_remaining(context_window i64) i64 {
	if context_window <= baseline_tokens {
		return 0
	}
	effective_window := context_window - baseline_tokens
	used := math.max(usage.tokens_in_context_window() - baseline_tokens, i64(0))
	remaining := math.max(effective_window - used, i64(0))
	return i64(math.round(math.clamp((f64(remaining) / f64(effective_window)) * 100.0,
		0.0, 100.0)))
}

// V has module-level visibility rather than Rust's pub(crate). Export the type and
// its fields so the eventual TUI sibling modules can access the crate-private model.
pub struct TokenUsageInfo {
pub mut:
	total_token_usage    TokenUsage
	last_token_usage     TokenUsage
	model_context_window ?i64
}

// Rust's Display::fmt maps to V's borrowed str() method.
pub fn (usage &TokenUsage) str() string {
	cached := if usage.cached_input() > 0 {
		' (+ ${num_format.format_with_separators(usage.cached_input())} cached)'
	} else {
		''
	}
	reasoning := if usage.reasoning_output_tokens > 0 {
		' (reasoning ${num_format.format_with_separators(usage.reasoning_output_tokens)})'
	} else {
		''
	}
	return 'Token usage: total=${num_format.format_with_separators(usage.blended_total())} input=${num_format.format_with_separators(usage.non_cached_input())}${cached} output=${num_format.format_with_separators(usage.output_tokens)}${reasoning}'
}

// The following methods preserve the Rust derives. Equality is V's structural
// equality; these numeric models have no allocation-bearing fields to clone.
pub fn TokenUsage.default() TokenUsage {
	return TokenUsage{}
}

pub fn (usage &TokenUsage) clone() TokenUsage {
	return *usage
}

pub fn (usage &TokenUsage) debug() string {
	return 'TokenUsage { input_tokens: ${usage.input_tokens}, cached_input_tokens: ${usage.cached_input_tokens}, output_tokens: ${usage.output_tokens}, reasoning_output_tokens: ${usage.reasoning_output_tokens}, total_tokens: ${usage.total_tokens} }'
}

pub fn (info &TokenUsageInfo) clone() TokenUsageInfo {
	return TokenUsageInfo{
		total_token_usage:    info.total_token_usage.clone()
		last_token_usage:     info.last_token_usage.clone()
		model_context_window: info.model_context_window
	}
}

pub fn (info &TokenUsageInfo) debug() string {
	window := if value := info.model_context_window { 'Some(${value})' } else { 'None' }
	return 'TokenUsageInfo { total_token_usage: ${info.total_token_usage.debug()}, last_token_usage: ${info.last_token_usage.debug()}, model_context_window: ${window} }'
}

// Serialize retains declaration order and the unrenamed serde snake_case fields.
pub fn (usage &TokenUsage) serialize() string {
	return '{"input_tokens":${usage.input_tokens},"cached_input_tokens":${usage.cached_input_tokens},"output_tokens":${usage.output_tokens},"reasoning_output_tokens":${usage.reasoning_output_tokens},"total_tokens":${usage.total_tokens}}'
}

pub fn (usage &TokenUsage) to_json() string {
	return usage.serialize()
}

pub fn (info &TokenUsageInfo) serialize() string {
	window := if value := info.model_context_window { value.str() } else { 'null' }
	return '{"total_token_usage":${info.total_token_usage.serialize()},"last_token_usage":${info.last_token_usage.serialize()},"model_context_window":${window}}'
}

pub fn (info &TokenUsageInfo) to_json() string {
	return info.serialize()
}

// serde's generated Deserialize accepts struct maps and positional sequences. V's
// default decoder coerces floats into integers and replaces duplicate fields, so
// validate JSON syntax with the existing serde_json parser, then retain the token
// stream to enforce serde's field, integer, and duplicate checks. Error categories
// are retained; this dependency boundary does not expose serde's line/column suffix.
pub fn TokenUsage.deserialize(encoded &string) !TokenUsage {
	validate_json_structure(encoded)!
	mut decoder := TokenUsageDecoder{ encoded: encoded, scanner: json2.new_scanner(encoded.clone()) }
	first := decoder.next()!
	return decoder.read_usage(&first)
}

pub fn TokenUsageInfo.deserialize(encoded &string) !TokenUsageInfo {
	validate_json_structure(encoded)!
	mut decoder := TokenUsageDecoder{ encoded: encoded, scanner: json2.new_scanner(encoded.clone()) }
	first := decoder.next()!
	return decoder.read_info(&first)
}

struct TokenUsageDecoder {
	encoded &string
mut:
	scanner          json2.Scanner
	raw_cursor       int
	raw_string_start int
	raw_string_end   int
}

// json2.Scanner decodes surrogate halves independently. Track the original string
// ranges rather than validating its decoded bytes, so struct keys can be decoded
// as Unicode while strings inside IgnoredAny retain serde's permissive escape rules.
fn (mut decoder TokenUsageDecoder) next() !json2.Token {
	token := decoder.scanner.next()!
	if token.kind != .str {
		return token
	}
	for decoder.raw_cursor < decoder.encoded.len
		&& (*decoder.encoded)[decoder.raw_cursor] != `"` {
		decoder.raw_cursor++
	}
	decoder.raw_string_start = decoder.raw_cursor
	decoder.raw_cursor++
	for decoder.raw_cursor < decoder.encoded.len {
		ch := (*decoder.encoded)[decoder.raw_cursor]
		decoder.raw_cursor++
		if ch == `\\` {
			decoder.raw_cursor++
		} else if ch == `"` {
			break
		}
	}
	decoder.raw_string_end = decoder.raw_cursor
	return token
}

fn (decoder &TokenUsageDecoder) field_name() !string {
	// The allocated raw slice is a V lifetime adaptation for the borrowed JSON key.
	// This checks actual struct keys, including unknown names; ignored nested keys
	// never reach this method. json2's decoder correctly combines surrogate pairs.
	raw := (*decoder.encoded)[decoder.raw_string_start..decoder.raw_string_end].clone()
	_ := serde_json.from_str(&raw)!
	return json2.decode[string](raw, strict: true)
}

// serde's IgnoredAny skips unknown numbers without requiring them to fit f64.
// Validate each raw number's grammar and substitute zero only in the syntax-check
// copy, so an ignored 1e9999 remains legal while known fields still require i64.
// IgnoredAny also accepts lone surrogate escapes in strings and nested keys.
// Replace valid four-hex Unicode escapes only in this syntax-check copy; actual
// struct keys are checked separately against their original raw JSON spans.
fn validate_json_structure(encoded &string) ! {
	mut syntax := []u8{cap: encoded.len}
	mut position := 0
	mut in_string := false
	for position < encoded.len {
		ch := (*encoded)[position]
		if in_string {
			syntax << ch
			position++
			if ch == `\\` && position < encoded.len {
				if (*encoded)[position] == `u` {
					if position + 4 >= encoded.len {
						return error('invalid unicode escape')
					}
					for index in position + 1 .. position + 5 {
						if !(*encoded)[index].is_hex_digit() {
							return error('invalid unicode escape')
						}
					}
					syntax << 'u0000'.bytes()
					position += 5
				} else {
					syntax << (*encoded)[position]
					position++
				}
			} else if ch == `"` {
				in_string = false
			}
			continue
		}
		if ch == `"` {
			in_string = true
			syntax << ch
			position++
			continue
		}
		if ch != `-` && (ch < `0` || ch > `9`) {
			syntax << ch
			position++
			continue
		}
		if ch == `-` {
			position++
		}
		if position >= encoded.len || (*encoded)[position] < `0`
			|| (*encoded)[position] > `9` {
			return error('invalid number')
		}
		if (*encoded)[position] == `0` {
			position++
			if position < encoded.len && (*encoded)[position] >= `0`
				&& (*encoded)[position] <= `9` {
				return error('invalid number: leading zero')
			}
		} else {
			for position < encoded.len && (*encoded)[position] >= `0`
				&& (*encoded)[position] <= `9` {
				position++
			}
		}
		if position < encoded.len && (*encoded)[position] == `.` {
			position++
			start := position
			for position < encoded.len && (*encoded)[position] >= `0`
				&& (*encoded)[position] <= `9` {
				position++
			}
			if position == start {
				return error('invalid number: empty fraction')
			}
		}
		if position < encoded.len && (*encoded)[position] in [`e`, `E`] {
			position++
			if position < encoded.len && (*encoded)[position] in [`+`, `-`] {
				position++
			}
			start := position
			for position < encoded.len && (*encoded)[position] >= `0`
				&& (*encoded)[position] <= `9` {
				position++
			}
			if position == start {
				return error('invalid number: empty exponent')
			}
		}
		syntax << u8(`0`)
	}
	validated := syntax.bytestr()
	_ := serde_json.from_str(&validated)!
}

fn read_i64(token &json2.Token) !i64 {
	text := token.literal()
	// serde_json treats negative zero as a floating-point number, even without a dot.
	if token.kind != .int || text == '-0' || text.contains_any('.eE') {
		return error('invalid type: ${text}, expected i64')
	}
	// parse_int saturates on signed overflow; serde's i64 visitor rejects it.
	return strconv.common_parse_int(text, 10, 64, true, true) or {
		return error('invalid value: integer `${text}`, expected i64')
	}
}

fn (mut decoder TokenUsageDecoder) read_usage(first &json2.Token) !TokenUsage {
	mut usage := TokenUsage{}
	mut seen := u8(0)
	if first.kind == .lsbr {
		for index in 0 .. 5 {
			token := decoder.next()!
			if token.kind == .rsbr {
				return error('invalid length ${index}, expected struct TokenUsage with 5 elements')
			}
			value := read_i64(&token)!
			match index {
				0 { usage.input_tokens = value }
				1 { usage.cached_input_tokens = value }
				2 { usage.output_tokens = value }
				3 { usage.reasoning_output_tokens = value }
				4 { usage.total_tokens = value }
				else {}
			}
			separator := decoder.next()!
			if index == 4 {
				if separator.kind != .rsbr {
					return error('invalid length, expected struct TokenUsage with 5 elements')
				}
			} else if separator.kind == .rsbr {
				return error('invalid length ${index + 1}, expected struct TokenUsage with 5 elements')
			}
		}
		return usage
	}
	if first.kind != .lcbr {
		return error('invalid type, expected struct TokenUsage')
	}
	mut key := decoder.next()!
	for key.kind != .rcbr {
		name := decoder.field_name()!
		_ = decoder.next()! // colon, checked by the JSON parser
		token := decoder.next()!
		index := match name {
			'input_tokens' { 0 }
			'cached_input_tokens' { 1 }
			'output_tokens' { 2 }
			'reasoning_output_tokens' { 3 }
			'total_tokens' { 4 }
			else { -1 }
		}
		if index >= 0 {
			bit := u8(1) << index
			if seen & bit != 0 {
				return error('duplicate field `${name}`')
			}
			seen |= bit
			value := read_i64(&token)!
			match index {
				0 { usage.input_tokens = value }
				1 { usage.cached_input_tokens = value }
				2 { usage.output_tokens = value }
				3 { usage.reasoning_output_tokens = value }
				4 { usage.total_tokens = value }
				else {}
			}
		} else {
			decoder.skip_value(&token)!
		}
		separator := decoder.next()!
		if separator.kind == .rcbr {
			break
		}
		key = decoder.next()!
	}
	for index, name in ['input_tokens', 'cached_input_tokens', 'output_tokens',
		'reasoning_output_tokens', 'total_tokens'] {
		if seen & (u8(1) << index) == 0 {
			return error('missing field `${name}`')
		}
	}
	return usage
}

fn (mut decoder TokenUsageDecoder) read_info(first &json2.Token) !TokenUsageInfo {
	mut info := TokenUsageInfo{}
	mut seen := u8(0)
	if first.kind == .lsbr {
		for index in 0 .. 3 {
			token := decoder.next()!
			if token.kind == .rsbr {
				return error('invalid length ${index}, expected struct TokenUsageInfo with 3 elements')
			}
			match index {
				0 { info.total_token_usage = decoder.read_usage(&token)! }
				1 { info.last_token_usage = decoder.read_usage(&token)! }
				2 {
					info.model_context_window = if token.kind == .null {
						none
					} else {
						read_i64(&token)!
					}
				}
				else {}
			}
			separator := decoder.next()!
			if index == 2 {
				if separator.kind != .rsbr {
					return error('invalid length, expected struct TokenUsageInfo with 3 elements')
				}
			} else if separator.kind == .rsbr {
				return error('invalid length ${index + 1}, expected struct TokenUsageInfo with 3 elements')
			}
		}
		return info
	}
	if first.kind != .lcbr {
		return error('invalid type, expected struct TokenUsageInfo')
	}
	mut key := decoder.next()!
	for key.kind != .rcbr {
		name := decoder.field_name()!
		_ = decoder.next()! // colon, checked by the JSON parser
		token := decoder.next()!
		index := match name {
			'total_token_usage' { 0 }
			'last_token_usage' { 1 }
			'model_context_window' { 2 }
			else { -1 }
		}
		if index >= 0 {
			bit := u8(1) << index
			if seen & bit != 0 {
				return error('duplicate field `${name}`')
			}
			seen |= bit
			match index {
				0 { info.total_token_usage = decoder.read_usage(&token)! }
				1 { info.last_token_usage = decoder.read_usage(&token)! }
				2 {
					info.model_context_window = if token.kind == .null {
						none
					} else {
						read_i64(&token)!
					}
				}
				else {}
			}
		} else {
			decoder.skip_value(&token)!
		}
		separator := decoder.next()!
		if separator.kind == .rcbr {
			break
		}
		key = decoder.next()!
	}
	for index, name in ['total_token_usage', 'last_token_usage'] {
		if seen & (u8(1) << index) == 0 {
			return error('missing field `${name}`')
		}
	}
	return info
}

// Unknown fields are ignored by serde, including any nested arrays or objects.
fn (mut decoder TokenUsageDecoder) skip_value(first &json2.Token) ! {
	if first.kind !in [.lcbr, .lsbr] {
		return
	}
	mut depth := 1
	for depth > 0 {
		token := decoder.next()!
		match token.kind {
			.lcbr, .lsbr { depth++ }
			.rcbr, .rsbr { depth-- }
			.eof { return error('unexpected end of input') }
			else {}
		}
	}
}
