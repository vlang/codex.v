// Adaptive stream chunking policy for commit animation ticks.
//
// This policy preserves the baseline user experience while adapting to bursty
// stream input. In [`ChunkingMode::Smooth`], one queued line is drained per
// baseline commit tick. When queue pressure rises, it switches to
// [`ChunkingMode::CatchUp`] and drains queued backlog immediately so display
// lag converges as quickly as possible.
//
// The policy is source-agnostic: it depends only on queue depth and queue
// age from [`QueueSnapshot`]. It does not branch on source identity or explicit
// throughput targets.
//
// # Mental model
//
// Think of this as a two-gear system:
//
// - [`ChunkingMode::Smooth`]: steady baseline display pacing.
// - [`ChunkingMode::CatchUp`]: full queue draining while backlog exists.
//
// The transition logic intentionally uses hysteresis:
//
// - enter catch-up on higher-pressure thresholds
// - exit catch-up on lower-pressure thresholds, held for [`EXIT_HOLD`]
// - after exit, suppress immediate re-entry for [`REENTER_CATCH_UP_HOLD`]
//   unless backlog is severe
//
// This avoids rapid gear-flapping near threshold boundaries.
//
// # Policy flow
//
// On each decision tick, [`AdaptiveChunkingPolicy::decide`] does:
//
// 1. If queue is empty, reset to [`ChunkingMode::Smooth`].
// 2. If currently smooth, call [`AdaptiveChunkingPolicy::maybe_enter_catch_up`].
// 3. If currently catch-up, call [`AdaptiveChunkingPolicy::maybe_exit_catch_up`].
// 4. Build [`DrainPlan`] (`Single` for smooth, `Batch(queued_lines)` for catch-up).
//
// # Concrete examples
//
// With current defaults:
//
// - `Smooth` drains one line per commit tick.
// - `CatchUp` drains all currently queued lines in a tick.
//
// # Tuning guide (in code terms)
//
// Prefer tuning in this order so causes remain clear:
//
// 1. enter/exit thresholds: [`ENTER_QUEUE_DEPTH_LINES`], [`ENTER_OLDEST_AGE`],
//    [`EXIT_QUEUE_DEPTH_LINES`], [`EXIT_OLDEST_AGE`]
// 2. hysteresis windows: [`EXIT_HOLD`], [`REENTER_CATCH_UP_HOLD`]
// 3. severe gates: [`SEVERE_QUEUE_DEPTH_LINES`], [`SEVERE_OLDEST_AGE`]
//
// Symptom-oriented adjustments:
//
// - lag starts too late: lower enter thresholds
// - frequent smooth/catch-up chatter: increase hold windows, or tighten exit
//   thresholds
// - catch-up re-enters too eagerly after exit: increase re-entry hold
//
// # Responsibilities
//
// - track mode and hysteresis state
// - produce deterministic [`ChunkingDecision`] values from queue snapshots
// - preserve queue order by draining from queue head only
//
// # Non-responsibilities
//
// - scheduling commit ticks
// - reordering stream lines
// - transport/source-specific semantics
//
// Markdown docs remain supplemental:
//
// - `docs/tui-stream-chunking-review.md`
// - `docs/tui-stream-chunking-tuning.md`
// - `docs/tui-stream-chunking-validation.md`

module chunking

import std_time

// Queue-depth threshold that allows entering catch-up mode.
//
// Crossing this threshold alone is sufficient to leave smooth mode.
const enter_queue_depth_lines = usize(8)

// Oldest-line age threshold that allows entering catch-up mode.
//
// Crossing this threshold alone is sufficient to leave smooth mode.
const enter_oldest_age = std_time.Duration.from_millis(120)

// Queue-depth threshold used when evaluating catch-up exit hysteresis.
//
// Depth must be at or below this value before exit hold timing can begin.
const exit_queue_depth_lines = usize(2)

