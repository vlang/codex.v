// Tracks when Codex-owned transcript scrollback must be repaired after terminal resize.
//
// Terminal scrollback is not a retained widget tree: once Codex writes wrapped lines into the
// terminal, the terminal owns those rows. Width resize reflow treats the in-memory transcript cells
// as the source of truth, clears Codex-owned history, and re-emits the cells at the current width.
// Height-only growth also schedules a rebuild so rows exposed above the inline viewport are
// restored from the same source of truth.
//
// This module owns only scheduling and stream-time repair state. It does not know how to render
// cells or clear terminal output; `app.resize_reflow` consumes this state and performs the
// rebuild. The key invariant is that a reflow request which happens while streaming output is
// active, or while transient stream cells are still waiting for consolidation, must trigger one
// final source-backed reflow after the stream becomes source-backed history.
module transcript_reflow

import std_time

pub const transcript_reflow_debounce = std_time.Duration.from_millis(75)

// Tracks pending terminal-scrollback repair after a terminal resize.
//
// The state intentionally separates observed terminal width from rebuilt terminal width. Terminal
// emulators can report an intermediate size during drag-resize, then settle on the final size after
// Codex has already rebuilt scrollback. Keeping those widths distinct lets the next draw request a
// final rebuild instead of assuming the latest observed size has already been repaired.
// V's structural formatting supplies Debug; all fields are allocation-free and default to absent
// widths/deadlines and false flags, matching Rust's derived Default.
pub struct TranscriptReflowState {
mut:
	last_observed_width            ?u16
	last_reflow_width              ?u16
	pending_reflow_width           ?u16
	pending_until                  ?std_time.Instant
	visible_history_rows           ?u16
	ran_during_stream              bool
	resize_requested_during_stream bool
}

pub fn TranscriptReflowState.default() TranscriptReflowState {
	return TranscriptReflowState{}
}

// Reset all width, pending deadline, and stream repair state.
//
// Call this when the app discards the transcript state that pending reflow work would have
// rebuilt. Leaving stale deadlines behind would make a later draw attempt to rebuild history
// from unrelated cells.
pub fn (mut state TranscriptReflowState) clear() {
	state = TranscriptReflowState.default()
}

// Cache the history rows left above the composer for the current terminal size.
pub fn (mut state TranscriptReflowState) set_visible_history_rows(rows u16) {
	state.visible_history_rows = if rows > /*other*/
	u16(1) {
		rows
	} else {
		u16(1)
	}
}

// Return the last viewport budget without querying the terminal during cell replay.
pub fn (state &TranscriptReflowState) visible_history_rows() ?u16 {
	return state.visible_history_rows
}

// Record the width observed during a draw and report whether it is new or changed.
//
// The first observed width initializes the state without scheduling a rebuild because no
// old-width transcript has been emitted yet. Treating initialization as a real resize would
// make the first draw do redundant scrollback work.
pub fn (mut state TranscriptReflowState) note_width(width u16) TranscriptWidthChange {
	previous_width := state.last_observed_width
	state.last_observed_width = width
	if previous_width == none {
		state.last_reflow_width = width
	}
	return TranscriptWidthChange{
		changed:     if previous := previous_width { previous != width } else { false }
		initialized: previous_width == none
	}
}

// Return whether scrollback still needs to be rebuilt at `width`.
//
// This compares against the width that actually rebuilt scrollback, not just the most recently
// observed terminal width. A terminal can report the final size after the reflow that handled
// the resize event, so the follow-up draw must be able to request one more reflow even if
// the observed-width tracker already saw that value.
pub fn (state &TranscriptReflowState) reflow_needed_for_width(width u16) bool {
	return state.last_reflow_width != ?u16(width) && state.pending_reflow_width != ?u16(width)
}

