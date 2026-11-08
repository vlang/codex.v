module serde_json

// STUB: serde::de::IgnoredAny validates a JSON value without retaining payload.
pub struct IgnoredAny {}

// STUB: raw serde visitor input retains duplicate fields and discards arbitrary
// JSON values without finite-number conversions, as IgnoredAny requires.
pub struct RawJsonValue {
pub:
	text string
}

// STUB: raw JSON map visitor's ordered, duplicate-preserving field entries.
pub struct RawJsonField {
pub:
	name  string
	value RawJsonValue
}

// STUB: validates complete raw JSON via the established ignored-value parser.
pub fn raw_json_value(text &string) !RawJsonValue {
	mut parser := Parser{ text: text }
	parser.ignore_value()!
	parser.skip_space()
	if parser.position != text.len {
		return error('trailing characters')
	}
	return RawJsonValue{ text: text.trim_space().clone() }
}

// STUB: serde visitor's diagnostic type description for raw JSON values.
pub fn (value &RawJsonValue) unexpected() string {
	if value.text.len == 0 {
		return 'end of input'
	}
	return match value.text[0] {
		`{` { 'map' }
		`[` { 'sequence' }
		`"` { 'string ${value.text}' }
		`n` { 'null' }
		`t`, `f` { 'boolean `${value.text}`' }
		else {
			if value.text.contains('.') || value.text.contains('e') || value.text.contains('E') {
				'floating point `${value.text}`'
			} else {
				'integer `${value.text}`'
			}
		}
	}
}

// STUB: serde borrowed string visitor builds the equivalent owned V String.
pub fn (value &RawJsonValue) string_owned() !string {
	if value.text.len == 0 || value.text[0] != `"` {
		return error('invalid type: ${value.unexpected()}, expected a string')
	}
	mut parser := Parser{ text: &value.text }
	return parser.parse_string()!
}

// STUB: serde JSON object visitor preserves field order and duplicates.
pub fn (value &RawJsonValue) object_fields() ![]RawJsonField {
	if value.text.len == 0 || value.text[0] != `{` {
		return error('invalid type: ${value.unexpected()}, expected a map')
	}
	mut parser := Parser{ text: &value.text, position: 1 }
	mut fields := []RawJsonField{}
	parser.skip_space()
	if parser.position < value.text.len && value.text[parser.position] == `}` {
		return fields
	}
	for {
		parser.skip_space()
		name := parser.parse_string()!
		parser.skip_space()
		if parser.take()! != `:` {
			return error('expected colon')
		}
		parser.skip_space()
		start := parser.position
		parser.ignore_value()!
		fields << RawJsonField{ name: name, value: RawJsonValue{ text: value.text[start..parser.position].clone() } }
		parser.skip_space()
		separator := parser.take()!
		if separator == `}` {
			break
		}
		if separator != `,` {
			return error('expected comma')
		}
	}
	return fields
}

// STUB: serde JSON sequence visitor preserves each value's complete lexical input.
pub fn (value &RawJsonValue) sequence_values() ![]RawJsonValue {
	if value.text.len == 0 || value.text[0] != `[` {
		return error('invalid type: ${value.unexpected()}, expected a sequence')
	}
	mut parser := Parser{ text: &value.text, position: 1 }
	mut values := []RawJsonValue{}
	parser.skip_space()
	if parser.position < value.text.len && value.text[parser.position] == `]` {
		return values
	}
	for {
		parser.skip_space()
		start := parser.position
		parser.ignore_value()!
		values << RawJsonValue{ text: value.text[start..parser.position].clone() }
		parser.skip_space()
		separator := parser.take()!
		if separator == `]` {
			break
		}
		if separator != `,` {
			return error('expected comma')
		}
	}
	return values
}
