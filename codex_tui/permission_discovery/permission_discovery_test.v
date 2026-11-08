module permission_discovery

import codex_app_server_client
import codex_app_server_protocol as api
import codex_config
import codex_core
import codex_protocol
import codex_tui
import codex_tui.app_event
import codex_tui.app_event_sender
import codex_tui.permission_discovery.types
import os
import serde_json
import std_path
import time
import toml
import uuid

fn receive_discovery(events chan app_event.AppEvent) types.PermissionDiscoveryResult {
	select {
		event := <-events {
			assert event.kind == .permission_profiles_loaded
			return event.permission_profiles.result
		}
		30 * time.second {
			panic('expected discovery result')
		}
	}
	panic('expected discovery result')
}

fn test_discovery_preserves_config_scope_and_bounds_server_requests() {
	home := os.join_path(os.temp_dir(), 'codex-permission-discovery-${uuid.Uuid.new_v4()}')
	os.mkdir(home) or { panic(err) }
	// V's garbage collector does not run Rust TempDir::drop; clean up explicitly.
	defer { os.rmdir_all(home) or {} }
	for case in ['local', 'session-only', 'remote', 'remote-default', 'thread', 'legacy', 'empty',
		'unsupported', 'config-error', 'cycle', 'limit', 'timeout'] {
		mode := if case in ['local', 'session-only', 'timeout'] {
			codex_tui.ThreadParamsMode.embedded
		} else {
			codex_tui.ThreadParamsMode.remote
		}
		mut overrides := []codex_core.PermissionCliOverride{}
		if case == 'session-only' {
			overrides << codex_core.PermissionCliOverride{ key: 'permissions.session-only.extends', value: toml.Any(':workspace') }
			overrides << codex_core.PermissionCliOverride{ key: 'default_permissions', value: toml.Any('session-only') }
		}
		initial_builder := codex_core.ConfigBuilder.default()
		home_builder := initial_builder.codex_home(home.clone())
		configured_builder := home_builder.cli_overrides(overrides)
		config := configured_builder.build() or { panic(err) }
		thread_path_string := '/thread'
		thread_cwd := codex_tui.BorrowedPermissionPath{
			path: if case == 'thread' {
				?std_path.Path(std_path.Path.new(&thread_path_string))
			} else {
				?std_path.Path(none)
			}
		}
		remote_cwd := if case != 'remote-default' { ?string('/server') } else { ?string(none) }
		cwd := if case == 'thread' {
			?string('/thread')
		} else if mode == .embedded {
			?string(config.cwd.clone())
		} else {
			if remote := remote_cwd { ?string(remote.clone()) } else { ?string(none) }
		}
		data := [api.PermissionProfileSummary{ id: ':workspace', allowed: true },
			api.PermissionProfileSummary{ id: 'remote-profile', description: 'Server description', allowed: true }]
		requirements := api.ConfigRequirements{
			allowed_permission_profiles: {
				'remote-profile': true
			}
		}
		mut replies := []codex_app_server_client.PermissionDiscoveryReply{}
		if mode == .remote {
			replies << api.ConfigReadResponse{
				config: api.Config{
					additional: {
						'default_permissions': if case != 'legacy' {
							serde_json.Value.string(':workspace')
						} else {
							serde_json.Value{}
						}
					}
				}
			}
		}
		replies << api.ConfigRequirementsReadResponse{ requirements: requirements.clone() }
		match case {
			'empty' { replies << api.PermissionProfileListResponse{ data: [], next_cursor: none } }
			'unsupported' {
				replies << api.JSONRPCErrorError{ code: -32601, message: 'Unknown method' }
			}
			'config-error' {
				replies << api.JSONRPCErrorError{ code: -32603, message: 'Invalid project config' }
			}
			'cycle' {
				for _ in 0 .. 2 {
					replies << api.PermissionProfileListResponse{ data: [], next_cursor: 'repeat' }
				}
			}
			'limit' {
				for i in 0 .. 10 {
					replies << api.PermissionProfileListResponse{ data: [], next_cursor: i.str() }
				}
			}
			else {
				replies << api.PermissionProfileListResponse{ data: [(&data[0]).clone()], next_cursor: 'second' }
				replies << api.PermissionProfileListResponse{ data: [(&data[1]).clone()], next_cursor: none }
			}
		}
		if case == 'timeout' {
			replies = [codex_app_server_client.PermissionDiscoveryReply(codex_app_server_client.PermissionNoReply{})]
		}
		// The untranslated WebSocket runtime is the smallest typed transport stub
		// boundary. The actual discovery requests, ordering, params and responses
		// are retained; no source assertion is replaced with a name-based smoke test.
		handle := codex_app_server_client.AppServerRequestHandle.permission_discovery_fixture(replies)
		session := codex_tui.AppServerSession.new(handle, mode).with_remote_cwd_override(if remote := remote_cwd {
			remote.clone()
		} else {
			none
		})
		observer := session.request_handle()
		events := chan app_event.AppEvent{cap: 1}
		// Keep real time for the socket handshake. The transport boundary has no
		// handshake, and V's native timeout cannot pause Tokio's virtual clock;
		// this case therefore exercises the real ten-second source deadline.
		for attempt in 0 .. if case == 'timeout' { 4 } else { 1 } {
			fetch(&session, uuid.Uuid.new_v4(), &config, thread_cwd, app_event_sender.AppEventSender.new(events))
			result := receive_discovery(events)
			expected_error := match case {
				'unsupported' { ?string('Upgrade') }
				'config-error' { ?string('Invalid project config') }
				'cycle', 'limit' { ?string('pagination limit') }
				'timeout' { ?string(if attempt == 0 { 'timed out' } else { 'duplicate' }) }
				else { ?string(none) }
			}
			if expected := expected_error {
				assert result.is_error
				assert result.error_value.contains(expected)
				continue
			}
			assert !result.is_error, '${case}: ${result.error_value}'
			discovery := &result.value
			assert discovery.explicit_profile_mode == (case != 'legacy')
			if case == 'session-only' {
				mut found := false
				for index in 0 .. discovery.profiles.len {
					profile := &discovery.profiles[index]
					if profile.id == 'session-only' && profile.allowed {
						found = true
					}
				}
				assert found
			} else if case in ['empty', 'legacy'] {
				assert discovery.profiles.len == 0
			} else {
				assert discovery.profiles == data
				assert discovery.requirements == ?api.ConfigRequirements(requirements.clone())
			}
		}
		session.shutdown() or { panic(err) }
		requests := observer.permission_fixture_requests()
		match case {
			'session-only' {
				assert requests.len == 0
			}
			'timeout', 'legacy' {
				assert requests.len == 1
			}
			'local', 'remote', 'remote-default', 'thread' {
				mut pages := []api.PermissionProfileListParams{}
				for index in 0 .. requests.len {
					request := &requests[index]
					if request is api.ClientRequestPermissionProfileList {
						pages << api.PermissionProfileListParams{
							cursor: if value := request.params.cursor {
								value.clone()
							} else {
								none
							}
							cwd:    if value := request.params.cwd { value.clone() } else { none }
							limit:  request.params.limit
						}
					}
				}
				expected_pages := [
					api.PermissionProfileListParams{
						cwd:    if cwd_value := cwd {
							cwd_value.clone()
						} else {
							none
						}
						limit:  u32(100)
						cursor: none
					},
					api.PermissionProfileListParams{
						cwd:    if cwd_value := cwd {
							cwd_value.clone()
						} else {
							none
						}
						limit:  u32(100)
						cursor: 'second'
					},
				]
				if pages != expected_pages {
					panic('${case}: actual=${pages} expected=${expected_pages}')
				}
				assert pages == expected_pages
				if mode == .remote {
					first := &requests[0]
					assert first is api.ClientRequestConfigRead
					if first is api.ClientRequestConfigRead {
						assert first.params.cwd == cwd
					}
				}
			}
			else {}
		}
	}
}

