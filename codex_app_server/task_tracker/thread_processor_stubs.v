module task_tracker

import tracing

// STUB: TaskTrackerState backs the tokio-util TaskTracker adaptation.
pub struct TaskTrackerState {
pub mut:
	closed  bool
	pending int
}

// STUB: TaskTracker is owned by tokio-util. This handle retains close/wait state until V async
// task tracking replaces it.
pub struct TaskTracker {
pub:
	state &TaskTrackerState = unsafe { nil }
}

// STUB: registers a spawned future with tokio-util's TaskTracker.
pub fn (tracker &TaskTracker) begin_task() bool {
	if isnil(tracker.state) {
		return true
	}
	unsafe {
		mut state := tracker.state
		if state.closed {
			return false
		}
		state.pending++
	}
	return true
}

// STUB: marks a registered future complete after its response or error side effect.
pub fn (tracker &TaskTracker) complete_task() {
	if isnil(tracker.state) {
		return
	}
	unsafe {
		mut state := tracker.state
		if state.pending > 0 {
			state.pending--
		}
	}
}

// STUB: tokio_util::task::TaskTracker::spawn registers and launches one background task.
pub fn (tracker &TaskTracker) spawn(task tracing.InstrumentedTask) {
	if !tracker.begin_task() {
		return
	}
	spawn fn [tracker, task] () {
		task.run()
		tracker.complete_task()
	}()
}

// STUB: prevents new task registration.
pub fn (tracker &TaskTracker) close() {
	if !isnil(tracker.state) {
		unsafe {
			mut state := tracker.state
			state.closed = true
		}
	}
}

// STUB: reports whether all tasks drained inside the caller's bounded timeout.
pub fn (tracker &TaskTracker) wait_bounded(timeout_ms u64) bool {
	_ = timeout_ms
	if isnil(tracker.state) {
		return true
	}
	unsafe {
		return tracker.state.pending == 0
	}
}
