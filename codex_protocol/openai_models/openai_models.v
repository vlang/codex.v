module openai_models

// STUB: Reasoning effort configuration.
pub enum ReasoningEffort {
	none
	minimal
	low
	medium
	high
	xhigh
	max
	ultra
	persistent
	custom
}

// STUB: Truncation mode configuration.
pub enum TruncationMode {
	bytes
	tokens
}

// STUB: Truncation configuration.
pub struct TruncationPolicyConfig {
pub:
	mode  TruncationMode
	limit u64
}
