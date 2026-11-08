module update_versions

// Rust str::trim uses Unicode White_Space, including non-ASCII separators.
const unicode_whitespace = '\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000'

// V has no optional tuple type. These allocation-free fields retain Rust's
// (u64, u64, u64) representation and lexicographic comparison order.
struct Version {
	major u64
	minor u64
	patch u64
}

// V exposes these functions publicly because it has no Rust pub(crate).
pub fn is_newer(latest &string, current &string) ?bool {
	latest_version := parse_version(latest) or { return none }
	current_version := parse_version(current) or { return none }
	if latest_version.major != current_version.major {
		return latest_version.major > current_version.major
	}
	if latest_version.minor != current_version.minor {
		return latest_version.minor > current_version.minor
	}
	return latest_version.patch > current_version.patch
}

pub fn extract_version_from_latest_tag(latest_tag_name &string) !string {
	if latest_tag_name.starts_with('rust-v') {
		// The owned substring matches Rust's str::to_owned boundary.
		return (*latest_tag_name)[6..]
	}
	return error("Failed to parse latest tag name '${*latest_tag_name}'")
}

pub fn is_source_build_version(version &string) bool {
	return parse_version(version) == ?Version(Version{})
}

fn parse_version(v &string) ?Version {
	// V's trim returns an owned temporary where Rust borrows a trimmed slice.
	trimmed := v.trim(unicode_whitespace)
	mut start := 0
	mut components := [3]u64{}
	for index in 0 .. 3 {
		mut end := start
		for end < trimmed.len && trimmed[end] != `.` {
			end++
		}
		components[index] = parse_version_component(&trimmed, start, end) or { return none }
		if index < 2 {
			if end == trimmed.len {
				return none
			}
			start = end + 1
		}
	}
	return Version{
		major: components[0]
		minor: components[1]
		patch: components[2]
	}
}

// Equivalent to str::parse::<u64>: one optional leading '+', ASCII decimal
// digits, and checked arithmetic. Component ranges avoid allocating slices.
fn parse_version_component(value &string, start int, end int) ?u64 {
	mut index := start
	if index < end && (*value)[index] == `+` {
		index++
	}
	if index == end {
		return none
	}
	mut result := u64(0)
	for index < end {
		byte := (*value)[index]
		if byte < `0` || byte > `9` {
			return none
		}
		digit := u64(byte - `0`)
		if result > (u64(18446744073709551615) - digit) / 10 {
			return none
		}
		result = result * 10 + digit
		index++
	}
	return result
}
