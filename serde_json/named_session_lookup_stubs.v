module serde_json

// STUB: serde_json::Value::Array consumes owned JSON values for rollout fixtures.
pub fn Value.array_value(values []Value) Value {
	return Value{ kind: .array, children: values }
}
