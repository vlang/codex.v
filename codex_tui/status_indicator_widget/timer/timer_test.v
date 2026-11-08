module timer

import std_time

fn test_pauses_and_resumes_without_counting_wait_time() {
	baseline := std_time.Instant.now()
	mut status_timer := StatusTimer{
		...StatusTimer.default()
		last_resume_at: baseline
	}
	status_timer.pause_at(baseline.add(std_time.Duration.from_secs(5)))
	status_timer.pause_at(baseline.add(std_time.Duration.from_secs(8)))
	assert status_timer.elapsed_at(baseline.add(std_time.Duration.from_secs(10))) == std_time.Duration.from_secs(5)
	status_timer.resume_at(baseline.add(std_time.Duration.from_secs(10)))
	status_timer.resume_at(baseline.add(std_time.Duration.from_secs(12)))
	assert status_timer.elapsed_at(baseline.add(std_time.Duration.from_secs(13))) == std_time.Duration.from_secs(8)
	status_timer.reset(std_time.Duration.from_secs(24))
	assert status_timer.elapsed_at(status_timer.last_resume_at) == std_time.Duration.from_secs(24)
	status_timer.pause_at(status_timer.last_resume_at)
	status_timer.reset(std_time.duration_zero)
	assert status_timer.elapsed_at(status_timer.last_resume_at.add(std_time.Duration.from_secs( /*secs*/
	120))) == std_time.duration_zero
}

fn test_phase_origin_remains_independent_during_pause_resume_and_reset() {
	baseline := std_time.Instant.now()
	phase := baseline.sub(std_time.Duration.from_secs(900))
	mut status_timer := StatusTimer{
		display_started_at: phase
		elapsed_running:    std_time.Duration.from_secs(3)
		last_resume_at:     baseline
	}
	assert status_timer.elapsed_at(baseline.add(std_time.Duration.from_secs(4))) == std_time.Duration.from_secs(7)
	status_timer.pause_at(baseline.add(std_time.Duration.from_secs(4)))
	status_timer.reset(std_time.Duration.from_secs(18))
	assert status_timer.display_started_at == ?std_time.Instant(phase)
	assert status_timer.is_paused
	assert status_timer.elapsed_at(baseline.add(std_time.Duration.from_secs(1_000))) == std_time.Duration.from_secs(18)
	status_timer.resume_at(baseline.add(std_time.Duration.from_secs(10)))
	assert status_timer.elapsed_at(baseline.add(std_time.Duration.from_secs(11))) == std_time.Duration.from_secs(19)
	status_timer.display_started_at = none
	assert status_timer.elapsed_at(baseline.add(std_time.Duration.from_secs(11))) == std_time.Duration.from_secs(19)
}

fn test_running_reset_replaces_accounting_and_starts_a_new_interval() {
	baseline := std_time.Instant.now()
	mut status_timer := StatusTimer{
		display_started_at: baseline
		elapsed_running:    std_time.Duration.from_secs(40)
		last_resume_at:     baseline.sub(std_time.Duration.from_secs(10))
	}
	before_reset := std_time.Instant.now()
	status_timer.reset(std_time.Duration.from_secs(17))
	after_reset := std_time.Instant.now()
	assert status_timer.last_resume_at >= before_reset
	assert status_timer.last_resume_at <= after_reset
	assert status_timer.display_started_at == ?std_time.Instant(baseline)
	assert !status_timer.is_paused
	assert status_timer.elapsed_at(status_timer.last_resume_at.add(std_time.Duration.from_secs(7))) == std_time.Duration.from_secs(24)
}

fn test_regressed_clocks_saturate_without_reducing_running_time() {
	baseline := std_time.Instant.now()
	mut status_timer := StatusTimer{
		elapsed_running: std_time.Duration.from_secs(4)
		last_resume_at:  baseline
	}
	earlier := baseline.sub(std_time.Duration.from_secs(2))
	assert status_timer.elapsed_at(earlier) == std_time.Duration.from_secs(4)
	status_timer.pause_at(earlier)
	assert status_timer.elapsed_running == std_time.Duration.from_secs(4)
	status_timer.pause_at(baseline.add(std_time.Duration.from_secs(8)))
	assert status_timer.elapsed_at(baseline.add(std_time.Duration.from_secs(100))) == std_time.Duration.from_secs(4)
	status_timer.resume_at(baseline.add(std_time.Duration.from_secs(10)))
	assert status_timer.elapsed_at(baseline.add(std_time.Duration.from_secs(9))) == std_time.Duration.from_secs(4)
	assert status_timer.elapsed_at(baseline.add(std_time.Duration.from_secs(13))) == std_time.Duration.from_secs(7)
}

fn test_borrowed_reads_leave_timer_and_copy_clock_arguments_reusable() {
	baseline := std_time.Instant.now()
	interval := std_time.Duration.from_secs(2)
	mut status_timer := StatusTimer{
		display_started_at: baseline
		last_resume_at:     baseline
	}
	borrowed := &status_timer
	assert borrowed.elapsed_at(baseline.add(interval)) == interval
	assert borrowed.elapsed_at(baseline.add(interval)) == interval
	assert status_timer.display_started_at == ?std_time.Instant(baseline)
	assert status_timer.last_resume_at == baseline
	status_timer.pause_at(baseline.add(interval))
	assert borrowed.elapsed_at(baseline.add(std_time.Duration.from_secs(5))) == interval
	status_timer.reset(interval)
	assert interval == std_time.Duration.from_secs(2)
	assert status_timer.elapsed_at(status_timer.last_resume_at) == interval
	assert status_timer.display_started_at == ?std_time.Instant(baseline)
}
