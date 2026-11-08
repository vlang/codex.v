module serde_json

import encoding.utf8

// STUB: serde's internally tagged visitor extracts the discriminant and buffers
// all remaining Content, preserving duplicate keys for the variant struct visitor.
pub struct TaggedInput {
pub:
	tag   string
	input StructInput
}

// STUB: serde::private::TaggedContentVisitor accepts object and sequence forms.
// Unlike deserialize_struct's ignored unknown fields, internally tagged Content
// must parse every value, including fields the variant will eventually ignore.
pub fn deserialize_tagged(text &string, tag_name &string) !TaggedInput {
	if !utf8.validate(text.str, text.len) {
		return error('invalid UTF-8 in JSON input')
	}
	mut parser := Parser{ text: text }
	parser.skip_space()
	first := parser.take()!
	if first !in [`{`, `[`] {
		return error('expected internally tagged enum object or array')
	}
	parser.depth = 1
	mut tag := ?string(none)
	mut fields := []StructField{}
	mut sequence := []Value{}
	is_sequence := first == `[`
	end := if is_sequence { u8(`]`) } else { u8(`}`) }
	parser.skip_space()
	if parser.position < text.len && (*text)[parser.position] == end {
		parser.position++
	} else {
		for {
			parser.skip_space()
			if is_sequence {
				if tag == none {
					tag = parser.parse_string()!
				} else {
					sequence << parser.parse_value()!
				}
			} else {
				name := parser.parse_string()!
				parser.skip_space()
				if parser.take()! != `:` {
					return error('expected colon')
				}
				parser.skip_space()
				if name == *tag_name {
					if tag != none {
						return error('duplicate field `${*tag_name}`')
					}
					tag = parser.parse_string()!
				} else {
					value := parser.parse_value()!
					fields << StructField{ name: name, value: value }
				}
			}
			parser.skip_space()
			separator := parser.take()!
			if separator == end {
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
	return TaggedInput{
		tag:   tag or { return error('missing field `${*tag_name}`') }
		input: StructInput{ is_sequence: is_sequence, fields: fields, sequence: sequence }
	}
}
