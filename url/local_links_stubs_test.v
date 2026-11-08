module url

fn local_links_url_owned(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn test_path_prefix_excludes_query_and_fragment_and_borrows_owner() {
	raw := local_links_url_owned('https://alice:secret@example.com:8443/a%20b?q=1#L12C3')
	parsed := Url.parse(&raw) or { panic('parse') }
	for _ in 0 .. 2 {
		assert parsed.prefix(.after_path) == 'https://alice:secret@example.com:8443/a%20b'
		fragment := parsed.fragment()
		assert fragment.has_value
		assert *fragment.value == 'L12C3'
		assert parsed.to_string() == raw
	}
	assert raw.ends_with('#L12C3')
	without_fragment := local_links_url_owned('file:///repo/a?ignored=1')
	file_url := Url.parse(&without_fragment) or { panic('parse') }
	assert file_url.prefix(.after_path) == 'file:///repo/a'
	assert !file_url.fragment().has_value
	assert file_url.to_string() == without_fragment
}

fn test_file_drive_normalization_retains_root_and_web_url_behavior() {
	inputs := ['file://c:/a/../../b', 'file://c|/a/../../b', 'file:///c|/a/../../b',
		'file://server/c:/a/../../b']
	for index in 0 .. inputs.len {
		parsed := Url.parse(&inputs[index]) or { panic('file drive') }
		assert parsed.to_string() == 'file:///c:/b'
	}
	web := local_links_url_owned('HTTPS://Example.COM:443/a/../b?q=1#L12')
	parsed := Url.parse(&web) or { panic('web URL') }
	assert parsed.to_string() == 'https://example.com/b?q=1#L12'
	assert parsed.prefix(.after_path) == 'https://example.com/b'
	assert web == 'HTTPS://Example.COM:443/a/../b?q=1#L12'
}
