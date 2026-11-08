module chunking

import std_time

fn snapshot(queued_lines usize, oldest_age_ms u64) QueueSnapshot {
	return QueueSnapshot{
		queued_lines: queued_lines
		oldest_age:   std_time.Duration.from_millis(oldest_age_ms)
	}
}

fn test_smooth_mode_is_default() {
	mut policy := AdaptiveChunkingPolicy.default()
	now := std_time.Instant.now()

	decision := policy.decide(snapshot( /* queued_lines */
	1, /* oldest_age_ms */
		10), now)
	assert decision.mode == .smooth
	assert decision.entered_catch_up == false
	assert decision.drain_plan == DrainPlan.single()
}

fn test_enters_catch_up_on_depth_threshold() {
	mut policy := AdaptiveChunkingPolicy.default()
	now := std_time.Instant.now()

	decision := policy.decide(snapshot( /* queued_lines */
	8, /* oldest_age_ms */
		10), now)
	assert decision.mode == .catch_up
	assert decision.entered_catch_up == true
	assert decision.drain_plan == DrainPlan.batch(8)
}

fn test_enters_catch_up_on_age_threshold() {
	mut policy := AdaptiveChunkingPolicy.default()
	now := std_time.Instant.now()

	decision := policy.decide(snapshot( /* queued_lines */
	2, /* oldest_age_ms */
		120), now)
	assert decision.mode == .catch_up
	assert decision.entered_catch_up == true
	assert decision.drain_plan == DrainPlan.batch(2)
}

fn test_severe_backlog_uses_faster_paced_batches() {
	mut policy := AdaptiveChunkingPolicy.default()
	now := std_time.Instant.now()
	_ = policy.decide(snapshot( /* queued_lines */
	9, /* oldest_age_ms */
		10), now)

	decision := policy.decide(snapshot( /* queued_lines */
	64, /* oldest_age_ms */
		10), now.add(std_time.Duration.from_millis(5)))
	assert decision.mode == .catch_up
	assert decision.drain_plan == DrainPlan.batch(64)
}

fn test_catch_up_batch_drains_current_backlog() {
	mut policy := AdaptiveChunkingPolicy.default()
	now := std_time.Instant.now()
	decision := policy.decide(snapshot( /* queued_lines */
	512, /* oldest_age_ms */
		400), now)
	assert decision.mode == .catch_up
	assert decision.drain_plan == DrainPlan.batch(512)
}

fn test_exits_catch_up_after_hysteresis_hold() {
	mut policy := AdaptiveChunkingPolicy.default()
	t0 := std_time.Instant.now()

	_ = policy.decide(snapshot( /* queued_lines */
	9, /* oldest_age_ms */
		10), t0)
	assert policy.mode() == .catch_up

	pre_hold := policy.decide(snapshot( /* queued_lines */
	2, /* oldest_age_ms */
		40), t0.add(std_time.Duration.from_millis(200)))
	assert pre_hold.mode == .catch_up

	post_hold := policy.decide(snapshot( /* queued_lines */
	2, /* oldest_age_ms */
		40), t0.add(std_time.Duration.from_millis(460)))
	assert post_hold.mode == .smooth
	assert post_hold.drain_plan == DrainPlan.single()
}

fn test_drops_back_to_smooth_when_idle() {
	mut policy := AdaptiveChunkingPolicy.default()
	now := std_time.Instant.now()
	_ = policy.decide(snapshot( /* queued_lines */
	9, /* oldest_age_ms */
		10), now)
	assert policy.mode() == .catch_up

	decision := policy.decide(QueueSnapshot{
		queued_lines: 0
		oldest_age:   none
	}, now.add(std_time.Duration.from_millis(20)))
	assert decision.mode == .smooth
	assert decision.drain_plan == DrainPlan.single()
}

fn test_holds_reentry_after_catch_up_exit() {
	mut policy := AdaptiveChunkingPolicy.default()
	t0 := std_time.Instant.now()

	entered := policy.decide(snapshot( /* queued_lines */
	8, /* oldest_age_ms */
		20), t0)
	assert entered.mode == .catch_up

	drained := policy.decide(QueueSnapshot{
		queued_lines: 0
		oldest_age:   none
	}, t0.add(std_time.Duration.from_millis(20)))
	assert drained.mode == .smooth

	held := policy.decide(snapshot( /* queued_lines */
	8, /* oldest_age_ms */
		20), t0.add(std_time.Duration.from_millis(120)))
	assert held.mode == .smooth
	assert held.drain_plan == DrainPlan.single()

	reentered := policy.decide(snapshot( /* queued_lines */
	8, /* oldest_age_ms */
		20), t0.add(std_time.Duration.from_millis(320)))
	assert reentered.mode == .catch_up
	assert reentered.drain_plan == DrainPlan.batch(8)
}

