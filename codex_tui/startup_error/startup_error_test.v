module startup_error

import std_path

fn test_display_preserves_path_detail_and_empty_fields() {
	failure := LocalStateDbStartupError.new('/tmp/state/session.sqlite', 'database is locked')
	assert failure.msg() == 'failed to initialize sqlite local db at /tmp/state/session.sqlite: database is locked'
	assert failure.detail() == 'database is locked'
	assert failure.database_path().to_path_buf() == '/tmp/state/session.sqlite'
	assert failure.state_db_path().to_path_buf() == '/tmp/state/session.sqlite'
	empty := LocalStateDbStartupError.new('', '')
	assert empty.msg() == 'failed to initialize sqlite local db at : '
	assert empty.detail() == ''
	assert empty.state_db_path().to_path_buf() == ''
}

fn test_display_uses_lossy_path_bytes_without_escaping_valid_text() {
	path := [u8(`/`), `d`, `b`, `/`, 0xf0, 0x80, 0x80, `a`, 0xe2, 0x82].bytestr()
	failure := LocalStateDbStartupError.new(path, 'detail: "☃"\nnext line')
	assert failure.msg() == 'failed to initialize sqlite local db at /db/\ufffd\ufffd\ufffda\ufffd: detail: "☃"\nnext line'
	assert failure.msg() == 'failed to initialize sqlite local db at /db/\ufffd\ufffd\ufffda\ufffd: detail: "☃"\nnext line'
	assert failure.database_path().to_path_buf().bytes() == [u8(`/`), `d`, `b`, `/`, 0xf0, 0x80,
		0x80, `a`, 0xe2, 0x82]
	assert failure.state_db_path().to_path_buf().bytes() == [u8(`/`), `d`, `b`, `/`, 0xf0, 0x80,
		0x80, `a`, 0xe2, 0x82]
	assert failure.detail() == 'detail: "☃"\nnext line'
}

fn test_borrowed_accessors_leave_heap_error_and_original_path_owner_reusable() {
	mut path_owner := '/tmp/reusable/./state.sqlite'
	mut detail := 'unable to open database file'
	$if ownership ? {
		path_owner = path_owner.to_owned()
		detail = detail.to_owned()
	}
	borrowed := std_path.Path.new(&path_owner)
	owned_path := borrowed.to_path_buf()
	failure := LocalStateDbStartupError.new(owned_path, detail)
	first_path := failure.database_path()
	second_path := failure.database_path()
	delegated_path := failure.state_db_path()
	first_detail := failure.detail()
	second_detail := failure.detail()
	assert first_path.to_path_buf() == '/tmp/reusable/./state.sqlite'
	assert second_path.to_path_buf() == '/tmp/reusable/./state.sqlite'
	assert delegated_path.to_path_buf() == '/tmp/reusable/./state.sqlite'
	assert first_detail == 'unable to open database file'
	assert second_detail == 'unable to open database file'
	assert failure.msg() == 'failed to initialize sqlite local db at /tmp/reusable/./state.sqlite: unable to open database file'
	assert failure.detail() == 'unable to open database file'
	assert borrowed.to_path_buf() == '/tmp/reusable/./state.sqlite'
	assert path_owner == '/tmp/reusable/./state.sqlite'
}

fn owned_startup_error_outputs() (string, string, string) {
	mut path := '/tmp/owned/startup.sqlite'
	mut detail := 'schema migration failed'
	$if ownership ? {
		path = path.to_owned()
		detail = detail.to_owned()
	}
	failure := LocalStateDbStartupError.new(path, detail)
	message := failure.msg()
	owned_detail := failure.detail()
	owned_path := failure.database_path().to_path_buf()
	return message, owned_detail, owned_path
}

fn test_owned_results_survive_error_drop() {
	message, detail, path := owned_startup_error_outputs()
	assert message == 'failed to initialize sqlite local db at /tmp/owned/startup.sqlite: schema migration failed'
	assert detail == 'schema migration failed'
	assert path == '/tmp/owned/startup.sqlite'
}

fn fail_local_state_db(database_path string, detail string) ! {
	return LocalStateDbStartupError.new(database_path, detail)
}

fn test_startup_error_preserves_display_through_v_error_interface() {
	mut database_path := '/tmp/interface.sqlite'
	mut detail := 'not a database'
	$if ownership ? {
		database_path = database_path.to_owned()
		detail = detail.to_owned()
	}
	fail_local_state_db(database_path, detail) or {
		assert err.msg() == 'failed to initialize sqlite local db at /tmp/interface.sqlite: not a database'
		assert err.msg() == 'failed to initialize sqlite local db at /tmp/interface.sqlite: not a database'
		assert err.code() == 0
		return
	}
	assert false, 'expected LocalStateDbStartupError'
}
