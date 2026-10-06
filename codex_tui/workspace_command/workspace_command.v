// App-server-backed workspace command execution for TUI-owned background lookups.
//
// This module is the TUI boundary for non-interactive commands that need to run wherever
// the active workspace lives. Callers describe a command in terms of argv, cwd, environment
// overrides, timeout, and output cap; the runner translates that request to app-server
// `command/exec`. Keeping this as a TUI-local abstraction lets status surfaces avoid knowing
// whether the current app-server is embedded or remote.
//
// Commands sent through this path should not prompt for stdin. Most callers should keep output
// bounded so metadata refreshes cannot grow into unbounded background processes; callers that own a
// full user-visible payload, such as `/diff`, can explicitly opt out of output capping.
module workspace_command

import codex_app_server_client as client
import codex_app_server_protocol
import codex_protocol
import std_path
import std_time
import uuid

// Shared handle for running workspace commands from TUI components.
// Rust's Arc is a GC-managed shared heap interface in V; cloning retains the same executor.
// An explicit handle keeps borrowed receiver calls safe: V currently passes a pointer alias
// directly to a &alias receiver even when its generated C signature requires a double pointer.
// V has no crate-only visibility, so sibling-module APIs are public.
pub struct WorkspaceCommandRunner {
	cell &WorkspaceCommandExecutorCell
}

// Describes a bounded non-interactive command to execute in the active workspace.
//
// The command is intentionally argv-based rather than shell-based so callers do not need to quote
// user or repository data. `cwd` is interpreted by app-server relative to the workspace rules for
// the active session, which is what makes the same request shape work for embedded and remote
// app-server instances.
pub struct WorkspaceCommand {
pub:
	// Program and arguments to execute without shell interpolation.
	argv []string
	// Working directory for the command, if different from app-server's session cwd.
	cwd ?std_path.PathBuf
	// Environment overrides where none removes a variable.
	env map[string]?string
	// Maximum wall-clock duration before app-server cancels the command.
	timeout std_time.Duration
	// Maximum captured stdout/stderr bytes returned by app-server.
	output_bytes_cap usize
	// Whether app-server should return uncapped stdout/stderr.
	disable_output_cap bool
}

// Creates a workspace command with conservative defaults for metadata probes.
// V accepts an owned argv array after the caller performs Rust's Into<String> conversions.
pub fn WorkspaceCommand.new(argv []string) WorkspaceCommand {
	return WorkspaceCommand{
		argv:               argv
		cwd:                none
		env:                map[string]?string{}
		timeout:            std_time.Duration.from_secs( /*secs*/
		5)
		output_bytes_cap:   64 * 1024
		disable_output_cap: false
	}
}

// Sets the command working directory.
pub fn (command WorkspaceCommand) cwd(cwd std_path.PathBuf) WorkspaceCommand {
	return WorkspaceCommand{ ...command, cwd: cwd }
}

// Adds or replaces one environment variable override.
pub fn (command WorkspaceCommand) env(key string, value string) WorkspaceCommand {
	mut env := command.env
	env[key] = value
	return WorkspaceCommand{ ...command, env: env }
}

// Sets the maximum wall-clock duration before app-server cancels the command.
pub fn (command WorkspaceCommand) timeout(timeout std_time.Duration) WorkspaceCommand {
	return WorkspaceCommand{ ...command, timeout: timeout }
}

// Requests uncapped stdout/stderr capture from app-server.
pub fn (command WorkspaceCommand) disable_output_cap() WorkspaceCommand {
	return WorkspaceCommand{ ...command, disable_output_cap: true }
}

// Rust's derived Clone owns independent argv, cwd, and environment data.
pub fn (command &WorkspaceCommand) clone() WorkspaceCommand {
	mut env := map[string]?string{}
	// V3 needs a key array and a typed option snapshot to unwrap borrowed nullable map values.
	// Each enumerated key is present; the canonical nested-option wrapper preserves its null value.
	for key in command.env.keys() {
		value := codex_protocol.OptionalString{ is_set: true, value: command.env[key] }
		env[key.clone()] = if contents := value.value { contents.clone() } else { none }
	}
	return WorkspaceCommand{
		argv:               command.argv.clone()
		cwd:                if value := command.cwd { value.clone() } else { none }
		env:                env
		timeout:            command.timeout
		output_bytes_cap:   command.output_bytes_cap
		disable_output_cap: command.disable_output_cap
	}
}

// Captured result from a completed workspace command.
pub struct WorkspaceCommandOutput {
pub:
	// Process exit status code reported by app-server.
	exit_code i32
	// Captured stdout after app-server output capping.
	stdout string
	// Captured stderr after app-server output capping.
	stderr string
}

// Returns whether the process exited successfully.
pub fn (output &WorkspaceCommandOutput) success() bool {
	return output.exit_code == 0
}

// Rust's derived Clone preserves owned stdout and stderr.
pub fn (output &WorkspaceCommandOutput) clone() WorkspaceCommandOutput {
	return WorkspaceCommandOutput{ exit_code: output.exit_code, stdout: output.stdout.clone(), stderr: output.stderr.clone() }
}

