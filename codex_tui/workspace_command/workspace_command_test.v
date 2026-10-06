module workspace_command

import codex_app_server_client as client
import codex_app_server_protocol
import codex_protocol
import codex_utils_absolute_path
import serde_json
import std_path
import std_time
import uuid

fn owned_workspace_string(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value
	}
}

fn workspace_response(exit_code i32, stdout string, stderr string) client.WorkspaceCommandReply {
	return codex_app_server_protocol.CommandExecResponse{ exit_code: exit_code, stdout: stdout, stderr: stderr }
}

fn test_owned_builders_preserve_argv_and_replace_env_overrides() {
	command := WorkspaceCommand.new([
		owned_workspace_string('git'),
		owned_workspace_string('status'),
		owned_workspace_string('unquoted value; $(literal)\nПривет'),
	]).cwd(std_path.PathBuf.from(owned_workspace_string('/workspace/with spaces'))).env(owned_workspace_string('MODE'),
		owned_workspace_string('first')).env(owned_workspace_string('MODE'),
		owned_workspace_string('second')).env(owned_workspace_string('OTHER'),
		owned_workspace_string('')).timeout(std_time.Duration.new(7, 123_456_789)).disable_output_cap()
	assert command == WorkspaceCommand{
		argv:               ['git', 'status', 'unquoted value; $(literal)\nПривет']
		cwd:                std_path.PathBuf.from('/workspace/with spaces')
		env:                {
			'MODE':  ?string('second')
			'OTHER': ?string('')
		}
		timeout:            std_time.Duration.new(7, 123_456_789)
		output_bytes_cap:   64 * 1024
		disable_output_cap: true
	}
}

fn test_command_clone_retains_heap_owners_and_independent_overrides() {
	command := WorkspaceCommand.new([owned_workspace_string('probe')]).cwd(std_path.PathBuf.from(owned_workspace_string('/cwd'))).env(owned_workspace_string('KEY'), owned_workspace_string('original'))
	first := command.clone().env(owned_workspace_string('KEY'), owned_workspace_string('changed'))
	second := command.clone()
	assert (command.env['KEY'] or { '' }) == 'original'
	assert (first.env['KEY'] or { '' }) == 'changed'
	assert second == command
	assert command.argv == ['probe']
	path := command.cwd or { panic('expected cwd') }
	assert path.as_path().to_path_buf() == '/cwd'
	assert command.clone() == second
}

fn test_shared_runner_preserves_default_request_and_nonzero_completion() {
	handle := client.AppServerRequestHandle{}.with_workspace_command_fixture([
		workspace_response(0, owned_workspace_string('first stdout'), owned_workspace_string('first stderr')),
		workspace_response(27, owned_workspace_string('second stdout'), owned_workspace_string('second stderr')),
	])
	runner := WorkspaceCommandRunner.new(AppServerWorkspaceCommandRunner.new(handle.clone()))
	shared_runner := runner.clone()
	first := runner.run(WorkspaceCommand.new([owned_workspace_string('git'),
		owned_workspace_string('status')])) or { panic(err.msg()) }
	second := shared_runner.run(WorkspaceCommand.new([owned_workspace_string('git'),
		owned_workspace_string('rev-parse')])) or { panic(err.msg()) }
	assert first == WorkspaceCommandOutput{ exit_code: 0, stdout: 'first stdout', stderr: 'first stderr' }
	assert second == WorkspaceCommandOutput{ exit_code: 27, stdout: 'second stdout', stderr: 'second stderr' }
	assert first.success()
	assert first.success()
	assert !second.success()
	assert !second.success()
	assert first.stdout == 'first stdout'
	assert second.stderr == 'second stderr'
	requests := handle.workspace_command_fixture_requests()
	assert requests.len == 2
	for index in 0 .. requests.len {
		request := &requests[index]
		assert request.request_id.kind == .string_id
		assert request.request_id.string_value.starts_with('workspace-command-')
		id := request.request_id.string_value['workspace-command-'.len..].clone()
		parsed := uuid.Uuid.parse_str(&id) or { panic(err.msg()) }
		assert parsed.str() == id
		assert id[14] == `4`
		assert id[19] in [`8`, `9`, `a`, `b`]
		assert request.params == codex_app_server_protocol.CommandExecParams{
			command:          if index == 0 { ['git', 'status'] } else { ['git', 'rev-parse'] }
			output_bytes_cap: usize(64 * 1024)
			timeout_ms:       i64(5_000)
		}
	}
	assert requests[0].request_id.string_value != requests[1].request_id.string_value
	assert handle.workspace_command_fixture_requests() == requests
}

