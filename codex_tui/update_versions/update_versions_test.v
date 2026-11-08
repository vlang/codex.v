module update_versions

fn test_extracts_version_from_latest_tag() {
	latest_tag_name := 'rust-v1.5.0'
	assert extract_version_from_latest_tag(&latest_tag_name) or { panic('failed to parse version') } == '1.5.0'
}

fn test_latest_tag_without_prefix_is_invalid() {
	latest_tag_name := 'v1.5.0'
	if _ := extract_version_from_latest_tag(&latest_tag_name) {
		assert false, 'tag without prefix must fail'
	} else {
		assert err.msg() == "Failed to parse latest tag name 'v1.5.0'"
	}
}

fn test_prerelease_version_is_not_considered_newer() {
	latest_beta := '0.11.0-beta.1'
	current_beta := '0.11.0'
	assert is_newer(&latest_beta, &current_beta) == none
	latest_rc := '1.0.0-rc.1'
	current_rc := '1.0.0'
	assert is_newer(&latest_rc, &current_rc) == none
}

fn test_plain_semver_comparisons_work() {
	previous_patch := '0.11.0'
	next_patch := '0.11.1'
	assert is_newer(&next_patch, &previous_patch) == ?bool(true)
	assert is_newer(&previous_patch, &next_patch) == ?bool(false)
	next_major := '1.0.0'
	previous_major := '0.9.9'
	assert is_newer(&next_major, &previous_major) == ?bool(true)
	assert is_newer(&previous_major, &next_major) == ?bool(false)
}

fn test_source_build_version_is_not_checked() {
	source := '0.0.0'
	release := '0.1.0'
	assert is_source_build_version(&source)
	assert !is_source_build_version(&release)
}

fn test_whitespace_is_ignored() {
	version := ' 1.2.3 \n'
	assert parse_version(&version) == ?Version(Version{ major: 1, minor: 2, patch: 3 })
	latest := ' 1.2.3 '
	current := '1.2.2'
	assert is_newer(&latest, &current) == ?bool(true)
}

fn test_u64_components_preserve_full_range_and_reject_overflow() {
	maximum := '18446744073709551615.18446744073709551615.18446744073709551615'
	assert parse_version(&maximum) == ?Version(Version{
		major: u64(18446744073709551615)
		minor: u64(18446744073709551615)
		patch: u64(18446744073709551615)
	})
	for version in [
		'18446744073709551616.0.0',
		'0.18446744073709551616.0',
		'0.0.18446744073709551616',
		'999999999999999999999999999999999999.0.0',
	] {
		assert parse_version(&version) == none
	}
	leading_zeroes := '00000000000000000000000018446744073709551615.000.00'
	assert parse_version(&leading_zeroes) == ?Version(Version{
		major: u64(18446744073709551615)
	})
}

fn test_component_signs_and_ascii_digit_syntax_match_rust() {
	positive := '+1.+02.+003'
	assert parse_version(&positive) == ?Version(Version{ major: 1, minor: 2, patch: 3 })
	positive_zero := '+0.+0.+0'
	assert is_source_build_version(&positive_zero)
	for version in [
		'-0.0.0',
		'0.-1.0',
		'0.0.-1',
		'+.0.0',
		'++.0.0',
		'1.+.0',
		'1.2.+',
		'1.2.3_0',
		'0x1.2.3',
		'1. 2.3',
		'١.2.3',
		'1.２.3',
	] {
		assert parse_version(&version) == none
	}
}

fn test_unicode_whitespace_is_trimmed_only_at_outer_boundaries() {
	for separator in unicode_whitespace.runes() {
		version := '${separator}1.2.3${separator}'
		assert parse_version(&version) == ?Version(Version{ major: 1, minor: 2, patch: 3 })
		internal := '1.${separator}2.3'
		assert parse_version(&internal) == none
	}
	for separator in ['\u0000', '\u180e', '\u200b', '\ufeff'] {
		version := '${separator}1.2.3${separator}'
		assert parse_version(&version) == none
	}
}

fn test_exactly_first_three_components_are_parsed() {
	for version in ['1.2.3.4', '1.2.3.', '1.2.3.beta', '1.2.3.18446744073709551616'] {
		assert parse_version(&version) == ?Version(Version{ major: 1, minor: 2, patch: 3 })
	}
	for version in ['', '1', '1.2', '1.2.', '.2.3', '1..3', '1.2.3-beta.4'] {
		assert parse_version(&version) == none
	}
	source := '0.0.0.extra'
	assert is_source_build_version(&source)
}

fn test_numeric_tuple_order_and_invalid_current_version() {
	previous_minor := '1.9.99'
	next_minor := '1.10.0'
	assert is_newer(&next_minor, &previous_minor) == ?bool(true)
	assert is_newer(&previous_minor, &next_minor) == ?bool(false)
	assert is_newer(&next_minor, &next_minor) == ?bool(false)
	maximum := '18446744073709551615.0.0'
	previous_major := '18446744073709551614.18446744073709551615.18446744073709551615'
	assert is_newer(&maximum, &previous_major) == ?bool(true)
	invalid_current := '1.10.0-beta'
	assert is_newer(&next_minor, &invalid_current) == none
}

fn test_tag_extraction_preserves_payload_and_exact_error_text() {
	for tag in ['rust-v', 'rust-v1.2.3-beta', 'rust-v 1.2.3 ', 'rust-vrust-v1.2.3'] {
		assert extract_version_from_latest_tag(&tag) or { panic(err) } == tag[6..]
	}
	for tag in ['v1.5.0', 'Rust-v1.2.3', ' rust-v1.2.3', "tag'\n雪"] {
		if _ := extract_version_from_latest_tag(&tag) {
			assert false, 'tag without exact prefix must fail'
		} else {
			assert err.msg() == "Failed to parse latest tag name '${tag}'"
		}
	}
}

fn test_borrowed_dynamic_owners_remain_reusable() {
	mut latest := ' +1.2.3.extra '
	mut current := '1.2.2'
	mut tag := 'rust-v1.2.3'
	mut source := '0.0.0.extra'
	$if ownership ? {
		latest = latest.to_owned()
		current = current.to_owned()
		tag = tag.to_owned()
		source = source.to_owned()
	}
	assert is_newer(&latest, &current) == ?bool(true)
	assert is_newer(&latest, &current) == ?bool(true)
	assert parse_version(&latest) == ?Version(Version{ major: 1, minor: 2, patch: 3 })
	first := extract_version_from_latest_tag(&tag) or { panic(err) }
	second := extract_version_from_latest_tag(&tag) or { panic(err) }
	assert first == '1.2.3'
	assert second == first
	assert is_source_build_version(&source)
	assert is_source_build_version(&source)
	assert latest == ' +1.2.3.extra '
	assert current == '1.2.2'
	assert tag == 'rust-v1.2.3'
	assert source == '0.0.0.extra'
}
