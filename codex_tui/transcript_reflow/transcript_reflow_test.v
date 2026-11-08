module transcript_reflow

import std_time
import time

pub fn (mut state TranscriptReflowState) set_due_for_test() {
	state.pending_until = std_time.Instant.now().sub(std_time.Duration.from_millis(1))
}

fn test_visible_history_rows_are_cached_for_resize_replay() {
	mut state := TranscriptReflowState.default()

	state.set_visible_history_rows( /*rows*/
	19)

	assert state.visible_history_rows() == ?u16(19)
}

fn test_visible_history_rows_keep_one_row_for_a_full_height_composer() {
	mut state := TranscriptReflowState.default()

	state.set_visible_history_rows( /*rows*/
	0)

	assert state.visible_history_rows() == ?u16(1)
}

fn test_schedule_debounced_postpones_existing_reflow() {
	mut state := TranscriptReflowState.default()

	assert !state.schedule_debounced( /*target_width*/
	none)
	first_deadline := state.pending_until() or { panic('pending reflow') }

	time.sleep(time.millisecond)
	assert !state.schedule_debounced( /*target_width*/
	none)

	assert (state.pending_until() or { panic('pending reflow') }) > first_deadline, 'a later resize should push the debounce deadline out'
}

fn test_schedule_debounced_postpones_due_existing_reflow() {
	mut state := TranscriptReflowState.default()
	state.set_due_for_test()
	before_reschedule := std_time.Instant.now()

	assert !state.schedule_debounced( /*target_width*/
	none)
	assert (state.pending_until() or { panic('pending reflow') }) > before_reschedule, 'a resize after the old deadline should start a fresh quiet period'
}

fn test_first_observed_width_marks_reflow_baseline() {
	mut state := TranscriptReflowState.default()

	width := state.note_width( /*width*/
	80)

	assert width.initialized
	assert state.last_observed_width == ?u16(80)
	assert state.last_reflow_width == ?u16(80)
	assert !state.reflow_needed_for_width( /*width*/
	80)
}

fn test_mark_reflowed_width_records_actual_rebuild_width() {
	mut state := TranscriptReflowState.default()
	state.note_width( /*width*/
	80)

	assert state.mark_reflowed_width( /*width*/
	100)

	assert state.last_observed_width == ?u16(80)
	assert state.last_reflow_width == ?u16(100)
}

fn test_reflow_needed_compares_against_actual_rebuild_width() {
	mut state := TranscriptReflowState.default()
	state.note_width( /*width*/
	80)
	state.mark_reflowed_width( /*width*/
	90)
	state.note_width( /*width*/
	100)

	assert state.reflow_needed_for_width( /*width*/
	100)
}

fn test_pending_reflow_target_prevents_repeated_reschedule() {
	mut state := TranscriptReflowState.default()
	state.note_width( /*width*/
	80)

	assert state.reflow_needed_for_width( /*width*/
	100)
	state.schedule_debounced( /*target_width*/
	?u16(100))

	assert !state.reflow_needed_for_width( /*width*/
	100)
}

fn test_clear_pending_reflow_allows_same_width_to_be_rescheduled() {
	mut state := TranscriptReflowState.default()
	state.note_width( /*width*/
	80)
	state.schedule_debounced( /*target_width*/
	?u16(100))

	state.clear_pending_reflow()

	assert state.reflow_needed_for_width( /*width*/
	100)
}

fn test_mark_reflowed_width_reports_unchanged_width() {
	mut state := TranscriptReflowState.default()
	assert state.mark_reflowed_width( /*width*/
	100)

	assert !state.mark_reflowed_width( /*width*/
	100)
	assert state.last_reflow_width == ?u16(100)
}

fn test_take_stream_finish_reflow_needed_drains_resize_request() {
	mut state := TranscriptReflowState.default()
	state.mark_resize_requested_during_stream()

	assert state.take_stream_finish_reflow_needed()
	assert !state.take_stream_finish_reflow_needed()
}

fn test_take_stream_finish_reflow_needed_drains_ran_during_stream() {
	mut state := TranscriptReflowState.default()
	state.mark_ran_during_stream()

	assert state.take_stream_finish_reflow_needed()
	assert !state.take_stream_finish_reflow_needed()
}

