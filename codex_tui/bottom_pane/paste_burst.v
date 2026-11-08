// Paste-burst detection for terminals without bracketed paste.
//
// On some platforms (notably Windows), pastes often arrive as a rapid stream of
// `KeyCodeKind.char_key` and `KeyCodeKind.enter` key events rather than as a single "paste" event.
// In that mode, the composer needs to:
//
// - Prevent transient UI side effects (e.g. toggles bound to `?`) from triggering on pasted text.
// - Ensure Enter is treated as a newline *inside the paste*, not as "submit the message".
// - Avoid flicker caused by inserting a typed prefix and then immediately reclassifying it as
//   paste once enough chars have arrived.
//
// This module provides the `PasteBurst` state machine. `ChatComposer` feeds it only
// text-producing character events (plain, Shift, or Windows AltGr) and uses the full buffering
// decisions to either:
//
// - briefly hold a first ASCII char (flicker suppression),
// - buffer a burst as a single pasted string, or
// - let input flow through as normal typing.
//
// # Call Pattern
//
// `PasteBurst` is a pure state machine: it never mutates the textarea directly. The caller feeds
// it events and then applies the chosen action:
//
// - For each text-producing `KeyCodeKind.char_key`, call [`PasteBurst.on_plain_char`] (ASCII) or
//   [`PasteBurst.on_plain_char_no_hold`] (non-ASCII/IME).
// - If the decision indicates buffering, the caller appends to `PasteBurst.buffer` via
//   [`PasteBurst.append_char_to_buffer`].
// - On Enter, [`PasteBurst.append_newline_if_active`] promotes a held first character into
//   the active buffer before appending the newline.
// - On a UI tick, call [`PasteBurst.flush_if_due`]. If it returns [`FlushResultKind.typed`], insert
//   that char as normal typing. If it returns [`FlushResultKind.paste`], treat the returned string as
//   an explicit paste.
// - Before applying non-text input (arrow keys; Ctrl/Alt shortcuts other than Windows AltGr;
//   or Super, Hyper, and Meta modifiers), use
//   [`PasteBurst.flush_before_modified_input`] to avoid leaving buffered text "stuck", and then
//   [`PasteBurst.clear_window_after_non_char`] so subsequent typing does not get grouped into a
//   previous burst.
// - Direct-insert callers can skip buffering, use
//   [`PasteBurst.direct_insert_newline_should_insert`] in their Enter handler, and call
//   [`PasteBurst.extend_window`] when Enter or [`PasteBurst.on_plain_char_no_hold`] reports a
//   burst-like stream.
//
// # State Variables
//
// This state machine is encoded in a few fields with slightly different meanings:
//
// - `active`: true while we are still *actively* accepting characters into the current burst.
// - `buffer`: accumulated burst text that will eventually flush as a single `FlushResultKind.paste`.
//   A non-empty buffer is treated as "in burst context" even if `active` has been cleared.
// - `pending_first_char`: a single held ASCII char used for flicker suppression. The caller must
//   not render this char until it joins a burst through `begin_buffer_from_pending` or
//   `append_newline_if_active`, or flushes as a normal typed char (`FlushResultKind.typed`).
// - `last_plain_char_time`/`consecutive_plain_char_burst`: the timing/count heuristic for
//   "paste-like" streams.
// - `burst_window_until`: the Enter suppression window ("Enter inserts newline") that outlives the
//   buffer itself.
//
// # Timing Model
//
// There are two timeouts:
//
// - `paste_burst_char_interval`: maximum delay between consecutive "plain" chars for them to be
//   considered part of a single burst. It also bounds how long `pending_first_char` is held.
// - `paste_burst_active_idle_timeout`: once buffering is active, how long to wait after the last
//   char before flushing the accumulated buffer as a paste.
//
// `flush_if_due()` intentionally uses `>` (not `>=`) when comparing elapsed time, so tests and UI
// ticks should cross the threshold by at least 1ms (see `recommended_flush_delay()`).
//
// # Retro Capture Details
//
// Retro-capture exists to handle the case where we initially inserted characters as "normal
// typing", but later decide that the stream is paste-like. When that happens, we retroactively
// remove a prefix of already-inserted text from the textarea and move it into the burst buffer so
// the eventual `handle_paste(...)` sees a contiguous pasted string.
//
// Retro-capture mostly matters on paths that do *not* hold the first character (non-ASCII/IME
// input, and retro-grab scenarios). The ASCII path usually prefers
// `retain_first_char -> begin_buffer_from_pending`, which avoids needing retro-capture at all.
//
// Retro-capture is expressed in terms of characters, not bytes:
//
// - `CharDecision{ kind: .begin_buffer, retro_chars }` uses `retro_chars` as a character count.
// - `decide_begin_buffer(now, before_cursor, retro_chars)` turns that into a UTF-8 byte range by
//   calling `retro_start_index()`.
// - `RetroGrab.start_byte` is a byte index into the `before_cursor` slice; callers must clamp the
//   cursor to a char boundary before slicing so `start_byte..cursor` is always valid UTF-8.
//
// # Clearing vs Flushing
//
// There are two ways callers end burst handling, and they are not interchangeable:
//
// - `flush_before_modified_input()` returns the buffered text (and/or a pending first ASCII char)
//   so the caller can apply it through the normal paste path before handling an unrelated input.
// - `clear_window_after_non_char()` clears the *classification window* so subsequent typing does
//   not get grouped into the previous burst. It assumes the caller has already flushed any buffer
//   because it clears `last_plain_char_time`, which means `flush_if_due()` will not flush a
//   non-empty buffer until another plain char updates the timestamp.
//
// # States (Conceptually)
//
// - **Idle**: no buffered text, no pending char.
// - **Pending first char**: `pending_first_char` holds one ASCII char for up to
//   `paste_burst_char_interval` while we wait to see if a burst follows.
// - **Active buffer**: `active`/`buffer` holds paste-like content until it times out and flushes.
// - **Enter suppress window**: `burst_window_until` keeps Enter treated as newline briefly after
//   burst activity so multiline pastes stay grouped.
//
// # ASCII vs Non-ASCII
//
// - [`PasteBurst.on_plain_char`] may return [`CharDecisionKind.retain_first_char`] to hold the first
//   ASCII char and avoid flicker.
// - [`PasteBurst.on_plain_char_no_hold`] never holds (used for IME/non-ASCII paths), since
//   holding a non-ASCII character can feel like dropped input.
//
// # Contract With Callers
//
// `PasteBurst` does not mutate the UI text buffer on its own. Callers must interpret decisions
// and apply the corresponding UI edits. `ChatComposer` uses the full buffering contract:
//
// - For each plain ASCII `KeyCodeKind.char_key`, call [`PasteBurst.on_plain_char`].
//   - [`CharDecisionKind.retain_first_char`]: do **not** insert the char into the textarea yet.
//   - [`CharDecisionKind.begin_buffer_from_pending`]: call [`PasteBurst.append_char_to_buffer`] for the
//     current char (the previously-held char is already in the burst buffer).
//   - [`CharDecision{ kind: .begin_buffer, retro_chars }`]: consider retro-capturing the already-inserted
//     prefix by calling [`PasteBurst.decide_begin_buffer`]. If it returns `Some`, remove the
//     returned `start_byte..cursor` range from the textarea and then call
//     [`PasteBurst.append_char_to_buffer`] for the current char. If it returns `None`, fall back
//     to normal insertion.
//   - [`CharDecisionKind.buffer_append`]: call [`PasteBurst.append_char_to_buffer`].
//
// - For each plain non-ASCII `KeyCodeKind.char_key`, call [`PasteBurst.on_plain_char_no_hold`] and then:
//   - If it returns `Some(CharDecisionKind.buffer_append)`, call
//     [`PasteBurst.append_char_to_buffer`].
//   - If it returns `Some(CharDecision{ kind: .begin_buffer, retro_chars })`, call
//     [`PasteBurst.decide_begin_buffer`] as above (and if buffering starts, remove the grabbed
//     prefix from the textarea and then append the current char to the buffer).
//   - If it returns `None`, insert normally.
//
// - Before applying non-char input (or any input that should not join a burst), call
//   [`PasteBurst.flush_before_modified_input`] and pass the returned string (if any) through the
//   normal paste path.
//
// - Periodically (e.g. on a UI tick), call [`PasteBurst.flush_if_due`].
//   - [`FlushResultKind.typed`]: insert that single char as normal typing.
//   - [`FlushResultKind.paste`]: treat the returned string as an explicit paste.
//
// - When non-text input is pressed (Ctrl/Alt shortcuts other than Windows AltGr; Super, Hyper,
//   and Meta modifiers; arrows; etc.), callers should use
//   [`PasteBurst.clear_window_after_non_char`] to prevent the next keystroke from being
//   incorrectly grouped into a previous burst.

