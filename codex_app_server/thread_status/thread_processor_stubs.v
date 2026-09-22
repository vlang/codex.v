module thread_status

import codex_app_server_protocol as api

// STUB: ThreadWatchState backs the watch channels owned by app-server/thread_status.rs.
pub struct ThreadWatchState {
pub mut:
	statuses                     map[string]api.ThreadStatus
	running_assistant_turn_count int
}

// STUB: ThreadWatchManager is owned by app-server/thread_status.rs.
pub struct ThreadWatchManager {
pub:
	state &ThreadWatchState = unsafe { nil }
}

// STUB: RunningTurnCountReceiver preserves watch-receiver semantics rather than returning a
// one-time integer snapshot.
pub struct RunningTurnCountReceiver {
pub:
	state &ThreadWatchState = unsafe { nil }
}

// STUB: borrows the latest watch value.
pub fn (receiver &RunningTurnCountReceiver) value() int {
	if isnil(receiver.state) {
		return 0
	}
	unsafe {
		return receiver.state.running_assistant_turn_count
	}
}

// STUB: subscribes to running-assistant-turn changes.
pub fn (manager &ThreadWatchManager) subscribe_running_turn_count() RunningTurnCountReceiver {
	return RunningTurnCountReceiver{ state: manager.state }
}

// STUB: inserts a watch entry without sending an update.
pub fn (manager &ThreadWatchManager) upsert_thread_silently(thread_id &string) {
	if isnil(manager.state) {
		return
	}
	unsafe {
		mut state := manager.state
		if *thread_id !in state.statuses {
			state.statuses[*thread_id] = api.ThreadStatus{ kind: .idle }
		}
	}
}

// STUB: inserts a watch entry and publishes the normal thread-status update.
pub fn (manager &ThreadWatchManager) upsert_thread(thread_id &string) {
	manager.upsert_thread_silently(thread_id)
}

// STUB: removes a thread's watch entry.
pub fn (manager &ThreadWatchManager) remove_thread(thread_id &string) {
	if isnil(manager.state) {
		return
	}
	unsafe {
		mut state := manager.state
		state.statuses.delete(*thread_id)
	}
}

// STUB: reads a loaded thread status.
pub fn (manager &ThreadWatchManager) loaded_status_for_thread(thread_id &string) api.ThreadStatus {
	if isnil(manager.state) {
		return api.ThreadStatus{ kind: .not_loaded }
	}
	unsafe {
		state := manager.state
		return state.statuses[*thread_id] or { api.ThreadStatus{ kind: .not_loaded } }
	}
}

// STUB: returns one consistent watch snapshot for a batch of loaded thread ids.
pub fn (manager &ThreadWatchManager) loaded_statuses_for_threads(thread_ids []string) map[string]api.ThreadStatus {
	mut statuses := map[string]api.ThreadStatus{}
	if isnil(manager.state) {
		return statuses
	}
	unsafe {
		state := manager.state
		for thread_id in thread_ids {
			if thread_id in state.statuses {
				statuses[thread_id] = state.statuses[thread_id]
			}
		}
	}
	return statuses
}