// Transport or protocol failure before a command result was available.
//
// Non-zero process exits are represented as `WorkspaceCommandOutput` so callers can distinguish
// a normal probe miss from an app-server request failure.
pub struct WorkspaceCommandError {
	message string
}

fn WorkspaceCommandError.new(message string) WorkspaceCommandError {
	return WorkspaceCommandError{ message: message }
}

// std::fmt::Display writes the borrowed message. V needs an owned display result.
pub fn (failure &WorkspaceCommandError) str() string {
	return failure.message.clone()
}

// std::error::Error is represented by V's IError message and code methods.
pub fn (failure &WorkspaceCommandError) msg() string {
	return failure.str()
}

pub fn (failure &WorkspaceCommandError) code() int {
	return 0
}

// Rust's derived Clone retains an independent message owner.
pub fn (failure &WorkspaceCommandError) clone() WorkspaceCommandError {
	return WorkspaceCommandError.new(failure.message.clone())
}

// Executes non-interactive workspace commands through the active TUI app-server session.
//
// Implementations decide where the workspace lives. Callers provide argv/cwd/env and should not
// branch on local versus remote execution.
// V interfaces have no Send + Sync bounds; implementations must preserve shared-call safety.
pub interface WorkspaceCommandExecutor {
	// Runs a workspace command and returns captured output or an app-server request error.
	//
	// Callers should treat errors as infrastructure failures and should treat successful output
	// with a non-zero exit code as ordinary command failure. Rust returns a boxed future to keep
	// the trait object-safe; V uses synchronous typed calls at the untranslated transport boundary.
	run(command WorkspaceCommand) !WorkspaceCommandOutput
}

// Keep the moved interface in an explicit heap allocation at Arc::new's allocation boundary.
// Taking &executor on the constructor parameter would leave a pointer into its stack frame.
@[heap]
struct WorkspaceCommandExecutorCell {
	executor WorkspaceCommandExecutor
}

// Own the executor on the heap at the same shared allocation boundary as Arc::new.
pub fn WorkspaceCommandRunner.new(executor WorkspaceCommandExecutor) WorkspaceCommandRunner {
	return WorkspaceCommandRunner{ cell: &WorkspaceCommandExecutorCell{ executor: executor } }
}

// Arc::clone keeps the same shared executor rather than cloning its command state.
pub fn (runner &WorkspaceCommandRunner) clone() WorkspaceCommandRunner {
	return WorkspaceCommandRunner{ cell: runner.cell }
}

// The shared handle forwards the object-safe executor method in V.
pub fn (runner &WorkspaceCommandRunner) run(command WorkspaceCommand) !WorkspaceCommandOutput {
	return runner.cell.executor.run(command)
}

// Workspace command runner that forwards every request to the active app-server.
pub struct AppServerWorkspaceCommandRunner {
	request_handle client.AppServerRequestHandle
}

// Creates a runner from an app-server request handle owned by the current TUI session.
pub fn AppServerWorkspaceCommandRunner.new(request_handle client.AppServerRequestHandle) AppServerWorkspaceCommandRunner {
	return AppServerWorkspaceCommandRunner{ request_handle: request_handle }
}

// Rust's derived Clone shares the request handle's underlying transport state.
pub fn (runner &AppServerWorkspaceCommandRunner) clone() AppServerWorkspaceCommandRunner {
	return AppServerWorkspaceCommandRunner.new(runner.request_handle.clone())
}

// Sends the command as a one-off app-server `command/exec` request.
//
// The request is non-tty, does not stream stdin/stdout/stderr, and uses the caller's timeout
// and output cap. It leaves sandbox and permission profile selection to app-server so the same
// runner follows the active session's embedded or remote execution policy.
pub fn (runner &AppServerWorkspaceCommandRunner) run(command WorkspaceCommand) !WorkspaceCommandOutput {
	millis := command.timeout.as_millis()
	timeout_ms := if millis.hi > 0 || millis.lo > u64(9_223_372_036_854_775_807) {
		i64(9_223_372_036_854_775_807)
	} else {
		i64(millis.lo)
	}
	env := if command.env.len == 0 {
		?map[string]?string(none)
	} else {
		?map[string]?string(command.env)
	}
	request := codex_app_server_protocol.ClientRequestOneOffCommandExec{
		request_id: codex_app_server_protocol.RequestId.string('workspace-command-${uuid.Uuid.new_v4()}')
		params:     codex_app_server_protocol.CommandExecParams{
			command:              command.argv
			process_id:           none
			tty:                  false
			stream_stdin:         false
			stream_stdout_stderr: false
			output_bytes_cap:     if command.disable_output_cap {
				none
			} else {
				?usize(command.output_bytes_cap)
			}
			disable_output_cap:   command.disable_output_cap
			disable_timeout:      false
			timeout_ms:           timeout_ms
			cwd:                  command.cwd
			env:                  env
			size:                 none
			sandbox_policy:       none
			permission_profile:   none
		}
	}
	// Borrowing the handle and naming the owned payload avoids V3 generic-callee snapshots.
	handle := &runner.request_handle
	response := handle.request_typed[codex_app_server_protocol.CommandExecResponse](request) or { return WorkspaceCommandError.new(err.msg()) }
	return WorkspaceCommandOutput{ exit_code: response.exit_code, stdout: response.stdout, stderr: response.stderr }
}