module bottom_pane

// V adaptation: Instant/Duration are represented as i64 milliseconds, matching the composer's
// clock and scheduling interface. Optional timestamps preserve a valid zero clock value.
// The caller must provide timestamps from one nondecreasing clock domain.

// Heuristic thresholds for detecting paste-like input bursts.
// Detect quickly to avoid showing typed prefix before paste is recognized
const paste_burst_min_chars = u16(3)
const paste_enter_suppress_window = i64(120)

// Maximum delay between consecutive chars to be considered part of a paste burst.
const paste_burst_char_interval = i64(8)

// Idle timeout before flushing buffered paste content.
// Slower paste bursts have been observed in Windows environments.
const paste_burst_active_idle_timeout = $if windows { i64(60) } $else { i64(8) }

pub struct PasteBurst {
mut:
	last_plain_char_time         ?i64
	consecutive_plain_char_burst u16
	burst_window_until           ?i64
	buffer                       string
	active                       bool
	// Hold first fast char briefly to avoid rendering flicker
	pending_first_char ?PasteBurstPendingFirstChar
}

// V adaptation: the optional Rust (char, Instant) tuple is an allocation-free value.
struct PasteBurstPendingFirstChar {
	ch rune
	at i64
}

// V uses an explicit tag and payload to represent the source enum variants.
pub enum CharDecisionKind {
	// Start buffering and retroactively capture some already-inserted chars.
	begin_buffer
	// We are currently buffering; append the current char into the buffer.
	buffer_append
	// Do not insert/render this char yet; temporarily save the first fast
	// char while we wait to see if a paste-like burst follows.
	retain_first_char
	// Begin buffering using the previously saved first char (no retro grab needed).
	begin_buffer_from_pending
}

