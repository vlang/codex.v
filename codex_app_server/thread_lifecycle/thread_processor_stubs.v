module thread_lifecycle

import codex_app_server.outgoing_message
import codex_app_server.skills_watcher
import codex_app_server.thread_state
import codex_app_server.thread_status
import codex_app_server.turn_cost_worker
import codex_app_server_protocol as api
import codex_core
import codex_protocol
import codex_thread_store
import sync

// STUB: PendingThreadUnloadSet is the shared Arc<Mutex<HashSet<ThreadId>>> used by
// app-server/request_processors/thread_lifecycle.rs.
pub struct PendingThreadUnloadSet {
pub:
	state &PendingThreadUnloadState = unsafe { nil }
}

// STUB: PendingThreadUnloadState is the synchronized storage behind PendingThreadUnloadSet.
pub struct PendingThreadUnloadState {
pub mut:
	mutex sync.Mutex
	ids   map[string]bool
}

// STUB: checks whether a thread is currently being unloaded.
pub fn (set &PendingThreadUnloadSet) contains(thread_id &string) bool {
	if isnil(set.state) {
		return false
	}
	set.state.mutex.lock()
	defer {
		set.state.mutex.unlock()
	}
	unsafe {
		return set.state.ids[*thread_id]
	}
}

// STUB: removes a completed unload from the shared set.
pub fn (set &PendingThreadUnloadSet) remove(thread_id &string) {
	if isnil(set.state) {
		return
	}
	set.state.mutex.lock()
	defer {
		set.state.mutex.unlock()
	}
	unsafe {
		mut state := set.state
		state.ids.delete(*thread_id)
	}
}

// STUB: ListenerTaskContext is owned by app-server/request_processors/thread_lifecycle.rs. It
// preserves every dependency captured by the Rust listener task.
pub struct ListenerTaskContext {
pub:
	thread_manager          codex_core.ThreadManager
	thread_state_manager    thread_state.ThreadStateManager
	outgoing                outgoing_message.OutgoingMessageSender
	pending_thread_unloads  PendingThreadUnloadSet
	thread_watch_manager    thread_status.ThreadWatchManager
	thread_list_permit_open bool
	fallback_model_provider string
	codex_home              string
	thread_unload_delay_ms  u64
	skills_watcher          skills_watcher.SkillsWatcher
	turn_cost_worker        ?turn_cost_worker.TurnCostWorkerHandle
}

// STUB: EnsureConversationListenerResult is the lifecycle attach outcome.
pub enum EnsureConversationListenerResult {
	attached
	connection_closed
}

// STUB: ListenerAttachResultKind adapts the lifecycle logger's typed Rust `Result` argument.
pub enum ListenerAttachResultKind {
	ok
	error
}

// STUB: ListenerAttachResult preserves either the listener outcome or its JSON-RPC error message.
pub struct ListenerAttachResult {
pub:
	kind          ListenerAttachResultKind
	value         EnsureConversationListenerResult
	error_message string
}

// STUB: attaches an open initialized connection and starts its listener task if necessary.
pub fn ensure_conversation_listener(context &ListenerTaskContext, conversation_id codex_protocol.ThreadId, connection_id outgoing_message.ConnectionId, raw_events_enabled bool) !EnsureConversationListenerResult {
	if !context.thread_state_manager.try_add_connection_to_thread(conversation_id, connection_id) {
		return EnsureConversationListenerResult.connection_closed
	}
	_ = raw_events_enabled
	return EnsureConversationListenerResult.attached
}

// STUB: logs the outcome of every automatic listener attachment.
pub fn log_listener_attach_result(result ListenerAttachResult, thread_id codex_protocol.ThreadId, connection_id outgoing_message.ConnectionId, thread_kind &string) {
	_ = result
	_ = thread_id
	_ = connection_id
	_ = thread_kind
}

// STUB: starts a listener task using the existing thread state retained across reload.
pub fn ensure_listener_task_running(context &ListenerTaskContext, conversation_id codex_protocol.ThreadId, conversation &codex_core.CodexThread, state &thread_state.ThreadState) ! {
	_ = context
	_ = conversation_id
	_ = conversation
	_ = state
}

// STUB: populates the legacy API turn projection from rollout history and overlays a live turn.
pub fn populate_thread_turns_from_history(mut thread_value api.Thread, history &[]codex_thread_store.RolloutItem, active_turn ?api.Turn) {
	mut turns := []api.Turn{}
	for item in *history {
		match item.kind {
			.turn { turns << item.turn }
			.user_message {
				turns << api.Turn{
					id:         'turn-${turns.len + 1}'
					items:      [api.ThreadItem{
						id:      'user-${turns.len + 1}'
						kind:    .user_message
						content: [item.message.clone()]
					}]
					items_view: .full
					status:     .completed
				}
			}
			.agent_message {
				if turns.len > 0 {
					turns.last().items << api.ThreadItem{
						id:      'agent-${turns.len}'
						kind:    .agent_message
						content: [item.message.clone()]
					}
				}
			}
			.session_meta, .response_item, .other {}
		}
	}
	if live_turn := active_turn {
		mut replaced := false
		for index, turn in turns {
			if turn.id == live_turn.id {
				turns[index] = live_turn
				replaced = true
				break
			}
		}
		if !replaced {
			turns << live_turn
		}
	}
	thread_value.turns = turns
}
