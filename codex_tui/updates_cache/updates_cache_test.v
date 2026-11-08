module updates_cache

import os
import rand
import chrono
import codex_core
import serde_json
import std_path

fn cache_tempdir() string {
	path := os.join_path(os.temp_dir(), 'codex-updates-cache-${rand.uuid_v4()}')
	os.mkdir(path.clone()) or { panic(err) }
	return path
}

fn cache_config(home &string) codex_core.Config {
	return codex_core.ConfigBuilder.default().codex_home(home.clone()).build() or { panic(err) }
}

fn cache_read(config &codex_core.Config) VersionInfo {
	filename := version_filepath(config)
	path := std_path.Path.new(&filename)
	return read_version_info(&path) or { panic(err) }
}

// Source test: ConfigBuilder receives only codex_home; dismissal creates the
// absent file with an epoch timestamp and matching latest/dismissed version.
fn test_dismiss_version_creates_cache_file_when_missing() {
	codex_home := cache_tempdir()
	defer { os.rmdir_all(codex_home.clone()) or { panic(err) } }
	config := codex_core.ConfigBuilder.default().codex_home(codex_home.clone()).build() or {
		panic(err)
	}
	version_file := version_filepath(&config)
	borrowed_literal_1 := '999.0.0'
	dismiss_version(&config, &borrowed_literal_1) or { panic(err) }
	path := std_path.Path.new(&version_file)
	info := read_version_info(&path) or { panic(err) }
	assert info.last_checked_at == chrono.DateTimeUtc.unix_epoch()
	assert info.latest_version == '999.0.0'
	assert info.dismissed_version or { panic('missing dismissal') } == '999.0.0'
}

fn test_dismissal_preserves_latest_version_timestamp_and_replaces_previous_dismissal() {
	home := cache_tempdir()
	defer { os.rmdir_all(home.clone()) or { panic(err) } }
	config := cache_config(&home)
	filename := version_filepath(&config)
	os.write_file(filename.clone(), '{"latest_version":"2026.10.2","last_checked_at":"2026-10-02T08:45:00.123456Z","dismissed_version":"old"}') or { panic(err) }
	borrowed_literal_2 := 'dismiss-this'
	dismiss_version(&config, &borrowed_literal_2) or { panic(err) }
	info := cache_read(&config)
	assert info.latest_version == '2026.10.2'
	borrowed_literal_3 := '2026-10-02T08:45:00.123456Z'
	assert info.last_checked_at == chrono.DateTimeUtc.from_serde_string(&borrowed_literal_3) or { panic(err) }
	assert info.dismissed_version or { panic('missing dismissal') } == 'dismiss-this'
	bytes := os.read_file(filename.clone()) or { panic(err) }
	assert bytes == '{"latest_version":"2026.10.2","last_checked_at":"2026-10-02T08:45:00.123456Z","dismissed_version":"dismiss-this"}\n'
}

fn test_malformed_cache_uses_epoch_fallback_and_creates_nested_home() {
	root := cache_tempdir()
	defer { os.rmdir_all(root.clone()) or { panic(err) } }
	home := os.join_path(root.clone(), 'one', 'two')
	config := cache_config(&home)
	borrowed_literal_4 := 'first'
	dismiss_version(&config, &borrowed_literal_4) or { panic(err) }
	assert os.is_dir(home.clone())
	filename := version_filepath(&config)
	os.write_file(filename, '{ invalid JSON') or { panic(err) }
	borrowed_literal_5 := 'second'
	dismiss_version(&config, &borrowed_literal_5) or { panic(err) }
	info := cache_read(&config)
	assert info.latest_version == 'second'
	assert info.last_checked_at == chrono.DateTimeUtc.unix_epoch()
	assert info.dismissed_version or { panic('missing dismissal') } == 'second'
}

fn test_non_utf8_cache_is_a_read_error_and_dismissal_falls_back() {
	home := cache_tempdir()
	defer { os.rmdir_all(home.clone()) or { panic(err) } }
	config := cache_config(&home)
	filename := version_filepath(&config)
	os.write_file(filename.clone(), [u8(0xff), u8(0xfe)].bytestr()) or { panic(err) }
	path := std_path.Path.new(&filename)
	if _ := read_version_info(&path) {
		assert false
	} else {
		assert err.msg().contains('UTF-8')
	}
	borrowed_literal_6 := 'valid-version'
	dismiss_version(&config, &borrowed_literal_6) or { panic(err) }
	assert cache_read(&config).latest_version == 'valid-version'
}

fn test_directory_cache_path_propagates_write_error() {
	home := cache_tempdir()
	defer { os.rmdir_all(home.clone()) or { panic(err) } }
	config := cache_config(&home)
	filename := version_filepath(&config)
	os.mkdir(filename) or { panic(err) }
	borrowed_literal_7 := '1'
	if _ := dismiss_version(&config, &borrowed_literal_7) {
		assert false
	} else {
		assert err.msg().len > 0
	}
}