pub struct CharDecision {
pub:
	kind        CharDecisionKind
	retro_chars u16
}

pub struct RetroGrab {
pub:
	start_byte int
	grabbed    string
}

// V uses an explicit tag and disjoint payload fields to represent the source enum variants.
pub enum FlushResultKind {
	paste
	typed
	no_flush
}

pub struct FlushResult {
pub:
	kind FlushResultKind
	text string
	ch   rune
}

// Recommended delay to wait between simulated keypresses (or before
// scheduling a UI tick) so that a pending fast keystroke is flushed
// out of the burst detector as normal typed input.
//
// Primarily used by tests and by the TUI to reliably cross the
// paste-burst timing threshold.
pub fn PasteBurst.recommended_flush_delay() i64 {
	return paste_burst_char_interval + 1
}

pub fn PasteBurst.recommended_active_flush_delay() i64 {
	return paste_burst_active_idle_timeout + 1
}

// Entry point: decide how to treat a plain char with current timing.
pub fn (mut burst PasteBurst) on_plain_char(ch rune, now i64) CharDecision {
	burst.note_plain_char(now)

	if burst.active {
		burst.burst_window_until = now + paste_enter_suppress_window
		return CharDecision{ kind: .buffer_append }
	}

	// If we already held a first char and receive a second fast char,
	// start buffering without retro-grabbing (we never rendered the first).
	pending := burst.pending_first_char
	if held := pending {
		if now - held.at <= paste_burst_char_interval {
			burst.active = true
			// Clear pending; we already captured the held char above.
			burst.pending_first_char = none
			burst.buffer += held.ch.str()
			burst.burst_window_until = now + paste_enter_suppress_window
			return CharDecision{ kind: .begin_buffer_from_pending }
		}
	}

	if burst.consecutive_plain_char_burst >= paste_burst_min_chars {
		return CharDecision{
			kind:        .begin_buffer
			retro_chars: burst.consecutive_plain_char_burst - 1
		}
	}

	// Save the first fast char very briefly to see if a burst follows.
	burst.pending_first_char = PasteBurstPendingFirstChar{ ch: ch, at: now }
	return CharDecision{ kind: .retain_first_char }
}

