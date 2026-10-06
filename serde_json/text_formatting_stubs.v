module serde_json

import math
import strconv
import json2

// STUB: serde_json::Value kinds used by text_formatting; object order follows preserve_order.
enum Kind {
	null_value
	boolean
	string_value
	number
	array
	object
}

// STUB: serde_json::Value's observed tree representation. Number text is its normalized
// i64/u64/f64 serialization; parallel object keys preserve insertion order and duplicate replacement.
pub struct Value {
mut:
	kind     Kind
	text     string
	children []Value
	keys     []string
}

// STUB: serde_json's borrowed input parser boundary, limited to the Value API needed here.
struct Parser {
	text &string
mut:
	position int
	depth    int
}

// STUB: serde_json::from_str::<Value>, with strict syntax, finite numbers and a 128-depth limit.
pub fn from_str(text &string) !Value {
	mut parser := Parser{ text: text }
	value := parser.parse_value()!
	parser.skip_space()
	if parser.position != text.len {
		return error('trailing characters')
	}
	return value
}

// STUB: serde_json::to_string_pretty::<Value>; two-space indentation and escaped JSON strings.
pub fn to_string_pretty(value &Value) !string {
	return encode_value(value, 0, true)
}

// STUB: serde_json::Value::to_string compact serialization fallback.
pub fn (value &Value) to_string() string {
	return encode_value(value, 0, false)
}

// STUB: serde_json serializer for the Value surface used by the translated formatter.
fn encode_value(value &Value, depth int, pretty bool) string {
	match value.kind {
		.null_value { return 'null' }
		.boolean, .number { return value.text.clone() }
		.string_value { return json2.encode(value.text.clone()) }
		.array, .object {
			is_object := value.kind == .object
			mut result := if is_object { '{' } else { '[' }
			for i in 0 .. value.children.len {
				if i > 0 {
					result += ','
				}
				if pretty {
					result += '\n' + '  '.repeat(depth + 1)
				}
				if is_object {
					result += json2.encode(value.keys[i].clone()) + ':'
					if pretty {
						result += ' '
					}
				}
				result += encode_value(&value.children[i], depth + 1, pretty)
			}
			if pretty && value.children.len > 0 {
				result += '\n' + '  '.repeat(depth)
			}
			result += if is_object { '}' } else { ']' }
			return result
		}
	}
}

// STUB: serde_json parser's JSON-whitespace scanning.
fn (mut parser Parser) skip_space() {
	for parser.position < parser.text.len && (*parser.text)[parser.position] in [` `, `\t`, `\r`,
		`\n`] {
		parser.position++
	}
}

// STUB: serde_json parser's byte consumption with end-of-input error.
fn (mut parser Parser) take() !u8 {
	if parser.position >= parser.text.len {
		return error('unexpected end of input')
	}
	value := (*parser.text)[parser.position]
	parser.position++
	return value
}