// Oldest-line age threshold used when evaluating catch-up exit hysteresis.
//
// Age must be at or below this value before exit hold timing can begin.
const exit_oldest_age = std_time.Duration.from_millis(40)

// Minimum duration queue pressure must stay below exit thresholds to leave catch-up mode.
const exit_hold = std_time.Duration.from_millis(250)

// Cooldown window after a catch-up exit that suppresses immediate re-entry.
//
// Severe backlog still bypasses this hold to avoid unbounded queue-age growth.
const reenter_catch_up_hold = std_time.Duration.from_millis(250)

// Queue-depth cutoff that marks backlog as severe for faster convergence.
//
// This threshold is used to bypass re-entry hold after a recent catch-up exit.
const severe_queue_depth_lines = usize(64)

// Oldest-line age cutoff that marks backlog as severe for faster convergence.
const severe_oldest_age = std_time.Duration.from_millis(300)

// These scalar-only types retain Rust's derived Clone/Copy and equality semantics.
// V's first enum variant is the default, and structural formatting supplies Debug.
pub enum ChunkingMode {
	// Drain one line per baseline commit tick.
	smooth
	// Drain multiple lines per tick according to queue pressure.
	catch_up
}

// Captures queue pressure inputs used by adaptive chunking decisions.
pub struct QueueSnapshot {
pub:
	// Number of queued stream lines waiting to be displayed.
	queued_lines usize
	// Age of the oldest queued line at decision time.
	oldest_age ?std_time.Duration
}

// A scalar tag and payload preserve DrainPlan's payload variant and Copy behavior in V.
pub enum DrainPlanKind {
	single
	batch
}

pub struct DrainPlan {
pub:
	// Emit exactly one queued line, or emit up to `usize` queued lines for a batch.
	kind         DrainPlanKind
	queued_lines usize
}

// Emit exactly one queued line.
pub fn DrainPlan.single() DrainPlan {
	return DrainPlan{ kind: .single }
}

// Emit up to `usize` queued lines.
pub fn DrainPlan.batch(queued_lines usize) DrainPlan {
	return DrainPlan{ kind: .batch, queued_lines: queued_lines }
}

// Represents one policy decision for a specific queue snapshot.
pub struct ChunkingDecision {
pub:
	// Mode after applying hysteresis transitions for this decision.
	mode ChunkingMode
	// Whether this decision transitioned from `Smooth` into `CatchUp`.
	entered_catch_up bool
	// Drain plan to execute for the current commit tick.
	drain_plan DrainPlan
}

// Maintains adaptive chunking mode and hysteresis state across ticks.
pub struct AdaptiveChunkingPolicy {
mut:
	// V does not allow a field and method to share a name; current_mode is Rust's mode field.
	current_mode               ChunkingMode
	below_exit_threshold_since ?std_time.Instant
	last_catch_up_exit_at      ?std_time.Instant
}

pub fn AdaptiveChunkingPolicy.default() AdaptiveChunkingPolicy {
	return AdaptiveChunkingPolicy{}
}

// Returns the policy mode used by the most recent decision.
pub fn (policy &AdaptiveChunkingPolicy) mode() ChunkingMode {
	return policy.current_mode
}

// Resets state to baseline smooth mode.
pub fn (mut policy AdaptiveChunkingPolicy) reset() {
	policy.current_mode = .smooth
	policy.below_exit_threshold_since = none
	policy.last_catch_up_exit_at = none
}

