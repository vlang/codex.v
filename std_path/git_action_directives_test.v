module std_path

// STUB: Verify the borrowed std::path::Path boundary reused by the translated TUI.
fn test_borrowed_strip_prefix_views_preserve_owner_and_components() {
	mut path_text := '/repo//src/./a.ts/'
	mut prefix_text := '/repo/.'
	$if ownership ? {
		path_text = path_text.to_owned()
		prefix_text = prefix_text.to_owned()
	}
	path := Path.new(&path_text)
	prefix := Path.new(&prefix_text)
	first := path.strip_prefix(&prefix) or { panic(err) }
	second := path.strip_prefix(&prefix) or { panic(err) }
	assert first.to_string_lossy() == 'src/./a.ts'
	assert second.to_path_buf() == 'src/./a.ts'
	assert !first.is_absolute()
	assert !second.is_absolute()
	assert path.to_path_buf() == '/repo//src/./a.ts/'
	assert path.to_string_lossy() == '/repo//src/./a.ts/'
	assert prefix_text == '/repo/.'
	assert path_text == '/repo//src/./a.ts/'
}

// STUB: std::path::Path::to_string_lossy must match Rust's invalid-sequence grouping.
fn test_lossy_path_conversion_preserves_native_bytes_in_owned_path_buf() {
	invalid := [u8(0xf0), 0x80, 0x80, `a`, 0xe2, 0x82].bytestr()
	path := Path.new(&invalid)
	assert path.to_string_lossy() == '\ufffd\ufffd\ufffda\ufffd'
	assert path.to_string_lossy() == '\ufffd\ufffd\ufffda\ufffd'
	assert path.to_path_buf().bytes() == [u8(0xf0), 0x80, 0x80, `a`, 0xe2, 0x82]
	assert invalid.bytes() == [u8(0xf0), 0x80, 0x80, `a`, 0xe2, 0x82]
}

// STUB: std's Windows prefix fields compare semantically and retain verbatim rules.
fn test_native_windows_drive_unc_device_and_verbatim_prefixes() {
	$if windows {
		pairs := [
			[r'C:\src\a', r'c:\src', 'a'],
			[r'C:.\src\a', r'C:.', r'src\a'],
			[r'\\server\share\a', '//server/share', 'a'],
			[r'\\.\COM42\a', '//./COM42', 'a'],
			[r'\\?\C:\src\.\a', r'\\?\c:\src', r'.\a'],
			// Verbatim UNC emits a RootDir only for a physical separator, so
			// a prefix without that separator leaves the root in the remainder.
			[r'\\?\UNC\server\share\a', r'\\?\UNC\server\share', r'\a'],
		]
		for pair in pairs {
			path := Path.new(&pair[0])
			prefix := Path.new(&pair[1])
			actual := path.strip_prefix(&prefix) or { panic(err) }
			assert actual.to_path_buf() == pair[2]
		}
		drive_text := r'\\?\C:'
		drive := Path.new(&drive_text)
		assert drive.is_absolute()
		generic_verbatim_text := r'\\?\C:tail'
		generic_verbatim := Path.new(&generic_verbatim_text)
		assert generic_verbatim.is_absolute()
	}
}
