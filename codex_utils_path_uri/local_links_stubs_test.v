module codex_utils_path_uri

fn local_links_uri_owned(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn test_parsed_drive_uri_canonicalizes_case_and_keeps_input_reusable() {
	input := local_links_uri_owned('file:///c%3a/Users/Alice%20Smith/a.rs')
	for _ in 0 .. 2 {
		path := PathUri.parse(&input) or { panic('drive URI') }
		assert path.str() == 'file:///C%3a/Users/Alice%20Smith/a.rs'
		assert path.inferred_native_path_string() == 'C:\\Users\\Alice Smith\\a.rs'
		assert path.inferred_native_path_string() == 'C:\\Users\\Alice Smith\\a.rs'
		assert path.str() == 'file:///C%3a/Users/Alice%20Smith/a.rs'
	}
	assert input == 'file:///c%3a/Users/Alice%20Smith/a.rs'
}

fn test_drive_case_normalization_preserves_posix_and_unc_path_segments() {
	for input in ['file:///case/a', 'file://server/c:/a', 'file:///c%253a/a', 'file:///c:dir/a'] {
		path := PathUri.parse(&input) or { panic('URI') }
		assert path.str() == input
	}
	input := local_links_uri_owned('file://///c:/repo')
	path := PathUri.parse(&input) or { panic('empty URI segments') }
	assert path.str() == 'file://///C:/repo'
	assert input == 'file://///c:/repo'
}