// STUB: serde_json parser's recursive Value decoding, including duplicate-key replacement.
fn (mut parser Parser) parse_value() !Value {
	parser.skip_space()
	if parser.position >= parser.text.len {
		return error('expected value')
	}
	ch := (*parser.text)[parser.position]
	if ch == `"` {
		return Value{ kind: .string_value, text: parser.parse_string()! }
	}
	if ch in [`{`, `[`] {
		parser.depth++
		if parser.depth >= 128 {
			return error('recursion limit exceeded')
		}
		parser.position++
		is_object := ch == `{`
		end := if is_object { u8(`}`) } else { u8(`]`) }
		mut children := []Value{}
		mut keys := []string{}
		parser.skip_space()
		if parser.position < parser.text.len && (*parser.text)[parser.position] == end {
			parser.position++
			parser.depth--
			return Value{ kind: if is_object { Kind.object } else { Kind.array } }
		}
		for {
			parser.skip_space()
			mut key := ''
			if is_object {
				key = parser.parse_string()!
				parser.skip_space()
				if parser.take()! != `:` {
					return error('expected colon')
				}
			}
			child := parser.parse_value()!
			if is_object {
				idx := keys.index(key)
				if idx >= 0 {
					children[idx] = child
				} else {
					keys << key
					children << child
				}
			} else {
				children << child
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
		parser.depth--
		return Value{ kind: if is_object { Kind.object } else { Kind.array }, children: children, keys: keys }
	}
	for literal in ['null', 'true', 'false'] {
		if parser.position + literal.len <= parser.text.len
			&& (*parser.text)[parser.position..parser.position + literal.len] == literal {
			parser.position += literal.len
			return Value{ kind: if literal == 'null' { Kind.null_value } else { Kind.boolean }, text: literal.clone() }
		}
	}
	return Value{ kind: .number, text: parser.parse_number()! }
}

// STUB: serde_json quoted-string decoding, including strict UTF-16 surrogate pairs.
fn (mut parser Parser) parse_string() !string {
	if parser.take()! != `"` {
		return error('expected string')
	}
	mut result := []u8{}
	for {
		ch := parser.take()!
		if ch == `"` {
			return result.bytestr()
		}
		if ch < 0x20 {
			return error('control character in string')
		}
		if ch != `\\` {
			result << ch
			continue
		}
		escaped := parser.take()!
		match escaped {
			`"`, `\\`, `/` { result << escaped }
			`b` { result << u8(8) }
			`f` { result << u8(12) }
			`n` { result << u8(10) }
			`r` { result << u8(13) }
			`t` { result << u8(9) }
			`u` {
				mut cp := parser.hex_quad()!
				if cp >= 0xd800 && cp <= 0xdbff {
					if parser.take()! != `\\` || parser.take()! != `u` {
						return error('missing low surrogate')
					}
					low := parser.hex_quad()!
					if low < 0xdc00 || low > 0xdfff {
						return error('invalid low surrogate')
					}
					cp = 0x10000 + ((cp - 0xd800) << 10) + low - 0xdc00
				} else if cp >= 0xdc00 && cp <= 0xdfff {
					return error('unexpected low surrogate')
				}
				result << rune(cp).str().bytes()
			}
			else { return error('invalid escape') }
		}
	}
	return error('unexpected end of string')
}

// STUB: serde_json parser's four-hex-digit Unicode escape.
fn (mut parser Parser) hex_quad() !u32 {
	mut value := u32(0)
	for _ in 0 .. 4 {
		ch := parser.take()!
		mut digit := u32(0)
		if ch >= `0` && ch <= `9` {
			digit = ch - `0`
		} else if ch >= `a` && ch <= `f` {
			digit = ch - `a` + 10
		} else if ch >= `A` && ch <= `F` {
			digit = ch - `A` + 10
		} else {
			return error('invalid unicode escape')
		}
		value = (value << 4) | digit
	}
	return value
}

// STUB: serde_json Number decoding, retaining exact integer values before falling back to finite f64.
fn (mut parser Parser) parse_number() !string {
	start := parser.position
	if parser.position < parser.text.len && (*parser.text)[parser.position] == `-` {
		parser.position++
	}
	first := parser.take()!
	if first < `0` || first > `9` {
		return error('invalid number')
	}
	if first != `0` {
		for parser.position < parser.text.len && (*parser.text)[parser.position] >= `0` && (*parser.text)[parser.position] <= `9` {
			parser.position++
		}
	}
	mut is_float := false
	if parser.position < parser.text.len && (*parser.text)[parser.position] == `.` {
		is_float = true
		parser.position++
		fraction_start := parser.position
		for parser.position < parser.text.len && (*parser.text)[parser.position] >= `0` && (*parser.text)[parser.position] <= `9` {
			parser.position++
		}
		if parser.position == fraction_start {
			return error('empty fraction')
		}
	}
	if parser.position < parser.text.len && (*parser.text)[parser.position] in [`e`, `E`] {
		is_float = true
		parser.position++
		if parser.position < parser.text.len && (*parser.text)[parser.position] in [
			`+`,
			`-`,
		] {
			parser.position++
		}
		exponent_start := parser.position
		for parser.position < parser.text.len && (*parser.text)[parser.position] >= `0` && (*parser.text)[parser.position] <= `9` {
			parser.position++
		}
		if parser.position == exponent_start {
			return error('empty exponent')
		}
	}
	token := (*parser.text)[start..parser.position]
	if !is_float && token != '-0' {
		if token.starts_with('-') {
			if integer := backend_banners_parse_i64(&token) {
				return integer.str()
			}
		} else if integer := strconv.parse_uint(token.clone(), 10, 64) {
			return integer.str()
		}
	}
	value := parse_float_token(&token)!
	if math.is_inf(value, 0) || math.is_nan(value) {
		return error('number out of range')
	}
	return format_float(value)
}

// STUB: serde_json's default (without float_roundtrip) mantissa parsing. The upstream
// parser deliberately stops collecting digits on u64 overflow; using atof64 instead
// changes observable JSON output for many high-precision decimals.
fn parse_float_token(token &string) !f64 {
	negative := token.starts_with('-')
	mut position := if negative { 1 } else { 0 }
	mut significand := u64(0)
	mut exponent := i64(0)
	mut overflowed := false
	for position < token.len && (*token)[position] >= `0` && (*token)[position] <= `9` {
		digit := u64((*token)[position] - `0`)
		if overflowed || significand > (u64(18446744073709551615) - digit) / 10 {
			overflowed = true
			exponent++
		} else {
			significand = significand * 10 + digit
		}
		position++
	}
	if position < token.len && (*token)[position] == `.` {
		position++
		overflowed = false
		for position < token.len && (*token)[position] >= `0` && (*token)[position] <= `9` {
			digit := u64((*token)[position] - `0`)
			if !overflowed && significand <= (u64(18446744073709551615) - digit) / 10 {
				significand = significand * 10 + digit
				exponent--
			} else {
				overflowed = true
			}
			position++
		}
	}
	if position < token.len {
		position++ // e or E, already validated by parse_number.
		positive_exp := position >= token.len || (*token)[position] != `-`
		if position < token.len && (*token)[position] in [`+`, `-`] { position++ }
		mut explicit_exp := i64(0)
		for position < token.len {
			digit := i64((*token)[position] - `0`)
			if explicit_exp > (i64(2147483647) - digit) / 10 {
				if significand != 0 && positive_exp {
					return error('number out of range')
				}
				return if negative { -f64(0) } else { f64(0) }
			}
			explicit_exp = explicit_exp * 10 + digit
			position++
		}
		exponent += if positive_exp { explicit_exp } else { -explicit_exp }
		if exponent > 2147483647 {
			exponent = 2147483647
		}
		if exponent < -2147483648 {
			exponent = -2147483648
		}
	}
	return f64_from_parts(!negative, significand, exponent)
}

// STUB: serde_json::Deserializer::f64_from_parts with its exact binary64 POW10 table.
fn f64_from_parts(positive bool, significand u64, decimal_exponent i64) !f64 {
	mut value := f64(significand)
	mut exponent := decimal_exponent
	for {
		absolute := if exponent < 0 { -exponent } else { exponent }
		if absolute < powers_of_ten.len {
			power := powers_of_ten[int(absolute)]
			if exponent >= 0 {
				value *= power
				if math.is_inf(value, 0) {
					return error('number out of range')
				}
			} else {
				value /= power
			}
			break
		}
		if value == 0 {
			break
		}
		if exponent >= 0 {
			return error('number out of range')
		}
		value /= 1e308
		exponent += 308
	}
	return if positive { value } else { -value }
}

// STUB: serde_json's shortest-roundtrip finite f64 rendering uses V's Ryū implementation,
// with the same decimal/scientific cutoffs as its float serializer.
fn format_float(value f64) string {
	if value == 0 {
		return if value.str().starts_with('-') { '-0.0' } else { '0.0' }
	}
	scientific := strconv.ftoa_64(value)
	parts := scientific.split('e')
	if parts.len != 2 {
		return scientific
	}
	exponent := int(backend_banners_parse_decimal_i64(&parts[1], true) or { 0 })
	negative := parts[0].starts_with('-')
	coefficient := if negative { parts[0][1..] } else { parts[0] }
	digits := coefficient.replace('.', '')
	sign := if negative { '-' } else { '' }
	if exponent >= -5 && exponent < 16 {
		point := exponent + 1
		if point <= 0 {
			return sign + '0.' + '0'.repeat(-point) + digits
		}
		if point >= digits.len {
			return sign + digits + '0'.repeat(point - digits.len) + '.0'
		}
		return sign + digits[..point] + '.' + digits[point..]
	}
	return sign + coefficient + 'e' + if exponent >= 0 { '+${exponent}' } else { '${exponent}' }
}

// STUB: serde_json default float parser powers of ten, indexed 0 through 308.
const powers_of_ten = [f64(1e000), 1e001, 1e002, 1e003, 1e004, 1e005, 1e006, 1e007, 1e008, 1e009,
	1e010, 1e011, 1e012, 1e013, 1e014, 1e015, 1e016, 1e017, 1e018, 1e019, 1e020, 1e021, 1e022,
	1e023, 1e024, 1e025, 1e026, 1e027, 1e028, 1e029, 1e030, 1e031, 1e032, 1e033, 1e034, 1e035,
	1e036, 1e037, 1e038, 1e039, 1e040, 1e041, 1e042, 1e043, 1e044, 1e045, 1e046, 1e047, 1e048,
	1e049, 1e050, 1e051, 1e052, 1e053, 1e054, 1e055, 1e056, 1e057, 1e058, 1e059, 1e060, 1e061,
	1e062, 1e063, 1e064, 1e065, 1e066, 1e067, 1e068, 1e069, 1e070, 1e071, 1e072, 1e073, 1e074,
	1e075, 1e076, 1e077, 1e078, 1e079, 1e080, 1e081, 1e082, 1e083, 1e084, 1e085, 1e086, 1e087,
	1e088, 1e089, 1e090, 1e091, 1e092, 1e093, 1e094, 1e095, 1e096, 1e097, 1e098, 1e099, 1e100,
	1e101, 1e102, 1e103, 1e104, 1e105, 1e106, 1e107, 1e108, 1e109, 1e110, 1e111, 1e112, 1e113,
	1e114, 1e115, 1e116, 1e117, 1e118, 1e119, 1e120, 1e121, 1e122, 1e123, 1e124, 1e125, 1e126,
	1e127, 1e128, 1e129, 1e130, 1e131, 1e132, 1e133, 1e134, 1e135, 1e136, 1e137, 1e138, 1e139,
	1e140, 1e141, 1e142, 1e143, 1e144, 1e145, 1e146, 1e147, 1e148, 1e149, 1e150, 1e151, 1e152,
	1e153, 1e154, 1e155, 1e156, 1e157, 1e158, 1e159, 1e160, 1e161, 1e162, 1e163, 1e164, 1e165,
	1e166, 1e167, 1e168, 1e169, 1e170, 1e171, 1e172, 1e173, 1e174, 1e175, 1e176, 1e177, 1e178,
	1e179, 1e180, 1e181, 1e182, 1e183, 1e184, 1e185, 1e186, 1e187, 1e188, 1e189, 1e190, 1e191,
	1e192, 1e193, 1e194, 1e195, 1e196, 1e197, 1e198, 1e199, 1e200, 1e201, 1e202, 1e203, 1e204,
	1e205, 1e206, 1e207, 1e208, 1e209, 1e210, 1e211, 1e212, 1e213, 1e214, 1e215, 1e216, 1e217,
	1e218, 1e219, 1e220, 1e221, 1e222, 1e223, 1e224, 1e225, 1e226, 1e227, 1e228, 1e229, 1e230,
	1e231, 1e232, 1e233, 1e234, 1e235, 1e236, 1e237, 1e238, 1e239, 1e240, 1e241, 1e242, 1e243,
	1e244, 1e245, 1e246, 1e247, 1e248, 1e249, 1e250, 1e251, 1e252, 1e253, 1e254, 1e255, 1e256,
	1e257, 1e258, 1e259, 1e260, 1e261, 1e262, 1e263, 1e264, 1e265, 1e266, 1e267, 1e268, 1e269,
	1e270, 1e271, 1e272, 1e273, 1e274, 1e275, 1e276, 1e277, 1e278, 1e279, 1e280, 1e281, 1e282,
	1e283, 1e284, 1e285, 1e286, 1e287, 1e288, 1e289, 1e290, 1e291, 1e292, 1e293, 1e294, 1e295,
	1e296, 1e297, 1e298, 1e299, 1e300, 1e301, 1e302, 1e303, 1e304, 1e305, 1e306, 1e307, 1e308]
