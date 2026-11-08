// Tests for local-link parsing and root-preserving separator normalization.
module local_links

import codex_utils_path_uri
import std_path
import url
import urlencoding

fn test_load_location_suffix_regexes() {
	_ = load_colon_location_suffix_regex()
	_ = load_hash_location_suffix_regex()
}

fn test_trailing_separator_trimming_preserves_local_roots() {
	paths := ['/', '//', 'C:/', 'dir/', '//server/share/', 'C:/dir/']
	mut trimmed := []string{}
	for index in 0 .. paths.len {
		trimmed << trim_trailing_local_path_separator(&paths[index])
	}
	assert trimmed == ['/', '//', 'C:/', 'dir', '//server/share', 'C:/dir']
}

fn test_local_path_detection_uses_exact_lexical_shapes() {
	for destination in ['file:///repo/a', '/', '~/a', './a', '../a', '\\\\server\\share', 'C:/a',
		'z:\\a'] {
		assert is_local_path_like_link(&destination)
	}
	for destination in ['FILE:///repo/a', 'src/a', 'C:a', '1:/a', 'https://example.com/a', '\\a',
		''] {
		assert !is_local_path_like_link(&destination)
	}
}

fn test_location_suffixes_match_the_original_regex_grammar() {
	cases := [
		['a:001', ':001'],
		['a:12:3', ':12:3'],
		['a:12-14:9', ':12-14:9'],
		['a:12:3–14:9', ':12:3–14:9'],
		['a:1:2:3', ':2:3'],
		['C:/a:7', ':7'],
	]
	for index in 0 .. cases.len {
		assert (extract_colon_location_suffix(&cases[index][0]) or { panic('missing suffix') }) == cases[index][1]
	}
	for invalid in ['C:/a', 'a:1x', 'a:١', 'a:1\n', 'a:1-', 'a:'] {
		assert extract_colon_location_suffix(&invalid) == none
	}
	fragments := [
		['L12', ':12'],
		['L12C3', ':12:3'],
		['L12-L14', ':12-14'],
		['L12C3-L14C9', ':12:3-14:9'],
		['L01C00', ':01:00'],
	]
	for index in 0 .. fragments.len {
		assert (normalize_hash_location_suffix_fragment(&fragments[index][0]) or { panic('missing location') }) == fragments[index][1]
	}
	for invalid in ['L', 'l12', 'L12C', 'L12–L14', 'L12-L', 'L١', 'L12\n', 'anchor'] {
		assert normalize_hash_location_suffix_fragment(&invalid) == none
	}
}

fn test_plain_targets_preserve_lexical_paths_and_decode_once() {
	range_target := '../a/./b%20c.rs#L12C3-L14C9'
	assert (parse_local_link_target(&range_target) or { panic('path') }) == LocalLinkTarget{
		path:            '../a/./b c.rs'
		location_suffix: ':12:3-14:9'
	}
	preferred_hash_target := 'a:10#L12'
	assert (parse_local_link_target(&preferred_hash_target) or { panic('path') }) == LocalLinkTarget{
		path:            'a:10'
		location_suffix: ':12'
	}
	anchor_with_colon_target := 'a#anchor:10'
	assert (parse_local_link_target(&anchor_with_colon_target) or { panic('path') }) == LocalLinkTarget{
		path:            'a#anchor'
		location_suffix: ':10'
	}
	multiple_hash_target := 'a#L12#L14'
	assert (parse_local_link_target(&multiple_hash_target) or { panic('path') }) == LocalLinkTarget{
		path:            'a#L12'
		location_suffix: ':14'
	}
	double_encoded_target := 'percent%2520.rs:3'
	assert (parse_local_link_target(&double_encoded_target) or { panic('path') }) == LocalLinkTarget{
		path:            'percent%20.rs'
		location_suffix: ':3'
	}
	encoded_colon_target := 'a%3A12'
	assert (parse_local_link_target(&encoded_colon_target) or { panic('path') }) == LocalLinkTarget{ path: 'a:12' }
	encoded_hash_target := 'a%23L12'
	assert (parse_local_link_target(&encoded_hash_target) or { panic('path') }) == LocalLinkTarget{ path: 'a#L12' }
	invalid_utf8_target := 'a%FF%20b'
	assert (parse_local_link_target(&invalid_utf8_target) or { panic('path') }) == LocalLinkTarget{ path: 'a%FF%20b' }
	malformed_escape_target := 'a%2G+b#anchor'
	assert (parse_local_link_target(&malformed_escape_target) or { panic('path') }) == LocalLinkTarget{ path: 'a%2G+b#anchor' }
	home_target := '~/a\\..\\b'
	assert (parse_local_link_target(&home_target) or { panic('path') }) == LocalLinkTarget{ path: '~/a/../b' }
	repeated_unc_target := '\\\\\\\\server\\share\\a'
	assert (parse_local_link_target(&repeated_unc_target) or { panic('path') }) == LocalLinkTarget{ path: '//server/share/a' }
}

