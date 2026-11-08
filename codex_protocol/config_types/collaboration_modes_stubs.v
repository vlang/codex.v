module config_types

// STUB: protocol/src/config_types.rs::ModeKind::is_tui_visible. Preserve the
// existing legacy variant storage, while accepting only the source's visible kinds.
pub fn (kind ModeKind) is_tui_visible() bool {
	return kind in [.default_mode, .plan]
}
