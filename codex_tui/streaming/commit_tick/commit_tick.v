// Orchestrates commit-tick drains across streaming controllers.
//
// This module bridges queue-based chunking policy (`chunking`) with the concrete stream
// controllers (`controller`). Callers provide the current controllers and tick scope; the module
// computes queue pressure, selects a drain plan, applies it, and returns emitted history cells.
//
// The module preserves ordering by draining only from controller queue heads. It does not schedule
// ticks and it does not mutate UI state directly; callers remain responsible for animation events
// and history insertion side effects.
//
// The main flow is:
// [`run_commit_tick`] -> [`stream_queue_snapshot`] -> [`QueueSnapshot`] ->
// [`resolve_chunking_plan`] -> [`ChunkingDecision`]/[`DrainPlan`] ->
// [`apply_commit_tick_plan`] -> [`CommitTickOutput`].
module commit_tick

import std_time
import codex_tui.history_cell
import codex_tui.streaming.chunking
import codex_tui.streaming.controller
import tracing

// Describes whether a commit tick may run in all modes or only in catch-up mode.
// The allocation-free enum preserves Rust's Clone, Copy, Debug, and equality behavior.
pub enum CommitTickScope {
	// Always run the tick, regardless of current chunking mode.
	any_mode
	// Run model transitions and policy updates, but commit lines only in `CatchUp`.
	catch_up_only
}

// Describes what a single commit tick produced.
pub struct CommitTickOutput {
pub mut:
	// Cells produced by drained stream lines during this tick.
	// Reuse the translated owned HistoryCell boundary until its dynamic trait is ported.
	cells []history_cell.HistoryCell
	// Whether at least one stream controller was present for this tick.
	has_controller bool
	// Whether all present controllers were idle after this tick.
	all_idle bool = true
}

// Creates an output that represents "no commit performed".
//
// This is used when a tick is intentionally suppressed, for example when
// the scope is [`CommitTickScope::CatchUpOnly`] and policy is not in catch-up mode.
pub fn CommitTickOutput.default() CommitTickOutput {
	return CommitTickOutput{}
}

// V cannot safely represent Option<&mut T> with ?&T in C generation. These wrappers borrow
// the controller without owning it; a present wrapper must not outlive the referenced owner.
pub struct StreamControllerMut {
	present bool
	value   &controller.StreamController = unsafe { nil }
}

pub fn StreamControllerMut.some(mut value controller.StreamController) StreamControllerMut {
	return StreamControllerMut{ present: true, value: &value }
}

pub fn StreamControllerMut.none() StreamControllerMut {
	return StreamControllerMut{}
}

pub struct PlanStreamControllerMut {
	present bool
	value   &controller.PlanStreamController = unsafe { nil }
}

pub fn PlanStreamControllerMut.some(mut value controller.PlanStreamController) PlanStreamControllerMut {
	return PlanStreamControllerMut{ present: true, value: &value }
}

pub fn PlanStreamControllerMut.none() PlanStreamControllerMut {
	return PlanStreamControllerMut{}
}

// Shared views model Option<&T>; private fields prevent dereferencing absent wrappers.
struct StreamControllerRef {
	present bool
	value   &controller.StreamController = unsafe { nil }
}

struct PlanStreamControllerRef {
	present bool
	value   &controller.PlanStreamController = unsafe { nil }
}

fn (value &StreamControllerMut) as_ref() StreamControllerRef {
	return StreamControllerRef{ present: value.present, value: value.value }
}

fn (value &PlanStreamControllerMut) as_ref() PlanStreamControllerRef {
	return PlanStreamControllerRef{ present: value.present, value: value.value }
}

// Runs one commit tick against the provided stream controllers.
//
// This function collects a [`QueueSnapshot`], asks [`AdaptiveChunkingPolicy`] for a
// [`ChunkingDecision`], and then applies the resulting [`DrainPlan`] to both controllers.
// If callers pass stale controller references (for example, references not tied to the
// current turn), queue age can be misread and the policy may stay in catch-up longer
// than expected.
pub fn run_commit_tick(mut policy chunking.AdaptiveChunkingPolicy, mut stream_controller StreamControllerMut, mut plan_stream_controller PlanStreamControllerMut, scope CommitTickScope, now std_time.Instant) CommitTickOutput {
	snapshot := stream_queue_snapshot(stream_controller.as_ref(), plan_stream_controller.as_ref(), now)
	decision := resolve_chunking_plan(mut policy, snapshot, now)
	if scope == .catch_up_only && decision.mode != .catch_up {
		return CommitTickOutput.default()
	}
	return apply_commit_tick_plan(decision.drain_plan, mut stream_controller, mut plan_stream_controller)
}

