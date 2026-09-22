module thread_state

import codex_app_server_protocol as api
import codex_app_server.outgoing_message
import codex_core
import codex_protocol
import codex_state
import codex_thread_store

// STUB: ConnectionCapabilities is owned by app-server/thread_state.rs.
pub struct ConnectionCapabilities {
pub:
	request_attestation bool
}

// STUB: ThreadStateRegistry is the synchronized state behind ThreadStateManager.
pub struct ThreadStateRegistry {
pub mut:
	connections       map[u64]ConnectionCapabilities
	subscriptions     map[string][]u64
	raw_event_threads map[string]bool
	listener_running  map[string]bool
	active_turn_ids   map[string]string
	active_turns      map[string]api.Turn
	pending_rollbacks map[string]outgoing_message.ConnectionRequestId
}

// STUB: PendingThreadResumeRequest is owned by app-server/thread_state.rs and retains every value
// queued to the running listener before it sends the resume response.
pub struct PendingThreadResumeRequest {
pub:
	request_id                                    outgoing_message.ConnectionRequestId
	history_items                                 []codex_thread_store.RolloutItem
	cold_resume_token_usage_turn_id               ?string
	config_snapshot                               codex_core.ThreadConfigSnapshot
	instruction_sources                           []string
	thread_summary                                api.Thread
	emit_thread_goal_update                       bool
	thread_goal_state_db                          ?codex_state.StateDbHandle
	include_turns                                 bool
	initial_turns_page                            ?api.ThreadResumeInitialTurnsPageParams
	paginated_turns                               ?[]api.Turn
	paginated_initial_turns_page                  ?api.TurnsPage
	paginated_initial_turns_page_with_active_slot ?api.TurnsPage
	resume_cursor_store                           ?codex_thread_store.ThreadStore
	redact_resume_payloads                        bool
}

// STUB: ThreadListenerCommandKind is the tag for commands consumed by the listener task.
pub enum ThreadListenerCommandKind {
	send_thread_resume_response
}

// STUB: ThreadListenerCommand is owned by app-server/thread_state.rs.
pub struct ThreadListenerCommand {
pub:
	kind           ThreadListenerCommandKind
	resume_request PendingThreadResumeRequest
}

// STUB: ThreadListenerCommandSender preserves the listener command channel's closed state.
pub struct ThreadListenerCommandSender {
pub:
	available bool
}

// STUB: sends one command to the running thread listener; false represents a closed channel.
pub fn (sender &ThreadListenerCommandSender) send(command ThreadListenerCommand) bool {
	_ = command
	return sender.available
}

// STUB: atomically records one pending rollback request; false means another is in flight.
pub fn (manager &ThreadStateManager) begin_rollback(thread_id &codex_protocol.ThreadId, request_id outgoing_message.ConnectionRequestId) bool {
	if isnil(manager.registry) {
		return true
	}
	unsafe {
		mut registry := manager.registry
		if thread_id.value in registry.pending_rollbacks {
			return false
		}
		registry.pending_rollbacks[thread_id.value] = request_id
	}
	return true
}

// STUB: clears pending rollback state after submission failure or completion.
pub fn (manager &ThreadStateManager) clear_rollback(thread_id &codex_protocol.ThreadId) {
	if isnil(manager.registry) {
		return
	}
	unsafe {
		mut registry := manager.registry
		registry.pending_rollbacks.delete(thread_id.value)
	}
}

// STUB: ThreadStateManager is owned by app-server/thread_state.rs.
pub struct ThreadStateManager {
pub:
	registry &ThreadStateRegistry = unsafe { nil }
}

// STUB: ThreadState is the per-thread synchronized listener state owned by
// app-server/thread_state.rs.
pub struct ThreadState {
pub:
	registry  &ThreadStateRegistry = unsafe { nil }
	thread_id codex_protocol.ThreadId
}

// STUB: returns the per-thread state handle used by listener lifecycle operations.
pub fn (manager &ThreadStateManager) thread_state(thread_id &codex_protocol.ThreadId) ThreadState {
	return ThreadState{
		registry:  manager.registry
		thread_id: codex_protocol.ThreadId{ value: thread_id.value.clone() }
	}
}

// STUB: borrows the command sender installed in this thread state.
pub fn (state &ThreadState) listener_command_tx() ?ThreadListenerCommandSender {
	if isnil(state.registry) {
		return none
	}
	unsafe {
		return ThreadListenerCommandSender{
			available: state.registry.listener_running[state.thread_id.value]
		}
	}
}

// STUB: records an initialized connection and its negotiated capabilities.
pub fn (manager &ThreadStateManager) connection_initialized(connection_id outgoing_message.ConnectionId, capabilities ConnectionCapabilities) {
	if isnil(manager.registry) {
		return
	}
	unsafe {
		mut registry := manager.registry
		registry.connections[connection_id.value] = capabilities
	}
}

// STUB: removes a connection and returns threads from which it was detached.
pub fn (manager &ThreadStateManager) remove_connection(connection_id outgoing_message.ConnectionId) []codex_protocol.ThreadId {
	mut affected := []codex_protocol.ThreadId{}
	if isnil(manager.registry) {
		return affected
	}
	unsafe {
		mut registry := manager.registry
		registry.connections.delete(connection_id.value)
		for thread_id, connection_ids in registry.subscriptions {
			if connection_id.value in connection_ids {
				affected << codex_protocol.ThreadId{ value: thread_id.clone() }
				registry.subscriptions[thread_id] = connection_ids.filter(it != connection_id.value)
			}
		}
	}
	return affected
}

