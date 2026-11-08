module controller

import codex_tui.history_cell
import std_time

// STUB: the untranslated StreamCore queue; these explicit fixture cells carry plain line
// payloads. Real markdown collection, HyperlinkLine rendering, headers and plan styles are absent.
struct CommitTickFixtureLine {
	cell        history_cell.HistoryCell
	enqueued_at std_time.Instant
}

// STUB: crate::streaming::controller::StreamController, restricted to commit-tick APIs.
pub struct StreamController {
mut:
	queue        []CommitTickFixtureLine
	single_calls usize
	batch_calls  []usize
}

// STUB: crate::streaming::controller::PlanStreamController, restricted to commit-tick APIs.
pub struct PlanStreamController {
mut:
	queue        []CommitTickFixtureLine
	single_calls usize
	batch_calls  []usize
}

// STUB: fixture construction, not the source controller constructor. The caller supplies owned
// plain HistoryCell line carriers and an enqueue timestamp without a markdown/runtime dependency.
pub fn StreamController.fixture(cells []history_cell.HistoryCell, enqueued_at std_time.Instant) StreamController {
	mut queue := []CommitTickFixtureLine{cap: cells.len}
	for cell in cells {
		queue << CommitTickFixtureLine{ cell: cell, enqueued_at: enqueued_at }
	}
	return StreamController{ queue: queue }
}

// STUB: fixture construction for the proposed-plan controller without plan render styling.
pub fn PlanStreamController.fixture(cells []history_cell.HistoryCell, enqueued_at std_time.Instant) PlanStreamController {
	mut queue := []CommitTickFixtureLine{cap: cells.len}
	for cell in cells {
		queue << CommitTickFixtureLine{ cell: cell, enqueued_at: enqueued_at }
	}
	return PlanStreamController{ queue: queue }
}

// STUB: StreamController::queued_lines delegates to the fixture FIFO's line count.
pub fn (stream &StreamController) queued_lines() usize {
	return usize(stream.queue.len)
}

// STUB: PlanStreamController::queued_lines delegates to the fixture FIFO's line count.
pub fn (stream &PlanStreamController) queued_lines() usize {
	return usize(stream.queue.len)
}

// STUB: StreamController::oldest_queued_age retains Rust's saturating timestamp arithmetic.
pub fn (stream &StreamController) oldest_queued_age(now std_time.Instant) ?std_time.Duration {
	if stream.queue.len == 0 {
		return none
	}
	return now.saturating_duration_since(stream.queue[0].enqueued_at)
}

// STUB: PlanStreamController::oldest_queued_age retains Rust's saturating timestamp arithmetic.
pub fn (stream &PlanStreamController) oldest_queued_age(now std_time.Instant) ?std_time.Duration {
	if stream.queue.len == 0 {
		return none
	}
	return now.saturating_duration_since(stream.queue[0].enqueued_at)
}

// STUB: StreamController::on_commit_tick drains one fixture line and returns queue-idle state.
pub fn (mut stream StreamController) on_commit_tick() (?history_cell.HistoryCell, bool) {
	stream.single_calls++
	cell := drain_fixture_queue(mut stream.queue, 1)
	return cell, stream.queue.len == 0
}

// STUB: StreamController::on_commit_tick_batch preserves max_lines and FIFO queue-idle state.
pub fn (mut stream StreamController) on_commit_tick_batch(max_lines usize) (?history_cell.HistoryCell, bool) {
	stream.batch_calls << max_lines
	cell := drain_fixture_queue(mut stream.queue, max_lines)
	return cell, stream.queue.len == 0
}

// STUB: PlanStreamController::on_commit_tick drains one fixture line and returns queue-idle state.
pub fn (mut stream PlanStreamController) on_commit_tick() (?history_cell.HistoryCell, bool) {
	stream.single_calls++
	cell := drain_fixture_queue(mut stream.queue, 1)
	return cell, stream.queue.len == 0
}

// STUB: PlanStreamController::on_commit_tick_batch preserves max_lines and FIFO queue-idle state.
pub fn (mut stream PlanStreamController) on_commit_tick_batch(max_lines usize) (?history_cell.HistoryCell, bool) {
	stream.batch_calls << max_lines
	cell := drain_fixture_queue(mut stream.queue, max_lines)
	return cell, stream.queue.len == 0
}

// STUB: StreamCore::tick/tick_batch and emit's fixture boundary. Move cells before deleting
// queue slots so ownership builds do not free emitted payloads. Multi-line fixtures concatenate
// plain messages and retain the first carrier's kind/hint; they do not implement rich UI styling.
fn drain_fixture_queue(mut queue []CommitTickFixtureLine, max_lines usize) ?history_cell.HistoryCell {
	count := if max_lines < usize(queue.len) { int(max_lines) } else { queue.len }
	if count == 0 {
		return none
	}
	first := queue[0].cell
	queue[0] = CommitTickFixtureLine{}
	queue.delete(0)
	if count == 1 {
		return first
	}
	mut messages := []string{cap: count}
	messages << first.message
	for _ in 1 .. count {
		cell := queue[0].cell
		queue[0] = CommitTickFixtureLine{}
		queue.delete(0)
		messages << cell.message
	}
	return history_cell.HistoryCell{
		kind:    first.kind
		message: messages.join('\n')
		hint:    first.hint
	}
}

// STUB: typed fixture observation of source-shaped one-line and batch-drain calls.
pub struct CommitTickFixtureCalls {
pub:
	single usize
	batch  []usize
}

// STUB: borrowed controller observation returns an owned copy of recorded batch arguments.
pub fn (stream &StreamController) fixture_calls() CommitTickFixtureCalls {
	return CommitTickFixtureCalls{ single: stream.single_calls, batch: stream.batch_calls.clone() }
}

// STUB: borrowed plan-controller observation returns an owned copy of recorded batch arguments.
pub fn (stream &PlanStreamController) fixture_calls() CommitTickFixtureCalls {
	return CommitTickFixtureCalls{ single: stream.single_calls, batch: stream.batch_calls.clone() }
}