fn test_custom_cap_env_removal_and_cwd_bytes_pass_through_request() {
	handle := client.AppServerRequestHandle{}.with_workspace_command_fixture([workspace_response(0, '', '')])
	runner := AppServerWorkspaceCommandRunner.new(handle.clone())
	mut cwd := '/workspace/with spaces'
	$if !windows {
		cwd = '/workspace/\xff'.clone()
	}
	command := WorkspaceCommand{
		argv:             [owned_workspace_string('program'),
			owned_workspace_string('literal; $(command)')]
		cwd:              std_path.PathBuf.from(owned_workspace_string(cwd.clone()))
		env:              {
			'ADD':    ?string(owned_workspace_string('exact\nvalue'))
			'REMOVE': ?string(none)
		}
		timeout:          std_time.Duration.new(1, 999_999_999)
		output_bytes_cap: 17
	}
	_ := runner.run(command) or { panic(err.msg()) }
	requests := handle.workspace_command_fixture_requests()
	assert requests.len == 1
	assert requests[0].params == codex_app_server_protocol.CommandExecParams{
		command:          ['program', 'literal; $(command)']
		output_bytes_cap: usize(17)
		timeout_ms:       i64(1_999)
		cwd:              std_path.PathBuf.from(cwd.clone())
		env:              {
			'ADD':    ?string('exact\nvalue')
			'REMOVE': ?string(none)
		}
	}
	assert runner.clone().request_handle.workspace_command_fixture_requests() == requests
}

fn test_uncapped_request_omits_cap_and_timeout_saturates_only_after_i64_max() {
	handle := client.AppServerRequestHandle{}.with_workspace_command_fixture([
		workspace_response(0, '', ''),
		workspace_response(0, '', ''),
		workspace_response(0, '', ''),
	])
	runner := AppServerWorkspaceCommandRunner.new(handle.clone())
	for duration in [
		std_time.Duration.from_millis(u64(9_223_372_036_854_775_807)),
		std_time.Duration.from_millis(u64(9_223_372_036_854_775_808)),
		std_time.duration_max,
	] {
		_ := runner.run(WorkspaceCommand.new([owned_workspace_string('probe')]).timeout(duration).disable_output_cap()) or { panic(err.msg()) }
	}
	requests := handle.workspace_command_fixture_requests()
	assert requests.len == 3
	for index in 0 .. requests.len {
		assert requests[index].params == codex_app_server_protocol.CommandExecParams{
			command:            ['probe']
			disable_output_cap: true
			timeout_ms:         i64(9_223_372_036_854_775_807)
		}
	}
}

fn test_zero_timeout_and_zero_output_cap_are_preserved() {
	handle := client.AppServerRequestHandle{}.with_workspace_command_fixture([workspace_response(0, '', '')])
	runner := AppServerWorkspaceCommandRunner.new(handle.clone())
	_ := runner.run(WorkspaceCommand{ argv: [owned_workspace_string('probe')], timeout: std_time.duration_zero, output_bytes_cap: 0 }) or { panic(err.msg()) }
	requests := handle.workspace_command_fixture_requests()
	assert requests[0].params == codex_app_server_protocol.CommandExecParams{ command: ['probe'], output_bytes_cap: usize(0), timeout_ms: i64(0) }
}

fn test_error_layers_become_workspace_errors_with_the_source_display_message() {
	handle := client.AppServerRequestHandle{}.with_workspace_command_fixture([
		client.WorkspaceCommandReply(client.TypedRequestError{ kind: .transport, method: owned_workspace_string('command/exec'), transport_source: error('fixture disconnected') }),
		client.WorkspaceCommandReply(client.TypedRequestError{ kind: .server, method: owned_workspace_string('command/exec'), server_source: codex_app_server_protocol.JSONRPCErrorError{ code: -32603, message: owned_workspace_string('fixture rejected') } }),
		client.WorkspaceCommandReply(client.TypedRequestError{ kind: .deserialize, method: owned_workspace_string('command/exec'), deserialize_source: error('fixture malformed response') }),
	])
	runner := AppServerWorkspaceCommandRunner.new(handle.clone())
	for expected in [
		'command/exec transport error: fixture disconnected',
		'command/exec failed: fixture rejected (code -32603)',
		'command/exec response decode error: fixture malformed response',
	] {
		if _ := runner.run(WorkspaceCommand.new([owned_workspace_string('probe')])) {
			assert false
		} else {
			assert err is WorkspaceCommandError
			assert err.msg() == expected
			assert err.msg() == expected
			if err is WorkspaceCommandError {
				assert err.str() == expected
				assert err.clone() == err
			}
		}
	}
	assert handle.workspace_command_fixture_requests().len == 3
}

fn test_untranslated_transport_reports_failure_without_fabricating_output() {
	runner := AppServerWorkspaceCommandRunner.new(client.AppServerRequestHandle{})
	if _ := runner.run(WorkspaceCommand.new([owned_workspace_string('probe')])) {
		assert false
	} else {
		assert err is WorkspaceCommandError
		assert err.msg() == 'command/exec transport error: app-server client is not available'
	}
}

