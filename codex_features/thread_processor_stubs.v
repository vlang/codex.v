module codex_features

// STUB: Feature is owned by codex-features and enumerates runtime feature gates observed by
// app-server/thread_processor.rs.
pub enum Feature {
	goals
	windows_sandbox
	windows_sandbox_elevated
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
