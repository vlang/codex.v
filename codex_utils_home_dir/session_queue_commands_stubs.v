module codex_utils_home_dir

import codex_utils_absolute_path
import std_io

// STUB: the source home resolver's distinct successful path and IO failure.
pub type SessionQueueHomeReply = codex_utils_absolute_path.AbsolutePathBuf | std_io.Error

// STUB: a fixture replaces environment-dependent utils/home-dir/src/lib.rs.
@[heap]
struct SessionQueueHomeFixture {
mut:
	ready bool
	reply SessionQueueHomeReply = std_io.Error{}
	calls int
}

// STUB: the owned one-shot home result is separate from archive startup/probing.
const session_queue_home_fixture = &SessionQueueHomeFixture{}

// STUB: utils/home-dir/src/lib.rs::find_codex_home preserves the native result
// shape; unported environment resolution fails explicitly when no fixture exists.
pub fn find_codex_home() !codex_utils_absolute_path.AbsolutePathBuf {
	mut fixture := unsafe { session_queue_home_fixture }
	fixture.calls++
	if !fixture.ready {
		return std_io.Error.new(.unsupported, 'Codex home resolution is not translated')
	}
	reply := fixture.reply
	fixture.ready = false
	fixture.reply = std_io.Error.new(.unsupported, 'Codex home resolution is not translated')
	return match reply {
		codex_utils_absolute_path.AbsolutePathBuf { reply }
		std_io.Error { reply }
	}
}

// STUB: install the owned path/error returned by the next source-shaped home call.
pub fn configure_session_queue_home(reply SessionQueueHomeReply) {
	mut fixture := unsafe { session_queue_home_fixture }
	fixture.reply = reply
	fixture.ready = true
	fixture.calls = 0
}

// STUB: observe home-resolution order independently of startup/probe state.
pub fn session_queue_home_calls() int {
	return session_queue_home_fixture.calls
}
