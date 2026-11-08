module terminal_probe

import codex_tui.color
import time

// STUB: crate::terminal_probe::DEFAULT_TIMEOUT, the default wall-clock budget for each startup
// probe group.
pub const default_timeout = 100 * time.millisecond

// STUB: crate::terminal_probe::DefaultColors, the default terminal foreground and background
// colors reported by OSC 10 and OSC 11.
pub struct DefaultColors {
pub:
	// Default foreground color as an 8-bit RGB tuple.
	fg color.Rgb
	// Default background color as an 8-bit RGB tuple.
	bg color.Rgb
}

// STUB: OptionalDefaultColors preserves the `Option<DefaultColors>` success value of Rust's
// `io::Result<Option<DefaultColors>>`; V cannot nest an option directly inside a result.
pub struct OptionalDefaultColors {
pub:
	has_value bool
	value     DefaultColors
}

// STUB: crate::terminal_probe::default_colors. The OSC 10/11 tty probe is owned by the
// untranslated terminal_probe module; until it is ported the probe reports no response.
pub fn default_colors(timeout time.Duration) !OptionalDefaultColors {
	_ = timeout
	return OptionalDefaultColors{}
}