fn owned_permission_text(text &string) string {
	$if ownership ? {
		return text.to_owned()
	}
	return text.clone()
}

fn test_local_profiles_and_disabled_reasons_borrow_owners_repeatedly() {
	id_text := 'custom-profile'
	description_text := 'A locally configured profile'
	config := codex_core.Config{ custom_permission_profiles: [codex_core.PermissionProfileCatalogEntry{ id: owned_permission_text(&id_text), description: owned_permission_text(&description_text), allowed: false }] }
	first := PermissionDiscovery.local(&config)
	second := types.PermissionDiscovery.local(&config)
	assert first.profiles == second.profiles
	assert first.profiles.len == 4
	assert first.profiles[3].id == id_text
	assert first.profiles[3].description == ?string(description_text.clone())
	assert !first.profiles[3].allowed
	assert first.explicit_profile_mode
	assert first.requirements == none
	owner := owned_permission_text(&id_text)
	for _ in 0 .. 2 {
		assert first.disabled_reason(&owner, none, none) == ?string('Disabled by requirements.')
	}
	assert owner == id_text
	assert config.custom_permission_profiles[0].id == id_text
	assert config.custom_permission_profiles[0].description == ?string(description_text.clone())
	missing := 'missing'
	assert first.disabled_reason(&missing, none, none) == ?string('Not available on this server.')
}