// Like on_plain_char(), but never holds the first char.
//
// Used for non-ASCII input paths (e.g., IMEs) where holding a character can
// feel like dropped input, while still allowing burst-based paste detection.
//
// Note: This method will only ever return buffer_append or begin_buffer.
pub fn (mut burst PasteBurst) on_plain_char_no_hold(now i64) ?CharDecision {
	burst.note_plain_char(now)

	if burst.active {
		burst.burst_window_until = now + paste_enter_suppress_window
		return CharDecision{ kind: .buffer_append }
	}

	if burst.consecutive_plain_char_burst >= paste_burst_min_chars {
		return CharDecision{
			kind:        .begin_buffer
			retro_chars: burst.consecutive_plain_char_burst - 1
		}
	}

	return none
}

fn (mut burst PasteBurst) note_plain_char(now i64) {
	previous_option := burst.last_plain_char_time
	mut consecutive := false
	if previous := previous_option {
		consecutive = now - previous <= paste_burst_char_interval
	}
	if consecutive {
		if burst.consecutive_plain_char_burst < u16(0xffff) {
			burst.consecutive_plain_char_burst++
		}
	} else {
		burst.consecutive_plain_char_burst = 1
	}
	burst.last_plain_char_time = now
}

// Flushes any buffered burst if the inter-key timeout has elapsed.
//
// Returns:
//
// - FlushResultKind.paste when a paste burst was active and buffered text is emitted as one
//   pasted string.
// - FlushResultKind.typed when a single fast first ASCII char was being held (flicker
//   suppression) and no burst followed before the timeout elapsed.
// - FlushResultKind.no_flush when the timeout has not elapsed, or there is nothing to flush.
pub fn (mut burst PasteBurst) flush_if_due(now i64) FlushResult {
	timeout := if burst.is_active_internal() {
		paste_burst_active_idle_timeout
	} else {
		paste_burst_char_interval
	}
	last_option := burst.last_plain_char_time
	mut timed_out := false
	if last := last_option {
		timed_out = now - last > timeout
	}
	if timed_out && burst.is_active_internal() {
		burst.active = false
		out := burst.buffer
		burst.buffer = ''
		return FlushResult{ kind: .paste, text: out }
	} else if timed_out {
		// If we were saving a single fast char and no burst followed,
		// flush it as normal typed input.
		pending := burst.pending_first_char
		burst.pending_first_char = none
		if held := pending {
			return FlushResult{ kind: .typed, ch: held.ch }
		}
		return FlushResult{ kind: .no_flush }
	} else {
		return FlushResult{ kind: .no_flush }
	}
}

// While bursting: accumulate a newline into the buffer instead of
// submitting the textarea.
//
// Returns true if a newline was appended (we are in a burst context),
// false otherwise.
pub fn (mut burst PasteBurst) append_newline_if_active(now i64) bool {
	if burst.is_active() {
		pending := burst.pending_first_char
		burst.pending_first_char = none
		if held := pending {
			burst.buffer += held.ch.str()
		}
		burst.active = true
		burst.buffer += '\n'
		burst.burst_window_until = now + paste_enter_suppress_window
		return true
	} else {
		return false
	}
}

// Decide if Enter should insert a newline (burst context) vs submit.
pub fn (burst &PasteBurst) newline_should_insert_instead_of_submit(now i64) bool {
	in_burst_window := if until := burst.burst_window_until { now <= until } else { false }
	return burst.is_active() || in_burst_window
}

// Decide if Enter should insert a newline for callers that insert chars immediately.
pub fn (burst &PasteBurst) direct_insert_newline_should_insert(now i64) bool {
	recent_plain_char := if last := burst.last_plain_char_time {
		now - last <= paste_burst_char_interval
	} else {
		false
	}
	return burst.newline_should_insert_instead_of_submit(now) || recent_plain_char
}

