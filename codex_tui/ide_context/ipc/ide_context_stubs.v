module ipc

import std_io
import std_path

$if windows {
	import codex_tui.ide_context.windows_pipe
}

// STUB: tui/src/ide_context/ipc.rs's Windows stream alias; only Windows builds
// load the untranslated named-pipe transport, as in the source module declaration.
$if windows {
	type IdeContextStream = windows_pipe.WindowsPipeStream
}

// STUB: tui/src/ide_context/ipc.rs::IdeContextError payload variants.
pub enum IdeContextErrorKind {
	connect
	send
	read
	invalid_response
	response_too_large
	request_failed
	unsupported_platform
}

// STUB: tui/src/ide_context/ipc.rs::IdeContextError preserves typed I/O errors
// and String payloads; the source's transport and hint behavior remain unported.
pub struct IdeContextError {
pub:
	kind     IdeContextErrorKind
	io_error std_io.Error
	detail   string
}

// STUB: thiserror Display for the typed dependency error shape.
pub fn (failure &IdeContextError) msg() string {
	return match failure.kind {
		.connect { 'failed to connect to IDE context provider: ${failure.io_error.msg()}' }
		.send { 'failed to request IDE context: ${failure.io_error.msg()}' }
		.read { 'failed to read IDE context: ${failure.io_error.msg()}' }
		.invalid_response { 'invalid IDE context response: ${failure.detail}' }
		.response_too_large { 'IDE context response exceeded maximum size' }
		.request_failed { 'IDE context request failed' }
		.unsupported_platform { 'IDE context is not supported on this platform' }
	}
}

// STUB: V IError requires a numeric code; the source enum has no numeric code.
pub fn (failure &IdeContextError) code() int {
	return 0
}

// STUB: tui/src/ide_context/ipc.rs::fetch_ide_context borrows both paths and
// returns the parent-owned model. A generic result avoids V's parent/child import
// cycle. Explicit failure reports that no IPC transport is implemented here.
pub fn fetch_ide_context[T](workspace_root &std_path.Path, codex_home &std_path.Path) !T {
	return IdeContextError{
		kind:     .connect
		io_error: std_io.Error.new(.unsupported, 'IDE context IPC transport is not translated')
	}
}
