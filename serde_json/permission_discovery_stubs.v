module serde_json

// STUB: serde_json::Value::is_string is a borrowed, allocation-free type check.
pub fn (value &Value) is_string() bool {
	return value.kind == .string_value
}
