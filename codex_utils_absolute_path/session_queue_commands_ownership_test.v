module codex_utils_absolute_path

import std_path

fn consume_session_queue_pathbuf(path std_path.PathBuf) {
	view := path.as_path()
	assert view.to_path_buf() == '/tmp/session-queue-owned-home'
}

fn test_session_queue_owned_path_results_preserve_the_borrowed_absolute_owner() {
	mut bytes := '/tmp/session-queue-owned-home'
	$if ownership ? {
		bytes = bytes.to_owned()
	}
	owner := AbsolutePathBuf{ path: bytes }
	first := owner.to_path_buf()
	second := owner.to_path_buf()
	first_view := first.as_path()
	second_view := second.as_path()
	owner_view := owner.as_path()
	assert first_view.to_path_buf() == '/tmp/session-queue-owned-home'
	assert second_view.to_path_buf() == '/tmp/session-queue-owned-home'
	assert owner_view.to_path_buf() == '/tmp/session-queue-owned-home'
	assert first_view.equals(&second_view)
	assert first_view.equals(&owner_view)
	assert owner.str() == '/tmp/session-queue-owned-home'
	assert owner.str() == '/tmp/session-queue-owned-home'
	assert owner.path == '/tmp/session-queue-owned-home'
	// Under ownership the consumed PathBuf drops here. Its independent allocation
	// must leave both the absolute owner and the second owned result usable.
	consume_session_queue_pathbuf(first)
	assert owner.path == '/tmp/session-queue-owned-home'
	assert owner.str() == '/tmp/session-queue-owned-home'
	assert second_view.to_path_buf() == '/tmp/session-queue-owned-home'
}