fn test_severe_backlog_can_reenter_during_hold() {
	mut policy := AdaptiveChunkingPolicy.default()
	t0 := std_time.Instant.now()

	_ = policy.decide(snapshot( /* queued_lines */
	8, /* oldest_age_ms */
		20), t0)
	_ = policy.decide(QueueSnapshot{
		queued_lines: 0
		oldest_age:   none
	}, t0.add(std_time.Duration.from_millis(20)))

	severe := policy.decide(snapshot( /* queued_lines */
	64, /* oldest_age_ms */
		20), t0.add(std_time.Duration.from_millis(120)))
	assert severe.mode == .catch_up
	assert severe.drain_plan == DrainPlan.batch(64)
}

fn test_exit_hold_requires_continuous_low_pressure_and_known_age() {
	mut policy := AdaptiveChunkingPolicy.default()
	t0 := std_time.Instant.now()
	_ = policy.decide(snapshot(8, 10), t0)
	_ = policy.decide(snapshot(2, 40), t0.add(std_time.Duration.from_millis(100)))
	_ = policy.decide(QueueSnapshot{ queued_lines: 2, oldest_age: none }, t0.add(std_time.Duration.from_millis(350)))
	assert policy.mode() == .catch_up
	_ = policy.decide(snapshot(2, 40), t0.add(std_time.Duration.from_millis(400)))
	assert policy.decide(snapshot(2, 40), t0.add(std_time.Duration.from_millis(649))).mode == .catch_up
	assert policy.decide(snapshot(2, 40), t0.add(std_time.Duration.from_millis(650))).mode == .smooth
}

fn test_regressed_time_saturates_exit_hold_and_reentry_hold() {
	mut policy := AdaptiveChunkingPolicy.default()
	t0 := std_time.Instant.now()
	_ = policy.decide(snapshot(8, 10), t0)
	_ = policy.decide(snapshot(2, 40), t0.add(std_time.Duration.from_millis(100)))
	assert policy.decide(snapshot(2, 40), t0.sub(std_time.Duration.from_millis(100))).mode == .catch_up
	assert policy.decide(snapshot(2, 40), t0.add(std_time.Duration.from_millis(350))).mode == .smooth
	assert policy.decide(snapshot(8, 10), t0).mode == .smooth
	assert policy.decide(snapshot(8, 10), t0.add(std_time.Duration.from_millis(600))).mode == .catch_up
}

fn test_severe_age_bypasses_reentry_hold_and_transition_is_one_shot() {
	mut policy := AdaptiveChunkingPolicy.default()
	t0 := std_time.Instant.now()
	_ = policy.decide(snapshot(8, 10), t0)
	_ = policy.decide(QueueSnapshot{}, t0.add(std_time.Duration.from_millis(10)))
	assert policy.decide(snapshot(1, 299), t0.add(std_time.Duration.from_millis(20))).mode == .smooth
	entered := policy.decide(snapshot(1, 300), t0.add(std_time.Duration.from_millis(21)))
	assert entered.entered_catch_up
	assert entered.drain_plan == DrainPlan.batch(1)
	again := policy.decide(snapshot(1, 300), t0.add(std_time.Duration.from_millis(22)))
	assert !again.entered_catch_up
	assert again.mode == .catch_up
}

fn test_idle_smooth_tick_does_not_extend_reentry_hold_and_reset_removes_it() {
	mut policy := AdaptiveChunkingPolicy.default()
	t0 := std_time.Instant.now()
	_ = policy.decide(snapshot(8, 10), t0)
	_ = policy.decide(QueueSnapshot{}, t0.add(std_time.Duration.from_millis(10)))
	_ = policy.decide(QueueSnapshot{}, t0.add(std_time.Duration.from_millis(250)))
	assert policy.decide(snapshot(8, 10), t0.add(std_time.Duration.from_millis(260))).mode == .catch_up
	_ = policy.decide(QueueSnapshot{}, t0.add(std_time.Duration.from_millis(261)))
	policy.reset()
	assert policy.mode() == .smooth
	assert policy.decide(snapshot(8, 10), t0.add(std_time.Duration.from_millis(262))).entered_catch_up
}

fn test_copy_snapshot_decision_and_borrowed_policy_remain_reusable() {
	mut policy := AdaptiveChunkingPolicy.default()
	t0 := std_time.Instant.now()
	pressure := snapshot(8, 120)
	first := policy.decide(pressure, t0)
	second := policy.decide(pressure, t0)
	assert first.entered_catch_up
	assert !second.entered_catch_up
	assert first.drain_plan == second.drain_plan
	oldest := pressure.oldest_age or { panic('expected snapshot age') }
	assert oldest == std_time.Duration.from_millis(120)
	assert policy.mode() == .catch_up
	assert policy.mode() == .catch_up
	policy.reset()
	assert policy.mode() == .smooth
	assert first.mode == .catch_up
}
