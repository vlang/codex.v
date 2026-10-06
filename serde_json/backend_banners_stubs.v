module serde_json

// STUB: serde_json::Value::as_i64 accepts only signed-range integer Numbers,
// including nonnegative u64-backed Numbers that fit i64. Float Numbers remain
// distinct even when their mathematical value is an integer.
pub fn (value &Value) as_i64() ?i64 {
	if value.kind != .number { return none }
	return backend_banners_parse_i64(&value.text)
}

// STUB: serde_json's integer Number parser borrows its token and detects range
// overflow. A local typed decoder avoids the compiler/strconv combination that
// consumes aliased sign-trimmed string storage during ownership execution.
fn backend_banners_parse_i64(text &string) ?i64 {
	return backend_banners_parse_decimal_i64(text, false)
}

// STUB: typed borrowed decimal parsing also serves the serializer's Ryū
// exponent, which may have a leading plus sign unlike a JSON integer token.
fn backend_banners_parse_decimal_i64(text &string, allow_plus bool) ?i64 {
	if text.len == 0 { return none }
	negative := (*text)[0] == `-`
	start := if negative || (allow_plus && (*text)[0] == `+`) { 1 } else { 0 }
	if start == text.len { return none }
	limit := if negative { u64(9223372036854775808) } else { u64(9223372036854775807) }
	mut magnitude := u64(0)
	for index in start .. text.len {
		byte := (*text)[index]
		if byte < `0` || byte > `9` { return none }
		digit := u64(byte - `0`)
		if magnitude > (limit - digit) / 10 { return none }
		magnitude = magnitude * 10 + digit
	}
	if negative && magnitude == u64(9223372036854775808) { return i64(-9223372036854775807) - 1 }
	return if negative { -i64(magnitude) } else { i64(magnitude) }
}

// STUB: Value's IndexMut<&str> observes the same object entry as Rust indexing.
// The caller must end this mutable view before reallocating its parent object.
pub fn (mut value Value) index_mut(name &string) &Value {
	if value.kind == .object {
		for index in 0 .. value.keys.len {
			if value.keys[index] == *name { return unsafe { &value.children[index] } }
		}
	}
	panic('mutable JSON indexing requires an existing object entry')
}

// STUB: Value::as_array_mut's optional borrowed vector is represented with an
// explicit presence tag because V cannot safely return an optional owned ref.
pub struct MutableArray {
pub:
	has_value bool
mut:
	value &Value = unsafe { nil }
}

// STUB: Value::as_array_mut retains the original array without cloning it.
pub fn (mut value Value) as_array_mut() MutableArray {
	if value.kind == .array { return MutableArray{ has_value: true, value: &value } }
	return MutableArray{}
}

// STUB: Vec<Value>::push consumes the new element while mutating its owner.
pub fn (mut array MutableArray) push(value Value) {
	assert array.has_value
	array.value.children << value
}

// STUB: Value::as_object_mut's optional map view uses a presence tag for V's
// resource-bearing optional-reference limitation.
pub struct MutableObject {
pub:
	has_value bool
mut:
	value &Value = unsafe { nil }
}

// STUB: Value::as_object_mut retains the original object without cloning it.
pub fn (mut value Value) as_object_mut() MutableObject {
	if value.kind == .object { return MutableObject{ has_value: true, value: &value } }
	return MutableObject{}
}

// STUB: serde_json::Map::extend consumes the incoming entries, replacing an
// existing key in place and appending new keys in the incoming iteration order.
pub fn (mut object MutableObject) extend(values map[string]Value) {
	assert object.has_value
	for key, value in values {
		object.value.insert_backend_banner_entry(key, value)
	}
}

// STUB: Map::insert's replacement/append implementation used by extend. An
// early return keeps each owned input in exactly one mutation branch.
fn (mut object Value) insert_backend_banner_entry(key string, value Value) {
	for index in 0 .. object.keys.len {
		if object.keys[index] == key {
			object.children[index] = value
			return
		}
	}
	object.keys << key
	object.children << value
}

// STUB: serde_json::Map's Clone returns owned keys and recursively owned JSON
// children at the source test's explicit as_object().unwrap().clone boundary.
pub fn (object &BorrowedObject) clone() map[string]Value {
	assert object.has_value
	mut result := map[string]Value{}
	for index in 0 .. object.len() {
		key := object.key(index)
		value := object.get(key)
		result[key.clone()] = value.value.clone()
	}
	return result
}
