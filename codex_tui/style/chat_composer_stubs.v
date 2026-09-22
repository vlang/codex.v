module style

import ratatui.style as rat_style

// STUB: crate::style::user_message_style. Terminal palette probing remains in its source owner;
// this target boundary retains the light-palette composer surface observed by the source tests.
pub fn user_message_style() rat_style.Style {
	return rat_style.Style{
		background: rat_style.RgbColor{ r: 244, g: 244, b: 244 }
	}
}
