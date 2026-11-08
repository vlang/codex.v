module config_types

import codex_protocol

// STUB: protocol/src/config_types.rs::CollaborationModeMask.
// V cannot nest options, so existing typed protocol wrappers retain preserve, clear, and set states.
pub struct CollaborationModeMask {
pub mut:
	name                   string
	mode                   ?ModeKind
	model                  ?string
	reasoning_effort       codex_protocol.OptionalReasoningEffort
	developer_instructions codex_protocol.OptionalString
}

// STUB: The derived Clone operation on protocol/src/config_types.rs::CollaborationModeMask.
pub fn (mask &CollaborationModeMask) clone() CollaborationModeMask {
	model := if value := mask.model { ?string(value.clone()) } else { ?string(none) }
	instructions := if value := mask.developer_instructions.value {
		?string(value.clone())
	} else {
		?string(none)
	}
	return CollaborationModeMask{
		name:                   mask.name.clone()
		mode:                   mask.mode
		model:                  model
		reasoning_effort:       mask.reasoning_effort
		developer_instructions: codex_protocol.OptionalString{
			is_set: mask.developer_instructions.is_set
			value:  instructions
		}
	}
}