fn test_file_uri_targets_infer_execution_convention_and_strip_metadata() {
	drive_uri := 'file:///c:/repo/a.rs'
	assert (parse_local_link_target(&drive_uri) or { panic('canonical drive') }) == LocalLinkTarget{ path: 'C:/repo/a.rs' }
	encoded_drive_uri := 'file:///c%3a/repo/a.rs'
	assert (parse_local_link_target(&encoded_drive_uri) or { panic('canonical encoded drive') }) == LocalLinkTarget{ path: 'C:/repo/a.rs' }
	for legacy_drive_uri in ['file://c:/repo/a.rs', 'file://c|/repo/a.rs', 'file:///c|/repo/a.rs',
		'file://server/c:/repo/a.rs'] {
		assert (parse_local_link_target(&legacy_drive_uri) or { panic('legacy file drive') }) == LocalLinkTarget{ path: 'C:/repo/a.rs' }
	}
	drive_root_uri := 'file:///C:/a/../../b.rs'
	assert (parse_local_link_target(&drive_root_uri) or { panic('preserved drive root') }) == LocalLinkTarget{ path: 'C:/b.rs' }
	file_metadata_target := 'file:///repo/a%20b.rs?ignored=1#L12C3-L14C9'
	assert (parse_local_link_target(&file_metadata_target) or { panic('file URI') }) == LocalLinkTarget{
		path:            '/repo/a b.rs'
		location_suffix: ':12:3-14:9'
	}
	windows_target := 'file:///C:/repo/a.rs#L12'
	assert (parse_local_link_target(&windows_target) or { panic('Windows URI') }) == LocalLinkTarget{
		path:            'C:/repo/a.rs'
		location_suffix: ':12'
	}
	unc_target := 'file://server/share/a%2520.rs#L12'
	assert (parse_local_link_target(&unc_target) or { panic('UNC URI') }) == LocalLinkTarget{
		path:            '//server/share/a%20.rs'
		location_suffix: ':12'
	}
	localhost_target := 'file://localhost/repo/a#anchor'
	assert (parse_local_link_target(&localhost_target) or { panic('localhost URI') }) == LocalLinkTarget{ path: '/repo/a' }
	dot_segment_target := 'file:///repo/a/../b.rs'
	assert (parse_local_link_target(&dot_segment_target) or { panic('canonical URL path') }) == LocalLinkTarget{ path: '/repo/b.rs' }
	for invalid in ['file://user@server/a', 'file://server:80/a', 'file://[broken/a',
		'file:///repo/%00a'] {
		assert parse_local_link_target(&invalid) == none
	}
}

fn test_labels_compare_path_boundaries_url_spelling_and_unicode_case() {
	collapsed := [
		['src/a.rs', '/repo/src/a.rs:12'],
		['A.RS', '/repo/a.rs#L12'],
		['././a.rs/', '/repo/a.rs/'],
		['/repo/a.rs', 'a.rs'],
		['FILE:///repo/a.rs#L12', 'file:///repo/a.rs#L14'],
		['percent%20.rs', '/repo/percent%2520.rs'],
		['percent%2520.rs', '/repo/percent%2520.rs'],
		['a%20b.rs', '/repo/a%20b.rs'],
		['a b.rs', '/repo/a%20b.rs'],
		['\u00a0a.rs\u3000', '/repo/a.rs'],
		['İ.rs', '/repo/i\u0307.rs'],
		['ΟΣ', '/repo/ος'],
		['ΟΣ.rs', '/repo/οσ.rs'],
		['a.rs:12', '/repo/a.rs:12'],
	]
	for index in 0 .. collapsed.len {
		assert !should_render_local_link_label(&collapsed[index][0], &collapsed[index][1]), 'case ${index}: ${collapsed[index]}'
	}
	visible := [
		['parser implementation', '/repo/a.rs'],
		['a.rs', '/repo/ba.rs'],
		['src/a.rs', '/repo/not-src/a.rs'],
		['percent .rs', '/repo/percent%2520.rs'],
		['/repo', '/repo/dir/a.rs'],
		['file://bad:80/a', '/repo/a'],
		['label', 'file:///repo/%00a'],
	]
	for index in 0 .. visible.len {
		assert should_render_local_link_label(&visible[index][0], &visible[index][1])
	}
	whitespace_label := '\u2002\u0085'
	label_target := '/repo/a'
	assert !should_render_local_link_label(&whitespace_label, &label_target)
	empty_label := ''
	invalid_label_target := 'file:///repo/%00a'
	assert !should_render_local_link_label(&empty_label, &invalid_label_target)
}

