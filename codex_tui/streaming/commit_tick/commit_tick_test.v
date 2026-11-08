module commit_tick

import codex_tui.history_cell
import codex_tui.streaming.chunking
import codex_tui.streaming.controller
import std_time
import tracing

fn fixture_cell(message &string) history_cell.HistoryCell {
	return history_cell.new_info_event(message.clone(), none)
}

fn fixture_cells(prefix string, count int) []history_cell.HistoryCell {
	mut cells := []history_cell.HistoryCell{cap: count}
	for index in 0 .. count {
		message := '${prefix}${index}'
		cells << fixture_cell(&message)
	}
	return cells
}

fn messages(cells &[]history_cell.HistoryCell) []string {
	mut values := []string{cap: cells.len}
	for cell in *cells {
		values << cell.message.clone()
	}
	return values
}

fn test_tick_without_controllers_has_idle_default() {
	now := std_time.Instant.now()
	mut policy := chunking.AdaptiveChunkingPolicy.default()
	mut stream := StreamControllerMut.none()
	mut plan := PlanStreamControllerMut.none()
	output := run_commit_tick(mut policy, mut stream, mut plan, .any_mode, now)
	assert output == CommitTickOutput.default()
}

fn test_empty_present_controllers_are_still_reported_and_each_drained() {
	now := std_time.Instant.now()
	mut main_controller := controller.StreamController.fixture([], now)
	mut plan_controller := controller.PlanStreamController.fixture([], now)
	mut stream := StreamControllerMut.some(mut main_controller)
	mut plan := PlanStreamControllerMut.some(mut plan_controller)
	mut policy := chunking.AdaptiveChunkingPolicy.default()
	output := run_commit_tick(mut policy, mut stream, mut plan, .any_mode, now)
	assert output == CommitTickOutput{ has_controller: true, all_idle: true }
	assert main_controller.fixture_calls() == controller.CommitTickFixtureCalls{ single: 1 }
	assert plan_controller.fixture_calls() == controller.CommitTickFixtureCalls{ single: 1 }
}

fn test_smooth_mode_emits_main_before_plan_and_preserves_fifo() {
	now := std_time.Instant.now()
	mut main_controller := controller.StreamController.fixture(fixture_cells('main-', 3), now)
	mut plan_controller := controller.PlanStreamController.fixture(fixture_cells('plan-', 2), now)
	mut stream := StreamControllerMut.some(mut main_controller)
	mut plan := PlanStreamControllerMut.some(mut plan_controller)
	mut policy := chunking.AdaptiveChunkingPolicy.default()
	first := run_commit_tick(mut policy, mut stream, mut plan, .any_mode, now)
	second := run_commit_tick(mut policy, mut stream, mut plan, .any_mode, now)
	third := run_commit_tick(mut policy, mut stream, mut plan, .any_mode, now)
	assert messages(&first.cells) == ['main-0', 'plan-0']
	assert messages(&second.cells) == ['main-1', 'plan-1']
	assert messages(&third.cells) == ['main-2']
	assert first.has_controller && !first.all_idle
	assert second.has_controller && !second.all_idle
	assert third.has_controller && third.all_idle
	assert main_controller.fixture_calls() == controller.CommitTickFixtureCalls{ single: 3 }
	assert plan_controller.fixture_calls() == controller.CommitTickFixtureCalls{ single: 3 }
	assert main_controller.queued_lines() == 0
	assert plan_controller.queued_lines() == 0
}

fn test_single_present_plan_controller_can_emit_and_finish() {
	now := std_time.Instant.now()
	mut plan_controller := controller.PlanStreamController.fixture(fixture_cells('plan-', 1), now)
	mut stream := StreamControllerMut.none()
	mut plan := PlanStreamControllerMut.some(mut plan_controller)
	mut policy := chunking.AdaptiveChunkingPolicy.default()
	output := run_commit_tick(mut policy, mut stream, mut plan, .any_mode, now)
	assert messages(&output.cells) == ['plan-0']
	assert output.has_controller && output.all_idle
}

