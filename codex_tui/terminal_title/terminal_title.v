// Terminal-title output helpers for the TUI.
//
// This module owns the low-level OSC title write path and the sanitization
// that happens immediately before we emit it. It is intentionally narrow:
// callers decide when the title should change and whether an empty title means
// "leave the old title alone" or "clear the title Codex last wrote".
// This module does not attempt to read or restore the terminal's previous
// title because that is not portable across terminals.
//
// Sanitization is necessary because title content is assembled from untrusted
// text sources such as model output, thread names, project paths, and config.
// Before we place that text inside an OSC sequence, we strip:
// - control characters that could terminate or reshape the escape sequence
// - bidi/invisible formatting codepoints that can visually reorder or hide
//   text (the same family of issues discussed in Trojan Source writeups)
// - redundant whitespace that would make titles noisy or hard to scan
module terminal_title

import crossterm
import os
import strings

// Practical upper bound on title length, measured in Unicode scalar values.
//
// Most terminals silently truncate titles beyond a few hundred characters.
// 240 leaves headroom for the OSC framing bytes while keeping titles
// readable in tab bars and window managers.
const max_terminal_title_chars = 240

// Outcome of a set_terminal_title call.
pub enum SetTerminalTitleResult {
	applied // A sanitized title was written, or stdout is not a terminal so no write was needed.
	// Sanitization removed every visible character, so no title was emitted.
	//
	// This is distinct from clearing the title. Callers decide whether an
	// empty post-sanitization value should result in no-op behavior, clearing
	// the title Codex manages, or some other fallback.
	no_visible_content
}

// Writes a sanitized OSC window-title sequence to stdout.
//
// The input is treated as untrusted display text: control characters,
// invisible formatting characters, and redundant whitespace are removed before
// the title is emitted. If sanitization removes all visible content, the
// function returns SetTerminalTitleResult.no_visible_content instead of
// clearing the title because clearing and restoring are policy decisions for
// higher-level callers. Mechanically, sanitization collapses whitespace runs
// to single spaces, drops disallowed codepoints, and bounds the result to
// max_terminal_title_chars visible characters before writing OSC 0.
pub fn set_terminal_title(title &string) !SetTerminalTitleResult {
	if os.is_atty(1) == 0 {
		return .applied
	}
	sanitized := sanitize_terminal_title(title)
	if sanitized.len == 0 {
		return .no_visible_content
	}
	command := SetWindowTitle{ title: sanitized }
	mut output := os.stdout()
	crossterm.execute(mut output, &command)!
	return .applied
}

// Clears the current terminal title by writing an empty OSC title payload.
//
// This clears the visible title; it does not restore whatever title the shell
// or a previous program may have set before Codex started managing the title.
pub fn clear_terminal_title() ! {
	if os.is_atty(1) == 0 {
		return
	}
	command := SetWindowTitle{ title: '' }
	mut output := os.stdout()
	crossterm.execute(mut output, &command)!
}

struct SetWindowTitle {
	title string
}

// Rust derives Clone for the owned title payload.
fn (command &SetWindowTitle) clone() SetWindowTitle {
	return SetWindowTitle{ title: command.title.clone() }
}

fn (command &SetWindowTitle) write_ansi(mut output strings.Builder) ! {
	// Match crossterm's SetTitle command and terminate OSC 0 with BEL.
	// Some terminal title integrations expose the ST terminator in process
	// decorations even though they otherwise accept the title update.
	output.write_string('\x1b]0;')
	output.write_string(command.title)
	output.write_u8(7)
}

// V makes the Windows trait methods available on all platforms so the command
// has a stable interface; the ANSI execution path uses the same source behavior.
fn (command &SetWindowTitle) execute_winapi() ! {
	return error('tried to execute SetWindowTitle using WinAPI; use ANSI instead')
}

fn (command &SetWindowTitle) is_ansi_code_supported() bool {
	return true
}

// Normalizes untrusted title text into a single bounded display line.
//
// This removes terminal control characters, strips invisible/bidi formatting
// characters, collapses any whitespace run into a single ASCII space, and
// truncates after max_terminal_title_chars emitted characters.
fn sanitize_terminal_title(title &string) string {
	// Each emitted Unicode scalar occupies at most four UTF-8 bytes. Bound the output
	// allocation and iterate lazily so an oversized input does not allocate a full rune array.
	capacity := if title.len < max_terminal_title_chars * 4 {
		title.len
	} else {
		max_terminal_title_chars * 4
	}
	mut sanitized := strings.new_builder(capacity)
	mut chars_written := 0
	mut pending_space := false
	for ch in title.runes_iterator() {
		if title_char_is_whitespace(ch) {
			// Only set pending if we've already written content; this
			// strips leading whitespace without an extra trim pass.
			pending_space = sanitized.len > 0
			continue
		}
		if is_disallowed_terminal_title_char(ch) {
			continue
		}
		if pending_space {
			remaining := max_terminal_title_chars - chars_written
			if remaining > 1 {
				sanitized.write_u8(32)
				chars_written++
				pending_space = false
			}
		}
		if chars_written >= max_terminal_title_chars {
			break
		}
		sanitized.write_rune(ch)
		chars_written++
	}
	return sanitized.str()
}

// Returns whether ch should be dropped from terminal-title output.
//
// This includes both plain control characters and a curated set of invisible
// formatting codepoints. The bidi entries here cover the Trojan-Source-style
// text-reordering controls that can make a title render misleadingly relative
// to its underlying byte sequence.
fn is_disallowed_terminal_title_char(ch rune) bool {
	// Rust char::is_control is Unicode General_Category=Cc (C0, DEL, and C1).
	if ch <= 0x1f || (ch >= 0x7f && ch <= 0x9f) {
		return true
	}
	// Strip Trojan-Source-related bidi controls plus common non-rendering
	// formatting characters so title text cannot smuggle terminal control
	// semantics or visually misleading content.
	return ch in [rune(0x00ad), 0x034f, 0x061c, 0x180e, 0xfeff]
		|| (ch >= 0x200b && ch <= 0x200f) || (ch >= 0x202a && ch <= 0x202e)
		|| (ch >= 0x2060 && ch <= 0x206f) || (ch >= 0xfe00 && ch <= 0xfe0f)
		|| (ch >= 0xfff9 && ch <= 0xfffb) || (ch >= 0x1bca0 && ch <= 0x1bca3)
		|| (ch >= 0xe0100 && ch <= 0xe01ef)
}

// Rust char::is_whitespace uses Unicode White_Space; V's byte-oriented trim
// helpers do not cover this scalar set.
fn title_char_is_whitespace(ch rune) bool {
	return ch in [rune(0x20), 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x85, 0xa0, 0x1680, 0x2028, 0x2029,
		0x202f, 0x205f, 0x3000] || (ch >= 0x2000 && ch <= 0x200a)
}
