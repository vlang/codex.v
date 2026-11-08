module terminal_palette

import codex_terminal_detection
import codex_tui.color
import codex_tui.terminal_probe
import os
import ratatui.style
import supports_color
import sync

pub enum StdoutColorLevel {
	true_color
	ansi256
	ansi16
	unknown
}

pub fn stdout_color_level() StdoutColorLevel {
	if level := supports_color.on_cached(.stdout) {
		if level.has_16m {
			return .true_color
		}
		if level.has_256 {
			return .ansi256
		}
		return .ansi16
	}
	return .unknown
}

pub fn rgb_color(rgb color.Rgb) style.Color {
	return style.Color.rgb(rgb.r, rgb.g, rgb.b)
}

pub fn indexed_color(index u8) style.Color {
	return style.Color.indexed(index)
}

// Returns the closest color to the target color that the terminal can display.
pub fn best_color(target color.Rgb) style.Color {
	return best_color_for_color_level(target, effective_stdout_color_level())
}

// Returns the closest color to the target color for a known terminal color level.
pub fn best_color_for_level(target color.Rgb, color_level StdoutColorLevel) style.Color {
	return best_color_for_color_level(target, color_level)
}

pub fn effective_stdout_color_level() StdoutColorLevel {
	$if test {
		if test_default_colors.value != none {
			return .true_color
		}
	}

	return stdout_color_level_for_terminal(stdout_color_level(), codex_terminal_detection.terminal_info().name,
		os.getenv_opt('WT_SESSION') != none, os.getenv_opt('FORCE_COLOR') != none)
}

fn stdout_color_level_for_terminal(stdout_level StdoutColorLevel, terminal_name codex_terminal_detection.TerminalName, has_wt_session bool, has_force_color_override bool) StdoutColorLevel {
	if has_wt_session && !has_force_color_override {
		return .true_color
	}

	if stdout_level == .ansi16 && terminal_name == .windows_terminal && !has_force_color_override {
		return .true_color
	} else {
		return stdout_level
	}
}

fn best_color_for_color_level(target color.Rgb, color_level StdoutColorLevel) style.Color {
	return match color_level {
		.true_color {
			rgb_color(target)
		}
		.ansi256 {
			// Rust's `Iterator::min_by` keeps the earlier candidate unless it compares `Greater`;
			// incomparable (NaN) distances fall back to `Ordering::Equal`, which `>` also rejects.
			mut best := ?XtermColorEntry(none)
			for candidate in xterm_fixed_colors() {
				if current := best {
					if color.perceptual_distance(current.rgb, target) > color.perceptual_distance(candidate.rgb,
						target) {
						best = candidate
					}
				} else {
					best = candidate
				}
			}
			if found := best {
				indexed_color(u8(found.index))
			} else {
				style.Color{}
			}
		}
		.ansi16, .unknown {
			style.Color{}
		}
	}
}

pub struct DefaultColors {
	fg color.Rgb
	bg color.Rgb
}

// Rust keeps this override in a test-only `thread_local!` `Cell<Option<DefaultColors>>`. V has
// no thread-local statics, so the cell is a module-level heap value that is only consulted in
// `$if test` builds; V runs the test functions of one test binary sequentially on one thread.
@[heap]
struct TestDefaultColorsCell {
mut:
	value ?DefaultColors
}

const test_default_colors = &TestDefaultColorsCell{}

pub fn default_colors() ?DefaultColors {
	$if test {
		if colors := test_default_colors.value {
			return colors
		}
	}

	return imp_default_colors()
}

// Scope a truecolor terminal palette to the current test thread while rendering a real widget.
//
// Rust compiles this helper only for tests. V cannot remove a declaration under `$if test`, so it
// is always available, but the override it installs is only read by test builds.
pub fn with_test_default_colors[T](colors terminal_probe.DefaultColors, render fn () T) T {
	mut override_colors := unsafe { test_default_colors }
	previous := override_colors.value
	override_colors.value = DefaultColors{
		fg: colors.fg
		bg: colors.bg
	}
	result := render()
	override_colors.value = previous
	return result
}