fn test_combined_depth_enters_catch_up_and_passes_same_full_depth_to_both() {
	now := std_time.Instant.now()
	mut main_controller := controller.StreamController.fixture(fixture_cells('m', 4), now)
	mut plan_controller := controller.PlanStreamController.fixture(fixture_cells('p', 4), now)
	mut stream := StreamControllerMut.some(mut main_controller)
	mut plan := PlanStreamControllerMut.some(mut plan_controller)
	mut policy := chunking.AdaptiveChunkingPolicy.default()
	output := run_commit_tick(mut policy, mut stream, mut plan, .any_mode, now)
	assert messages(&output.cells) == ['m0\nm1\nm2\nm3', 'p0\np1\np2\np3']
	assert output.has_controller && output.all_idle
	assert policy.mode() == .catch_up
	assert main_controller.fixture_calls() == controller.CommitTickFixtureCalls{ batch: [usize(8)] }
	assert plan_controller.fixture_calls() == controller.CommitTickFixtureCalls{ batch: [usize(8)] }
}

fn test_snapshot_keeps_sum_depth_and_maximum_age_in_either_controller_order() {
	now := std_time.Instant.now()
	mut main_controller := controller.StreamController.fixture(fixture_cells('m', 2), now.sub(std_time.Duration.from_millis(12)))
	mut plan_controller := controller.PlanStreamController.fixture(fixture_cells('p', 3), now.sub(std_time.Duration.from_millis(137)))
	stream := StreamControllerMut.some(mut main_controller)
	plan := PlanStreamControllerMut.some(mut plan_controller)
	snapshot := stream_queue_snapshot(stream.as_ref(), plan.as_ref(), now)
	assert snapshot == chunking.QueueSnapshot{ queued_lines: 5, oldest_age: std_time.Duration.from_millis(137) }
	mut old_main := controller.StreamController.fixture(fixture_cells('m', 3), now.sub(std_time.Duration.from_millis(137)))
	mut young_plan := controller.PlanStreamController.fixture(fixture_cells('p', 2), now.sub(std_time.Duration.from_millis(12)))
	reverse_stream := StreamControllerMut.some(mut old_main)
	reverse_plan := PlanStreamControllerMut.some(mut young_plan)
	assert stream_queue_snapshot(reverse_stream.as_ref(), reverse_plan.as_ref(), now) == snapshot
	// Repeated snapshot reads cannot consume either queue's owned strings.
	assert stream_queue_snapshot(stream.as_ref(), plan.as_ref(), now) == snapshot
	assert main_controller.queued_lines() == 2 && plan_controller.queued_lines() == 3
}

fn test_age_pressure_enters_catch_up_with_only_one_queued_line() {
	now := std_time.Instant.now()
	mut main_controller := controller.StreamController.fixture(fixture_cells('old-', 1), now.sub(std_time.Duration.from_millis(120)))
	mut stream := StreamControllerMut.some(mut main_controller)
	mut plan := PlanStreamControllerMut.none()
	mut policy := chunking.AdaptiveChunkingPolicy.default()
	output := run_commit_tick(mut policy, mut stream, mut plan, .catch_up_only, now)
	assert messages(&output.cells) == ['old-0']
	assert output.has_controller && output.all_idle
	assert policy.mode() == .catch_up
	assert main_controller.fixture_calls() == controller.CommitTickFixtureCalls{ batch: [usize(1)] }
}

