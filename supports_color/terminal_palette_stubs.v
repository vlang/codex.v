module supports_color

// STUB: supports_color::Stream. Terminal capability detection belongs to the external
// `supports-color` crate.
pub enum Stream {
	stdout
	stderr
}

// STUB: supports_color::ColorLevel fields observed by `terminal_palette::stdout_color_level`.
pub struct ColorLevel {
pub:
	level     usize
	has_basic bool
	has_256   bool
	has_16m   bool
}

// STUB: supports_color::on_cached. The crate's environment and tty capability detection is not
// ported, so no color support is reported; callers map that to their unknown color level.
pub fn on_cached(stream Stream) ?ColorLevel {
	_ = stream
	return none
}
