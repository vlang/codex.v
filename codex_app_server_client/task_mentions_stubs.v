module codex_app_server_client

import codex_app_server_protocol as api
import serde_json

// STUB: codex_app_server_client::AppServerRequestHandle. The in-process and remote app-server
// clients are not ported.
pub struct AppServerRequestHandle {
	collaboration_fixture     &CollaborationModeFixture   = unsafe { nil }
	structured_fixture        &TemporaryStructuredFixture = unsafe { nil }
	permission_fixture        &PermissionDiscoveryFixture = unsafe { nil }
	named_session_fixture     &NamedSessionFixture        = unsafe { nil }
	daybreak_fixture          &DaybreakAuthStatusFixture  = unsafe { nil }
	session_queue_fixture     &SessionQueueFixture        = unsafe { nil }
	workspace_command_fixture &WorkspaceCommandFixture    = unsafe { nil }
	config_update_fixture     &ConfigUpdateFixture        = unsafe { nil }
}

// STUB: codex_app_server_client::AppServerRequestHandle::request_typed. Rust awaits the typed
// JSON-RPC response. The source-shaped collaboration fixture is an in-memory boundary;
// without one, unported in-process/remote transports fail with a transport error.
pub fn (handle &AppServerRequestHandle) request_typed[T](request api.ClientRequest) !T {
	$if T is api.ConfigWriteResponse {
		if request is api.ClientRequestConfigBatchWrite {
			return handle.request_config_batch_write(request)
		}
	}
	$if T is api.EnvironmentInfoResponse {
		if request is api.ClientRequestEnvironmentInfo {
			return handle.request_environment_info(request)
		}
	}
	$if T is api.SkillsConfigWriteResponse {
		if request is api.ClientRequestSkillsConfigWrite {
			return handle.request_skills_config_write(request)
		}
	}
	$if T is serde_json.Value {
		if request is api.ClientRequestConfigRead {
			return handle.config_update_request_config_read_json(request)
		}
	}
	$if T is api.CommandExecResponse {
		if request is api.ClientRequestOneOffCommandExec {
			return handle.request_one_off_command_exec(request)
		}
	}
	$if T is api.ThreadQueueAddResponse {
		if request is api.ClientRequestThreadQueueAdd {
			return handle.request_thread_queue_add(request)
		}
	}
	$if T is api.GetAuthStatusResponse {
		if request is api.ClientRequestGetAuthStatus {
			return handle.request_get_auth_status(request)
		}
	}
	$if T is api.ThreadListResponse {
		if request is api.ClientRequestThreadList {
			return handle.request_named_thread_list(request)
		}
	}
	$if T is api.ThreadReadResponse {
		if request is api.ClientRequestThreadRead {
			return handle.request_named_thread_read(request)
		}
	}
	$if T is api.CollaborationModeListResponse {
		if request is api.ClientRequestCollaborationModeList {
			return handle.request_collaboration_mode_list(request)
		}
	}
	$if T is api.ConfigReadResponse {
		if request is api.ClientRequestConfigRead {
			if handle.config_update_fixture != unsafe { nil } {
				return handle.config_update_request_config_read(request)
			}
			return handle.request_config_read(request)
		}
	}
	$if T is api.ConfigRequirementsReadResponse {
		if request is api.ClientRequestConfigRequirementsRead {
			return handle.request_config_requirements_read(request)
		}
	}
	$if T is api.PermissionProfileListResponse {
		if request is api.ClientRequestPermissionProfileList {
			return handle.request_permission_profile_list(request)
		}
	}
	$if T is api.ThreadStartResponse {
		if request is api.ClientRequestThreadStart {
			if handle.config_update_fixture != unsafe { nil } {
				return handle.config_update_request_thread_start(request)
			}
			return handle.request_thread_start(request)
		}
	}
	$if T is api.TurnStartResponse {
		if request is api.ClientRequestTurnStart {
			return handle.request_turn_start(request)
		}
	}
	$if T is api.ThreadUnsubscribeResponse {
		if request is api.ClientRequestThreadUnsubscribe {
			return handle.request_thread_unsubscribe(request)
		}
	}
	return error('app-server client is not available')
}