// Keep the burst window alive.
pub fn (mut burst PasteBurst) extend_window(now i64) {
	burst.burst_window_until = now + paste_enter_suppress_window
}

// Begin buffering with retroactively grabbed text.
pub fn (mut burst PasteBurst) begin_with_retro_grabbed(grabbed string, now i64) {
	if grabbed.len > 0 {
		burst.buffer += grabbed
	}
	burst.active = true
	burst.burst_window_until = now + paste_enter_suppress_window
}

// Append a char into the burst buffer.
pub fn (mut burst PasteBurst) append_char_to_buffer(ch rune, now i64) {
	burst.buffer += ch.str()
	burst.burst_window_until = now + paste_enter_suppress_window
}

// Try to append a char into the burst buffer only if a burst is already active.
//
// Returns true when the char was captured into the existing burst, false otherwise.
pub fn (mut burst PasteBurst) try_append_char_if_active(ch rune, now i64) bool {
	if burst.active || burst.buffer.len > 0 {
		burst.append_char_to_buffer(ch, now)
		return true
	} else {
		return false
	}
}

// Decide whether to begin buffering by retroactively capturing recent
// chars from the slice before the cursor.
//
// Heuristic: if the retro-grabbed slice contains any whitespace or is
// sufficiently long (>= 16 characters), treat it as paste-like to avoid
// rendering the typed prefix momentarily before the paste is recognized.
// This favors responsiveness and prevents flicker for typical pastes
// (URLs, file paths, multiline text) while not triggering on short words.
//
// Returns a RetroGrab with the start byte and grabbed text when we
// decide to buffer retroactively; otherwise none.
pub fn (mut burst PasteBurst) decide_begin_buffer(now i64, before &string,
	retro_chars int) ?RetroGrab {
	start_byte := retro_start_index(before, retro_chars)
	grabbed := (*before)[start_byte..].clone()
	grabbed_chars := grabbed.runes()
	looks_pastey := grabbed_chars.any(rune_is_space(it)) || grabbed_chars.len >= 16
	if looks_pastey {
		// Note: caller is responsible for removing this slice from UI text.
		burst.begin_with_retro_grabbed(grabbed.clone(), now)
		return RetroGrab{ start_byte: start_byte, grabbed: grabbed }
	} else {
		return none
	}
}

// Before applying modified/non-char input: flush buffered burst immediately.
pub fn (mut burst PasteBurst) flush_before_modified_input() ?string {
	if !burst.is_active() {
		return none
	}
	burst.active = false
	mut out := burst.buffer
	burst.buffer = ''
	pending := burst.pending_first_char
	burst.pending_first_char = none
	if held := pending {
		out += held.ch.str()
	}
	return out
}

// Clear only the timing window and any pending first-char.
//
// Does not emit or clear the buffered text itself; callers should have
// already flushed (if needed) via one of the flush methods above.
pub fn (mut burst PasteBurst) clear_window_after_non_char() {
	burst.consecutive_plain_char_burst = 0
	burst.last_plain_char_time = none
	burst.burst_window_until = none
	burst.active = false
	burst.pending_first_char = none
}

// Returns true if we are in any paste-burst related transient state
// (actively buffering, have a non-empty buffer, or have saved the first
// fast char while waiting for a potential burst).
pub fn (burst &PasteBurst) is_active() bool {
	return burst.is_active_internal() || burst.pending_first_char != none
}

fn (burst &PasteBurst) is_active_internal() bool {
	return burst.active || burst.buffer.len > 0
}

pub fn (mut burst PasteBurst) clear_after_explicit_paste() {
	burst.last_plain_char_time = none
	burst.consecutive_plain_char_burst = 0
	burst.burst_window_until = none
	burst.active = false
	burst.buffer = ''
	burst.pending_first_char = none
}

pub fn retro_start_index(before &string, retro_chars int) int {
	if retro_chars == 0 {
		return before.len
	}
	mut remaining := retro_chars
	mut index := before.len
	for index > 0 {
		index--
		if (*before)[index] & 0xc0 != 0x80 {
			remaining--
			if remaining == 0 {
				return index
			}
		}
	}
	return 0
}