fn test_cwd_display_preserves_roots_equal_paths_and_frontend_home() {
	cwd_text := '/repo/'
	cwd := std_path.Path.new(&cwd_text)
	child_target := '/repo/src/a.rs#L12C3'
	assert (render_local_link_target(&child_target, cwd) or { panic('display') }) == 'src/a.rs:12:3'
	equal_cwd_target := '/repo/'
	assert (render_local_link_target(&equal_cwd_target, cwd) or { panic('display') }) == '/repo/'
	sibling_target := '/repository/a'
	assert (render_local_link_target(&sibling_target, cwd) or { panic('display') }) == '/repository/a'
	home_display_target := '~/repo/a'
	assert (render_local_link_target(&home_display_target, cwd) or { panic('display') }) == '~/repo/a'
	relative_display_target := './src/../a'
	assert (render_local_link_target(&relative_display_target, cwd) or { panic('display') }) == './src/../a'
	root_text := '/'
	root := std_path.Path.new(&root_text)
	root_child_target := '/tmp/x'
	assert (render_local_link_target(&root_child_target, root) or { panic('display') }) == 'tmp/x'
	equal_root_target := '/'
	assert (render_local_link_target(&equal_root_target, root) or { panic('display') }) == '/'
	unc_root_text := '//'
	unc_root := std_path.Path.new(&unc_root_text)
	unc_child_target := '//server/share'
	assert (render_local_link_target(&unc_child_target, unc_root) or { panic('display') }) == '/server/share'
	windows_cwd_text := 'C:\\repo\\'
	windows_cwd := std_path.Path.new(&windows_cwd_text)
	windows_child_target := 'file:///C:/repo/a.rs#L7'
	assert (render_local_link_target(&windows_child_target, windows_cwd) or { panic('display') }) == 'a.rs:7'
	equal_windows_target := 'C:/repo'
	assert (render_local_link_target(&equal_windows_target, windows_cwd) or { panic('display') }) == 'C:/repo'
	drive_root_text := 'C:/'
	drive_root := std_path.Path.new(&drive_root_text)
	drive_child_target := 'C:/a.rs'
	assert (render_local_link_target(&drive_child_target, drive_root) or { panic('display') }) == 'C:/a.rs'
	unc_cwd_text := '\\\\server\\share'
	unc_cwd := std_path.Path.new(&unc_cwd_text)
	unc_display_target := 'file://server/share/a.rs'
	assert (render_local_link_target(&unc_display_target, unc_cwd) or { panic('display') }) == 'a.rs'
}

fn local_links_owned(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn test_repeated_borrows_preserve_heap_destinations_labels_paths_and_urls() {
	destination := local_links_owned('file:///C:/repo/percent%2520.rs?ignored=1#L12C3-L14C9')
	label := local_links_owned('percent%20.rs')
	cwd_text := local_links_owned('C:\\repo')
	cwd := std_path.Path.new(&cwd_text)
	for _ in 0 .. 2 {
		assert is_local_path_like_link(&destination)
		assert !should_render_local_link_label(&label, &destination)
		assert (render_local_link_target(&destination, cwd) or { panic('borrowed display') }) == 'percent%20.rs:12:3-14:9'
		assert cwd.to_string_lossy() == 'C:\\repo'
	}
	parsed := url.Url.parse(&destination) or { panic('borrowed URL') }
	for _ in 0 .. 2 {
		prefix := parsed.prefix(.after_path)
		path := codex_utils_path_uri.PathUri.parse(&prefix) or { panic('borrowed URI') }
		assert path.inferred_native_path_string() == 'C:\\repo\\percent%20.rs'
		fragment := parsed.fragment()
		assert fragment.has_value
		assert *fragment.value == 'L12C3-L14C9'
		assert parsed.to_string() == destination
	}
	encoded := local_links_owned('percent%2520+%20.rs')
	assert (urlencoding.decode(&encoded) or { panic('decode') }) == 'percent%20+ .rs'
	assert (urlencoding.decode(&encoded) or { panic('decode') }) == 'percent%20+ .rs'
	assert encoded == 'percent%2520+%20.rs'
	assert destination.contains('?ignored=1')
	assert label == 'percent%20.rs'
	assert cwd_text == 'C:\\repo'
}
