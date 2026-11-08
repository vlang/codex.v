module tracing

import ratatui.layout

// STUB: tracing::warn!(%error, "Failed to start terminal size monitor"). Subscriber
// routing remains untranslated; the complete error/context stays at this typed boundary.
pub fn warn_start_size_monitor(failure &IError) {
	_ = failure
}

// STUB: tracing::debug!(?size, "Recovered terminal size from background check").
pub fn debug_recovered_terminal_size(size layout.Size) {
	_ = size
}
