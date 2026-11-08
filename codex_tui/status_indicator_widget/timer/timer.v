// Pause-aware status time owned independently of the optional status row.
// A phase can override the displayed clock without changing turn accounting.
module timer

import std_time

// V's structural formatting supplies Rust's derived Debug. Allocation-free Instant and
// Duration fields retain Rust's Copy semantics, including the optional phase origin.
pub struct StatusTimer {
pub mut:
	// Optional wall-clock origin for the displayed phase, without resetting turn accounting.
	display_started_at ?std_time.Instant
	// V has no pub(super); these fields remain public for the eventual parent widget module.
	elapsed_running std_time.Duration
	last_resume_at  std_time.Instant
	is_paused       bool
}

pub fn StatusTimer.default() StatusTimer {
	return StatusTimer{
		display_started_at: none
		elapsed_running:    std_time.duration_zero
		last_resume_at:     std_time.Instant.now()
		is_paused:          false
	}
}

pub fn (mut status_timer StatusTimer) reset(elapsed std_time.Duration) {
	status_timer.elapsed_running = elapsed
	status_timer.last_resume_at = std_time.Instant.now()
	// A turn can start while an MCP elicitation or approval is still open.
	// Reset elapsed time without changing that modal's pause state.
}

pub fn (mut status_timer StatusTimer) pause_at(now std_time.Instant) {
	if !status_timer.is_paused {
		status_timer.elapsed_running = status_timer.elapsed_running.add(now.saturating_duration_since(status_timer.last_resume_at))
		status_timer.is_paused = true
	}
}

pub fn (mut status_timer StatusTimer) resume_at(now std_time.Instant) {
	if status_timer.is_paused {
		status_timer.last_resume_at = now
		status_timer.is_paused = false
	}
}

pub fn (status_timer &StatusTimer) elapsed_at(now std_time.Instant) std_time.Duration {
	return status_timer.elapsed_running.add(if status_timer.is_paused {
		std_time.duration_zero
	} else {
		now.saturating_duration_since(status_timer.last_resume_at)
	})
}
