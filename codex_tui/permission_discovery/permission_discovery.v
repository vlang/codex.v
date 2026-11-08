// Bounded discovery for permission pickers; fixed request IDs bound abandoned RPCs.
// This never applies a profile; the app chooses local or server-owned selection.
module permission_discovery

import codex_app_server_client
import codex_app_server_protocol as api
import codex_config
import codex_core
import codex_tui
import codex_tui.app_event
import codex_tui.app_event_sender
import codex_tui.permission_discovery.types
import std_path
import time
import tokio.time as tokio_time
import uuid

// Reexport source-owned data/methods from the independent types module; this
// avoids a V import cycle through AppEvent without erasing the typed result.
pub type PermissionDiscovery = types.PermissionDiscovery

// The source async future owns only these captures, keeping its caller's config
// and session reusable. The deadline covers every page and config/requirements RPC.
struct DiscoveryOperation {
	handle                codex_app_server_client.AppServerRequestHandle
	mode                  codex_tui.ThreadParamsMode
	cwd                   ?string
	local_discovery       ?types.PermissionDiscovery
	active_custom_profile bool
mut:
	deadline_nanos i64
}

pub fn fetch(app_server &codex_tui.AppServerSession, request_id uuid.Uuid, config &codex_core.Config, thread_cwd codex_tui.BorrowedPermissionPath, tx app_event_sender.AppEventSender) {
	handle := app_server.request_handle()
	mode := app_server.thread_params_mode()
	mut cwd := ?string(none)
	if path := thread_cwd.path {
		cwd = path.to_string_lossy()
	} else if mode == .embedded {
		path := std_path.Path.new(&config.cwd)
		cwd = path.to_string_lossy()
	} else if path := app_server.remote_cwd_override().path {
		cwd = path.to_string_lossy()
	}
	// The daemon's catalog cannot see permission definitions from this invocation.
	mut use_local := false
	if !app_server.uses_embedded_app_server() && mode == .embedded {
		// Typed layer companion adapts the existing legacy []string stack stub;
		// the source-shaped enabled-layer iterator still governs this decision.
		for layer in config.permission_config_layer_stack.layers_low_to_high() {
			if layer.name == codex_config.ConfigLayerSource.session_flags && 'permissions' in layer.config {
				use_local = true
				break
			}
		}
	}
	local_discovery := if use_local {
		?types.PermissionDiscovery(types.PermissionDiscovery.local(config))
	} else {
		?types.PermissionDiscovery(none)
	}
	active_custom_profile := if profile := config.permissions.active_permission_profile() {
		!profile.id.starts_with(':')
	} else {
		false
	}
	operation := DiscoveryOperation{ handle: handle, mode: mode, cwd: cwd, local_discovery: local_discovery, active_custom_profile: active_custom_profile }
	spawn dispatch_discovery(operation, request_id, tx)
}

fn dispatch_discovery(payload DiscoveryOperation, request_id uuid.Uuid, tx app_event_sender.AppEventSender) {
	mut operation := payload
	operation.deadline_nanos = time.sys_mono_now() + i64(10 * time.second)
	discovery := tokio_time.timeout_owned[types.PermissionDiscovery, DiscoveryOperation](10 * time.second, operation, run_discovery) or {
		message := if err is tokio_time.Elapsed {
			'Permission discovery timed out. Try /permissions again.'
		} else {
			err.msg()
		}
		tx.send(app_event.permission_profiles_loaded(request_id, types.PermissionDiscoveryResult{ is_error: true, error_value: message }))
		return
	}
	tx.send(app_event.permission_profiles_loaded(request_id, types.PermissionDiscoveryResult{ value: discovery }))
}

