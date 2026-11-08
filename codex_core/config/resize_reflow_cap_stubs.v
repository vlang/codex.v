module config

// STUB: discriminant of codex_core::config::TerminalResizeReflowMaxRows in core/src/config/mod.rs.
pub enum TerminalResizeReflowMaxRowsKind {
	// Use the runtime terminal detector to choose a scrollback-sized cap.
	auto
	// Keep all rendered transcript rows during resize reflow.
	disabled
	// Keep at most this many rendered transcript rows during resize reflow.
	limit
}

// STUB: codex_core::config::TerminalResizeReflowMaxRows. Rust's Copy payload enum uses this
// allocation-free explicit tag and usize payload; its zero-value default is Auto.
pub struct TerminalResizeReflowMaxRows {
pub:
	kind  TerminalResizeReflowMaxRowsKind = .auto
	limit usize
}

// STUB: codex_core::config::TerminalResizeReflowConfig. The source derives Copy and Default;
// this allocation-free value has the same automatic row-limit default.
pub struct TerminalResizeReflowConfig {
pub:
	max_rows TerminalResizeReflowMaxRows
}