fn test_clear_resets_stream_reflow_flags() {
	mut state := TranscriptReflowState.default()
	state.mark_ran_during_stream()
	state.mark_resize_requested_during_stream()

	state.clear()

	assert !state.take_stream_finish_reflow_needed()
}

fn test_note_width_reports_first_unchanged_and_changed_observations() {
	mut state := TranscriptReflowState.default()
	assert state.note_width(80) == TranscriptWidthChange{ initialized: true }
	assert state.note_width(80) == TranscriptWidthChange{}
	assert state.note_width(100) == TranscriptWidthChange{ changed: true }
	assert state.note_width(80) == TranscriptWidthChange{ changed: true }
	assert !state.has_pending_reflow()
	assert !state.reflow_needed_for_width(80)
}

fn test_height_only_request_does_not_hide_a_width_repair_or_erase_a_pending_width() {
	mut state := TranscriptReflowState.default()
	state.note_width(80)
	state.schedule_debounced(none)
	assert state.has_pending_reflow()
	assert state.reflow_needed_for_width(100)
	state.schedule_debounced(?u16(100))
	state.schedule_debounced(none)
	assert !state.reflow_needed_for_width(100)
	assert state.reflow_needed_for_width(90)
	state.schedule_debounced(?u16(90))
	assert state.reflow_needed_for_width(100)
	assert !state.reflow_needed_for_width(90)
}

fn test_pending_deadline_is_inclusive_and_borrowed_reads_keep_state_reusable() {
	mut state := TranscriptReflowState.default()
	assert !state.pending_is_due(std_time.Instant.now())
	state.schedule_debounced(?u16(100))
	deadline := state.pending_until() or { panic('pending reflow') }
	assert !state.pending_is_due(deadline.sub(std_time.Duration.from_nanos(1)))
	assert state.pending_is_due(deadline)
	assert state.pending_is_due(deadline.add(std_time.Duration.from_nanos(1)))
	assert state.pending_until() == ?std_time.Instant(deadline)
	assert state.pending_until() == ?std_time.Instant(deadline)
	assert state.has_pending_reflow()
	assert state.pending_reflow_width == ?u16(100)
}

fn test_immediate_request_removes_debounced_width_suppression() {
	mut state := TranscriptReflowState.default()
	state.note_width(80)
	state.schedule_debounced(?u16(100))
	assert !state.reflow_needed_for_width(100)
	state.schedule_immediate()
	assert state.pending_is_due(std_time.Instant.now())
	assert state.reflow_needed_for_width(100)
	assert state.has_pending_reflow()
	state.clear_pending_reflow()
	assert !state.has_pending_reflow()
	assert !state.pending_is_due(std_time.Instant.now())
}

fn test_clear_stream_flags_preserves_width_budget_and_pending_deadline() {
	mut state := TranscriptReflowState.default()
	state.note_width(80)
	state.mark_reflowed_width(90)
	state.set_visible_history_rows(19)
	state.schedule_debounced(?u16(100))
	deadline := state.pending_until() or { panic('pending reflow') }
	state.mark_ran_during_stream()
	state.mark_resize_requested_during_stream()
	state.clear_stream_flags()
	assert !state.take_stream_finish_reflow_needed()
	assert state.last_observed_width == ?u16(80)
	assert state.last_reflow_width == ?u16(90)
	assert state.visible_history_rows() == ?u16(19)
	assert state.pending_until() == ?std_time.Instant(deadline)
	assert !state.reflow_needed_for_width(100)
}

fn test_clear_resets_width_budget_deadline_and_stream_repair_state() {
	mut state := TranscriptReflowState.default()
	state.note_width(80)
	state.mark_reflowed_width(90)
	state.set_visible_history_rows(19)
	state.schedule_debounced(?u16(100))
	state.mark_ran_during_stream()
	state.mark_resize_requested_during_stream()
	state.clear()
	assert state == TranscriptReflowState.default()
	assert state.note_width(100) == TranscriptWidthChange{ initialized: true }
}

fn test_combined_stream_flags_drain_once_then_accept_a_new_episode() {
	mut state := TranscriptReflowState.default()
	state.mark_ran_during_stream()
	state.mark_resize_requested_during_stream()
	assert state.take_stream_finish_reflow_needed()
	assert !state.take_stream_finish_reflow_needed()
	state.mark_resize_requested_during_stream()
	assert state.take_stream_finish_reflow_needed()
	assert !state.take_stream_finish_reflow_needed()
}
