module codex_app_server_protocol

import codex_protocol
import serde_json
import std_path

// STUB: protocol/v2/command_exec.rs::CommandExecTerminalSize carries the exact PTY dimensions.
pub struct CommandExecTerminalSize {
pub:
	rows u16
	cols u16
}

// STUB: protocol/v2/command_exec.rs::CommandExecParams retains every typed request field
// and reuses the canonical native-path owner.
pub struct CommandExecParams {
pub:
	command              []string
	process_id           ?string                       @[json: 'processId'; json_null]
	tty                  bool                          @[omitempty]
	stream_stdin         bool                          @[json: 'streamStdin'; omitempty]
	stream_stdout_stderr bool                          @[json: 'streamStdoutStderr'; omitempty]
	output_bytes_cap     ?usize                        @[json: 'outputBytesCap'; json_null]
	disable_output_cap   bool                          @[json: 'disableOutputCap'; omitempty]
	disable_timeout      bool                          @[json: 'disableTimeout'; omitempty]
	timeout_ms           ?i64                          @[json: 'timeoutMs'; json_null]
	cwd                  ?std_path.PathBuf             @[json_null]
	env                  ?map[string]?string           @[json_null]
	size                 ?CommandExecTerminalSize      @[json_null]
	sandbox_policy       ?codex_protocol.SandboxPolicy @[json: 'sandboxPolicy'; json_null]
	permission_profile   ?string                       @[json: 'permissionProfile'; json_null]
}

// STUB: protocol/v2/command_exec.rs::CommandExecResponse, the buffered completion payload.
pub struct CommandExecResponse {
pub:
	exit_code i32 @[json: 'exitCode']
	stdout    string
	stderr    string
}

// STUB: protocol/common.rs::ClientRequest::OneOffCommandExec is command/exec on the wire.
pub struct ClientRequestOneOffCommandExec {
pub:
	request_id RequestId
	params     CommandExecParams
}

// STUB: RPC serialization clones an independent server-owned CommandExecParams payload.
pub fn (params &CommandExecParams) clone() CommandExecParams {
	mut env := ?map[string]?string(none)
	if overrides := params.env {
		mut copied := map[string]?string{}
		// V3 needs a key array and the canonical typed option wrapper for safe nullable lookup.
		for key in overrides.keys() {
			value := codex_protocol.OptionalString{ is_set: true, value: overrides[key] }
			copied[key.clone()] = if contents := value.value { contents.clone() } else { none }
		}
		env = copied
	}
	return CommandExecParams{
		command:              params.command.clone()
		process_id:           if value := params.process_id { value.clone() } else { none }
		tty:                  params.tty
		stream_stdin:         params.stream_stdin
		stream_stdout_stderr: params.stream_stdout_stderr
		output_bytes_cap:     params.output_bytes_cap
		disable_output_cap:   params.disable_output_cap
		disable_timeout:      params.disable_timeout
		timeout_ms:           params.timeout_ms
		cwd:                  if value := params.cwd { value.clone() } else { none }
		env:                  env
		size:                 params.size
		sandbox_policy:       if policy := params.sandbox_policy {
			codex_protocol.SandboxPolicy{ ...policy, writable_roots: policy.writable_roots.clone() }
		} else {
			none
		}
		permission_profile:   if value := params.permission_profile { value.clone() } else { none }
	}
}

// STUB: CommandExecParams's serde Serialize uses native-path serialization rather than
// reflecting PathBuf's private representation. Optional fields serialize as null, while
// false control flags are omitted, matching the source v2 request annotations.
pub fn (params &CommandExecParams) serialize_json() !string {
	mut command := []string{cap: params.command.len}
	for index in 0 .. params.command.len {
		command << serde_json.quote_string(&params.command[index])
	}
	process_id := if value := params.process_id { serde_json.quote_string(&value) } else { 'null' }
	mut result := '{"command":[' + command.join(',') + '],"processId":' + process_id
	if params.tty { result += ',"tty":true' }
	if params.stream_stdin { result += ',"streamStdin":true' }
	if params.stream_stdout_stderr { result += ',"streamStdoutStderr":true' }
	cap := if value := params.output_bytes_cap { value.str() } else { 'null' }
	result += ',"outputBytesCap":' + cap
	if params.disable_output_cap { result += ',"disableOutputCap":true' }
	if params.disable_timeout { result += ',"disableTimeout":true' }
	timeout := if value := params.timeout_ms { value.str() } else { 'null' }
	result += ',"timeoutMs":' + timeout
	cwd := if path := params.cwd { path.serialize_json()! } else { 'null' }
	result += ',"cwd":' + cwd
	mut env := 'null'
	if overrides := params.env {
		mut pairs := []string{cap: overrides.len}
		// A typed snapshot of each present key avoids V3's optional-map pointer unwrap error.
		for key in overrides.keys() {
			value := codex_protocol.OptionalString{ is_set: true, value: overrides[key] }
			contents := if text := value.value { serde_json.quote_string(&text) } else { 'null' }
			pairs << serde_json.quote_string(&key) + ':' + contents
		}
		env = '{' + pairs.join(',') + '}'
	}
	result += ',"env":' + env
	size := if value := params.size {
		'{"rows":${value.rows},"cols":${value.cols}}'
	} else {
		'null'
	}
	result += ',"size":' + size
	policy := if value := params.sandbox_policy {
		workspace_command_sandbox_json(&value)!
	} else {
		'null'
	}
	result += ',"sandboxPolicy":' + policy
	profile := if value := params.permission_profile {
		serde_json.quote_string(&value)
	} else {
		'null'
	}
	return result + ',"permissionProfile":' + profile + '}'
}

// STUB: protocol/v2/permissions.rs::SandboxPolicy's camelCase serde view reuses the
// canonical typed policy payload, preserving every source variant and its fields.
fn workspace_command_sandbox_json(policy &codex_protocol.SandboxPolicy) !string {
	return match policy.policy_kind {
		.danger_full_access { '{"type":"dangerFullAccess"}' }
		.read_only { '{"type":"readOnly","networkAccess":${policy.network_access}}' }
		.external_sandbox {
			'{"type":"externalSandbox","networkAccess":"${policy.external_network_access}"}'
		}
		.workspace_write {
			mut roots := []string{cap: policy.writable_roots.len}
			for index in 0 .. policy.writable_roots.len {
				path := std_path.PathBuf.from(policy.writable_roots[index].path.clone())
				roots << path.serialize_json()!
			}
			'{"type":"workspaceWrite","writableRoots":[' + roots.join(',') + '],"networkAccess":${policy.network_access},"excludeTmpdirEnvVar":${policy.exclude_tmpdir_env_var},"excludeSlashTmp":${policy.exclude_slash_tmp}}'
		}
	}
}
