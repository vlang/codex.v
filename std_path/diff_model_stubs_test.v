module std_path

// STUB: Check the std::path::PathBuf owned storage boundary used by diff_model.
fn test_owned_path_buf_clone_and_repeated_views_keep_native_bytes() {
	mut bytes := 'a//./b/'
	$if ownership ? {
		bytes = bytes.to_owned()
	}
	owner := PathBuf.from(bytes)
	cloned := owner.clone()
	assert cloned.equals(&owner)
	assert owner.equals(&cloned)
	assert owner.bytes.str != cloned.bytes.str
	first := owner.as_path()
	second := owner.as_path()
	assert first.equals(&second)
	assert owner.serialize_json() or { panic(err) } == '"a//./b/"'
	assert owner.serialize_json() or { panic(err) } == '"a//./b/"'
	assert owner.bytes == 'a//./b/'
	assert cloned.bytes == 'a//./b/'
	normalized := PathBuf.from('a/b')
	assert owner.equals(&normalized)
	assert first.to_path_buf() == 'a//./b/'
}
