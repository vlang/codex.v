module codex_utils_path

// STUB: verify borrowed trusted-helper discovery retains its heap-owned name,
// rejects path escapes and native NULs, and supplies a trusted child PATH.
fn test_keyboard_system_helper_borrows_name_and_rejects_path_escapes() {
	mut name := $if windows { 'cmd' } $else { 'sh' }
	$if ownership ? {
		name = name.to_owned()
	}
	for _ in 0 .. 2 {
		executable := system_executable(&name) or { panic('installed system helper was not found') }
		view := executable.as_path()
		assert view.is_absolute()
		assert view.to_path_buf().len > 0
	}
	assert name == $if windows { 'cmd' } $else { 'sh' }
	for invalid in ['', '.', '..', '../sh', '/bin/sh', 'sh\x00invalid'] {
		assert system_executable(&invalid) == none
	}
	path := system_path() or { panic(err) }
	assert path.len > 0
	assert !path.starts_with(':')
	assert !path.starts_with(';')
}

// STUB: trust checks compare components, preventing sibling-prefix bypasses.
fn test_keyboard_installation_root_component_boundaries() {
	$if !windows {
		root := '/usr/local'
		installed := '/usr/local/bin/tmux'
		sibling := '/usr/local-untrusted/tmux'
		assert keyboard_path_within(&installed, &root)
		assert !keyboard_path_within(&sibling, &root)
		missing := '/codex-missing-installation-root/probe'
		assert keyboard_canonicalize(&missing) == none
	}
}