// Computes a drain decision from the current queue snapshot.
//
// The decision is deterministic for a given `(mode, snapshot, now)` triple. Callers should
// avoid inventing synthetic snapshots; stale queue age data can cause premature catch-up exits.
pub fn (mut policy AdaptiveChunkingPolicy) decide(snapshot QueueSnapshot, now std_time.Instant) ChunkingDecision {
	if snapshot.queued_lines == 0 {
		policy.note_catch_up_exit(now)
		policy.current_mode = .smooth
		policy.below_exit_threshold_since = none
		return ChunkingDecision{
			mode:             policy.current_mode
			entered_catch_up: false
			drain_plan:       DrainPlan.single()
		}
	}

	entered_catch_up := match policy.current_mode {
		.smooth { policy.maybe_enter_catch_up(snapshot, now) }
		.catch_up {
			policy.maybe_exit_catch_up(snapshot, now)
			false
		}
	}

	drain_plan := match policy.current_mode {
		.smooth { DrainPlan.single() }
		.catch_up {
			DrainPlan.batch(if snapshot.queued_lines > 1 { snapshot.queued_lines } else { usize(1) })
		}
	}

	return ChunkingDecision{
		mode:             policy.current_mode
		entered_catch_up: entered_catch_up
		drain_plan:       drain_plan
	}
}

// Switches from `Smooth` to `CatchUp` when enter thresholds are crossed.
//
// Returns `true` only on the transition tick so callers can emit one-shot
// transition observability.
fn (mut policy AdaptiveChunkingPolicy) maybe_enter_catch_up(snapshot QueueSnapshot, now std_time.Instant) bool {
	if !should_enter_catch_up(snapshot) {
		return false
	}
	if policy.reentry_hold_active(now) && !is_severe_backlog(snapshot) {
		return false
	}
	policy.current_mode = .catch_up
	policy.below_exit_threshold_since = none
	policy.last_catch_up_exit_at = none
	return true
}

// Applies exit hysteresis while in `CatchUp` mode.
//
// The policy requires queue pressure to stay below exit thresholds for the
// full `EXIT_HOLD` window before returning to `Smooth`.
fn (mut policy AdaptiveChunkingPolicy) maybe_exit_catch_up(snapshot QueueSnapshot, now std_time.Instant) {
	if !should_exit_catch_up(snapshot) {
		policy.below_exit_threshold_since = none
		return
	}

	if since := policy.below_exit_threshold_since {
		if now.saturating_duration_since(since) >= exit_hold {
			policy.current_mode = .smooth
			policy.below_exit_threshold_since = none
			policy.last_catch_up_exit_at = now
		}
	} else {
		policy.below_exit_threshold_since = now
	}
}

fn (mut policy AdaptiveChunkingPolicy) note_catch_up_exit(now std_time.Instant) {
	if policy.current_mode == .catch_up {
		policy.last_catch_up_exit_at = now
	}
}

fn (policy &AdaptiveChunkingPolicy) reentry_hold_active(now std_time.Instant) bool {
	if exit := policy.last_catch_up_exit_at {
		return now.saturating_duration_since(exit) < reenter_catch_up_hold
	}
	return false
}

// Returns whether current queue pressure warrants entering catch-up mode.
//
// Either depth or age pressure is sufficient to trigger catch-up.
fn should_enter_catch_up(snapshot QueueSnapshot) bool {
	if snapshot.queued_lines >= enter_queue_depth_lines {
		return true
	}
	if oldest := snapshot.oldest_age {
		return oldest >= enter_oldest_age
	}
	return false
}

// Returns whether queue pressure is low enough to begin exit hysteresis.
//
// Both depth and age must be below thresholds; this prevents oscillation when
// one signal is still under load.
fn should_exit_catch_up(snapshot QueueSnapshot) bool {
	if snapshot.queued_lines > exit_queue_depth_lines {
		return false
	}
	if oldest := snapshot.oldest_age {
		return oldest <= exit_oldest_age
	}
	return false
}

// Returns whether backlog is severe enough to use a faster catch-up target.
//
// Severe pressure bypasses re-entry hold to avoid queue-age growth after a
// recent catch-up exit.
fn is_severe_backlog(snapshot QueueSnapshot) bool {
	if snapshot.queued_lines >= severe_queue_depth_lines {
		return true
	}
	if oldest := snapshot.oldest_age {
		return oldest >= severe_oldest_age
	}
	return false
}
