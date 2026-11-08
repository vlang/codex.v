module outgoing_message

import codex_app_server_protocol as api
import codex_protocol
import tracing

// STUB: ConnectionId is owned by app-server/outgoing_message.rs.
pub struct ConnectionId {
pub:
	value u64
}

// STUB: ConnectionRequestId is owned by app-server/outgoing_message.rs.
pub struct ConnectionRequestId {
pub:
	connection_id ConnectionId
	request_id    string
}

// STUB: RequestContext is owned by app-server/outgoing_message.rs and carries the request trace.
pub struct RequestContext {
pub:
	trace ?codex_protocol.W3cTraceContext
}

// STUB: request_trace returns the W3C context captured at request ingress.
pub fn (context &RequestContext) request_trace() ?codex_protocol.W3cTraceContext {
	return context.trace
}

// STUB: returns the tracing span captured at request ingress.
pub fn (context &RequestContext) span() tracing.Span {
	_ = context
	return tracing.Span{ name: 'app_server.request' }
}

// STUB: SentResponse retains the JSON-RPC correlation id next to its typed response payload.
pub struct SentResponse {
pub:
	request_id ConnectionRequestId
	payload    api.ClientResponsePayload
}

// STUB: SentError records the complete request-correlated JSON-RPC error without dropping data.
pub struct SentError {
pub:
	request_id ConnectionRequestId
	error      api.JSONRPCErrorError
}

// STUB: OutgoingMessageState is the observable queue behind the untranslated channel sender.
pub struct OutgoingMessageState {
pub mut:
	responses      []SentResponse
	notifications  []string
	errors         []SentError
	warnings       []string
	cancellations  []string
	request_traces map[string]codex_protocol.W3cTraceContext
}

// STUB: OutgoingMessageSender is owned by app-server/outgoing_message.rs.
pub struct OutgoingMessageSender {
pub:
	state &OutgoingMessageState = unsafe { nil }
}

// STUB: queues one request-correlated JSON-RPC response.
pub fn (sender &OutgoingMessageSender) send_response(request_id ConnectionRequestId, payload api.ClientResponsePayload) {
	if isnil(sender.state) {
		return
	}
	unsafe {
		mut state := sender.state
		state.responses << SentResponse{ request_id: request_id, payload: payload }
	}
}

// STUB: sends a request-correlated response while retaining the originating thread source.
pub fn (sender &OutgoingMessageSender) send_response_with_thread_originator(request_id ConnectionRequestId, payload api.ClientResponsePayload, thread_originator string) {
	_ = thread_originator
	sender.send_response(request_id, payload)
}

// STUB: queues one request-correlated JSON-RPC error.
pub fn (sender &OutgoingMessageSender) send_error(request_id ConnectionRequestId, rpc_error api.JSONRPCErrorError) {
	if isnil(sender.state) {
		return
	}
	unsafe {
		mut state := sender.state
		state.errors << SentError{ request_id: request_id, error: rpc_error }
	}
}

// STUB: broadcasts one typed generated server notification to initialized connections.
pub fn (sender &OutgoingMessageSender) send_server_notification(notification api.ServerNotification) {
	if isnil(sender.state) {
		return
	}
	unsafe {
		mut state := sender.state
		state.notifications << match notification {
			api.ConfigWarningNotification { 'config_warning' }
			api.ItemCompletedNotification { 'item_completed' }
			api.TurnCompletedNotification { 'turn_completed' }
			api.DeprecationNoticeNotification { 'deprecation_notice' }
			api.ThreadArchivedNotification { 'thread_archived' }
			api.ThreadNameUpdatedNotification { 'thread_name_updated' }
			api.ThreadProjectUpdatedNotification { 'thread_project_updated' }
			api.ThreadRevertedNotification { 'thread_reverted' }
			api.ThreadStartedNotification { 'thread_started' }
			api.ThreadUnarchivedNotification { 'thread_unarchived' }
		}
	}
}

// STUB: sends one typed generated server notification only to the listed connections.
pub fn (sender &OutgoingMessageSender) send_server_notification_to_connections(connection_ids &[]ConnectionId, notification api.ServerNotification) {
	_ = connection_ids
	sender.send_server_notification(notification)
}

// STUB: queues the restored token-usage update that follows a resume response.
pub fn (sender &OutgoingMessageSender) send_restored_usage(connection_id ConnectionId, thread_id &string, turn_id &string) {
	if isnil(sender.state) {
		return
	}
	unsafe {
		mut state := sender.state
		state.notifications << 'thread/tokenUsage/updated:${connection_id.value}:${*thread_id}:${*turn_id}'
	}
}

// STUB: records a tracing warning without emitting a protocol notification.
pub fn (sender &OutgoingMessageSender) log_warning(message &string) {
	if isnil(sender.state) {
		return
	}
	unsafe {
		mut state := sender.state
		state.warnings << message.clone()
	}
}

// STUB: retrieves the trace captured for this request.
pub fn (sender &OutgoingMessageSender) request_trace_context(request_id &ConnectionRequestId) ?codex_protocol.W3cTraceContext {
	if isnil(sender.state) {
		return none
	}
	key := '${request_id.connection_id.value}:${request_id.request_id}'
	unsafe {
		state := sender.state
		if key in state.request_traces {
			return state.request_traces[key]
		}
	}
	return none
}

// STUB: cancels outstanding request routing for a removed thread.
pub fn (sender &OutgoingMessageSender) cancel_requests_for_thread(thread_id codex_protocol.ThreadId) {
	if isnil(sender.state) {
		return
	}
	unsafe {
		mut state := sender.state
		state.cancellations << thread_id.value
	}
}