pub fn default_fg() ?color.Rgb {
	if colors := default_colors() {
		return colors.fg
	}
	return none
}

pub fn default_bg() ?color.Rgb {
	if colors := default_colors() {
		return colors.bg
	}
	return none
}

// Rust declares this for `cfg(any(unix, windows))` targets only. V has no declaration-level
// target filter here, so the other targets fall through to the no-op implementation.
pub fn set_default_colors_from_startup_probe(colors ?terminal_probe.DefaultColors) {
	imp_set_default_colors_from_startup_probe(colors)
}

// Rust selects one of three `imp` modules:
// - `cfg(all(unix, not(test)))` and `cfg(windows)`: the startup-probe cache below;
// - every other configuration (including unix test builds): no terminal colors and a no-op probe
//   setter.
// V selects the same implementation with compile-time conditions on each entry point.
fn imp_default_colors() ?DefaultColors {
	$if windows {
		return imp_cached_default_colors()
	} $else $if unix && !test {
		return imp_cached_default_colors()
	}
	return none
}

fn imp_set_default_colors_from_startup_probe(colors ?terminal_probe.DefaultColors) {
	$if windows {
		imp_cache_default_colors_from_startup_probe(colors)
	} $else $if unix && !test {
		imp_cache_default_colors_from_startup_probe(colors)
	} $else {
		_ = colors
	}
}

struct Cache[T] {
mut:
	attempted bool
	value     ?T
}

// Rust implements `Default` for `Cache<T>`; V's zero value is the same unattempted, empty cache.
fn Cache.default[T]() Cache[T] {
	return Cache[T]{
		attempted: false
		value:     none
	}
}

fn (mut cache Cache[T]) get_or_init_with[T](init fn () ?T) ?T {
	if !cache.attempted {
		cache.value = init()
		cache.attempted = true
	}
	return cache.value
}

// Rust stores the cache in a lazily initialized `OnceLock<Mutex<Cache<DefaultColors>>>`. The V
// cache is a module-level heap value created at module initialization; creating an empty cache
// and mutex has no side effects, so eager initialization is observably the same.
@[heap]
struct DefaultColorsCache {
mut:
	mutex &sync.Mutex = sync.new_mutex()
	cache Cache[DefaultColors]
}

const default_colors_cache_instance = &DefaultColorsCache{
	cache: Cache.default[DefaultColors]()
}

fn default_colors_cache() &DefaultColorsCache {
	return default_colors_cache_instance
}

// Rust returns `None` when the cache mutex is poisoned. V mutexes have no poisoning, so the lock
// always succeeds.
fn imp_cached_default_colors() ?DefaultColors {
	mut cache := unsafe { default_colors_cache() }
	cache.mutex.lock()
	colors := cache.cache.get_or_init_with(query_default_colors)
	cache.mutex.unlock()
	return colors
}

fn imp_cache_default_colors_from_startup_probe(colors ?terminal_probe.DefaultColors) {
	mut cache := unsafe { default_colors_cache() }
	cache.mutex.lock()
	if probe_colors := colors {
		cache.cache.value = DefaultColors{
			fg: probe_colors.fg
			bg: probe_colors.bg
		}
	} else {
		cache.cache.value = none
	}
	cache.cache.attempted = true
	cache.mutex.unlock()
}

// Queries terminal default colors through the bounded startup probe path.
//
// The palette cache treats `None` as an attempted-but-unavailable result, so this function
// collapses I/O errors and missing responses into the same fallback path used for terminals
// that simply do not support OSC 10/11 queries.
fn query_default_colors() ?DefaultColors {
	probe := terminal_probe.default_colors(terminal_probe.default_timeout) or { return none }
	if !probe.has_value {
		return none
	}
	return DefaultColors{
		fg: probe.value.fg
		bg: probe.value.bg
	}
}