fn run_discovery(operation DiscoveryOperation) !types.PermissionDiscovery {
	if discovery := operation.local_discovery {
		return discovery
	}
	if operation.mode == .remote && !operation.active_custom_profile {
		request := api.ClientRequestConfigRead{
			request_id: api.RequestId.string('tui-permission-config')
			params:     api.ConfigReadParams{
				include_layers: false
				cwd:            if cwd := operation.cwd {
					cwd.clone()
				} else {
					none
				}
			}
		}
		config := operation.handle.request_typed[api.ConfigReadResponse](request) or { return permission_rpc_error(err) }
		// A native RPC worker cannot be forcibly cancelled like Tokio's future.
		// Recheck the original deadline before issuing any subsequent RPC.
		if time.sys_mono_now() > operation.deadline_nanos {
			return tokio_time.Elapsed{}
		}
		mut explicit := false
		if 'default_permissions' in config.config.additional {
			value := unsafe { &config.config.additional['default_permissions'] }
			explicit = value.is_string()
		}
		if !explicit {
			return types.PermissionDiscovery{ profiles: [], requirements: none, explicit_profile_mode: false }
		}
	}
	request := api.ClientRequestConfigRequirementsRead{ request_id: api.RequestId.string('tui-permission-requirements'), params: none }
	requirements := operation.handle.request_typed[api.ConfigRequirementsReadResponse](request) or { return permission_rpc_error(err) }
	if time.sys_mono_now() > operation.deadline_nanos {
		return tokio_time.Elapsed{}
	}
	mut profiles := []api.PermissionProfileSummary{}
	mut cursor := PaginationCursor{}
	mut cursors := map[string]bool{}
	for _ in 0 .. 10 {
		request_cursor := cursor_into_optional(cursor)
		page_request := api.ClientRequestPermissionProfileList{
			request_id: api.RequestId.string('tui-permission-profiles')
			params:     api.PermissionProfileListParams{
				cursor: request_cursor
				limit:  u32(100)
				cwd:    if cwd := operation.cwd {
					cwd.clone()
				} else {
					none
				}
			}
		}
		response := operation.handle.request_typed[api.PermissionProfileListResponse](page_request) or { return permission_rpc_error(err) }
		if time.sys_mono_now() > operation.deadline_nanos {
			return tokio_time.Elapsed{}
		}
		if response.data.len > 100 {
			break
		}
		profiles << response.data
		cursor = cursor_from_optional(response.next_cursor)
		if cursor.has_value {
			if cursor.value in cursors {
				break
			}
			cursors[cursor.value.clone()] = true
		} else {
			if !profiles_have_unique_ids(&profiles) {
				return error('The server returned duplicate permission profiles.')
			}
			return types.PermissionDiscovery{ profiles: profiles, requirements: requirements.requirements, explicit_profile_mode: true }
		}
	}
	return error('Permission discovery exceeded its pagination limit. Try /permissions again.')
}

// Rust inspects cursor.as_ref() before moving the same cursor into the next
// request. An owned optional binding consumes strings in V, so keep the tag and
// stable owned string separate; a shared field borrow never drains the cursor.
struct PaginationCursor {
	has_value bool
	value     string
}

fn cursor_from_optional(value ?string) PaginationCursor {
	if cursor := value {
		return PaginationCursor{ has_value: true, value: cursor }
	}
	return PaginationCursor{}
}

fn cursor_into_optional(cursor PaginationCursor) ?string {
	if cursor.has_value {
		return cursor.value
	}
	return none
}

// Rust's HashSet<&String> borrows the existing identifiers. V maps own keys;
// bounded pairwise comparisons retain those borrows without allocating copies.
// The helper ends their lifetime before the successful result moves profiles.
fn profiles_have_unique_ids(profiles &[]api.PermissionProfileSummary) bool {
	for index in 0 .. profiles.len {
		for previous in 0 .. index {
			if profiles[index].id == profiles[previous].id {
				return false
			}
		}
	}
	return true
}

// V's IError transport preserves TypedRequestError's owned payload at the
// source map_err boundary; an unexpected untyped failure keeps its message.
fn permission_rpc_error(failure IError) IError {
	if failure is codex_app_server_client.TypedRequestError {
		return error(discovery_error(failure))
	}
	return error('Failed to load permissions: ${failure.msg()}')
}

fn discovery_error(failure codex_app_server_client.TypedRequestError) string {
	if failure.kind == .server && (failure.server_source.code == -32601 || (failure.server_source.code == -32600 && (failure.server_source.message.contains('permissionProfile/list') || failure.server_source.message.contains('configRequirements/read') || failure.server_source.message.contains('config/read')))) {
		return 'This server does not support permission discovery. Upgrade the Codex server to use this menu.'
	}
	return 'Failed to load permissions: ${failure.msg()}'
}
