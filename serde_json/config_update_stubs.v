module serde_json

// STUB: serde_json::Value::as_str returns a borrowed string view. The explicit
// presence tag avoids V's unsupported optional resource-bearing references.
pub struct BorrowedString {
pub:
	has_value bool
	value     &string = unsafe { nil }
}

// STUB: Value::as_str observes its original string storage without cloning.
pub fn (value &Value) as_str() BorrowedString {
	if value.kind == .string_value { return BorrowedString{ has_value: true, value: &value.text } }
	return BorrowedString{}
}

// STUB: serde_json's indexing returns a shared null value for missing/non-object
// keys, preserving distinctions between indexing, get(), and string extraction.
const config_update_null = &Value{}

// STUB: Value's Index<&str> API remains borrowed through nested object lookups.
pub fn (value &Value) index(name &string) &Value {
	entry := value.get(name)
	if entry.has_value { return entry.value }
	return config_update_null
}

// STUB: Value::as_object's optional shared map view. Iteration borrows original
// keys/values rather than cloning a key list at a boundary Rust does not clone.
pub struct BorrowedObject {
pub:
	has_value bool
	value     &Value = unsafe { nil }
}

// STUB: Value::as_object preserves both object presence and borrowed storage.
pub fn (value &Value) as_object() BorrowedObject {
	if value.kind == .object { return BorrowedObject{ has_value: true, value: value } }
	return BorrowedObject{}
}

// STUB: as_object().into_iter().flatten() has no entries when no object exists.
pub fn (object &BorrowedObject) len() int {
	return if object.has_value { object.value.keys.len } else { 0 }
}

// STUB: map entry iterator's shared key; its index is bounded by len().
pub fn (object &BorrowedObject) key(index int) &string {
	assert index >= 0 && index < object.len()
	return &object.value.keys[index]
}

// STUB: the optional shared map's get operation borrows the selected value.
pub fn (object &BorrowedObject) get(name &string) BorrowedValue {
	if object.has_value { return object.value.get(name) }
	return BorrowedValue{}
}
