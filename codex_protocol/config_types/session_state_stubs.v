module config_types

// STUB: protocol/src/config_types.rs::Settings's derived Clone preserves all
// settings and allocates independent storage for owned strings.
pub fn (settings &Settings) clone() Settings {
	return Settings{
		model:                  settings.model.clone()
		reasoning_effort:       settings.reasoning_effort
		developer_instructions: if text := settings.developer_instructions {
			text.clone()
		} else {
			none
		}
	}
}

// STUB: protocol/src/config_types.rs::CollaborationMode's derived Clone.
pub fn (mode &CollaborationMode) clone() CollaborationMode {
	return CollaborationMode{ mode: mode.mode, settings: mode.settings.clone() }
}
