module serde_json

import json2

// STUB: serde's struct visitor input preserves repeated object fields so derived
// Deserialize can reject duplicates; the general Value parser intentionally cannot.
pub struct StructField {
pub:
	name  string
	value Value
}

// STUB: serde's map/sequence struct representations, needed by VersionInfo's derive.
pub struct StructInput {
pub:
	is_sequence bool
	fields      []StructField
	sequence    []Value
}

// STUB: serde_json's derived-struct visitor boundary. Nested values reuse the
// existing strict Value parser; top-level object fields retain their source order.
pub fn deserialize_struct(text &string, known_fields &[]string) !StructInput {
	mut parser := Parser{ text: text }
	parser.skip_space()
	if parser.position < text.len && (*text)[parser.position] == `[` {
		value := parser.parse_value()!
		parser.skip_space()
		if parser.position != text.len {
			return error('trailing characters')
		}
		return StructInput{ is_sequence: true, sequence: value.children }
	}
	if parser.take()! != `{` {
		return error('expected struct object or array')
	}
	parser.depth = 1
	mut fields := []StructField{}
	parser.skip_space()
	if parser.position < text.len && (*text)[parser.position] == `}` {
		parser.position++
	} else {
		for {
			parser.skip_space()
			name := parser.parse_string()!
			parser.skip_space()
			if parser.take()! != `:` {
				return error('expected colon')
			}
			if known_fields.contains(name) {
				value := parser.parse_value()!
				fields << StructField{ name: name, value: value }
			} else {
				parser.ignore_value()!
			}
			parser.skip_space()
			separator := parser.take()!
			if separator == `}` {
				break
			}
			if separator != `,` {
				return error('expected comma')
			}
		}
	}
	parser.skip_space()
	if parser.position != text.len {
		return error('trailing characters')
	}
	return StructInput{ fields: fields }
}

// STUB: serde_json::Deserializer::ignore_value keeps an explicit container stack;
// ignored fields permit huge numbers and arbitrary nesting without Value decoding.
struct IgnoredFrame {
	kind u8
mut:
	state int
}

// STUB: serde's IgnoredAny validates syntax while discarding unknown field values.
// Escaped surrogate code units are not decoded, matching serde_json's ignore_str.
fn (mut parser Parser) ignore_value() ! {
	mut stack := []IgnoredFrame{}
	mut expecting_value := true
	for {
		parser.skip_space()
		if expecting_value {
			if parser.position >= parser.text.len {
				return error('expected value')
			}
			character := (*parser.text)[parser.position]
			match character {
				`[`, `{` {
					parser.position++
					stack << IgnoredFrame{ kind: character }
				}
				`"` { parser.ignore_string()! }
				`n`, `t`, `f` {
					literal := if character == `n` {
						'null'
					} else if character == `t` {
						'true'
					} else {
						'false'
					}
					for byte in literal.bytes() {
						if parser.take()! != byte {
							return error('invalid literal')
						}
					}
				}
				else { parser.ignore_number()! }
			}
			expecting_value = false
		}
		if stack.len == 0 {
			return
		}
		parser.skip_space()
		last := stack.len - 1
		frame := stack[last]
		end := if frame.kind == `[` { u8(`]`) } else { u8(`}`) }
		if parser.position >= parser.text.len {
			return error('unexpected end of container')
		}
		character := (*parser.text)[parser.position]
		if frame.state == 1 {
			if character == end {
				parser.position++
				stack.delete(last)
				continue
			}
			if character != `,` {
				return error('expected comma or end')
			}
			parser.position++
			stack[last].state = 2
			continue
		}
		if frame.state == 0 && character == end {
			parser.position++
			stack.delete(last)
			continue
		}
		if frame.kind == `{` {
			parser.ignore_string()!
			parser.skip_space()
			if parser.take()! != `:` {
				return error('expected colon')
			}
		}
		stack[last].state = 1
		expecting_value = true
	}
}

// STUB: serde_json's discard-only string reader checks escape syntax without
// materializing Unicode, so an ignored lone surrogate is permitted.
fn (mut parser Parser) ignore_string() ! {
	if parser.take()! != `"` {
		return error('expected string')
	}
	for {
		character := parser.take()!
		if character == `"` {
			return
		}
		if character < 0x20 {
			return error('control character in string')
		}
		if character != `\\` {
			continue
		}
		escaped := parser.take()!
		if escaped == `u` {
			parser.hex_quad()!
		} else if escaped !in [`"`, `\\`, `/`, `b`, `f`, `n`, `r`, `t`] {
			return error('invalid escape')
		}
	}
}

// STUB: serde_json's ignored number scanner validates JSON grammar without
// converting values into bounded integer or finite floating-point storage.
fn (mut parser Parser) ignore_number() ! {
	if parser.position < parser.text.len && (*parser.text)[parser.position] == `-` {
		parser.position++
	}
	first := parser.take()!
	if first < `0` || first > `9` {
		return error('invalid number')
	}
	if first == `0` {
		if parser.position < parser.text.len && (*parser.text)[parser.position] >= `0` && (*parser.text)[parser.position] <= `9` {
			return error('leading zero in number')
		}
	} else {
		parser.ignore_digits()
	}
	if parser.position < parser.text.len && (*parser.text)[parser.position] == `.` {
		parser.position++
		start := parser.position
		parser.ignore_digits()
		if parser.position == start {
			return error('empty fraction')
		}
	}
	if parser.position < parser.text.len && (*parser.text)[parser.position] in [`e`, `E`] {
		parser.position++
		if parser.position < parser.text.len && (*parser.text)[parser.position] in [
			`+`,
			`-`,
		] {
			parser.position++
		}
		start := parser.position
		parser.ignore_digits()
		if parser.position == start {
			return error('empty exponent')
		}
	}
}

// STUB: serde_json's lexical digit consumption for ignored numbers.
fn (mut parser Parser) ignore_digits() {
	for parser.position < parser.text.len && (*parser.text)[parser.position] >= `0` && (*parser.text)[parser.position] <= `9` {
		parser.position++
	}
}

// STUB: serde_json's typed serialization entry calls the translated serde derive.
// V has no Rust proc-macro derive, so the target supplies serialize_json explicitly.
pub fn to_string[T](value &T) !string {
	return value.serialize_json()
}

// STUB: serde Serializer::serialize_str returns owned escaped JSON text.
pub fn quote_string(value &string) string {
	return json2.encode(value.clone())
}

// STUB: borrowed Value string extraction supplies the owned String constructed by
// serde Deserialize. V cannot return a borrowed string slice; this copy is explicit.
pub fn (value &Value) string_owned() !string {
	if value.kind != .string_value {
		return error('expected a string')
	}
	return value.text.clone()
}

// STUB: serde's Option<String> visitor recognizes JSON null independently of string.
pub fn (value &Value) is_null() bool {
	return value.kind == .null_value
}