fn test_requirements_apply_id_approval_and_reviewer_restrictions_independently() {
	identifier := 'allowed'
	owner := owned_permission_text(&identifier)
	discovery := types.PermissionDiscovery{
		profiles:              [
			api.PermissionProfileSummary{ id: owner.clone(), allowed: true },
			api.PermissionProfileSummary{ id: 'absent-id', allowed: true },
			api.PermissionProfileSummary{ id: 'false-id', allowed: true },
		]
		requirements:          api.ConfigRequirements{
			allowed_permission_profiles: {
				owner.clone(): true
				'false-id':    false
			}
			allowed_approval_policies:   [api.AskForApproval{ kind: .on_request }]
			allowed_approvals_reviewers: [api.ApprovalsReviewer.user]
		}
		explicit_profile_mode: true
	}
	for _ in 0 .. 2 {
		assert discovery.disabled_reason(&owner, api.AskForApproval{ kind: .on_request }, .user) == none
		assert discovery.disabled_reason(&owner, none, none) == none
		assert discovery.disabled_reason(&owner, api.AskForApproval{ kind: .never }, .user) == ?string('Disabled by requirements.')
		assert discovery.disabled_reason(&owner, api.AskForApproval{ kind: .on_request }, .guardian_subagent) == ?string('Disabled by requirements.')
	}
	absent := 'absent-id'
	false_id := 'false-id'
	assert discovery.disabled_reason(&absent, none, none) == ?string('Disabled by requirements.')
	assert discovery.disabled_reason(&false_id, none, none) == ?string('Disabled by requirements.')
	assert owner == identifier
	assert discovery.profiles[0].id == identifier
	assert requirements_remain_intact(&discovery, &owner)
	assert discovery.disabled_reason(&owner, api.AskForApproval{ kind: .on_request }, .user) == none
}

fn test_discovery_error_classifies_supported_method_errors_precisely() {
	for method in ['permissionProfile/list', 'configRequirements/read', 'config/read'] {
		text := 'Invalid request to ${method}'
		result := discovery_error(codex_app_server_client.TypedRequestError{ kind: .server, method: method, server_source: api.JSONRPCErrorError{ code: -32600, message: text } })
		assert result.contains('Upgrade the Codex server')
	}
	result := discovery_error(codex_app_server_client.TypedRequestError{ kind: .server, method: 'config/read', server_source: api.JSONRPCErrorError{ code: -32600, message: 'Unrelated invalid request' } })
	assert result.starts_with('Failed to load permissions: ')
	assert result.contains('Unrelated invalid request')
	assert discovery_error(codex_app_server_client.TypedRequestError{ kind: .server, server_source: api.JSONRPCErrorError{ code: -32601, message: 'Unknown method' } }).contains('Upgrade')
	assert discovery_error(codex_app_server_client.TypedRequestError{ kind: .deserialize, method: 'config/read', deserialize_source: error('invalid JSON') }).contains('invalid JSON')
}