fn test_output_and_error_borrowed_apis_retain_allocated_owners() {
	output := WorkspaceCommandOutput{ exit_code: -1, stdout: owned_workspace_string('heap stdout'), stderr: owned_workspace_string('heap stderr') }
	assert !output.success()
	assert !output.success()
	assert output.clone() == output
	assert output.clone() == output
	assert output.stdout == 'heap stdout'
	assert output.stderr == 'heap stderr'
	failure := WorkspaceCommandError.new(owned_workspace_string('heap failure'))
	assert failure.msg() == 'heap failure'
	assert failure.str() == 'heap failure'
	assert failure.clone() == failure
	assert failure.message == 'heap failure'
}

fn test_command_exec_wire_names_nullable_fields_and_environment_removal() {
	params := codex_app_server_protocol.CommandExecParams{
		command:            [owned_workspace_string('probe')]
		disable_output_cap: true
		timeout_ms:         i64(123)
		env:                {
			'SET':    ?string(owned_workspace_string('value'))
			'REMOVE': ?string(none)
		}
	}
	encoded := params.serialize_json() or { panic(err.msg()) }
	decoded := serde_json.from_str(&encoded) or { panic(err.msg()) }
	expected_text := '{"command":["probe"],"processId":null,"outputBytesCap":null,"disableOutputCap":true,"timeoutMs":123,"cwd":null,"env":{"SET":"value","REMOVE":null},"size":null,"sandboxPolicy":null,"permissionProfile":null}'
	expected := serde_json.from_str(&expected_text) or { panic(err.msg()) }
	assert decoded.equals(&expected)
	assert params.clone() == params
	assert (params.env or { panic('missing env') })['SET'] or { '' } == 'value'
}

fn test_native_cwd_serialization_retains_the_typed_path_owner() {
	params := codex_app_server_protocol.CommandExecParams{ command: [owned_workspace_string('probe')], cwd: std_path.PathBuf.from(owned_workspace_string('/workspace/quoted"path')) }
	first := params.serialize_json() or { panic(err.msg()) }
	second := params.serialize_json() or { panic(err.msg()) }
	assert first == second
	assert first.contains('"cwd":"/workspace/quoted\\"path"')
	assert params.clone() == params
	path := params.cwd or { panic('missing path owner') }
	assert path.as_path().to_path_buf() == '/workspace/quoted"path'
	$if !windows {
		invalid := codex_app_server_protocol.CommandExecParams{ command: [owned_workspace_string('probe')], cwd: std_path.PathBuf.from(owned_workspace_string('/workspace/\xff')) }
		for _ in 0 .. 2 {
			if _ := invalid.serialize_json() {
				assert false
			} else {
				assert err.msg() == 'path contains invalid UTF-8 characters'
			}
		}
		assert invalid.clone() == invalid
	}
}

fn test_optional_command_transport_fields_keep_the_protocol_wire_shapes() {
	for policy in [
		codex_protocol.SandboxPolicy{ policy_kind: .danger_full_access },
		codex_protocol.SandboxPolicy{ policy_kind: .read_only, network_access: true },
		codex_protocol.SandboxPolicy{ policy_kind: .external_sandbox, external_network_access: .enabled },
		codex_protocol.SandboxPolicy{ policy_kind: .workspace_write, writable_roots: [codex_utils_absolute_path.AbsolutePathBuf{ path: owned_workspace_string('/native/root') }], network_access: false, exclude_tmpdir_env_var: true, exclude_slash_tmp: true },
	] {
		policy_kind := policy.policy_kind
		params := codex_app_server_protocol.CommandExecParams{
			command:              [owned_workspace_string('probe')]
			process_id:           owned_workspace_string('client-process')
			tty:                  true
			stream_stdin:         true
			stream_stdout_stderr: true
			disable_timeout:      true
			size:                 codex_app_server_protocol.CommandExecTerminalSize{ rows: 12, cols: 34 }
			sandbox_policy:       policy
			permission_profile:   owned_workspace_string('profile')
		}
		encoded := params.serialize_json() or { panic(err.msg()) }
		assert encoded.contains('"processId":"client-process","tty":true,"streamStdin":true,"streamStdoutStderr":true')
		assert encoded.contains('"disableTimeout":true')
		assert encoded.contains('"size":{"rows":12,"cols":34}')
		assert encoded.contains('"permissionProfile":"profile"')
		match policy_kind {
			.danger_full_access {
				assert encoded.contains('"sandboxPolicy":{"type":"dangerFullAccess"}')
			}
			.read_only {
				assert encoded.contains('"sandboxPolicy":{"type":"readOnly","networkAccess":true}')
			}
			.external_sandbox {
				assert encoded.contains('"sandboxPolicy":{"type":"externalSandbox","networkAccess":"enabled"}')
			}
			.workspace_write {
				assert encoded.contains('"sandboxPolicy":{"type":"workspaceWrite","writableRoots":["/native/root"],"networkAccess":false,"excludeTmpdirEnvVar":true,"excludeSlashTmp":true}')
			}
		}
	}
}