fn test_parent_file_propagates_create_directory_error() {
	root := cache_tempdir()
	defer { os.rmdir_all(root.clone()) or { panic(err) } }
	blocker := os.join_path(root.clone(), 'file')
	os.write_file(blocker.clone(), 'blocking parent') or { panic(err) }
	home := os.join_path(blocker, 'child')
	config := cache_config(&home)
	borrowed_literal_8 := '1'
	if _ := dismiss_version(&config, &borrowed_literal_8) {
		assert false
	} else {
		assert err.msg().len > 0
	}
}

fn test_missing_cache_read_propagates_error() {
	home := cache_tempdir()
	defer { os.rmdir_all(home.clone()) or { panic(err) } }
	config := cache_config(&home)
	filename := version_filepath(&config)
	path := std_path.Path.new(&filename)
	if _ := read_version_info(&path) {
		assert false
	} else {
		assert err.msg().len > 0
	}
}

fn test_missing_or_null_dismissal_defaults_and_unknown_fields_are_ignored() {
	for source in [
		'{"latest_version":"v","last_checked_at":"1970-01-01T00:00:00Z"}',
		'{"dismissed_version":null,"unknown":{"nested":[1,true]},"last_checked_at":"1970-01-01T00:00:00Z","latest_version":"v"}',
		'["v","1970-01-01T00:00:00Z"]',
		'["v","1970-01-01T00:00:00Z",null]',
	] {
		info := VersionInfo.deserialize_json(&source) or { panic(err) }
		assert info.latest_version == 'v'
		assert info.last_checked_at == chrono.DateTimeUtc.unix_epoch()
		assert info.dismissed_version == none
		assert serde_json.to_string(&info) or { panic(err) } == '{"latest_version":"v","last_checked_at":"1970-01-01T00:00:00Z","dismissed_version":null}'
	}
}

fn test_serde_rejects_missing_duplicate_and_wrong_typed_fields() {
	for source in [
		'{}',
		'{"latest_version":"v"}',
		'{"last_checked_at":"1970-01-01T00:00:00Z"}',
		'{"latest_version":null,"last_checked_at":"1970-01-01T00:00:00Z"}',
		'{"latest_version":"v","last_checked_at":0}',
		'{"latest_version":"v","last_checked_at":"1970-01-01T00:00:00Z","dismissed_version":7}',
		'{"latest_version":"v","latest_version":"x","last_checked_at":"1970-01-01T00:00:00Z"}',
		'{"latest_version":"v","last_checked_at":"1970-01-01T00:00:00Z","last_checked_at":"1970-01-01T00:00:00Z"}',
		'{"latest_version":"v","last_checked_at":"1970-01-01T00:00:00Z","dismissed_version":null,"dismissed_version":"v"}',
		'{"latest_version":"v","latest\\u005fversion":"x","last_checked_at":"1970-01-01T00:00:00Z"}',
		'[]',
		'["v"]',
		'["v","1970-01-01T00:00:00Z",null,4]',
		'{"latest_version":"v","last_checked_at":"1970-01-01T00:00:00Z",}',
		'{"latest_version":"v","last_checked_at":"1970-01-01T00:00:00Z"} false',
	] {
		if _ := VersionInfo.deserialize_json(&source) {
			assert false, source
		} else {
			assert err.msg().len > 0
		}
	}
}

fn test_serde_escaped_values_and_sequence_serialization_round_trip() {
	source := '["v\\\"\\n雪","2026-10-02T03:00:00+03:00","\\t\\\\"]'
	info := VersionInfo.deserialize_json(&source) or { panic(err) }
	assert info.latest_version == 'v"\n雪'
	assert info.dismissed_version or { panic('missing dismissal') } == '\t\\'
	encoded := serde_json.to_string(&info) or { panic(err) }
	decoded := VersionInfo.deserialize_json(&encoded) or { panic(err) }
	assert decoded.latest_version == info.latest_version
	assert decoded.dismissed_version == info.dismissed_version
	assert decoded.last_checked_at == info.last_checked_at
}

fn test_unknown_fields_are_skipped_without_number_or_nesting_limits() {
	unknown := '['.repeat(512) + '{"huge":1e999999,"code_unit":"\\ud800"}' + ']'.repeat(512)
	source := '{"latest_version":"v","future":' + unknown + ',"last_checked_at":"1970-01-01T00:00:00Z"}'
	info := VersionInfo.deserialize_json(&source) or { panic(err) }
	assert info.latest_version == 'v'
	assert info.last_checked_at == chrono.DateTimeUtc.unix_epoch()
	for unknown_invalid in ['01', '[1,]', '{"x":}', '1e+', '"\\x"'] {
		invalid := '{"latest_version":"v","future":' + unknown_invalid + ',"last_checked_at":"1970-01-01T00:00:00Z"}'
		if _ := VersionInfo.deserialize_json(&invalid) {
			assert false, invalid
		} else {
			assert err.msg().len > 0
		}
	}
}

