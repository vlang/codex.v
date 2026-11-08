// Shared UI constants for layout and alignment within the TUI.
module ui_consts

// Width (in terminal columns) reserved for the left gutter/prefix used by
// live cells and aligned widgets.
//
// Semantics:
// - Chat composer reserves this many columns for the left border + padding.
// - Status indicator lines begin with this many spaces for alignment.
// - User history lines account for this many columns (e.g., "▌ ") when wrapping.
// V exports these constants across modules; Rust restricts them to this crate.
pub const live_prefix_cols = u16(2)
pub const footer_indent_cols = usize(live_prefix_cols)
// The literal retains static storage, matching Rust's borrowed static string.
pub const transcript_hint = 'ctrl + t to view transcript'