// Schedule a trailing-debounced reflow and return whether it should run immediately.
//
// Repeated resize events push the deadline out so dragging a terminal edge rebuilds scrollback
// at the final observed width rather than at intermediate widths. `target_width` is present
// only for width-changing rebuilds; height-only exposure still needs a rebuild, but it must not
// suppress a later width repair for the same draw cycle.
pub fn (mut state TranscriptReflowState) schedule_debounced(target_width ?u16) bool {
	now := std_time.Instant.now()
	if width := target_width {
		state.pending_reflow_width = width
	}
	state.pending_until = now.add(transcript_reflow_debounce)
	return false
}

// Schedule an immediate reflow for the next draw opportunity.
//
// This is used after stream consolidation when waiting for the debounce interval would leave
// visible terminal-wrapped stream rows in the finalized transcript.
pub fn (mut state TranscriptReflowState) schedule_immediate() {
	state.pending_reflow_width = none
	state.pending_until = std_time.Instant.now()
}

pub fn (state &TranscriptReflowState) pending_is_due(now std_time.Instant) bool {
	if deadline := state.pending_until {
		return now >= deadline
	}
	return false
}

pub fn (state &TranscriptReflowState) pending_until() ?std_time.Instant {
	return state.pending_until
}

pub fn (state &TranscriptReflowState) has_pending_reflow() bool {
	return state.pending_until != none
}

pub fn (mut state TranscriptReflowState) clear_pending_reflow() {
	state.pending_until = none
	state.pending_reflow_width = none
}

// Remember the terminal width that actually rebuilt transcript scrollback.
//
// Resize scheduling is driven by observed widths, but debounced redraws may run before a
// terminal emulator has settled on its final size. Keeping the rendered width separate avoids
// confusing "seen during a draw" with "scrollback has been repaired at this width".
pub fn (mut state TranscriptReflowState) mark_reflowed_width(width u16) bool {
	previous_width := state.last_reflow_width
	state.last_reflow_width = width
	return previous_width != ?u16(width)
}

// Remember that a reflow actually rebuilt history before stream consolidation completed.
//
// A mid-stream rebuild can only render the transient stream cells that exist at that moment.
// The consolidation handler must later rebuild again from the finalized source-backed cell or
// the transcript can keep old stream wrapping.
pub fn (mut state TranscriptReflowState) mark_ran_during_stream() {
	state.ran_during_stream = true
}

// Remember that the terminal width changed while streaming or pre-consolidation cells existed.
//
// This captures the case where the debounce did not fire before the stream finished. Without
// this flag, consolidation could complete without the final source-backed resize repair.
// Marking the request rather than forcing immediate rendering keeps resize drag behavior
// debounced while still guaranteeing that finalized stream cells replace transient rows.
pub fn (mut state TranscriptReflowState) mark_resize_requested_during_stream() {
	state.resize_requested_during_stream = true
}

// Return whether stream finalization needs a source-backed reflow and clear the request.
//
// This is a draining read because each resize-during-stream episode should force at most one
// post-consolidation repair. Calling it before consolidation would drop the repair request and
// leave finalized scrollback shaped by transient stream rows.
pub fn (mut state TranscriptReflowState) take_stream_finish_reflow_needed() bool {
	needed := state.ran_during_stream || state.resize_requested_during_stream
	state.ran_during_stream = false
	state.resize_requested_during_stream = false
	return needed
}

// Clear only the stream repair flags while preserving width and pending-deadline state.
//
// Use this after a required final stream reflow has completed. Calling `clear()` here would
// also forget the last observed width and make the next draw look like first initialization.
pub fn (mut state TranscriptReflowState) clear_stream_flags() {
	state.ran_during_stream = false
	state.resize_requested_during_stream = false
}

// Describes how the latest draw width relates to the previous observed draw width.
//
// `initialized` means this was the first width observed by the state machine. `changed` means a
// previously observed transcript width exists and differs from the new width.
pub struct TranscriptWidthChange {
pub:
	changed     bool
	initialized bool
}
