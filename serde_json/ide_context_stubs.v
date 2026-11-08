module serde_json

// STUB: serde_json::from_value consumes a Value and invokes the target's explicit
// Deserialize implementation. V cannot invoke a generic static method, so its
// typed callback explicitly supplies the derive without importing the target.
pub fn from_value[T](value Value, deserialize fn (&Value) !T) !T {
	return deserialize(&value)
}

// STUB: serde_json::Value::is_object observes the existing typed JSON owner.
pub fn (value &Value) is_object() bool {
	return value.kind == .object
}

// STUB: serde_json::Value::is_array observes the existing typed JSON owner.
pub fn (value &Value) is_array() bool {
	return value.kind == .array
}

// STUB: Value::as_array().len() without cloning the borrowed array.
pub fn (value &Value) array_len() !int {
	if value.kind != .array {
		return error('invalid type, expected a sequence')
	}
	return value.children.len
}

// STUB: Value::get(usize) retains the owner's element storage. The existing
// BorrowedValue wrapper avoids V's unsupported optional resource-bearing refs.
pub fn (value &Value) get_index(index int) BorrowedValue {
	if value.kind == .array && index >= 0 && index < value.children.len {
		return BorrowedValue{ has_value: true, value: &value.children[index] }
	}
	return BorrowedValue{}
}

// STUB: serde_json::Value::as_u64 accepts only nonnegative integer Numbers;
// integral-looking f64 values retain their distinct serde_json number type.
pub fn (value &Value) as_u64() ?u64 {
	if value.kind != .number || value.text.len == 0 {
		return none
	}
	mut number := u64(0)
	for byte in value.text {
		if byte < `0` || byte > `9` {
			return none
		}
		digit := u64(byte - `0`)
		if number > (~u64(0) - digit) / 10 {
			return none
		}
		number = number * 10 + digit
	}
	return number
}