// Named stand-in for the `(usize, (u8, u8, u8))` items of Rust's enumerated color iterator.
struct XtermColorEntry {
	index int
	rgb   color.Rgb
}

// The subset of Xterm colors that are usually consistent across terminals.
//
// Rust returns a lazy `enumerate().skip(16)` iterator; V materializes the same ordered entries.
fn xterm_fixed_colors() []XtermColorEntry {
	mut colors := []XtermColorEntry{cap: xterm_colors.len - 16}
	for index, rgb in xterm_colors {
		if index < 16 {
			continue
		}
		colors << XtermColorEntry{
			index: index
			rgb:   rgb
		}
	}
	return colors
}

// Xterm colors; derived from https://ss64.com/bash/syntax-colors.html
pub const xterm_colors = [
	// The first 16 colors vary based on terminal theme, so these are likely not the actual colors
	// that are displayed when using these indices.
	color.Rgb{0, 0, 0}, //   0 Black (SYSTEM)
	color.Rgb{128, 0, 0}, //   1 Maroon (SYSTEM)
	color.Rgb{0, 128, 0}, //   2 Green (SYSTEM)
	color.Rgb{128, 128, 0}, //   3 Olive (SYSTEM)
	color.Rgb{0, 0, 128}, //   4 Navy (SYSTEM)
	color.Rgb{128, 0, 128}, //   5 Purple (SYSTEM)
	color.Rgb{0, 128, 128}, //   6 Teal (SYSTEM)
	color.Rgb{192, 192, 192}, //   7 Silver (SYSTEM)
	color.Rgb{128, 128, 128}, //   8 Grey (SYSTEM)
	color.Rgb{255, 0, 0}, //   9 Red (SYSTEM)
	color.Rgb{0, 255, 0}, //  10 Lime (SYSTEM)
	color.Rgb{255, 255, 0}, //  11 Yellow (SYSTEM)
	color.Rgb{0, 0, 255}, //  12 Blue (SYSTEM)
	color.Rgb{255, 0, 255}, //  13 Fuchsia (SYSTEM)
	color.Rgb{0, 255, 255}, //  14 Aqua (SYSTEM)
	color.Rgb{255, 255, 255}, //  15 White (SYSTEM)
	// The rest of the colors are consistent in most terminals.
	color.Rgb{0, 0, 0}, //  16 Grey0
	color.Rgb{0, 0, 95}, //  17 NavyBlue
	color.Rgb{0, 0, 135}, //  18 DarkBlue
	color.Rgb{0, 0, 175}, //  19 Blue3
	color.Rgb{0, 0, 215}, //  20 Blue3
	color.Rgb{0, 0, 255}, //  21 Blue1
	color.Rgb{0, 95, 0}, //  22 DarkGreen
	color.Rgb{0, 95, 95}, //  23 DeepSkyBlue4
	color.Rgb{0, 95, 135}, //  24 DeepSkyBlue4
	color.Rgb{0, 95, 175}, //  25 DeepSkyBlue4
	color.Rgb{0, 95, 215}, //  26 DodgerBlue3
	color.Rgb{0, 95, 255}, //  27 DodgerBlue2
	color.Rgb{0, 135, 0}, //  28 Green4
	color.Rgb{0, 135, 95}, //  29 SpringGreen4
	color.Rgb{0, 135, 135}, //  30 Turquoise4
	color.Rgb{0, 135, 175}, //  31 DeepSkyBlue3
	color.Rgb{0, 135, 215}, //  32 DeepSkyBlue3
	color.Rgb{0, 135, 255}, //  33 DodgerBlue1
	color.Rgb{0, 175, 0}, //  34 Green3
	color.Rgb{0, 175, 95}, //  35 SpringGreen3
	color.Rgb{0, 175, 135}, //  36 DarkCyan
	color.Rgb{0, 175, 175}, //  37 LightSeaGreen
	color.Rgb{0, 175, 215}, //  38 DeepSkyBlue2
	color.Rgb{0, 175, 255}, //  39 DeepSkyBlue1
	color.Rgb{0, 215, 0}, //  40 Green3
	color.Rgb{0, 215, 95}, //  41 SpringGreen3
	color.Rgb{0, 215, 135}, //  42 SpringGreen2
	color.Rgb{0, 215, 175}, //  43 Cyan3
	color.Rgb{0, 215, 215}, //  44 DarkTurquoise
	color.Rgb{0, 215, 255}, //  45 Turquoise2
	color.Rgb{0, 255, 0}, //  46 Green1
	color.Rgb{0, 255, 95}, //  47 SpringGreen2
	color.Rgb{0, 255, 135}, //  48 SpringGreen1
	color.Rgb{0, 255, 175}, //  49 MediumSpringGreen
	color.Rgb{0, 255, 215}, //  50 Cyan2
	color.Rgb{0, 255, 255}, //  51 Cyan1
	color.Rgb{95, 0, 0}, //  52 DarkRed
	color.Rgb{95, 0, 95}, //  53 DeepPink4
	color.Rgb{95, 0, 135}, //  54 Purple4
	color.Rgb{95, 0, 175}, //  55 Purple4
	color.Rgb{95, 0, 215}, //  56 Purple3
	color.Rgb{95, 0, 255}, //  57 BlueViolet
	color.Rgb{95, 95, 0}, //  58 Orange4
	color.Rgb{95, 95, 95}, //  59 Grey37
	color.Rgb{95, 95, 135}, //  60 MediumPurple4
	color.Rgb{95, 95, 175}, //  61 SlateBlue3
	color.Rgb{95, 95, 215}, //  62 SlateBlue3
	color.Rgb{95, 95, 255}, //  63 RoyalBlue1
	color.Rgb{95, 135, 0}, //  64 Chartreuse4
	color.Rgb{95, 135, 95}, //  65 DarkSeaGreen4
	color.Rgb{95, 135, 135}, //  66 PaleTurquoise4
	color.Rgb{95, 135, 175}, //  67 SteelBlue
	color.Rgb{95, 135, 215}, //  68 SteelBlue3
	color.Rgb{95, 135, 255}, //  69 CornflowerBlue
	color.Rgb{95, 175, 0}, //  70 Chartreuse3
	color.Rgb{95, 175, 95}, //  71 DarkSeaGreen4
	color.Rgb{95, 175, 135}, //  72 CadetBlue
	color.Rgb{95, 175, 175}, //  73 CadetBlue
	color.Rgb{95, 175, 215}, //  74 SkyBlue3
	color.Rgb{95, 175, 255}, //  75 SteelBlue1
	color.Rgb{95, 215, 0}, //  76 Chartreuse3
	color.Rgb{95, 215, 95}, //  77 PaleGreen3
	color.Rgb{95, 215, 135}, //  78 SeaGreen3
	color.Rgb{95, 215, 175}, //  79 Aquamarine3
	color.Rgb{95, 215, 215}, //  80 MediumTurquoise
	color.Rgb{95, 215, 255}, //  81 SteelBlue1
	color.Rgb{95, 255, 0}, //  82 Chartreuse2
	color.Rgb{95, 255, 95}, //  83 SeaGreen2
	color.Rgb{95, 255, 135}, //  84 SeaGreen1
	color.Rgb{95, 255, 175}, //  85 SeaGreen1
	color.Rgb{95, 255, 215}, //  86 Aquamarine1
	color.Rgb{95, 255, 255}, //  87 DarkSlateGray2
	color.Rgb{135, 0, 0}, //  88 DarkRed
	color.Rgb{135, 0, 95}, //  89 DeepPink4
	color.Rgb{135, 0, 135}, //  90 DarkMagenta
	color.Rgb{135, 0, 175}, //  91 DarkMagenta
	color.Rgb{135, 0, 215}, //  92 DarkViolet
	color.Rgb{135, 0, 255}, //  93 Purple
	color.Rgb{135, 95, 0}, //  94 Orange4
	color.Rgb{135, 95, 95}, //  95 LightPink4
	color.Rgb{135, 95, 135}, //  96 Plum4
	color.Rgb{135, 95, 175}, //  97 MediumPurple3
	color.Rgb{135, 95, 215}, //  98 MediumPurple3
	color.Rgb{135, 95, 255}, //  99 SlateBlue1
	color.Rgb{135, 135, 0}, // 100 Yellow4
	color.Rgb{135, 135, 95}, // 101 Wheat4
	color.Rgb{135, 135, 135}, // 102 Grey53
	color.Rgb{135, 135, 175}, // 103 LightSlateGrey
	color.Rgb{135, 135, 215}, // 104 MediumPurple
	color.Rgb{135, 135, 255}, // 105 LightSlateBlue
	color.Rgb{135, 175, 0}, // 106 Yellow4
	color.Rgb{135, 175, 95}, // 107 DarkOliveGreen3
	color.Rgb{135, 175, 135}, // 108 DarkSeaGreen
	color.Rgb{135, 175, 175}, // 109 LightSkyBlue3
	color.Rgb{135, 175, 215}, // 110 LightSkyBlue3
	color.Rgb{135, 175, 255}, // 111 SkyBlue2
	color.Rgb{135, 215, 0}, // 112 Chartreuse2
	color.Rgb{135, 215, 95}, // 113 DarkOliveGreen3
	color.Rgb{135, 215, 135}, // 114 PaleGreen3
	color.Rgb{135, 215, 175}, // 115 DarkSeaGreen3
	color.Rgb{135, 215, 215}, // 116 DarkSlateGray3
	color.Rgb{135, 215, 255}, // 117 SkyBlue1
	color.Rgb{135, 255, 0}, // 118 Chartreuse1
	color.Rgb{135, 255, 95}, // 119 LightGreen
	color.Rgb{135, 255, 135}, // 120 LightGreen
	color.Rgb{135, 255, 175}, // 121 PaleGreen1
	color.Rgb{135, 255, 215}, // 122 Aquamarine1
	color.Rgb{135, 255, 255}, // 123 DarkSlateGray1
	color.Rgb{175, 0, 0}, // 124 Red3
	color.Rgb{175, 0, 95}, // 125 DeepPink4
	color.Rgb{175, 0, 135}, // 126 MediumVioletRed
	color.Rgb{175, 0, 175}, // 127 Magenta3
	color.Rgb{175, 0, 215}, // 128 DarkViolet
	color.Rgb{175, 0, 255}, // 129 Purple
	color.Rgb{175, 95, 0}, // 130 DarkOrange3
	color.Rgb{175, 95, 95}, // 131 IndianRed
	color.Rgb{175, 95, 135}, // 132 HotPink3
	color.Rgb{175, 95, 175}, // 133 MediumOrchid3
	color.Rgb{175, 95, 215}, // 134 MediumOrchid
	color.Rgb{175, 95, 255}, // 135 MediumPurple2
	color.Rgb{175, 135, 0}, // 136 DarkGoldenrod
	color.Rgb{175, 135, 95}, // 137 LightSalmon3
	color.Rgb{175, 135, 135}, // 138 RosyBrown
	color.Rgb{175, 135, 175}, // 139 Grey63
	color.Rgb{175, 135, 215}, // 140 MediumPurple2
	color.Rgb{175, 135, 255}, // 141 MediumPurple1
	color.Rgb{175, 175, 0}, // 142 Gold3
	color.Rgb{175, 175, 95}, // 143 DarkKhaki
	color.Rgb{175, 175, 135}, // 144 NavajoWhite3
	color.Rgb{175, 175, 175}, // 145 Grey69
	color.Rgb{175, 175, 215}, // 146 LightSteelBlue3
	color.Rgb{175, 175, 255}, // 147 LightSteelBlue
	color.Rgb{175, 215, 0}, // 148 Yellow3
	color.Rgb{175, 215, 95}, // 149 DarkOliveGreen3
	color.Rgb{175, 215, 135}, // 150 DarkSeaGreen3
	color.Rgb{175, 215, 175}, // 151 DarkSeaGreen2
	color.Rgb{175, 215, 215}, // 152 LightCyan3
	color.Rgb{175, 215, 255}, // 153 LightSkyBlue1
	color.Rgb{175, 255, 0}, // 154 GreenYellow
	color.Rgb{175, 255, 95}, // 155 DarkOliveGreen2
	color.Rgb{175, 255, 135}, // 156 PaleGreen1
	color.Rgb{175, 255, 175}, // 157 DarkSeaGreen2
	color.Rgb{175, 255, 215}, // 158 DarkSeaGreen1
	color.Rgb{175, 255, 255}, // 159 PaleTurquoise1
	color.Rgb{215, 0, 0}, // 160 Red3
	color.Rgb{215, 0, 95}, // 161 DeepPink3
	color.Rgb{215, 0, 135}, // 162 DeepPink3
	color.Rgb{215, 0, 175}, // 163 Magenta3
	color.Rgb{215, 0, 215}, // 164 Magenta3
	color.Rgb{215, 0, 255}, // 165 Magenta2
	color.Rgb{215, 95, 0}, // 166 DarkOrange3
	color.Rgb{215, 95, 95}, // 167 IndianRed
	color.Rgb{215, 95, 135}, // 168 HotPink3
	color.Rgb{215, 95, 175}, // 169 HotPink2
	color.Rgb{215, 95, 215}, // 170 Orchid
	color.Rgb{215, 95, 255}, // 171 MediumOrchid1
	color.Rgb{215, 135, 0}, // 172 Orange3
	color.Rgb{215, 135, 95}, // 173 LightSalmon3
	color.Rgb{215, 135, 135}, // 174 LightPink3
	color.Rgb{215, 135, 175}, // 175 Pink3
	color.Rgb{215, 135, 215}, // 176 Plum3
	color.Rgb{215, 135, 255}, // 177 Violet
	color.Rgb{215, 175, 0}, // 178 Gold3
	color.Rgb{215, 175, 95}, // 179 LightGoldenrod3
	color.Rgb{215, 175, 135}, // 180 Tan
	color.Rgb{215, 175, 175}, // 181 MistyRose3
	color.Rgb{215, 175, 215}, // 182 Thistle3
	color.Rgb{215, 175, 255}, // 183 Plum2
	color.Rgb{215, 215, 0}, // 184 Yellow3
	color.Rgb{215, 215, 95}, // 185 Khaki3
	color.Rgb{215, 215, 135}, // 186 LightGoldenrod2
	color.Rgb{215, 215, 175}, // 187 LightYellow3
	color.Rgb{215, 215, 215}, // 188 Grey84
	color.Rgb{215, 215, 255}, // 189 LightSteelBlue1
	color.Rgb{215, 255, 0}, // 190 Yellow2
	color.Rgb{215, 255, 95}, // 191 DarkOliveGreen1
	color.Rgb{215, 255, 135}, // 192 DarkOliveGreen1
	color.Rgb{215, 255, 175}, // 193 DarkSeaGreen1
	color.Rgb{215, 255, 215}, // 194 Honeydew2
	color.Rgb{215, 255, 255}, // 195 LightCyan1
	color.Rgb{255, 0, 0}, // 196 Red1
	color.Rgb{255, 0, 95}, // 197 DeepPink2
	color.Rgb{255, 0, 135}, // 198 DeepPink1
	color.Rgb{255, 0, 175}, // 199 DeepPink1
	color.Rgb{255, 0, 215}, // 200 Magenta2
	color.Rgb{255, 0, 255}, // 201 Magenta1
	color.Rgb{255, 95, 0}, // 202 OrangeRed1
	color.Rgb{255, 95, 95}, // 203 IndianRed1
	color.Rgb{255, 95, 135}, // 204 IndianRed1
	color.Rgb{255, 95, 175}, // 205 HotPink
	color.Rgb{255, 95, 215}, // 206 HotPink
	color.Rgb{255, 95, 255}, // 207 MediumOrchid1
	color.Rgb{255, 135, 0}, // 208 DarkOrange
	color.Rgb{255, 135, 95}, // 209 Salmon1
	color.Rgb{255, 135, 135}, // 210 LightCoral
	color.Rgb{255, 135, 175}, // 211 PaleVioletRed1
	color.Rgb{255, 135, 215}, // 212 Orchid2
	color.Rgb{255, 135, 255}, // 213 Orchid1
	color.Rgb{255, 175, 0}, // 214 Orange1
	color.Rgb{255, 175, 95}, // 215 SandyBrown
	color.Rgb{255, 175, 135}, // 216 LightSalmon1
	color.Rgb{255, 175, 175}, // 217 LightPink1
	color.Rgb{255, 175, 215}, // 218 Pink1
	color.Rgb{255, 175, 255}, // 219 Plum1
	color.Rgb{255, 215, 0}, // 220 Gold1
	color.Rgb{255, 215, 95}, // 221 LightGoldenrod2
	color.Rgb{255, 215, 135}, // 222 LightGoldenrod2
	color.Rgb{255, 215, 175}, // 223 NavajoWhite1
	color.Rgb{255, 215, 215}, // 224 MistyRose1
	color.Rgb{255, 215, 255}, // 225 Thistle1
	color.Rgb{255, 255, 0}, // 226 Yellow1
	color.Rgb{255, 255, 95}, // 227 LightGoldenrod1
	color.Rgb{255, 255, 135}, // 228 Khaki1
	color.Rgb{255, 255, 175}, // 229 Wheat1
	color.Rgb{255, 255, 215}, // 230 Cornsilk1
	color.Rgb{255, 255, 255}, // 231 Grey100
	color.Rgb{8, 8, 8}, // 232 Grey3
	color.Rgb{18, 18, 18}, // 233 Grey7
	color.Rgb{28, 28, 28}, // 234 Grey11
	color.Rgb{38, 38, 38}, // 235 Grey15
	color.Rgb{48, 48, 48}, // 236 Grey19
	color.Rgb{58, 58, 58}, // 237 Grey23
	color.Rgb{68, 68, 68}, // 238 Grey27
	color.Rgb{78, 78, 78}, // 239 Grey30
	color.Rgb{88, 88, 88}, // 240 Grey35
	color.Rgb{98, 98, 98}, // 241 Grey39
	color.Rgb{108, 108, 108}, // 242 Grey42
	color.Rgb{118, 118, 118}, // 243 Grey46
	color.Rgb{128, 128, 128}, // 244 Grey50
	color.Rgb{138, 138, 138}, // 245 Grey54
	color.Rgb{148, 148, 148}, // 246 Grey58
	color.Rgb{158, 158, 158}, // 247 Grey62
	color.Rgb{168, 168, 168}, // 248 Grey66
	color.Rgb{178, 178, 178}, // 249 Grey70
	color.Rgb{188, 188, 188}, // 250 Grey74
	color.Rgb{198, 198, 198}, // 251 Grey78
	color.Rgb{208, 208, 208}, // 252 Grey82
	color.Rgb{218, 218, 218}, // 253 Grey85
	color.Rgb{228, 228, 228}, // 254 Grey89
	color.Rgb{238, 238, 238}, // 255 Grey93
]!
