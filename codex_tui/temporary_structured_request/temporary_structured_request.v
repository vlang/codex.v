// Run isolated structured requests through existing app-server methods.
module temporary_structured_request

import codex_app_server_client
import codex_app_server_protocol
import codex_protocol
import codex_protocol.openai_models
import serde_json
import std_time
import tokio.sync.mpsc
import tokio.time as tokio_time
import tracing
import uuid

const structured_turn_timeout = std_time.Duration.from_secs( /*secs*/
30)
const structured_response_max_bytes = usize(8 * 1024)

// Preserve the visible thread's provider, permissions, and external-tool isolation.
// V uses public cross-module names for Rust's pub(crate) surface.
pub struct TemporaryStructuredThreadOptions {
pub:
	model                     string
	model_provider            string
	cwd                       string
	active_permission_profile ?string
	mcp_server_names          []string
}

// The V timeout worker consumes this future's captured owned data once. A cloned
// shared request handle lease keeps its transport alive if the worker finishes
// after the deadline; Tokio would instead cancel the dropped future.
struct StartOperation {
	request_handle            codex_app_server_client.AppServerRequestHandle
	model                     string
	model_provider            string
	cwd                       string
	custom_permission_profile ?string
	mcp_server_names          []string
	config                    map[string]serde_json.Value
	deadline                  std_time.Instant
}

// Start an ephemeral thread without widening permissions or exposing tools and environment access.
//
// Structured prompts can contain untrusted transcript text, so the effective app-server config is
// read first and every MCP server is explicitly disabled alongside built-in and extension tools.
pub fn start_temporary_thread(request_handle &codex_app_server_client.AppServerRequestHandle, options TemporaryStructuredThreadOptions) !codex_app_server_protocol.ThreadStartResponse {
	custom_permission_profile := if profile := options.active_permission_profile {
		if !profile.starts_with(':') { ?string(profile) } else { ?string(none) }
	} else {
		?string(none)
	}
	config := {
		'features.apps':                                 serde_json.Value.boolean(false)
		'features.code_mode':                            serde_json.Value.boolean(false)
		'features.code_mode_only':                       serde_json.Value.boolean(false)
		'features.context_management':                   serde_json.Value.boolean(false)
		'features.current_time_reminder':                serde_json.Value.boolean(false)
		'features.deferred_executor':                    serde_json.Value.boolean(false)
		'features.enable_fanout':                        serde_json.Value.boolean(false)
		'features.goals':                                serde_json.Value.boolean(false)
		'features.hooks':                                serde_json.Value.boolean(false)
		'features.image_generation':                     serde_json.Value.boolean(false)
		'features.memories':                             serde_json.Value.boolean(false)
		'features.multi_agent':                          serde_json.Value.boolean(false)
		'features.multi_agent_v2':                       serde_json.Value.boolean(false)
		'features.plugins':                              serde_json.Value.boolean(false)
		'features.request_permissions_tool':             serde_json.Value.boolean(false)
		'features.shell_snapshot':                       serde_json.Value.boolean(false)
		'features.shell_tool':                           serde_json.Value.boolean(false)
		'features.standalone_web_search':                serde_json.Value.boolean(false)
		'features.token_budget':                         serde_json.Value.boolean(false)
		'features.tool_suggest':                         serde_json.Value.boolean(false)
		'features.unified_exec':                         serde_json.Value.boolean(false)
		'features.view_image':                           serde_json.Value.boolean(false)
		'orchestrator.skills.enabled':                   serde_json.Value.boolean(false)
		'skills.include_instructions':                   serde_json.Value.boolean(false)
		'token_budget.use_history_notes_extension':      serde_json.Value.boolean(false)
		'tools.experimental_request_user_input.enabled': serde_json.Value.boolean(false)
		'tools.update_plan.enabled':                     serde_json.Value.boolean(false)
		'web_search':                                    serde_json.Value.string('disabled')
	}
	response := tokio_time.timeout_owned[codex_app_server_protocol.ThreadStartResponse, StartOperation](i64(structured_turn_timeout.as_nanos().lo), StartOperation{
		request_handle:            request_handle.clone()
		model:                     options.model
		model_provider:            options.model_provider
		cwd:                       options.cwd
		custom_permission_profile: if profile := custom_permission_profile {
			profile.clone()
		} else {
			none
		}
		mcp_server_names:          options.mcp_server_names
		config:                    config
		deadline:                  std_time.Instant.now().add(structured_turn_timeout)
	}, start_operation) or {
		if err is tokio_time.Elapsed {
			return error('temporary structured thread start timed out')
		}
		return err
	}
	if expected_profile := custom_permission_profile {
		if profile := response.active_permission_profile {
			if profile.id != expected_profile {
				return error('temporary structured thread did not preserve permission profile ${expected_profile}')
			}
		} else {
			return error('temporary structured thread did not preserve permission profile ${expected_profile}')
		}
	} else if response.sandbox.policy_kind != .read_only {
		return error('temporary structured thread did not start with read-only permissions')
	}
	return response
}