// Builds the combined queue-pressure snapshot consumed by chunking policy.
//
// The snapshot sums queue depth across controllers and keeps the maximum oldest age
// so policy decisions reflect the most delayed queued line currently visible.
fn stream_queue_snapshot(stream_controller StreamControllerRef, plan_stream_controller PlanStreamControllerRef, now std_time.Instant) chunking.QueueSnapshot {
	mut queued_lines := usize(0)
	mut oldest_age := ?std_time.Duration(none)
	if stream_controller.present {
		queued_lines += stream_controller.value.queued_lines()
		oldest_age = max_duration(oldest_age, stream_controller.value.oldest_queued_age(now))
	}
	if plan_stream_controller.present {
		queued_lines += plan_stream_controller.value.queued_lines()
		oldest_age = max_duration(oldest_age, plan_stream_controller.value.oldest_queued_age(now))
	}
	return chunking.QueueSnapshot{ queued_lines: queued_lines, oldest_age: oldest_age }
}

// Computes one policy decision and emits a trace log on mode transitions.
//
// This keeps policy transition logging in one place so callers can rely on
// [`run_commit_tick`] to provide consistent observability.
fn resolve_chunking_plan(mut policy chunking.AdaptiveChunkingPolicy, snapshot chunking.QueueSnapshot, now std_time.Instant) chunking.ChunkingDecision {
	prior_mode := policy.mode()
	decision := policy.decide(snapshot, now)
	if decision.mode != prior_mode {
		mut oldest_queued_age_ms := ?u64(none)
		if age := snapshot.oldest_age {
			// Rust's u128 `as u64` cast takes the low 64 bits without saturating.
			oldest_queued_age_ms = age.as_millis().lo
		}
		tracing.trace_stream_chunking_transition(tracing.StreamChunkingTransition{
			prior_mode:           prior_mode
			new_mode:             decision.mode
			queued_lines:         snapshot.queued_lines
			oldest_queued_age_ms: oldest_queued_age_ms
			entered_catch_up:     decision.entered_catch_up
		})
	}
	return decision
}

// Applies a [`DrainPlan`] to all available stream controllers.
//
// The returned [`CommitTickOutput`] reports emitted cells and whether all
// present controllers are idle after draining.
fn apply_commit_tick_plan(drain_plan chunking.DrainPlan, mut stream_controller StreamControllerMut, mut plan_stream_controller PlanStreamControllerMut) CommitTickOutput {
	mut output := CommitTickOutput.default()
	if stream_controller.present {
		output.has_controller = true
		mut stream := stream_controller.value
		cell, is_idle := drain_stream_controller(mut stream, drain_plan)
		if cell != none {
			output.cells << cell
		}
		output.all_idle = output.all_idle && is_idle
	}
	if plan_stream_controller.present {
		output.has_controller = true
		mut plan_stream := plan_stream_controller.value
		cell, is_idle := drain_plan_stream_controller(mut plan_stream, drain_plan)
		if cell != none {
			output.cells << cell
		}
		output.all_idle = output.all_idle && is_idle
	}
	return output
}

// Applies one drain step to the main stream controller.
//
// [`DrainPlan::Single`] maps to one-line drain; [`DrainPlan::Batch`] maps to
// multi-line drain (including instant catch-up when policy requests the full
// queued backlog).
fn drain_stream_controller(mut stream controller.StreamController, drain_plan chunking.DrainPlan) (?history_cell.HistoryCell, bool) {
	return match drain_plan.kind {
		.single { stream.on_commit_tick() }
		.batch { stream.on_commit_tick_batch(drain_plan.queued_lines) }
	}
}

// Applies one drain step to the plan stream controller.
//
// This mirrors [`drain_stream_controller`] so both controller types follow the
// same chunking policy decisions.
fn drain_plan_stream_controller(mut stream controller.PlanStreamController, drain_plan chunking.DrainPlan) (?history_cell.HistoryCell, bool) {
	return match drain_plan.kind {
		.single { stream.on_commit_tick() }
		.batch { stream.on_commit_tick_batch(drain_plan.queued_lines) }
	}
}

// Returns the greater of two optional durations.
//
// This helper preserves whichever side is present when only one duration exists.
fn max_duration(lhs ?std_time.Duration, rhs ?std_time.Duration) ?std_time.Duration {
	if left := lhs {
		if right := rhs {
			return if left < right { right } else { left }
		}
		return left
	}
	if right := rhs {
		return right
	}
	return none
}