fn test_timestamp_offsets_fractions_relaxed_syntax_and_leap_seconds() {
	inputs := [
		'1970-01-01T00:00:00Z',
		'1970-01-01T03:30:00+03:30',
		'1969-12-31T22:00:00-0200',
		'1970-1-1 0:0:0 UTC',
		'1970-  1-1t0:  0:0z',
		'1970-01-01T00:00:00.1Z',
		'1970-01-01T00:00:00.000001Z',
		'1970-01-01T00:00:00.123456789999Z',
		'2016-12-31T23:59:60.1Z',
		'2017-01-01T00:59:60+01:00',
		'1970-01-01T00:00:00−00:00',
		'\u20031970-1-1 0:0:0 utc\u3000',
	]
	expected := [
		'1970-01-01T00:00:00Z',
		'1970-01-01T00:00:00Z',
		'1970-01-01T00:00:00Z',
		'1970-01-01T00:00:00Z',
		'1970-01-01T00:00:00Z',
		'1970-01-01T00:00:00.100Z',
		'1970-01-01T00:00:00.000001Z',
		'1970-01-01T00:00:00.123456789Z',
		'2016-12-31T23:59:60.100Z',
		'2016-12-31T23:59:60Z',
		'1970-01-01T00:00:00Z',
		'1970-01-01T00:00:00Z',
	]
	for i, source in inputs {
		timestamp := chrono.DateTimeUtc.from_serde_string(&source) or { panic(err) }
		assert timestamp.to_serde_string() or { panic(err) } == expected[i]
	}
}

fn test_timestamp_extended_years_and_calendar_boundaries_round_trip() {
	for source in ['0000-02-29T00:00:00Z', '-0001-12-31T23:59:59Z', '-0400-02-29T00:00:00Z',
		'+10000-01-01T00:00:00Z', '-262143-01-01T00:00:00Z', '+262142-12-31T23:59:59Z',
		'1900-02-28T23:59:59Z', '2000-02-29T00:00:00Z'] {
		timestamp := chrono.DateTimeUtc.from_serde_string(&source) or { panic(err) }
		assert timestamp.to_serde_string() or { panic(err) } == source
	}
}

fn test_timestamp_rejects_invalid_calendar_time_offset_and_trailing_data() {
	for source in ['2023-02-29T00:00:00Z', '2026-04-31T00:00:00Z', '2026-00-01T00:00:00Z',
		'2026-01-00T00:00:00Z', '2026-01-01T24:00:00Z', '2026-01-01T00:60:00Z', '2026-01-01T00:00:61Z',
		'2026-01-01T00:00:00.Z', '2026-01-01T00:00:00+24:00', '2026-01-01T00:00:00+00:60',
		'2026-01-01T00:00:00+00', '2026-01-01T00:00:00', '2026-01-01T00:00:00Zbad',
		'10000-01-01T00:00:00Z', '-262144-01-01T00:00:00Z', '+262143-01-01T00:00:00Z',
		'-262143-01-01T00:00:00+01:00', '+999999999999999999999-01-01T00:00:00Z'] {
		if _ := chrono.DateTimeUtc.from_serde_string(&source) {
			assert false, source
		} else {
			assert err.msg().len > 0
		}
	}
}

fn test_borrowed_config_version_path_and_json_owners_remain_reusable() {
	home := cache_tempdir()
	defer { os.rmdir_all(home.clone()) or { panic(err) } }
	mut version := 'heap-owned-version'
	mut source := '{"latest_version":"heap-cache","last_checked_at":"2026-10-02T00:00:00Z","dismissed_version":"before"}'
	$if ownership ? {
		version = version.to_owned()
		source = source.to_owned()
	}
	config := cache_config(&home)
	first_path := version_filepath(&config)
	second_path := version_filepath(&config)
	assert first_path == second_path
	for _ in 0 .. 2 {
		info := VersionInfo.deserialize_json(&source) or { panic(err) }
		cloned := info.clone()
		assert serde_json.to_string(&info) or { panic(err) } == serde_json.to_string(&cloned) or { panic(err) }
		dismiss_version(&config, &version) or { panic(err) }
		path := std_path.Path.new(&first_path)
		assert read_version_info(&path) or { panic(err) }.latest_version == version
		assert read_version_info(&path) or { panic(err) }.dismissed_version or { panic('missing dismissal') } == version
	}
	assert config.codex_home == home
	assert version == 'heap-owned-version'
	assert source.contains('heap-cache')
	assert first_path.ends_with('version.json')
}

fn test_unix_home_keeps_literal_backslash_path_components() {
	$if windows {
		return
	}
	root := cache_tempdir()
	defer { os.rmdir_all(root.clone()) or { panic(err) } }
	home := os.join_path_single(root.clone(), 'literal\\home')
	config := cache_config(&home)
	borrowed_literal_9 := '1'
	dismiss_version(&config, &borrowed_literal_9) or { panic(err) }
	assert os.is_dir(home.clone())
	assert cache_read(&config).latest_version == '1'
}
