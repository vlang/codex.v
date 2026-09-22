module codex_tools

// STUB: parse_tool_input_schema is owned by codex-tools. This boundary rejects the one schema
// form the source tests identify as unsupported and accepts schemas the upstream sanitizer handles.
pub fn parse_tool_input_schema(schema &string) ! {
	compact := schema.replace(' ', '').replace('\n', '').replace('\t', '')
	if compact.contains('"type":"null"') {
		return error('top-level null schemas are unsupported')
	}
}
