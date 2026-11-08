module codex_features

// STUB: Feature is owned by codex-features and enumerates runtime feature gates observed by
// app-server/thread_processor.rs and tui/service_tier_resolution.rs.
pub enum Feature {
	goals
	windows_sandbox
	windows_sandbox_elevated
	// Enable Fast mode selection in the TUI and request layer.
	fast_mode
	// STUB: codex-features::Feature::TerminalVisualizationInstructions gates terminal visuals.
	terminal_visualization_instructions
	// STUB: codex-features::Feature::Psp controls the resolved HTTP routing cookie.
	psp
}

// STUB: Features is owned by codex-features and carries the resolved feature set.
pub struct Features {
pub:
	enabled_features []Feature
}

// STUB: codex_features::Features::enabled queries one resolved feature gate.
pub fn (features &Features) enabled(feature Feature) bool {
	return feature in features.enabled_features
}
