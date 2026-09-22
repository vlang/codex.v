module mcp

// STUB: MCP request IDs may be string or numeric on the wire.
pub struct RequestId {
pub:
	value string
}

// STUB: MCP tool result content is translated with the MCP module.
pub struct CallToolResult {
pub:
	content  []string
	is_error ?bool
}
