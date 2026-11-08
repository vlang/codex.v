module serde_json

// STUB: serde_json::Value's PartialEq compares owned contents recursively.
// V's generated equality currently compares backing storage for these recursive
// arrays; explicit shared comparison preserves independently cloned JSON values.
pub fn (left &Value) equals(right &Value) bool {
	if left.kind != right.kind {
		return false
	}
	match left.kind {
		.null_value { return true }
		.boolean, .string_value { return left.text == right.text }
		.number {
			// Number text is normalized by the parser. serde_json keeps integers
			// distinct from floats, while its finite f64 equality ignores zero's sign.
			return left.text == right.text
				|| (left.text in ['0.0', '-0.0'] && right.text in ['0.0', '-0.0'])
		}
		.array {
			if left.children.len != right.children.len {
				return false
			}
			for index in 0 .. left.children.len {
				if !(&left.children[index]).equals(&right.children[index]) {
					return false
				}
			}
			return true
		}
		.object {
			if left.keys.len != right.keys.len {
				return false
			}
			for index in 0 .. left.keys.len {
				value := right.get(&left.keys[index])
				if !value.has_value || !(&left.children[index]).equals(value.value) {
					return false
				}
			}
			return true
		}
	}
}