fn test_catch_up_only_suppresses_smooth_drain_without_consuming_queue() {
	now := std_time.Instant.now()
	mut main_controller := controller.StreamController.fixture(fixture_cells('m', 2), now)
	mut stream := StreamControllerMut.some(mut main_controller)
	mut plan := PlanStreamControllerMut.none()
	mut policy := chunking.AdaptiveChunkingPolicy.default()
	first := run_commit_tick(mut policy, mut stream, mut plan, .catch_up_only, now)
	second := run_commit_tick(mut policy, mut stream, mut plan, .catch_up_only, now)
	assert first == CommitTickOutput.default()
	assert second == CommitTickOutput.default()
	assert main_controller.queued_lines() == 2
	assert main_controller.fixture_calls() == controller.CommitTickFixtureCalls{}
	allowed := run_commit_tick(mut policy, mut stream, mut plan, .any_mode, now)
	assert messages(&allowed.cells) == ['m0']
}

fn test_catch_up_only_updates_exit_hold_before_suppressing_commit() {
	now := std_time.Instant.now()
	mut policy := chunking.AdaptiveChunkingPolicy.default()
	policy.decide(chunking.QueueSnapshot{ queued_lines: 8, oldest_age: std_time.duration_zero }, now)
	mut main_controller := controller.StreamController.fixture(fixture_cells('m', 2), now.add(std_time.Duration.from_millis(250)))
	mut stream := StreamControllerMut.some(mut main_controller)
	mut plan := PlanStreamControllerMut.none()
	// Record an earlier low-pressure decision to start the source policy's exit hold.
	resolve_chunking_plan(mut policy, chunking.QueueSnapshot{ queued_lines: 2, oldest_age: std_time.duration_zero }, now)
	output := run_commit_tick(mut policy, mut stream, mut plan, .catch_up_only, now.add(std_time.Duration.from_millis(250)))
	assert output == CommitTickOutput.default()
	assert policy.mode() == .smooth
	assert main_controller.queued_lines() == 2
	assert main_controller.fixture_calls() == controller.CommitTickFixtureCalls{}
}

fn test_absence_resets_policy_before_catch_up_only_suppression() {
	now := std_time.Instant.now()
	mut policy := chunking.AdaptiveChunkingPolicy.default()
	policy.decide(chunking.QueueSnapshot{ queued_lines: 8 }, now)
	assert policy.mode() == .catch_up
	mut stream := StreamControllerMut.none()
	mut plan := PlanStreamControllerMut.none()
	output := run_commit_tick(mut policy, mut stream, mut plan, .catch_up_only, now)
	assert output == CommitTickOutput.default()
	assert policy.mode() == .smooth
}

fn test_zero_and_bounded_batch_plans_preserve_controller_order_and_idle_reduction() {
	now := std_time.Instant.now()
	mut main_controller := controller.StreamController.fixture(fixture_cells('m', 1), now)
	mut plan_controller := controller.PlanStreamController.fixture(fixture_cells('p', 3), now)
	mut stream := StreamControllerMut.some(mut main_controller)
	mut plan := PlanStreamControllerMut.some(mut plan_controller)
	zero := apply_commit_tick_plan(chunking.DrainPlan.batch(0), mut stream, mut plan)
	assert zero == CommitTickOutput{ has_controller: true, all_idle: false }
	first := apply_commit_tick_plan(chunking.DrainPlan.batch(2), mut stream, mut plan)
	assert messages(&first.cells) == ['m0', 'p0\np1']
	assert first.has_controller && !first.all_idle
	assert main_controller.queued_lines() == 0 && plan_controller.queued_lines() == 1
	second := apply_commit_tick_plan(chunking.DrainPlan.batch(~usize(0)), mut stream, mut plan)
	assert messages(&second.cells) == ['p2']
	assert second.all_idle
	assert main_controller.fixture_calls().batch == [usize(0), 2, ~usize(0)]
	assert plan_controller.fixture_calls().batch == [usize(0), 2, ~usize(0)]
}

fn test_optional_duration_maximum_preserves_both_absence_and_full_range() {
	a := std_time.Duration.from_millis(3)
	b := std_time.Duration.from_millis(4)
	assert max_duration(none, none) == none
	assert max_duration(a, none) == ?std_time.Duration(a)
	assert max_duration(none, b) == ?std_time.Duration(b)
	assert max_duration(a, b) == ?std_time.Duration(b)
	assert max_duration(b, a) == ?std_time.Duration(b)
	assert max_duration(b, b) == ?std_time.Duration(b)
	assert max_duration(std_time.duration_max, b) == ?std_time.Duration(std_time.duration_max)
}

