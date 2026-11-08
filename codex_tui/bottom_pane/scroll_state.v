module bottom_pane

// Generic scroll/selection state for a vertical list menu.
//
// Encapsulates the common behavior of a selectable list that supports:
// - Optional selection (none when list is empty)
// - Wrap-around navigation on Up/Down
// - Maintaining a scroll window (`scroll_top`) so the selected row stays visible
//
// Callers own the filtered row count and the visible window size. Every
// mutation method takes those values instead of caching them here, so list
// views can apply filters, pagination, or density changes without this helper
// knowing about their data model. Passing a stale length after filtering would
// leave selection pointing at the wrong row, so callers should clamp or move
// through this type immediately after changing their visible row set.
// V's allocation-free fields provide Rust's Copy/Clone semantics, its generated
// equality and formatting provide PartialEq/Debug, and zero initialization is Default.
pub struct ScrollState {
pub mut:
	selected_idx ?usize
	scroll_top   usize
}

pub fn ScrollState.new() ScrollState {
	return ScrollState{
		selected_idx: none
		scroll_top:   0
	}
}

// Reset selection and scroll.
pub fn (mut state ScrollState) reset() {
	state.selected_idx = none
	state.scroll_top = 0
}

// Clamp selection to be within the [0, len-1] range, or none when empty.
pub fn (mut state ScrollState) clamp_selection(len usize) {
	if state.clear_if_empty(len) {
		return
	}
	current := state.selected_idx or { usize(0) }
	state.selected_idx = if current < len { current } else { len - 1 }
}

// Move selection up by one, wrapping to the bottom when necessary.
pub fn (mut state ScrollState) move_up_wrap(len usize) {
	if state.clear_if_empty(len) {
		return
	}
	if idx := state.selected_idx {
		state.selected_idx = if idx > 0 { idx - 1 } else { len - 1 }
	} else {
		state.selected_idx = usize(0)
	}
}

// Move selection down by one, wrapping to the top when necessary.
pub fn (mut state ScrollState) move_down_wrap(len usize) {
	if state.clear_if_empty(len) {
		return
	}
	if idx := state.selected_idx {
		state.selected_idx = if idx + 1 < len { idx + 1 } else { usize(0) }
	} else {
		state.selected_idx = usize(0)
	}
}

// Move selection up by one visible page, clamping at the first row.
//
// Page movement intentionally does not wrap. It mirrors terminal list
// behavior where repeated page-up/page-down converges at the nearest edge
// while still keeping the selected row visible.
pub fn (mut state ScrollState) page_up_clamped(len usize, visible_rows usize) {
	if state.clear_if_empty(len) {
		return
	}
	step := if visible_rows > 1 { visible_rows } else { usize(1) }
	selected := state.selected_idx or { usize(0) }
	current := if selected < len { selected } else { len - 1 }
	state.selected_idx = if current >= step { current - step } else { usize(0) }
	state.ensure_visible(len, visible_rows)
}

// Move selection down by one visible page, clamping at the last row.
//
// Page movement intentionally does not wrap. It mirrors terminal list
// behavior where repeated page-up/page-down converges at the nearest edge
// while still keeping the selected row visible.
pub fn (mut state ScrollState) page_down_clamped(len usize, visible_rows usize) {
	if state.clear_if_empty(len) {
		return
	}
	step := if visible_rows > 1 { visible_rows } else { usize(1) }
	selected := state.selected_idx or { usize(0) }
	current := if selected < len { selected } else { len - 1 }
	// Rust usize::saturating_add retains the platform-sized unsigned range.
	next := if step > ~usize(0) - current { ~usize(0) } else { current + step }
	state.selected_idx = if next < len { next } else { len - 1 }
	state.ensure_visible(len, visible_rows)
}

// Jump selection to the first row.
pub fn (mut state ScrollState) jump_top(len usize, visible_rows usize) {
	if state.clear_if_empty(len) {
		return
	}
	state.selected_idx = usize(0)
	state.ensure_visible(len, visible_rows)
}

// Jump selection to the last row.
pub fn (mut state ScrollState) jump_bottom(len usize, visible_rows usize) {
	if state.clear_if_empty(len) {
		return
	}
	state.selected_idx = len - 1
	state.ensure_visible(len, visible_rows)
}

fn (mut state ScrollState) clear_if_empty(len usize) bool {
	if len != 0 {
		return false
	}
	state.selected_idx = none
	state.scroll_top = 0
	return true
}

// Adjust `scroll_top` so that the current `selected_idx` is visible within
// the window of `visible_rows`.
pub fn (mut state ScrollState) ensure_visible(len usize, visible_rows usize) {
	if len == 0 || visible_rows == 0 {
		state.scroll_top = 0
		return
	}
	if sel := state.selected_idx {
		if sel < state.scroll_top {
			state.scroll_top = sel
		} else {
			bottom := state.scroll_top + visible_rows - 1
			if sel > bottom {
				state.scroll_top = sel + 1 - visible_rows
			}
		}
	} else {
		state.scroll_top = 0
	}
}
