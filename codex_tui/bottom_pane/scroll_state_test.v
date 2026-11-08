module bottom_pane

fn test_wrap_navigation_and_visibility() {
	mut s := ScrollState.new()
	len := usize(10)
	vis := usize(5)

	s.clamp_selection(len)
	assert s.selected_idx == ?usize(0)
	s.ensure_visible(len, vis)
	assert s.scroll_top == 0

	s.move_up_wrap(len)
	s.ensure_visible(len, vis)
	assert s.selected_idx == ?usize(len - 1)
	if sel := s.selected_idx {
		assert s.scroll_top <= sel
	} else {
		panic('expected Some(selected_idx) after wrap')
	}

	s.move_down_wrap(len)
	s.ensure_visible(len, vis)
	assert s.selected_idx == ?usize(0)
	assert s.scroll_top == 0
}

fn test_page_and_jump_navigation_clamps() {
	mut s := ScrollState.new()
	len := usize(10)
	vis := usize(4)

	s.clamp_selection(len)
	s.page_down_clamped(len, vis)
	assert s.selected_idx == ?usize(4)
	assert s.scroll_top == 1

	s.page_down_clamped(len, vis)
	assert s.selected_idx == ?usize(8)
	assert s.scroll_top == 5

	s.page_down_clamped(len, vis)
	assert s.selected_idx == ?usize(9)
	assert s.scroll_top == 6

	s.page_up_clamped(len, vis)
	assert s.selected_idx == ?usize(5)
	assert s.scroll_top == 5

	s.jump_top(len, vis)
	assert s.selected_idx == ?usize(0)
	assert s.scroll_top == 0

	s.jump_bottom(len, vis)
	assert s.selected_idx == ?usize(9)
	assert s.scroll_top == 6
}

fn test_scroll_state_filtering_reestablishes_valid_selection() {
	mut state := ScrollState{
		selected_idx: usize(9)
		scroll_top:   6
	}
	state.clamp_selection(3)
	state.ensure_visible(3, 2)
	assert state == ScrollState{
		selected_idx: usize(2)
		scroll_top:   2
	}
	state.clamp_selection(0)
	assert state == ScrollState.new()
	state.move_up_wrap(5)
	assert state.selected_idx == ?usize(0)
	state.reset()
	state.move_down_wrap(5)
	assert state.selected_idx == ?usize(0)
}

fn test_scroll_state_empty_navigation_resets_selection_and_scroll() {
	for navigation in 0 .. 8 {
		mut state := ScrollState{
			selected_idx: usize(9)
			scroll_top:   7
		}
		match navigation {
			0 { state.clamp_selection(0) }
			1 { state.move_up_wrap(0) }
			2 { state.move_down_wrap(0) }
			3 { state.page_up_clamped(0, 4) }
			4 { state.page_down_clamped(0, 4) }
			5 { state.jump_top(0, 4) }
			6 { state.jump_bottom(0, 4) }
			7 { state.reset() }
			else { panic('unexpected navigation') }
		}
		assert state == ScrollState.new()
	}
}

fn test_scroll_state_empty_viewport_preserves_selection() {
	mut state := ScrollState{
		selected_idx: usize(9)
		scroll_top:   7
	}
	state.ensure_visible(10, 0)
	assert state == ScrollState{
		selected_idx: usize(9)
	}
	state.scroll_top = 7
	state.ensure_visible(0, 4)
	assert state == ScrollState{
		selected_idx: usize(9)
	}
	state.page_up_clamped(10, 0)
	assert state.selected_idx == ?usize(8)
	state.page_down_clamped(10, 0)
	assert state.selected_idx == ?usize(9)
}

fn test_scroll_state_page_movement_saturates_unsigned_arithmetic() {
	mut state := ScrollState{
		selected_idx: usize(4)
	}
	state.page_down_clamped(10, ~usize(0))
	assert state.selected_idx == ?usize(9)
	state.page_up_clamped(10, ~usize(0))
	assert state.selected_idx == ?usize(0)
	state.selected_idx = ~usize(0)
	state.page_up_clamped(10, 4)
	assert state.selected_idx == ?usize(5)
	state.page_down_clamped(10, 4)
	assert state.selected_idx == ?usize(9)
}

fn test_scroll_state_copy_remains_independent_and_reusable() {
	original := ScrollState{
		selected_idx: usize(6)
		scroll_top:   3
	}
	mut copy := original
	copy.page_down_clamped(10, 4)
	copy.reset()
	assert copy == ScrollState.new()
	assert original == ScrollState{
		selected_idx: usize(6)
		scroll_top:   3
	}
}