fn run_fixture_case(config &codex_core.Config, mode codex_tui.ThreadParamsMode, replies []codex_app_server_client.PermissionDiscoveryReply) (types.PermissionDiscoveryResult, []api.ClientRequest) {
	handle := codex_app_server_client.AppServerRequestHandle.permission_discovery_fixture(replies)
	session := codex_tui.AppServerSession.new(handle, mode)
	observer := session.request_handle()
	events := chan app_event.AppEvent{cap: 1}
	fetch(&session, uuid.Uuid.new_v4(), config, codex_tui.BorrowedPermissionPath{}, app_event_sender.AppEventSender.new(events))
	result := receive_discovery(events)
	session.shutdown() or { panic(err) }
	return result, observer.permission_fixture_requests()
}

fn test_duplicate_profile_ids_and_oversized_pages_are_rejected() {
	config := codex_core.Config{ cwd: '/workspace' }
	duplicate_replies := [
		codex_app_server_client.PermissionDiscoveryReply(api.ConfigRequirementsReadResponse{}),
		codex_app_server_client.PermissionDiscoveryReply(api.PermissionProfileListResponse{ data: [api.PermissionProfileSummary{ id: 'same', allowed: true }], next_cursor: 'next' }),
		codex_app_server_client.PermissionDiscoveryReply(api.PermissionProfileListResponse{ data: [api.PermissionProfileSummary{ id: 'same', allowed: true }] }),
	]
	duplicate, duplicate_requests := run_fixture_case(&config, .embedded, duplicate_replies)
	assert duplicate.is_error
	assert duplicate.error_value == 'The server returned duplicate permission profiles.'
	assert duplicate_requests.len == 3
	mut profiles := []api.PermissionProfileSummary{}
	for i in 0 .. 101 {
		profiles << api.PermissionProfileSummary{ id: i.str(), allowed: true }
	}
	oversized, oversized_requests := run_fixture_case(&config, .embedded, [
		codex_app_server_client.PermissionDiscoveryReply(api.ConfigRequirementsReadResponse{}),
		codex_app_server_client.PermissionDiscoveryReply(api.PermissionProfileListResponse{ data: profiles }),
	])
	assert oversized.is_error
	assert oversized.error_value.contains('pagination limit')
	assert oversized_requests.len == 2
}

fn test_active_custom_profile_skips_legacy_config_probe() {
	text := 'custom'
	config := codex_core.Config{ cwd: '/workspace', permissions: codex_core.ConfigPermissions{ active_profile: codex_protocol.ActivePermissionProfile{ id: owned_permission_text(&text) } } }
	for _ in 0 .. 2 {
		result, requests := run_fixture_case(&config, .remote, [
			codex_app_server_client.PermissionDiscoveryReply(api.ConfigRequirementsReadResponse{}),
			codex_app_server_client.PermissionDiscoveryReply(api.PermissionProfileListResponse{}),
		])
		assert !result.is_error
		assert result.value.explicit_profile_mode
		assert requests.len == 2
		assert requests[0] is api.ClientRequestConfigRequirementsRead
	}
	profile := config.permissions.active_permission_profile() or { panic('missing active profile') }
	assert profile.id == text
}

fn test_local_session_layers_ignore_disabled_and_non_session_layers() {
	for source in [codex_config.ConfigLayerSource.project,
		codex_config.ConfigLayerSource.session_flags] {
		config := codex_core.Config{
			cwd:                           '/workspace'
			permission_config_layer_stack: codex_config.ConfigLayerStack{
				layers: [codex_config.ConfigLayerEntry{
					name:            source
					config:          {
						'permissions': toml.Any(map[string]toml.Any{})
					}
					disabled_reason: if source == .session_flags {
						?string('disabled')
					} else {
						?string(none)
					}
				}]
			}
		}
		result, requests := run_fixture_case(&config, .embedded, [
			codex_app_server_client.PermissionDiscoveryReply(api.ConfigRequirementsReadResponse{}),
			codex_app_server_client.PermissionDiscoveryReply(api.PermissionProfileListResponse{}),
		])
		assert !result.is_error
		assert requests.len == 2
	}
}

fn requirements_remain_intact(discovery &types.PermissionDiscovery, id &string) bool {
	if restrictions := discovery.requirements {
		if allowed := restrictions.allowed_permission_profiles {
			return allowed.len == 2 && allowed[*id] && !allowed['false-id']
		}
	}
	return false
}