// The original timeout's asynchronous block, moved into a worker entry so V
// transfers owned captures without the additional clones required by closures.
fn start_operation(operation StartOperation) !codex_app_server_protocol.ThreadStartResponse {
	// Fail closed if the remote-effective MCP configuration cannot be read.
	effective_config := operation.request_handle.request_typed[codex_app_server_protocol.ConfigReadResponse](codex_app_server_protocol.ClientRequestConfigRead{
		request_id: codex_app_server_protocol.RequestId.string('temporary-config-${uuid.Uuid.new_v4()}')
		params:     codex_app_server_protocol.ConfigReadParams{ include_layers: false, cwd: operation.cwd.clone() }
	})!
	// A native RPC worker cannot be forcibly cancelled. Recheck the original
	// deadline at its await boundary so a late ConfigRead cannot issue ThreadStart
	// after Tokio would have dropped the timed future.
	if std_time.Instant.now() >= operation.deadline {
		return tokio_time.Elapsed{}
	}
	mut mcp_server_names := map[string]bool{}
	for name in operation.mcp_server_names {
		mcp_server_names[name] = true
	}
	if 'mcp_servers' in effective_config.config.additional {
		// The key is present and this immutable map cannot reallocate during the borrow.
		server_config := unsafe { &effective_config.config.additional['mcp_servers'] }
		if names := server_config.object_keys() {
			for name in names {
				mcp_server_names[name] = true
			}
		}
	}
	// BTreeSet's union is sorted before constructing the JSON object.
	mut names := mcp_server_names.keys()
	names.sort()
	mut disabled_servers := map[string]serde_json.Value{}
	for name in names {
		disabled_servers[name] = serde_json.Value.object({
			'enabled': serde_json.Value.boolean(false)
		})
	}
	mut config := operation.config
	config['mcp_servers'] = serde_json.Value.object(disabled_servers)
	// Materialize the owned request before invoking the generic method: V's C
	// evaluation-order lowering otherwise treats a generic receiver method as an
	// unknown function pointer when a payload contains an if-expression.
	request := codex_app_server_protocol.ClientRequestThreadStart{
		request_id: codex_app_server_protocol.RequestId.string('temporary-structured-${uuid.Uuid.new_v4()}')
		params:     codex_app_server_protocol.ThreadStartParams{
			model:                     operation.model
			model_provider:            operation.model_provider
			cwd:                       operation.cwd
			approval_policy:           codex_app_server_protocol.AskForApproval{ kind: .never }
			sandbox:                   if operation.custom_permission_profile == none {
				?codex_app_server_protocol.SandboxMode(.read_only)
			} else {
				?codex_app_server_protocol.SandboxMode(none)
			}
			permissions:               operation.custom_permission_profile
			runtime_workspace_roots:   []string{}
			ephemeral:                 true
			thread_source:             codex_protocol.ThreadSource{ source_kind: .feature, feature: 'system' }
			environments:              []codex_app_server_protocol.TurnEnvironmentParams{}
			dynamic_tools:             []codex_app_server_protocol.DynamicToolSpec{}
			selected_capability_roots: []codex_app_server_protocol.SelectedCapabilityRoot{}
			config:                    config
		}
	}
	return operation.request_handle.request_typed[codex_app_server_protocol.ThreadStartResponse](request)
}

// Submit a structured turn using the temporary thread's existing settings.
pub fn start_structured_turn(request_handle &codex_app_server_client.AppServerRequestHandle, thread_id string, prompt string, output_schema serde_json.Value, effort ?openai_models.ReasoningEffort) !codex_app_server_protocol.TurnStartResponse {
	return request_handle.request_typed[codex_app_server_protocol.TurnStartResponse](codex_app_server_protocol.ClientRequestTurnStart{
		request_id: codex_app_server_protocol.RequestId.string('temporary-structured-turn-${uuid.Uuid.new_v4()}')
		params:     codex_app_server_protocol.TurnStartParams{
			thread_id:     thread_id
			input:         [codex_app_server_protocol.UserInput(codex_app_server_protocol.UserInputText{ text: prompt, text_elements: []codex_app_server_protocol.TextElement{} })]
			output_schema: output_schema
			effort:        effort
		}
	})
}

