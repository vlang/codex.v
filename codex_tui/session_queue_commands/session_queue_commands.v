// Queue user messages through a local or remote app server.
module session_queue_commands

import codex_app_server_client
import codex_app_server_protocol as api
import codex_protocol
import codex_protocol.thread_id
import codex_tui
import codex_tui.named_session_lookup
import codex_tui.session_archive_commands
import codex_utils_home_dir
import color_eyre.eyre
import std_path
import uuid

const jsonrpc_invalid_request = i64(-32600)
const jsonrpc_method_not_found = i64(-32601)
const thread_queue_add_method = 'thread/queue/add'

// Async awaits become synchronous calls at the untranslated typed transport
// boundary. Owned command arguments stay alive across the action's shared borrows.
pub fn run_session_queue_command(target string, message string, options session_archive_commands.SessionArchiveCommandOptions) !string {
	codex_home := codex_utils_home_dir.find_codex_home() or {
		return eyre.wrap_err(err, 'failed to find Codex home')
	}
	explicit_remote := options.explicit_remote_endpoint != none
	mut app_server := session_archive_commands.start_app_server_for_session_command(options,
		codex_home.to_path_buf())!
	home_path := codex_home.as_path()
	if !explicit_remote && app_server.uses_embedded_app_server()
		&& codex_tui.maybe_probe_default_daemon_socket(&home_path) != none {
		return error('cannot queue through an embedded app server while a local app-server daemon is running; remove configuration overrides or use --remote')
	}
	implicit_local_daemon := !explicit_remote && !app_server.uses_embedded_app_server()
	client_message_id := uuid.Uuid.now_v7().str()

	id, response := run_session_queue_action_with_app_server(mut app_server, &home_path,
		&target, &message, &client_message_id) or {
		if (implicit_local_daemon || explicit_remote) && is_unsupported_queue_error(&err) {
			server := if explicit_remote { 'remote app server' } else { 'local app-server daemon' }
			return eyre.wrap_err(err,
				'the ${server} does not support thread/queue/add; update or restart the ${server}')
		}
		return err
	}

	return 'Queued message ${response.queued_submission.id} for thread ${id}.'
}

// V has no pub(super); the action is exported for sibling modules and its tests.
pub fn run_session_queue_action_with_app_server(mut app_server codex_tui.AppServerSession, codex_home &std_path.Path, target &string, message &string, client_message_id &string) !(codex_protocol.ThreadId, api.ThreadQueueAddResponse) {
	id := if parsed := thread_id.from_string(target) {
		parsed
	} else {
		collections := [named_session_lookup.SessionCollection.active]
		source_kind_filters := [
			codex_tui.resume_source_kinds( /*include_non_interactive*/
			true),
			// An empty filter includes Atlas/ChatGPT sessions.
			[]api.ThreadSourceKind{},
		]
		provider := named_session_lookup.BorrowedModelProvider{}
		selected := named_session_lookup.lookup(mut app_server, codex_home, target, &collections,
			&source_kind_filters, /*model_provider*/
			&provider)!
		if !selected.has_value {
			return error("No active session found matching '${*target}'.")
		}
		listed_thread := selected.value
		thread_id.from_string(&listed_thread.id) or {
			return eyre.wrap_err(err, 'app server returned invalid session id `${listed_thread.id}`')
		}
	}
	request_id := app_server.next_request_id()
	response := app_server.request_handle().request_typed[api.ThreadQueueAddResponse](api.ClientRequestThreadQueueAdd{
		request_id: request_id
		params:     api.ThreadQueueAddParams{
			thread_id:              id.str()
			input:                  [api.UserInput(api.UserInputText{
				text:          message.clone()
				text_elements: []api.TextElement{}
			})]
			client_user_message_id: client_message_id.clone()
		}
	}) or { return eyre.wrap_err(err, 'failed to queue session message') }
	return id, response
}

// V's result interface carries eyre reports and their typed causes together.
// Borrow through Report contexts before narrowing, preserving downcast_ref behavior.
fn is_unsupported_queue_error(failure &IError) bool {
	cause := eyre.root_cause(failure)
	if cause is codex_app_server_client.TypedRequestError {
		return cause.kind == .server && cause.method == thread_queue_add_method
			&& (cause.server_source.code == jsonrpc_method_not_found
				|| (cause.server_source.code == jsonrpc_invalid_request
					&& (cause.server_source.message == api.experimental_required_message(&thread_queue_add_method)
						|| cause.server_source.message.starts_with('Invalid request: unknown variant `thread/queue/add`'))))
	}
	return false
}