fn test_future_enqueue_timestamp_saturates_queue_age() {
	now := std_time.Instant.now()
	mut main_controller := controller.StreamController.fixture(fixture_cells('future-', 1), now.add(std_time.Duration.from_millis(400)))
	stream := StreamControllerMut.some(mut main_controller)
	plan := PlanStreamControllerMut.none()
	assert stream_queue_snapshot(stream.as_ref(), plan.as_ref(), now) == chunking.QueueSnapshot{ queued_lines: 1, oldest_age: std_time.duration_zero }
}

fn test_only_actual_mode_transitions_emit_complete_typed_trace_metadata() {
	tracing.fixture_begin_commit_tick_trace()
	now := std_time.Instant.now()
	mut policy := chunking.AdaptiveChunkingPolicy.default()
	resolve_chunking_plan(mut policy, chunking.QueueSnapshot{ queued_lines: 1, oldest_age: std_time.Duration.from_millis(5) }, now)
	resolve_chunking_plan(mut policy, chunking.QueueSnapshot{ queued_lines: 8, oldest_age: std_time.Duration.from_millis(125) }, now)
	resolve_chunking_plan(mut policy, chunking.QueueSnapshot{ queued_lines: 9, oldest_age: std_time.Duration.from_millis(130) }, now)
	resolve_chunking_plan(mut policy, chunking.QueueSnapshot{}, now)
	events := tracing.fixture_take_commit_tick_trace()
	assert events == [
		tracing.StreamChunkingTransition{ prior_mode: .smooth, new_mode: .catch_up, queued_lines: 8, oldest_queued_age_ms: u64(125), entered_catch_up: true },
		tracing.StreamChunkingTransition{ prior_mode: .catch_up, new_mode: .smooth, queued_lines: 0, entered_catch_up: false },
	]
}

fn test_transition_age_cast_keeps_low_64_bits_of_u128_milliseconds() {
	tracing.fixture_begin_commit_tick_trace()
	now := std_time.Instant.now()
	mut policy := chunking.AdaptiveChunkingPolicy.default()
	resolve_chunking_plan(mut policy, chunking.QueueSnapshot{ queued_lines: 1, oldest_age: std_time.duration_max }, now)
	events := tracing.fixture_take_commit_tick_trace()
	assert events.len == 1
	assert events[0].oldest_queued_age_ms == ?u64(~u64(0))
	assert events[0].entered_catch_up
}

fn test_dynamic_owned_payloads_survive_repeated_borrows_and_emitted_queue_deletion() {
	mut owner := 'source-owned-payload'
	$if ownership ? {
		owner = 'source-owned-payload'.to_owned()
	}
	now := std_time.Instant.now()
	mut main_controller := controller.StreamController.fixture([fixture_cell(&owner),
		fixture_cell(&owner)], now)
	mut stream := StreamControllerMut.some(mut main_controller)
	mut plan := PlanStreamControllerMut.none()
	mut policy := chunking.AdaptiveChunkingPolicy.default()
	assert stream_queue_snapshot(stream.as_ref(), plan.as_ref(), now).queued_lines == 2
	assert stream_queue_snapshot(stream.as_ref(), plan.as_ref(), now).queued_lines == 2
	first := run_commit_tick(mut policy, mut stream, mut plan, .any_mode, now)
	second := run_commit_tick(mut policy, mut stream, mut plan, .any_mode, now)
	// The controller owner and first emitted value remain usable after subsequent queue writes.
	assert main_controller.queued_lines() == 0
	assert messages(&first.cells) == ['source-owned-payload']
	assert messages(&second.cells) == ['source-owned-payload']
	assert owner == 'source-owned-payload'
}
