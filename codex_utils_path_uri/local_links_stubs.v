module codex_utils_path_uri

// STUB: utils/path-uri/src/lib.rs::with_normalized_windows_drive_letter folds
// the first nonempty drive URI segment to uppercase only without a UNC host.
// The borrowed URI stays usable; V owns the canonical returned string.
fn local_links_canonical_drive(uri &string) string {
	rest := (*uri)[7..]
	slash := rest.index('/') or { return uri.clone() }
	host := rest[..slash]
	if host.len > 0 && host != 'localhost' {
		return uri.clone()
	}
	mut drive_start := slash + 7
	for drive_start < uri.len && (*uri)[drive_start] == `/` {
		drive_start++
	}
	mut drive_end := drive_start
	for drive_end < uri.len && (*uri)[drive_end] != `/` {
		drive_end++
	}
	drive := (*uri)[drive_start..drive_end]
	if drive.len < 2 || !drive[0].is_letter() {
		return uri.clone()
	}
	if !(drive.len == 2 && drive[1] == `:`) && !(drive.len == 4 && drive[1] == `%`
		&& drive[2] == `3` && drive[3] in [`a`, `A`]) {
		return uri.clone()
	}
	return '${(*uri)[..drive_start]}${(drive[0] & u8(0xdf)).ascii_str()}${(*uri)[drive_start + 1..]}'
}
