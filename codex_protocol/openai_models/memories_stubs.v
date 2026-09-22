module openai_models

// STUB: reasoning_effort_from_str mirrors ReasoningEffort's FromStr implementation in
// protocol/src/openai_models.rs. The existing tagged enum cannot retain the payload of custom
// values until that external owner is fully translated.
pub fn reasoning_effort_from_str(value &string) !ReasoningEffort {
	return match *value {
		'none' { .none }
		'minimal' { .minimal }
		'low' { .low }
		'medium' { .medium }
		'high' { .high }
		'xhigh' { .xhigh }
		'max' { .max }
		'ultra' { .ultra }
		'persistent' { .persistent }
		'' { error('reasoning effort must not be empty') }
		else { .custom }
	}
}
