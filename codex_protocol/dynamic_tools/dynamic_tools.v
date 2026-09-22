module dynamic_tools

import x.json2

// STUB: Dynamic tool output content item.
pub struct DynamicToolCallOutputContentItem {
pub:
	text string
}

// STUB: Dynamic tool request.
pub struct DynamicToolCallRequest {
pub:
	call_id string
}

// STUB: Dynamic tool response.
pub struct DynamicToolResponse {
pub:
	success bool
}

// STUB: Dynamic tool specification.
pub struct DynamicToolSpec {
pub:
	namespace     string
	name          string
	description   string
	input_schema  json2.Any
	defer_loading bool
}

// STUB: Legacy dynamic-tool normalization is deferred to the dynamic_tools module translation.
pub fn deserialize_dynamic_tool_specs(value json2.Any) ![]DynamicToolSpec {
	_ = value
	return []DynamicToolSpec{}
}