// Return the latest assistant message when the requested turn completes.
pub fn collect_structured_response(notifications mpsc.NotificationReceiver, turn_id &string) !string {
	mut receiver := notifications
	defer { receiver.close() }
	mut response := ?string(none)
	for {
		notification := receiver.recv() or { break }
		match notification {
			codex_app_server_protocol.ItemCompletedNotification {
				if notification.turn_id == *turn_id && notification.item.kind == .agent_message {
					if usize(notification.item.text.len) > structured_response_max_bytes {
						return error('temporary structured response exceeds ${structured_response_max_bytes} bytes')
					}
					response = notification.item.text
				}
			}
			codex_app_server_protocol.TurnCompletedNotification {
				if notification.turn.id == *turn_id {
					if notification.turn.status != .completed {
						status := match notification.turn.status {
							.completed { 'Completed' }
							.interrupted { 'Interrupted' }
							.failed { 'Failed' }
							.in_progress { 'InProgress' }
						}
						return error('temporary structured turn ended with status ${status}')
					}
					return response or { return error('temporary structured turn completed without a response') }
				}
			}
			else {}
		}
	}
	return error('temporary structured turn notification channel closed')
}

// The unsubscribe future owns its thread id and a shared transport lease.
struct UnsubscribeOperation {
	request_handle codex_app_server_client.AppServerRequestHandle
	thread_id      string
}

fn unsubscribe_operation(operation UnsubscribeOperation) !codex_app_server_protocol.ThreadUnsubscribeResponse {
	return operation.request_handle.request_typed[codex_app_server_protocol.ThreadUnsubscribeResponse](codex_app_server_protocol.ClientRequestThreadUnsubscribe{
		request_id: codex_app_server_protocol.RequestId.string('temporary-structured-unsubscribe-${uuid.Uuid.new_v4()}')
		params:     codex_app_server_protocol.ThreadUnsubscribeParams{ thread_id: operation.thread_id }
	})
}

// Make a bounded best-effort attempt to detach an ephemeral thread.
pub fn unsubscribe_temporary_thread(request_handle &codex_app_server_client.AppServerRequestHandle, thread_id string) {
	tokio_time.timeout_owned[codex_app_server_protocol.ThreadUnsubscribeResponse, UnsubscribeOperation](i64(structured_turn_timeout.as_nanos().lo), UnsubscribeOperation{
		request_handle: request_handle.clone()
		thread_id:      thread_id
	}, unsubscribe_operation) or {
		if err is tokio_time.Elapsed {
			message := 'temporary structured thread unsubscribe timed out'
			tracing.debug(&message)
		} else {
			message := 'failed to unsubscribe from temporary structured thread'
			tracing.debug_temporary_structured_unsubscribe_failure(&err, &message)
		}
	}
}

// V's owned future payload for the source's whole start-and-collect timeout.
struct TurnOperation {
	request_handle codex_app_server_client.AppServerRequestHandle
	thread_id      string
	prompt         string
	output_schema  serde_json.Value
	effort         ?openai_models.ReasoningEffort
	notifications  mpsc.NotificationReceiver
}

fn turn_operation(operation TurnOperation) !string {
	defer { operation.notifications.close() }
	turn := start_structured_turn(&operation.request_handle, operation.thread_id, operation.prompt, operation.output_schema, operation.effort)!
	return collect_structured_response(operation.notifications, &turn.turn.id)
}

// Run a bounded structured turn and make a bounded temporary-thread cleanup attempt.
pub fn run_temporary_structured_turn(request_handle codex_app_server_client.AppServerRequestHandle, thread_id string, prompt string, output_schema serde_json.Value, effort ?openai_models.ReasoningEffort, notifications mpsc.NotificationReceiver) !string {
	defer { unsubscribe_temporary_thread(&request_handle, thread_id) }
	// Dropping Tokio's timed future closes its receiver before cleanup. Wake the
	// V receive worker on every result, including a deadline or TurnStart failure.
	cancellation := notifications.cancellation_handle()
	defer { cancellation.cancel() }
	return tokio_time.timeout_owned[string, TurnOperation](i64(structured_turn_timeout.as_nanos().lo), TurnOperation{
		request_handle: request_handle.clone()
		thread_id:      thread_id.clone()
		prompt:         prompt
		output_schema:  output_schema
		effort:         effort
		notifications:  notifications
	}, turn_operation) or {
		if err is tokio_time.Elapsed {
			return error('temporary structured turn timed out')
		}
		return err
	}
}
