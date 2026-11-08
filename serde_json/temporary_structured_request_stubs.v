module serde_json

// STUB: serde_json::Value::from(bool), retaining a JSON boolean rather than text.
pub fn Value.boolean(value bool) Value {
	return Value{ kind: .boolean, text: if value { 'true' } else { 'false' } }
}

// STUB: serde_json::Value::from(String) consumes the owned string.
pub fn Value.string(value string) Value {
	return Value{ kind: .string_value, text: value }
}

// STUB: serde_json::Value::Object consumes an owned JSON object.
pub fn Value.object(values map[string]Value) Value {
	mut keys := []string{cap: values.len}
	mut children := []Value{cap: values.len}
	for key, value in values {
		keys << key
		children << value
	}
	return Value{ kind: .object, keys: keys, children: children }
}

// STUB: Value's derived Clone owns all strings and recursively owns its children.
pub fn (value &Value) clone() Value {
	mut children := []Value{cap: value.children.len}
	for index in 0 .. value.children.len {
		children << (&value.children[index]).clone()
	}
	return Value{ kind: value.kind, text: value.text.clone(), keys: value.keys.clone(), children: children }
}

// STUB: the observed Value::as_object().keys().cloned() boundary. None preserves
// a non-object value; returned keys are owned exactly as the Rust cloned iterator.
pub fn (value &Value) object_keys() ?[]string {
	if value.kind != .object {
		return none
	}
	return value.keys.clone()
}

// STUB: Value::as_bool returns an allocation-free optional scalar.
pub fn (value &Value) as_bool() ?bool {
	if value.kind != .boolean {
		return none
	}
	return value.text == 'true'
}

// STUB: borrowed Value object lookup, guarded so an absent entry never forms an
// optional resource-bearing reference (unsupported by V's C generator).
pub struct BorrowedValue {
pub:
	has_value bool
	value     &Value = unsafe { nil }
}

// STUB: Value::get retains its owner's storage and never clones the payload.
pub fn (value &Value) get(name &string) BorrowedValue {
	if value.kind == .object {
		for index in 0 .. value.keys.len {
			if value.keys[index] == *name {
				return BorrowedValue{ has_value: true, value: &value.children[index] }
			}
		}
	}
	return BorrowedValue{}
}