// STUB: unsubscribes one connection and reports whether it was subscribed.
pub fn (manager &ThreadStateManager) unsubscribe_connection_from_thread(thread_id codex_protocol.ThreadId, connection_id outgoing_message.ConnectionId) bool {
	if isnil(manager.registry) {
		return false
	}
	unsafe {
		mut registry := manager.registry
		ids := registry.subscriptions[thread_id.value]
		was_subscribed := connection_id.value in ids
		registry.subscriptions[thread_id.value] = ids.filter(it != connection_id.value)
		return was_subscribed
	}
}

// STUB: attaches an initialized open connection to a thread.
pub fn (manager &ThreadStateManager) try_add_connection_to_thread(thread_id codex_protocol.ThreadId, connection_id outgoing_message.ConnectionId) bool {
	if isnil(manager.registry) {
		return false
	}
	unsafe {
		mut registry := manager.registry
		if connection_id.value !in registry.connections {
			return false
		}
		mut ids := registry.subscriptions[thread_id.value]
		if connection_id.value !in ids {
			ids << connection_id.value
			registry.subscriptions[thread_id.value] = ids
		}
	}
	return true
}

// STUB: returns the currently subscribed connection ids.
pub fn (manager &ThreadStateManager) subscribed_connection_ids(thread_id &codex_protocol.ThreadId) []outgoing_message.ConnectionId {
	mut result := []outgoing_message.ConnectionId{}
	if isnil(manager.registry) {
		return result
	}
	unsafe {
		registry := manager.registry
		for id in registry.subscriptions[thread_id.value] {
			result << outgoing_message.ConnectionId{ value: id }
		}
	}
	return result
}

// STUB: removes listener and active-turn bookkeeping for one thread.
pub fn (manager &ThreadStateManager) remove_thread_state(thread_id &codex_protocol.ThreadId) {
	if isnil(manager.registry) {
		return
	}
	unsafe {
		mut registry := manager.registry
		registry.subscriptions.delete(thread_id.value)
		registry.raw_event_threads.delete(thread_id.value)
		registry.listener_running.delete(thread_id.value)
		registry.active_turn_ids.delete(thread_id.value)
	}
}

// STUB: clears every listener/subscription while retaining initialized connections.
pub fn (manager &ThreadStateManager) clear_all_listeners() {
	if isnil(manager.registry) {
		return
	}
	unsafe {
		mut registry := manager.registry
		registry.subscriptions.clear()
		registry.raw_event_threads.clear()
		registry.listener_running.clear()
	}
}

// STUB: returns whether a connection negotiated request attestation.
pub fn (manager &ThreadStateManager) supports_attestation(connection_id outgoing_message.ConnectionId) bool {
	if isnil(manager.registry) {
		return false
	}
	unsafe {
		registry := manager.registry
		return connection_id.value in registry.connections
			&& registry.connections[connection_id.value].request_attestation
	}
}

// STUB: returns a thread's inherited raw-event listener setting.
pub fn (manager &ThreadStateManager) raw_events_enabled(thread_id &codex_protocol.ThreadId) bool {
	if isnil(manager.registry) {
		return false
	}
	unsafe {
		return manager.registry.raw_event_threads[thread_id.value]
	}
}

// STUB: snapshots the live turn projected by the app-server listener for pagination overlays.
pub fn (manager &ThreadStateManager) active_turn_snapshot(thread_id &codex_protocol.ThreadId) ?api.Turn {
	if isnil(manager.registry) {
		return none
	}
	unsafe {
		registry := manager.registry
		if thread_id.value in registry.active_turns {
			return registry.active_turns[thread_id.value]
		}
	}
	return none
}

// STUB: borrows the command sender installed by the thread's running listener task.
pub fn (manager &ThreadStateManager) listener_command_sender(thread_id &codex_protocol.ThreadId) ?ThreadListenerCommandSender {
	if isnil(manager.registry) {
		return none
	}
	unsafe {
		return ThreadListenerCommandSender{
			available: manager.registry.listener_running[thread_id.value]
		}
	}
}

// STUB: ShutdownDrainReceiver is the listener-completion receiver registered before shutdown.
pub struct ShutdownDrainReceiver {
pub:
	result ShutdownDrainWaitResult
}

// STUB: ShutdownDrainWaitResult distinguishes timeout from a stopped listener channel.
pub enum ShutdownDrainWaitResult {
	complete
	timed_out
	listener_stopped
}

// STUB: ThreadState registers the listener drain waiter used by revert shutdown coordination.
pub fn (state &ThreadState) register_shutdown_drain_waiter() ShutdownDrainReceiver {
	_ = state
	return ShutdownDrainReceiver{ result: .complete }
}

// STUB: ThreadState removes an abandoned shutdown drain waiter.
pub fn (state &ThreadState) take_shutdown_drain_waiter() {
	_ = state
}

// STUB: waits at most `timeout_ms` for the listener to drain shutdown events.
pub fn (receiver &ShutdownDrainReceiver) wait(timeout_ms u64) ShutdownDrainWaitResult {
	_ = timeout_ms
	return receiver.result
}
